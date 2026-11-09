import Foundation
import simd

enum SceneFactory {
    private static let blue = SIMD4<Float>(0.12, 0.58, 1.0, 0.92)
    private static let dimBlue = SIMD4<Float>(0.05, 0.22, 0.38, 0.7)
    private static let amber = SIMD4<Float>(1.0, 0.56, 0.12, 0.95)
    private static let green = SIMD4<Float>(0.22, 1.0, 0.58, 0.95)
    private static let red = SIMD4<Float>(1.0, 0.24, 0.28, 0.95)
    private static let pink = SIMD4<Float>(1.0, 0.32, 0.68, 0.95)
    private static let white = SIMD4<Float>(0.85, 0.92, 1.0, 0.9)

    static func anatomy(frame: HumanFrame?, telemetry: VoiceTelemetry, size: CGSize) -> MetalScene {
        guard let frame, size.width > 0, size.height > 0 else { return MetalScene() }
        let scale = Float(min(size.width / 20, size.height / 29))
        let origin = SIMD2<Float>(Float(size.width) * 0.43 + 7.5 * scale, Float(size.height) * 0.88)

        func point(_ value: Vec2) -> SIMD2<Float> {
            SIMD2<Float>(origin.x + Float(value.x) * scale, origin.y - Float(value.y) * scale)
        }
        func line(_ points: [Vec2], _ color: SIMD4<Float>, _ width: Float = 1.2) -> LineStrip {
            LineStrip(points: points.map(point), color: color, width: width)
        }

        var scene = MetalScene()
        scene.lines.append(line(frame.nasalCavity + [frame.nasalCavity.first].compactMap { $0 }, dimBlue))
        scene.lines.append(line(frame.outer, blue, 1.4))
        scene.lines.append(line(frame.inner, blue, 1.2))
        scene.lines.append(line(frame.epiglottis, blue, 1.6))
        scene.lines.append(line(frame.upperTeeth, dimBlue))
        scene.lines.append(line(frame.lowerTeeth, dimBlue))
        scene.lines.append(line(frame.jawBone, red, 1.4))
        scene.lines.append(line(frame.tongue, green, 1.6))
        scene.lines.append(line(frame.upperLip, pink, 1.5))
        scene.lines.append(line(frame.lowerLip, pink, 1.5))
        scene.lines.append(line(frame.velum, white, 1.3))

        for (index, sample) in frame.grid.enumerated() {
            let pressure = index < telemetry.pressure.count ? telemetry.pressure[index] : 0
            let heat = Float(pressure / (pressure + 1_200))
            let color = SIMD4<Float>(1, 0.35 + heat * 0.4, 0.08, 0.08 + heat * 0.9)
            scene.lines.append(line([sample.inner, sample.outer], color, 0.8 + heat * 1.8))
        }
        let glottis = frame.glottis
        let vibration = Float(min(1, telemetry.voicing)) * scale * 0.16
        scene.lines.append(line([
            Vec2(x: glottis.x - 0.6, y: glottis.y),
            Vec2(x: glottis.x - Double(vibration / scale), y: glottis.y + 0.12)
        ], amber, 1.4))
        return scene
    }

    static func spectrum(_ transfer: Transfer?, size: CGSize) -> MetalScene {
        var scene = MetalScene()
        addAxes(to: &scene, size: size)
        guard let transfer, transfer.freqs.count == transfer.db.count, !transfer.freqs.isEmpty else { return scene }
        let rect = insetRect(size)
        func x(_ frequency: Double) -> Float {
            let position = log(frequency / 60) / log(8_000 / 60)
            return Float(rect.minX) + Float(position) * Float(rect.width)
        }
        let points = zip(transfer.freqs, transfer.db).map { frequency, db -> SIMD2<Float> in
            let normalized = max(0, min(1, (db + 35) / 65))
            return SIMD2<Float>(x(frequency), Float(rect.maxY) - Float(normalized) * Float(rect.height))
        }
        scene.lines.append(LineStrip(points: points, color: amber, width: 1.4))
        for formant in transfer.formants {
            let fx = x(formant)
            scene.lines.append(LineStrip(points: [SIMD2<Float>(fx, Float(rect.minY)), SIMD2<Float>(fx, Float(rect.maxY))], color: green, width: 0.8))
        }
        return scene
    }

