import SwiftUI

@main
struct HollyWatchApp: App {
    init() {
        _ = WatchIntervalTimer.shared
        Connectivity.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
