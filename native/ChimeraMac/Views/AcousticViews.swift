import SwiftUI

struct TubeView: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        Screen(title: "TUBE", subtitle: "GLOTTIS TO LIPS") {
            Canvas { context, size in
                let telemetry = model.telemetry
                let phLen = telemetry.phLen > 0 ? telemetry.phLen : model.frame?.pharynxLength ?? 8.8
                let orLen = telemetry.orLen > 0 ? telemetry.orLen : max(0, (model.frame?.length ?? 17.1) - phLen)
                let total = phLen + orLen
                guard total > 0, !telemetry.phAreas.isEmpty, !telemetry.orAreas.isEmpty else {
                    acousticLabel(context, "START AUDIO TO SEE THE AIRWAY", at: CGPoint(x: size.width / 2, y: size.height / 2), color: Phosphor.blue)
                    return
                }

                let x0 = 16.0
                let x1 = size.width - 16
                let scale = (x1 - x0) / total
                let axisY = size.height * 0.6
                let diameterScale = size.height * 0.3 / 4
                var sections: [(x: Double, radius: Double, level: Double)] = []
                for (index, area) in telemetry.phAreas.enumerated() {
                    sections.append((
                        x: x0 + (Double(index) + 0.5) / Double(telemetry.phAreas.count) * phLen * scale,
                        radius: sqrt(max(0, area) / .pi) * diameterScale,
                        level: pressureLevel(telemetry.pressure, index: index)
                    ))
                }
                for (index, area) in telemetry.orAreas.enumerated() {
                    sections.append((
                        x: x0 + (phLen + (Double(index) + 0.5) / Double(telemetry.orAreas.count) * orLen) * scale,
                        radius: sqrt(max(0, area) / .pi) * diameterScale,
                        level: pressureLevel(telemetry.pressure, index: telemetry.phAreas.count + index)
                    ))
                }

                let velum = telemetry.velumPort > 0 ? telemetry.velumPort : model.frame?.velumPort ?? 0
                let open = velum > 0.02
                let junctionX = x0 + phLen * scale
                let noseY = axisY - size.height * 0.36
                let noseLength = max(20, min(x1 - junctionX - 40, 11.4 * model.bodyScale * scale * 0.62))
                let nasalColor = open ? Phosphor.white : Phosphor.blue.opacity(0.45)
                for offset in [-5.0, 5.0] {
                    var nasal = Path()
                    nasal.move(to: CGPoint(x: junctionX + offset, y: axisY - 26))
                    nasal.addLine(to: CGPoint(x: junctionX + offset, y: noseY + offset + 2))
                    nasal.addQuadCurve(to: CGPoint(x: junctionX + 8, y: noseY + offset), control: CGPoint(x: junctionX + offset, y: noseY + offset))
                    nasal.addLine(to: CGPoint(x: junctionX + noseLength, y: noseY + offset))
                    context.stroke(nasal, with: .color(nasalColor), style: StrokeStyle(lineWidth: 1, dash: open ? [] : [3, 4]))
                }
                acousticLabel(context, "NOSE", at: CGPoint(x: junctionX + noseLength + 6, y: noseY + 3), color: nasalColor, size: 9, anchor: .leading)
                acousticLabel(context, open ? String(format: "VELUM OPEN %.2f CM²", velum) : "VELUM SHUT", at: CGPoint(x: junctionX, y: noseY - 12), color: nasalColor, size: 9)

                var top = Path()
                var bottom = Path()
                top.move(to: CGPoint(x: x0, y: axisY - 3))
                bottom.move(to: CGPoint(x: x0, y: axisY + 3))
                for section in sections {
                    top.addLine(to: CGPoint(x: section.x, y: axisY - section.radius))
                    bottom.addLine(to: CGPoint(x: section.x, y: axisY + section.radius))
                }
                if let last = sections.last {
                    top.addLine(to: CGPoint(x: x1, y: axisY - last.radius))
                    bottom.addLine(to: CGPoint(x: x1, y: axisY + last.radius))
                }
                context.stroke(top, with: .color(Phosphor.blue), lineWidth: 1.3)
                context.stroke(bottom, with: .color(Phosphor.blue), lineWidth: 1.3)
                for section in sections {
                    let radius = section.radius
                    let rect = CGRect(x: section.x - max(1.2, radius * 0.28), y: axisY - max(0.6, radius), width: max(2.4, radius * 0.56), height: max(1.2, radius * 2))
                    context.stroke(Path(ellipseIn: rect), with: .color(heat(section.level)), lineWidth: 1.1)
                }
                var axis = Path()
                axis.move(to: CGPoint(x: x0, y: axisY))
                axis.addLine(to: CGPoint(x: x1, y: axisY))
                context.stroke(axis, with: .color(Phosphor.blue.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 5]))

