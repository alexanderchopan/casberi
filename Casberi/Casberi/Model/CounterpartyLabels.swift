import Foundation
import Observation

/// Names the person gave to counterparty addresses (2026-07-15) — "this is Mom",
/// "my Ledger", "the DAO". A wallet transfer's counterparty is a raw hex until
/// something resolves it (a watched wallet, a known contract, ENS); this lets
/// the person supply the name themselves, from a transaction's thing sheet, and
/// it wins over every resolver because it's their own record. Consulted first by
/// `WalletIngest.counterpartyNames`, so every FUTURE transfer with that
/// counterparty carries the name. Kept out of `WalletStore` deliberately: those
/// are WATCHED addresses (things land from them); these are just labels for
/// addresses you meet in your activity, never watched.
///
/// Local, tiny (a hex→name dictionary in UserDefaults). Not synced — a note you
/// jotted on this device, like a contact nickname.
@Observable
final class CounterpartyLabels {
    static let shared = CounterpartyLabels()
    private static let key = "wallet.counterpartyLabels.v1"

    /// address (lowercased hex) → the name the person gave it.
    private var labels: [String: String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            labels = saved
        } else {
            labels = [:]
        }
    }

    /// The name for an address, or nil — a blank name means "no label",
    /// clearing any prior one.
    func label(for address: String) -> String? {
        let name = labels[address.lowercased()]
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// Sets (or, with an empty/whitespace name, clears) an address's label.
    func setLabel(_ name: String, for address: String) {
        let key = address.lowercased()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { labels.removeValue(forKey: key) }
        else { labels[key] = trimmed }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(labels) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
