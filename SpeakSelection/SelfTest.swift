import Foundation

/// Headless check that the installed voice bundle actually synthesizes.
///
/// A wrong model filename, a missing lexicon or a stale speaker table all
/// compile perfectly and then fail at runtime — either silently (wrong voice)
/// or with no audio at all. This exercises the real load path and the real
/// generate call, so those failures surface in the build rather than on a
/// customer's Mac.
///
/// Exits 0 on success, 1 on failure. Never returns.
enum SelfTest {
    private static let phrase =
        "The quick brown fox jumps over the lazy dog. Kokoro voice check, 2026."

    static func runAndExit() -> Never {
        var failures: [String] = []

        func check(_ label: String, _ body: () throws -> Void) {
            do {
                try body()
                print("  ok    \(label)")
            } catch {
                print("  FAIL  \(label): \(error.localizedDescription)")
                failures.append(label)
            }
        }

        print("SpeakSelection self-test")
        print("  bundle: \(ModelDownloader.bundleName)")

        let fm = FileManager.default
        let dir = ModelDownloader.modelDir

        // 1. Every file the engine config references must exist. Missing ones
        //    make sherpa-onnx fail deep inside C++ with no useful message.
        for component in [
            "model.int8.onnx", "voices.bin", "tokens.txt",
            "espeak-ng-data", "dict", "lexicon-us-en.txt", "lexicon-zh.txt",
        ] {
            check("present: \(component)") {
                guard fm.fileExists(atPath: dir.appendingPathComponent(component).path) else {
                    throw Failure("not found in \(dir.path)")
                }
            }
        }

        guard failures.isEmpty else { finish(failures) }

        // 2. The model must load with the config the app actually uses.
        let engine = NativeKokoroEngine()
        check("engine loads") { try engine.load() }
        guard failures.isEmpty else { finish(failures) }

        // 3. The default voice must be in the speaker table. A bundle swap
        //    that forgets the table silently speaks as an arbitrary person.
        check("default voice \(NativeKokoroEngine.defaultVoice) is in the speaker table") {
            guard let v = NativeKokoroEngine.voiceTable
                .first(where: { $0.name == NativeKokoroEngine.defaultVoice })
            else { throw Failure("not present") }
            guard v.sid == NativeKokoroEngine.defaultSid else {
                throw Failure("sid is \(v.sid), expected \(NativeKokoroEngine.defaultSid)")
            }
        }

        // 4. Synthesis must produce real audio, not a valid-but-empty WAV.
        check("synthesizes \(phrase.count) characters") {
            let semaphore = DispatchSemaphore(value: 0)
            // Detached, not Task {}: this runs from the App's MainActor-isolated
            // init, so an inheriting task would need the main thread that
            // semaphore.wait() is about to block — an instant deadlock.
            nonisolated(unsafe) var result: Result<Data?, Error>!
            Task.detached {
                do {
                    result = .success(
                        try await engine.synthesize(
                            text: phrase, voice: NativeKokoroEngine.defaultVoice, speed: 1.0))
                } catch {
                    result = .failure(error)
                }
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + 120) == .success else {
                throw Failure("timed out after 120s")
            }
            let data = try result.get()
            guard let data else { throw Failure("returned no data") }
            // 44-byte WAV header plus enough samples to be more than a click.
            guard data.count > 44 + 24_000 else {
                throw Failure("only \(data.count) bytes of audio — effectively silence")
            }
            print("        \(data.count / 1024) KB of audio")
        }

        finish(failures)
    }

    private static func finish(_ failures: [String]) -> Never {
        if failures.isEmpty {
            print("PASS")
            exit(0)
        }
        print("FAIL (\(failures.count)): \(failures.joined(separator: ", "))")
        exit(1)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
