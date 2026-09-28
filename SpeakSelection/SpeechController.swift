import Foundation
import AVFoundation
import SwiftUI

/// Central coordinator: picks the engine, chunks text, pipelines
/// synthesis-ahead-of-playback, and owns the audio player.
@MainActor
final class SpeechController: NSObject, ObservableObject {
    static let shared = SpeechController()

    @Published var isSpeaking = false
    @Published var statusMessage = ""
    @Published var kokoroReady = false
    @Published var voices: [String] = []

    @AppStorage("voice") var voice = "af_sarah"
    @AppStorage("speed") var speed = 1.0
    @AppStorage("useKokoro") var useKokoro = true

    let downloader = ModelDownloader.shared

    private let kokoro = NativeKokoroEngine()
    private let system = SystemVoiceEngine()
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var speakTask: Task<Void, Never>?

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
            }.value
            voices = await kokoro.availableVoices()
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

        let engine = activeEngine
        isSpeaking = true
        statusMessage = "Speaking…"

        speakTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isSpeaking = false
                    if self.statusMessage == "Speaking…" { self.statusMessage = "" }
                }
            }

            // Engines that play audio themselves (system voices):
            if !(engine is NativeKokoroEngine) {
                engine.speakDirectly(text: text, voice: self.voice, speed: self.speed)
                return
            }

            // Kokoro: chunk + pipeline (synthesize chunk N+1 while playing N).
            let chunks = TextChunker.chunks(from: text)
            guard !chunks.isEmpty else { return }

            var nextData: Task<Data?, Never>? = self.synthesisTask(for: chunks[0], engine: engine)
            for index in chunks.indices {
                guard !Task.isCancelled else { return }
                let data = await nextData?.value
                // Kick off the next chunk before playing this one.
                if index + 1 < chunks.count {
                    nextData = self.synthesisTask(for: chunks[index + 1], engine: engine)
                } else {
                    nextData = nil
                }
                guard let wav = data else { continue }
                guard !Task.isCancelled else { return }
                await self.play(wav)
            }
        }
    }

    private func synthesisTask(for chunk: String, engine: SpeechEngine) -> Task<Data?, Never> {
        Task.detached(priority: .userInitiated) { [voice, speed] in
            do {
                return try await engine.synthesize(text: chunk, voice: voice, speed: speed)
            } catch {
                await MainActor.run { SpeechController.shared.statusMessage = error.localizedDescription }
                return nil
            }
        }
    }

    private func play(_ wavData: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let p = try AVAudioPlayer(data: wavData)
                p.delegate = self
                self.player = p
                self.playbackContinuation = continuation
                p.play()
            } catch {
                self.statusMessage = "Playback failed: \(error.localizedDescription)"
                continuation.resume()
            }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        player?.stop()
        player = nil
        system.stop()
        playbackContinuation?.resume()
        playbackContinuation = nil
        isSpeaking = false
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
