import SwiftUI

/// Hand-painted pastoral look: the AnimeGANv3 Hayao model (Resources/Models/animegan_hayao_<side>).
/// Without the model the style reports itself unavailable; Ghibli.metal is no longer used.
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
        try CoreMLStyleRenderer(context: context, modelName: Self.modelName, finish: KernelRenderer<Void>.resample(context: context))
    }
}
