import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey. Unlike the Services key
/// equivalent, these fire no matter which app is frontmost — including
/// terminal TUIs that capture the mouse and Electron apps (VS Code) that
/// never implement the macOS Services protocol.
///
/// Defaults: ⌃⌥S = speak selection, ⌃⌥X = stop. Deliberately not ⌘⇧S —
/// a global hotkey swallows its combo system-wide, and ⌘⇧S is Save As /
/// Duplicate in many document apps.
final class HotKeyManager {
    var onSpeak: (() -> Void)?
    var onStop: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []

    func install() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        // GetEventDispatcherTarget, not GetApplicationEventTarget: hot key
        // events for background/menu-bar apps are only delivered through the
        // dispatcher target (same choice as MASShortcut/HotKey libraries).
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                Unmanaged<HotKeyManager>.fromOpaque(userData)
                    .takeUnretainedValue().dispatch(id: hotKeyID.id)
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef)

        register(id: 1, keyCode: UInt32(kVK_ANSI_S))
        register(id: 2, keyCode: UInt32(kVK_ANSI_X))
    }

    private func register(id: UInt32, keyCode: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5350_4B53) /* 'SPKS' */, id: id)
        let status = RegisterEventHotKey(
            keyCode, UInt32(controlKey | optionKey), hotKeyID,
            GetEventDispatcherTarget(), 0, &ref)
        if status != noErr {
            NSLog("Hearby: RegisterEventHotKey(id %d) failed: %d", id, status)
        }
        hotKeyRefs.append(ref)
    }

    private func dispatch(id: UInt32) {
        switch id {
        case 1: onSpeak?()
        case 2: onStop?()
        default: break
        }
    }
}

/// Remembers when the clipboard last changed, so the hotkey can tell a copy
/// made moments ago from one left over from earlier.
///
/// NSPasteboard has no change notification; polling `changeCount` is the only
/// way to timestamp a change.
@MainActor
final class ClipboardWatcher {
    static let shared = ClipboardWatcher()

    private var lastCount = NSPasteboard.general.changeCount
    private var lastChange: Date?
    private var timer: Timer?
    private var paused = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in self.poll() }
        }
    }

    private func poll() {
        guard !paused else { return }
        let count = NSPasteboard.general.changeCount
        guard count != lastCount else { return }
        lastCount = count
        lastChange = Date()
    }

    func pause() { paused = true }

    /// Swallows whatever changed while paused.
    func resume() {
        lastCount = NSPasteboard.general.changeCount
        paused = false
    }

    /// The clipboard's text, if it was copied within the last `seconds`.
    func recentText(within seconds: TimeInterval) -> String? {
        poll()
        guard let lastChange, Date().timeIntervalSince(lastChange) <= seconds else { return nil }
        let pasteboard = NSPasteboard.general
        // Password managers flag their copies; never read those aloud.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pasteboard.types?.contains(concealed) != true else { return nil }
        return pasteboard.string(forType: .string)
    }
}

/// Reads the frontmost app's current text selection.
///
/// Strategy: ask the Accessibility API for the focused element's selected
/// text (no side effects). Apps that don't expose it (some Electron/terminal
/// setups) fall back to a synthesized ⌘C, reading the pasteboard, then
/// restoring the previous clipboard string.
///
/// Both paths require the app to be trusted in System Settings →
/// Privacy & Security → Accessibility.
///
/// Neither path can see a selection drawn by a terminal TUI that captures the
/// mouse (Claude Code in fullscreen mode, for one): the terminal itself has
/// nothing selected, so AX reports no text and ⌘C copies nothing. Those TUIs
/// copy to the clipboard on mouse release instead, so a clipboard that changed
/// in the last few seconds stands in for the selection.
@MainActor
enum SelectionGrabber {
    /// Long enough to select and reach for the hotkey, short enough that an
    /// old copy is not read back as if it were the selection.
    private static let recentCopyWindow: TimeInterval = 30

    static func grabSelectedText() async -> String? {
        let axText = axSelectedText()
        if let axText, !axText.isEmpty { return axText }
        // nil means the app does not expose its selection, so ⌘C is the only
        // way to find out. An empty string means it does and nothing is
        // selected: ⌘C would only beep and burn the full poll timeout.
        if axText == nil, let text = await copiedSelection(), !text.isEmpty { return text }
        return ClipboardWatcher.shared.recentText(within: recentCopyWindow)
    }

    private static func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected) == .success
        else { return nil }
        return selected as? String
    }

    private static func copiedSelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let startCount = pasteboard.changeCount

        // Our own copy-and-restore round trip is not the user copying.
        ClipboardWatcher.shared.pause()
        defer { ClipboardWatcher.shared.resume() }

        await postCmdC()
        // The copy lands asynchronously; poll briefly for the change.
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pasteboard.changeCount != startCount { break }
        }
        guard pasteboard.changeCount != startCount else { return nil }
        let text = pasteboard.string(forType: .string)

        if let previous {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
        return text
    }

    /// Waits for ⌃ and ⌥ to be physically released, up to ~400ms.
    ///
    /// The hotkey is ⌃⌥S and Carbon fires on key-down, so both modifiers are
    /// still held when we get here. A synthetic event posted in that window
    /// inherits the live hardware modifiers and arrives as ⌃⌥⌘C, which no app
    /// maps to Copy — the reason this fallback silently failed in Terminal.
    private static func waitForModifiersToClear() async {
        for _ in 0..<20 {
            let held = NSEvent.modifierFlags.intersection([.control, .option, .command])
            if held.isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func postCmdC() async {
        await waitForModifiersToClear()
        // .privateState, not .combinedSessionState: the latter ORs in whatever
        // modifiers are physically down at post time.
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
