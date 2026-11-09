import SwiftUI

@main
struct ChimeraBeatboxApp: App {
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8646,
        mcpServerName: "chimera-beatbox",
        mcpTools: ["chimera_status", "chimera_beatbox", "chimera_stop"],
        projectID: "chimera-beatbox",
        projectName: "Chimera Beatbox",
        controlledByHead: true,
        initialMode: .beatbox
    )

    var body: some Scene {
        WindowGroup("Chimera Beatbox") {
            ChimeraBeatboxView()
                .environmentObject(instrument)
                .frame(minWidth: 760, minHeight: 600)
                .background(Color.black)
        }
        .defaultSize(width: 920, height: 760)
    }
}
