import Foundation
import AVFoundation

/// Fallback engine using Apple's built-in voices.
/// Used automatically when the Kokoro sidecar isn't installed yet,
/// so the app works out of the box.
final class SystemVoiceEngine: SpeechEngine {
    let name = "System (Apple voices)"

    private let synthesizer = AVSpeechSynthesizer()

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
        if let v = AVSpeechSynthesisVoice(identifier: voice) {
            utterance.voice = v
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        // AVSpeech rate is 0...1 with 0.5 ≈ normal; map speed 0.5–2.0 around that.
        utterance.rate = Float(min(max(0.5 * speed, 0.1), 1.0))
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
