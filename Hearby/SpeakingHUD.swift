import AppKit
import Combine
import SwiftUI

/// A small floating pill at the top of the screen while Hearby is
/// getting ready or speaking.
///
/// The menu bar icon alone is easy to miss, and Kokoro can take a couple of
/// seconds before the first word — without something on screen, that gap
/// reads as the hotkey having failed, and people press it again (which
/// restarts the wait). The pill also carries a Stop button, so stopping
/// never depends on remembering ⌃⌥X.
///
/// With "Show text while speaking" on, the pill opens into a panel showing
/// the sentence being spoken, so the eye can follow the voice. It is drawn
/// here rather than over the document because only some apps report where
/// their text sits on screen; this works in all of them.
@MainActor
enum SpeakingHUD {
    static let enabledKey = "showSpeakingHUD"
    static let captionsKey = "showSpeakingCaptions"

    private static var panel: NSPanel?
    private static var subscription: AnyCancellable?

    static func install() {
        subscription = SpeechController.shared.$phase
            .removeDuplicates()
            .sink { phase in
                if phase == .idle || !UserDefaults.standard.bool(forKey: enabledKey, default: true) {
                    hide()
                } else {
                    show()
                }
            }
    }

    private static func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
    }

    private static func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
            // A new phase may have shown it again while this faded out.
            Task { @MainActor in
                if SpeechController.shared.phase == .idle { panel.orderOut(nil) }
            }
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 244, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        // Follows the user onto every Space, including fullscreen apps, which
        // is where most long-form reading happens.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SpeakingHUDView().environmentObject(SpeechController.shared))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    /// The content grows and shrinks with the sentence on show. Keep the
    /// panel hugging it, pinned at the top, on the screen it is already on.
    fileprivate static func contentSizeChanged(to size: CGSize) {
        guard let panel, panel.isVisible, size.width > 0, size.height > 0 else { return }
        position(panel, size: size, on: panel.screen)
    }

    /// Top center of the screen the pointer is on, just under the menu bar —
    /// close to the menu bar icon it mirrors, and clear of document content.
    private static func position(_ panel: NSPanel, size: CGSize? = nil, on screen: NSScreen? = nil) {
        let mouse = NSEvent.mouseLocation
        guard let screen = screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return }
        let size = size ?? panel.contentView?.fittingSize ?? panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10,
                   width: size.width, height: size.height),
            display: true)
    }
}

/// Never takes key focus: pressing the hotkey must not pull focus away from
/// the document being read, and clicking Stop must not either.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct SpeakingHUDView: View {
    @EnvironmentObject var speech: SpeechController
    @AppStorage(SpeakingHUD.captionsKey) private var showCaptions = true

    private var pieces: [String] { showCaptions ? speech.captionPieces : [] }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            controls
            if !pieces.isEmpty { caption }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, pieces.isEmpty ? 0 : 12)
        .frame(width: pieces.isEmpty ? 240 : 520)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .padding(2)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HUDSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(HUDSizeKey.self) { size in
            Task { @MainActor in SpeakingHUD.contentSizeChanged(to: size) }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Group {
                if speech.phase == .preparing {
                    ProgressView().controlSize(.small)
                } else if #available(macOS 14, *) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                } else {
                    Image(systemName: "waveform")
                }
            }
            .frame(width: 18)

            Text(speech.phase == .preparing ? "Getting ready…" : "Speaking")
                .font(.callout.weight(.medium))

            Spacer(minLength: 4)

            Button {
                showCaptions.toggle()
            } label: {
                Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(showCaptions ? "Hide the text" : "Show the text being spoken")

            Button {
                speech.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop speaking (⌃⌥X)")
        }
        .frame(height: 40)
    }

    /// The sentence being spoken, with one line of what came before and what
    /// comes next so the eye is never surprised by a jump.
    private var caption: some View {
        let index = min(speech.captionIndex, pieces.count - 1)
        return VStack(alignment: .leading, spacing: 4) {
            if index > 0 {
                Text(pieces[index - 1])
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }
            Text(pieces[index])
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Color.accentColor.opacity(speech.phase == .speaking ? 0.25 : 0),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            if index + 1 < pieces.count {
                Text(pieces[index + 1])
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HUDSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private extension UserDefaults {
    /// `bool(forKey:)` reads a missing key as false; the indicator is on
    /// unless the user has switched it off.
    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }
}
