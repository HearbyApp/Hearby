import XCTest

@testable import Hearby

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

    /// Nothing plays until the first chunk is synthesized, and Kokoro takes
    /// about as long to synthesize a chunk as to speak half of it. A long
    /// first chunk is the difference between speech in a second and speech
    /// in ten.
    func testFirstChunkIsShortAndLaterChunksGrow() {
        let sentence = String(repeating: "word ", count: 8) + "end. "  // ~45 chars
        let chunks = TextChunker.chunks(
            from: String(repeating: sentence, count: 40), maxLength: 400, firstChunkLength: 100)
        XCTAssertLessThanOrEqual(chunks[0].count, 100)
        XCTAssertLessThanOrEqual(chunks[1].count, 200)
        XCTAssertGreaterThan(chunks[1].count, chunks[0].count)
        XCTAssertTrue(chunks.dropFirst(3).allSatisfy { $0.count <= 400 })
    }

    /// Unpunctuated text (a pasted transcript, a bullet list) arrives as one
    /// giant "sentence". Emitted whole, it would stall the start of speech
    /// for as long as it takes to synthesize all of it.
    func testOversizedSentenceIsSplitAtWordBoundaries() {
        let words = (1...300).map { "word\($0)" }
        let chunks = TextChunker.chunks(from: words.joined(separator: " "), maxLength: 400)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertLessThanOrEqual(chunks[0].count, 100)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 400 })
        XCTAssertEqual(
            chunks.flatMap { $0.split(separator: " ").map(String.init) }, words,
            "A word was split, dropped or reordered.")
    }

    func testOversizedSentencePrefersClauseBreaks() {
        let clause = "this clause runs on for a while"
        let text = [String](repeating: clause, count: 10).joined(separator: ", ") + "."
        let first = TextChunker.chunks(from: text, maxLength: 400)[0]
        XCTAssertTrue(first.hasSuffix(","), "Split mid-clause: \(first)")
    }

    func testTextWithNoWhitespaceIsCutRatherThanDropped() {
        let long = String(repeating: "a", count: 900) + "."
        let chunks = TextChunker.chunks(from: long, maxLength: 400)
        XCTAssertEqual(chunks.joined(), long)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 400 })
    }

    /// Periods inside words and after abbreviations are not sentence ends.
    /// Splitting there would put a chunk seam, and an audible pause, in the
    /// middle of "github.com" or between "Dr." and the name.
    func testChunksNeverEndInsideAWordOrAfterAnAbbreviation() {
        let sentence = "Mr. Smith asked Dr. Jones about github.com and v1.0, e.g. today. "
        let chunks = TextChunker.chunks(from: String(repeating: sentence, count: 20), maxLength: 200)
        for chunk in chunks {
            for bad in ["Mr.", "Dr.", "github.", "v1.", "e.g."] {
                XCTAssertFalse(chunk.hasSuffix(bad), "Chunk split after \"\(bad)\": \(chunk)")
            }
        }
    }

    func testCRLFIsNormalized() {
        let chunks = TextChunker.chunks(from: "Line one.\r\nLine two.")
        XCTAssertFalse(
            chunks.contains { $0.contains("\r") },
            "Carriage returns leaked into a chunk and will be spoken or mispronounced.")
    }

    /// sherpa-onnx quits the app when one Kokoro call exceeds 510 phonemes,
    /// so no piece handed to it may be longer than maxPieceLength, whatever
    /// the chunk looks like once numbers are spelled out.
    func testKokoroPiecesNeverExceedTheLimit() {
        let chunk = NumberSpeller.spellOut(
            String(repeating: "Order 1234567 cost $98,765.43 on 2026-10-20 and shipped ", count: 8)
            + String(repeating: "word ", count: 120)
            + String(repeating: "x", count: 500))
        let pieces = NativeKokoroEngine.pieces(of: chunk)
        XCTAssertGreaterThan(chunk.count, 400)
        XCTAssertFalse(pieces.isEmpty)
        for piece in pieces {
            XCTAssertLessThanOrEqual(piece.count, NativeKokoroEngine.maxPieceLength)
            XCTAssertFalse(piece.isEmpty)
        }
        XCTAssertEqual(pieces.joined().filter { !$0.isWhitespace }, chunk.filter { !$0.isWhitespace },
                       "splitting must not drop or reorder text")
    }

    // MARK: - Follow-along captions

    func testGroupedChunksJoinToTheSameChunks() {
        let text = String(repeating: "A short sentence. Another one follows! And a third? ", count: 20)
        let grouped = TextChunker.groupedChunks(from: text)
        XCTAssertEqual(grouped.map { $0.joined(separator: " ") }, TextChunker.chunks(from: text))
        XCTAssertTrue(grouped.contains { $0.count > 1 }, "later chunks should hold several sentences")
        XCTAssertFalse(grouped.contains { $0.isEmpty })
    }

    func testCaptionFollowsSentenceLength() {
        // One short sentence, then one three times as long.
        let weights = [10.0, 30.0]
        XCTAssertEqual(CaptionTiming.index(atFraction: 0, weights: weights), 0)
        XCTAssertEqual(CaptionTiming.index(atFraction: 0.2, weights: weights), 0)
        XCTAssertEqual(CaptionTiming.index(atFraction: 0.3, weights: weights), 1)
        XCTAssertEqual(CaptionTiming.index(atFraction: 1.0, weights: weights), 1)
        XCTAssertEqual(CaptionTiming.index(atFraction: 0.5, weights: []), 0)
    }

    func testCaptionStartsFindRepeatedSentencesInOrder() {
        let text = "Go. Stop.\nGo. Done."
        let pieces = TextChunker.groupedChunks(from: text).flatMap { $0 }
        XCTAssertEqual(pieces, ["Go.", "Stop.", "Go.", "Done."])
        XCTAssertEqual(CaptionTiming.starts(of: pieces, in: text), [0, 4, 10, 14])
    }
}
