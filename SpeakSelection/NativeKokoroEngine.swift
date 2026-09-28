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

    /// Voice name -> speaker id for the kokoro-en-v0_19 bundle (11 voices).
    static let voiceTable: [(name: String, sid: Int)] = [
        ("af_default", 0),
        ("af_bella", 1),
        ("af_nicole", 2),
        ("af_sarah", 3),
        ("af_sky", 4),
        ("am_adam", 5),
        ("am_michael", 6),
        ("bf_emma", 7),
        ("bf_isabella", 8),
        ("bm_george", 9),
        ("bm_lewis", 10),
    ]

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
        let modelPath = dir.appendingPathComponent("model.onnx").path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw SpeechEngineError.sidecarNotInstalled
        }

        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: dir.appendingPathComponent("voices.bin").path,
            tokens: dir.appendingPathComponent("tokens.txt").path,
            dataDir: dir.appendingPathComponent("espeak-ng-data").path
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoro,
            numThreads: 2
        )
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

        let sid = Self.voiceTable.first(where: { $0.name == voice })?.sid ?? 3 // af_sarah
        let audio = tts.generate(text: text, sid: sid, speed: Float(speed))
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
