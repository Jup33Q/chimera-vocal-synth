import Foundation

struct VowelPoint {
    let ipa: String
    let example: String
    let f1: Double
    let f2: Double
    let artic: [String: Double]
}

struct VowelSpace {
    let points: [VowelPoint]
    let f1Range: ClosedRange<Double>
    let f2Range: ClosedRange<Double>

    init(catalog: VoiceCatalog, body: BodyMix) {
        let female = min(1, max(0, body.female))
        let child = min(1, max(0, body.child))
        let parts = [
            ("male", (1 - child) * (1 - female)),
            ("female", (1 - child) * female),
            ("child", child)
        ].filter { $0.1 > 0 }

        func blendLog(_ male: Double, _ female: Double, _ child: Double) -> Double {
            let values = [male, female, child]
            return exp(parts.reduce(0) { result, part in
                let index = part.0 == "male" ? 0 : part.0 == "female" ? 1 : 2
                return result + part.1 * log(values[index])
            })
        }

        f1Range = blendLog(230, 280, 300)...blendLog(950, 1_150, 1_250)
        f2Range = blendLog(700, 800, 900)...blendLog(2_700, 3_200, 3_500)

        var blended: [VowelPoint] = []
        for reference in catalog.vowels {
            var f1 = 0.0
            var f2 = 0.0
            var artic: [String: Double] = [:]
            var complete = true
            for (name, weight) in parts {
                guard let target = catalog.vowelTargets[name]?[reference.ipa], target.formants.count >= 2 else {
                    complete = false
                    break
                }
                f1 += weight * target.formants[0]
                f2 += weight * target.formants[1]
                for (key, value) in target.artic {
                    artic[key] = (artic[key] ?? 0) + weight * value
                }
            }
            if complete {
                blended.append(VowelPoint(ipa: reference.ipa, example: reference.example, f1: f1, f2: f2, artic: artic))
            }
        }
        points = blended
    }

    func formants(x: Double, y: Double) -> (f1: Double, f2: Double) {
        let x = min(1, max(0, x))
        let y = min(1, max(0, y))
        let f2 = exp(log(f2Range.upperBound) - x * log(f2Range.upperBound / f2Range.lowerBound))
        let f1 = exp(log(f1Range.lowerBound) + y * log(f1Range.upperBound / f1Range.lowerBound))
        return (f1, f2)
    }

    func unitPoint(f1: Double, f2: Double) -> (x: Double, y: Double) {
        (
            log(f2Range.upperBound / f2) / log(f2Range.upperBound / f2Range.lowerBound),
            log(f1 / f1Range.lowerBound) / log(f1Range.upperBound / f1Range.lowerBound)
        )
    }

    func articulation(x: Double, y: Double, base: HumanArtic) -> HumanArtic {
        let formants = formants(x: x, y: y)
        let weighted = points.map { point in
            let d1 = log(formants.f1 / point.f1) * 2.2
            let d2 = log(formants.f2 / point.f2)
            let distance = hypot(d1, d2)
            return (point, 1 / pow(distance + 0.02, 3))
        }
        .sorted { $0.1 > $1.1 }
        .prefix(4)
        let total = weighted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return base }

        var result = base
        let paths: [String: WritableKeyPath<HumanArtic, Double>] = [
            "tbX": \.tbX, "tbY": \.tbY, "jaw": \.jaw, "lipAp": \.lipAp,
            "lipProt": \.lipProt, "lipWidth": \.lipWidth, "root": \.root,
            "larynx": \.larynx, "ttCurl": \.ttCurl
        ]
        for (key, path) in paths {
            let fallback = base[keyPath: path]
            let value = weighted.reduce(0.0) { result, item in
                result + (item.0.artic[key] ?? fallback) * item.1
            } / total
            result[keyPath: path] = value
        }
        return result
    }

    func nearest(f1: Double, f2: Double) -> VowelPoint? {
        points.min { a, b in
            let da = hypot(log(f1 / a.f1) * 2.2, log(f2 / a.f2))
            let db = hypot(log(f1 / b.f1) * 2.2, log(f2 / b.f2))
            return da < db
        }
    }
}
