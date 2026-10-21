import Foundation
import WatchConnectivity

/// One command applied identically on both devices. `elapsed` is how far into
/// the infinite loop the workout is, so each side can seek to the same point.
struct SyncCommand {
    var kind: String            // "run", "pause" or "stop"
    var work: Int
    var rest: Int
    var elapsed: Double
    var sentAt: TimeInterval = Date().timeIntervalSince1970
    /// Orders commands across devices without trusting either clock: every sender
    /// stamps above anything it has already seen.
    var stamp: TimeInterval = 0

    var receivedAt = Date()
    var viaContext = false

    /// The loop position now. A live message is aged by this device's own stopwatch
    /// since it arrived, so the two clocks never have to agree; a saved context may
    /// have waited for ages, so the sender's timestamp is all there is to age it by.
    func currentElapsed() -> Double {
        if kind != "run" { return elapsed }
        let age = viaContext ? max(0, Date().timeIntervalSince1970 - sentAt) : Date().timeIntervalSince(receivedAt)
        return elapsed + age
    }

    var dictionary: [String: Any] {
        ["kind": kind, "work": work, "rest": rest, "elapsed": elapsed, "sentAt": sentAt, "stamp": stamp]
    }

    init(kind: String, work: Int, rest: Int, elapsed: Double) {
        self.kind = kind; self.work = work; self.rest = rest; self.elapsed = elapsed
    }

    init?(_ d: [String: Any]) {
        guard let kind = d["kind"] as? String, let work = d["work"] as? Int,
              let rest = d["rest"] as? Int, let elapsed = d["elapsed"] as? Double,
              let sentAt = d["sentAt"] as? TimeInterval else { return nil }
        self.init(kind: kind, work: work, rest: rest, elapsed: elapsed)
        self.sentAt = sentAt
        self.stamp = d["stamp"] as? TimeInterval ?? sentAt
    }
}

/// Position in the work/rest loop for a given elapsed time.
func loopPosition(elapsed: Double, work: Int, rest: Int) -> (isWork: Bool, round: Int, remaining: Double) {
    let cycle = Double(work + rest)
    let e = max(0, elapsed)
    let k = (e / cycle).rounded(.down)
    let w = e - k * cycle
    return w < Double(work) ? (true, Int(k) + 1, Double(work) - w) : (false, Int(k) + 1, cycle - w)
}

/// The loop as it was when the app last changed it, so a relaunch can rejoin it.
enum LoopStore {
    struct Saved {
        var running: Bool
        var epoch: Double       // wall-clock start of the loop (running)
        var elapsed: Double     // position in the loop (paused)
        var work: Int
        var rest: Int
    }

    static func save(running: Bool, epoch: Double, elapsed: Double, work: Int, rest: Int) {
        let d = UserDefaults.standard
        d.set(true, forKey: "loop.active")
        d.set(running, forKey: "loop.running")
        d.set(epoch, forKey: "loop.epoch")
        d.set(elapsed, forKey: "loop.elapsed")
        d.set(work, forKey: "loop.work")
        d.set(rest, forKey: "loop.rest")
    }

    static func load() -> Saved? {
        let d = UserDefaults.standard
        guard d.bool(forKey: "loop.active") else { return nil }
        let saved = Saved(running: d.bool(forKey: "loop.running"), epoch: d.double(forKey: "loop.epoch"),
                          elapsed: d.double(forKey: "loop.elapsed"), work: d.integer(forKey: "loop.work"),
                          rest: d.integer(forKey: "loop.rest"))
        guard saved.work > 0, saved.rest > 0 else { return nil }
        if saved.running, Date().timeIntervalSince1970 - saved.epoch > 7200 { clear(); return nil }
        return saved
    }

    static func clear() { UserDefaults.standard.set(false, forKey: "loop.active") }
}

@MainActor
final class Connectivity: NSObject {
    static let shared = Connectivity()

    var onCommand: ((SyncCommand) -> Void)?
    /// Timestamp of the newest change either device has made. Kept across launches so an
    /// old saved context can never override something this device did more recently.
    private var lastHandled: TimeInterval {
        get { UserDefaults.standard.double(forKey: "sync.stamp") }
        set { UserDefaults.standard.set(newValue, forKey: "sync.stamp") }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: SyncCommand) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var command = command
        command.stamp = max(command.sentAt, lastHandled + 0.001)
        lastHandled = command.stamp
        if session.isReachable {
            session.sendMessage(command.dictionary, replyHandler: nil, errorHandler: nil)
        }
        // Also leave it as the latest state for a counterpart that isn't running yet.
        try? session.updateApplicationContext(command.dictionary)
    }

    /// Re-reads the other device's latest state, e.g. when coming back to the foreground.
    func reconcile() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        receive(WCSession.default.receivedApplicationContext, viaContext: true)
    }

    fileprivate func receive(_ dictionary: [String: Any], viaContext: Bool) {
        guard var command = SyncCommand(dictionary), command.stamp > lastHandled else { return }
        command.viaContext = viaContext
        guard command.kind != "run" || !viaContext || Date().timeIntervalSince1970 - command.sentAt < 7200 else { return }
        lastHandled = command.stamp
        onCommand?(command)
    }
}

extension Connectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.receive(context, viaContext: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message, viaContext: false) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext, viaContext: true) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
