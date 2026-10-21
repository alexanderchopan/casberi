import Foundation

/// What this phone signed for an Aztec testnet account (2026-10-18, prd
/// §1419): the signer's own record, kept on this device. Each entry is what
/// the sheet showed when the person signed — the network, the account, the
/// call lines — never the signature, which the computer already holds.
///
/// Foundation-only, so `scripts/aztec-sign-selftest.sh` compiles it whole.
enum AztecSignedLog {
    struct Entry: Codable, Equatable, Identifiable {
        let at: Date
        let network: String
        let account: String
        let messageHash: String
        let lines: [String]
        var id: String { messageHash }
    }

    /// How many the page keeps: enough to see a session's work, small enough
    /// to read whole.
    static let cap = 30
    private static let key = "aztec.signer.log.v1"

    /// The entries, newest first.
    static func entries(_ defaults: UserDefaults = .standard) -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    /// Adds one signature's record. The same hash signed again (the computer
    /// retried) replaces its entry rather than doubling it.
    static func record(_ entry: Entry, _ defaults: UserDefaults = .standard) {
        var list = entries(defaults).filter { $0.messageHash != entry.messageHash }
        list.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(cap))) { defaults.set(data, forKey: key) }
    }

    static func forget(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    /// The entry for a request the sheet just signed.
    static func entry(for request: AztecSignRequest.Request, network: String, at: Date = .now) -> Entry {
        Entry(at: at, network: network, account: request.account.lowercased(),
              messageHash: request.messageHash.lowercased(),
              lines: request.calls.map { AztecSignRequest.line($0, account: request.account) })
    }
}
