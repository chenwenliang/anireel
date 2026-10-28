import Metal
import SwiftUI

struct StyleID: RawRepresentable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

struct StyleDescriptor {
    let id: StyleID
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
}

/// A style plugs into the capture pipeline by turning one camera frame into one stylized frame.
/// The engine owns buffers and command submission, so a pack only encodes GPU work.
protocol StylePack {
    var descriptor: StyleDescriptor { get }
    func makeRenderer(context: MetalContext) throws -> StyleRenderer
}

protocol StyleRenderer: AnyObject {
    /// `source` is the portrait camera frame; `destination` is the output frame at `OutputFormat` size.
    func encode(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer)
}
