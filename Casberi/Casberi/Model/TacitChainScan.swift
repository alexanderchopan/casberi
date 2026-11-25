import Foundation

/// WHERE THE LAST TACIT CHAIN SCAN STOPPED, KEPT ON THIS PHONE.
///
/// A scan tries every note on the Tacit chain with your key; thousands of
/// them, about half a minute through Tor. Keeping where it stopped and the
/// notes it found lets the next open try only what came after (user,
/// 2026-11-24: "do all", of "open instantly, then refresh").
///
/// The notes hold their secrets, which say what you hold but cannot spend
/// it (spending needs the key the co-signer's signature makes, never kept).
/// So they live in the Keychain, this device only (`TokenVault`), keyed by
/// the co-signer, and go when Tacit is removed.
enum TacitChainScan {
    struct Kept: Codable, Equatable {
        let next: Int
        let notes: [TacitEngineWire.KeptNote]
    }

    static func key(_ coSigner: String) -> String {
        "tacit.chainScan.v1.\(coSigner.lowercased())"
    }

    static func load(_ coSigner: String) -> Kept? {
        guard let text = TokenVault.get(key(coSigner)), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Kept.self, from: data)
    }

    static func save(_ kept: Kept, for coSigner: String) {
        guard let data = try? JSONEncoder().encode(kept), let text = String(data: data, encoding: .utf8) else { return }
        TokenVault.set(text, for: key(coSigner))
    }

    static func forget(_ coSigner: String) {
        TokenVault.delete(key(coSigner))
    }
}
