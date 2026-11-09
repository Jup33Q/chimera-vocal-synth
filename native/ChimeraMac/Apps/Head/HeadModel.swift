import Foundation
import Observation

@MainActor
@Observable
final class HeadModel {
    var sourceMode = "auto"
    var animationEnabled = true
    var particlesEnabled = true
    var lkgStatus = "Disconnected"
    var lkgConnected = false
    var lkgFrameCount = 0
    var lkgFov = 51.0 {
        didSet { lkgController?.fov = lkgFov }
    }
    var lkgFocus = 47.0 {
        didSet { lkgController?.focus = lkgFocus }
    }
    var lkgParallax = 20.0 {
        didSet { lkgController?.parallax = lkgParallax }
    }
    let camera = HeadCamera()

    @ObservationIgnored let visualStore = HeadVisualSnapshotStore()
    @ObservationIgnored private var lkgController: LKGHeadController?
    @ObservationIgnored private var mcpServer: MCPServer?

    var lkgHardwareVerified: Bool { lkgConnected && lkgFrameCount > 0 }
    var lkgOrientation: [String: Double] {
        [
            "yaw": lkgController?.yaw ?? camera.yaw,
            "pitch": lkgController?.pitch ?? camera.pitch,
            "zoom": lkgController?.zoom ?? camera.zoom
        ]
    }

    func start(model: InstrumentModel) {
        if lkgController == nil {
            lkgController = LKGHeadController(store: visualStore) { [weak self] connected, status, frames in
                self?.lkgConnected = connected
                self?.lkgStatus = status
                self?.lkgFrameCount = frames
            }
            lkgController?.fov = lkgFov
            lkgController?.focus = lkgFocus
            lkgController?.parallax = lkgParallax
        }
        camera.onChange = { [weak self] in self?.syncLKGCamera() }
        syncLKGCamera()
        guard mcpServer == nil else { return }
        let server = MCPServer(
            port: 8647,
            serverName: "chimera-head",
            router: HeadToolRouter(model: self, instrument: model),
            headStream: model.headStreamService
        )
        server.start()
        mcpServer = server
    }

    func selectSource(_ source: String) {
        sourceMode = source
    }

    func toggleLKG() {
        if lkgConnected {
            lkgController?.disconnect()
        } else {
            Task { await lkgController?.connect() }
        }
    }

    func setLKGCamera(
        yaw: Double? = nil,
        pitch: Double? = nil,
        zoom: Double? = nil,
        fov: Double? = nil,
        focus: Double? = nil,
        parallax: Double? = nil
    ) {
        guard let lkgController else { return }
        if let yaw { lkgController.yaw = yaw }
        if let pitch { lkgController.pitch = min(1.1, max(-1.1, pitch)) }
        if let zoom { lkgController.zoom = min(2.4, max(0.55, zoom)) }
        if let fov { lkgFov = min(90, max(12, fov)) }
        if let focus { lkgFocus = min(100, max(20, focus)) }
        if let parallax { lkgParallax = min(30, max(0, parallax)) }
    }

    private func syncLKGCamera() {
        lkgController?.yaw = camera.yaw
        lkgController?.pitch = camera.pitch
        lkgController?.zoom = camera.zoom
    }
}
