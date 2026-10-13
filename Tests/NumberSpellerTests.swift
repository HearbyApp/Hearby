import XCTest

@testable import Hearby

/// Kokoro reads any digit it is handed in Mandarin, so the failure that
/// matters here is a digit surviving. The rest is whether the English sounds
/// like what a person would say.
final class NumberSpellerTests: XCTestCase {

    private func spell(_ text: String) -> String { NumberSpeller.spellOut(text) }

    func testNoDigitSurvives() {
        let text = "v1.0 shipped 2026-10-13 at 9:05 to 1,204 users (38%), $4.99 each, id 0042, +1 555 0100."
        XCTAssertNil(spell(text).rangeOfCharacter(from: .decimalDigits), spell(text))
    }

    func testTextWithoutDigitsIsUnchanged() {
        let text = "Nothing to see here: just words, and punctuation!"
        XCTAssertEqual(spell(text), text)
    }

    func testCardinals() {
        XCTAssertEqual(spell("I have 3 cats and 42 fish."), "I have three cats and forty two fish.")
        XCTAssertEqual(spell("1,204 users"), "one thousand two hundred four users")
        XCTAssertEqual(spell("line 400"), "line four hundred")
    }

    func testDecimalsAreReadDigitByDigit() {
        XCTAssertEqual(spell("3.14"), "three point one four")
        XCTAssertEqual(spell("version 1.0"), "version one point zero")
        XCTAssertEqual(spell("End of sentence 5."), "End of sentence five.")
    }

    func testYears() {
        XCTAssertEqual(spell("in 2026"), "in twenty twenty six")
        XCTAssertEqual(spell("in 1905"), "in nineteen oh five")
        XCTAssertEqual(spell("in 1900"), "in nineteen hundred")
        XCTAssertEqual(spell("in 2005"), "in two thousand five")
        XCTAssertEqual(spell("5000 items"), "five thousand items")
    }

    func testOrdinals() {
        XCTAssertEqual(spell("1st, 2nd, 3rd, 4th"), "first, second, third, fourth")
        XCTAssertEqual(spell("the 21st and 30th"), "the twenty first and thirtieth")
        XCTAssertEqual(spell("the 112th"), "the one hundred twelfth")
    }

    func testMoneyAndPercent() {
        XCTAssertEqual(spell("$1"), "one dollar")
        XCTAssertEqual(spell("$4.99"), "four dollars and ninety nine cents")
        XCTAssertEqual(spell("$5 million"), "five million dollars")
        XCTAssertEqual(spell("3.5 million"), "three point five million")
        XCTAssertEqual(spell("38%"), "thirty eight percent")
    }

    func testTimes() {
        XCTAssertEqual(spell("at 3:30"), "at three thirty")
        XCTAssertEqual(spell("at 9:05"), "at nine oh five")
        XCTAssertEqual(spell("at 7:00"), "at seven o'clock")
    }

    func testIdentifiersAreReadDigitByDigit() {
        XCTAssertEqual(spell("zip 02134"), "zip zero two one three four")
        XCTAssertEqual(spell("id 12345678901"), "id one two three four five six seven eight nine zero one")
    }
}
