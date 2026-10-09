import AVFoundation
import Observation

/// Single shared player so starting one clip always stops the previous one.
@MainActor
@Observable
final class Player: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.isMeteringEnabled = true
        player.play()
        self.player = player
        playingURL = url
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    func isPlaying(_ url: URL) -> Bool { playingURL == url }

    /// 0...1 loudness right now. Polled by animations each frame instead of published, so playback
    /// doesn't re-render every view that observes the player.
    var level: Double {
        guard let player, player.isPlaying else { return 0 }
        player.updateMeters()
        let power = Double(player.averagePower(forChannel: 0))
        return max(0, min(1, (power + 42) / 42))
    }

    /// 0...1 position of the clip that is playing.
    var progress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }
}
