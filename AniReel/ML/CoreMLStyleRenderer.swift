import CoreML
import Foundation
import Metal
import QuartzCore
import os

enum CoreMLStyleError: Error {
    case modelUnusable
    case outOfResources
}

/// Shared runtime for ML style packs: camera frame → resample to inference size → Core ML →
/// `finish` pass at output size. Runs on the camera's video queue and blocks it for the
/// inference; late camera frames are discarded upstream.
///
/// There is no shader fallback. Without a bundled model, or after a load or inference error,
/// every frame is a dimmed grey placeholder reported as unstyled (never recorded) and
/// `onStatus` says why.
final class CoreMLStyleRenderer: StyleRenderer {
    private struct Stage {
        let side: Int
        let model: MLModel
        let inputName: String
        let outputName: String
        let inputPool: CVPixelBufferPool
        let outputPool: CVPixelBufferPool
    }

    /// Called on the video queue whenever the status changes, and once per stats window while running.
    var onStatus: (@Sendable (StyleModelStatus) -> Void)?
    let initialStatus: StyleModelStatus
    /// Bundled sizes, largest first; the camera screen cycles through them.
    let availableSides: [Int]

    private let context: MetalContext
    private let modelURLs: [Int: URL]
    private let resample: KernelRenderer<Void>
    private let placeholder: KernelRenderer<Void>
    private let finish: StyleRenderer
    private var governor: InferenceGovernor?
    private var stage: Stage?
    private var failure: StyleModelStatus.UnavailableReason?
    private let requestLock = NSLock()
    private var requestedSide: Int?
    private var window = StatsWindow()

    private static let log = Logger(subsystem: "com.anireel.app", category: "coreml")

    init(context: MetalContext, modelName: String, finish: StyleRenderer) throws {
        let urls = InferenceGovernor.ladder.reduce(into: [Int: URL]()) { urls, side in
            urls[side] = Bundle.main.url(forResource: "\(modelName)_\(side)", withExtension: "mlmodelc")
        }
        let sides = InferenceGovernor.ladder.filter { urls[$0] != nil }
        let tier = DeviceTier.current ?? .a13
        let governor = InferenceGovernor(startingAt: tier.inferenceSize, available: Set(sides))
        modelURLs = urls
        availableSides = sides
        self.governor = governor
        initialStatus = governor == nil ? .unavailable(.notBundled) : .loading
        failure = governor == nil ? .notBundled : nil
        self.context = context
        self.finish = finish
        resample = try .resample(context: context)
        placeholder = try KernelRenderer(context: context, kernel: "styleUnavailable", params: ())
        let bundled = sides.map(String.init).joined(separator: ",")
        let units = Self.computeUnitsName
        Self.log.info("\(modelName, privacy: .public): bundled sizes [\(bundled, privacy: .public)], compute units \(units, privacy: .public)")
    }

    /// Restarts inference at `side` (one of `availableSides`) from the next frame. Called from the main thread.
    func requestSide(_ side: Int) {
        requestLock.withLock { requestedSide = side }
    }

