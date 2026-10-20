import AppKit
import Foundation
import Security

/// Where small licensing values are kept. The Keychain survives deleting and
/// reinstalling the app, which a preferences file does not, so a reinstall
/// does not restart the trial. Tests swap in an in-memory store.
protocol SecretStore {
    func read(_ account: String) -> String?
    func write(_ account: String, _ value: String)
    func delete(_ account: String)
}

struct KeychainStore: SecretStore {
    /// Development builds, including the copy every test run launches, are
    /// signed by another team. Items they saved under the release name made
    /// released versions before 0.4.1 prompt for the password without end,
    /// so they keep their own.
    #if DEBUG
    let service = "app.hearby.Hearby.debug"
    #else
    let service = "app.hearby.Hearby"
    #endif

    /// An item saved by a differently signed copy of Hearby (a development
    /// build) makes macOS ask for the login password on every read, and each
    /// "Allow" lasts one read, so the prompts never stop. Hearby needs no
    /// Keychain UI at all: with interaction off such a read just fails, and
    /// the UserDefaults copy of the same value is used instead.
    init() {
        SecKeychainSetUserInteractionAllowed(false)
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ account: String, _ value: String) {
        let data = Data(value.utf8)
        if SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// The 7-day trial, measured from the first launch of a version that has one.
///
/// Two defenses, both cheap: the start date is kept in the Keychain and in
/// preferences and the earlier of the two wins, so clearing either one alone
/// does not restart the trial; and time never runs backwards, so setting the
/// Mac's clock back does not win days back. Someone determined can still get
/// around it. For a $19 app that is an acceptable trade against ever locking
/// out an honest user.
struct TrialClock {
    static let length: TimeInterval = 7 * 86_400

    enum Status: Equatable {
        case active(daysLeft: Int)
        case ended
    }

    let store: SecretStore
    let defaults: UserDefaults

    static let startedKey = "trial-started"
    static let lastSeenKey = "trial-last-seen"

    func status(now: Date) -> Status {
        let start: Date
        if let recorded = [store.read(Self.startedKey), defaults.string(forKey: Self.startedKey)]
            .compactMap({ $0.flatMap(Self.date) }).min() {
            start = recorded
        } else {
            start = now
        }
        // Rewritten every time so a copy deleted from one place comes back.
        save(Self.startedKey, start)

        let lastSeen = [store.read(Self.lastSeenKey), defaults.string(forKey: Self.lastSeenKey)]
            .compactMap { $0.flatMap(Self.date) }.max() ?? start
        let effectiveNow = max(now, lastSeen, start)
        if effectiveNow > lastSeen { save(Self.lastSeenKey, effectiveNow) }

        let remaining = Self.length - effectiveNow.timeIntervalSince(start)
        guard remaining > 0 else { return .ended }
        return .active(daysLeft: Int((remaining / 86_400).rounded(.up)))
    }

    func reset() {
        for key in [Self.startedKey, Self.lastSeenKey] {
            store.delete(key)
            defaults.removeObject(forKey: key)
        }
    }

    private func save(_ key: String, _ date: Date) {
        let text = Self.formatter.string(from: date)
        if store.read(key) != text { store.write(key, text) }
        defaults.set(text, forKey: key)
    }

    private static let formatter = ISO8601DateFormatter()
    private static func date(_ text: String) -> Date? { formatter.date(from: text) }
}

/// What the rest of the app asks: may Hearby speak, and what should the menu
/// say about the trial or license.
@MainActor
final class Licensing: ObservableObject {
    static let shared = Licensing()

    enum State: Equatable {
        case licensed(License)
        case trial(daysLeft: Int)
        case trialEnded
    }

    @Published private(set) var state: State = .trial(daysLeft: 7)

    /// Opens the purchase page. hearby.app/buy forwards to checkout, so the
    /// shipped app never has to know which payment provider is behind it.
    static let buyURL = URL(string: "https://hearby.app/buy?ref=app")!
    static let supportEmail = "support@hearby.app"

    private static let licenseAccount = "license"
    private let store: SecretStore
    private let defaults: UserDefaults
    private var clock: TrialClock { TrialClock(store: store, defaults: defaults) }

    init(store: SecretStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        refresh()
    }

    var allowsSpeaking: Bool { state != .trialEnded }

    /// Re-reads the license and the trial clock. Cheap; called whenever the
    /// menu opens and before every read, so "days left" is never stale.
    func refresh() {
        if let saved = store.read(Self.licenseAccount) ?? defaults.string(forKey: Self.licenseAccount),
           let license = try? License.verify(saved) {
            state = .licensed(license)
            return
        }
        switch clock.status(now: now) {
        case .active(let days): state = .trial(daysLeft: days)
        case .ended: state = .trialEnded
        }
    }

    /// Checks and saves a pasted key. Throws `License.Problem` with a message
    /// fit to show as-is.
    func activate(_ text: String) throws {
        let license = try License.verify(text)
        let compact = text.filter { !$0.isWhitespace }
        store.write(Self.licenseAccount, compact)
        defaults.set(compact, forKey: Self.licenseAccount)
        state = .licensed(license)
    }

    /// For moving to another Mac. The trial does not restart.
    func removeLicense() {
        store.delete(Self.licenseAccount)
        defaults.removeObject(forKey: Self.licenseAccount)
        refresh()
    }

    func openBuyPage() { NSWorkspace.shared.open(Self.buyURL) }

    // MARK: - Testing the trial without waiting a week

    /// Debug builds only: pretend this much time has passed. Release builds
    /// compile the offset out entirely, so it cannot be set from Terminal.
    private var now: Date {
        #if DEBUG
        return Date().addingTimeInterval(defaults.double(forKey: "debugTrialOffset"))
        #else
        return Date()
        #endif
    }

    #if DEBUG
    func debugSkipDays(_ days: Double) {
        defaults.set(defaults.double(forKey: "debugTrialOffset") + days * 86_400, forKey: "debugTrialOffset")
        refresh()
    }

    func debugRestartTrial() {
        defaults.removeObject(forKey: "debugTrialOffset")
        clock.reset()
        refresh()
    }
    #endif
}
