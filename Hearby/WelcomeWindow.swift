import AppKit
import SwiftUI

/// First-run onboarding.
///
/// A menu-bar-only app is invisible by definition: without this, first launch
/// looks like nothing happened, and the two things a user must know — where
/// the app lives and how to invoke it — are undiscoverable. It also gives
/// the Accessibility grant a place to happen calmly, instead of as a
/// surprise dialog the first time someone presses the hotkey.
@MainActor
enum WelcomeWindow {
    private static var controller: NSWindowController?

    /// Shown once, then only on request. Tracked by version so a future
    /// release can reintroduce it after a meaningful change.
    @AppStorage("welcomeShownForVersion") private static var shownFor = ""

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func showIfFirstRun() {
        guard shownFor != currentVersion else { return }
        shownFor = currentVersion
        show()
    }

    static func show() {
        if let controller {
            present(controller.window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Welcome to Hearby"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: WelcomeView())

        let wc = NSWindowController(window: window)
        controller = wc
        present(window)
    }

    /// Brings the window to wherever the user actually is.
    ///
    /// `makeKeyAndOrderFront` alone puts it on the Space the app last used,
    /// which for a menu-bar app is usually not the Space in front of the
    /// user — someone reading in a fullscreen browser would trigger this and
    /// see nothing happen. `.moveToActiveSpace` follows them instead.
    private static func present(_ window: NSWindow?) {
        guard let window else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        // LSUIElement apps are not in the Dock and do not come forward on
        // their own; without this the window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        controller?.close()
    }
}

struct WelcomeView: View {
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var downloader = ModelDownloader.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hearby")
                    .font(.largeTitle.weight(.semibold))
                Text("Select text anywhere, and hear it read aloud.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            step(
                number: 1,
                title: "Look for the speaker in your menu bar",
                detail: "Hearby has no Dock icon or window — it lives up "
                    + "there. Click it any time for voice, speed and playback controls."
            )

            step(
                number: 2,
                title: "Select text, then press ⌃⌥S",
                detail: "⌃⌥X stops. This works in every app, including terminals "
                    + "and VS Code. In most native apps you can also right-click "
                    + "and choose Services → Speak Selection."
            )

            step(
                number: 3,
                title: "Allow Accessibility access",
                detail: "The keyboard shortcut needs it to read your selection. "
                    + "The right-click Services menu works without it."
            ) {
                accessibilityControls
            }

            if case .downloading(let progress) = downloader.state {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Downloading voices… \(Int(progress * 100))%")
                        .font(.callout)
                    ProgressView(value: progress)
                    Text("Apple's built-in voices work right now; the "
                        + "high-quality ones take over when this finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Toggle("Open at login", isOn: $permissions.launchAtLogin)
                Spacer()
                Button("Get Started") { WelcomeWindow.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460, height: 560, alignment: .topLeading)
        .onAppear { permissions.beginWatching() }
        .onDisappear { permissions.endWatching() }
    }

    @ViewBuilder
    private var accessibilityControls: some View {
        if permissions.isTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else {
            HStack(spacing: 8) {
                Button("Allow Access…") { permissions.showAccessibilityControls() }
                Button("Open Settings") { permissions.openSettings() }
                    .buttonStyle(.link)
            }
            Text("In System Settings, switch on Hearby under "
                + "Privacy & Security → Accessibility. " + Permissions.staleEntryHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func step(
        number: Int, title: String, detail: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.tint))

            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }
}
