import MetalKit
import SwiftUI

/// Draws the most recent stylized frame, aspect-filled, or the unstyled source frame while the
/// user peeks. Frames arrive from the video queue; drawing happens on the main thread at the
/// display's pace. Peeking is preview-only: the recorder is fed separately.
final class PreviewRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let context: MetalContext
    private let pipeline: MTLRenderPipelineState
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var latestOriginal: CVPixelBuffer?
    private var showsOriginal = false

    init(context: MetalContext) throws {
        self.context = context
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = context.library.makeFunction(name: "previewVertex")
        descriptor.fragmentFunction = context.library.makeFunction(name: "previewFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try context.device.makeRenderPipelineState(descriptor: descriptor)
    }

    func display(_ stylized: CVPixelBuffer, original: CVPixelBuffer) {
        lock.withLock {
            latest = stylized
            latestOriginal = original
        }
    }

    func setShowsOriginal(_ value: Bool) {
        lock.withLock { showsOriginal = value }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let frame = lock.withLock { showsOriginal ? latestOriginal : latest }
        let wrapped = frame.flatMap(context.makeTexture(from:))
        if let texture = wrapped?.texture {
            var scale = aspectFillScale(texture: texture, drawable: view.drawableSize)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(wrapped) {} }
        commandBuffer.commit()
    }

    private func aspectFillScale(texture: MTLTexture, drawable: CGSize) -> SIMD2<Float> {
        guard drawable.width > 0, drawable.height > 0 else { return SIMD2(1, 1) }
        let textureAspect = Float(texture.width) / Float(texture.height)
        let viewAspect = Float(drawable.width / drawable.height)
        return textureAspect > viewAspect
            ? SIMD2(textureAspect / viewAspect, 1)
            : SIMD2(1, viewAspect / textureAspect)
    }
}

struct MetalPreview: UIViewRepresentable {
    let renderer: PreviewRenderer
    let device: MTLDevice

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.delegate = renderer
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}
