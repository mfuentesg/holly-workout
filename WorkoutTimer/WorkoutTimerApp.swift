import SwiftUI

@main
struct WorkoutTimerApp: App {
    init() {
        _ = IntervalTimer.shared
        Connectivity.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
