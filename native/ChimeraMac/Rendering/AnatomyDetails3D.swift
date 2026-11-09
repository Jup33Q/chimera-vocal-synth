import Foundation
import simd

private let detailBlue = SIMD4<Float>(0.12, 0.58, 1, 0.88)
private let detailDim = SIMD4<Float>(0.05, 0.22, 0.38, 0.55)
private let detailGreen = SIMD4<Float>(0.22, 1, 0.58, 0.88)

private func detailLine(_ points: [SIMD3<Double>], _ color: SIMD4<Float>, _ width: Float = 1) -> LineStrip3D {
    LineStrip3D(points: points.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }, color: color, width: width)
}

private func catmull(_ points: [SIMD2<Double>], steps: Int = 4) -> [SIMD2<Double>] {
    guard points.count > 2 else { return points }
    var output: [SIMD2<Double>] = []
    for index in 0..<(points.count - 1) {
        let p0 = points[max(0, index - 1)]
        let p1 = points[index]
        let p2 = points[index + 1]
        let p3 = points[min(points.count - 1, index + 2)]
        for step in 0..<steps {
            let t = Double(step) / Double(steps)
            let t2 = t * t
            let t3 = t2 * t
            output.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        }
    }
    output.append(points[points.count - 1])
    return output
}

private func interpolate(_ table: [(Double, Double)], _ x: Double) -> Double {
    guard let first = table.first, let last = table.last else { return 0 }
    if x <= first.0 { return first.1 }
    for index in 1..<table.count where x <= table[index].0 {
        let a = table[index - 1]
        let b = table[index]
        return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
    }
    return last.1
}

private func sideZ(_ section: HeadSection, x: Double) -> Double {
    let widest = section.back + (section.front - section.back) * 0.45
    let c = x > widest
        ? (x - widest) / max(0.0001, section.front - widest)
        : (widest - x) / max(0.0001, widest - section.back)
    return section.width * pow(max(0, 1 - pow(min(1, c), 2.2)), 1 / 2.2)
}

private func frontX(_ section: HeadSection, z: Double) -> Double {
    let widest = section.back + (section.front - section.back) * 0.45
    let u = min(1, abs(z) / section.width)
    return widest + (section.front - widest) * pow(1 - pow(u, 2.2), 1 / 2.2)
}

