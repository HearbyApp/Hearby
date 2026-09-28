import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var speech: SpeechController
    @ObservedObject var downloader = ModelDownloader.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: speech.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                Text("SpeakSelection").font(.headline)
                Spacer()
                Text(speech.activeEngineName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !speech.statusMessage.isEmpty {
                Text(speech.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // First-run voice install progress
            switch downloader.state {
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installing Kokoro voices… \(Int(progress * 100))%")
                        .font(.caption)
                    ProgressView(value: progress)
                }
            case .verifying:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verifying download…").font(.caption)
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            case .extracting:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unpacking voices…").font(.caption)
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry Download") { downloader.retry() }
                }
            case .notInstalled, .installed:
                EmptyView()
            }

            Divider()

            if speech.kokoroReady && !speech.voices.isEmpty {
                // 54 voices across 8 languages: a flat list is unusable, so
                // section it and keep English at the top where most users need it.
                Picker("Voice", selection: $speech.voice) {
                    ForEach(NativeKokoroEngine.voicesByLanguage, id: \.language) { group in
                        Section(group.language) {
                            ForEach(group.voices, id: \.name) { v in
                                Text(v.displayName).tag(v.name)
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Speed")
                Slider(value: $speech.speed, in: 0.5...2.0, step: 0.1)
                Text(String(format: "%.1f×", speech.speed))
                    .font(.caption.monospacedDigit())
            }

            Divider()

            Button {
                Task { await speech.speakClipboard() }
            } label: {
                Label("Speak Clipboard (test)", systemImage: "doc.on.clipboard")
            }

            Button {
                speech.stop()
            } label: {
                Label("Stop Speaking", systemImage: "stop.fill")
            }
            .disabled(!speech.isSpeaking)

            Divider()

            Text("Select text in any app, then press ⌃⌥S (speak) / ⌃⌥X (stop). Native apps also get right-click → Services → “Speak Selection”. First hotkey use asks for Accessibility access.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }
}
