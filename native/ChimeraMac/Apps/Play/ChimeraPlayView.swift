import SwiftUI

struct ChimeraPlayView: View {
    @EnvironmentObject private var model: InstrumentModel
    @StateObject private var midi = MIDIInputController(clientName: "Chimera Play")

    var body: some View {
        VStack(spacing: 12) {
            PlayHeader(model: model)
            if let error = model.lastError {
                PlayErrorBanner(message: error) { model.lastError = nil }
            }
            ScrollView {
                PlayControls(model: model, midi: midi)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.visible)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task {
            midi.onNoteOn = { note in model.noteOn(note) }
            midi.onNoteOff = { note in model.noteOff(note) }
            model.prepare()
        }
        .onDisappear { midi.stop() }
    }
}

private struct PlayHeader: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 12) {
            Text("CHIMERA PLAY")
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Phosphor.blue)
            Text(model.isStarted ? "HEAD AUDIO ONLINE / 48 KHZ" : "HEAD AUDIO STANDBY")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.isStarted ? Phosphor.green : Phosphor.amber)
            Spacer()
            Text(model.headConnected ? "HEAD CONNECTED" : "HEAD OFFLINE")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.headConnected ? Phosphor.green : Phosphor.red)
            Text("MCP 127.0.0.1:\(model.mcpPort)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Phosphor.blue)
                .textSelection(.enabled)
            Chip(title: "Start", color: Phosphor.green) { model.startAudio() }
            Chip(title: "Stop", color: Phosphor.red) { model.stopAll() }
        }
    }
}

private struct PlayErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Phosphor.red)
            Spacer()
            Button("Dismiss", action: dismiss)
                .foregroundStyle(Phosphor.red)
        }
    }
}

private struct PlayControls: View {
    @ObservedObject var model: InstrumentModel
    @ObservedObject var midi: MIDIInputController

    var body: some View {
        VStack(spacing: 12) {
            Screen(title: "VOICE", subtitle: "SOURCE PARAMETERS") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    InstrumentSlider(label: "Pitch", value: $model.source.f0, range: 40...1_100, unit: " Hz", color: Phosphor.green)
                    InstrumentSlider(label: "Pressure", value: $model.source.pressure, range: 2...22, unit: " cmH₂O", color: Phosphor.red)
                    InstrumentSlider(label: "Breathiness", value: $model.source.breathiness, range: 0...1, color: Phosphor.pink)
                    InstrumentSlider(label: "Tension", value: $model.source.tension, range: 0...1, color: Phosphor.white)
                    InstrumentSlider(label: "Vibrato", value: $model.source.vibratoDepth, range: 0...120, unit: " ct", color: Phosphor.green)
                    InstrumentSlider(label: "Vibrato rate", value: $model.source.vibratoRate, range: 2...8, unit: " Hz", color: Phosphor.red)
                }
            }
            VowelMapView()
            Screen(title: "MOUTH", subtitle: "ARTICULATORS") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    InstrumentSlider(label: "Jaw", value: $model.artic.jaw, range: -0.2...3, color: Phosphor.red)
                    InstrumentSlider(label: "Lip aperture", value: $model.artic.lipAp, range: -0.5...3, color: Phosphor.pink)
                    InstrumentSlider(label: "Lip protrusion", value: $model.artic.lipProt, range: -1...2, color: Phosphor.pink)
                    InstrumentSlider(label: "Velum", value: $model.artic.velum, range: 0...1, color: Phosphor.white)
                    InstrumentSlider(label: "Tongue X", value: $model.artic.tbX, range: -2...8, color: Phosphor.green)
                    InstrumentSlider(label: "Tongue Y", value: $model.artic.tbY, range: 1...15, color: Phosphor.green)
                }
            }
            Screen(title: "KEYS", subtitle: "HOLD A NOTE") {
                VStack(spacing: 10) {
                    HStack {
                        Spacer()
                        InstrumentSlider(label: "Volume", value: $model.volume, range: 0...1, color: Phosphor.amber)
                            .frame(width: 220)
                    }
                    MIDIInputView(midi: midi)
                    PianoKeys(heldNotes: model.heldNotes, onNoteOn: model.noteOn, onNoteOff: model.noteOff)
                }
            }
            PlayTelemetry(model: model)
        }
    }
}

private struct PlayTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        Screen(title: "LIVE TELEMETRY", subtitle: "30 HZ ACOUSTICS / 10 HZ GEOMETRY") {
            HStack(spacing: 28) {
                PlayReadout(label: "F0 HZ", value: model.telemetry.f0)
                PlayReadout(label: "GATE", value: model.telemetry.gate)
                PlayReadout(label: "OUT RMS", value: model.telemetry.outRMS)
                PlayReadout(label: "LUNG", value: model.telemetry.lungPressure)
                Spacer()
            }
        }
    }
}

private struct PlayReadout: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Phosphor.amber)
        }
    }
}
