import Foundation
import AVFoundation

/// Fallback engine using Apple's built-in voices.
/// Used automatically when the Kokoro sidecar isn't installed yet,
/// so the app works out of the box.
final class SystemVoiceEngine: SpeechEngine {
    let name = "System (Apple voices)"

    private let synthesizer = AVSpeechSynthesizer()

    /// Best English voice actually installed on this Mac. Apple ships several
    /// quality tiers; `.premium` and `.enhanced` are downloads the user may or
    /// may not have, so this degrades to whatever is present.
    private static let bestEnglishVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        // AVSpeech reports BCP-47 ("en-GB"); Locale.identifier uses
        // underscores ("en_GB"), so it has to be normalized or nothing matches.
        let preferred = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let byQuality: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
        for quality in byQuality {
            // Prefer the user's own locale within a tier, so en-GB users are
            // not read to in an American accent.
            let tier = english.filter { $0.quality == quality }
            if let match = tier.first(where: { $0.language == preferred }) ?? tier.first {
                return match
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }()

    func availableVoices() async -> [String] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { $0.identifier }
    }

    func synthesize(text: String, voice: String, speed: Double) async throws -> Data? {
        nil // this engine plays audio itself
    }

    func speakDirectly(text: String, voice: String, speed: Double) {
        let utterance = AVSpeechUtterance(string: text)
        // `voice` is normally a Kokoro name like "af_heart", which is not an
        // AVSpeech identifier — this engine only runs while Kokoro is still
        // downloading. Rather than fall straight to the default (Alex, the
        // lowest-quality option), pick the best installed English voice so
        // the first impression is a fair one.
        utterance.voice = AVSpeechSynthesisVoice(identifier: voice) ?? Self.bestEnglishVoice
        // AVSpeech rate is 0...1 with 0.5 ≈ normal; map speed 0.5–2.0 around that.
        utterance.rate = Float(min(max(0.5 * speed, 0.1), 1.0))
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
