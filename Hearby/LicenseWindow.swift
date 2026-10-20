import AppKit
import SwiftUI

/// Enter, view or remove a license key. Also what ⌃⌥S opens once the trial
/// has ended, so the shortcut explains itself instead of doing nothing.
@MainActor
enum LicenseWindow {
    private static var controller: NSWindowController?

    static func show() {
        Licensing.shared.refresh()
        if let window = controller?.window {
            present(window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Hearby License"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: LicenseView())
        controller = NSWindowController(window: window)
        present(window)
    }

    /// Same reasoning as WelcomeWindow: follow the user to their Space and
    /// come forward even though a menu-bar app is never active on its own.
    private static func present(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() { controller?.close() }
}

struct LicenseView: View {
    @ObservedObject private var licensing = Licensing.shared
    @State private var key = ""
    @State private var problem: String?
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch licensing.state {
            case .licensed(let license): licensed(license)
            case .trial(let days): entry(title: "Enter your license key", status: Self.trialText(days))
            case .trialEnded:
                entry(title: "Your trial has ended",
                      status: "Buy Hearby to keep listening. It's $19 once, with updates included.")
            }
        }
        .padding(28)
        .frame(width: 440, alignment: .topLeading)
    }

    static func trialText(_ days: Int) -> String {
        days == 1 ? "Your trial has 1 day left." : "Your trial has \(days) days left."
    }

    @ViewBuilder
    private func entry(title: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.weight(.semibold))
            Text(status).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("License key").font(.callout.weight(.medium))
            // Multi-line because keys arrive wrapped across lines in email.
            TextEditor(text: $key)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                .onChange(of: key) { _ in problem = nil }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack {
            Button("Buy Hearby, $19") { licensing.openBuyPage() }
            Spacer()
            Button("Activate") { activate() }
                .keyboardShortcut(.defaultAction)
                .disabled(key.allSatisfy(\.isWhitespace))
        }

        Text("Lost your key? Write to \(Licensing.supportEmail) with the email you bought with.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func licensed(_ license: License) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hearby is licensed", systemImage: "checkmark.seal.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
            Text("Licensed to \(license.email). Thank you for buying Hearby.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        HStack {
            Button("Remove License Key…") { confirmingRemoval = true }
            Spacer()
            Button("Done") { LicenseWindow.close() }
                .keyboardShortcut(.defaultAction)
        }
        .confirmationDialog(
            "Remove the license key from this Mac?", isPresented: $confirmingRemoval
        ) {
            Button("Remove", role: .destructive) { licensing.removeLicense() }
        } message: {
            Text("Use this when moving Hearby to another Mac. Keep your license email: you'll need the key to activate again.")
        }
    }

    private func activate() {
        do {
            try licensing.activate(key)
            key = ""
        } catch {
            problem = error.localizedDescription
        }
    }
}
