import SwiftUI

struct ChimeraSingView: View {
    @EnvironmentObject private var model: InstrumentModel
    @StateObject private var generation = SingGenerationModel()
    @StateObject private var midi = MIDIInputController(clientName: "Chimera Sing")
    @State private var selectedID: UUID?
    @State private var showAcoustics = false

    var body: some View {
        VStack(spacing: 12) {
            SingHeader(model: model, generation: generation)
            if let error = model.lastError {
                SingErrorBanner(message: error) { model.lastError = nil }
            }
            ScrollView {
                VStack(spacing: 12) {
                    SingTransport(model: model, selectedID: $selectedID)
                    PianoRollEditor(model: model, selectedID: $selectedID)
                    SingNoteInspector(model: model, selectedID: $selectedID)
                    SingLiveInput(model: model, midi: midi)
                    HStack(alignment: .top, spacing: 12) {
                        SingLyricsEditor(model: model)
                        SingLyricsGenerator(generation: generation, instrument: model)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        GesturalScoreView(model: model)
                        SpectrogramView(model: model)
                    }
                    DisclosureGroup(isExpanded: $showAcoustics) {
                        VStack(spacing: 12) {
                            TubeView(model: model)
                            VocalFoldsView(model: model)
                        }
                        .padding(.top, 10)
                    } label: {
                        Text("TUBE + VOCAL FOLDS")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(Phosphor.blue)
                    }
                    .padding(10)
                    .background(Color(red: 0.004, green: 0.009, blue: 0.014))
                    .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.25)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.visible)
            SingTelemetry(model: model)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task {
            midi.onNoteOn = { note in model.noteOn(note) }
            midi.onNoteOff = { note in model.noteOff(note) }
            model.prepare()
            await model.refreshOllamaModels()
        }
        .onDisappear {
            midi.stop()
            model.stopSinging()
        }
    }
}

private struct SingLiveInput: View {
    @ObservedObject var model: InstrumentModel
    @ObservedObject var midi: MIDIInputController

    var body: some View {
        Screen(title: "MIDI + PIANO INPUT", subtitle: "EACH NOTE-ON SINGS THE NEXT SYLLABLE") {
            VStack(spacing: 10) {
                MIDIInputView(midi: midi)
                PianoKeys(base: 60, count: 12, heldNotes: model.heldNotes, onNoteOn: model.noteOn, onNoteOff: model.noteOff)
            }
        }
    }
}

private struct SingHeader: View {
    @ObservedObject var model: InstrumentModel
    @ObservedObject var generation: SingGenerationModel

    var body: some View {
        HStack(spacing: 12) {
            Text("CHIMERA SING")
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Phosphor.blue)
            Text(model.isStarted ? "HEAD LIVE / 48 KHZ" : "HEAD STANDBY")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.isStarted ? Phosphor.green : Phosphor.amber)
            Spacer()
            Text(model.headConnected ? "NDJSON CONNECTED" : "HEAD OFFLINE / RECONNECTING")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(model.headConnected ? Phosphor.green : Phosphor.red)
            Text("MCP 127.0.0.1:\(model.mcpPort)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Phosphor.blue)
                .textSelection(.enabled)
            Chip(title: "Clear", color: Phosphor.blue) {
                generation.clear()
                model.clearSong()
                model.lastError = nil
            }
            Chip(title: "Stop all", color: Phosphor.red) {
                generation.stop()
                model.stopAll()
            }
        }
    }
}

private struct SingErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Phosphor.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", action: dismiss).foregroundStyle(Phosphor.red)
        }
    }
}

private struct SingTransport: View {
    @ObservedObject var model: InstrumentModel
    @Binding var selectedID: UUID?

    var body: some View {
        Screen(title: "TRANSPORT + SONG PRESETS", subtitle: model.playingSong ?? "EDITED SCORE READY") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Chip(title: "Play current", selected: model.playingSong != nil, color: Phosphor.green) {
                        model.playCurrentSong()
                    }
                    .disabled(model.songNotes.isEmpty)
                    Chip(title: "Stop singing", color: Phosphor.red) { model.stopSinging() }
                    Chip(title: "Add note", color: Phosphor.blue) {
                        model.addSongNote()
                        selectedID = model.songNotes.last?.id
                    }
                    Spacer()
                    Text(model.songNotes.isEmpty ? "NO NOTES" : "\(model.songNotes.count) NOTES / \(model.songSyllables.count) SOURCE SYLLABLES")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(model.songNotes.isEmpty ? Phosphor.red : .secondary)
                }
                HStack(spacing: 20) {
                    InstrumentSlider(label: "Tempo", value: $model.songBPM, range: 40...240, unit: " BPM", color: Phosphor.green)
                    InstrumentSlider(label: "Vibrato", value: $model.vibrato, range: 0...100, unit: " cents", color: Phosphor.pink)
                }
                if let catalog = model.catalog {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(catalog.demoSongs) { song in
                                Chip(title: "Play \(song.name)", selected: model.playingSong == song.name, color: Phosphor.amber) {
                                    model.playSong(song)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
            }
        }
    }
}

private struct SingNoteInspector: View {
    @ObservedObject var model: InstrumentModel
    @Binding var selectedID: UUID?

