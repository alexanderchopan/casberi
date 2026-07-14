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
    private static let key = "wallet.addresses"

    struct WatchedAddress: Codable, Identifiable, Equatable {
        var id = UUID()
        /// A name the person gave it ("Main", "Cold") — optional, address shows if empty.
        var label: String
        var address: String
        /// Holdings on Home and Feed (ruling 2026-07-09): per WALLET, not one
        /// switch for everything watched — two watched addresses are usually
        /// two different purposes, and a person may only want one of them
        /// showing. Same idea as a Feed pin ("keep this in view"), scoped to
        /// the address it's swiped on.
        var pinnedToHome: Bool = false

        enum CodingKeys: String, CodingKey { case id, label, address, pinnedToHome }

        init(id: UUID = UUID(), label: String, address: String, pinnedToHome: Bool = false) {
            self.id = id
            self.label = label
            self.address = address
            self.pinnedToHome = pinnedToHome
        }

        /// Custom decode: older persisted data has no `pinnedToHome` key —
        /// defaults to false rather than failing to decode at all.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            label = try c.decode(String.self, forKey: .label)
            address = try c.decode(String.self, forKey: .address)
            pinnedToHome = try c.decodeIfPresent(Bool.self, forKey: .pinnedToHome) ?? false
        }

        /// "0x1a2B…4f4f" — the row form.
        var short: String { WalletStore.shortAddress(address) }
    }

    /// "0x1a2B…4f4f" — the one address-shortening rule, shared with every
    /// surface that shows an address it has no label for.
    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    var addresses: [WatchedAddress] {
        didSet {
            persist()
            // A dropped wallet takes its value history with it — watching
            // ended, so the record ends (and re-watching starts honest, at
            // zero history, not a resurrected line with a hole in it).
            let kept = Set(addresses.map { $0.address.lowercased() })
            for old in oldValue where !kept.contains(old.address.lowercased()) {
                UserDefaults.standard.removeObject(forKey: Self.historyKey(old.address))
            }
        }
    }

    // MARK: - Value history (2026-07-14)

    /// One point of a wallet's USD value line — sampled whenever holdings are
    /// really fetched (WalletIngest), at most one per 4 hours, capped at 240
    /// points. Forward-only and honest: history exists from the moment
    /// watching began, sampled as the app is used — never back-filled.
    struct ValueSample: Codable {
        let at: Date
        let usd: Double
    }

    private static func historyKey(_ address: String) -> String {
        "wallet.history.\(address.lowercased())"
    }

    func valueSamples(forAddress address: String) -> [ValueSample] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey(address)),
              let samples = try? JSONDecoder().decode([ValueSample].self, from: data)
        else { return [] }
        return samples
    }

    /// Appends a sample unless one landed in the last 4 hours — holdings
    /// refresh every foreground, and a line of near-identical minutes-apart
    /// points is noise, not history.
    func recordSample(address: String, totalUSD: Double) {
        var samples = valueSamples(forAddress: address)
        if let last = samples.last, Date.now.timeIntervalSince(last.at) < 4 * 3600 { return }
        samples.append(ValueSample(at: .now, usd: totalUSD))
        if samples.count > 240 { samples.removeFirst(samples.count - 240) }
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: Self.historyKey(address))
        }
    }

    /// The name a Wallet transaction's row shows when more than one address
    /// is watched — matched by exact address string (an ENS-named watch
    /// won't match its resolved hex form; the row simply carries no label
    /// then, never a wrong one).
    func label(forAddress address: String?) -> String? {
        guard let address, addresses.count > 1,
              let match = addresses.first(where: { $0.address.lowercased() == address.lowercased() })
        else { return nil }
        return match.label.isEmpty ? match.short : match.label
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

    /// Flips one address's pin — scoped to that wallet, never the whole list.
    func togglePin(_ id: WatchedAddress.ID) {
        guard let i = addresses.firstIndex(where: { $0.id == id }) else { return }
        addresses[i].pinnedToHome.toggle()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
