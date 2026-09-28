import Foundation

/// Abstraction over speech backends so engines are swappable
/// (Kokoro sidecar today; a cloud API or sherpa-onnx later).
protocol SpeechEngine: AnyObject {
    var name: String { get }

    /// Return available voice identifiers (may be empty if not applicable).
    func availableVoices() async -> [String]

    /// Synthesize one chunk of text into playable audio data (WAV),
    /// or `nil` if this engine plays audio itself (e.g. AVSpeechSynthesizer).
    func synthesize(text: String, voice: String, speed: Double) async throws -> Data?

    /// For engines that play audio themselves.
    func speakDirectly(text: String, voice: String, speed: Double)

    func stop()
}

enum SpeechEngineError: LocalizedError {
    case sidecarNotInstalled
    case synthesisFailed(String)

    var errorDescription: String? {
        switch self {
        case .sidecarNotInstalled:
            return "Kokoro voices are still installing — using system voices for now."
        case .synthesisFailed(let msg):
            return "Speech synthesis failed: \(msg)"
        }
    }
}

/// Splits text into sentence-ish chunks so playback can start quickly and
/// the next chunk synthesizes while the current one plays.
enum TextChunker {
    static func chunks(from text: String, maxLength: Int = 400) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        // Split on sentence enders and paragraph breaks, keeping the delimiter.
        var sentences: [String] = []
        var current = ""
        for ch in normalized {
            current.append(ch)
            if ".!?\n".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        // Merge short sentences up to maxLength for fewer round-trips.
        var result: [String] = []
        var buffer = ""
        for s in sentences {
            if buffer.isEmpty {
                buffer = s
            } else if buffer.count + s.count + 1 <= maxLength {
                buffer += " " + s
            } else {
                result.append(buffer)
                buffer = s
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }
}