                let teeth = model.frame?.teethS ?? phLen + orLen * 0.75
                let marks = [(0, "GLOTTIS"), (phLen, "VELUM"), (teeth, "TEETH"), (total, "LIPS")]
                var lastRight = -Double.infinity
                for (position, name) in marks {
                    let x = x0 + position * scale
                    let width = Double(name.count) * 8
                    let labelX = min(size.width - width - 2, max(2, x - width / 2))
                    if labelX < lastRight + 8 { continue }
                    lastRight = labelX + width
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - 26))
                    tick.addLine(to: CGPoint(x: x, y: size.height - 21))
                    context.stroke(tick, with: .color(Phosphor.blue.opacity(0.6)), lineWidth: 1)
                    acousticLabel(context, name, at: CGPoint(x: labelX, y: size.height - 9), color: Phosphor.blue, size: 9, anchor: .leading)
                }
            }
            .frame(minHeight: 220)
            .accessibilityLabel("Area function of the simulated tube, lit by sound pressure")
        }
    }

    private func pressureLevel(_ values: [Double], index: Int) -> Double {
        guard values.indices.contains(index), values[index] > 0 else { return 0 }
        return min(1, max(0, (log10(values[index]) - log10(40)) / (log10(4_000) - log10(40))))
    }

    private func heat(_ level: Double) -> Color {
        let value = pow(min(1, max(0, level)), 0.85)
        return Color(red: 0.25 + value * 0.75, green: 0.12 + value * 0.85, blue: 0.03 + value * 0.8).opacity(0.35 + value * 0.65)
    }
}

struct VocalFoldsView: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        Screen(title: "VOCAL FOLDS", subtitle: "SLOWED 100×") {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let area = model.telemetry.glottalArea
                    let flow = model.telemetry.glottalFlow
                    let count = min(area.count, flow.count)
                    let phase = (timeline.date.timeIntervalSinceReferenceDate / 1.8).truncatingRemainder(dividingBy: 1)
                    let index = count > 0 ? min(count - 1, Int(phase * Double(count))) : 0
                    let maximum = area.map { max(0.02, $0) }.max() ?? 0.02
                    let minimum = area.min() ?? 0
                    let current = area.indices.contains(index) ? area[index] : 0
                    let radius = max(20, min(size.height * 0.4, size.width * 0.2))
                    let center = CGPoint(x: radius + 14, y: size.height / 2 + 4)
                    let length = radius * 1.22
                    let opening = min(1, current / max(0.12, maximum)) * radius * 0.42
                    let chink = area.isEmpty ? 0 : min(radius * 0.06, minimum / 0.05 * radius * 0.08)

