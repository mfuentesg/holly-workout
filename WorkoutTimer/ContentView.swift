import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer = IntervalTimer.shared
    @AppStorage("workSeconds") private var work = 45
    @AppStorage("restSeconds") private var rest = 15

    private var tint: Color { timer.phase == .work ? .green : .orange }

    var body: some View {
        ZStack {
            tint.opacity(0.18).ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 28) {
                Text("ROUND \(timer.round)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)

                ZStack {
                    PulseView(remaining: timer.remaining, tint: tint, running: timer.isRunning)
                    VStack(spacing: 4) {
                        Text(timer.phase.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(tint)
                        Text("\(Int(timer.remaining.rounded(.up)))")
                            .font(.system(size: 110, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 32)
                .aspectRatio(1, contentMode: .fit)

                HStack(spacing: 20) {
                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                            .frame(width: 64, height: 64)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .disabled(!timer.hasStarted)

                    Button { timer.toggle() } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                            .frame(width: 96, height: 96)
                            .background(tint, in: Circle())
                            .foregroundStyle(.black)
                    }
                }
                .foregroundStyle(.white)

                HStack(spacing: 16) {
                    stepper("Work", value: $work, range: 5...300, step: 5, color: .green)
                    stepper("Rest", value: $rest, range: 5...300, step: 5, color: .orange)
                }
                .disabled(timer.hasStarted)
                .opacity(timer.hasStarted ? 0.4 : 1)
            }
            .padding()
        }
        .onAppear { sync() }
        .onChange(of: scenePhase) { if scenePhase == .active { Connectivity.shared.reconcile() } }
        .onChange(of: work) { sync() }
        .onChange(of: rest) { sync() }
    }

    private func sync() {
        timer.workSeconds = work
        timer.restSeconds = rest
        timer.applySettings()
    }

    private func stepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(color)
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)s").font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview { ContentView() }
