import AVFoundation
import GeigerCore

/// Plays the geiger click in-process via a small pool of AVAudioPlayers,
/// so rapid clicks can overlap without spawning processes.
final class ClickAudio {
    private static let mutedKey = "clicksMuted"

    private var players: [AVAudioPlayer] = []
    private var next = 0

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.mutedKey) }
    }

    init() {
        let data = makeClickWavData()
        for _ in 0..<8 {
            if let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
                p.prepareToPlay()
                players.append(p)
            }
        }
    }

    func click() {
        guard !muted, !players.isEmpty else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.currentTime = 0
        p.play()
    }
}
