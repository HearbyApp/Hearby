import XCTest

@testable import Hearby

/// The cleaner decides what the listener hears. Two failure modes matter:
/// markup leaking through (the voice says "asterisk asterisk"), and real
/// content being eaten (a sum like 5 * 3 silently losing its operator).
final class SpeechTextCleanerTests: XCTestCase {

    private func clean(_ text: String) -> String { SpeechTextCleaner.clean(text) }

    func testPlainProseIsUnchanged() {
        let prose = "The budget grew 3.5 million dollars. NASA and the FBI agreed."
        XCTAssertEqual(clean(prose), prose)
    }

    func testFencedCodeBlockIsAnnounced() {
        XCTAssertEqual(
            clean("Here:\n```swift\nlet a = 1\n\nlet b = 2\n```\nDone."),
            "Here:\nCode block: 2 lines of Swift.\nDone.")
    }

    func testUnclosedFenceRunsToTheEnd() {
        XCTAssertEqual(clean("Try:\n```\nmake build"), "Try:\nCode block: 1 line.")
    }

    func testEmphasisMarkersAreRemoved() {
        XCTAssertEqual(
            clean("This is **bold**, *italic*, ***both***, ~~gone~~ and __under__."),
            "This is bold, italic, both, gone and under.")
    }

    func testArithmeticAsterisksSurvive() {
        XCTAssertEqual(clean("Compute 5 * 3 * 2 and a*b*c."), "Compute 5 * 3 * 2 and a*b*c.")
    }

    func testInlineCodeIsSpeakable() {
        XCTAssertEqual(
            clean("Call `speak(_:)` in `SpeechController.swift` with `--verbose`."),
            "Call speak in Speech Controller.swift with verbose.")
    }

    func testLongInlineCodeIsSummarized() {
        let long = "`" + String(repeating: "x", count: 90) + "`"
        XCTAssertEqual(clean("Run \(long) now."), "Run a code snippet now.")
    }

    func testLinksReadAsTextAndURLsAsHost() {
        XCTAssertEqual(
            clean("See [the docs](https://x.org/a) or https://www.github.com/foo/bar."),
            "See the docs or github.com.")
    }

    func testHeadingsListsAndQuotesGetPauses() {
        XCTAssertEqual(
            clean("## Summary\n- first item\n- [x] done item\n1. step one\n> quoted line"),
            "Summary.\nfirst item.\ndone item.\n1: step one.\nquoted line")
    }

    func testTableReadsRowByRow() {
        XCTAssertEqual(
            clean("| Name | Value |\n|------|:-----:|\n| `max_length` | 400 |"),
            "Name, Value.\n\nmax length, 400.")
    }

    func testTerminalGlyphsDropAndKeySymbolsAreNamed() {
        XCTAssertEqual(
            clean("⏺ Done ✅\nPress ⌘⇧S\n  ⎿  Read 193 lines (ctrl+o to expand)"),
            "Done\nPress Command Shift S\nRead 193 lines")
    }

    func testFilePathReadsAsFileName() {
        XCTAssertEqual(clean("Edit /Users/me/Projects/App/main.swift now."), "Edit main.swift now.")
    }

    func testIdentifiersAreSplitIntoWords() {
        XCTAssertEqual(
            clean("The parseHTMLResponse and user_id_field helpers."),
            "The parse HTML Response and user id field helpers.")
    }

    func testAbbreviationsAndSymbolsAreSpokenAsWords() {
        XCTAssertEqual(
            clean("Use e.g. Swift vs. Python ~40% faster -> done && shipped."),
            "Use for example Swift versus Python about 40% faster to done and shipped.")
    }

    /// End to end on the kind of reply the app exists for: nothing a voice
    /// would mispronounce may survive.
    func testTypicalAssistantReplyLeavesNoMarkup() {
        let reply = """
            ⏺ I fixed `SpeechController.swift`. The **`speak()`** method now cleans text.

            ## What changed
            1. Added `SpeechTextCleaner`
            2. See [docs](https://example.com/docs)

            | Setting | Default |
            |---------|---------|
            | `max_length` | 400 |

            ```swift
            let text = SpeechTextCleaner.clean(text)
            ```
            """
        let spoken = clean(reply)
        for leak in ["`", "**", "|", "##", "](", "http", "⏺", "---"] {
            XCTAssertFalse(spoken.contains(leak), "\"\(leak)\" leaked into: \(spoken)")
        }
        XCTAssertTrue(spoken.contains("Code block: 1 line of Swift."))
    }
}
