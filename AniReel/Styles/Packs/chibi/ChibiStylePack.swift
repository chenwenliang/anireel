import SwiftUI

/// Cute, bold look. Model slot Resources/Models/animegan_chibi_<side>: no official model fits it
/// yet (docs/MODELS.md), so the style reports itself unavailable; Chibi.metal is no longer used.
struct ChibiStylePack: StylePack {
    static let id = StyleID(rawValue: "chibi")
    static let modelName = "animegan_chibi"

    let descriptor = StyleDescriptor(
        id: ChibiStylePack.id,
        title: String(localized: "Chibi Pop"),
        subtitle: String(localized: "Thick outlines, candy colors and rounded shapes."),
        symbolName: "face.smiling.inverse",
        accent: .pink
    )

    func makeRenderer(context: MetalContext) throws -> StyleRenderer {
        try CoreMLStyleRenderer(context: context, modelName: Self.modelName, finish: KernelRenderer<Void>.resample(context: context))
    }
}