                    for extra in [5.0, 0.0] {
                        let rect = CGRect(x: center.x - radius - extra, y: center.y - radius - extra, width: (radius + extra) * 2, height: (radius + extra) * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(extra > 0 ? Phosphor.blue.opacity(0.5) : Phosphor.blue), lineWidth: extra > 0 ? 0.8 : 1.3)
                    }
                    for sign in [-1.0, 1.0] {
                        var edge = Path()
                        edge.move(to: CGPoint(x: center.x, y: center.y - length / 2))
                        edge.addQuadCurve(to: CGPoint(x: center.x + sign * chink * 0.8, y: center.y + length / 2), control: CGPoint(x: center.x + sign * (opening + chink), y: center.y + length * 0.05))
                        context.stroke(edge, with: .color(Phosphor.white), lineWidth: 1.6)
                        var fold = Path()
                        fold.move(to: CGPoint(x: center.x + sign * 3, y: center.y - length / 2 - 2))
                        fold.addQuadCurve(to: CGPoint(x: center.x + sign * radius * 0.22, y: center.y + length / 2 + 4), control: CGPoint(x: center.x + sign * radius * 0.62, y: center.y))
                        context.stroke(fold, with: .color(Phosphor.blue), lineWidth: 1.1)
                        var falseFold = Path()
                        falseFold.move(to: CGPoint(x: center.x + sign * 8, y: center.y - length / 2 - 8))
                        falseFold.addQuadCurve(to: CGPoint(x: center.x + sign * radius * 0.42, y: center.y + length / 2 + 6), control: CGPoint(x: center.x + sign * radius * 0.92, y: center.y - 2))
                        context.stroke(falseFold, with: .color(Phosphor.blue.opacity(0.55)), lineWidth: 1)
                        let aryRect = CGRect(x: center.x + sign * radius * 0.2 - radius * 0.13, y: center.y + length / 2 + radius * 0.05, width: radius * 0.26, height: radius * 0.18)
                        context.stroke(Path(ellipseIn: aryRect), with: .color(Phosphor.blue), lineWidth: 1.1)
                    }
                    var epiglottis = Path()
                    epiglottis.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y - radius * 0.62))
                    epiglottis.addQuadCurve(to: CGPoint(x: center.x + radius * 0.42, y: center.y - radius * 0.62), control: CGPoint(x: center.x, y: center.y - radius * 0.98))
                    context.stroke(epiglottis, with: .color(Phosphor.blue), lineWidth: 1.2)
                    acousticLabel(context, "FRONT", at: CGPoint(x: center.x, y: center.y - radius - 8), color: Phosphor.blue, size: 8)

                    let x0 = center.x + radius + 22
                    let x1 = size.width - 12
                    guard x1 - x0 >= 40 else { return }
                    let bandHeight = max(12, (size.height - 52) / 2)
                    let areaTop = 16.0
                    let areaBottom = areaTop + bandHeight
                    let flowTop = areaBottom + 18
                    let flowBottom = flowTop + bandHeight
                    acousticLabel(context, "AREA", at: CGPoint(x: x1, y: areaTop - 4), color: Phosphor.blue, size: 9, anchor: .trailing)
                    acousticLabel(context, "FLOW", at: CGPoint(x: x1, y: flowTop - 4), color: Phosphor.blue, size: 9, anchor: .trailing)
                    for y in [areaBottom, flowBottom] {
                        var rule = Path()
                        rule.move(to: CGPoint(x: x0, y: y))
                        rule.addLine(to: CGPoint(x: x1, y: y))
                        context.stroke(rule, with: .color(Phosphor.blue.opacity(0.45)), lineWidth: 1)
                    }
                    guard count > 1 else {
                        acousticLabel(context, "START AUDIO TO SEE THEM VIBRATE", at: CGPoint(x: (x0 + x1) / 2, y: (areaTop + areaBottom) / 2), color: Phosphor.blue, size: 9)
                        return
                    }
                    drawWave(context, Array(area.prefix(count)), x0: x0, x1: x1, y0: areaTop, y1: areaBottom, color: Phosphor.white)
                    drawWave(context, Array(flow.prefix(count)), x0: x0, x1: x1, y0: flowTop, y1: flowBottom, color: Phosphor.amber)
                    let playheadX = x0 + (x1 - x0) * Double(index) / Double(count - 1)
                    var playhead = Path()
                    playhead.move(to: CGPoint(x: playheadX, y: areaTop))
                    playhead.addLine(to: CGPoint(x: playheadX, y: flowBottom))
                    context.stroke(playhead, with: .color(Phosphor.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    let opened = area.filter { $0 > minimum + 0.002 }.count
                    acousticLabel(context, "OPEN \(Int((Double(opened) / Double(area.count) * 100).rounded()))%", at: CGPoint(x: x0, y: size.height - 4), color: Phosphor.blue, size: 9, anchor: .leading)
                    acousticLabel(context, String(format: "%.1f MM²", current * 100), at: CGPoint(x: x1, y: size.height - 4), color: Phosphor.blue, size: 9, anchor: .trailing)
                }
            }
            .frame(minHeight: 280)
            .accessibilityLabel("Vocal folds seen from above, with glottal area and flow")
        }
    }

    private func drawWave(_ context: GraphicsContext, _ values: [Double], x0: Double, x1: Double, y0: Double, y1: Double, color: Color) {
        guard let minimum = values.min(), let maximum = values.max(), !values.isEmpty else { return }
        var path = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(
                x: x0 + (x1 - x0) * Double(index) / Double(values.count - 1),
                y: y1 - (value - minimum) / max(1e-9, maximum - minimum) * (y1 - y0 - 4)
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.3)
    }
}

private func acousticLabel(_ context: GraphicsContext, _ text: String, at point: CGPoint, color: Color, size: Double = 9, anchor: UnitPoint = .center) {
    context.draw(Text(text).font(.system(size: size, design: .monospaced)).foregroundStyle(color), at: point, anchor: anchor)
}