extension SceneFactory {
    static func headDetails3D(bodyScale k: Double, bodyTint: SIMD4<Float>? = nil) -> [LineStrip3D] {
        let outlineColor = bodyTint ?? detailBlue
        let dimColor = bodyTint.map { SIMD4<Float>($0.x * 0.42, $0.y * 0.42, $0.z * 0.42, 0.55) } ?? detailDim
        var lines: [LineStrip3D] = []
        func point(_ pair: SIMD2<Double>, _ z: Double = 0) -> SIMD3<Double> {
            SIMD3<Double>(pair.x * k, pair.y * k, z)
        }
        func profile(_ values: [(Double, Double)], _ color: SIMD4<Float>, _ width: Float) {
            let points = catmull(values.map { SIMD2<Double>($0.0, $0.1) })
            lines.append(detailLine(points.map { point($0) }, color, width))
        }

        profile([
            (2.3, -4.6), (2.38, -1.5), (2.52, 0.4), (3, 1.7), (5.3, 3),
            (7.25, 3.35), (7.95, 4.6), (7.55, 5.7), (7.05, 10.6),
            (7.75, 10.78), (8.75, 11.05), (9.25, 11.65), (8.95, 12.6),
            (8.35, 13.9), (7.7, 15), (7.95, 16.1), (7.9, 18.1),
            (6.9, 20.5), (3, 22.9), (-2.2, 22.7), (-6.9, 19.6),
            (-8.7, 15.4), (-8.3, 11.9), (-7.4, 8.9), (-6.8, 4.8), (-6.6, 0), (-6.6, -4.6)
        ], outlineColor, 1.5)
        profile([
            (7, 16.2), (7.3, 18.5), (6, 20.7), (3, 22.1), (-2, 22),
            (-6.3, 19.2), (-7.9, 15.3), (-7.4, 12.6), (-4.6, 12.2),
            (-2.2, 13.3), (1, 13.7), (4.1, 14.1), (6.2, 14.9)
        ], dimColor, 1)
        profile([
            (6.55, 16.3), (6.75, 18.4), (5.5, 20.1), (2.8, 21.4),
            (-1.9, 21.3), (-5.8, 18.8), (-7.1, 15.4), (-6.7, 13.1),
            (-4.4, 12.8), (-2.1, 13.9), (1, 14.3), (4, 14.7), (5.9, 15.4)
        ], dimColor, 1)

        let sections = headSections()
        for side in [-1.0, 1.0] {
            func onSide(_ values: [(Double, Double)], offset: (Int, Int) -> Double) {
                let curve = catmull(values.map { SIMD2<Double>($0.0, $0.1) })
                let points = curve.enumerated().map { index, p -> SIMD3<Double> in
                    let section = interpolateHead(sections, y: p.y)
                    let z = section.map { sideZ($0, x: p.x) } ?? 0
                    return SIMD3<Double>(p.x * k, p.y * k, side * (z + offset(index, curve.count)) * k)
                }
                lines.append(detailLine(points, dimColor, 1))
            }
            onSide([
                (-2.55, 13.4), (-2.85, 14.75), (-3.65, 15.45), (-4.6, 15.25),
                (-5.2, 14.25), (-5.4, 12.8), (-5.05, 11.3), (-4.55, 10.2),
                (-3.95, 9.55), (-3.35, 9.65), (-3, 10.35)
            ]) { index, count in 0.25 + 1.2 * pow(sin(Double.pi * Double(index) / Double(count - 1)), 1.5) }
            onSide([(-3.15, 14.3), (-3.95, 14.45), (-4.55, 13.5), (-4.6, 12.1), (-4.15, 11.05)]) { _, _ in 0.55 }
            onSide([(-2.7, 11.2), (-2.55, 11.85), (-2.75, 12.35)]) { _, _ in 0.35 }
            onSide((0...16).map { index in
                let angle = Double(index) / 16 * 2 * Double.pi
                return (-3.5 + 0.6 * cos(angle), 12 + 0.85 * sin(angle))
            }) { _, _ in 0.12 }

            var nose: [SIMD3<Double>] = []
            var y = 14.6
            while y >= 11.3 {
                if let section = interpolateHead(sections, y: y) {
                    let z = side * (0.3 + 1.05 * (14.6 - y) / 3.3)
                    nose.append(SIMD3<Double>(frontX(section, z: z) * k, y * k, z * k))
                }
                y -= 0.15
            }
            lines.append(detailLine(nose, dimColor, 0.9))
            let wing = [(7.95, 11.05, 0.95), (7.4, 11.15, 1.45), (7.25, 11.6, 1.55), (7.55, 12.1, 1.35), (8.2, 12.15, 1.0)]
            lines.append(detailLine(wing.map { SIMD3<Double>($0.0 * k, $0.1 * k, side * $0.2 * k) }, dimColor, 1))
            let nostril = (0...20).map { index -> SIMD3<Double> in
                let angle = Double(index) / 20 * 2 * Double.pi
                return SIMD3<Double>((8.05 + 0.42 * cos(angle)) * k, (10.98 + 0.04 * cos(angle)) * k, side * (0.62 + 0.26 * sin(angle)) * k)
            }
            lines.append(detailLine(nostril, dimColor, 0.9))
        }

        let brainWidths = [(12.3, 4.0), (13, 5.6), (14.5, 6.4), (16.5, 6.9), (18.5, 6.6), (20, 5.4), (21, 3.6), (21.45, 0.5)]
        for y in stride(from: 13.0, through: 20.8, by: 1.3) {
            let width = interpolate(brainWidths, y)
            let points = (0...40).map { index -> SIMD3<Double> in
                let angle = Double(index) / 40 * 2 * Double.pi
                return SIMD3<Double>((-0.6 + 5.5 * cos(angle)) * k, y * k, width * sin(angle) * k)
            }
            lines.append(detailLine(points, SIMD4<Float>(0.05, 0.22, 0.38, 0.25), 0.8))
        }
        return lines
    }

