import CoreVideo
import Metal

enum MetalContextError: Error {
    case unavailable
    case missingFunction(String)
}

/// One device, queue, shader library and texture cache shared by every renderer.
final class MetalContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let textureCache: CVMetalTextureCache

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw MetalContextError.unavailable }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache
        else { throw MetalContextError.unavailable }
        self.device = device
        self.commandQueue = queue
        self.library = library
        self.textureCache = cache
    }

    func computePipeline(named name: String) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: name) else { throw MetalContextError.missingFunction(name) }
        return try device.makeComputePipelineState(function: function)
    }

    /// Wraps a BGRA pixel buffer as a texture without copying.
    func makeTexture(from pixelBuffer: CVPixelBuffer) -> PixelBufferTexture? {
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &cvTexture
        )
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return PixelBufferTexture(texture: texture, backing: cvTexture)
    }
}

/// The cache-backed texture is only valid while `backing` is alive, so hold this value
/// until the GPU work that touches `texture` has completed.
struct PixelBufferTexture {
    let texture: MTLTexture
    let backing: CVMetalTexture
}
