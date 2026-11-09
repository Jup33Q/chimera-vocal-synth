import SwiftUI

@main
struct ChimeraMacApp: App {
    @StateObject private var instrument = InstrumentModel()

    var body: some Scene {
        WindowGroup("CHIMERA") {
            RootView()
                .environmentObject(instrument)
                .frame(minWidth: 980, minHeight: 680)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 920)
    }
}
