import SwiftUI

@main
struct ChimeraHeadApp: App {
    @State private var head = HeadModel()
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8647,
        mcpServerName: "chimera-head",
        servesHeadStream: true,
        projectID: "chimera-head",
        projectName: "Chimera Head",
        sourceName: "head",
        startsMCP: false
    )

    var body: some Scene {
        WindowGroup("Chimera Head") {
            ChimeraHeadView(head: head, model: instrument)
                .frame(minWidth: 1000, minHeight: 640)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 840)
    }
}
