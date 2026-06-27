import AppKit

final class SoundPlayer {
    private var lastPlayedAt: Date = .distantPast
    let cooldown: TimeInterval = 0.75

    // DISABLED — these legacy system beeps (Ping for waiting, Glass.wav for
    // done) doubled the app's own SFX. AgentTAB now plays only its `SoundFX`
    // cues: awp-shot on waiting, gun-shot on finish. Kept as no-ops so the
    // existing call sites stay valid without making any sound.
    func playWaiting() { /* no-op — see SoundFX.waiting (awp-shot) */ }

    func playDone() { /* no-op — see SoundFX.shot (gun-shot) */ }

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
