import SwiftUI

struct ChimeraGenderAgeView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            GenderAgeHeader(model: model)
            if let error = model.lastError {
                GenderAgeError(message: error) { model.lastError = nil }
            }
            HStack(spacing: 12) {
                BodyPaletteView(model: model)
                VoiceControlPanel(model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GenderAgeTelemetry(model: model)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task { model.prepare() }
    }
}

private struct GenderAgeHeader: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 12) {
            Text("CHIMERA GENDER AGE")
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Phosphor.blue)
            Text(model.headConnected ? "HEAD CONNECTED" : "HEAD OFFLINE")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.headConnected ? Phosphor.green : Phosphor.red)
            Spacer()
            Text("MCP 127.0.0.1:\(model.mcpPort)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Phosphor.blue)
                .textSelection(.enabled)
            Chip(title: "Start", color: Phosphor.green) { model.startAudio() }
            Chip(title: "Stop all", color: Phosphor.red) { model.stopAll() }
        }
    }
}

private struct GenderAgeError: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(message).font(.system(size: 11, design: .monospaced)).foregroundStyle(Phosphor.red)
            Spacer()
            Button("Dismiss", action: dismiss).foregroundStyle(Phosphor.red)
        }
    }
}

private struct VoiceControlPanel: View {
    @ObservedObject var model: InstrumentModel
    @State private var page = 0
    private let pages = ["VOICE", "TONE", "PITCH", "MOUTH", "TONGUE", "THROAT"]

    var body: some View {
        Screen(title: "VOICE", subtitle: model.whisperEnabled ? "WHISPER ALL CONTROLS / HEAD" : "HEAD SOURCE + ARTICULATION") {
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Chip(title: "Hold breath", selected: model.hold, color: Phosphor.amber) { model.hold.toggle() }
                    Chip(title: "Whisper", selected: model.whisperEnabled, color: Phosphor.pink) { model.setWhisper(!model.whisperEnabled) }
                }
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Chip(title: pages[index], selected: page == index, color: Phosphor.blue) { page = index }
                    }
                }
                VoicePage(model: model, page: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VoicePage: View {
    @ObservedObject var model: InstrumentModel
    let page: Int

    var body: some View {
        switch page {
        case 0:
            HStack {
                RotaryKnob(label: "Pitch", value: $model.source.f0, range: 40...1_100, unit: "Hz \(noteName(model.source.f0))", color: Phosphor.green, logarithmic: true) { String(Int($0.rounded())) }
                RotaryKnob(label: "Breath", value: $model.source.pressure, range: 2...22, unit: "cmH₂O", color: Phosphor.red) { String(format: "%.1f", $0) }
                RotaryKnob(label: "Pressed", value: $model.source.tension, range: 0...1, unit: "%", color: Phosphor.pink) { String(Int(($0 * 100).rounded())) }
                RotaryKnob(label: "Vibrato", value: $model.source.vibratoDepth, range: 0...120, unit: "cents", color: Phosphor.white) { String(Int($0.rounded())) }
            }
        case 1:
            HStack {
                RotaryKnob(label: "Bright", value: $model.source.brightness, range: 0...1, unit: "%", color: Phosphor.green, format: percent)
                RotaryKnob(label: "Breathy", value: $model.source.breathiness, range: 0...1, unit: "%", color: Phosphor.red, format: percent)
                RotaryKnob(label: "Rough", value: $model.source.roughness, range: 0...1, unit: "%", color: Phosphor.pink, format: percent)
                RotaryKnob(label: "Fry", value: $model.source.fry, range: 0...1, unit: "%", color: Phosphor.white, format: percent)
            }
        case 2:
            HStack {
                RotaryKnob(label: "Glide", value: $model.source.glide, range: 0.005...0.6, unit: "ms", color: Phosphor.green, logarithmic: true) { String(Int(($0 * 1_000).rounded())) }
                Spacer()
            }
        case 3:
            HStack {
                RotaryKnob(label: "Rounding", value: $model.lipRounding, range: 0...1, unit: "%", color: Phosphor.green, format: percent)
                RotaryKnob(label: "Lips open", value: $model.artic.lipAp, range: -0.3...2.2, unit: "cm", color: Phosphor.red, format: centimeters)
                RotaryKnob(label: "Protrude", value: $model.artic.lipProt, range: -0.1...1.4, unit: "cm", color: Phosphor.pink, format: centimeters)
                RotaryKnob(label: "Jaw", value: $model.artic.jaw, range: 0...2.4, unit: "cm", color: Phosphor.white, format: centimeters)
            }
        case 4:
            HStack {
                RotaryKnob(label: "Root", value: $model.artic.root, range: -0.9...0.9, unit: "cm", color: Phosphor.green, format: signedCentimeters)
                RotaryKnob(label: "Tip curl", value: $model.artic.ttCurl, range: 0...1, unit: "%", color: Phosphor.pink, format: percent)
                Spacer()
            }
        default:
            HStack {
                RotaryKnob(label: "Soft palate", value: $model.artic.velum, range: -0.25...1.2, unit: "cm²", color: Phosphor.green) { $0 <= 0 ? "Shut" : String(format: "%.2f", $0) }
                RotaryKnob(label: "Larynx", value: $model.artic.larynx, range: -1.5...1.5, unit: "cm", color: Phosphor.red, format: signedCentimeters)
                RotaryKnob(label: "Twang", value: $model.artic.epilarynx, range: 0...1, unit: "%", color: Phosphor.pink, format: percent)
                RotaryKnob(label: "False folds", value: $model.artic.ventricular, range: 0...1, unit: "%", color: Phosphor.white, format: percent)
            }
        }
    }
}

private struct GenderAgeTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 24) {
            Text(String(format: "F0 %.1f HZ", model.telemetry.f0))
            Text(String(format: "GATE %.3f", model.telemetry.gate))
            Text(String(format: "OUT RMS %.3f", model.telemetry.outRMS))
            Spacer()
            Text("HEAD OWNS AUDIO / CONTINUOUS BODY MIX")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Phosphor.amber)
    }
}

private extension InstrumentModel {
    var lipRounding: Double {
        get { 1 - artic.lipWidth }
        set { artic.lipWidth = 1 - newValue }
    }
}

private func percent(_ value: Double) -> String { String(Int((value * 100).rounded())) }
private func centimeters(_ value: Double) -> String { String(format: "%.1f", value) }
private func signedCentimeters(_ value: Double) -> String { String(format: "%@%.1f", value >= 0 ? "+" : "", value) }

private func noteName(_ frequency: Double) -> String {
    let notes = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    let midi = Int((69 + 12 * log2(frequency / 440)).rounded())
    return "\(notes[((midi % 12) + 12) % 12])\(midi / 12 - 1)"
}
