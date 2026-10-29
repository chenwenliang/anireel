import Metal
import SwiftUI

/// Cinematic 2.5D look: the AnimeGANv3 Shinkai model (Resources/Models/animegan_shinkai_<side>).
/// Without the model the style reports itself unavailable; NPR.metal is no longer used.
struct NPRStylePack: StylePack {
    static let id = StyleID(rawValue: "npr")
    static let modelName = "animegan_shinkai"

    let descriptor = StyleDescriptor(
        id: NPRStylePack.id,
        title: String(localized: "NPR Anime"),
        subtitle: String(localized: "Bright cinematic skies, clear light and detailed anime scenery."),
        symbolName: "cube.transparent",
        accent: .orange
    )

    func makeRenderer(context: MetalContext) throws -> StyleRenderer {
        try CoreMLStyleRenderer(context: context, modelName: Self.modelName, finish: KernelRenderer<Void>.resample(context: context))
    }
}
