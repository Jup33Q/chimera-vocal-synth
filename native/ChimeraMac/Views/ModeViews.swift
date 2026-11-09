import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            Screen(title: "TRANSFER FUNCTION", subtitle: "60 HZ — 8 KHZ") {
                GeometryReader { geometry in
                    MetalCanvas(scene: SceneFactory.spectrum(model.transfer, size: geometry.size))
                }
            }
            .frame(height: 180)
            Screen(title: "VOCAL FOLDS", subtitle: "AREA / FLOW") {
                GeometryReader { geometry in
                    MetalCanvas(scene: SceneFactory.glottal(model.telemetry, size: geometry.size))
                }
            }
            .frame(height: 130)
            VowelMapView()
            Screen(title: "VOICE", subtitle: "SOURCE PARAMETERS") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    InstrumentSlider(label: "Pitch", value: $model.source.f0, range: 40...1_100, unit: " Hz", color: Phosphor.green)
                    InstrumentSlider(label: "Pressure", value: $model.source.pressure, range: 2...22, unit: " cmH₂O", color: Phosphor.red)
                    InstrumentSlider(label: "Breathiness", value: $model.source.breathiness, range: 0...1, color: Phosphor.pink)
                    InstrumentSlider(label: "Tension", value: $model.source.tension, range: 0...1, color: Phosphor.white)
                    InstrumentSlider(label: "Vibrato", value: $model.source.vibratoDepth, range: 0...120, unit: " ct", color: Phosphor.green)
                    InstrumentSlider(label: "Vibrato rate", value: $model.source.vibratoRate, range: 2...8, unit: " Hz", color: Phosphor.red)
                    InstrumentSlider(label: "Roughness", value: $model.source.roughness, range: 0...1, color: Phosphor.pink)
                    InstrumentSlider(label: "Brightness", value: $model.source.brightness, range: 0...1, color: Phosphor.white)
                }
            }
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
                    Chip(title: model.hold ? "Release breath" : "Hold breath", selected: model.hold, color: Phosphor.amber) { model.hold.toggle() }
                    PianoKeys(heldNotes: model.heldNotes, onNoteOn: model.noteOn, onNoteOff: model.noteOff)
                }
            }
        }
    }
}

struct SpeakView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            Screen(title: "SAY", subtitle: "ENGLISH OR IPA") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $model.speechText)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(Phosphor.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.black)
                        .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.35)))
                        .frame(minHeight: 86)
                    HStack {
                        Chip(title: "IPA input", selected: model.speechUsesIPA, color: Phosphor.pink) { model.speechUsesIPA.toggle() }
                        Spacer()
                        Chip(title: "Speak", color: Phosphor.green) { model.speak() }
                        Chip(title: "Stop", color: Phosphor.red) { model.stopSpeech() }
                    }
                    InstrumentSlider(label: "Speaking rate", value: $model.speechRate, range: 0.5...1.8, unit: "×")
                    OllamaControls(mode: .speak)
                }
            }
            Screen(title: "TRANSCRIPTION", subtitle: "\(model.speechSegments.count) SEGMENTS") {
                ScrollView {
                    Text(model.transcription.isEmpty ? "Phonemes and gestural timing appear here." : model.transcription)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Phosphor.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 70, maxHeight: 130)
            }
            Screen(title: "TRANSFER FUNCTION", subtitle: "ARTICULATORY TARGET") {
                GeometryReader { geometry in
                    MetalCanvas(scene: SceneFactory.spectrum(model.transfer, size: geometry.size))
                }
            }
            .frame(height: 190)
            Screen(title: "VOCAL FOLDS", subtitle: "LIVE SOURCE") {
                GeometryReader { geometry in
                    MetalCanvas(scene: SceneFactory.glottal(model.telemetry, size: geometry.size))
                }
            }
            .frame(height: 140)
        }
    }
}

struct SingView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            Screen(title: "LYRICS", subtitle: "ONE SYLLABLE PER NOTE") {
                VStack(spacing: 10) {
                    TextEditor(text: $model.lyrics)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Phosphor.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.black)
                        .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.35)))
                        .frame(minHeight: 82)
                    HStack {
                        Chip(title: "Apply lyrics", color: Phosphor.green) { model.rebuildSyllables() }
                        Chip(title: "Stop", color: Phosphor.red) { model.stopSinging() }
                        Spacer()
                        Text("NEXT \(model.syllableCursor + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    InstrumentSlider(label: "Vibrato", value: $model.vibrato, range: 0...100, unit: " ct", color: Phosphor.pink)
                    OllamaControls(mode: .sing)
                }
            }
            if let catalog = model.catalog {
                Screen(title: "SONGS", subtitle: model.playingSong ?? "SELECT A SCORE") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(catalog.demoSongs) { song in
                            Chip(title: song.name, selected: model.playingSong == song.name, color: Phosphor.amber) { model.playSong(song) }
                        }
                    }
                }
            }
            Screen(title: "SPECTRUM", subtitle: "RING / FORMANTS") {
                GeometryReader { geometry in
                    MetalCanvas(scene: SceneFactory.spectrum(model.transfer, size: geometry.size))
                }
            }
            .frame(height: 180)
            Screen(title: "SING", subtitle: "PLAY SEQUENTIAL SYLLABLES") {
                PianoKeys(base: 60, heldNotes: model.heldNotes, onNoteOn: model.noteOn, onNoteOff: model.noteOff)
            }
        }
    }
}

