import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isWork: Bool
        var round: Int
        /// When the current phase ends; the system counts down to it on its own.
        var phaseEnd: Date
        var isPaused: Bool
        var secondsLeft: Int
    }
}
