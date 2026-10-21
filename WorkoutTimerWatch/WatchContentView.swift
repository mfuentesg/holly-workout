import SwiftUI

struct WatchContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer = WatchIntervalTimer.shared
    @AppStorage("workSeconds") private var work = 45
    @AppStorage("restSeconds") private var rest = 15

    private var tint: Color { timer.phase == .work ? .green : .orange }

    var body: some View {
        Group {
            if timer.isActive { running } else { idle }
        }
        .task { await timer.restoreIfNeeded() }
        .onChange(of: scenePhase) { if scenePhase == .active { Connectivity.shared.reconcile() } }
    }

    private var idle: some View {
        ScrollView {
            VStack(spacing: 10) {
                adjuster("WORK", value: $work, color: .green)
                adjuster("REST", value: $rest, color: .orange)
                Button {
                    timer.workSeconds = work
                    timer.restSeconds = rest
                    Task { await timer.begin() }
                } label: {
                    Text("START")
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func adjuster(_ label: String, value: Binding<Int>, color: Color) -> some View {
        HStack(spacing: 6) {
            roundButton("minus", color: color) { value.wrappedValue = max(5, value.wrappedValue - 5) }
            VStack(spacing: 0) {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(color)
                Text("\(value.wrappedValue)s")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            roundButton("plus", color: color) { value.wrappedValue = min(300, value.wrappedValue + 5) }
        }
    }

    private func roundButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .background(color.opacity(0.3), in: Circle())
    }

    private var running: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ROUND \(timer.round)")
                Spacer()
            }
            .font(.caption2.weight(.semibold).monospacedDigit())

            Spacer(minLength: 0)
            Text(timer.phase.title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(tint)
            Text("\(Int(timer.remaining.rounded(.up)))")
                .font(.system(size: 78, weight: .heavy, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button { timer.toggle() } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .tint(tint)
                Button { timer.end() } label: { Image(systemName: "xmark") }
                    .tint(.red)
            }
            .buttonStyle(.bordered)
        }
        .background {
            GeometryReader { geo in
                Rectangle()
                    .fill(tint.opacity(0.4))
                    .frame(height: geo.size.height * max(0, min(1, timer.remaining / timer.phaseDuration)))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.linear(duration: 0.1), value: timer.remaining)
            }
            .ignoresSafeArea()
        }
    }
}
