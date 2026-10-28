import AVFoundation
import CoreGraphics
import QuartzCore

/// Synthetic 30 fps portrait frames so styling, preview, recording and saving can be exercised
/// end to end where no camera exists (Simulator). No audio: clips are silent.
final class DemoFrameSource: FrameSource, @unchecked Sendable {
    var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?
    var onAudio: (@Sendable (CMSampleBuffer) -> Void)?
    var onInterrupted: (@Sendable () -> Void)?
    let requiresCameraPermission = false

    private let queue = DispatchQueue(label: "com.anireel.demo", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var configuration = CameraConfiguration()
    private var pool: CVPixelBufferPool?
    private let startedAt = CACurrentMediaTime()

    func start(_ configuration: CameraConfiguration) async throws {
        let pool = try MetalContext.makePixelBufferPool(width: OutputFormat.width, height: OutputFormat.height)
        queue.sync {
            self.configuration = configuration
            self.pool = pool
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(33))
            timer.setEventHandler { [weak self] in self?.emitFrame() }
            timer.resume()
            self.timer = timer
        }
    }

    func apply(_ configuration: CameraConfiguration) async throws {
        queue.sync { self.configuration = configuration }
    }

    func setAudioCapture(_ enabled: Bool) async -> Bool { false }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    private func emitFrame() {
        var buffer: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let buffer
        else { return }
        DemoScene.draw(into: buffer, time: CACurrentMediaTime() - startedAt, configuration: configuration)
        onFrame?(buffer, CMClockGetTime(CMClockGetHostTimeClock()))
    }
}

/// Back camera: a moving landscape whose house sits left of center, so mirroring is visible.
/// Front camera: a blinking face, standing in for a selfie.
private enum DemoScene {
    static func draw(into buffer: CVPixelBuffer, time t: Double, configuration: CameraConfiguration) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        let w = CGFloat(width)
        let h = CGFloat(height)
        context.translateBy(x: 0, y: h)
        context.scaleBy(x: 1, y: -1)
        if configuration.isMirrored {
            context.translateBy(x: w, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        switch configuration.position {
        case .back: landscape(context, w: w, h: h, t: t)
        case .front: face(context, w: w, h: h, t: t)
        }
    }

    private static func fill(_ context: CGContext, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ path: () -> Void) {
        context.setFillColor(red: r, green: g, blue: b, alpha: 1)
        path()
        context.fillPath()
    }

    private static func verticalGradient(_ context: CGContext, top: [CGFloat], bottom: [CGFloat], h: CGFloat) {
        let colors = [CGColor(red: top[0], green: top[1], blue: top[2], alpha: 1),
                      CGColor(red: bottom[0], green: bottom[1], blue: bottom[2], alpha: 1)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }

    private static func landscape(_ context: CGContext, w: CGFloat, h: CGFloat, t: Double) {
        verticalGradient(context, top: [0.42, 0.68, 0.95], bottom: [0.98, 0.86, 0.72], h: h * 0.6)
        fill(context, 1.0, 0.86, 0.35) { context.addEllipse(in: CGRect(x: w * 0.68, y: h * 0.12, width: 150, height: 150)) }

        let drift = CGFloat(t * 45).truncatingRemainder(dividingBy: w + 360) - 180
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        for (dx, dy, r) in [(0.0, 0.0, 60.0), (55, -20, 70), (115, 5, 55)] {
            context.addEllipse(in: CGRect(x: drift + dx, y: h * 0.2 + dy, width: r * 2, height: r * 1.4))
        }
        context.fillPath()

        let hills: [(base: CGFloat, amp: CGFloat, freq: CGFloat, speed: Double, rgb: (CGFloat, CGFloat, CGFloat))] = [
            (0.52, 40, 0.008, 0.3, (0.45, 0.66, 0.42)),
            (0.62, 55, 0.012, 0.5, (0.32, 0.55, 0.30)),
            (0.74, 35, 0.016, 0.8, (0.22, 0.42, 0.22)),
        ]
        for hill in hills {
            fill(context, hill.rgb.0, hill.rgb.1, hill.rgb.2) {
                context.move(to: CGPoint(x: 0, y: h))
                for x in stride(from: 0, through: w, by: 8) {
                    let y = h * hill.base + hill.amp * sin(x * hill.freq + CGFloat(t * hill.speed))
                    context.addLine(to: CGPoint(x: x, y: y))
                }
                context.addLine(to: CGPoint(x: w, y: h))
                context.closePath()
            }
        }

        let houseX = w * 0.18
        let houseY = h * 0.66
        fill(context, 0.96, 0.92, 0.82) { context.addRect(CGRect(x: houseX, y: houseY, width: 170, height: 130)) }
        fill(context, 0.78, 0.25, 0.2) {
            context.move(to: CGPoint(x: houseX - 20, y: houseY))
            context.addLine(to: CGPoint(x: houseX + 85, y: houseY - 90))
            context.addLine(to: CGPoint(x: houseX + 190, y: houseY))
            context.closePath()
        }
        fill(context, 0.35, 0.25, 0.2) { context.addRect(CGRect(x: houseX + 110, y: houseY + 55, width: 40, height: 75)) }
        fill(context, 0.55, 0.75, 0.95) { context.addRect(CGRect(x: houseX + 25, y: houseY + 35, width: 45, height: 40)) }

        let bounce = abs(sin(t * 2.2)) * 160
        fill(context, 0.98, 0.45, 0.6) { context.addEllipse(in: CGRect(x: w * 0.62, y: h * 0.86 - bounce, width: 90, height: 90)) }
    }

    private static func face(_ context: CGContext, w: CGFloat, h: CGFloat, t: Double) {
        verticalGradient(context, top: [0.93, 0.88, 0.98], bottom: [0.75, 0.82, 0.95], h: h)
        let cx = w / 2 + CGFloat(sin(t * 0.8)) * 30
        let cy = h * 0.45
        fill(context, 0.3, 0.2, 0.18) { context.addEllipse(in: CGRect(x: cx - 230, y: cy - 280, width: 460, height: 430)) }
        fill(context, 0.98, 0.84, 0.72) { context.addEllipse(in: CGRect(x: cx - 200, y: cy - 220, width: 400, height: 460)) }
        let blink = t.truncatingRemainder(dividingBy: 3) < 0.15 ? 0.1 : 1.0
        for dx in [-80.0, 80.0] {
            fill(context, 0.15, 0.12, 0.18) {
                context.addEllipse(in: CGRect(x: cx + dx - 22, y: cy - 30 - 30 * blink, width: 44, height: 60 * blink))
            }
        }
        fill(context, 0.95, 0.6, 0.6) {
            context.addEllipse(in: CGRect(x: cx - 150, y: cy + 40, width: 60, height: 36))
            context.addEllipse(in: CGRect(x: cx + 90, y: cy + 40, width: 60, height: 36))
        }
        context.setStrokeColor(red: 0.6, green: 0.25, blue: 0.3, alpha: 1)
        context.setLineWidth(12)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: cx, y: cy + 70), radius: 70, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
        context.strokePath()
        fill(context, 1.0, 0.8, 0.2) {
            let star = CGPoint(x: cx - 170, y: cy - 230)
            for i in 0..<10 {
                let angle = CGFloat(i) * .pi / 5 - .pi / 2
                let radius: CGFloat = i % 2 == 0 ? 40 : 16
                let point = CGPoint(x: star.x + radius * cos(angle), y: star.y + radius * sin(angle))
                if i == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.closePath()
        }
    }
}
