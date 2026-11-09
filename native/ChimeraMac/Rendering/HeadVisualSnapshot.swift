import Foundation

struct HeadVisualSnapshot {
    var scene = Metal3DScene()
    var frame: HumanFrame?
    var telemetry = VoiceTelemetry()
    var bodyScale = 1.0
    var bodyMix = BodyMix.male
    var animationEnabled = true
    var particlesEnabled = true
}

final class HeadVisualSnapshotStore {
    private let lock = NSLock()
    private var snapshot = HeadVisualSnapshot()

    func update(_ renderer: PhosphorRenderer3D) {
        let value = HeadVisualSnapshot(
            scene: renderer.scene,
            frame: renderer.frame,
            telemetry: renderer.telemetry,
            bodyScale: renderer.bodyScale,
            bodyMix: renderer.bodyMix,
            animationEnabled: renderer.animationEnabled,
            particlesEnabled: renderer.particlesEnabled
        )
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    func read() -> HeadVisualSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}
