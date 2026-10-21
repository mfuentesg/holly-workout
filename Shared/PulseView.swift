import SwiftUI

/// A heartbeat: the core thumps and a ripple expands at every second boundary.
struct PulseView: View {
    let remaining: Double
    let tint: Color
    let running: Bool
    /// Outlines around the discs; the watch draws the pulse as solid colour only.
    var showsRing = true

    var body: some View {
        let frac = running ? remaining - remaining.rounded(.down) : 1
        let thump = pow(frac, 6)
        ZStack {
            if showsRing {
                Circle()
                    .stroke(tint, lineWidth: 3)
                    .scaleEffect(1 + 0.4 * (1 - frac))
                    .opacity(running ? 0.6 * frac : 0)
                Circle()
                    .fill(tint.opacity(0.22))
                    .scaleEffect(1 + 0.07 * thump)
                Circle()
                    .stroke(tint, lineWidth: 4)
                    .scaleEffect(1 + 0.07 * thump)
            } else {
                Circle()
                    .fill(tint.opacity(running ? 0.35 * frac : 0))
                    .scaleEffect(1 + 0.4 * (1 - frac))
                Circle()
                    .fill(tint.opacity(0.3 + 0.2 * thump))
                    .scaleEffect(1 + 0.1 * thump)
            }
        }
        .scaleEffect(0.75)
    }
}
