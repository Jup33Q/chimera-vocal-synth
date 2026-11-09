import SwiftUI

@MainActor
@Observable
final class HeadCamera {
    @ObservationIgnored var onChange: (() -> Void)?
    var yaw = 0.62 { didSet { onChange?() } }
    var pitch = 0.2 { didSet { onChange?() } }
    var zoom = 1.0 { didSet { onChange?() } }

    func reset() {
        yaw = 0.62
        pitch = 0.2
        zoom = 1.0
    }
}

@MainActor
private final class HeadSceneCache {
    private var clock: Double?
    private var body = BodyMix.male
    private var scale = 1.0
    private var cached = Metal3DScene()

    func scene(frame: HumanFrame?, telemetry: VoiceTelemetry, bodyScale: Double, bodyMix: BodyMix) -> Metal3DScene {
        if clock == telemetry.clock, scale == bodyScale, body == bodyMix { return cached }
        clock = telemetry.clock
        scale = bodyScale
        body = bodyMix
        cached = SceneFactory.anatomy3D(frame: frame, telemetry: telemetry, bodyScale: bodyScale, bodyTint: BodyPalette.vector(bodyMix))
        return cached
    }
}

struct HeadCanvas: View {
    let frame: HumanFrame?
    let telemetry: VoiceTelemetry
    let bodyScale: Double
    let bodyMix: BodyMix
    let camera: HeadCamera
    var animationEnabled = true
    var particlesEnabled = true
    var visualStore: HeadVisualSnapshotStore?

    @State private var yawAtDragStart = 0.62
    @State private var pitchAtDragStart = 0.2
    @State private var zoomAtGestureStart = 1.0
    @State private var orbiting = false
    @State private var zooming = false
    @State private var sceneCache = HeadSceneCache()

    var body: some View {
        GeometryReader { _ in
            MetalCanvas3D(
                scene: sceneCache.scene(frame: frame, telemetry: telemetry, bodyScale: bodyScale, bodyMix: bodyMix),
                yaw: camera.yaw,
                pitch: camera.pitch,
                zoom: camera.zoom,
                bodyScale: bodyScale,
                frame: frame,
                telemetry: telemetry,
                bodyMix: bodyMix,
                animationEnabled: animationEnabled,
                particlesEnabled: particlesEnabled,
                onUpdate: { renderer in visualStore?.update(renderer) }
            )
        }
        .contentShape(Rectangle())
        .gesture(orbitGesture)
        .simultaneousGesture(zoomGesture)
        .simultaneousGesture(TapGesture(count: 2).onEnded(camera.reset))
        .accessibilityLabel("Interactive three-dimensional vocal tract. Drag to orbit, pinch to zoom, double-click to reset.")
    }

    private var orbitGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !orbiting {
                    yawAtDragStart = camera.yaw
                    pitchAtDragStart = camera.pitch
                    orbiting = true
                }
                camera.yaw = yawAtDragStart + Double(value.translation.width) * 0.008
                camera.pitch = min(1.1, max(-1.1, pitchAtDragStart + Double(value.translation.height) * 0.006))
            }
            .onEnded { _ in orbiting = false })
    }

    private var zoomGesture: AnyGesture<MagnificationGesture.Value> {
        AnyGesture(MagnificationGesture()
            .onChanged { value in
                if !zooming {
                    zoomAtGestureStart = camera.zoom
                    zooming = true
                }
                camera.zoom = min(2.4, max(0.55, zoomAtGestureStart * Double(value)))
            }
            .onEnded { _ in
                zoomAtGestureStart = camera.zoom
                zooming = false
            })
    }
}
