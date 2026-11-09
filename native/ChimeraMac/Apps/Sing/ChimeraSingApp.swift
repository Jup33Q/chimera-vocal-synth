import SwiftUI

@main
struct ChimeraSingApp: App {
    @StateObject private var instrument = InstrumentModel(
        mcpPort: 8645,
        mcpServerName: "chimera-sing",
        mcpTools: ["chimera_status", "chimera_sing", "chimera_stop_singing", "chimera_stop"],
        projectID: "chimera-sing",
        projectName: "Chimera Sing",
        controlledByHead: true,
        initialMode: .sing
    )

    var body: some Scene {
        WindowGroup("Chimera Sing") {
            ChimeraSingView()
                .environmentObject(instrument)
                .frame(minWidth: 940, minHeight: 700)
                .background(Color.black)
                .background(SingWindowConfigurator())
        }
        .defaultSize(width: 1180, height: 860)
        .windowResizability(.contentMinSize)
    }
}

private struct SingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.viewDidMoveToWindow()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        window.minSize = NSSize(width: 940, height: 700)
        guard window.frame.width < 940 || window.frame.height < 700 else { return }
        let visible = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1180, height: 860)
        let size = NSSize(width: min(1180, visible.width), height: min(860, visible.height))
        window.setContentSize(size)
        window.center()
    }
}
