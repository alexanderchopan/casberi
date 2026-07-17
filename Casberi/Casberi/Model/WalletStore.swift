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
        /// A pinned wallet's NFT strip rides Home by default (ruling
        /// 2026-07-14); long-press → "Remove from Home" sets this, per
        /// wallet, and re-pinning the wallet resets it (fresh pin, fresh
        /// default).
        var nftStripHidden: Bool = false

        enum CodingKeys: String, CodingKey {
            case id, label, address, pinnedToHome, nftStripHidden
        }

        init(id: UUID = UUID(), label: String, address: String, pinnedToHome: Bool = false) {
            self.id = id
            self.label = label
            self.address = address
            self.pinnedToHome = pinnedToHome
        }

        /// Custom decode: older persisted data has no `pinnedToHome` /
        /// `nftStripHidden` keys — they default rather than failing to decode.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            label = try c.decode(String.self, forKey: .label)
            address = try c.decode(String.self, forKey: .address)
            pinnedToHome = try c.decodeIfPresent(Bool.self, forKey: .pinnedToHome) ?? false
            nftStripHidden = try c.decodeIfPresent(Bool.self, forKey: .nftStripHidden) ?? false
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
                // The high-water mark leaves with the watch too — else a
                // re-watch would judge its "new high" against a peak from a
                // prior watch period whose history was already wiped (the same
                // "re-watching starts honest, at zero" rule the history obeys).
                UserDefaults.standard.removeObject(forKey: "wallet.high.\(old.address.lowercased())")
                // The approval block cursors leave too (prd §84) — a stale
                // cursor would back-fill the unwatched gap into the feed on
                // re-watch, instead of the silent fresh-baseline seed.
                WalletApprovals.clearCursors(address: old.address)
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
        /// The wallet's top positions by USD at this moment (symbol → USD),
        /// snapshotted so the combined sheet can attribute a move to a token
        /// ("mostly ETH", 2026-07-15). Optional — samples from before this field
        /// decode with nil (synthesized Codable uses decodeIfPresent for
        /// optionals), so attribution only draws once enough new samples carry it.
        var holdings: [String: Double]? = nil
    }

    private static func historyKey(_ address: String) -> String {
        "wallet.history.\(address.lowercased())"
    }

    // MARK: - Faces (ENS avatars, 2026-07-15)

    /// Resolved ENS avatar URLs, keyed by lowercased hex address — read by
    /// WalletFace, populated by loadAvatars(). Observed, so a face swaps from
    /// its identicon to the real avatar the moment resolution lands. In-memory
    /// only: avatars are cheap to re-resolve and can change, so nothing
    /// persists (the identicon is always a correct answer meanwhile).
    private(set) var avatarURLs: [String: String] = [:]

    /// The avatar for a hex address, if one resolved — nil means "draw the
    /// identicon", never a broken image.
    func avatarURL(for address: String) -> String? {
        avatarURLs[address.lowercased()]
    }

    /// Resolves each watched address's ENS avatar once, filling `avatarURLs`.
    /// Tries the hex first (reverse resolve), then the label when it's an ENS
    /// name (a name resolve carries the avatar even when reverse doesn't).
    /// Skips any address already resolved this launch — ENS.avatar caches
    /// misses too, so a faceless wallet costs one lookup, not one per visit.
    @MainActor
    func loadAvatars() async {
        for entry in addresses {
            let key = entry.address.lowercased()
            guard avatarURLs[key] == nil else { continue }
            var found = await ENS.avatar(for: entry.address)
            if found == nil, ENS.looksLikeName(entry.label) {
                found = await ENS.avatar(for: entry.label)
            }
            if let found { avatarURLs[key] = found }
        }
    }

    func valueSamples(forAddress address: String) -> [ValueSample] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey(address)),
              let samples = try? JSONDecoder().decode([ValueSample].self, from: data)
        else { return [] }
        return samples
    }

    /// Every watched wallet's value line merged into ONE portfolio net-worth
    /// series (2026-07-15) — the combined "bundle" line. At each sampled moment
    /// it sums the most recent known value of every wallet (forward-filled from
    /// that wallet's last sample at or before the moment). Forward-only and
    /// honest, exactly like the per-wallet samples it's built from — nothing is
    /// back-filled.
    ///
    /// The series starts only once EVERY watched wallet has a sample (the
    /// latest of the wallets' first-sample times). Before that, a just-added
    /// wallet would contribute nothing and the total would jump the moment it
    /// first prices — a real +millions-% artifact when wallets are watched at
    /// different times (paid for 2026-07-15). Starting at the aligned point
    /// means the line only ever shows the true combined net worth, never a
    /// composition change masquerading as a gain. Empty until at least two such
    /// aligned points exist, so a single-point line never draws.
    func combinedValueSamples() -> [ValueSample] {
        let lines = addresses
            .map { valueSamples(forAddress: $0.address) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, let start = lines.compactMap({ $0.first?.at }).max()
        else { return [] }
        let moments = Set(lines.flatMap { $0.map(\.at) })
            .filter { $0 >= start }
            .sorted()
        guard moments.count >= 2 else { return [] }
        return moments.map { moment in
            let total = lines.reduce(0.0) { sum, samples in
                sum + (samples.last(where: { $0.at <= moment })?.usd ?? 0)
            }
            return ValueSample(at: moment, usd: total)
        }
    }

    /// The combined move attributed by TOKEN (2026-07-15) — each symbol's USD
    /// change from the first aligned moment to the last, summed across wallets,
    /// biggest swing first. The combined sheet's "What moved" read: "ETH +$310,
    /// USDC −$4". Forward-only and honest like every sample it's built from —
    /// only samples that carry a per-token snapshot count, so it stays empty
    /// until enough of those exist, and it aligns on the wallets' first snapshot
    /// so a composition change can't masquerade as a move (§77's rule, applied
    /// per token). Deltas under $1 drop as noise.
    func combinedHoldingsDeltas() -> [(symbol: String, delta: Double)] {
        let lines = addresses
            .map { valueSamples(forAddress: $0.address).filter { $0.holdings != nil } }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty,
              let start = lines.compactMap({ $0.first?.at }).max(),
              let end = lines.compactMap({ $0.last?.at }).max(),
              end > start
        else { return [] }
        func merged(at moment: Date) -> [String: Double] {
            var total: [String: Double] = [:]
            for samples in lines {
                guard let s = samples.last(where: { $0.at <= moment }),
                      let h = s.holdings else { continue }
                for (sym, usd) in h { total[sym, default: 0] += usd }
            }
            return total
        }
        let firstMap = merged(at: start)
        let lastMap = merged(at: end)
        let symbols = Set(firstMap.keys).union(lastMap.keys)
        return symbols
            .map { (symbol: $0, delta: (lastMap[$0] ?? 0) - (firstMap[$0] ?? 0)) }
            .filter { abs($0.delta) >= 1 }
            .sorted { abs($0.delta) > abs($1.delta) }
    }

    /// Appends a sample unless one landed in the last 4 hours — holdings
    /// refresh every foreground, and a line of near-identical minutes-apart
    /// points is noise, not history. Main-actor: it fires wallet moments
    /// (WalletMoments), and its only caller (WalletIngest) already is.
    @MainActor
    func recordSample(address: String, totalUSD: Double, holdings: [String: Double] = [:]) {
        // A single watched wallet's own value hitting a new high is its
        // moment (delight 2026-07-15; the combined high covers the multi-
        // wallet case — WalletIngest). The mark is checked every fetch, not
        // just every 4h, so a fast climb isn't missed by the sample throttle;
        // it fires only with exactly one wallet watched, so several wallets
        // never stack toasts. First value seeds the mark silently.
        if addresses.count == 1,
           WalletMoments.shared.notedNewHigh(scope: address.lowercased(), value: totalUSD) {
            WalletMoments.shared.fire(String(localized: "Your wallet hit a new high 📈"))
        }
        var samples = valueSamples(forAddress: address)
        if let last = samples.last, Date.now.timeIntervalSince(last.at) < 4 * 3600 { return }
        samples.append(ValueSample(at: .now, usd: totalUSD,
                                   holdings: holdings.isEmpty ? nil : holdings))
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

    /// The form two watched addresses are COMPARED in — never the form one is
    /// stored in.
    ///
    /// Normalises per family, and the asymmetry is load-bearing (2026-07-16).
    /// An EVM address is hex whose case is an EIP-55 checksum, not identity:
    /// the same wallet arrives cased differently from different sources and
    /// must collapse to one row. A Solana address is base58, where case IS
    /// identity — lowercasing it can fold two genuinely different wallets
    /// together and silently discard the second. So lowercase only what is
    /// provably hex, and leave everything else exactly as it came.
    private static func dedupeKey(_ address: String) -> String {
        ENS.isHexAddress(address) ? address.lowercased() : address
    }

    /// Adds a pasted address. Light validation only — an address is public
    /// data and a bad one simply never produces things.
    @discardableResult
    func add(_ raw: String, label: String = "") -> Bool {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.dedupeKey(addr)
        guard addr.count >= 6,
              !addresses.contains(where: { Self.dedupeKey($0.address) == key })
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
    /// Pinning ON resets the NFT strip to its default (a fresh pin brings the
    /// full presence back; removal was scoped to the previous pin).
    func togglePin(_ id: WatchedAddress.ID) {
        guard let i = addresses.firstIndex(where: { $0.id == id }) else { return }
        addresses[i].pinnedToHome.toggle()
        if addresses[i].pinnedToHome { addresses[i].nftStripHidden = false }
    }

    /// Renames a watched wallet — the missing half of the label story: an
    /// ENS add sets the label automatically, but a raw-hex watch had no way
    /// to ever become "Cold" or "Trading" (a real gap in a multi-wallet
    /// world, where every surface — feed tags, treemap eyebrows, self-
    /// transfer titles — leans on this label the moment more than one
    /// wallet is watched). Empty clears back to the address-only display.
    func rename(_ id: WatchedAddress.ID, to label: String) {
        guard let i = addresses.firstIndex(where: { $0.id == id }) else { return }
        addresses[i].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shows/hides a pinned wallet's NFT strip on Home — the Wallet screen's
    /// own control (the reachable verb: the board's drag driver pre-empts
    /// long-press menus there), plus the strip's long-press remove for
    /// whenever that arbitration is fixed.
    func setNFTStrip(hidden: Bool, address: String) {
        guard let i = addresses.firstIndex(where: {
            $0.address.lowercased() == address.lowercased()
        }) else { return }
        addresses[i].nftStripHidden = hidden
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
