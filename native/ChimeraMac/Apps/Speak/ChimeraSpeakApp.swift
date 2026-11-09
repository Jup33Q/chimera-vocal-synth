import SwiftUI

@main
struct ChimeraSpeakApp: App {
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8644,
        mcpServerName: "chimera-speak",
        mcpTools: ["chimera_status", "chimera_speak", "chimera_stop_speech", "chimera_stop"],
        projectID: "chimera-speak",
        projectName: "Chimera Speak",
        controlledByHead: true,
        initialMode: .speak
    )

    var body: some Scene {
        WindowGroup("Chimera Speak") {
            ChimeraSpeakView()
                .environmentObject(instrument)
                .frame(minWidth: 720, minHeight: 600)
                .background(Color.black)
        }
        .defaultSize(width: 960, height: 900)
    }
}
