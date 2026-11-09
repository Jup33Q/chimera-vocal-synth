import AppKit
import MetalKit
import StreamQuilt
import simd

struct LKGBridgeConfiguration {
    let calibration: Calibration
    let spec: QuiltSpec
    let serial: String

    static func fetch() async throws -> LKGBridgeConfiguration {
        let orchestration = try await put(
            "enter_orchestration",
            body: ["name": "ChimeraHead"]
        )
        guard let token = value(orchestration, "payload") as? String else {
            throw ChimeraError(message: "Looking Glass Bridge did not return an orchestration token.")
        }
        let response = try await put("available_output_devices", body: ["orchestration": token])
        guard let payload = response["payload"] as? [String: Any],
              let devices = payload["value"] as? [String: Any] else {
            throw ChimeraError(message: "Looking Glass Bridge returned no output-device list.")
        }
        for case let (_, item) in devices {
            guard let device = (item as? [String: Any])?["value"] as? [String: Any],
                  let hwid = value(device, "hwid") as? String,
                  hwid.contains("LKG"),
                  let calibrationText = value(device, "calibration") as? String,
                  let calibrationData = calibrationText.data(using: .utf8),
                  let rawCalibration = try? JSONSerialization.jsonObject(with: calibrationData) as? [String: Any],
                  let quiltText = value(device, "defaultQuilt") as? String,
                  let quiltData = quiltText.data(using: .utf8),
                  let quilt = try? JSONSerialization.jsonObject(with: quiltData) as? [String: Any] else { continue }
            func number(_ dictionary: [String: Any], _ key: String) -> Double? {
                if let wrapped = dictionary[key] as? [String: Any] { return (wrapped["value"] as? NSNumber)?.doubleValue }
                return (dictionary[key] as? NSNumber)?.doubleValue
            }
            guard let pitch = number(rawCalibration, "pitch"),
                  let slope = number(rawCalibration, "slope"),
                  let center = number(rawCalibration, "center"),
                  let dpi = number(rawCalibration, "DPI"),
                  let screenW = number(rawCalibration, "screenW"),
                  let screenH = number(rawCalibration, "screenH"),
                  let quiltX = number(quilt, "quiltX"),
                  let quiltY = number(quilt, "quiltY"),
                  let tileX = number(quilt, "tileX"),
                  let tileY = number(quilt, "tileY"),
                  tileX > 0, tileY > 0 else { continue }
            let columns = Int(tileX)
            let rows = Int(tileY)
            let serial = (rawCalibration["serial"] as? String) ?? hwid
            return LKGBridgeConfiguration(
                calibration: Calibration(
                    pitch: pitch,
                    slope: slope,
                    center: center,
                    dpi: dpi,
                    invView: number(rawCalibration, "invView") ?? 0,
                    flipImageX: number(rawCalibration, "flipImageX") ?? 0,
                    screenW: screenW,
                    screenH: screenH,
                    serial: serial
                ),
                spec: QuiltSpec(
                    columns: columns,
                    rows: rows,
                    tileWidth: Int(quiltX) / columns,
                    tileHeight: Int(quiltY) / rows,
                    screenAspect: Float(number(quilt, "quiltAspect") ?? screenW / screenH)
                ),
                serial: serial
            )
        }
        throw ChimeraError(message: "No calibrated Looking Glass device is available in Bridge.")
    }

    private static func put(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:33334")!.appending(path: endpoint))
        request.httpMethod = "PUT"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChimeraError(message: "Looking Glass Bridge is unavailable on 127.0.0.1:33334.")
        }
        return object
    }

    private static func value(_ dictionary: [String: Any], _ key: String) -> Any? {
        (dictionary[key] as? [String: Any])?["value"]
    }
}

@MainActor
final class LKGHeadController: NSObject, NSWindowDelegate {
    var yaw = 0.62
    var pitch = 0.2
    var zoom = 1.0
    var fov = 51.0
    var focus = 47.0
    var parallax = 20.0

    private let store: HeadVisualSnapshotStore
    private let onStatus: (Bool, String, Int) -> Void
    private var window: NSWindow?
    private var driver: LKGHeadDriver?
    private var frameCount = 0
    private var connectionID = 0
    private var lastStatusReport = 0.0

    init(store: HeadVisualSnapshotStore, onStatus: @escaping (Bool, String, Int) -> Void) {
        self.store = store
        self.onStatus = onStatus
    }

