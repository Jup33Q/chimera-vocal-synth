import SwiftUI

@MainActor
final class SingGenerationModel: ObservableObject {
    @Published var prompt = "Write a short song about discovering a voice made of air"
    @Published private(set) var lastPrompt = ""
    @Published private(set) var generatedLyrics = ""
    @Published private(set) var busy = false
    @Published private(set) var status = "Ready"
    @Published private(set) var error: String?

    private var generationTask: Task<Void, Never>?
    private var activeGeneration: UUID?

    func generate(using instrument: InstrumentModel) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            error = "Enter an Ollama lyric prompt first. The prompt itself is never sung."
            status = "Not generated"
            return
        }
        let generation = UUID()
        let previous = generationTask
        previous?.cancel()
        activeGeneration = generation
        lastPrompt = prompt
        generatedLyrics = ""
        error = nil
        busy = true
        status = "Generating and validating English lyrics"
        instrument.stopSinging()
        generationTask = Task { [weak self, weak instrument] in
            guard let self, let instrument else { return }
            defer {
                if self.activeGeneration == generation {
                    self.busy = false
                    self.generationTask = nil
                }
            }
            if let previous { await previous.value }
            guard self.activeGeneration == generation, !Task.isCancelled else { return }
            do {
                let generated = try await instrument.generateText(for: .sing, prompt: prompt)
                try Task.checkCancellation()
                guard self.activeGeneration == generation else { return }
                try instrument.applyLyricsToSong(generated)
                guard self.activeGeneration == generation else { return }
                self.generatedLyrics = generated
                self.status = "Validated lyrics assigned to \(instrument.songNotes.count) notes; press Play to sing"
            } catch is CancellationError {
                guard self.activeGeneration == generation else { return }
                self.status = "Generation stopped"
            } catch {
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.status = "Not applied to the score"
            }
        }
    }

    func stop() {
        activeGeneration = nil
        generationTask?.cancel()
        generationTask = nil
        busy = false
        status = "Generation stopped"
    }

    func clear() {
        stop()
        prompt = ""
        lastPrompt = ""
        generatedLyrics = ""
        error = nil
        status = "Ready"
    }

    deinit {
        generationTask?.cancel()
    }
}

struct SingLyricsGenerator: View {
    @ObservedObject var generation: SingGenerationModel
    @ObservedObject var instrument: InstrumentModel

    var body: some View {
        Screen(title: "OLLAMA LYRIC PROMPT", subtitle: generation.status.uppercased()) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The prompt is an instruction only. Only validated generated English lyrics enter the score.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $generation.prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Phosphor.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64, maxHeight: 100)
                    .background(Color.black)
                    .overlay(Rectangle().stroke(Phosphor.blue.opacity(0.35)))
                    .accessibilityLabel("Ollama lyric prompt, never sung directly")
                HStack(spacing: 10) {
                    Picker("Ollama model", selection: $instrument.selectedOllamaModel) {
                        if instrument.ollamaModels.isEmpty {
                            Text("No local model").tag("")
                        } else {
                            ForEach(instrument.ollamaModels, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(generation.busy || instrument.ollamaModels.isEmpty)
                    .frame(maxWidth: 220)
                    if generation.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Chip(title: "Stop generation", color: Phosphor.red) { generation.stop() }
                        .disabled(!generation.busy)
                    Chip(title: "Generate + assign", selected: generation.busy, color: Phosphor.green) {
                        generation.generate(using: instrument)
                    }
                    .disabled(generation.busy || instrument.selectedOllamaModel.isEmpty)
                }
                if !generation.lastPrompt.isEmpty {
                    SingGeneratedText(title: "USER PROMPT / NOT SUNG", text: generation.lastPrompt, color: Phosphor.blue)
                }
                if !generation.generatedLyrics.isEmpty {
                    SingGeneratedText(title: "VALIDATED GENERATED LYRICS / IN SCORE", text: generation.generatedLyrics, color: Phosphor.green)
                }
                if let error = generation.error {
                    SingGeneratedText(title: "ERROR / NOT SUNG", text: error, color: Phosphor.red)
                }
            }
        }
    }
}

private struct SingGeneratedText: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, design: .monospaced))
                .tracking(1)
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(color == Phosphor.red ? Phosphor.red : Phosphor.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.05))
        .overlay(Rectangle().stroke(color.opacity(0.25)))
    }
}
