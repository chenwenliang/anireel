import SwiftUI

/// Hand-painted pastoral look. Runs the AnimeGANv3 Hayao model when it is bundled
/// (Resources/Models/animegan_hayao_<side>), otherwise a Metal approximation.
/// User-facing copy stays descriptive: no studio, film or character names.
struct GhibliStylePack: StylePack {
    static let id = StyleID(rawValue: "ghibli")
    static let modelName = "animegan_hayao"

    let descriptor = StyleDescriptor(
        id: GhibliStylePack.id,
        title: String(localized: "Hand-Painted Anime"),
        subtitle: String(localized: "Soft painted light, gentle lines and warm countryside colors."),
        symbolName: "leaf.fill",
        accent: .green
    )

    func makeRenderer(context: MetalContext) throws -> StyleRenderer {
        try CoreMLStyleRenderer.make(
            context: context,
            modelName: Self.modelName,
            finish: KernelRenderer<Void>.resample(context: context),
            fallback: KernelRenderer(context: context, kernel: "ghibliApprox", params: GhibliParams())
        )
    }
}

/// Mirrors `GhibliParams` in Ghibli.metal; field order and types must match.
private struct GhibliParams {
    var spread: Float = 1.5
    var levels: Float = 6
    var saturation: Float = 1.15
    var edgeStrength: Float = 0.45
}