    func connect() async {
        guard driver == nil else { return }
        onStatus(false, "Reading Bridge calibration", frameCount)
        do {
            let configuration = try await LKGBridgeConfiguration.fetch()
            guard let screen = NSScreen.screens.first(where: {
                $0.localizedName.localizedCaseInsensitiveContains("LKG") ||
                (Int($0.frame.width) == Int(configuration.calibration.screenW) && Int($0.frame.height) == Int(configuration.calibration.screenH))
            }) else {
                throw ChimeraError(message: "Bridge returned \(configuration.serial), but no matching LKG screen is attached.")
            }
            connectionID += 1
            let connection = connectionID
            let quilt = try QuiltRenderer(spec: configuration.spec, renderScale: 0.5)
            let scene = try PhosphorRenderer3D(device: quilt.device, colorPixelFormat: .rgba16Float, sampleCount: 1)
            let driver = try LKGHeadDriver(
                quilt: quilt,
                scene: scene,
                calibration: configuration.calibration,
                store: store,
                camera: { [weak self] in
                    (
                        self?.yaw ?? 0.62,
                        self?.pitch ?? 0.2,
                        self?.zoom ?? 1,
                        self?.fov ?? 51,
                        self?.focus ?? 47,
                        self?.parallax ?? 20
                    )
                },
                onFrame: { [weak self] in
                    guard let self, self.driver != nil, self.connectionID == connection else { return }
                    self.frameCount += 1
                    let now = Date().timeIntervalSinceReferenceDate
                    guard now - self.lastStatusReport >= 1 else { return }
                    self.lastStatusReport = now
                    self.onStatus(true, "\(configuration.serial) / LIVE HARDWARE / \(quilt.spec.columns)×\(quilt.spec.rows)", self.frameCount)
                }
            )
            let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: quilt.device)
            view.colorPixelFormat = .bgra8Unorm
            view.preferredFramesPerSecond = 60
            view.isPaused = false
            view.enableSetNeedsDisplay = false
            view.delegate = driver
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.delegate = self
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            self.window = window
            self.driver = driver
            onStatus(true, "\(configuration.serial) / HARDWARE STARTING", frameCount)
        } catch {
            driver = nil
            window = nil
            onStatus(false, error.localizedDescription, frameCount)
        }
    }

    func disconnect() {
        connectionID += 1
        if let view = window?.contentView as? MTKView {
            view.isPaused = true
            view.delegate = nil
        }
        window?.orderOut(nil)
        window = nil
        driver = nil
        onStatus(false, "Disconnected / audio and telemetry unchanged", frameCount)
    }

    func windowWillClose(_ notification: Notification) {
        disconnect()
    }
}

private struct LKGCameraCacheKey: Equatable {
    let yaw: Double
    let pitch: Double
    let zoom: Double
    let fov: Double
    let focus: Double
    let parallax: Double
    let bodyScale: Double
    let width: Int
    let height: Int
}

private final class LKGHeadDriver: NSObject, MTKViewDelegate {
    private let quilt: QuiltRenderer
    private let scene: PhosphorRenderer3D
    private let calibration: Calibration
    private let store: HeadVisualSnapshotStore
    private let camera: () -> (Double, Double, Double, Double, Double, Double)
    private let onFrame: () -> Void
    private let depthTexture: MTLTexture
    private var cameraKey: LKGCameraCacheKey?
    private var cachedViews: [HeadRenderView] = []

    init(
        quilt: QuiltRenderer,
        scene: PhosphorRenderer3D,
        calibration: Calibration,
        store: HeadVisualSnapshotStore,
        camera: @escaping () -> (Double, Double, Double, Double, Double, Double),
        onFrame: @escaping () -> Void
    ) throws {
        self.quilt = quilt
        self.scene = scene
        self.calibration = calibration
        self.store = store
        self.camera = camera
        self.onFrame = onFrame
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: quilt.quiltTexture.width,
            height: quilt.quiltTexture.height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        guard let depthTexture = quilt.device.makeTexture(descriptor: descriptor) else {
            throw ChimeraError(message: "The LKG depth target could not be created.")
        }
        self.depthTexture = depthTexture
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let snapshot = store.read()
        scene.scene = snapshot.scene
        scene.frame = snapshot.frame
        scene.telemetry = snapshot.telemetry
        scene.bodyScale = snapshot.bodyScale
        scene.bodyMix = snapshot.bodyMix
        scene.animationEnabled = snapshot.animationEnabled
        scene.particlesEnabled = snapshot.particlesEnabled
        let (yaw, pitch, zoom, fov, focus, parallax) = camera()
        let key = LKGCameraCacheKey(
            yaw: yaw,
            pitch: pitch,
            zoom: zoom,
            fov: fov,
            focus: focus,
            parallax: parallax,
            bodyScale: snapshot.bodyScale,
            width: quilt.quiltTexture.width,
            height: quilt.quiltTexture.height
        )
        if cameraKey != key {
            cameraKey = key
            cachedViews = (0..<quilt.spec.viewCount).map { index -> HeadRenderView in
                let viewport = quilt.tileRect(index: index)
                let progress = quilt.spec.viewCount > 1 ? Float(index) / Float(quilt.spec.viewCount - 1) : 0.5
                let offset = (progress - 0.5) * Float(parallax) * Float(snapshot.bodyScale)
                return HeadRenderView(
                    viewport: viewport,
                    scissor: MTLScissorRect(x: Int(viewport.originX), y: Int(viewport.originY), width: Int(viewport.width), height: Int(viewport.height)),
                    viewProjection: scene.camera(
                        size: CGSize(width: viewport.width, height: viewport.height),
                        yaw: yaw,
                        pitch: pitch,
                        zoom: zoom,
                        lateralOffset: offset,
                        fovDegrees: fov,
                        focusDistance: focus
                    ),
                    pixelScale: 1
                )
            }
        }
        let views = cachedViews
        guard let command = quilt.commandQueue.makeCommandBuffer() else { return }
        let quiltPass = quilt.makeQuiltPassDescriptor(loadAction: .clear)
        quiltPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.003, green: 0.006, blue: 0.009, alpha: 1)
        quiltPass.depthAttachment.texture = depthTexture
        quiltPass.depthAttachment.loadAction = .clear
        quiltPass.depthAttachment.clearDepth = 1
        quiltPass.depthAttachment.storeAction = .dontCare
        scene.encode(command: command, pass: quiltPass, views: views)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        quilt.encodeLenticular(
            cmd: command,
            pass: pass,
            calibration: calibration,
            drawableSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        command.present(drawable)
        command.addCompletedHandler { _ in
            Task { @MainActor in self.onFrame() }
        }
        command.commit()
    }
}
