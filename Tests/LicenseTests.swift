import CryptoKit
import XCTest

@testable import Hearby

/// Keys here are signed with a throwaway key pair, never the real one; the
/// format is what matters, and it must match what the website produces.
final class LicenseTests: XCTestCase {

    private let signer = Curve25519.Signing.PrivateKey()
    private var publicKey: Curve25519.Signing.PublicKey { signer.publicKey }

    private func key(_ json: String, signedBy key: Curve25519.Signing.PrivateKey? = nil) throws -> String {
        let payload = Data(json.utf8)
        let signature = try (key ?? signer).signature(for: payload)
        return License.prefix + payload.base64URLEncoded + "." + signature.base64URLEncoded
    }

    private let ann = #"{"v":1,"email":"ann@example.com","name":"Ann","order":"cs_test_1","issued":"2026-10-19"}"#

    func testValidKey() throws {
        let license = try License.verify(key(ann), publicKey: publicKey)
        XCTAssertEqual(license, License(email: "ann@example.com", name: "Ann", order: "cs_test_1", issued: "2026-10-19"))
    }

    func testOptionalFieldsMayBeMissing() throws {
        let license = try License.verify(key(#"{"v":1,"email":"b@example.com"}"#), publicKey: publicKey)
        XCTAssertEqual(license.email, "b@example.com")
        XCTAssertNil(license.name)
    }

    /// Email clients wrap long lines; people paste with a trailing newline.
    func testWhitespaceAndLineBreaksAreIgnored() throws {
        let k = try key(ann)
        let mid = k.index(k.startIndex, offsetBy: 30)
        let wrapped = "  " + k[..<mid] + "\n  " + k[mid...] + " \n"
        XCTAssertEqual(try License.verify(String(wrapped), publicKey: publicKey).email, "ann@example.com")
    }

    func testLowercasePrefixIsAccepted() throws {
        let k = try key(ann)
        let lower = "hearby-" + k.dropFirst(License.prefix.count)
        XCTAssertNoThrow(try License.verify(lower, publicKey: publicKey))
    }

    func testEditedPayloadIsRejected() throws {
        let original = try key(ann)
        let parts = original.dropFirst(License.prefix.count).split(separator: ".")
        let forged = Data(ann.replacingOccurrences(of: "ann@", with: "eve@").utf8).base64URLEncoded
        let edited = License.prefix + forged + "." + parts[1]
        XCTAssertThrowsError(try License.verify(edited, publicKey: publicKey)) {
            XCTAssertEqual($0 as? License.Problem, .badSignature)
        }
    }

    func testEditedSignatureIsRejected() throws {
        var k = Array(try key(ann))
        let i = k.count - 5
        k[i] = k[i] == "A" ? "B" : "A"
        XCTAssertThrowsError(try License.verify(String(k), publicKey: publicKey)) {
            XCTAssertEqual($0 as? License.Problem, .badSignature)
        }
    }

    func testKeyFromAnotherSignerIsRejected() throws {
        let other = Curve25519.Signing.PrivateKey()
        XCTAssertThrowsError(try License.verify(key(ann, signedBy: other), publicKey: publicKey)) {
            XCTAssertEqual($0 as? License.Problem, .badSignature)
        }
    }

    /// A test key must never unlock the shipped app.
    func testTestKeysFailAgainstTheRealPublicKey() throws {
        XCTAssertThrowsError(try License.verify(key(ann))) {
            XCTAssertEqual($0 as? License.Problem, .badSignature)
        }
    }

    func testMalformedKeys() {
        let cases = [
            "", "hello", "HEARBY-", "HEARBY-abc", "HEARBY-abc.def.ghi", "HEARBY-.",
            "HEARBY-!!!.???", "SOMETHING-abc.def",
            "HEARBY-" + Data("x".utf8).base64URLEncoded + "." + Data(count: 10).base64URLEncoded,
        ]
        for text in cases {
            XCTAssertThrowsError(try License.verify(text, publicKey: publicKey), text) {
                XCTAssertEqual($0 as? License.Problem, .malformed, text)
            }
        }
    }

    func testSignedButNotJSONIsMalformed() throws {
        XCTAssertThrowsError(try License.verify(key("not json"), publicKey: publicKey)) {
            XCTAssertEqual($0 as? License.Problem, .malformed)
        }
    }

    func testMissingEmailIsMalformed() throws {
        XCTAssertThrowsError(try License.verify(key(#"{"v":1,"email":"  "}"#), publicKey: publicKey)) {
            XCTAssertEqual($0 as? License.Problem, .malformed)
        }
    }

    func testNewerFormatAsksForAnUpdate() throws {
        XCTAssertThrowsError(try License.verify(key(#"{"v":2,"email":"a@example.com"}"#), publicKey: publicKey)) {
            XCTAssertEqual($0 as? License.Problem, .newerVersion)
        }
    }

    func testBase64URLRoundTrip() {
        for length in 0..<70 {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 250) })
            XCTAssertEqual(Data(base64URL: data.base64URLEncoded), data)
        }
    }
}

final class TrialClockTests: XCTestCase {

    final class MemoryStore: SecretStore {
        var values: [String: String] = [:]
        func read(_ account: String) -> String? { values[account] }
        func write(_ account: String, _ value: String) { values[account] = value }
        func delete(_ account: String) { values[account] = nil }
    }

    private var store = MemoryStore()
    private var defaults: UserDefaults!
    private let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store = MemoryStore()
        defaults = UserDefaults(suiteName: "TrialClockTests-\(UUID())")
    }

    private var clock: TrialClock { TrialClock(store: store, defaults: defaults) }

    func testFreshTrialHasSevenDays() {
        XCTAssertEqual(clock.status(now: t0), .active(daysLeft: 7))
    }

    func testCountsDown() {
        _ = clock.status(now: t0)
        XCTAssertEqual(clock.status(now: t0 + 1), .active(daysLeft: 7))
        XCTAssertEqual(clock.status(now: t0 + day), .active(daysLeft: 6))
        XCTAssertEqual(clock.status(now: t0 + 6.5 * day), .active(daysLeft: 1))
        XCTAssertEqual(clock.status(now: t0 + 7 * day), .ended)
        XCTAssertEqual(clock.status(now: t0 + 30 * day), .ended)
    }

    func testSettingTheClockBackDoesNotWinDaysBack() {
        _ = clock.status(now: t0)
        XCTAssertEqual(clock.status(now: t0 + 7 * day), .ended)
        XCTAssertEqual(clock.status(now: t0 + day), .ended)
        XCTAssertEqual(clock.status(now: t0 - 100 * day), .ended)
    }

    /// Deleting the app (and its preferences) leaves the Keychain copy.
    func testReinstallKeepsTheStartDate() {
        _ = clock.status(now: t0)
        defaults = UserDefaults(suiteName: "TrialClockTests-\(UUID())")
        XCTAssertEqual(clock.status(now: t0 + 3 * day), .active(daysLeft: 4))
    }

    /// And clearing the Keychain item alone doesn't restart it either.
    func testClearingTheKeychainAloneDoesNotRestart() {
        _ = clock.status(now: t0)
        store = MemoryStore()
        XCTAssertEqual(clock.status(now: t0 + 3 * day), .active(daysLeft: 4))
        XCTAssertNotNil(store.values[TrialClock.startedKey], "the missing copy is restored")
    }

    func testEarlierOfTheTwoStartDatesWins() {
        let iso = ISO8601DateFormatter()
        store.values[TrialClock.startedKey] = iso.string(from: t0)
        defaults.set(iso.string(from: t0 + 5 * day), forKey: TrialClock.startedKey)
        XCTAssertEqual(clock.status(now: t0 + 6 * day), .active(daysLeft: 1))

        store = MemoryStore()
        defaults = UserDefaults(suiteName: "TrialClockTests-\(UUID())")
        store.values[TrialClock.startedKey] = iso.string(from: t0 + 5 * day)
        defaults.set(iso.string(from: t0), forKey: TrialClock.startedKey)
        XCTAssertEqual(clock.status(now: t0 + 6 * day), .active(daysLeft: 1))
    }

    func testUnreadableValuesStartFresh() {
        store.values[TrialClock.startedKey] = "garbage"
        XCTAssertEqual(clock.status(now: t0), .active(daysLeft: 7))
    }
}
