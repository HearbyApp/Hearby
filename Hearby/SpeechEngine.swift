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
///
/// Nothing is heard until the first chunk is fully synthesized, so it is kept
/// short (`firstChunkLength`); each later chunk may be twice the previous
/// one, up to `maxLength`. Larger later chunks mean fewer seams, and they
/// synthesize while the earlier, shorter ones are already playing.
enum TextChunker {
    static func chunks(from text: String, maxLength: Int = 400, firstChunkLength: Int = 100) -> [String] {
        groupedChunks(from: text, maxLength: maxLength, firstChunkLength: firstChunkLength)
            .map { $0.joined(separator: " ") }
    }

    /// The same chunks, each as the sentences it was merged from. The
    /// follow-along panel highlights one sentence at a time while the voice is
    /// handed the whole chunk.
    static func groupedChunks(
        from text: String, maxLength: Int = 400, firstChunkLength: Int = 100
    ) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        // Split on sentence enders and paragraph breaks, keeping the delimiter.
        // A period ends a sentence only at the end of a word, so "github.com",
        // "v1.0" and "3.5" stay whole, and not after a known abbreviation, so
        // the voice doesn't pause between "Dr." and the name.
        let characters = Array(normalized)
        var sentences: [String] = []
        var current = ""
        for (i, ch) in characters.enumerated() {
            current.append(ch)
            let atWordEnd = i + 1 == characters.count || characters[i + 1].isWhitespace
            guard ch == "\n" || (atWordEnd && endsSentence(current, with: ch)) else { continue }
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            current = ""
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        // Merge short sentences up to the current limit for fewer seams, and
        // break any sentence too long for it at a clause or word boundary.
        var result: [[String]] = []
        var buffer: [String] = []
        var bufferLength = 0
        var index = 0
        while index < sentences.count {
            let limit = min(maxLength, firstChunkLength << min(result.count, 16))
            let s = sentences[index]
            if buffer.isEmpty {
                if s.count <= limit {
                    buffer = [s]
                    bufferLength = s.count
                    index += 1
                } else {
                    let (head, rest) = splitHead(of: s, limit: limit)
                    result.append([head])
                    sentences[index] = rest
                }
            } else if bufferLength + s.count + 1 <= limit {
                buffer.append(s)
                bufferLength += s.count + 1
                index += 1
            } else {
                result.append(buffer)
                buffer = []
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }

    /// Periods that do not end a sentence. A miss only costs a pause, so this
    /// covers the common cases rather than every abbreviation in English.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc", "inc", "ltd",
        "co", "corp", "no", "fig", "approx", "dept", "est", "e.g", "i.e", "a.m", "p.m",
        "u.s", "u.k",
    ]

    private static func endsSentence(_ text: String, with ch: Character) -> Bool {
        guard ch == "." else { return ch == "!" || ch == "?" }
        let word = text.dropLast()
            .split(whereSeparator: \.isWhitespace).last
            .map { $0.drop(while: { "(\"'\u{201C}\u{2018}".contains($0) }) } ?? ""
        // Single letters are initials ("J. R. Tolkien"), not sentence ends.
        let isInitial = word.count == 1 && word.first?.isLetter == true
        return !(isInitial || abbreviations.contains(word.lowercased()))
    }

    /// Splits `text` (longer than `limit`) into a head of at most `limit`
    /// characters and the non-empty remainder. Prefers a clause break so the
    /// seam lands where a reader would pause anyway, then a word break, and
    /// cuts mid-word only when there is no whitespace at all.
    private static func splitHead(of text: String, limit: Int) -> (String, String) {
        let window = text.prefix(limit)
        let clauseBreak = window.lastIndex { ",;:—".contains($0) }
            .map { window.index(after: $0) }
            .flatMap { window.distance(from: window.startIndex, to: $0) >= limit / 3 ? $0 : nil }
        let cut = clauseBreak
            ?? window.lastIndex(where: \.isWhitespace).flatMap { $0 > window.startIndex ? $0 : nil }
            ?? window.endIndex
        let head = text[..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = text[cut...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (head, rest)
    }
}

/// Works out which sentence is being spoken, for the follow-along panel.
enum CaptionTiming {
    /// Kokoro returns audio with no word or sentence timings, so within a
    /// chunk the position is estimated: a sentence gets a share of the audio
    /// proportional to its length. Over one chunk (400 characters at most)
    /// the drift stays well inside a sentence.
    static func index(atFraction fraction: Double, weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        var passed = 0.0
        for (index, weight) in weights.enumerated() {
            passed += weight
            if fraction * total < passed { return index }
        }
        return max(0, weights.count - 1)
    }

    /// UTF-16 offset of each piece within `text`. System voices report the
    /// exact character they are on, so there the position is looked up
    /// rather than estimated.
    static func starts(of pieces: [String], in text: String) -> [Int] {
        let source = text as NSString
        var cursor = 0
        return pieces.map { piece in
            let found = source.range(
                of: piece, options: [], range: NSRange(location: cursor, length: source.length - cursor))
            guard found.location != NSNotFound else { return cursor }
            cursor = found.location + found.length
            return found.location
        }
    }
}
