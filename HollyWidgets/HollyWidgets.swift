import ActivityKit
import SwiftUI
import WidgetKit

@main
struct HollyWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.black.opacity(0.8))
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(s.isWork ? "WORK" : "REST").font(.title3.weight(.heavy)).foregroundStyle(tint(s))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(s, stale).font(.system(size: 40, weight: .bold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Round \(s.round)").foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(s.isWork ? "WORK" : "REST").font(.headline.weight(.heavy)).foregroundStyle(tint(s))
            } compactTrailing: {
                countdown(s, stale).font(.headline).frame(width: 52)
            } minimal: {
                Image(systemName: "bolt.fill").foregroundStyle(tint(s))
            }
        }
        .supplementalActivityFamilies([.small])
    }

    private func tint(_ s: WorkoutActivityAttributes.ContentState) -> Color { s.isWork ? .green : .orange }

    private func countdown(_ s: WorkoutActivityAttributes.ContentState, _ stale: Bool) -> some View { CountdownText(state: s, stale: stale) }
}

private struct CountdownText: View {
    let state: WorkoutActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if stale {
            Text("Stopped")
        } else if state.isPaused {
            Text("\(state.secondsLeft)").monospacedDigit()
        } else {
            Text(timerInterval: Date.now...max(state.phaseEnd, Date.now.addingTimeInterval(1)), countsDown: true)
                .monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

/// Lock screen card on iPhone; the `.small` family is what Apple Watch shows in the Smart Stack.
private struct WorkoutActivityView: View {
    @Environment(\.activityFamily) private var family
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    private var tint: Color { state.isWork ? .green : .orange }

    var body: some View {
        switch family {
        case .small:
            VStack(spacing: 0) {
                Text(state.isWork ? "WORK" : "REST")
                    .font(.headline.weight(.heavy)).foregroundStyle(tint)
                CountdownText(state: state, stale: isStale)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("Round \(state.round)").font(.caption2).foregroundStyle(.secondary)
            }
        default:
            HStack {
                VStack(alignment: .leading) {
                    Text(state.isWork ? "WORK" : "REST")
                        .font(.title2.weight(.heavy)).foregroundStyle(tint)
                    Text("Round \(state.round)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                CountdownText(state: state, stale: isStale).font(.system(size: 56, weight: .bold, design: .rounded))
            }
            .padding()
        }
    }
}
