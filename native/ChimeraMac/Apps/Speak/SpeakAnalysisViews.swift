import SwiftUI

private struct ScoreRow {
    let name: String
    let keys: Set<String>
    let color: Color
}

private let scoreRows = [
    ScoreRow(name: "LIPS", keys: ["lipAp", "lipProt", "lipWidth", "labiodental"], color: Phosphor.pink),
    ScoreRow(name: "TONGUE TIP", keys: ["ttX", "ttY", "ttCurl", "lateral"], color: Phosphor.green),
    ScoreRow(name: "TONGUE BODY", keys: ["tbX", "tbY", "root"], color: Phosphor.green),
    ScoreRow(name: "SOFT PALATE", keys: ["velum"], color: Phosphor.white),
    ScoreRow(name: "GLOTTIS", keys: ["abduction", "closure"], color: Phosphor.amber)
]

struct GesturalScoreView: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        Screen(title: "GESTURAL SCORE", subtitle: "ARTICULATORY PHONOLOGY") {
            Canvas { context, size in
                let left = 108.0
                let right = size.width - 14
                let top = 18.0
                let bottom = size.height - 30
                let rowHeight = (bottom - top) / 6
                let now = model.telemetry.clock - model.speechPlanOffset
                let end = model.speechPlanEnd + 0.15
                let x: (Double) -> Double = { time in
                    left + ((time + 0.05) / max(0.01, end + 0.05)) * (right - left)
                }

                for (index, row) in scoreRows.enumerated() {
                    drawLabel(context, row.name, at: CGPoint(x: 12, y: top + rowHeight * (Double(index) + 0.62)), color: row.color, size: 9, anchor: .leading)
                }
                drawLabel(context, "PITCH", at: CGPoint(x: 12, y: top + rowHeight * 5.62), color: Phosphor.amber, size: 9, anchor: .leading)
                for index in 1...6 {
                    var rule = Path()
                    let y = top + rowHeight * Double(index)
                    rule.move(to: CGPoint(x: left, y: y))
                    rule.addLine(to: CGPoint(x: right, y: y))
                    context.stroke(rule, with: .color(Phosphor.blue.opacity(0.4)), lineWidth: 1)
                }

                guard !model.speechGestures.isEmpty, right > left else {
                    drawLabel(context, "SPEAK SOMETHING TO SEE ITS GESTURES AND THEIR OVERLAP.", at: CGPoint(x: (left + right) / 2, y: (top + bottom) / 2), color: Phosphor.blue, size: 10)
                    return
                }

                var pitches: [(time: Double, f0: Double)] = []
                for gesture in model.speechGestures {
                    if let f0 = gesture.targets["f0"] {
                        pitches.append(((gesture.t0 + gesture.t1) / 2, f0))
                        continue
                    }
                    guard let row = scoreRow(gesture) else { continue }
                    let rowIndex = scoreRows.firstIndex { $0.name == row.name } ?? 0
                    let baseline = top + rowHeight * (Double(rowIndex) + 1) - 3
                    let target = top + rowHeight * Double(rowIndex) + 7
                    let x0 = x(gesture.t0 - gesture.rampIn)
                    let xa = x(gesture.t0)
                    let xb = x(gesture.t1)
                    let x1 = x(gesture.t1 + gesture.rampOut)
                    let active = now >= gesture.t0 - gesture.rampIn && now <= gesture.t1 + gesture.rampOut
                    var trapezoid = Path()
                    trapezoid.move(to: CGPoint(x: x0, y: baseline))
                    trapezoid.addLine(to: CGPoint(x: xa, y: target))
                    trapezoid.addLine(to: CGPoint(x: xb, y: target))
                    trapezoid.addLine(to: CGPoint(x: x1, y: baseline))
                    context.stroke(trapezoid, with: .color(row.color.opacity(active ? 1 : 0.72)), lineWidth: active ? 1.8 : 1.1)
                    if let label = gesture.label, xb - xa > 10 {
                        let text = label == "aspiration" || label == "voiceless" ? "OPEN" : label == "velum" ? "LOWERED" : label
                        drawLabel(context, text, at: CGPoint(x: (xa + xb) / 2, y: baseline - 4), color: row.color, size: 10)
                    }
                }

                pitches.sort { $0.time < $1.time }
                if let minimum = pitches.map(\.f0).min(), let maximum = pitches.map(\.f0).max() {
                    let lower = minimum * 0.92
                    let upper = maximum * 1.08
                    let baseline = top + rowHeight * 6 - 4
                    let target = top + rowHeight * 5 + 6
                    var contour = Path()
                    for (index, pitch) in pitches.enumerated() {
                        let point = CGPoint(
                            x: x(pitch.time),
                            y: baseline - ((pitch.f0 - lower) / max(1, upper - lower)) * (baseline - target)
                        )
                        if index == 0 { contour.move(to: point) } else { contour.addLine(to: point) }
                    }
                    context.stroke(contour, with: .color(Phosphor.amber), lineWidth: 1.4)
                    if let last = pitches.last {
                        let y = baseline - ((last.f0 - lower) / max(1, upper - lower)) * (baseline - target)
                        drawLabel(context, "\(Int(last.f0.rounded())) HZ", at: CGPoint(x: x(last.time) + 7, y: y + 3), color: Phosphor.amber, size: 9, anchor: .leading)
                    }
                }

                var lastRight = -Double.infinity
                for segment in model.speechSegments {
                    let center = x((segment.t0 + segment.t1) / 2)
                    guard center - 6 >= lastRight else { continue }
                    lastRight = center + 6
                    var tick = Path()
                    tick.move(to: CGPoint(x: x(segment.t0), y: bottom + 2))
                    tick.addLine(to: CGPoint(x: x(segment.t0), y: bottom + 6))
                    context.stroke(tick, with: .color(Phosphor.blue.opacity(0.6)), lineWidth: 1)
                    let active = now >= segment.t0 && now < segment.t1
                    drawLabel(context, segment.ipa, at: CGPoint(x: center, y: size.height - 8), color: active ? Phosphor.white : Phosphor.blue, size: 12)
                }

                if now >= -0.05, now <= end {
                    var playhead = Path()
                    playhead.move(to: CGPoint(x: x(now), y: top - 4))
                    playhead.addLine(to: CGPoint(x: x(now), y: bottom))
                    context.stroke(playhead, with: .color(Phosphor.white), lineWidth: 1.2)
                    drawLabel(context, String(format: "%.2f S", max(0, now)), at: CGPoint(x: x(now) + 8, y: top - 4), color: Phosphor.white, size: 9, anchor: .leading)
                }
            }
            .frame(minHeight: 280, idealHeight: 320)
            .accessibilityLabel("Gestural score of the current utterance")
        }
    }

    private func scoreRow(_ gesture: Gesture) -> ScoreRow? {
        let keys = Set(gesture.targets.keys)
        if keys.contains("tbX") && keys.contains("lipAp") && keys.count > 4 { return scoreRows[2] }
        if keys.contains("ttX") || keys.contains("ttCurl") { return scoreRows[1] }
        return scoreRows.first { !$0.keys.isDisjoint(with: keys) }
    }

    private func drawLabel(_ context: GraphicsContext, _ text: String, at point: CGPoint, color: Color, size: Double, anchor: UnitPoint = .center) {
        context.draw(Text(text).font(.system(size: size, design: .monospaced)).foregroundStyle(color), at: point, anchor: anchor)
    }
}

