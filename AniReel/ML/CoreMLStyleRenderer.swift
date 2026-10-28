import CoreML
import Foundation
import Metal
import QuartzCore

enum CoreMLStyleError: Error {
    case modelUnusable
}

/// Shared runtime for ML style packs: camera frame → resample to inference size → Core ML →
/// `finish` pass at output size. Runs on the camera's video queue and blocks it for the
/// inference; late camera frames are discarded upstream. Any ML failure renders `fallback`.
final class CoreMLStyleRenderer: StyleRenderer {
    private struct Stage {
        let side: Int
        let model: MLModel
        let inputName: String
        let outputName: String
        let inputPool: CVPixelBufferPool
        let outputPool: CVPixelBufferPool
    }

    private let context: MetalContext
    private let modelURLs: [Int: URL]
    private let resample: KernelRenderer<Void>
    private let finish: StyleRenderer
    private let fallback: StyleRenderer
    private var governor: InferenceGovernor
    private var stage: Stage?
    private var mlFailed = false

    /// Returns `fallback` itself when the pack ships no usable model for this device.
    static func make(
        context: MetalContext,
        modelName: String,
        finish: StyleRenderer,
        fallback: StyleRenderer
    ) throws -> StyleRenderer {
        let urls = InferenceGovernor.ladder.reduce(into: [Int: URL]()) { urls, side in
            urls[side] = Bundle.main.url(forResource: "\(modelName)_\(side)", withExtension: "mlmodelc")
        }
        let tier = DeviceTier.current ?? .a13
        guard let governor = InferenceGovernor(startingAt: tier.inferenceSize, available: Set(urls.keys)) else {
            return fallback
        }
        return try CoreMLStyleRenderer(context: context, modelURLs: urls, governor: governor, finish: finish, fallback: fallback)
    }

    private init(
        context: MetalContext,
        modelURLs: [Int: URL],
        governor: InferenceGovernor,
        finish: StyleRenderer,
        fallback: StyleRenderer
    ) throws {
        self.context = context
        self.modelURLs = modelURLs
        self.governor = governor
        self.finish = finish
        self.fallback = fallback
        resample = try .resample(context: context)
    }

    func encode(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let started = CACurrentMediaTime()
        guard !mlFailed, let stylized = infer(source) else {
            fallback.encode(source: source, destination: destination, commandBuffer: commandBuffer)
            return
        }
        finish.encode(source: stylized.texture, destination: destination, commandBuffer: commandBuffer)
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(stylized) {} }
        if governor.record(frameTime: CACurrentMediaTime() - started, thermal: ProcessInfo.processInfo.thermalState) {
            stage = nil
        }
    }

    private func infer(_ source: MTLTexture) -> PixelBufferTexture? {
        do {
            let stage = try currentStage()
            guard let input = makeBuffer(stage.inputPool),
                  let output = makeBuffer(stage.outputPool),
                  let inputTexture = context.makeTexture(from: input),
                  let prepass = context.commandQueue.makeCommandBuffer()
            else { return nil }
            resample.encode(source: source, destination: inputTexture.texture, commandBuffer: prepass)
            prepass.commit()
            prepass.waitUntilCompleted()

            let options = MLPredictionOptions()
            options.outputBackings = [stage.outputName: output]
            let features = try MLDictionaryFeatureProvider(dictionary: [stage.inputName: MLFeatureValue(pixelBuffer: input)])
            _ = try stage.model.prediction(from: features, options: options)
            return context.makeTexture(from: output)
        } catch {
            mlFailed = true
            return nil
        }
    }

    /// Loads the model for the governor's current side on first use and after each step down.
    private func currentStage() throws -> Stage {
        if let stage, stage.side == governor.side { return stage }
        guard let url = modelURLs[governor.side] else { throw CoreMLStyleError.modelUnusable }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let description = model.modelDescription
        guard let inputName = description.inputDescriptionsByName.first(where: { $0.value.type == .image })?.key,
              let outputName = description.outputDescriptionsByName.first(where: { $0.value.type == .image })?.key
        else { throw CoreMLStyleError.modelUnusable }
        let size = InferenceGovernor.frameSize(for: governor.side)
        let next = Stage(
            side: governor.side,
            model: model,
            inputName: inputName,
            outputName: outputName,
            inputPool: try MetalContext.makePixelBufferPool(width: size.width, height: size.height),
            outputPool: try MetalContext.makePixelBufferPool(width: size.width, height: size.height)
        )
        stage = next
        return next
    }

    private func makeBuffer(_ pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}
