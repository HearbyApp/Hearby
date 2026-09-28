import XCTest

@testable import SpeakSelection

/// The speaker table is transcribed by hand from the model's `id2speaker`
/// metadata. A typo there does not crash or throw — it silently speaks in
/// the wrong person's voice, which no amount of manual listening reliably
/// catches across 54 entries. These tests are the guard.
final class VoiceTableTests: XCTestCase {

    func testSpeakerIdsAreUnique() {
        let sids = NativeKokoroEngine.voiceTable.map(\.sid)
        XCTAssertEqual(
            Set(sids).count, sids.count,
            "Two voices share a speaker id — one of them will speak as the other.")
    }

    func testVoiceNamesAreUnique() {
        let names = NativeKokoroEngine.voiceTable.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// kokoro-int8-multi-lang-v1_0 reports n_speakers=54 with ids 0...53.
    func testSpeakerIdsCoverTheModelRangeExactly() {
        let sids = Set(NativeKokoroEngine.voiceTable.map(\.sid))
        XCTAssertEqual(sids, Set(0...53), "Speaker ids must be exactly 0...53 for this bundle.")
    }

    func testDefaultVoiceExistsAndMatchesDefaultSid() {
        let match = NativeKokoroEngine.voiceTable
            .first { $0.name == NativeKokoroEngine.defaultVoice }
        XCTAssertNotNil(match, "The default voice is not in the table.")
        XCTAssertEqual(match?.sid, NativeKokoroEngine.defaultSid)
    }

    /// Spot-check against the metadata string, including the off-by-one trap:
    /// em_santa was appended at 53, out of alphabetical order.
    func testKnownSpeakerIdsMatchModelMetadata() {
        let expected: [String: Int] = [
            "af_alloy": 0, "af_heart": 3, "af_sarah": 9, "af_sky": 10,
            "am_adam": 11, "am_santa": 19, "bf_alice": 20, "bm_lewis": 27,
            "ef_dora": 28, "ff_siwis": 30, "jf_alpha": 37, "pm_santa": 44,
            "zf_xiaobei": 45, "zm_yunyang": 52, "em_santa": 53,
        ]
        for (name, sid) in expected {
            let actual = NativeKokoroEngine.voiceTable.first { $0.name == name }?.sid
            XCTAssertEqual(actual, sid, "\(name) should be speaker \(sid), got \(actual as Any).")
        }
    }

    func testGroupingCoversEveryVoiceAndLeadsWithEnglish() {
        let groups = NativeKokoroEngine.voicesByLanguage
        XCTAssertEqual(
            groups.flatMap(\.voices).count, NativeKokoroEngine.voiceTable.count,
            "Grouping dropped or duplicated voices.")
        XCTAssertEqual(groups.first?.language, "English (US)")
        XCTAssertEqual(groups.dropFirst().first?.language, "English (UK)")
    }

    func testDisplayNameStripsTheLanguageGenderPrefix() {
        func display(_ name: String) -> String? {
            NativeKokoroEngine.voiceTable.first { $0.name == name }?.displayName
        }
        XCTAssertEqual(display("af_heart"), "Heart")
        XCTAssertEqual(display("zf_xiaoxiao"), "Xiaoxiao")
        XCTAssertEqual(display("jf_gongitsune"), "Gongitsune")
    }
}