private let consonantPlaces = ["BILAB", "LABDENT", "DENTAL", "ALVEOL", "POSTALV", "RETROFL", "PALATAL", "VELAR", "UVULAR", "PHARYN", "GLOTTAL"]
private let consonantRows: [(manner: String, cells: [[String?]])] = [
    ("PLOSIVE", [["p", "b"], [nil, nil], [nil, nil], ["t", "d"], [nil, nil], ["ʈ", "ɖ"], ["c", "ɟ"], ["k", "g"], ["q", "ɢ"], [nil, nil], ["ʔ", nil]]),
    ("NASAL", [[nil, "m"], [nil, "ɱ"], [nil, nil], [nil, "n"], [nil, nil], [nil, "ɳ"], [nil, "ɲ"], [nil, "ŋ"], [nil, "ɴ"], [nil, nil], [nil, nil]]),
    ("TRILL", [[nil, "ʙ"], [nil, nil], [nil, nil], [nil, "r"], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, "ʀ"], [nil, nil], [nil, nil]]),
    ("TAP", [[nil, nil], [nil, nil], [nil, nil], [nil, "ɾ"], [nil, nil], [nil, "ɽ"], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil]]),
    ("FRICATIVE", [["ɸ", "β"], ["f", "v"], ["θ", "ð"], ["s", "z"], ["ʃ", "ʒ"], ["ʂ", "ʐ"], ["ç", "ʝ"], ["x", "ɣ"], ["χ", "ʁ"], ["ħ", "ʕ"], ["h", "ɦ"]]),
    ("LAT FRIC", [[nil, nil], [nil, nil], [nil, nil], ["ɬ", "ɮ"], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil]]),
    ("APPROX", [[nil, nil], [nil, "ʋ"], [nil, nil], [nil, "ɹ"], [nil, nil], [nil, "ɻ"], [nil, "j"], [nil, "ɰ"], [nil, nil], [nil, nil], [nil, nil]]),
    ("LATERAL", [[nil, nil], [nil, nil], [nil, nil], [nil, "l"], [nil, nil], [nil, "ɭ"], [nil, "ʎ"], [nil, nil], [nil, nil], [nil, nil], [nil, nil]])
]

struct ConsonantChartView: View {
    @ObservedObject var model: InstrumentModel
    @State private var vowel = "ɑ"

    private var currentIPA: String? {
        let now = model.telemetry.clock - model.speechPlanOffset
        return model.speechSegments.first { now >= $0.t0 && now < $0.t1 }?.ipa
    }

    var body: some View {
        Screen(title: "CONSONANTS", subtitle: "BETWEEN TWO VOWELS") {
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    ForEach(["ɑ", "i", "u", "ə"], id: \.self) { item in
                        Chip(title: item, selected: vowel == item, color: Phosphor.blue) { vowel = item }
                    }
                }
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("").frame(width: 92)
                            ForEach(consonantPlaces, id: \.self) { place in
                                Text(place)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 78, height: 32)
                            }
                        }
                        ForEach(consonantRows, id: \.manner) { row in
                            HStack(spacing: 0) {
                                Text(row.manner)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 92, alignment: .leading)
                                ForEach(0..<consonantPlaces.count, id: \.self) { index in
                                    HStack(spacing: 0) {
                                        ForEach(0..<2, id: \.self) { symbolIndex in
                                            if let symbol = row.cells[index][symbolIndex] {
                                                Button {
                                                    model.speakConsonant(symbol, vowel: vowel)
                                                } label: {
                                                    Text(symbol)
                                                        .font(.system(size: 16, design: .monospaced))
                                                        .foregroundStyle(symbol == currentIPA ? Phosphor.white : Phosphor.blue)
                                                        .frame(width: 38, height: 32)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Say \(symbol) between two vowels")
                                            } else {
                                                Text("").frame(width: 38, height: 32)
                                            }
                                        }
                                    }
                                    .frame(width: 78, height: 34)
                                    .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.35)))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.visible)
            }
        }
    }
}
