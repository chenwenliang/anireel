import AVFoundation
import AVKit
import SwiftUI

/// Full-bleed looping clip with no system chrome: the feed and the result screen.
/// Plays only while `isPlaying`, so off-screen feed pages cost nothing.
struct ClipSurface: View {
    let url: URL
    var isPlaying = true
    var isMuted = false
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    @State private var looping: LoopingPlayer

    init(url: URL, isPlaying: Bool = true, isMuted: Bool = false, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.url = url
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.gravity = gravity
        _looping = State(initialValue: LoopingPlayer(url: url))
    }

    var body: some View {
        PlayerLayerView(player: looping.player, gravity: gravity)
            .onAppear { update() }
            .onDisappear { looping.player.pause() }
            .onChange(of: isPlaying) { update() }
            .onChange(of: isMuted) { update() }
    }

    private func update() {
        looping.player.isMuted = isMuted
        if isPlaying { looping.player.play() } else { looping.player.pause() }
    }
}

/// Plays a clip in a seamless loop with the system controls (My Clips detail).
struct LoopingVideo: View {
    @State private var looping: LoopingPlayer

    init(url: URL) {
        _looping = State(initialValue: LoopingPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: looping.player)
            .onAppear { looping.player.play() }
            .onDisappear { looping.player.pause() }
    }
}

private final class LoopingPlayer {
    let player = AVQueuePlayer()
    private let looper: AVPlayerLooper

    init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.videoGravity = gravity
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
