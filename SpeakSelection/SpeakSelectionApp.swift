import SwiftUI
import AppKit

@main
struct SpeakSelectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var speech = SpeechController.shared

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
    }

    private func speakCurrentSelection() {
        Task { @MainActor in
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
                SpeechController.shared.statusMessage =
                    "Hotkey needs Accessibility access: System Settings → Privacy & Security → Accessibility → enable SpeakSelection."
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
