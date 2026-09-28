import AppKit

/// Receives the right-click Services menu invocations declared in Info.plist.
///
/// The selector name must match `NSMessage` in the NSServices entry:
/// `NSMessage: speakSelectedText`  ->  `speakSelectedText(_:userData:error:)`
final class ServiceProvider: NSObject {

    @objc func speakSelectedText(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            error.pointee = "No text was selected." as NSString
            return
        }
        Task { await SpeechController.shared.speak(text) }
    }

    @objc func stopSpeaking(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        Task { await SpeechController.shared.stop() }
    }
}
