import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var speech: SpeechController
    @ObservedObject var downloader = ModelDownloader.shared
    @ObservedObject var permissions = Permissions.shared
    @ObservedObject var updater = Updater.shared
    @AppStorage(SpeakingHUD.enabledKey) private var showHUD = true
    @AppStorage(SpeakingHUD.captionsKey) private var showCaptions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: speech.menuBarSymbol)
                Text("Hearby").font(.headline)
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

            // Only surfaced when it is actually a problem — a permanent
            // nag for a permission the Services flow never needs is noise.
            if !permissions.isTrusted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Keyboard shortcut is inactive", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Text("⌃⌥S needs Accessibility access. Right-click → Services still works.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Fix This…") { WelcomeWindow.show() }
                        .controlSize(.small)
                }
                Divider()
            }

            Toggle("Open at login", isOn: $permissions.launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.callout)
            Toggle("Show on-screen indicator", isOn: $showHUD)
                .toggleStyle(.checkbox)
                .font(.callout)
            // The text is shown inside the indicator, so it has nowhere to
            // appear when the indicator itself is off.
            Toggle("Show text while speaking", isOn: $showCaptions)
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(!showHUD)

            Text("Select text in any app, then press ⌃⌥S (speak) / ⌃⌥X (stop). Native apps also get right-click → Services → “Speak Selection”.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if updater.isConfigured {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.down.circle")
                }
                .disabled(!updater.canCheck)
            }

            // GPLv3 asks an interactive program to show its copyright, its
            // lack of warranty and where to read the license.
            HStack(spacing: 6) {
                Text("© 2026 Justin Brundage. Open source (GPL v3), no warranty.")
                Button("License") { Self.openLicense() }
                if let source = Updater.sourceURL {
                    Button("Source") { NSWorkspace.shared.open(source) }
                }
            }
            .buttonStyle(.link)
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button("Help") { WelcomeWindow.show() }
                Spacer()
                Text("v\(Updater.displayVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
        // Catches a grant made in System Settings while the popover is open,
        // so the warning clears itself instead of looking stuck.
        .onAppear {
            permissions.refresh()
            permissions.beginWatching()
        }
        .onDisappear { permissions.endWatching() }
    }

    /// LICENSE has no file extension, so Launch Services has no default app
    /// for it; name TextEdit outright.
    private static func openLicense() {
        guard let license = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else { return }
        NSWorkspace.shared.open(
            [license], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }
}
