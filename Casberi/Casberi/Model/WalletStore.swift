import Foundation
import Observation

/// The addresses Zerion watches (PRD Zerion ruling) — the person pastes an
/// address, it joins the watch list, its activity lands as things. Add, remove,
/// and reorder are the person's; order is meaningful (the first address leads
/// the wallet view). Read-only by nature: an address is public; watching one
/// can never trade or move funds.
@Observable
final class WalletStore {
    static let shared = WalletStore()
    private static let key = "zerion.addresses"

    struct WatchedAddress: Codable, Identifiable, Equatable {
        var id = UUID()
        /// A name the person gave it ("Main", "Cold") — optional, address shows if empty.
        var label: String
        var address: String

        /// "0x1a2B…4f4f" — the row form.
        var short: String {
            guard address.count > 12 else { return address }
            return "\(address.prefix(6))…\(address.suffix(4))"
        }
    }

    var addresses: [WatchedAddress] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([WatchedAddress].self, from: data) {
            addresses = saved
        } else if DemoState.seedsDemoData {
            // The demo bridge's status line names this address — keep them in step.
            addresses = [WatchedAddress(label: "Main", address: "0x1a2B3c4D5e6F70819283a4B5c6D7e8F901234f4f")]
        } else {
            addresses = []
        }
    }

    /// Adds a pasted address. Light validation only — an address is public
    /// data and a bad one simply never produces things.
    @discardableResult
    func add(_ raw: String, label: String = "") -> Bool {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addr.count >= 6,
              !addresses.contains(where: { $0.address.lowercased() == addr.lowercased() })
        else { return false }
        addresses.append(WatchedAddress(label: label, address: addr))
        return true
    }

    func remove(at offsets: IndexSet) {
        addresses.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        addresses.move(fromOffsets: source, toOffset: destination)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
