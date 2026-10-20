import AppKit

/// Offers to move Hearby into /Applications when it is opened straight from
/// the disk image or the Downloads folder.
///
/// Run from the disk image, Hearby disappears when the image is ejected and
/// asks for Accessibility again once it is finally installed. The DMG window
/// says to drag it to Applications; this catches the people who double-click
/// instead.
enum AppMover {
    /// Whether an app at `path` should be offered the move. Only the places a
    /// download lands: a mounted disk image, Downloads, or Gatekeeper's
    /// translocated copy of either. Anywhere else was a deliberate choice.
    static func shouldOffer(path: String, home: String = NSHomeDirectory()) -> Bool {
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") {
            return false
        }
        return path.hasPrefix("/Volumes/")
            || path.contains("/AppTranslocation/")
            || path.hasPrefix(home + "/Downloads/")
    }

    /// The mounted disk image `path` is on, to eject after moving.
    static func volume(of path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/\(parts[1])"
    }

    /// Asks, and if the user agrees, installs this copy into /Applications,
    /// relaunches it from there and quits. Returns true when this copy is
    /// quitting, so launch should stop here.
    @MainActor
    static func offerMoveIfNeeded() -> Bool {
        #if DEBUG
        return false
        #else
        let source = Bundle.main.bundleURL
        guard shouldOffer(path: source.path) else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Hearby to your Applications folder?"
        alert.informativeText = "Hearby is running from the download. Moving it to Applications keeps it installed after you eject the disk image or clear Downloads."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let destination = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(source.lastPathComponent)
        do {
            try install(source, at: destination)
        } catch {
            let failed = NSAlert()
            failed.messageText = "Hearby couldn't be moved"
            failed.informativeText = "\(error.localizedDescription)\n\nDrag Hearby onto the Applications folder in the disk image window instead."
            failed.runModal()
            return false
        }
        relaunch(destination, ejecting: volume(of: source.path))
        NSApp.terminate(nil)
        return true
        #endif
    }

    /// Replaces any older copy, which goes to the Trash rather than being
    /// deleted, and quits it first if it is running.
    private static func install(_ source: URL, at destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            let me = NSRunningApplication.current
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            where app != me && app.bundleURL?.standardizedFileURL == destination.standardizedFileURL {
                app.terminate()
            }
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: destination)
    }

    /// Opens the installed copy once this process has exited, so the two
    /// never hold the hotkeys at the same time, then ejects the disk image.
    private static func relaunch(_ app: URL, ejecting volume: String?) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
            while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
            /usr/bin/open "$1"
            [ -n "$2" ] && /usr/bin/hdiutil detach "$2" -quiet
            exit 0
            """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, "sh", app.path, volume ?? ""]
        try? task.run()
    }
}
