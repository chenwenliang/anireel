import CoreVideo
import Foundation
import Metal

/// Output size shared by preview and (Phase 2) recording, so what you see is what gets saved.
enum OutputFormat {
    static let width = 720
    static let height = 1280
}

/// Turns camera frames into stylized frames in pooled BGRA buffers. Called from the camera's video queue.
final class StyleEngine: @unchecked Sendable {
    private let context: MetalContext
    private var renderer: StyleRenderer
    private let rendererLock = NSLock()
    private let pool: CVPixelBufferPool
    private let inFlight = DispatchSemaphore(value: 2)

    init(renderer: StyleRenderer, context: MetalContext) throws {
        self.context = context
        self.renderer = renderer
        pool = try MetalContext.makePixelBufferPool(width: OutputFormat.width, height: OutputFormat.height)
    }

    /// Switches the live style. The next frame uses the new renderer; a frame already encoding
    /// keeps the old one alive until it returns.
    func setRenderer(_ next: StyleRenderer) {
        rendererLock.withLock { renderer = next }
    }

    /// Drops the frame when the GPU is already two frames behind, rather than queueing latency.
    /// `completion` gets the output frame and whether it is stylized (see `StyleRenderer.encode`).
    func process(_ source: CVPixelBuffer, completion: @escaping @Sendable (CVPixelBuffer, Bool) -> Void) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard let output,
              let src = context.makeTexture(from: source),
              let dst = context.makeTexture(from: output),
              let commandBuffer = context.commandQueue.makeCommandBuffer()
        else {
            inFlight.signal()
            return
        }
        let renderer = rendererLock.withLock { self.renderer }
        let isStylized = renderer.encode(source: src.texture, destination: dst.texture, commandBuffer: commandBuffer)
        commandBuffer.addCompletedHandler { [inFlight] buffer in
            withExtendedLifetime((src, dst)) {}
            inFlight.signal()
            if buffer.status == .completed { completion(output, isStylized) }
        }
        commandBuffer.commit()
    }
}
