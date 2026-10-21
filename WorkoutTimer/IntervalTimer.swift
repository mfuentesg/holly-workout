import ActivityKit
import Observation
import UIKit

enum Phase {
    case work, rest

    var title: String { self == .work ? "WORK" : "REST" }
}

/// Infinite work/rest loop. Time is derived from wall-clock deadlines, so
/// ticks that arrive late never make the timer drift.
@MainActor
@Observable
final class IntervalTimer {
    static let shared = IntervalTimer()

    var workSeconds: Int = 45
    var restSeconds: Int = 15

    private(set) var phase: Phase = .work
    private(set) var round = 1
    private(set) var remaining: Double = 45
    private(set) var isRunning = false

    private var phaseEnd = Date()
    private var ticker: Timer?
    private var lastBeepSecond: Int?
    private var activity: Activity<WorkoutActivityAttributes>?

    var phaseDuration: Double { Double(phase == .work ? workSeconds : restSeconds) }
    var progress: Double { 1 - remaining / phaseDuration }
    var hasStarted: Bool { isRunning || remaining != Double(workSeconds) || phase != .work || round != 1 }

    private init() {
        Connectivity.shared.onCommand = { [weak self] in self?.apply($0) }
        // A previous run that was killed leaves its Live Activity behind.
        for stale in Activity<WorkoutActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        restore()
    }

    /// Rejoins the loop this app (or the watch) had going when it was last closed.
    private func restore() {
        guard let saved = LoopStore.load() else { return }
        workSeconds = saved.work
        restSeconds = saved.rest
        UserDefaults.standard.set(saved.work, forKey: "workSeconds")
        UserDefaults.standard.set(saved.rest, forKey: "restSeconds")
        if saved.running {
            seek(to: Date().timeIntervalSince1970 - saved.epoch)
            start(broadcast: false)
        } else {
            seek(to: saved.elapsed)
        }
    }

    private func persist() {
        if isRunning {
            LoopStore.save(running: true, epoch: Date().timeIntervalSince1970 - elapsed, elapsed: elapsed, work: workSeconds, rest: restSeconds)
        } else if hasStarted {
            LoopStore.save(running: false, epoch: 0, elapsed: elapsed, work: workSeconds, rest: restSeconds)
        } else {
            LoopStore.clear()
        }
    }

    func toggle() { isRunning ? pause() : start() }

    /// Seconds since the loop began, so the other device can seek to the same point.
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
        if isRunning { phaseEnd = Date().addingTimeInterval(remaining) }
    }

    private func broadcast(_ kind: String) {
        Connectivity.shared.send(SyncCommand(kind: kind, work: workSeconds, rest: restSeconds, elapsed: elapsed))
    }

    /// A command from the watch: mirror it without echoing it back.
    func apply(_ c: SyncCommand) {
        switch c.kind {
        case "run":
            workSeconds = c.work
            restSeconds = c.rest
            UserDefaults.standard.set(c.work, forKey: "workSeconds")
            UserDefaults.standard.set(c.rest, forKey: "restSeconds")
            seek(to: c.currentElapsed())
            if isRunning { pushActivity(); persist() } else { start(broadcast: false) }
        case "pause":
            if isRunning { pause(broadcast: false) }
            seek(to: c.elapsed)
            pushActivity()
            persist()
        case "stop":
            reset(broadcast: false)
        default: break
        }
    }

    func start(broadcast shouldBroadcast: Bool = true) {
        guard !isRunning else { return }
        phaseEnd = Date().addingTimeInterval(remaining)
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        Cues.shared.activate()
        pushActivity()
        persist()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if shouldBroadcast { broadcast("run") }
    }

    func pause(broadcast shouldBroadcast: Bool = true) {
        guard isRunning else { return }
        remaining = max(0, phaseEnd.timeIntervalSinceNow)
        stopTicker()
        pushActivity()
        persist()
        if shouldBroadcast { broadcast("pause") }
    }

    func reset(broadcast shouldBroadcast: Bool = true) {
        if shouldBroadcast { broadcast("stop") }
        stopTicker()
        endActivity()
        Cues.shared.deactivate()
        phase = .work
        round = 1
        remaining = Double(workSeconds)
        lastBeepSecond = nil
        LoopStore.clear()
    }

    /// Call when durations are edited while idle.
    func applySettings() {
        if !hasStarted { remaining = Double(workSeconds) }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
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
        if changed { pushActivity() }

        // 3-2-1 countdown beeps
        let whole = Int(left.rounded(.up))
        if whole <= 3, whole != lastBeepSecond {
            lastBeepSecond = whole
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func advance() {
        if phase == .work {
            phase = .rest
            phaseEnd = phaseEnd.addingTimeInterval(Double(restSeconds))
        } else {
            phase = .work
            round += 1
            phaseEnd = phaseEnd.addingTimeInterval(Double(workSeconds))
        }
        lastBeepSecond = nil
        UINotificationFeedbackGenerator().notificationOccurred(phase == .work ? .success : .warning)
    }

    // MARK: Live Activity (lock screen, Dynamic Island, Apple Watch Smart Stack)

    private func pushActivity() {
        let state = WorkoutActivityAttributes.ContentState(
            isWork: phase == .work,
            round: round,
            phaseEnd: isRunning ? phaseEnd : Date().addingTimeInterval(remaining),
            isPaused: !isRunning,
            secondsLeft: Int(remaining.rounded(.up)))
        // If the app dies the countdown can't advance; going stale lets the card say so.
        let content = ActivityContent(state: state, staleDate: isRunning ? phaseEnd.addingTimeInterval(3) : nil)
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: WorkoutActivityAttributes(), content: content)
        }
    }

    private func endActivity() {
        let current = activity
        activity = nil
        Task { await current?.end(nil, dismissalPolicy: .immediate) }
    }
}
