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
        case extracting
        case installed
        case failed(String)
    }

    @Published var state: State = .notInstalled

    /// English-only Kokoro bundle, 11 voices.
    /// Alternative (smaller, more voices incl. af_heart, English+Chinese):
    ///   kokoro-int8-multi-lang-v1_1.tar.bz2 — swap bundleName + voice map in
    ///   NativeKokoroEngine if you change this.
    nonisolated static let bundleName = "kokoro-en-v0_19"
    static let downloadURL = URL(string:
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2")!

    nonisolated static let appSupportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SpeakSelection")

    nonisolated static var modelDir: URL { appSupportDir.appendingPathComponent(bundleName) }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.modelDir.appendingPathComponent("model.onnx").path)
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
        state = .extracting
        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
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
                        Task { await SpeechController.shared.warmUp() }
                    } else {
                        self.state = .failed("Archive extracted but model.onnx not found.")
                    }
                }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
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
