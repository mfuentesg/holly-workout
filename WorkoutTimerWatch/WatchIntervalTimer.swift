import Observation
import UserNotifications
import WatchKit

enum Phase {
    case work, rest

    var title: String { self == .work ? "WORK" : "REST" }
}

/// Strong, distinct patterns so cues can be felt mid-exercise. A single tap is
/// easy to miss with a moving arm, so each cue is a burst of heavy haptics.
enum Haptics {
    enum Cue {
        /// Work starts: three firm "go" pulses.
        case go
        /// Rest starts: two long, heavy pulses.
        case rest
        /// Last 3 seconds: one firm tap per second.
        case countdown
    }

    static func play(_ cue: Cue) {
        let pattern: [(WKHapticType, Double)]
        switch cue {
        case .go: pattern = [(.start, 0), (.notification, 0.25), (.start, 0.5), (.notification, 0.75)]
        case .rest: pattern = [(.stop, 0), (.failure, 0.4), (.stop, 0.8)]
        case .countdown: pattern = [(.notification, 0)]
        }
        for (type, delay) in pattern {
            if delay == 0 {
                WKInterfaceDevice.current().play(type)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    WKInterfaceDevice.current().play(type)
                }
            }
        }
    }
}

/// Infinite work/rest loop. A background runtime session keeps the app alive
/// with the wrist down; queued notifications cover the cues if it is suspended.
/// Time comes from wall-clock deadlines, so late ticks never drift.
@MainActor
@Observable
final class WatchIntervalTimer: NSObject {
    static let shared = WatchIntervalTimer()

    var workSeconds: Int = 45
    var restSeconds: Int = 15

    private(set) var phase: Phase = .work
    private(set) var round = 1
    private(set) var remaining: Double = 45
    private(set) var isRunning = false
    private(set) var isActive = false

    private var runtime: WKExtendedRuntimeSession?
    private var phaseEnd = Date()
    private var ticker: Timer?
    private var lastBeepSecond: Int?

