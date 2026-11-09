import SwiftUI

struct ChimeraBeatboxView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            BeatboxHeader(model: model)
            if let error = model.lastError {
                BeatboxErrorBanner(message: error) { model.lastError = nil }
            }
            ScrollView {
                VStack(spacing: 12) {
                    if let catalog = model.catalog {
                        BeatboxSequencer(model: model, sounds: catalog.beatSounds)
                        BeatboxPads(model: model, sounds: catalog.beatSounds)
                        BeatboxTransport(model: model, presets: catalog.beatPresets)
                    } else {
                        ProgressView("Preparing shared engine")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.visible)
            BeatboxTelemetry(model: model)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task { model.prepare() }
    }
}

private struct BeatboxHeader: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 12) {
            Text("CHIMERA BEATBOX")
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
        }
    }
}

private struct BeatboxErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Phosphor.red)
            Spacer()
            Button("Dismiss", action: dismiss).foregroundStyle(Phosphor.red)
        }
    }
}

private struct BeatboxSequencer: View {
    @ObservedObject var model: InstrumentModel
    let sounds: [BeatSound]

    var body: some View {
        Screen(title: "STEP SEQUENCER", subtitle: "\(model.beatPlaying ? "RUNNING" : "STOPPED") / \(Int(model.beatBPM)) BPM") {
            VStack(spacing: 5) {
                ForEach(sounds) { sound in
                    HStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Text(sound.id)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Phosphor.white)
                                .frame(width: 28, alignment: .leading)
                            Text(sound.name.uppercased())
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 142, alignment: .leading)
                        HStack(spacing: 3) {
                            ForEach(model.beatSteps.indices, id: \.self) { index in
                                BeatboxStepCell(
                                    soundID: sound.id,
                                    stepID: model.beatSteps[index]?.id,
                                    playhead: index == model.beatPlayhead,
                                    downbeat: index % 4 == 0,
                                    action: {
                                        model.selectedBeatSound = sound.id
                                        model.toggleBeatStep(index)
                                    }
                                )
                                .accessibilityLabel("\(sound.name), step \(index + 1)")
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text("STEP").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 142, alignment: .leading)
                    HStack(spacing: 3) {
                        ForEach(model.beatSteps.indices, id: \.self) { index in
                            Text("\(index + 1)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(index == model.beatPlayhead ? Phosphor.green : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct BeatboxStepCell: View {
    let soundID: String
    let stepID: String?
    let playhead: Bool
    let downbeat: Bool
    let action: () -> Void

    private var active: Bool { stepID == soundID }

    var body: some View {
        Button(action: action) {
            Text(active ? "X" : "")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? Phosphor.amber : .secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Color.black)
                .overlay(
                    Rectangle().stroke(
                        playhead ? Phosphor.green : active ? Phosphor.amber : Phosphor.blue.opacity(downbeat ? 0.72 : 0.3),
                        lineWidth: playhead ? 2 : 1
                    )
                )
                .shadow(color: active ? Phosphor.amber.opacity(0.32) : .clear, radius: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct BeatboxTransport: View {
    @ObservedObject var model: InstrumentModel
    let presets: [BeatPreset]

    var body: some View {
        Screen(title: "TRANSPORT", subtitle: "HEAD CLOCK") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Chip(title: model.beatPlaying ? "Stop" : "Play beat", selected: model.beatPlaying, color: Phosphor.green) {
                        model.setBeatPlaying(!model.beatPlaying)
                    }
                    Chip(title: "Stop all", color: Phosphor.red) { model.stopAll() }
                    Spacer()
                    Text("16 STEPS / REAL HEAD TRANSPORT")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    RotaryKnob(label: "Tempo", value: $model.beatBPM, range: 50...180, unit: "BPM", color: Phosphor.green) { String(Int($0.rounded())) }
                    RotaryKnob(label: "Swing", value: $model.beatSwing, range: 0...0.7, unit: "%", color: Phosphor.red) { String(Int(($0 * 100).rounded())) }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(presets) { preset in
                            Chip(title: preset.name, color: Phosphor.blue) { model.loadBeatPreset(preset) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("BEAT AS TEXT")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("B . t . | Pf . t .", text: Binding(
                        get: { model.beatText },
                        set: { model.applyBeatText($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Phosphor.amber)
                    .padding(8)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Phosphor.blue.opacity(0.4)))
                    .accessibilityLabel("Beat as text. Edits update the sixteen-step matrix immediately.")
                    Text("B kick · t hat · Pf snare · K rimshot · ^K inward · ! click · m:43 hum · . rest · > accent")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BeatboxPads: View {
    @ObservedObject var model: InstrumentModel
    let sounds: [BeatSound]

    var body: some View {
        Screen(title: "PADS", subtitle: "KEYS 1–0 / PRESS TO HIT") {
            BeatboxKeyMonitor(sounds: sounds, onHit: model.beatHit)
                .frame(width: 0, height: 0)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(sounds.indices, id: \.self) { index in
                    let sound = sounds[index]
                    VStack(alignment: .leading) {
                        Text(sound.name).font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("\(key(for: sound)) / \(sound.id.uppercased())")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(7)
                    .background(Color.black)
                    .overlay(Rectangle().stroke(Phosphor.pink.opacity(0.55)))
                    .contentShape(Rectangle())
                    .overlay(MousePressTarget(onPress: { model.beatHit(sound.id) }, onRelease: {}))
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Play \(sound.name), key \(key(for: sound))")
                    .accessibilityAction { model.beatHit(sound.id) }
                    .help(sound.hint)
                }
            }
        }
    }

    private func key(for sound: BeatSound) -> String {
        if sound.id == "m" { return "0" }
        guard let index = sounds.firstIndex(where: { $0.id == sound.id }), index < 9 else { return "·" }
        return String(index + 1)
    }
}

private struct BeatboxKeyMonitor: NSViewRepresentable {
    let sounds: [BeatSound]
    let onHit: (String) -> Void

    final class Coordinator {
        var monitor: Any?
        var sounds: [BeatSound] = []
        var onHit: (String) -> Void = { _ in }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.sounds = sounds
        coordinator.onHit = onHit
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak coordinator] event in
            guard let view, let coordinator, view.window != nil, NSApp.keyWindow == view.window else { return event }
            if event.isARepeat || !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return event }
            if view.window?.firstResponder is NSTextView || view.window?.firstResponder is NSTextField { return event }
            guard let key = event.charactersIgnoringModifiers, key.count == 1 else { return event }
            let id: String?
            if key == "0" {
                id = "m"
            } else if let number = Int(key), (1...9).contains(number), number <= coordinator.sounds.count {
                id = coordinator.sounds[number - 1].id
            } else {
                id = nil
            }
            guard let id else { return event }
            coordinator.onHit(id)
            return nil
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.sounds = sounds
        context.coordinator.onHit = onHit
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
}

private struct BeatboxTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 24) {
            BeatboxReadout(label: "PLAYHEAD", value: model.beatPlayhead >= 0 ? "\(model.beatPlayhead + 1)" : "—")
            BeatboxReadout(label: "GATE", value: String(format: "%.3f", model.telemetry.gate))
            BeatboxReadout(label: "OUT RMS", value: String(format: "%.3f", model.telemetry.outRMS))
            Spacer()
            Text("HEAD OWNS AUDIO / NDJSON TELEMETRY")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct BeatboxReadout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(Phosphor.amber)
        }
    }
}
