import Foundation
import Security

/// The pairing secret for connecting an MCP client TO this person's things
/// (PRD §34). Generated once and kept in the Keychain — real and durable now.
/// The scanned payload also names the server endpoint, which is a placeholder
/// until the Goal-3 server exists: the token is real, the wire is not yet.
enum MCPPairing {
    /// Ship gate, same pattern as `SharedStore.cloudKitReady`: every pairing
    /// surface (chart Pair capsule, carousel story, product-page button) hides
    /// until a real server answers the payload's endpoint — a scannable code
    /// with no wire is a dead control. Ungated, Claude is a Soon row like any
    /// unwired offer. DEBUG `-openPair` still opens the sheet for design work.
    static let transportReady = false

    private static let service = "com.casberi.mcp.pairing"
    private static let account = "pairing-token"

    /// This install's stable pairing token — generated once, then read back.
    static func token() -> String {
        if let existing = load() { return existing }
        let fresh = newToken()
        save(fresh)
        return fresh
    }

    /// What a client scans: a custom-scheme URL carrying the token. The host is
    /// a placeholder endpoint until the server lands (honest gate).
    static func payload() -> String {
        "casberi-mcp://pair?token=\(token())&v=1"
    }

    /// The token in a human-readable short form (the fallback when a camera
    /// can't scan the code).
    static func shortCode() -> String {
        let t = token()
        return t.count >= 8 ? String(t.prefix(8)).uppercased() : t.uppercased()
    }

    /// Forget the pairing — the next `token()` mints a fresh one, which
    /// invalidates any client that paired on the old code (revoke).
    static func reset() { delete() }

    // MARK: - Keychain

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private static func save(_ token: String) {
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
