import SwiftUI

/// Cute, bold look. A second Core ML slot (Resources/Models/animegan_chibi_<side>) feeds the
/// chibi post-pass when a model is bundled; without one the post-pass runs on the camera frame.
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
        let post = try KernelRenderer(context: context, kernel: "chibiPost", params: ChibiParams())
        return try CoreMLStyleRenderer.make(context: context, modelName: Self.modelName, finish: post, fallback: post)
    }
}

/// Mirrors `ChibiParams` in Chibi.metal; field order and types must match.
private struct ChibiParams {
    var spread: Float = 3
    var levels: Float = 4
    var saturation: Float = 1.6
    var outlineWidth: Float = 2.5
    var outlineLow: Float = 0.12
    var outlineHigh: Float = 0.3
}
