import AVFoundation
import Observation

/// Plays the selected recording: play/pause, ±15 s, seek, and 1× / 1.5× / 2× speed.
@MainActor
@Observable
final class PlaybackController {
    static let speeds: [Float] = [1, 1.5, 2]

    private(set) var loadedID: String?
    private(set) var isReady = false
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var progress: Double {
        duration > 0 ? min(1, currentTime / duration) : 0
    }

    /// Loads a recording. `url` is `nil` while there is no playable audio yet.
    func load(id: String, url: URL?, duration: TimeInterval) {
        guard id != loadedID || (player == nil && url != nil) else { return }
        stop()
        loadedID = id
        self.duration = duration
        currentTime = 0
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            isReady = false
            return
        }
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        self.player = player
        isReady = true
    }

    func unload() {
        stop()
        loadedID = nil
        duration = 0
        currentTime = 0
        isReady = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if currentTime >= duration - 0.05 { seek(to: 0) }
        player.rate = rate
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(duration, time))
        player?.currentTime = clamped
        currentTime = clamped
    }

    func seek(fraction: Double) {
        seek(to: fraction * duration)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    /// Seeks to a transcript line and plays from there.
    func play(from time: TimeInterval) {
        seek(to: time)
        play()
    }

    private func stop() {
        pause()
        player?.stop()
        player = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    if self.duration - player.currentTime < 0.2 { self.currentTime = self.duration }
                    return
                }
            }
        }
    }
}
