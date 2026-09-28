import XCTest

@testable import SpeakSelection

/// Chunking decides when speech starts and where it pauses, so its edge cases
/// are audible: a dropped chunk silently truncates the text, and an oversized
/// one stalls playback while it synthesizes.
final class TextChunkerTests: XCTestCase {

    func testEmptyAndWhitespaceProduceNoChunks() {
        XCTAssertTrue(TextChunker.chunks(from: "").isEmpty)
        XCTAssertTrue(TextChunker.chunks(from: "   \n\n  \t ").isEmpty)
    }

    func testShortSentencesMergeIntoOneChunk() {
        let chunks = TextChunker.chunks(from: "One. Two. Three.")
        XCTAssertEqual(chunks, ["One. Two. Three."])
    }

    func testTextIsNeverLost() {
        let text = """
            The first sentence goes here. And a second one! A third?
            Then a line break, and a trailing fragment with no terminator
            """
        let joined = TextChunker.chunks(from: text).joined(separator: " ")
        // Chunking may re-wrap whitespace, but every word must survive.
        XCTAssertEqual(
            joined.split(whereSeparator: \.isWhitespace),
            text.split(whereSeparator: \.isWhitespace))
    }

    func testUnterminatedTrailingTextIsKept() {
        let chunks = TextChunker.chunks(from: "Done. Now a tail with no period")
        XCTAssertEqual(chunks, ["Done. Now a tail with no period"])
    }

    func testChunksRespectMaxLengthWhenSentencesAllow() {
        let sentence = String(repeating: "word ", count: 12) + "end. "  // ~65 chars
        let text = String(repeating: sentence, count: 40)
        let chunks = TextChunker.chunks(from: text, maxLength: 200)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(
                chunk.count, 200,
                "A chunk exceeded maxLength while its sentences could have been split.")
        }
    }

    /// A single sentence longer than maxLength cannot be split by the current
    /// rules, so it is emitted whole rather than dropped. Pinning the
    /// behaviour so a future rewrite has to make the choice deliberately.
    func testOversizedSingleSentenceIsEmittedRatherThanDropped() {
        let long = String(repeating: "a", count: 900) + "."
        let chunks = TextChunker.chunks(from: long, maxLength: 400)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.count, 901)
    }

    func testCRLFIsNormalized() {
        let chunks = TextChunker.chunks(from: "Line one.\r\nLine two.")
        XCTAssertFalse(
            chunks.contains { $0.contains("\r") },
            "Carriage returns leaked into a chunk and will be spoken or mispronounced.")
    }
}
