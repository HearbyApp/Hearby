import Combine
import Foundation
import Sparkle

/// Sparkle auto-update, wrapped so the rest of the app never imports Sparkle.
///
/// Security model: Sparkle installs an update only if its EdDSA signature
/// verifies against `SUPublicEDKey` in Info.plist *and* its Developer ID
/// signature matches the running app. The private half of that key pair lives
/// in the release machine's login Keychain and is never in the repository —
/// `Scripts/release.sh` signs each build with it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// False while a check is already running, so the menu item can disable
    /// itself instead of queueing duplicate checks.
    @Published private(set) var canCheck = false

    /// True once a real feed URL has been configured. Until then the updater
    /// is not started at all — pointing Sparkle at the placeholder would mean
    /// a background check failing every day for no reason.
    let isConfigured: Bool

    private let controller: SPUStandardUpdaterController?

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        isConfigured = !feed.isEmpty && !feed.contains(Self.placeholderOwner)

        guard isConfigured else {
            controller = nil
            NSLog("Hearby: auto-update disabled — SUFeedURL is still the placeholder.")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    /// Matches the placeholder in project.yml's SUFeedURL.
    static let placeholderOwner = "YOUR-GITHUB-USERNAME"

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// The repository the feed is served from, which is also where the GPL
    /// source offer points. Nil while the feed is still the placeholder.
    static var sourceURL: URL? {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard !feed.contains(placeholderOwner), let releases = feed.range(of: "/releases/")
        else { return nil }
        return URL(string: String(feed[..<releases.lowerBound]))
    }

    /// Version string for the menu bar footer.
    static var displayVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "—"
    }
}
