import SwiftUI

struct ChimeraSpeakView: View {
    @EnvironmentObject private var model: InstrumentModel
    @StateObject private var conversation = SpeakConversationModel()
    @State private var showAcoustics = false

    var body: some View {
        VStack(spacing: 12) {
            SpeakHeader(model: model, conversation: conversation)
            if let error = model.lastError {
                SpeakErrorBanner(message: error) { model.lastError = nil }
            }
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        GesturalScoreView(model: model)
                        SpectrogramView(model: model)
                    }
                    SpeakChatHistory(conversation: conversation, instrument: model)
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
            SpeakChatInput(conversation: conversation, instrument: model)
            SpeakTelemetry(model: model)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task {
            model.prepare()
            await model.refreshOllamaModels()
        }
    }
}

private struct SpeakHeader: View {
    @ObservedObject var model: InstrumentModel
    @ObservedObject var conversation: SpeakConversationModel

    var body: some View {
        HStack(spacing: 12) {
            Text("CHIMERA SPEAK")
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
            Chip(title: "Clear", color: Phosphor.blue) { conversation.clear(using: model) }
            Chip(title: "Stop all", color: Phosphor.red) {
                conversation.stop(using: model)
                model.stopAll()
            }
        }
    }
}

private struct SpeakErrorBanner: View {
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

private struct SpeakTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 22) {
            SpeakReadout(label: "F0 HZ", value: model.telemetry.f0)
            SpeakReadout(label: "GATE", value: model.telemetry.gate)
            SpeakReadout(label: "OUT RMS", value: model.telemetry.outRMS)
            InstrumentSlider(label: "Rate", value: $model.speechRate, range: 0.5...1.8, unit: "×")
                .frame(width: 160)
            Spacer()
        }
        .padding(8)
        .background(Color.black.opacity(0.72))
    }
}

private struct SpeakReadout: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Phosphor.amber)
        }
    }
}