    var phaseDuration: Double { Double(phase == .work ? workSeconds : restSeconds) }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Connectivity.shared.onCommand = { [weak self] c in
            guard let self else { return }
            Task { await self.apply(c) }
        }
    }

    /// Seconds since the loop began, so the iPhone can seek to the same point.
    var elapsed: Double {
        let rem = isRunning ? max(0, phaseEnd.timeIntervalSinceNow) : remaining
        let cycle = Double(workSeconds + restSeconds)
        return Double(round - 1) * cycle + (phase == .work ? 0 : Double(workSeconds)) + phaseDuration - rem
    }

    private func seek(to elapsed: Double) {
        let pos = loopPosition(elapsed: elapsed, work: workSeconds, rest: restSeconds)
        phase = pos.isWork ? .work : .rest
        round = pos.round
        remaining = pos.remaining
        lastBeepSecond = nil
        if isRunning {
            phaseEnd = Date().addingTimeInterval(remaining)
            scheduleCues()
        }
    }

    private func persist() {
        LoopStore.save(running: isRunning, epoch: Date().timeIntervalSince1970 - elapsed, elapsed: elapsed,
                       work: workSeconds, rest: restSeconds)
    }

    private func broadcast(_ kind: String) {
        Connectivity.shared.send(SyncCommand(kind: kind, work: workSeconds, rest: restSeconds, elapsed: elapsed))
    }

    /// A command from the iPhone: mirror it without echoing it back.
    func apply(_ c: SyncCommand) async {
        switch c.kind {
        case "run":
            workSeconds = c.work
            restSeconds = c.rest
            UserDefaults.standard.set(c.work, forKey: "workSeconds")
            UserDefaults.standard.set(c.rest, forKey: "restSeconds")
            if !isActive {
                await begin(position: { c.currentElapsed() }, broadcast: false)
            } else {
                seek(to: c.currentElapsed())
                if !isRunning { resume() } else { persist() }
            }
        case "pause":
            if !isActive {
                await begin(pausedAt: c.elapsed, broadcast: false)
            } else {
                if isRunning { toggle(broadcast: false) }
                seek(to: c.elapsed)
                persist()
            }
        case "stop":
            LoopStore.clear()
            if isActive { end(broadcast: false) }
        default: break
        }
    }

    // MARK: Session lifecycle

    /// Brings back a countdown that was running when the app was last closed.
    func restoreIfNeeded() async {
        guard !isActive, let saved = LoopStore.load() else { return }
        workSeconds = saved.work
        restSeconds = saved.rest
        if saved.running {
            await begin(position: { Date().timeIntervalSince1970 - saved.epoch }, broadcast: false)
        } else {
            await begin(pausedAt: saved.elapsed, broadcast: false)
        }
    }

    func begin(position: (() -> Double)? = nil, pausedAt: Double? = nil, broadcast shouldBroadcast: Bool = true) async {
        guard !isActive else { return }
        // Claim the session before any await so a second Start can't slip in.
        isActive = true
        seek(to: position?() ?? 0)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        runtime = session

        // Setup above can take seconds; take the position again only now.
        if let pausedAt {
            seek(to: pausedAt)
            persist()
        } else {
            seek(to: position?() ?? 0)
            resume()
        }
        if shouldBroadcast { broadcast("run") }
    }

    func end(broadcast shouldBroadcast: Bool = true) {
        if shouldBroadcast { broadcast("stop") }
        isActive = false
        stopTicker()
        LoopStore.clear()
        runtime?.invalidate()
        runtime = nil
    }

    func toggle(broadcast shouldBroadcast: Bool = true) {
        if isRunning {
            remaining = max(0, phaseEnd.timeIntervalSinceNow)
            stopTicker()
            persist()
            if shouldBroadcast { broadcast("pause") }
        } else {
            resume()
            if shouldBroadcast { broadcast("run") }
        }
    }

    // MARK: Ticking

    private func resume() {
        phaseEnd = Date().addingTimeInterval(remaining)
        isRunning = true
        persist()
        scheduleCues()
        Haptics.play(.go)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        scheduleCues()
    }

    private func tick() {
        var left = phaseEnd.timeIntervalSinceNow
        var changed = false
        while left <= 0 {
            advance()
            changed = true
            left = phaseEnd.timeIntervalSinceNow
        }
        remaining = left
        if changed { scheduleCues() }

        let whole = Int(left.rounded(.up))
        if whole <= 3, whole != lastBeepSecond {
            lastBeepSecond = whole
            Haptics.play(.countdown)
        }
    }

    private func advance() {
        if phase == .work {
            phase = .rest
            phaseEnd = phaseEnd.addingTimeInterval(Double(restSeconds))
            Haptics.play(.rest)
        } else {
            phase = .work
            round += 1
            phaseEnd = phaseEnd.addingTimeInterval(Double(workSeconds))
            Haptics.play(.go)
        }
        lastBeepSecond = nil
    }
}

extension WatchIntervalTimer: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}

extension WatchIntervalTimer: UNUserNotificationCenterDelegate {
    /// In the foreground the app plays its own haptics, so don't double up.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}

extension WatchIntervalTimer {
    /// Haptics from `WKInterfaceDevice` are dropped once the app leaves the
    /// foreground, but notifications still tap the wrist. Queue the next ~15
    /// minutes of phase changes plus 3-2-1 ticks for the nearest few; iOS caps
    /// pending notifications at 64, and this refills on every phase change.
    fileprivate func scheduleCues() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        guard isRunning else { return }

        func request(after delay: Double, title: String, body: String) {
            guard delay > 0.5 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        }

        var boundary = phaseEnd.timeIntervalSinceNow
        var nextIsWork = phase == .rest
        var nextRound = phase == .rest ? round + 1 : round
        for i in 0..<30 {
            if i < 6 {
                for s in 1...3 { request(after: boundary - Double(s), title: "\(s)", body: nextIsWork ? "Work next" : "Rest next") }
            }
            request(after: boundary, title: nextIsWork ? "WORK" : "REST", body: "Round \(nextRound)")
            boundary += Double(nextIsWork ? workSeconds : restSeconds)
            if !nextIsWork { nextRound += 1 }
            nextIsWork.toggle()
        }
    }
}