    var body: some View {
        Screen(title: "NOTE + LYRIC MAPPING", subtitle: "MISSING OR MULTI-SYLLABLE LYRICS BLOCK PLAYBACK") {
            VStack(spacing: 10) {
                if let note = model.songNotes.first(where: { $0.id == selectedID }) {
                    HStack(spacing: 12) {
                        Text(singNoteName(note.midi))
                            .font(.system(size: 20, design: .monospaced))
                            .foregroundStyle(Phosphor.amber)
                            .frame(width: 54)
                        TextField("One lyric syllable; - or ~ holds the previous vowel", text: Binding(
                            get: { note.lyric },
                            set: { var edited = note; edited.lyric = $0; model.updateSongNote(edited) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(note.lyric.isEmpty ? Phosphor.red : Phosphor.white)
                        .padding(7)
                        .background(Color.black)
                        .overlay(Rectangle().stroke(note.lyric.isEmpty ? Phosphor.red : Phosphor.blue.opacity(0.4)))
                        .accessibilityLabel("Lyric syllable for selected note")
                        Stepper("MIDI \(note.midi)", value: Binding(
                            get: { note.midi },
                            set: { var edited = note; edited.midi = $0; model.updateSongNote(edited) }
                        ), in: 48...76)
                        .font(.system(size: 10, design: .monospaced))
                        Chip(title: "Delete", color: Phosphor.red) {
                            model.deleteSongNote(note.id)
                            selectedID = nil
                        }
                        .keyboardShortcut(.delete, modifiers: [])
                    }
                    HStack(spacing: 20) {
                        InstrumentSlider(label: "Start", value: Binding(
                            get: { note.start },
                            set: { var edited = note; edited.start = $0; model.updateSongNote(edited) }
                        ), range: 0...128, unit: " beats", color: Phosphor.blue)
                        InstrumentSlider(label: "Duration", value: Binding(
                            get: { note.duration },
                            set: { var edited = note; edited.duration = $0; model.updateSongNote(edited) }
                        ), range: 0.25...8, unit: " beats", color: Phosphor.green)
                    }
                } else {
                    Text("Select a note in the roll or list. Add Note creates an explicit missing-lyric state rather than singing silence.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.songNotes) { note in
                            Button {
                                selectedID = note.id
                            } label: {
                                Text("\(singNoteName(note.midi)) · \(note.lyric.isEmpty ? "!" : note.lyric)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(note.lyric.isEmpty ? Phosphor.red : note.id == selectedID ? Color.black : Phosphor.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(note.id == selectedID ? Phosphor.green : Color.clear)
                                    .overlay(Rectangle().stroke(note.lyric.isEmpty ? Phosphor.red : Phosphor.green.opacity(0.45)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(singNoteName(note.midi)), lyric \(note.lyric.isEmpty ? "missing" : note.lyric)")
                        }
                    }
                }
            }
        }
    }
}

private struct SingLyricsEditor: View {
    @ObservedObject var model: InstrumentModel
    @State private var draft = ""

    var body: some View {
        Screen(title: "LYRICS → NOTES", subtitle: "APPLY DISTRIBUTES ONE SYLLABLE PER NOTE") {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Phosphor.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 82, maxHeight: 130)
                    .background(Color.black)
                    .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.35)))
                    .accessibilityLabel("English lyrics to distribute across notes")
                HStack {
                    Chip(title: "Apply lyrics to notes", color: Phosphor.green) {
                        do {
                            try model.applyLyricsToSong(draft)
                        } catch {
                            model.lastError = error.localizedDescription
                        }
                    }
                    Spacer()
                    Text("EXTRA NOTES KEEP AN EXPLICIT MISSING STATE")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(model.songSyllables.isEmpty ? "NO SINGABLE SYLLABLES" : model.songSyllables.enumerated().map { "\($0.offset + 1):\($0.element.text)" }.joined(separator: "  "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(model.songSyllables.isEmpty ? Phosphor.red : Phosphor.amber)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Consonants are planned before each beat; vowels sustain through the note; codas and release remain engine-planned. Use - or ~ for melisma.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { draft = model.lyrics }
        .onChange(of: model.lyrics) { _, text in
            if text != draft { draft = text }
        }
    }
}

private struct SingTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 18) {
            SingReadout(label: "PLAYHEAD", value: String(format: "%.2f s", model.songPlayhead))
            SingReadout(label: "NOTE", value: model.songNoteIndex >= 0 ? "\(model.songNoteIndex + 1)" : "—")
            SingReadout(label: "SYLLABLE", value: model.songSyllable ?? "—")
            SingReadout(label: "F0 HZ", value: String(format: "%.1f", model.telemetry.f0))
            SingReadout(label: "GATE", value: String(format: "%.3f", model.telemetry.gate))
            SingReadout(label: "OUT RMS", value: String(format: "%.4f", model.telemetry.outRMS))
            SingReadout(label: "HEAD FRAMES", value: "\(model.headRenderedFrames)")
            Spacer()
            Text(model.headEngineRunning ? "ENGINE RUNNING" : "ENGINE STANDBY")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(model.headEngineRunning ? Phosphor.green : Phosphor.amber)
        }
        .padding(8)
        .background(Color.black.opacity(0.72))
    }
}

private struct SingReadout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(Phosphor.amber)
        }
    }
}
