import SwiftUI

struct SpeakChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
        case status
        case error
    }

    let id = UUID()
    let role: Role
    let text: String
    var transcription: String?
}

@MainActor
final class SpeakConversationModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [SpeakChatMessage] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Ready"

    private var submissionTask: Task<Void, Never>?
    private var activeSubmission: UUID?

    func submit(using instrument: InstrumentModel) {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let submission = UUID()
        let previous = submissionTask
        previous?.cancel()
        activeSubmission = submission
        instrument.stopSpeech()
        draft = ""
        messages.append(SpeakChatMessage(role: .user, text: prompt))
        busy = true
        status = "Generating plain English"
        submissionTask = Task { [weak self, weak instrument] in
            guard let self, let instrument else { return }
            defer {
                if self.activeSubmission == submission {
                    self.busy = false
                    self.submissionTask = nil
                }
            }
            if let previous { await previous.value }
            guard self.activeSubmission == submission, !Task.isCancelled else { return }
            do {
                let generated = try await instrument.generateText(for: .speak, prompt: prompt)
                try Task.checkCancellation()
                guard self.activeSubmission == submission else { return }
                guard !generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChimeraError(message: "No speakable text was produced. Nothing was sent to Head.")
                }
                self.status = "Speaking generated reply through Head"
                let result = try await instrument.speakNow(text: generated, ipa: false)
                try Task.checkCancellation()
                guard self.activeSubmission == submission else { return }
                let transcription = result["transcription"] as? String ?? instrument.transcription
                self.messages.append(SpeakChatMessage(
                    role: .assistant,
                    text: generated,
                    transcription: transcription.isEmpty ? nil : transcription
                ))
                self.status = "Playing / telemetry live"
            } catch is CancellationError {
                guard self.activeSubmission == submission else { return }
                self.status = "Stopped"
            } catch {
                guard self.activeSubmission == submission, !Task.isCancelled else { return }
                self.messages.append(SpeakChatMessage(role: .error, text: error.localizedDescription))
                self.status = "Not sent to Head"
            }
        }
    }

    func replay(_ message: SpeakChatMessage, using instrument: InstrumentModel) {
        guard message.role == .assistant else { return }
        let replay = UUID()
        let previous = submissionTask
        previous?.cancel()
        activeSubmission = replay
        instrument.stopSpeech()
        busy = true
        status = "Replaying generated reply through Head"
        submissionTask = Task { [weak self, weak instrument] in
            guard let self, let instrument else { return }
            defer {
                if self.activeSubmission == replay {
                    self.busy = false
                    self.submissionTask = nil
                }
            }
            if let previous { await previous.value }
            guard self.activeSubmission == replay, !Task.isCancelled else { return }
            do {
                _ = try await instrument.speakNow(text: message.text, ipa: false)
                try Task.checkCancellation()
                guard self.activeSubmission == replay else { return }
                self.status = "Replaying / telemetry live"
            } catch is CancellationError {
                guard self.activeSubmission == replay else { return }
                self.status = "Stopped"
            } catch {
                guard self.activeSubmission == replay, !Task.isCancelled else { return }
                self.messages.append(SpeakChatMessage(role: .error, text: "Replay failed: \(error.localizedDescription)"))
                self.status = "Replay failed / not sent to Head"
            }
        }
    }

    func stop(using instrument: InstrumentModel) {
        activeSubmission = nil
        submissionTask?.cancel()
        submissionTask = nil
        busy = false
        status = "Stopped"
        instrument.stopSpeech()
    }

    func clear(using instrument: InstrumentModel) {
        stop(using: instrument)
        messages.removeAll()
        instrument.clearSpeech()
        status = "Ready"
    }

    deinit {
        submissionTask?.cancel()
    }
}

struct SpeakChatHistory: View {
    @ObservedObject var conversation: SpeakConversationModel
    @ObservedObject var instrument: InstrumentModel

    var body: some View {
        Screen(title: "CONVERSATION", subtitle: conversation.status.uppercased()) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if conversation.messages.isEmpty {
                            Text("Ask Ollama for a short English reply. Your prompt is not spoken; only the validated generated reply is sent to Head.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                        ForEach(conversation.messages) { message in
                            SpeakChatBubble(message: message) {
                                conversation.replay(message, using: instrument)
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 150, maxHeight: 260)
                .onChange(of: conversation.messages.count) { _, _ in
                    guard let last = conversation.messages.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct SpeakChatBubble: View {
    let message: SpeakChatMessage
    let replay: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(color)
                Text(message.text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(message.role == .error ? Phosphor.red : Phosphor.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let transcription = message.transcription {
                    Text(transcription)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Phosphor.amber)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if message.role == .assistant {
                    Chip(title: "Play", color: Phosphor.green, action: replay)
                        .accessibilityLabel("Replay this AI reply")
                }
            }
            .padding(10)
            .frame(maxWidth: 720, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3)))
            if message.role != .user { Spacer(minLength: 54) }
        }
    }

    private var label: String {
        switch message.role {
        case .user: "YOU"
        case .assistant: "HEAD / SPOKEN TEXT"
        case .status: "STATUS"
        case .error: "ERROR / NOT SPOKEN"
        }
    }

    private var color: Color {
        switch message.role {
        case .user: Phosphor.blue
        case .assistant: Phosphor.green
        case .status: Phosphor.amber
        case .error: Phosphor.red
        }
    }

    private var background: Color {
        switch message.role {
        case .user: Phosphor.blue.opacity(0.08)
        case .assistant: Phosphor.green.opacity(0.045)
        case .status: Phosphor.amber.opacity(0.05)
        case .error: Phosphor.red.opacity(0.07)
        }
    }
}

struct SpeakChatInput: View {
    @ObservedObject var conversation: SpeakConversationModel
    @ObservedObject var instrument: InstrumentModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $conversation.draft)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Phosphor.white)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.visible)
                    .focused($focused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .onKeyPress(.return, phases: .down) { key in
                        guard !key.modifiers.contains(.shift) else { return .ignored }
                        conversation.submit(using: instrument)
                        return .handled
                    }
                    .accessibilityLabel("Chat message. Enter sends, Shift Enter inserts a new line.")
                if conversation.draft.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 72, maxHeight: 150)

            Divider().overlay(Phosphor.blue.opacity(0.18))
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
                .disabled(conversation.busy || instrument.ollamaModels.isEmpty)
                .frame(maxWidth: 240, alignment: .leading)
                if conversation.busy {
                    ProgressView().controlSize(.small)
                    Text(conversation.status)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Phosphor.amber)
                        .lineLimit(1)
                }
                Spacer()
                Chip(title: "Stop", color: Phosphor.red) { conversation.stop(using: instrument) }
                    .disabled(!conversation.busy && instrument.telemetry.gate <= 0.01 && instrument.speechSegments.isEmpty)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(canSend ? Phosphor.green : Phosphor.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(canSend ? Color.black : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send and speak")
            }
            .padding(10)
        }
        .background(Color(red: 0.012, green: 0.018, blue: 0.027), in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(focused ? Phosphor.blue : Phosphor.blue.opacity(0.28), lineWidth: focused ? 1.5 : 1)
        )
        .shadow(color: focused ? Phosphor.blue.opacity(0.14) : .clear, radius: 8)
        .onAppear { focused = true }
        .onTapGesture { focused = true }
    }

    private var canSend: Bool {
        !conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !instrument.selectedOllamaModel.isEmpty
    }

    private var placeholder: String {
        "Ask for a short English utterance…"
    }

    private func send() {
        conversation.submit(using: instrument)
        focused = true
    }
}
