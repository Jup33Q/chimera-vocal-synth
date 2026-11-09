import MetalKit
import SwiftUI

struct MetalCanvas: NSViewRepresentable {
    let scene: MetalScene

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.device = context.coordinator.renderer.device
        view.delegate = context.coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.003, green: 0.006, blue: 0.009, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer.scene = scene
    }

    final class Coordinator {
        let renderer: PhosphorRenderer

        init() {
            guard let device = MTLCreateSystemDefaultDevice(), let renderer = try? PhosphorRenderer(device: device) else {
                fatalError("Metal is required to display CHIMERA's instrument views.")
            }
            self.renderer = renderer
        }
    }
}