    func encode(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        applyRequestedSide()
        guard failure == nil, let governor else {
            _ = placeholder.encode(source: source, destination: destination, commandBuffer: commandBuffer)
            return false
        }
        let started = CACurrentMediaTime()
        let stylized: PixelBufferTexture
        do {
            stylized = try infer(source)
        } catch {
            fail((error as? CoreMLStyleError) == .outOfResources ? .outOfResources : .inferenceFailed, error)
            _ = placeholder.encode(source: source, destination: destination, commandBuffer: commandBuffer)
            return false
        }
        guard finish.encode(source: stylized.texture, destination: destination, commandBuffer: commandBuffer) else {
            fail(.outOfResources, CoreMLStyleError.outOfResources)
            _ = placeholder.encode(source: source, destination: destination, commandBuffer: commandBuffer)
            return false
        }
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(stylized) {} }
        var next = governor
        if next.record(frameTime: CACurrentMediaTime() - started, thermal: ProcessInfo.processInfo.thermalState) {
            let side = next.side
            Self.log.notice("stepping down to \(side) (slow frames or thermal state)")
            stage = nil
            window = StatsWindow()
        }
        self.governor = next
        return true
    }

    private func applyRequestedSide() {
        guard let side = requestLock.withLock({ defer { requestedSide = nil }; return requestedSide }),
              failure == nil,
              let next = InferenceGovernor(startingAt: side, available: Set(availableSides))
        else { return }
        governor = next
        stage = nil
        window = StatsWindow()
        onStatus?(.loading)
    }

    private func infer(_ source: MTLTexture) throws -> PixelBufferTexture {
        let stage = try currentStage()
        let prepareStart = CACurrentMediaTime()
        guard let input = makeBuffer(stage.inputPool),
              let output = makeBuffer(stage.outputPool),
              let inputTexture = context.makeTexture(from: input),
              let prepass = context.commandQueue.makeCommandBuffer(),
              resample.encode(source: source, destination: inputTexture.texture, commandBuffer: prepass)
        else { throw CoreMLStyleError.outOfResources }
        prepass.commit()
        prepass.waitUntilCompleted()
        guard prepass.status == .completed else { throw CoreMLStyleError.outOfResources }

        let inferenceStart = CACurrentMediaTime()
        let options = MLPredictionOptions()
        options.outputBackings = [stage.outputName: output]
        let features = try MLDictionaryFeatureProvider(dictionary: [stage.inputName: MLFeatureValue(pixelBuffer: input)])
        _ = try stage.model.prediction(from: features, options: options)
        let done = CACurrentMediaTime()
        guard let texture = context.makeTexture(from: output) else { throw CoreMLStyleError.outOfResources }

        if let stats = window.add(side: stage.side, inference: done - inferenceStart, prepare: inferenceStart - prepareStart, now: done) {
            onStatus?(.running(stats))
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            Self.log.info("side \(stage.side) \(stats.width)x\(stats.height): \(stats.framesPerSecond, format: .fixed(precision: 1)) fps, inference p50 \(stats.inferenceP50 * 1000, format: .fixed(precision: 1)) ms p95 \(stats.inferenceP95 * 1000, format: .fixed(precision: 1)) ms, prepare p50 \(stats.prepareP50 * 1000, format: .fixed(precision: 1)) ms, thermal \(thermal), footprint \(Self.footprintMB()) MB")
        }
        return texture
    }

    /// Loads the model for the governor's current side on first use and after each size change.
    private func currentStage() throws -> Stage {
        guard let governor else { throw CoreMLStyleError.modelUnusable }
        if let stage, stage.side == governor.side { return stage }
        guard let url = modelURLs[governor.side] else { throw CoreMLStyleError.modelUnusable }
        let model: MLModel
        do {
            model = try Self.loadModel(at: url)
        } catch {
            fail(.loadFailed, error)
            throw error
        }
        let description = model.modelDescription
        guard let inputName = description.inputDescriptionsByName.first(where: { $0.value.type == .image })?.key,
              let outputName = description.outputDescriptionsByName.first(where: { $0.value.type == .image })?.key
        else {
            fail(.loadFailed, CoreMLStyleError.modelUnusable)
            throw CoreMLStyleError.modelUnusable
        }
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

    /// Reports the first error only; the renderer then stays on the placeholder until the
    /// style is selected again.
    private func fail(_ reason: StyleModelStatus.UnavailableReason, _ error: Error) {
        guard failure == nil else { return }
        failure = reason
        stage = nil
        Self.log.error("model unavailable (\(String(describing: reason), privacy: .public)): \(String(describing: error), privacy: .public)")
        onStatus?(.unavailable(reason))
    }

    private func makeBuffer(_ pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }

    // MARK: - Model cache

    /// Each model is compiled and loaded once per process, so switching styles or sizes back
    /// and forth never reloads it.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [URL: MLModel] = [:]

    private static func loadModel(at url: URL) throws -> MLModel {
        try cacheLock.withLock {
            if let model = cache[url] { return model }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = computeUnits
            let started = CACurrentMediaTime()
            let model = try MLModel(contentsOf: url, configuration: configuration)
            log.info("loaded \(url.lastPathComponent, privacy: .public) in \((CACurrentMediaTime() - started) * 1000, format: .fixed(precision: 0)) ms")
            cache[url] = model
            return model
        }
    }

    /// `.all` (CPU, GPU and Neural Engine) unless the launch argument
    /// `-CoreMLComputeUnits cpuAndNeuralEngine|cpuAndGPU|cpuOnly` asks for a comparison run.
    private static var computeUnitsName: String {
        UserDefaults.standard.string(forKey: "CoreMLComputeUnits") ?? "all"
    }

    private static var computeUnits: MLComputeUnits {
        switch computeUnitsName {
        case "cpuAndNeuralEngine": .cpuAndNeuralEngine
        case "cpuAndGPU": .cpuAndGPU
        case "cpuOnly": .cpuOnly
        default: .all
        }
    }

    private static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}

/// Collects about one second of inference timings, then turns them into `InferenceStats`.
/// Windows are back to back, so frames per second is completed inferences over wall time.
private struct StatsWindow {
    static let length: TimeInterval = 1
    private var start: TimeInterval?
    private var inference: [TimeInterval] = []
    private var prepare: [TimeInterval] = []

    init(start: TimeInterval? = nil) {
        self.start = start
    }

    mutating func add(side: Int, inference time: TimeInterval, prepare prepareTime: TimeInterval, now: TimeInterval) -> InferenceStats? {
        let start = self.start ?? now - time - prepareTime
        self.start = start
        inference.append(time)
        prepare.append(prepareTime)
        guard now - start >= Self.length else { return nil }
        defer { self = StatsWindow(start: now) }
        return InferenceStats(side: side, inferenceTimes: inference, prepareTimes: prepare, elapsed: now - start)
    }
}