struct BeatboxView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            if let catalog = model.catalog {
                Screen(title: "SEQUENCER", subtitle: model.beatPlaying ? "RUNNING" : "STOPPED") {
                    VStack(spacing: 12) {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(catalog.beatPresets) { preset in
                                    Chip(title: preset.name, color: Phosphor.blue) { model.loadBeatPreset(preset) }
                                }
                            }
                        }
                        HStack {
                            Text("SOUND")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Picker("Sound", selection: $model.selectedBeatSound) {
                                ForEach(catalog.beatSounds) { sound in
                                    Text(sound.name).tag(sound.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 5) {
                            ForEach(model.beatSteps.indices, id: \.self) { index in
                                Button {
                                    model.toggleBeatStep(index)
                                } label: {
                                    Text(model.beatSteps[index]?.id.uppercased() ?? "·")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .foregroundStyle(model.beatSteps[index] == nil ? Color.secondary : Color.black)
                                        .background(model.beatSteps[index] == nil ? Color.black : Phosphor.amber)
                                        .overlay(Rectangle().stroke(index == model.beatPlayhead ? Phosphor.green : Phosphor.blue.opacity(0.4), lineWidth: index == model.beatPlayhead ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Chip(title: model.beatPlaying ? "Stop" : "Play", selected: model.beatPlaying, color: Phosphor.green) { model.setBeatPlaying(!model.beatPlaying) }
                            Spacer()
                        }
                    }
                }
                Screen(title: "TRANSPORT", subtitle: "CLOCK") {
                    VStack(spacing: 14) {
                        InstrumentSlider(label: "Tempo", value: $model.beatBPM, range: 50...180, unit: " BPM", color: Phosphor.green)
                        InstrumentSlider(label: "Swing", value: $model.beatSwing, range: 0...0.7, color: Phosphor.red)
                    }
                }
                Screen(title: "PADS", subtitle: "ARTICULATORY DRUMS") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(catalog.beatSounds) { sound in
                            Button {
                                model.beatHit(sound.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(sound.name).font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(sound.id.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                                .padding(7)
                                .overlay(Rectangle().stroke(Phosphor.pink.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                            .help(sound.hint)
                        }
                    }
                }
            }
        }
    }
}

struct BestiaryView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            if let catalog = model.catalog,
               let creature = catalog.creatures.first(where: { $0.id == model.selectedCreatureID }) {
                Screen(title: "BESTIARY", subtitle: creature.latin) {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(catalog.creatures) { item in
                                Chip(title: item.name, selected: item.id == creature.id, color: Phosphor.blue) { model.selectCreature(item.id) }
                            }
                        }
                        Text(creature.blurb)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Screen(title: "VOICE PARAMETERS", subtitle: creature.role) {
                    VStack(spacing: 14) {
                        ForEach(creature.params) { param in
                            InstrumentSlider(
                                label: param.label,
                                value: Binding(
                                    get: { model.creatureParams[creature.id]?[param.key] ?? param.defaultValue },
                                    set: { model.setCreatureParam(param.key, value: $0) }
                                ),
                                range: param.min...param.max,
                                unit: param.unit ?? "",
                                color: Phosphor.green
                            )
                        }
                    }
                }
                Screen(title: "CALLS", subtitle: "PRECOMPUTED GESTURES") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(creature.calls) { call in
                            Chip(title: call.name, color: Phosphor.amber) { model.playCall(call.id) }
                                .help(call.hint)
                        }
                    }
                }
                Screen(title: "KEYS", subtitle: "PITCH CONTROL") {
                    PianoKeys(base: 48, heldNotes: model.heldNotes, onNoteOn: model.noteOn, onNoteOff: model.noteOff)
                }
            }
        }
    }
}


struct OllamaControls: View {
    @EnvironmentObject private var model: InstrumentModel
    let mode: InstrumentMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Phosphor.blue.opacity(0.25))
            HStack {
                Text("OLLAMA / PLAIN ENGLISH ONLY")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Phosphor.blue)
                Spacer()
                if model.ollamaBusy { ProgressView().controlSize(.small) }
            }
            TextField("English subject or writing instruction", text: $model.ollamaPrompt)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Phosphor.white)
                .padding(7)
                .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.3)))
            HStack {
                Picker("Ollama model", selection: $model.selectedOllamaModel) {
                    ForEach(model.ollamaModels, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(model.ollamaModels.isEmpty || model.ollamaBusy)
                .frame(maxWidth: .infinity, alignment: .leading)
                Chip(title: "Generate English", color: Phosphor.green) {
                    Task { try? await model.generateText(for: mode) }
                }
                .disabled(model.selectedOllamaModel.isEmpty || model.ollamaBusy)
                Chip(title: "Refresh", color: Phosphor.blue) {
                    Task { await model.refreshOllamaModels() }
                }
                .disabled(model.ollamaBusy)
            }
            Text(model.ollamaStatus)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