    static func tongueSurface3D(frame: HumanFrame, bodyScale k: Double, lateral: Double) -> [LineStrip3D] {
        var tipIndex = 0
        var best = Double.infinity
        for (index, point) in frame.tongue.enumerated() {
            let distance = pow(point.x - frame.tip.x, 2) + pow(point.y - frame.tip.y, 2)
            if distance < best {
                best = distance
                tipIndex = index
            }
        }
        let outline = Array(frame.tongue[0...tipIndex])
        guard outline.count > 1 else { return [] }
        var cumulative = [0.0]
        for index in 1..<outline.count {
            cumulative.append(cumulative[index - 1] + hypot(outline[index].x - outline[index - 1].x, outline[index].y - outline[index - 1].y))
        }
        let length = cumulative.last ?? 0
        guard length > 0.001 else { return [] }
        let count = 22
        var stations: [Vec2] = []
        var segment = 0
        for index in 0..<count {
            let target = length * Double(index) / Double(count - 1)
            while segment < outline.count - 2 && cumulative[segment + 1] < target { segment += 1 }
            let t = (target - cumulative[segment]) / max(0.000001, cumulative[segment + 1] - cumulative[segment])
            stations.append(Vec2(
                x: outline[segment].x + (outline[segment + 1].x - outline[segment].x) * t,
                y: outline[segment].y + (outline[segment + 1].y - outline[segment].y) * t
            ))
        }
        let widths = [(0, 1.5), (0.15, 1.9), (0.35, 2.35), (0.6, 2.45), (0.8, 2.2), (0.92, 1.5), (1, 0.55)]
        let heights = [(0, 1.3), (0.35, 1.1), (0.7, 0.9), (0.9, 0.55), (1, 0.25)]
        let tongueFrames = stations.enumerated().map { index, point -> (center: SIMD3<Double>, normal: SIMD3<Double>, width: Double, height: Double) in
            let before = stations[max(0, index - 1)]
            let after = stations[min(count - 1, index + 1)]
            let tangent = SIMD2<Double>(after.x - before.x, after.y - before.y)
            let unit = simd_normalize(tangent)
            let progress = Double(index) / Double(count - 1)
            let lateralLift = 0.8 * min(1, max(0, lateral)) * min(1, max(0, (progress - 0.45) / 0.35))
            return (
                SIMD3<Double>(point.x, point.y, 0),
                SIMD3<Double>(-unit.y, unit.x, 0),
                interpolate(widths, progress) * k,
                (interpolate(heights, progress) + lateralLift) * k
            )
        }
        func at(_ frame: (center: SIMD3<Double>, normal: SIMD3<Double>, width: Double, height: Double), _ phi: Double) -> SIMD3<Double> {
            frame.center - frame.normal * (frame.height * (1 - cos(phi))) + SIMD3<Double>(0, 0, frame.width * sin(phi))
        }
        var lines: [LineStrip3D] = []
        for index in stride(from: 1, to: count - 1, by: 2) {
            let points = (0...12).map { at(tongueFrames[index], -Double.pi / 2 + Double.pi * Double($0) / 12) }
            lines.append(detailLine(points, SIMD4<Float>(detailGreen.x, detailGreen.y, detailGreen.z, 0.5), 0.9))
        }
        for phi in [-Double.pi / 2, -Double.pi / 4, Double.pi / 4, Double.pi / 2] {
            let alpha = abs(phi) > 1 ? Float(0.8) : Float(0.45)
            lines.append(detailLine(tongueFrames.map { at($0, phi) }, SIMD4<Float>(detailGreen.x, detailGreen.y, detailGreen.z, alpha), abs(phi) > 1 ? 1.2 : 0.9))
        }
        return lines
    }
}
