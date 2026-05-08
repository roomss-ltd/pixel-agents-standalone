import AppKit

final class SoundPlayer {
    private var lastPlayedAt: Date = .distantPast
    let cooldown: TimeInterval = 0.75

    func playWaiting() { play(systemNamed: "Ping") }

    func playDone() {
        guard let url = Bundle.main.url(forResource: "Glass", withExtension: "wav",
                                        subdirectory: "sounds"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        playWithCooldown(sound)
    }

    private func play(systemNamed name: String) {
        guard let sound = NSSound(named: name) else { return }
        playWithCooldown(sound)
    }

    private func playWithCooldown(_ sound: NSSound) {
        guard Date().timeIntervalSince(lastPlayedAt) > cooldown else { return }
        sound.play()
        lastPlayedAt = Date()
    }
}
