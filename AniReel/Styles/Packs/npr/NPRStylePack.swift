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
        try KernelRenderer(context: context, kernel: "nprStylize", params: NPRParams())
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
