import SwiftUI

@main
struct ChimeraViewerApp: App {
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8649,
        mcpServerName: "chimera-viewer",
        mcpTools: ["chimera_status", "chimera_speak", "chimera_stop_speech", "chimera_stop"],
        projectID: "chimera-viewer",
        projectName: "Chimera Viewer",
        controlledByHead: true,
        initialMode: .speak
    )

    var body: some Scene {
        WindowGroup("Chimera Viewer") {
            ChimeraViewerView()
                .environmentObject(instrument)
                .frame(minWidth: 900, minHeight: 680)
                .background(Color.black)
        }
        .defaultSize(width: 1180, height: 900)
    }
}
