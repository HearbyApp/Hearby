import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var speech: SpeechController
    @ObservedObject var downloader = ModelDownloader.shared
    @ObservedObject var permissions = Permissions.shared
    @ObservedObject var updater = Updater.shared
    @ObservedObject var licensing = Licensing.shared
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

            licenseStatus

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
                    Text(Permissions.staleEntryHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Straight to the switch: this used to open the welcome
                    // window, one more step away from the actual fix.
                    Button("Open Accessibility Settings…") {
                        permissions.showAccessibilityControls()
                    }
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

            if case .licensed(let license) = licensing.state {
                Button("Licensed to \(license.email)") { LicenseWindow.show() }
                    .buttonStyle(.link)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Menu("Debug: Trial") {
                Button("Skip 1 Day") { licensing.debugSkipDays(1) }
                Button("Skip 7 Days (End Trial)") { licensing.debugSkipDays(7) }
                Button("Restart Trial") { licensing.debugRestartTrial() }
            }
            .controlSize(.small)
            #endif

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
            licensing.refresh()
            permissions.refresh()
            permissions.beginWatching()
        }
        .onDisappear { permissions.endWatching() }
    }

    /// Nothing while licensed (the footer says who it's licensed to); during
    /// the trial, how long is left; after it, why ⌃⌥S has stopped reading.
    @ViewBuilder
    private var licenseStatus: some View {
        switch licensing.state {
        case .licensed:
            EmptyView()
        case .trial(let days):
            licenseBox(
                title: days == 1 ? "Free trial: 1 day left" : "Free trial: \(days) days left",
                symbol: "clock",
                detail: "Then $19 once. No subscription, updates included.",
                tint: .accentColor)
        case .trialEnded:
            licenseBox(
                title: "Your trial has ended",
                symbol: "exclamationmark.triangle.fill",
                detail: "Buy Hearby to keep listening: $19 once, updates included.",
                tint: .orange)
        }
    }

    /// Boxed and with real buttons: as small grey links, buyers missed both
    /// the trial countdown and where to enter the key from their email.
    private func licenseBox(title: String, symbol: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text in the primary color on an opaque box: tinted text over the
            // popover's translucent material vanished against some desktops.
            Label {
                Text(title).foregroundStyle(.primary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.body.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Buy Hearby…") { licensing.openBuyPage() }
                    .buttonStyle(.borderedProminent)
                // The license email and the website's thank-you page both say
                // "choose Enter Key…", so keep this label in step with them.
                Button("Enter Key…") { LicenseWindow.show() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 1.5))
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
