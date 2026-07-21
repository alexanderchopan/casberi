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
                // The Peer fill cursor leaves with the watch for the same
                // reason (prd §113).
                PeerBridge.clearCursor(address: old.address)
                // The EIP-7702 delegation baseline leaves too (2026-07-20) —
                // a re-watch should seed fresh, not compare against a
                // delegate state from a prior, unrelated watch period.
                WalletSafety.clearDelegation(address: old.address)
                // The gas-spent running total leaves too (2026-07-20) — a
                // re-watch starts the count at zero, honest about what it can
                // actually know.
                WalletGas.clearTotals(address: old.address)
                // The Safe-detection cache leaves too (2026-07-20) — also
                // the only way to recover from a negative result still
                // inside its TTL.
                SafeBridge.clearCache(address: old.address)
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
    /// points is noise, not history. Main-actor: it fires source moments
    /// (SourceMoments), and its only caller (WalletIngest) already is.
    @MainActor
    func recordSample(address: String, totalUSD: Double, holdings: [String: Double] = [:]) {
        // A single watched wallet's own value hitting a new high is its
        // moment (delight 2026-07-15; the combined high covers the multi-
        // wallet case — WalletIngest). The mark is checked every fetch, not
        // just every 4h, so a fast climb isn't missed by the sample throttle;
        // it fires only with exactly one wallet watched, so several wallets
        // never stack toasts. First value seeds the mark silently.
        if addresses.count == 1,
           SourceMoments.shared.notedNewHigh(scope: "wallet.\(address.lowercased())", value: totalUSD) {
            SourceMoments.shared.fire(String(localized: "Your wallet hit a new high 📈"), source: "Wallet")
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
    /// is watched. Matched by exact string OR through the resolution cache —
    /// an ENS/SNS-named watch lands its things stamped with the RESOLVED hex
    /// (WalletIngest resolves before reading), so a raw compare missed every
    /// one of them. The old behavior ("no label then, never a wrong one") was
    /// an accepted degradation for a label; the same mismatch silently
    /// EMPTIED the scoped feed, which forced the real fix (2026-07-20).
    func label(forAddress address: String?) -> String? {
        guard let address, addresses.count > 1,
              let match = addresses.first(where: {
                  WalletWatch.sameAddress($0.address, address)
                      || resolvedForm(of: $0.address).map { WalletWatch.sameAddress($0, address) } == true
              })
        else { return nil }
        return match.label.isEmpty ? match.short : match.label
    }

    // MARK: - Resolution cache (2026-07-20)

    /// watched spelling → resolved on-chain address ("vitalik.eth" →
    /// "0xd8dA…6045"), filled as `WalletIngest.resolvedAddresses` runs — so
    /// by the time any landed thing exists to filter, its wallet's resolution
    /// has been seen at least once. Persisted: a fresh launch filters
    /// correctly before its first network read.
    @ObservationIgnored
    private var resolutions: [String: String] =
        UserDefaults.standard.dictionary(forKey: "wallet.resolutions") as? [String: String] ?? [:]

    func noteResolution(_ watched: String, resolved: String) {
        guard watched != resolved, resolutions[watched] != resolved else { return }
        resolutions[watched] = resolved
        UserDefaults.standard.set(resolutions, forKey: "wallet.resolutions")
    }

    func resolvedForm(of watched: String) -> String? {
        resolutions[watched]
    }

    /// Does a landed thing's stamped address belong to the given scope?
    /// Things carry the RESOLVED hex; a scope is the WATCHED spelling — so
    /// this matches raw-vs-raw first (a hex-watched wallet), then through
    /// the cache (an ENS/SNS-watched one). The bug this fixes: scoping the
    /// feed to "vitalik.eth" compared the name against stamped hex, matched
    /// nothing, and showed "Nothing from Wallet yet" over a corpus full of
    /// that wallet's own transactions (caught on camera, 2026-07-20).
    func scopeMatches(_ stored: String?, scope: String) -> Bool {
        guard let stored else { return false }
        if WalletWatch.sameAddress(stored, scope) { return true }
        if let hex = resolvedForm(of: scope), WalletWatch.sameAddress(stored, hex) { return true }
        return false
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

    private func persist() {
        if let data = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
