import CoreVideo
import Metal

/// Output size shared by preview and (Phase 2) recording, so what you see is what gets saved.
enum OutputFormat {
    static let width = 720
    static let height = 1280
}

/// Turns camera frames into stylized frames in pooled BGRA buffers. Called from the camera's video queue.
final class StyleEngine: @unchecked Sendable {
    private let context: MetalContext
    private let renderer: StyleRenderer
    private let pool: CVPixelBufferPool
    private let inFlight = DispatchSemaphore(value: 2)

    init(pack: any StylePack, context: MetalContext) throws {
        self.context = context
        self.renderer = try pack.makeRenderer(context: context)
        pool = try MetalContext.makePixelBufferPool(width: OutputFormat.width, height: OutputFormat.height)
    }

    /// Drops the frame when the GPU is already two frames behind, rather than queueing latency.
    func process(_ source: CVPixelBuffer, completion: @escaping @Sendable (CVPixelBuffer) -> Void) {
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
        renderer.encode(source: src.texture, destination: dst.texture, commandBuffer: commandBuffer)
        commandBuffer.addCompletedHandler { [inFlight] buffer in
            withExtendedLifetime((src, dst)) {}
            inFlight.signal()
            if buffer.status == .completed { completion(output) }
        }
        commandBuffer.commit()
    }
}
