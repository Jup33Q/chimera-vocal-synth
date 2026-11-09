import SwiftUI
import simd

enum BodyPalette {
    static let male = SIMD3<Float>(0.12, 0.58, 1)
    static let female = SIMD3<Float>(1, 0.24, 0.28)
    static let child = SIMD3<Float>(0.22, 1, 0.58)

    static func rgb(_ body: BodyMix) -> SIMD3<Float> {
        let childWeight = min(1, max(0, Float(body.child)))
        let femaleWeight = (1 - childWeight) * min(1, max(0, Float(body.female)))
        let maleWeight = 1 - childWeight - femaleWeight
        return male * maleWeight + female * femaleWeight + child * childWeight
    }

    static func color(_ body: BodyMix) -> Color {
        let value = rgb(body)
        return Color(red: Double(value.x), green: Double(value.y), blue: Double(value.z))
    }

    static func vector(_ body: BodyMix, alpha: Float = 1) -> SIMD4<Float> {
        let value = rgb(body)
        return SIMD4<Float>(value.x, value.y, value.z, alpha)
    }
}
