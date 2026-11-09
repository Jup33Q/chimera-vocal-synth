import SwiftUI

@main
struct ChimeraPlayApp: App {
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8643,
        mcpServerName: "chimera-play",
        mcpTools: ["chimera_status", "chimera_play_note", "chimera_start", "chimera_note_on", "chimera_note_off", "chimera_set_voice", "chimera_set_gate", "chimera_stop"],
        servesHeadStream: false,
        projectID: "chimera-play",
        projectName: "Chimera Play",
        controlledByHead: true
    )

    var body: some Scene {
        WindowGroup("Chimera Play") {
            ChimeraPlayView()
                .environmentObject(instrument)
                .frame(minWidth: 620, minHeight: 640)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 800)
    }
}
