import SwiftUI

struct SpectrogramView: View {
    @ObservedObject var model: InstrumentModel
    @State private var history: [(date: Date, transfer: Transfer)] = []
    @State private var lastSample = Date.distantPast

    var body: some View {
        Screen(title: "SPECTROGRAM", subtitle: "LAST TWO SECONDS / NEWEST IN FRONT") {
            Canvas { context, size in
                let now = Date()
                let frontLeft = 54.0
                let frontRight = size.width - 72
                let frontY = size.height - 42
                let depthX = 150.0
                let depthY = min(150.0, size.height * 0.52)
                let allDB = history.flatMap { $0.transfer.db }
                let maximum = allDB.max() ?? 0
                let minimum = maximum - 55

                for item in history {
                    let age = min(2, max(0, now.timeIntervalSince(item.date)))
                    let depth = age / 2
                    let recency = 1 - depth
                    let x0 = frontLeft + depth * depthX
                    let x1 = frontRight + depth * depthX
                    let baseline = frontY - depth * depthY
                    let transfer = item.transfer
                    guard transfer.freqs.count == transfer.db.count, transfer.freqs.count > 1 else { continue }
                    var path = Path()
                    for (index, frequency) in transfer.freqs.enumerated() {
                        let position = log(frequency / 60) / log(10_000 / 60)
                        let level = min(1, max(0, (transfer.db[index] - minimum) / max(1, maximum - minimum)))
                        let point = CGPoint(x: x0 + position * (x1 - x0), y: baseline - level * 28)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(Phosphor.amber.opacity(0.16 + recency * 0.7)), lineWidth: 0.8 + recency * 0.6)
                }

                var frontAxis = Path()
                frontAxis.move(to: CGPoint(x: frontLeft, y: frontY))
                frontAxis.addLine(to: CGPoint(x: frontRight, y: frontY))
                context.stroke(frontAxis, with: .color(Phosphor.white.opacity(0.75)), lineWidth: 1)
                for (frequency, name) in [(100.0, "100"), (1_000.0, "1K"), (10_000.0, "10K")] {
                    let x = frontLeft + log(frequency / 60) / log(10_000 / 60) * (frontRight - frontLeft)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: frontY - 5))
                    tick.addLine(to: CGPoint(x: x, y: frontY + 5))
                    context.stroke(tick, with: .color(Phosphor.blue), lineWidth: 1)
                    spectrogramLabel(context, name, at: CGPoint(x: x, y: frontY + 18), color: Phosphor.blue)
                }
                spectrogramLabel(context, "NOW", at: CGPoint(x: frontRight + 8, y: frontY + 2), color: Phosphor.white, anchor: .leading)
                spectrogramLabel(context, "2 S AGO", at: CGPoint(x: frontRight + depthX + 8, y: frontY - depthY + 2), color: Phosphor.blue, anchor: .leading)
                if history.isEmpty {
                    spectrogramLabel(context, "START AUDIO TO RECORD THE SPECTRUM", at: CGPoint(x: size.width / 2, y: size.height / 2), color: Phosphor.blue)
                }
            }
            .frame(minHeight: 240)
            .accessibilityLabel("Spectrogram of the last two seconds, newest in front")
        }
        .onChange(of: model.telemetry.clock) { _, _ in
            let now = Date()
            guard now.timeIntervalSince(lastSample) >= 0.08, let transfer = model.transfer, !transfer.freqs.isEmpty else { return }
            lastSample = now
            history.append((now, transfer))
            history.removeAll { now.timeIntervalSince($0.date) > 2 }
        }
    }
}

private func spectrogramLabel(_ context: GraphicsContext, _ text: String, at point: CGPoint, color: Color, anchor: UnitPoint = .center) {
    context.draw(Text(text).font(.system(size: 9, design: .monospaced)).foregroundStyle(color), at: point, anchor: anchor)
}
