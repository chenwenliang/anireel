import Metal
import SwiftUI

struct NPRStylePack: StylePack {
    static let id = StyleID(rawValue: "npr")

    let descriptor = StyleDescriptor(
        id: NPRStylePack.id,
        title: String(localized: "NPR Anime"),
        subtitle: String(localized: "Flat cel shading, ink outlines and paper grain."),
        symbolName: "cube.transparent",
        accent: .orange
    )

    func makeRenderer(context: MetalContext) throws -> StyleRenderer {
        try NPRRenderer(context: context)
    }
}

/// Mirrors `NPRParams` in NPR.metal; field order and types must match.
private struct NPRParams {
    var levels: Float = 5
    var saturation: Float = 1.25
    var edgeLow: Float = 0.18
    var edgeHigh: Float = 0.45
    var paperStrength: Float = 0.08
}

private final class NPRRenderer: StyleRenderer {
    private let pipeline: MTLComputePipelineState
    private var params = NPRParams()

    init(context: MetalContext) throws {
        pipeline = try context.computePipeline(named: "nprStylize")
    }

    func encode(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<NPRParams>.stride, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: destination.width, height: destination.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()
    }
}
