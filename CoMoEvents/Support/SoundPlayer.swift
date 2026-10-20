import AVFoundation
import Foundation

/// Two small, soft sounds: a welcome chime when the app opens and a pluck when an event is saved.
/// Both are synthesised in memory (sine tones with a gentle envelope), so there are no audio
/// assets to ship. Uses the `.ambient` session: respects the silent switch and never pauses music.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Sound { case welcome, favorite }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sounds.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sounds.enabled") }
    }

    private var players: [String: AVAudioPlayer] = [:]
    private var sessionReady = false

    func play(_ sound: Sound) {
        guard Self.enabled else { return }
        prepareSession()
        let key = "\(sound)"
        if players[key] == nil, let p = try? AVAudioPlayer(data: Self.render(sound)) {
            p.volume = sound == .welcome ? 0.55 : 0.5
            p.prepareToPlay()
            players[key] = p
        }
        guard let p = players[key] else { return }
        p.currentTime = 0
        p.play()
    }

    private func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: synthesis

    private struct Note { let hz: Double; let at: Double; let dur: Double; let gain: Double }

    private static func notes(for s: Sound) -> (notes: [Note], length: Double) {
        switch s {
        case .welcome:
            // Soft ascending major triad with a held top note: C5 E5 G5, then C6 fading out.
            return ([Note(hz: 523.25, at: 0.00, dur: 0.55, gain: 0.8),
                     Note(hz: 659.25, at: 0.16, dur: 0.55, gain: 0.8),
                     Note(hz: 783.99, at: 0.32, dur: 0.70, gain: 0.85),
                     Note(hz: 1046.5, at: 0.50, dur: 0.95, gain: 0.6)], 1.5)
        case .favorite:
            // Short two-note pluck: G5 then C6.
            return ([Note(hz: 783.99, at: 0.00, dur: 0.22, gain: 0.9),
                     Note(hz: 1046.5, at: 0.09, dur: 0.30, gain: 0.8)], 0.42)
        }
    }

    /// 16-bit mono WAV at 44.1 kHz.
    private static func render(_ s: Sound) -> Data {
        let rate = 44_100.0
        let (notes, length) = notes(for: s)
        let n = Int(rate * length)
        var samples = [Float](repeating: 0, count: n)
        for note in notes {
            let start = Int(note.at * rate), count = Int(note.dur * rate)
            for i in 0..<count where start + i < n {
                let t = Double(i) / rate
                // Bell-like envelope: quick 12 ms attack, exponential decay.
                let attack = min(1, t / 0.012)
                let env = attack * exp(-t * (3.2 / note.dur))
                let tone = sin(2 * .pi * note.hz * t) + 0.25 * sin(2 * .pi * note.hz * 2 * t) + 0.08 * sin(2 * .pi * note.hz * 3 * t)
                samples[start + i] += Float(env * note.gain * tone / 1.33)
            }
        }
        // Soft limiter so overlapping notes never clip.
        let peak = max(samples.map { abs($0) }.max() ?? 1, 0.001)
        let scale = min(1, 0.9 / peak)
        var pcm = Data(capacity: n * 2)
        for v in samples {
            var i = Int16(max(-1, min(1, v * scale)) * 32_767)
            withUnsafeBytes(of: &i) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        wav.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); wav.append(pcm)
        return wav
    }
}
