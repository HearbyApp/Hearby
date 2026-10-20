#!/usr/bin/env swift
// Issues a Hearby license key by hand: replacements, review copies, giveaways.
// Normal sales get their keys from the website; this produces the same format.
//
//   swift Scripts/make-license.swift someone@example.com ["Their Name"] [note]
//
// The private key is read from this Mac's Keychain ("Hearby License Signing
// Key"); macOS may ask for your login password the first time. The script
// prints only the license key, never the private key, and checks the result
// against the public key built into the app before printing it.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let email = args.first, email.contains("@") else {
    fail("usage: swift Scripts/make-license.swift EMAIL [\"NAME\"] [NOTE]")
}

// `security` rather than SecItemCopyMatching: the item's access list names
// the tools allowed to read it, and `security` is the one already allowed.
let security = Process()
security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
security.arguments = ["find-generic-password", "-s", "Hearby License Signing Key",
                      "-a", "HEARBY_LICENSE_PRIVATE_KEY", "-w"]
let pipe = Pipe()
security.standardOutput = pipe
try security.run()
security.waitUntilExit()
let secret = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard security.terminationStatus == 0, let der = Data(base64Encoded: secret), der.count == 48 else {
    fail("Could not read \"Hearby License Signing Key\" from the Keychain.")
}
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: der.suffix(32))

// Must match License.publicKey in Hearby/License.swift.
let appPublicKey = "NMBTZcAB0ddjaoOBEl/Ldv1jq3EsIASxECd6LI+Plbc="
guard privateKey.publicKey.rawRepresentation.base64EncodedString() == appPublicKey else {
    fail("The Keychain key does not match the public key built into the app.")
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .trimmingCharacters(in: CharacterSet(charactersIn: "="))
}

var fields: [String: Any] = ["v": 1, "email": email,
                             "issued": String(ISO8601DateFormatter().string(from: Date()).prefix(10))]
if args.count > 1 { fields["name"] = args[1] }
fields["order"] = args.count > 2 ? args[2] : "manual"
let payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
let signature = try privateKey.signature(for: payload)
guard privateKey.publicKey.isValidSignature(signature, for: payload) else { fail("Signature check failed.") }
print("HEARBY-" + base64URL(payload) + "." + base64URL(signature))
