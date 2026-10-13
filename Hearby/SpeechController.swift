import Foundation
import AVFoundation
import SwiftUI

/// Central coordinator: picks the engine, chunks text, pipelines
/// synthesis-ahead-of-playback, and owns the audio player.
@MainActor
final class SpeechController: NSObject, ObservableObject {
    static let shared = SpeechController()

    /// What the user should be told is happening. `.preparing` covers the
    /// seconds Kokoro spends synthesizing the first chunk, which used to look
    /// identical to the app having ignored the hotkey.
    enum Phase { case idle, preparing, speaking }

    @Published private(set) var phase = Phase.idle
    @Published var statusMessage = ""

    /// The text being read, one sentence per entry, and which one the voice
    /// is on. Drives the follow-along panel.
    @Published private(set) var captionPieces: [String] = []
    @Published private(set) var captionIndex = 0
    @Published var kokoroReady = false
    @Published var voices: [String] = []

    @AppStorage("voice") var voice = NativeKokoroEngine.defaultVoice
    @AppStorage("speed") var speed = 1.0
    @AppStorage("useKokoro") var useKokoro = true

    let downloader = ModelDownloader.shared

    private let kokoro = NativeKokoroEngine()
    private let system = SystemVoiceEngine()
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var speakTask: Task<Void, Never>?
    private var captionTimer: Timer?
    /// Bumped by every speak(). A superseded run finishing late must not
    /// reset the phase of the run that replaced it.
    private var generation = 0

    var isSpeaking: Bool { phase != .idle }

    var menuBarSymbol: String {
        switch phase {
        case .idle: "speaker.wave.2"
        case .preparing: "hourglass"
        case .speaking: "speaker.wave.3.fill"
        }
    }

    private var activeEngine: SpeechEngine {
        (useKokoro && kokoroReady) ? kokoro : system
    }

    var activeEngineName: String { activeEngine.name }

    // MARK: - Lifecycle

    /// Called at launch (and again after the model finishes installing).
    func warmUp() async {
        downloader.installIfNeeded()
        guard downloader.isInstalled else {
            statusMessage = "Downloading Kokoro voices — system voices in the meantime."
            return
        }
        do {
            // Model load takes a few seconds; keep it off the main thread.
            try await Task.detached(priority: .userInitiated) { [kokoro] in
                try kokoro.load()
                // The first inference after load pays one-off setup costs;
                // spend them now rather than on the user's first selection.
                _ = try? await kokoro.synthesize(
                    text: "Ready.", voice: NativeKokoroEngine.defaultVoice, speed: 1.0)
            }.value
            voices = await kokoro.availableVoices()
            // A voice saved by an older bundle may no longer exist. Left
            // alone, the Picker would show an empty selection and synthesis
            // would quietly use the fallback speaker.
            if !voices.contains(voice) { voice = NativeKokoroEngine.defaultVoice }
            kokoroReady = true
            statusMessage = "Kokoro ready."
        } catch {
            kokoroReady = false
            statusMessage = error.localizedDescription
        }
    }

    nonisolated func shutdown() {
        Task { @MainActor in self.stop() }
    }

    // MARK: - Speaking

    func speak(_ text: String) async {
        stop() // a new selection always interrupts the previous one

        // Markdown, code fences and terminal glyphs are written for the eye.
        // Clean once here so Kokoro and the system voice hear the same text.
        let text = SpeechTextCleaner.clean(text)
        let groups = TextChunker.groupedChunks(from: text)
        guard !groups.isEmpty else { return }
        let chunks = groups.map { $0.joined(separator: " ") }
        let pieces = groups.flatMap { $0 }
        // Which entries of `pieces` each chunk is made of.
        var pieceRanges: [Range<Int>] = []
        for group in groups {
            let start = pieceRanges.last?.upperBound ?? 0
            pieceRanges.append(start..<start + group.count)
        }
        captionPieces = pieces
        captionIndex = 0
        let engine = activeEngine
        let voice = self.voice
        let speed = self.speed
        generation += 1
        let run = generation
        phase = .preparing
        statusMessage = ""

        speakTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finish(run) }

            // Engines that play audio themselves (system voices):
            if let system = engine as? SystemVoiceEngine {
                let starts = CaptionTiming.starts(of: pieces, in: text)
                system.onWillSpeak = { [weak self] location in
                    guard let self, run == self.generation else { return }
                    let index = starts.lastIndex { $0 <= location } ?? 0
                    if self.captionIndex != index { self.captionIndex = index }
                }
                self.phase = .speaking
                await system.speakAndWait(text: text, voice: voice, speed: speed)
                return
            }

            // Kokoro: synthesis runs back to back on its own task, feeding
            // playback through the stream. Kokoro runs at roughly half real
            // time, so once the first chunk is out synthesis pulls ahead and
            // stays ahead; the only wait the user sees is that first chunk,
            // which TextChunker keeps short. Unbounded is fine: even 10,000
            // characters of buffered audio is about 25 MB.
            let (stream, output) = AsyncStream.makeStream(of: (Int, Data).self)
            let producer = Task.detached(priority: .userInitiated) {
                for (index, chunk) in chunks.enumerated() {
                    guard !Task.isCancelled else { break }
                    do {
                        if let wav = try await engine.synthesize(text: chunk, voice: voice, speed: speed) {
                            output.yield((index, wav))
                        }
                    } catch {
                        await MainActor.run { SpeechController.shared.statusMessage = error.localizedDescription }
                    }
                }
                output.finish()
            }
            defer { producer.cancel() }

            for await (index, wav) in stream {
                guard !Task.isCancelled else { return }
                self.phase = .speaking
                await self.play(wav, pieces: pieceRanges[index])
            }
        }
    }

    private func finish(_ run: Int) {
        guard run == generation else { return }
        phase = .idle
        speakTask = nil
    }

    private func play(_ wavData: Data, pieces: Range<Int>) async {
        defer { captionTimer?.invalidate() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let p = try AVAudioPlayer(data: wavData)
                p.delegate = self
                self.player = p
                self.playbackContinuation = continuation
                p.play()
                self.followCaptions(pieces)
            } catch {
                self.statusMessage = "Playback failed: \(error.localizedDescription)"
                continuation.resume()
            }
        }
    }

    /// Moves the caption through the sentences of the chunk now playing.
    private func followCaptions(_ pieces: Range<Int>) {
        captionTimer?.invalidate()
        captionIndex = pieces.lowerBound
        guard pieces.count > 1 else { return }
        let weights = captionPieces[pieces].map { Double($0.count) }
        captionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                let index = pieces.lowerBound + CaptionTiming.index(
                    atFraction: player.currentTime / player.duration, weights: weights)
                if self.captionIndex != index { self.captionIndex = index }
            }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        captionTimer?.invalidate()
        captionTimer = nil
        player?.stop()
        player = nil
        system.stop()
        playbackContinuation?.resume()
        playbackContinuation = nil
        phase = .idle
    }

    /// Handy for testing without a Services invocation.
    func speakClipboard() async {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string), !text.isEmpty else {
            statusMessage = "Clipboard has no text."
            return
        }
        await speak(text)
    }
}

extension SpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playbackContinuation?.resume()
            self.playbackContinuation = nil
        }
    }
}
