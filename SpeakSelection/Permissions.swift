import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// Accessibility permission state, and the login-item toggle.
///
/// Accessibility is needed only for the global hotkey, which reads the
/// selection out of whatever app is frontmost. The right-click Services entry
/// works without it, because macOS hands the text to us. Saying so plainly
/// matters: users who only want the Services flow should not be pushed
/// through a scary permission dialog for a feature they will not use.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    /// macOS grants the permission out of process and gives no notification,
    /// so polling is the only way to notice. Cheap call; 1s is imperceptible
    /// to the user and invisible in Activity Monitor.
    private var timer: Timer?
    /// The popover and the welcome window can both be showing the permission
    /// state. Refcounted so whichever closes first does not stop polling for
    /// the other.
    private var watchers = 0

    private init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Polls only while something is actually showing the state.
    func beginWatching() {
        watchers += 1
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Triggers the system's own "allow accessibility access" dialog. macOS
    /// shows this only once per app signature — after the user dismisses it,
    /// further calls are silent, which is why `openSettings()` exists as the
    /// reliable fallback.
    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    /// Opens System Settings directly on Privacy & Security -> Accessibility.
    func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration fails for an unsigned or quarantined build. Reflect
            // reality rather than leaving the toggle lying to the user.
            NSLog("SpeakSelection: launch-at-login change failed: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
