import SwiftUI

struct ChimeraViewerView: View {
    @EnvironmentObject private var model: InstrumentModel

    var body: some View {
        VStack(spacing: 12) {
            ViewerHeader(model: model)
            if let error = model.lastError {
                ViewerErrorBanner(message: error) { model.lastError = nil }
            }
            ScrollView {
                VStack(spacing: 12) {
                    GesturalScoreView(model: model)
                    ConsonantChartView(model: model)
                    TubeView(model: model)
                    VocalFoldsView(model: model)
                    SpectrogramView(model: model)
                }
            }
            .scrollIndicators(.visible)
            ViewerTelemetry(model: model)
        }
        .padding(14)
        .background(Color.black)
        .foregroundStyle(Phosphor.white)
        .task { model.prepare() }
    }
}

private struct ViewerHeader: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 12) {
            Text("CHIMERA VIEWER")
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
            Chip(title: "Stop", color: Phosphor.red) { model.stopSpeech() }
            Chip(title: "Stop all", color: Phosphor.red) { model.stopAll() }
        }
    }
}

private struct ViewerErrorBanner: View {
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

private struct ViewerTelemetry: View {
    @ObservedObject var model: InstrumentModel

    var body: some View {
        HStack(spacing: 22) {
            Text(String(format: "F0 %.1f HZ", model.telemetry.f0))
            Text(String(format: "GATE %.3f", model.telemetry.gate))
            Text(String(format: "OUT RMS %.3f", model.telemetry.outRMS))
            Spacer()
            Text("REMOTE VIEWER / HEAD OWNS AUDIO + 3D HEAD")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Phosphor.amber)
    }
}
