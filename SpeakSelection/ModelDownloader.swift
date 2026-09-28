import CryptoKit
import Foundation

/// Downloads and installs the Kokoro model bundle on first launch —
/// no terminal, no Python. Progress is published for the menu bar UI.
///
/// The bundle (model.onnx, voices.bin, tokens.txt, espeak-ng-data/, lexicon)
/// comes from the sherpa-onnx release archives and is extracted into
/// ~/Library/Application Support/SpeakSelection/.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    static let shared = ModelDownloader()

    enum State: Equatable {
        case notInstalled
        case downloading(progress: Double)   // 0...1
        case verifying
        case extracting
        case installed
        case failed(String)
    }

    @Published var state: State = .notInstalled

    /// Kokoro v1.0, int8-quantized: 54 voices (28 of them English, including
    /// af_heart) at 132 MB.
    ///
    /// Chosen over the two obvious alternatives:
    ///   - kokoro-en-v0_19 (the original here) is fp32: 320 MB for 11 English
    ///     voices, none as good as af_heart.
    ///   - kokoro-int8-multi-lang-v1_1 is newer but is the *-zh* release —
    ///     103 voices of which only 3 (af_maple, af_sol, bf_vale) are English.
    ///     A regression for an English-first product.
    /// Changing this bundle means regenerating `voiceTable` in
    /// NativeKokoroEngine from the model's own `id2speaker` metadata.
    nonisolated static let bundleName = "kokoro-int8-multi-lang-v1_0"
    static let downloadURL = URL(string:
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2")!

    /// Verified against the published release asset. A corrupted or
    /// man-in-the-middled archive gets extracted by /usr/bin/tar otherwise.
    nonisolated static let expectedSHA256 =
        "4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e"
    nonisolated static let expectedBytes: Int64 = 132_303_094

    /// Bundles shipped by earlier versions, deleted once the current one
    /// installs — the v0_19 bundle alone is 353 MB of dead weight.
    nonisolated static let supersededBundles = ["kokoro-en-v0_19"]

    nonisolated static let appSupportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SpeakSelection")

    nonisolated static var modelDir: URL { appSupportDir.appendingPathComponent(bundleName) }

    /// The int8 bundles name the weights model.int8.onnx, not model.onnx.
    nonisolated static var modelFile: URL { modelDir.appendingPathComponent("model.int8.onnx") }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.modelFile.path)
    }

    private var downloadTask: URLSessionDownloadTask?
    private lazy var session = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil)

    /// Called at launch: no-op if installed, otherwise begins the download.
    func installIfNeeded() {
        if isInstalled {
            state = .installed
            return
        }
        guard downloadTask == nil else { return }
        state = .downloading(progress: 0)
        let task = session.downloadTask(with: Self.downloadURL)
        downloadTask = task
        task.resume()
    }

    func retry() {
        downloadTask = nil
        installIfNeeded()
    }

    private func finishInstall(from archiveURL: URL) {
        state = .verifying
        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default

                try Self.verifyChecksum(of: archiveURL)
                await MainActor.run { self.state = .extracting }

                try fm.createDirectory(at: Self.appSupportDir, withIntermediateDirectories: true)

                // Extract with the system tar (handles .tar.bz2 natively).
                let tar = Process()
                tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tar.arguments = ["-xjf", archiveURL.path, "-C", Self.appSupportDir.path]
                try tar.run()
                tar.waitUntilExit()
                guard tar.terminationStatus == 0 else {
                    throw NSError(domain: "SpeakSelection", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "tar exited with status \(tar.terminationStatus)",
                    ])
                }
                try? fm.removeItem(at: archiveURL)

                await MainActor.run {
                    if self.isInstalled {
                        self.state = .installed
                        Self.removeSupersededBundles()
                        Task { await SpeechController.shared.warmUp() }
                    } else {
                        self.state = .failed(
                            "Archive extracted but \(Self.modelFile.lastPathComponent) was not found.")
                    }
                }
            } catch {
                // A bad archive must not linger — the next retry would just
                // re-verify the same corrupt bytes.
                try? FileManager.default.removeItem(at: archiveURL)
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    /// Streams the archive through SHA-256 so a 132 MB file never lands in
    /// memory all at once.
    nonisolated private static func verifyChecksum(of url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        guard digest == expectedSHA256 else {
            throw NSError(domain: "SpeakSelection", code: 2, userInfo: [
                NSLocalizedDescriptionKey:
                    "Downloaded voice pack failed its integrity check. Tap Retry to download it again.",
            ])
        }
    }

    /// Reclaims disk from bundles shipped by earlier app versions.
    nonisolated private static func removeSupersededBundles() {
        for name in supersededBundles {
            try? FileManager.default.removeItem(at: appSupportDir.appendingPathComponent(name))
        }
    }

    fileprivate func handleProgress(_ fraction: Double) {
        if case .downloading = state { state = .downloading(progress: fraction) }
    }

    fileprivate func handleCompletion(location: URL?, error: Error?) {
        downloadTask = nil
        if let error {
            state = .failed("Download failed: \(error.localizedDescription)")
            return
        }
        guard let location else {
            state = .failed("Download finished but no file was produced.")
            return
        }
        finishInstall(from: location)
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.handleProgress(fraction) }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move out of the temp location synchronously — it's deleted when
        // this delegate method returns.
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.bundleName).tar.bz2")
        try? FileManager.default.removeItem(at: stable)
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            Task { @MainActor in self.handleCompletion(location: stable, error: nil) }
        } catch {
            Task { @MainActor in self.handleCompletion(location: nil, error: error) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        guard let error else { return } // success handled above
        Task { @MainActor in self.handleCompletion(location: nil, error: error) }
    }
}
