import Metal

/// A style step that is one compute kernel: it samples `source` and writes every pixel of
/// `destination`, so it also resamples between sizes. `Params` must mirror the kernel's
/// constant buffer layout; use `Void` for kernels without parameters.
final class KernelRenderer<Params>: StyleRenderer {
    private let pipeline: MTLComputePipelineState
    private var params: Params

    init(context: MetalContext, kernel: String, params: Params) throws {
        pipeline = try context.computePipeline(named: kernel)
        self.params = params
    }

    func encode(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        if MemoryLayout<Params>.size > 0 {
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        }
        encoder.dispatchThreads(
            MTLSize(width: destination.width, height: destination.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()
        return true
    }
}

extension KernelRenderer where Params == Void {
    /// Plain bilinear resample, used around ML inference.
    static func resample(context: MetalContext) throws -> KernelRenderer<Void> {
        try KernelRenderer(context: context, kernel: "styleResample", params: ())
    }
}
