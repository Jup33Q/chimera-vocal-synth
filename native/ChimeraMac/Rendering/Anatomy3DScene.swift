import Foundation
import simd

struct HeadSection {
    let y: Double
    let front: Double
    let back: Double
    let width: Double
}

extension SceneFactory {
    static func anatomy3D(frame: HumanFrame?, telemetry: VoiceTelemetry, bodyScale: Double, bodyTint: SIMD4<Float>? = nil) -> Metal3DScene {
        guard let frame else { return Metal3DScene() }
        let k = bodyScale
        var scene = Metal3DScene()
        let blue = bodyTint ?? SIMD4<Float>(0.12, 0.58, 1, 0.78)
        let dim = bodyTint.map { SIMD4<Float>($0.x * 0.42, $0.y * 0.42, $0.z * 0.42, 0.48) } ?? SIMD4<Float>(0.05, 0.22, 0.38, 0.48)
        let green = SIMD4<Float>(0.22, 1, 0.58, 0.88)
        let red = SIMD4<Float>(1, 0.24, 0.28, 0.82)
        let pink = SIMD4<Float>(1, 0.32, 0.68, 0.9)
        let white = SIMD4<Float>(0.85, 0.92, 1, 0.8)

        func add(_ points: [SIMD3<Double>], _ color: SIMD4<Float>, _ width: Float = 1) {
            guard points.count > 1 else { return }
            scene.lines.append(LineStrip3D(
                points: points.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) },
                color: color,
                width: width
            ))
        }
        func body(_ x: Double, _ y: Double, _ z: Double = 0) -> SIMD3<Double> {
            SIMD3<Double>(x * k, y * k, z * k)
        }
        func ellipse(_ center: SIMD3<Double>, _ u: SIMD3<Double>, _ v: SIMD3<Double>, _ color: SIMD4<Float>, segments: Int = 32) {
            let points = (0...segments).map { index in
                let angle = Double(index) / Double(segments) * 2 * Double.pi
                return center + cos(angle) * u + sin(angle) * v
            }
            add(points, color)
        }

        let sections = headSections()
        for section in sections {
            let points = (0...48).map { index -> SIMD3<Double> in
                let angle = Double(index) / 48 * 2 * Double.pi
                let c = cos(angle)
                let s = sin(angle)
                let exponent = 2 / 2.2
                let widest = section.back + (section.front - section.back) * 0.45
                let x = c >= 0
                    ? widest + (section.front - widest) * pow(c, exponent)
                    : widest - (widest - section.back) * pow(-c, exponent)
                let z = section.width * (s >= 0 ? 1 : -1) * pow(abs(s), exponent)
                return body(x, section.y, z)
            }
            add(points, dim, 0.9)
        }
        for angle in stride(from: 0.0, through: 2 * Double.pi, by: Double.pi / 4) {
            var points: [SIMD3<Double>] = []
            var y = -4.4
            while y <= 22.8 {
                if let section = interpolateHead(sections, y: y) {
                    let c = cos(angle)
                    let s = sin(angle)
                    let exponent = 2 / 2.2
                    let widest = section.back + (section.front - section.back) * 0.45
                    let x = c >= 0
                        ? widest + (section.front - widest) * pow(c, exponent)
                        : widest - (widest - section.back) * pow(-c, exponent)
                    let z = section.width * (s >= 0 ? 1 : -1) * pow(abs(s), exponent)
                    points.append(body(x, y, z))
                }
                y += 0.5
            }
            add(points, dim, 0.8)
        }
        scene.lines.append(contentsOf: headDetails3D(bodyScale: k, bodyTint: bodyTint))

        func basis(_ normal: SIMD3<Double>) -> (SIMD3<Double>, SIMD3<Double>) {
            let up = SIMD3<Double>(0, 1, 0)
            let u = simd_normalize(simd_cross(up, normal))
            return (u, simd_cross(normal, u))
        }
        let gazeYaw = sin(telemetry.clock * 0.37) * 0.16
        let gazePitch = sin(telemetry.clock * 0.23) * 0.07
        let gaze = SIMD3<Double>(cos(gazePitch) * cos(gazeYaw), sin(gazePitch), cos(gazePitch) * sin(gazeYaw))
        let irisPlane = basis(gaze)
        let eyeRadius = 1.05 * k
        let wide = min(1, max(0, (telemetry.f0 - 150) / 200))
        for side in [-1.0, 1.0] {
            add(frame.nasalCavity.map { SIMD3<Double>($0.x, $0.y, side * 1.2 * k) }, dim)
            add(frame.upperTeeth.map { SIMD3<Double>($0.x, $0.y, side * 1.7 * k) }, blue)
            add(frame.lowerTeeth.map { SIMD3<Double>($0.x, $0.y, side * 1.7 * k) }, blue)
            add(frame.jawBone.map { SIMD3<Double>($0.x, $0.y, side * 3.1 * k) }, red, 1.3)
            add(frame.velum.map { SIMD3<Double>($0.x, $0.y, side * 1.1 * k) }, white)

            let eye = body(6.15, 15.35, side * 3.15)
            ellipse(eye, SIMD3<Double>(eyeRadius, 0, 0), SIMD3<Double>(0, eyeRadius, 0), dim, segments: 36)
            ellipse(eye, SIMD3<Double>(eyeRadius, 0, 0), SIMD3<Double>(0, 0, eyeRadius), dim, segments: 36)
            ellipse(eye, SIMD3<Double>(0, eyeRadius, 0), SIMD3<Double>(0, 0, eyeRadius), dim, segments: 36)
            ellipse(eye + gaze * (eyeRadius * 0.86), irisPlane.0 * (eyeRadius * 0.5), irisPlane.1 * (eyeRadius * 0.5), blue, segments: 28)
            ellipse(eye + gaze * (eyeRadius * 0.97), irisPlane.0 * (eyeRadius * 0.2), irisPlane.1 * (eyeRadius * 0.2), white, segments: 18)

            for upper in [true, false] {
                let points = (0...16).map { index -> SIMD3<Double> in
                    let sv = -1 + Double(index) / 8
                    let al = side * sv * 0.95
                    let lower = -0.36 * (1 - sv * sv) - 0.06 * sv * side
                    let opening = (0.5 + 0.2 * wide) * (1 - sv * sv) + 0.06 * sv * side
                    let be = upper ? opening : lower
                    return eye + SIMD3<Double>(
                        1.04 * eyeRadius * cos(be) * cos(al),
                        1.04 * eyeRadius * sin(be),
                        1.04 * eyeRadius * cos(be) * sin(al)
                    )
                }
                add(points, blue, upper ? 1.25 : 1.05)
            }
            let brow = (0...12).map { index -> SIMD3<Double> in
                let sv = -1 + Double(index) / 6
                let al = side * (0.15 + sv * 0.62)
                let be = 0.82 + 0.12 * (1 - sv * sv) - 0.06 * sv + 0.12 * wide
                return eye + SIMD3<Double>(
                    1.32 * eyeRadius * cos(be) * cos(al),
                    1.32 * eyeRadius * sin(be),
                    1.32 * eyeRadius * cos(be) * sin(al)
                )
            }
            add(brow, dim, 1.2)
        }
        add(frame.jawBone.map { SIMD3<Double>($0.x, $0.y, 0) }, red, 1.2)
        add(frame.tongue.map { SIMD3<Double>($0.x, $0.y, 0) }, green, 1.5)
        add(frame.velum.map { SIMD3<Double>($0.x, $0.y, 0) }, white, 1.2)
        let lateral = telemetry.artic.count > 15 ? min(1, max(0, telemetry.artic[15])) : 0
        scene.lines.append(contentsOf: tongueSurface3D(frame: frame, bodyScale: k, lateral: lateral))

        for level in [-2.0, -1.0, 0.0, 1.0, 2.0] {
            let alpha = Float(level == 0 ? 0.9 : 0.42)
            let color = SIMD4<Float>(pink.x, pink.y, pink.z, alpha)
            add(frame.upperLip.map { SIMD3<Double>($0.x, $0.y, level * k) }, color, 1.1)
            add(frame.lowerLip.map { SIMD3<Double>($0.x, $0.y, level * k) }, color, 1.1)
        }

        let outputLevel = Float(min(1, max(0, telemetry.outRMS * 3.5)))
        let gateLevel = Float(min(1, max(0, telemetry.gate)))
        let voicingLevel = Float(min(1, max(0, telemetry.voicing)))
        let activity = max(outputLevel, gateLevel * 0.45, voicingLevel * 0.35)
        add(
            frame.grid.map { SIMD3<Double>($0.mid.x, $0.mid.y, 0) },
            SIMD4<Float>(1, 0.5 + activity * 0.35, 0.08, 0.18 + activity * 0.82),
            0.8 + activity * 2.2
        )
        for (index, sample) in frame.grid.enumerated() {
            let dx = sample.outer.x - sample.inner.x
            let dy = sample.outer.y - sample.inner.y
            let gap = max(0.001, hypot(dx, dy))
            let a = gap * 0.5
            let b = min(4 * k, max(0.008, sample.area / (Double.pi * a)))
            let normal = SIMD3<Double>(dx / gap, dy / gap, 0)
            let center = SIMD3<Double>(sample.mid.x, sample.mid.y, 0)
            let pressure = index < telemetry.pressure.count ? telemetry.pressure[index] : 0
            let heat = Float(min(1, max(0, pressure / 900))) * 0.55 + activity * 0.45
            let color = SIMD4<Float>(1, 0.3 + heat * 0.55, 0.06, 0.1 + heat * 0.9)
            let points = (0...24).map { ringIndex in
                let angle = Double(ringIndex) / 24 * 2 * Double.pi
                return center + normal * (a * cos(angle)) + SIMD3<Double>(0, 0, b * sin(angle))
            }
            add(points, color, 0.7 + heat * 3.4)
        }

        let glottis = frame.glottis
        let opening = 0.45 + 0.25 * min(1, telemetry.voicing)
        for ring in 0..<3 {
            let ringLevel = activity * (1 - Float(ring) * 0.22)
            ellipse(
                SIMD3<Double>(glottis.x, glottis.y, 0),
                SIMD3<Double>((opening + Double(ring) * 0.28) * k, 0, 0),
                SIMD3<Double>(0, 0, (0.55 + Double(ring) * 0.22) * k),
                SIMD4<Float>(1, 0.48 + ringLevel * 0.4, 0.08, 0.18 + ringLevel * 0.82)
            )
        }
        for index in 0...4 {
            ellipse(
                SIMD3<Double>(glottis.x, glottis.y - Double(index) * 0.9 * k, 0),
                SIMD3<Double>(0.85 * k, 0, 0),
                SIMD3<Double>(0, 0, 0.8 * k),
                dim,
                segments: 24
            )
        }
        return scene
    }

    static func headSections() -> [HeadSection] {
        [
            HeadSection(y: -4.6, front: 2.3, back: -6.6, width: 5.3),
            HeadSection(y: -2, front: 2.4, back: -6.6, width: 5.35),
            HeadSection(y: 0, front: 2.5, back: -6.6, width: 5.4),
            HeadSection(y: 3, front: 5.3, back: -6.6, width: 5.5),
            HeadSection(y: 5, front: 7.5, back: -6.7, width: 5.4),
            HeadSection(y: 8, front: 6.35, back: -7, width: 6),
            HeadSection(y: 10, front: 6.6, back: -7.5, width: 6.5),
            HeadSection(y: 11.6, front: 9.25, back: -8, width: 6.9),
            HeadSection(y: 14, front: 8.1, back: -8.4, width: 7.1),
            HeadSection(y: 16, front: 7.95, back: -8.4, width: 7.45),
            HeadSection(y: 18, front: 7.8, back: -8.1, width: 7.65),
            HeadSection(y: 20, front: 6.5, back: -6.5, width: 7.2),
            HeadSection(y: 22, front: 2.8, back: -3.2, width: 4.8),
            HeadSection(y: 23, front: 0, back: 0, width: 0.3)
        ]
    }

    static func interpolateHead(_ sections: [HeadSection], y: Double) -> HeadSection? {
        guard let first = sections.first, let last = sections.last, y >= first.y, y <= last.y else { return nil }
        for index in 1..<sections.count {
            let upper = sections[index]
            if y <= upper.y {
                let lower = sections[index - 1]
                let t = (y - lower.y) / (upper.y - lower.y)
                return HeadSection(
                    y: y,
                    front: lower.front + (upper.front - lower.front) * t,
                    back: lower.back + (upper.back - lower.back) * t,
                    width: lower.width + (upper.width - lower.width) * t
                )
            }
        }
        return last
    }
}
