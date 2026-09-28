import SwiftUI
import AppKit

@main
struct SpeakSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var speech = SpeechController.shared

    init() {
        // `SpeakSelection.app/Contents/MacOS/SpeakSelection --self-test`
        // loads the installed voice bundle, synthesizes one phrase and exits
        // non-zero if anything is wrong. Run by Scripts/release.sh so a
        // model/config mismatch fails the build instead of shipping mute.
        if CommandLine.arguments.contains("--self-test") { SelfTest.runAndExit() }
    }

    var body: some Scene {
        MenuBarExtra("SpeakSelection", systemImage: speech.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2") {
            MenuBarView()
                .environmentObject(speech)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()
    private let hotKeys = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the object that receives right-click Services invocations.
        NSApp.servicesProvider = serviceProvider
        // Ask the pasteboard server to re-scan Info.plist service definitions
        // so "Speak Selection" shows up without a logout.
        NSUpdateDynamicServices()

        // Global hotkeys: ⌃⌥S speak selection, ⌃⌥X stop. These cover apps
        // the Services menu can't reach (terminal TUIs, VS Code/Electron).
        hotKeys.onSpeak = { [weak self] in self?.speakCurrentSelection() }
        hotKeys.onStop = { Task { @MainActor in SpeechController.shared.stop() } }
        hotKeys.install()

        // Warm up the Kokoro sidecar in the background so the first
        // "Speak Selection" doesn't pay the model-load cost.
        Task { await SpeechController.shared.warmUp() }

        // Starts Sparkle's scheduled background checks. Referencing the
        // singleton is what constructs it; it no-ops until a real feed URL
        // is configured.
        _ = Updater.shared

        // A menu-bar-only app that opens nothing looks like a failed launch.
        WelcomeWindow.showIfFirstRun()
    }

    private func speakCurrentSelection() {
        Task { @MainActor in
            guard Permissions.shared.isTrusted else {
                // The system prompt appears only once per app signature, so on
                // later attempts it does nothing and the user is left with a
                // hotkey that seems broken. Show the window that explains it.
                Permissions.shared.requestAccess()
                if !Permissions.shared.isTrusted { WelcomeWindow.show() }
                SpeechController.shared.statusMessage =
                    "The keyboard shortcut needs Accessibility access."
                return
            }
            let text = await SelectionGrabber.grabSelectedText()?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, !text.isEmpty else {
                SpeechController.shared.statusMessage = "No selected text found."
                return
            }
            await SpeechController.shared.speak(text)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SpeechController.shared.shutdown()
    }
}
