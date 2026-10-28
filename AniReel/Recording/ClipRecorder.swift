import AVFoundation

struct RecordedClip {
    let url: URL
    let duration: TimeInterval
}

enum ClipRecorderError: Error {
    case cannotStart
    case notRecording
    case writeFailed
}

/// Writes stylized frames (the same buffers the preview shows) plus optional mic audio to an
/// H.264/AAC MP4. All writer access is serialized on `queue`; appends outside a session are dropped.
final class ClipRecorder: @unchecked Sendable {
    var onProgress: (@Sendable (TimeInterval) -> Void)?
    var onFailure: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "com.anireel.recorder")
    private var session: Session?

    private static let frameDuration = CMTime(value: 1, timescale: 30)
    private static let limit = CMTime(seconds: DurationGuard.limit, preferredTimescale: 600)

    private final class Session {
        let url: URL
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let audio: AVAssetWriterInput?
        var start: CMTime?
        var last: CMTime?

        init(url: URL, includeAudio: Bool) throws {
            self.url = url
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: OutputFormat.width,
                AVVideoHeightKey: OutputFormat.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ])
            video.expectsMediaDataInRealTime = true
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: OutputFormat.width,
                kCVPixelBufferHeightKey as String: OutputFormat.height,
            ])
            guard writer.canAdd(video) else { throw ClipRecorderError.cannotStart }
            writer.add(video)

            if includeAudio {
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 96_000,
                ])
                audio.expectsMediaDataInRealTime = true
                guard writer.canAdd(audio) else { throw ClipRecorderError.cannotStart }
                writer.add(audio)
                self.audio = audio
            } else {
                self.audio = nil
            }

            guard writer.startWriting() else { throw writer.error ?? ClipRecorderError.cannotStart }
        }
    }

    func start(url: URL, includeAudio: Bool) throws {
        let session = try Session(url: url, includeAudio: includeAudio)
        queue.sync { self.session = session }
    }

    /// The first frame starts the clip timeline; frames past the 30 s cap are dropped.
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        queue.async { [self] in
            guard let session else { return }
            let start = session.start ?? time
            if session.start == nil {
                session.writer.startSession(atSourceTime: time)
                session.start = time
            }
            let elapsed = (time - start).seconds
            guard elapsed < DurationGuard.limit else {
                onProgress?(elapsed)
                return
            }
            if session.video.isReadyForMoreMediaData {
                if session.adaptor.append(pixelBuffer, withPresentationTime: time) {
                    session.last = time
                } else if session.writer.status == .failed {
                    fail(session)
                    return
                }
            }
            onProgress?(elapsed)
        }
    }

    /// Audio before the first video frame or past the cap is dropped so both tracks share one timeline.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [self] in
            guard let session, let audio = session.audio, let start = session.start else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard time >= start, time - start < Self.limit, audio.isReadyForMoreMediaData else { return }
            audio.append(sampleBuffer)
        }
    }

    func finish(completion: @escaping @Sendable (Result<RecordedClip, Error>) -> Void) {
        queue.async { [self] in
            guard let session else {
                completion(.failure(ClipRecorderError.notRecording))
                return
            }
            self.session = nil
            guard let start = session.start, let last = session.last else {
                session.writer.cancelWriting()
                completion(.success(RecordedClip(url: session.url, duration: 0)))
                return
            }
            let end = CMTimeMinimum(last + Self.frameDuration, start + Self.limit)
            session.writer.endSession(atSourceTime: end)
            session.video.markAsFinished()
            session.audio?.markAsFinished()
            session.writer.finishWriting {
                if session.writer.status == .completed {
                    completion(.success(RecordedClip(url: session.url, duration: (end - start).seconds)))
                } else {
                    completion(.failure(session.writer.error ?? ClipRecorderError.writeFailed))
                }
            }
        }
    }

    private func fail(_ session: Session) {
        session.writer.cancelWriting()
        self.session = nil
        onFailure?()
    }
}
