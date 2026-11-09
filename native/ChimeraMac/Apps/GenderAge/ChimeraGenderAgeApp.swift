import SwiftUI

@main
struct ChimeraGenderAgeApp: App {
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8648,
        mcpServerName: "chimera-gender-age",
        mcpTools: ["chimera_status", "chimera_start", "chimera_set_voice", "chimera_set_gate", "chimera_stop"],
        projectID: "chimera-gender-age",
        projectName: "Chimera Gender Age",
        controlledByHead: true,
        initialMode: .play
    )

    var body: some Scene {
        WindowGroup("Chimera Gender Age") {
            ChimeraGenderAgeView()
                .environmentObject(instrument)
                .frame(minWidth: 900, minHeight: 560)
                .background(Color.black)
        }
        .defaultSize(width: 1120, height: 680)
    }
}
