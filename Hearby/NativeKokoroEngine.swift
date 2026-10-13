import Foundation
import SherpaOnnx

/// Kokoro-82M running fully inside the app via the sherpa-onnx Swift package.
/// No Python, no sidecar process — synthesis is an in-process function call.
///
/// NOTE: the wrapper type/function names below follow the SherpaOnnx Swift API
/// (SherpaOnnxOfflineTtsWrapper etc.) shipped with the sherpa-onnx-spm package.
/// If the package pins a different sherpa-onnx version, cross-check names in
/// the package's SherpaOnnx.swift — they change rarely, but this file is the
/// only place that would need touching.
final class NativeKokoroEngine: SpeechEngine {
    let name = "Kokoro (on-device)"

    /// Voice name -> speaker id for kokoro-multi-lang-v1_0 (54 voices).
    ///
    /// Transcribed verbatim from the model's own `id2speaker` metadata rather
    /// than from any published voice list — the ordering in voices.bin is
    /// whatever sherpa-onnx's generate_voices_bin.py produced, and a wrong sid
    /// silently yields the wrong person's voice instead of an error. To
    /// regenerate after a bundle change:
    ///
    ///   strings model.onnx | grep -o 'id2speaker.*' | head -1
    ///
    /// The `af_`/`am_` prefixes are American English, `bf_`/`bm_` British.
    struct Voice {
        let name: String
        let sid: Int
        let language: String

        /// "af_heart" -> "Heart". The prefix encodes language and gender,
        /// which the section header already conveys.
        var displayName: String {
            let bare = name.contains("_") ? String(name.split(separator: "_", maxSplits: 1)[1]) : name
            return bare.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static let voiceTable: [Voice] = [
        // ── American English ──────────────────────────────────────────────
        Voice(name: "af_alloy", sid: 0, language: "English (US)"),
        Voice(name: "af_aoede", sid: 1, language: "English (US)"),
        Voice(name: "af_bella", sid: 2, language: "English (US)"),
        Voice(name: "af_heart", sid: 3, language: "English (US)"),
        Voice(name: "af_jessica", sid: 4, language: "English (US)"),
        Voice(name: "af_kore", sid: 5, language: "English (US)"),
        Voice(name: "af_nicole", sid: 6, language: "English (US)"),
        Voice(name: "af_nova", sid: 7, language: "English (US)"),
        Voice(name: "af_river", sid: 8, language: "English (US)"),
        Voice(name: "af_sarah", sid: 9, language: "English (US)"),
        Voice(name: "af_sky", sid: 10, language: "English (US)"),
        Voice(name: "am_adam", sid: 11, language: "English (US)"),
        Voice(name: "am_echo", sid: 12, language: "English (US)"),
        Voice(name: "am_eric", sid: 13, language: "English (US)"),
        Voice(name: "am_fenrir", sid: 14, language: "English (US)"),
        Voice(name: "am_liam", sid: 15, language: "English (US)"),
        Voice(name: "am_michael", sid: 16, language: "English (US)"),
        Voice(name: "am_onyx", sid: 17, language: "English (US)"),
        Voice(name: "am_puck", sid: 18, language: "English (US)"),
        Voice(name: "am_santa", sid: 19, language: "English (US)"),
        // ── British English ───────────────────────────────────────────────
        Voice(name: "bf_alice", sid: 20, language: "English (UK)"),
        Voice(name: "bf_emma", sid: 21, language: "English (UK)"),
        Voice(name: "bf_isabella", sid: 22, language: "English (UK)"),
        Voice(name: "bf_lily", sid: 23, language: "English (UK)"),
        Voice(name: "bm_daniel", sid: 24, language: "English (UK)"),
        Voice(name: "bm_fable", sid: 25, language: "English (UK)"),
        Voice(name: "bm_george", sid: 26, language: "English (UK)"),
        Voice(name: "bm_lewis", sid: 27, language: "English (UK)"),
        // ── Other languages ───────────────────────────────────────────────
        Voice(name: "ef_dora", sid: 28, language: "Spanish"),
        Voice(name: "em_alex", sid: 29, language: "Spanish"),
        Voice(name: "em_santa", sid: 53, language: "Spanish"),
        Voice(name: "ff_siwis", sid: 30, language: "French"),
        Voice(name: "hf_alpha", sid: 31, language: "Hindi"),
        Voice(name: "hf_beta", sid: 32, language: "Hindi"),
        Voice(name: "hm_omega", sid: 33, language: "Hindi"),
        Voice(name: "hm_psi", sid: 34, language: "Hindi"),
        Voice(name: "if_sara", sid: 35, language: "Italian"),
        Voice(name: "im_nicola", sid: 36, language: "Italian"),
        Voice(name: "jf_alpha", sid: 37, language: "Japanese"),
        Voice(name: "jf_gongitsune", sid: 38, language: "Japanese"),
        Voice(name: "jf_nezumi", sid: 39, language: "Japanese"),
        Voice(name: "jf_tebukuro", sid: 40, language: "Japanese"),
        Voice(name: "jm_kumo", sid: 41, language: "Japanese"),
        Voice(name: "pf_dora", sid: 42, language: "Portuguese"),
        Voice(name: "pm_alex", sid: 43, language: "Portuguese"),
        Voice(name: "pm_santa", sid: 44, language: "Portuguese"),
        Voice(name: "zf_xiaobei", sid: 45, language: "Chinese"),
        Voice(name: "zf_xiaoni", sid: 46, language: "Chinese"),
        Voice(name: "zf_xiaoxiao", sid: 47, language: "Chinese"),
        Voice(name: "zf_xiaoyi", sid: 48, language: "Chinese"),
        Voice(name: "zm_yunjian", sid: 49, language: "Chinese"),
        Voice(name: "zm_yunxi", sid: 50, language: "Chinese"),
        Voice(name: "zm_yunxia", sid: 51, language: "Chinese"),
        Voice(name: "zm_yunyang", sid: 52, language: "Chinese"),
    ]

    /// The model's best-rated English voice, and the app default.
    static let defaultVoice = "af_heart"
    static let defaultSid = 3

    /// Voices grouped for the picker, English first, then alphabetical by
    /// language. Order within a group follows `voiceTable`.
    static let voicesByLanguage: [(language: String, voices: [Voice])] = {
        let order = ["English (US)", "English (UK)"]
        let grouped = Dictionary(grouping: voiceTable, by: \.language)
        return grouped.keys
            .sorted { a, b in
                switch (order.firstIndex(of: a), order.firstIndex(of: b)) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a < b
                }
            }
            .map { (language: $0, voices: grouped[$0] ?? []) }
    }()

