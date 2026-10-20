import CryptoKit
import Foundation

/// A Hearby license key, checked entirely offline.
///
/// Format: `HEARBY-<payload>.<signature>`, both parts base64url without
/// padding. The payload is UTF-8 JSON such as
/// `{"v":1,"email":"a@b.com","name":"Ann","order":"cs_…","issued":"2026-10-19"}`
/// and the signature is Ed25519 over exactly those payload bytes. The website
/// signs with the private key (a Lovable secret); the app only ever holds the
/// public half below, which can check keys but never create them.
///
/// Nothing here contacts a server: a license keeps working offline, forever,
/// and survives the website going away.
struct License: Equatable {
    let email: String
    let name: String?
    let order: String?
    let issued: String?

    /// Public half of the license signing key generated 2026-10-19. The private
    /// half is in the release Mac's Keychain ("Hearby License Signing Key") and
    /// in the website's secrets. Replacing it invalidates every key already
    /// sold, so it only changes together with a plan for existing customers.
    static let publicKey = try! Curve25519.Signing.PublicKey(
        rawRepresentation: Data(base64Encoded: "NMBTZcAB0ddjaoOBEl/Ldv1jq3EsIASxECd6LI+Plbc=")!)

    static let prefix = "HEARBY-"

    enum Problem: Error, Equatable, LocalizedError {
        case malformed, badSignature, newerVersion

        var errorDescription: String? {
            switch self {
            case .malformed:
                "That doesn't look like a Hearby license key. Copy the whole key from your email, starting with HEARBY-."
            case .badSignature:
                "This key isn't valid. Check that all of it was copied, or write to support@hearby.app."
            case .newerVersion:
                "This key is for a newer version of Hearby. Check for updates, then try again."
            }
        }
    }

    private struct Payload: Decodable {
        let v: Int
        let email: String
        let name: String?
        let order: String?
        let issued: String?
    }

    /// Checks `text` and returns who it is licensed to.
    ///
    /// Email clients wrap long lines and people paste with stray spaces, so
    /// all whitespace is ignored. The prefix is case-insensitive; the base64
    /// parts are not, because changing their case changes the bytes.
    static func verify(_ text: String, publicKey: Curve25519.Signing.PublicKey = publicKey) throws -> License {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.uppercased().hasPrefix(prefix) else { throw Problem.malformed }
        let parts = compact.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Data(base64URL: String(parts[0])),
              let signature = Data(base64URL: String(parts[1])),
              signature.count == 64
        else { throw Problem.malformed }

        guard publicKey.isValidSignature(signature, for: payload) else { throw Problem.badSignature }

        // Only signed bytes are decoded, so a well-formed but forged payload
        // never gets this far.
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: payload) else {
            throw Problem.malformed
        }
        guard decoded.v == 1 else { throw Problem.newerVersion }
        let email = decoded.email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { throw Problem.malformed }
        return License(email: email, name: decoded.name, order: decoded.order, issued: decoded.issued)
    }
}

extension Data {
    /// RFC 4648 §5 base64url, padding optional.
    init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !base64.contains("=") || base64.hasSuffix("=") else { return nil }
        base64 = base64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
