import MetalKit
import simd

struct LineStrip {
    let points: [SIMD2<Float>]
    let color: SIMD4<Float>
    let width: Float
}

struct MetalScene {
    var lines: [LineStrip] = []
}

private struct VertexIn {
    let position: SIMD2<Float>
    let color: SIMD4<Float>
}

final class PhosphorRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    var scene = MetalScene()

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw ChimeraError(message: "A Metal command queue could not be created.")
        }
        self.commandQueue = commandQueue
        let library = try device.makeDefaultLibrary(bundle: Bundle.main)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "phosphor_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "phosphor_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        autoreleasepool {
            guard let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let command = commandQueue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }

            var vertices: [VertexIn] = []
            for line in scene.lines where line.points.count > 1 {
                append(line, width: line.width + 5, alpha: line.color.w * 0.12, to: &vertices)
                append(line, width: line.width + 2, alpha: line.color.w * 0.24, to: &vertices)
                append(line, width: line.width, alpha: line.color.w, to: &vertices)
            }
            if !vertices.isEmpty, let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<VertexIn>.stride, options: .storageModeShared) {
                var viewport = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }

    private func append(_ line: LineStrip, width: Float, alpha: Float, to vertices: inout [VertexIn]) {
        let color = SIMD4<Float>(line.color.x, line.color.y, line.color.z, alpha)
        for index in 0..<(line.points.count - 1) {
            let a = line.points[index]
            let b = line.points[index + 1]
            let delta = b - a
            let length = simd_length(delta)
            if length < 0.001 { continue }
            let normal = SIMD2<Float>(-delta.y, delta.x) / length * width * 0.5
            let a0 = a - normal
            let a1 = a + normal
            let b0 = b - normal
            let b1 = b + normal
            vertices.append(VertexIn(position: a0, color: color))
            vertices.append(VertexIn(position: a1, color: color))
            vertices.append(VertexIn(position: b1, color: color))
            vertices.append(VertexIn(position: a0, color: color))
            vertices.append(VertexIn(position: b1, color: color))
            vertices.append(VertexIn(position: b0, color: color))
        }
    }
}