    /// One thread per performance core, capped at 8. Measured on an M4 Max
    /// (10 P-cores): 4 threads synthesized at 0.21x real time, 8 at 0.13x,
    /// and 10 was no faster. Efficiency cores only slow the batch down. Intel
    /// Macs have no perflevel0, so they fall back to half the logical cores
    /// (hyperthreads add little to matrix math).
    static let threadCount: Int = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) != 0 || cores <= 0 {
            cores = Int32(ProcessInfo.processInfo.activeProcessorCount / 2)
        }
        return min(8, max(2, Int(cores)))
    }()

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private let loadLock = NSLock()

    var isLoaded: Bool { tts != nil }

    /// Load the model from the installed bundle. Takes a few seconds; call off
    /// the main thread. Safe to call repeatedly.
    func load() throws {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard tts == nil else { return }

        let dir = ModelDownloader.modelDir
        let modelPath = ModelDownloader.modelFile.path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw SpeechEngineError.sidecarNotInstalled
        }
        func path(_ component: String) -> String {
            dir.appendingPathComponent(component).path
        }

        // v1.0 is a multilingual bundle: it resolves pronunciation from the
        // lexicons first and only falls back to espeak-ng for out-of-vocabulary
        // words, so both lexicons must be listed or English words get the
        // espeak treatment (audibly worse on names and acronyms).
        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: path("voices.bin"),
            tokens: path("tokens.txt"),
            dataDir: path("espeak-ng-data"),
            dictDir: path("dict"),
            lexicon: [path("lexicon-us-en.txt"), path("lexicon-zh.txt")].joined(separator: ",")
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoro,
            numThreads: Self.threadCount
        )
        // No rule FSTs: the ones in the bundle (date-zh, number-zh, phone-zh)
        // are Chinese text normalization, and with them every number is
        // spoken in Mandarin. NumberSpeller does the English equivalent.
        var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)
        tts = SherpaOnnxOfflineTtsWrapper(config: &config)
    }

    // MARK: - SpeechEngine

    func availableVoices() async -> [String] {
        Self.voiceTable.map(\.name)
    }

    func synthesize(text: String, voice: String, speed: Double) async throws -> Data? {
        if tts == nil { try load() }
        guard let tts else { throw SpeechEngineError.sidecarNotInstalled }

        // An unknown name means a voice from a superseded bundle is still in
        // AppStorage; fall back rather than speak as an arbitrary speaker.
        let sid = Self.voiceTable.first(where: { $0.name == voice })?.sid ?? Self.defaultSid
        let audio = tts.generate(text: NumberSpeller.spellOut(text), sid: sid, speed: Float(speed))
        guard !audio.samples.isEmpty else {
            throw SpeechEngineError.synthesisFailed("Kokoro produced no audio for this text.")
        }
        return WavEncoder.encode(samples: audio.samples, sampleRate: Int(audio.sampleRate))
    }

    func speakDirectly(text: String, voice: String, speed: Double) {
        // Not used: this engine returns audio data; SpeechController plays it.
    }

    func stop() {
        // Playback is owned by SpeechController.
    }
}

/// Minimal 16-bit PCM mono WAV encoder, so the existing AVAudioPlayer
/// pipeline can play sherpa-onnx's raw float samples.
enum WavEncoder {
    static func encode(samples: [Float], sampleRate: Int) -> Data {
        let pcm: [Int16] = samples.map { sample in
            Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))
        }
        let dataSize = pcm.count * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + dataSize)

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16)                                  // fmt chunk size
        append16(1)                                 // PCM
        append16(1)                                 // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))              // byte rate
        append16(2)                                 // block align
        append16(16)                                // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
