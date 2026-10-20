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
        UserDefaults.standard.set(true, forKey: Self.promptedKey)
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    private static let promptedKey = "accessibility-prompted"

    /// Whether the system dialog has been asked for; after that macOS
    /// silently ignores further requests.
    var hasPrompted: Bool { UserDefaults.standard.bool(forKey: Self.promptedKey) }

    /// One route to the switch: the system dialog the first time (it has its
    /// own Open System Settings button and adds Hearby to the list), and
    /// Settings directly after that, when the dialog no longer appears.
    /// Doing both at once opened Settings on top of the unanswered dialog.
    func showAccessibilityControls() {
        if hasPrompted {
            openSettings()
        } else {
            requestAccess()
        }
    }

    /// An entry left by a differently signed copy (an older install, a test
    /// build) shows Hearby switched on yet grants nothing, and Settings gives
    /// no sign of it. Removing and re-adding the entry is the only cure.
    static let staleEntryHint =
        "Already switched on? Select Hearby in the list, click −, then switch it on again."

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
            NSLog("Hearby: launch-at-login change failed: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
