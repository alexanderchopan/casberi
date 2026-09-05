import Foundation

/// What an address calls ITSELF, across every name service this app reads
/// (prd §597, 2026-09-04) — ENS, Wei and Gwei.
///
/// **This is not the address book's name.** §169 says a name the person typed
/// is their data; this is a claim the ADDRESS makes, and the two are kept
/// apart everywhere. Nothing here ever writes `AddressBook.setName` for a real
/// name somebody chose — see `AddressBookScreen`'s fill, which only ever
/// stands in for an AUTO name (`WalletStore.isAutoName`, the `…44b1` display
/// fallback that is nobody's word).
///
/// **Why a store rather than a lookup.** `ENS.reverseName` caches per LAUNCH,
/// which is right for a transfer counterparty — transient, re-derived every
/// sweep. A book entry is durable and the book is UNCAPPED (naming is free by
/// §169, and entries land by themselves from counterparties, Safes, and the
/// vibenet/Hegotá/Frames/Altana signers), so a per-launch cache means the same
/// hundreds of addresses are re-asked on every cold start, three services
/// each. This persists, misses included.
///
/// **The miss IS the answer worth keeping.** Most addresses have set no
/// primary name on any of the three, so an unkept miss is the expensive case,
/// not the rare one.
///
/// **A READ IS BOUGHT BY AN INTENT, NEVER BY A ROW SCROLLING PAST.** Only two
/// things ask: opening an address's card, and the watched wallets on a
/// foreground. Rows DISPLAY what is already known and trigger nothing. The
/// arithmetic is why — a book of three hundred is ordinary, each address costs
/// up to three services, and the calls are paced against one shared public
/// host, so filling on appear turns a scroll to the bottom of the book into
/// several minutes of continuous chain reads that nobody asked for. Filling on
/// a tap bounds it to what somebody actually looked at, and the book fills in
/// as it is used.
@MainActor
@Observable
final class AddressNames {
    static let shared = AddressNames()

    /// One address's answer. `names` empty means ASKED AND NONE — distinct
    /// from no record at all, which means never asked, and the two must never
    /// render the same way (§83: "no ENS" is a claim we have not earned until
    /// we have looked).
    struct Record: Codable, Equatable {
        var names: [Entry]
        var askedAt: Date
    }

    struct Entry: Codable, Equatable, Hashable {
        var label: String
        var name: String
    }

    private static let storeKey = "addressNames.v1"

    /// How long an answer stands before it is worth re-asking. A primary name
    /// is set once and rarely moved, and the cost of being a fortnight late to
    /// somebody's new name is nothing — while re-asking a book of hundreds is
    /// three calls each.
    private static let freshness: TimeInterval = 14 * 24 * 3600

    /// The most addresses one pass will look up. A book of hundreds must not
    /// turn a single screen open into hundreds of sequential chain reads; the
    /// rows on screen ask, the rest wait for a later visit.
    static let perPassBudget = 12

    /// OBSERVED, deliberately: a row draws from this, so a name landing has to
    /// re-render the list that is showing it. That is also why there is no
    /// separate revision counter — one would be a second source of truth for
    /// "something changed", and the dictionary already is one.
    private var records: [String: Record] = [:]

    /// In flight right now — so two rows for one address (the book and the
    /// card behind it) do not each buy the same three calls.
    @ObservationIgnored
    private var asking: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
    }

    private static func key(for address: String) -> String { address.lowercased() }

    /// The names known for this address, or nil when it has never been asked.
    /// An empty array is a real answer.
    func names(for address: String) -> [Entry]? {
        records[Self.key(for: address)]?.names
    }

    /// The one name a ROW should stand in with, when it has no name of its
    /// own. First in `NameResolve.primaryNames`' fixed order — ENS, then Wei,
    /// then Gwei — because a row has space for one and choosing by any other
    /// rule would be ranking somebody's names against each other.
    func rowName(for address: String) -> String? {
        names(for: address)?.first?.name
    }

    private func isStale(_ record: Record) -> Bool {
        Date.now.timeIntervalSince(record.askedAt) > Self.freshness
    }

    /// Asks for one address unless it was asked recently. Safe to call from
    /// `onAppear` on every row: it returns immediately for anything already
    /// known, in flight, or not a hex address.
    func fill(_ address: String) async {
        guard !DemoMode.isActive, ENS.isHexAddress(address) else { return }
        let key = Self.key(for: address)
        guard !asking.contains(key) else { return }
        if let existing = records[key], !isStale(existing) { return }
        asking.insert(key)
        defer { asking.remove(key) }
        let found = await NameResolve.primaryNames(for: address)
        records[key] = Record(names: found.map { Entry(label: $0.label, name: $0.name) },
                              askedAt: .now)
        persist()
    }

    /// Asks for a list, newest interest first, bounded by `perPassBudget`.
    /// Sequential on purpose — these reads share one paced public host, and a
    /// `TaskGroup` here would defeat `WeiNamesSource`'s pacer.
    func fill(_ addresses: [String]) async {
        var spent = 0
        for address in addresses {
            guard spent < Self.perPassBudget else { return }
            let key = Self.key(for: address)
            if let existing = records[key], !isStale(existing) { continue }
            guard ENS.isHexAddress(address) else { continue }
            await fill(address)
            spent += 1
        }
    }

    /// Drops what is known for an address — called when a book entry is
    /// removed, so a re-added address asks again rather than showing a name
    /// resolved in a previous life.
    func forget(_ address: String) {
        records.removeValue(forKey: Self.key(for: address))
        persist()
    }

    func forgetAll() {
        records = [:]
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    #if DEBUG
    /// Everything known, for `-weiNameProbe`.
    var allRecords: [String: Record] { records }
    #endif
}