    static func glottal(_ telemetry: VoiceTelemetry, size: CGSize) -> MetalScene {
        var scene = MetalScene()
        addAxes(to: &scene, size: size)
        let rect = insetRect(size)
        scene.lines.append(waveform(telemetry.glottalArea, rect: rect, color: green, signed: false))
        scene.lines.append(waveform(telemetry.glottalFlow, rect: rect, color: amber, signed: true))
        return scene
    }

    static func creature(_ telemetry: CreatureTelemetry, size: CGSize) -> MetalScene {
        var scene = MetalScene()
        guard size.width > 40, size.height > 40 else { return scene }
        let rowHeight = Float(size.height - 32) / Float(max(1, telemetry.tubes.count))
        for (row, tube) in telemetry.tubes.enumerated() {
            let center = 16 + rowHeight * (Float(row) + 0.5)
            var upper: [SIMD2<Float>] = []
            var lower: [SIMD2<Float>] = []
            var pressure: [SIMD2<Float>] = []
            let count = tube.areas.count
            for index in 0..<count {
                let x = 20 + Float(index) / Float(max(1, count - 1)) * Float(size.width - 40)
                let area = Float(sqrt(max(0, tube.areas[index])) * 8 + 2)
                upper.append(SIMD2<Float>(x, center - area))
                lower.append(SIMD2<Float>(x, center + area))
                let level = index < tube.rms.count ? tube.rms[index] : 0
                let normalized = Float(level / (level + 800) + 1)
                let amplitude = min(rowHeight * 0.35, normalized * rowHeight * 0.2)
                pressure.append(SIMD2<Float>(x, center - amplitude))
            }
            scene.lines.append(LineStrip(points: upper, color: blue, width: 1.2))
            scene.lines.append(LineStrip(points: lower, color: blue, width: 1.2))
            scene.lines.append(LineStrip(points: pressure, color: amber, width: 1.1))
        }
        return scene
    }

    private static func waveform(_ values: [Double], rect: CGRect, color: SIMD4<Float>, signed: Bool) -> LineStrip {
        guard !values.isEmpty else { return LineStrip(points: [], color: color, width: 1) }
        let maximum = max(values.map { abs($0) }.max() ?? 1, 0.0001)
        let points = values.enumerated().map { index, value -> SIMD2<Float> in
            let x = Float(rect.minX) + Float(index) / Float(max(1, values.count - 1)) * Float(rect.width)
            let normalized = value / maximum
            let y = signed ? Float(rect.midY) - Float(normalized) * Float(rect.height) * 0.45 : Float(rect.maxY) - Float(normalized) * Float(rect.height)
            return SIMD2<Float>(x, y)
        }
        return LineStrip(points: points, color: color, width: 1.2)
    }

    private static func insetRect(_ size: CGSize) -> CGRect {
        CGRect(x: 20, y: 12, width: max(1, size.width - 40), height: max(1, size.height - 24))
    }

    private static func addAxes(to scene: inout MetalScene, size: CGSize) {
        let rect = insetRect(size)
        for index in 0...4 {
            let y = Float(rect.minY) + Float(index) / 4 * Float(rect.height)
            scene.lines.append(LineStrip(points: [SIMD2<Float>(Float(rect.minX), y), SIMD2<Float>(Float(rect.maxX), y)], color: dimBlue, width: 0.5))
        }
        scene.lines.append(LineStrip(points: [
            SIMD2<Float>(Float(rect.minX), Float(rect.minY)),
            SIMD2<Float>(Float(rect.minX), Float(rect.maxY)),
            SIMD2<Float>(Float(rect.maxX), Float(rect.maxY))
        ], color: dimBlue, width: 0.8))
    }
}
