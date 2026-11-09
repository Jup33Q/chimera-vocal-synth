import MetalKit
import QuartzCore
import SwiftUI
import simd

struct LineStrip3D {
    let points: [SIMD3<Float>]
    let color: SIMD4<Float>
    let width: Float
}

struct Metal3DScene {
    var lines: [LineStrip3D] = []
}

struct HeadRenderView {
    let viewport: MTLViewport
    let scissor: MTLScissorRect?
    let viewProjection: matrix_float4x4
    let pixelScale: Float
}

private struct Segment3D {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let color: SIMD4<Float>
    let width: Float
}

private struct SegmentStyle {
    let extraWidth: Float
    let alpha: Float
}

struct MetalCanvas3D: NSViewRepresentable {
    let scene: Metal3DScene
    let yaw: Double
    let pitch: Double
    let zoom: Double
    let bodyScale: Double
    var frame: HumanFrame?
    var telemetry = VoiceTelemetry()
    var bodyMix = BodyMix.male
    var animationEnabled = true
    var particlesEnabled = true
    var onUpdate: ((PhosphorRenderer3D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.renderer.device)
        view.delegate = context.coordinator.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.clearDepth = 1
        view.clearColor = MTLClearColor(red: 0.003, green: 0.006, blue: 0.009, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        view.layer?.contentsScale = scale
        let drawableSize = CGSize(width: max(1, view.bounds.width * scale), height: max(1, view.bounds.height * scale))
        if view.drawableSize != drawableSize { view.drawableSize = drawableSize }
        let renderer = context.coordinator.renderer
        renderer.scene = scene
        renderer.yaw = yaw
        renderer.pitch = pitch
        renderer.zoom = zoom
        renderer.bodyScale = bodyScale
        renderer.frame = frame
        renderer.telemetry = telemetry
        renderer.animationEnabled = animationEnabled
        renderer.particlesEnabled = particlesEnabled
        if renderer.bodyMix != bodyMix {
            renderer.bodyMix = bodyMix
            renderer.resetMotion()
        }
        onUpdate?(renderer)
    }

    final class Coordinator {
        let renderer: PhosphorRenderer3D

        init() {
            guard let device = MTLCreateSystemDefaultDevice(), let renderer = try? PhosphorRenderer3D(device: device) else {
                fatalError("Metal is required to display CHIMERA's 3D instrument view.")
            }
            self.renderer = renderer
        }
    }
}

final class PhosphorRenderer3D: NSObject, MTKViewDelegate {
    let device: MTLDevice
    var scene = Metal3DScene()
    var yaw = 0.62
    var pitch = 0.2
    var zoom = 1.0
    var bodyScale = 1.0
    var frame: HumanFrame?
    var telemetry = VoiceTelemetry()
    var bodyMix = BodyMix.male
    var animationEnabled = true
    var particlesEnabled = true

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let glowDepthState: MTLDepthStencilState
    private let coreDepthState: MTLDepthStencilState
    private let particles = AirflowParticleSystem()
    private var lastDrawTime = 0.0
    private var lastClock: Double?
    private var encodedBodyMix: BodyMix?
    private var nod: Float = 0
    private var nodVelocity: Float = 0
    private var sway: Float = 0
    private var swayVelocity: Float = 0

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat = .bgra8Unorm, sampleCount: Int = 4) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw ChimeraError(message: "A Metal command queue could not be created.")
        }
        self.commandQueue = commandQueue
        let library = try device.makeDefaultLibrary(bundle: Bundle.main)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "phosphor_vertex_3d")
        descriptor.fragmentFunction = library.makeFunction(name: "phosphor_fragment")
        descriptor.rasterSampleCount = sampleCount
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        descriptor.depthAttachmentPixelFormat = .depth32Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let glowDescriptor = MTLDepthStencilDescriptor()
        glowDescriptor.depthCompareFunction = .lessEqual
        glowDescriptor.isDepthWriteEnabled = false
        let coreDescriptor = MTLDepthStencilDescriptor()
        coreDescriptor.depthCompareFunction = .lessEqual
        coreDescriptor.isDepthWriteEnabled = true
        guard let glowDepthState = device.makeDepthStencilState(descriptor: glowDescriptor),
              let coreDepthState = device.makeDepthStencilState(descriptor: coreDescriptor) else {
            throw ChimeraError(message: "The 3D depth state could not be created.")
        }
        self.glowDepthState = glowDepthState
        self.coreDepthState = coreDepthState
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        particles.reset()
    }

    func resetMotion() {
        particles.reset()
        lastClock = nil
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = commandQueue.makeCommandBuffer() else { return }
        let size = view.drawableSize
        let renderView = HeadRenderView(
            viewport: MTLViewport(originX: 0, originY: 0, width: Double(size.width), height: Double(size.height), znear: 0, zfar: 1),
            scissor: nil,
            viewProjection: camera(size: size, yaw: yaw, pitch: pitch, zoom: zoom),
            pixelScale: Float(size.width / max(1, view.bounds.width))
        )
        encode(command: command, pass: descriptor, views: [renderView])
        command.present(drawable)
        command.commit()
    }

    func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, views: [HeadRenderView]) {
        autoreleasepool {
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            if encodedBodyMix != bodyMix {
                encodedBodyMix = bodyMix
                resetMotion()
            }
            let now = CACurrentMediaTime()
            let dt = lastDrawTime == 0 ? 1.0 / 60.0 : min(0.05, max(0, now - lastDrawTime))
            lastDrawTime = now
            if let lastClock, telemetry.clock < lastClock || telemetry.clock - lastClock > 1 {
                particles.reset()
            }
            lastClock = telemetry.clock
            updateMotion(dt: dt)

            var renderScene = scene
            if particlesEnabled, let frame {
                renderScene.lines.append(contentsOf: particles.lines(frame: frame, telemetry: telemetry, bodyScale: bodyScale, dt: dt))
            } else if !particlesEnabled {
                particles.reset()
            }
            let pixelScale = views.first?.pixelScale ?? 1
            var segments: [Segment3D] = []
            for line in renderScene.lines where line.points.count > 1 {
                for index in 0..<(line.points.count - 1) {
                    segments.append(Segment3D(start: line.points[index], end: line.points[index + 1], color: line.color, width: line.width * pixelScale))
                }
            }
            if !segments.isEmpty, let buffer = device.makeBuffer(bytes: segments, length: segments.count * MemoryLayout<Segment3D>.stride, options: .storageModeShared) {
                var modelTransform = headTransform()
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&modelTransform, length: MemoryLayout<matrix_float4x4>.size, index: 4)
                for renderView in views {
                    var viewProjection = renderView.viewProjection
                    var viewportSize = SIMD2<Float>(Float(renderView.viewport.width), Float(renderView.viewport.height))
                    encoder.setViewport(renderView.viewport)
                    if let scissor = renderView.scissor { encoder.setScissorRect(scissor) }
                    encoder.setVertexBytes(&viewProjection, length: MemoryLayout<matrix_float4x4>.size, index: 1)
                    encoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
                    for style in [SegmentStyle(extraWidth: 3 * pixelScale, alpha: 0.06), SegmentStyle(extraWidth: 1 * pixelScale, alpha: 0.13), SegmentStyle(extraWidth: 0, alpha: 1)] {
                        var style = style
                        encoder.setDepthStencilState(style.extraWidth == 0 ? coreDepthState : glowDepthState)
                        encoder.setVertexBytes(&style, length: MemoryLayout<SegmentStyle>.size, index: 3)
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: segments.count)
                    }
                }
            }
            encoder.endEncoding()
        }
    }

    private func updateMotion(dt: Double) {
        let activity = min(1, max(0, telemetry.outRMS * 4 + telemetry.gate * 0.3 + telemetry.voicing * 0.2))
        let speaking = telemetry.gate > 0.005 || telemetry.outRMS > 0.001 || telemetry.voicing > 0.01
        let pitch = min(1, max(0, (telemetry.f0 - 80) / 320))
        let clock = telemetry.clock
        let nodTarget = animationEnabled && speaking ? Float(0.012 * sin(clock * 1.31) + 0.025 * (pitch - 0.35) * activity) : 0
        let swayTarget = animationEnabled && speaking ? Float(0.009 * sin(clock * 0.73 + 0.4) * (0.35 + activity)) : 0
        spring(&nod, velocity: &nodVelocity, target: nodTarget, dt: dt)
        spring(&sway, velocity: &swayVelocity, target: swayTarget, dt: dt)
    }

    private func spring(_ value: inout Float, velocity: inout Float, target: Float, dt: Double) {
        let step = min(0.033, dt)
        velocity += ((target - value) * 80 - velocity * 17) * Float(step)
        value += velocity * Float(step)
    }

    private func headTransform() -> matrix_float4x4 {
        let pivot = SIMD3<Float>(-2.4 * Float(bodyScale), 1.5 * Float(bodyScale), 0)
        let nodMatrix = matrix_float4x4(
            SIMD4<Float>(cos(nod), sin(nod), 0, 0),
            SIMD4<Float>(-sin(nod), cos(nod), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        let swayMatrix = matrix_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(sway), sin(sway), 0),
            SIMD4<Float>(0, -sin(sway), cos(sway), 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return translation(pivot) * nodMatrix * swayMatrix * translation(-pivot)
    }

    private func translation(_ value: SIMD3<Float>) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(value.x, value.y, value.z, 1)
        return matrix
    }

    func camera(
        size: CGSize,
        yaw: Double,
        pitch: Double,
        zoom: Double,
        lateralOffset: Float = 0,
        fovDegrees: Double = 24,
        focusDistance: Double? = nil
    ) -> matrix_float4x4 {
        let k = Float(bodyScale)
        let target = SIMD3<Float>(0.3 * k, 9.2 * k, 0)
        let cp = Float(cos(pitch))
        let sp = Float(sin(pitch))
        let cy = Float(cos(yaw))
        let sy = Float(sin(yaw))
        let direction = simd_normalize(SIMD3<Float>(sy * cp, sp, cy * cp))
        let aspect = Float(max(1, size.width) / max(1, size.height))
        let fov = Float(fovDegrees * Double.pi / 180)
        let half = tan(fov * 0.5)
        let fittedDistance = 1.1 * max(15.2 / half, 11 / (half * max(0.3, aspect)))
        let distance = focusDistance.map { Float($0) / Float(zoom) } ?? fittedDistance / Float(zoom)
        let forward = simd_normalize(-direction)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let shift = right * lateralOffset
        let eye = target + direction * distance + shift
        let look = matrix_float4x4(
            SIMD4<Float>(right.x, up.x, -forward.x, 0),
            SIMD4<Float>(right.y, up.y, -forward.y, 0),
            SIMD4<Float>(right.z, up.z, -forward.z, 0),
            SIMD4<Float>(-simd_dot(right, eye), -simd_dot(up, eye), simd_dot(forward, eye), 1)
        )
        let y = 1 / half
        let near = Float(5)
        let far = Float(2_000)
        let projection = matrix_float4x4(
            SIMD4<Float>(y / aspect, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, far * near / (near - far), 0)
        )
        return projection * look
    }
}
