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
                // Privacy Pools' cursor and that wallet's pending-status
                // watchlist leave too (prd §162) — same back-fill reason,
                // plus a stale pending entry would alert for a wallet no
                // longer watched.
                PrivacyPoolsBridge.clearState(address: old.address)
                // Railgun's cursor and its evidence mark leave too (prd §268)
                // — same back-fill reason, plus a stale mark would keep the
                // seat lit for a wallet that's gone.
                RailgunBridge.clearState(address: old.address)
                // Gnosis Pay's cursor and its card-account mark leave too
                // (prd §222) — same back-fill reason, plus a stale mark would
                // keep the seat lit for a card whose wallet is gone.
                GnosisPayBridge.clearState(address: old.address)
                // Morpho's activity cursor and risk buckets leave too
                // (2026-07-21) — same back-fill reason, plus a stale
                // "at-risk" bucket would suppress a real alert on re-watch.
                MorphoDeFi.clearState(address: old.address)
                // Uniswap's activity cursor and range buckets leave too
                // (2026-07-30) — same back-fill reason, plus a stale
                // "out-of-range" bucket would suppress a real re-entry alert
                // on re-watch.
                UniswapLiquidity.clearState(address: old.address)
                // Hyperliquid's position snapshot leaves too (2026-07-30) —
                // a stale snapshot would read every live position back as
                // freshly "opened" on re-watch instead of the honest silent
                // reseed.
                HyperliquidDeFi.clearState(address: old.address)
                // Aerodrome keeps no cursor (both its events are reconciling
                // dueAt rows, read fresh every pass) — but its catalog seat's
                // evidence mark leaves with the watch like every sibling's,
                // or the seat stays lit for a wallet that's gone.
                AerodromeDeFi.clearState(address: old.address)
                // ether.fi Cash's spend cursor and risk bucket leave too
                // (2026-07-31) — same back-fill reason, plus a stale "at-risk"
                // bucket would suppress a real alert on re-watch.
                EtherFiCash.clearState(address: old.address)
                // The unstake queue keeps no cursor (its rows are reconciling
                // dueAt, read fresh every pass) — but the discovered-id cache
                // and walk floor leave with the watch, or a re-watch would
                // trust ids it never re-verified.
                EtherFiUnstake.clearState(address: old.address)
                // The EIP-7702 delegation baseline leaves too (2026-07-20) —
                // a re-watch should seed fresh, not compare against a
                // delegate state from a prior, unrelated watch period.
                WalletSafety.clearDelegation(address: old.address)
                // Aave's catalog-seat mark leaves too (2026-07-30) — the
                // risk buckets above already reset themselves, this is the
                // seat's own record.
                WalletDeFi.clearSeatEvidence(address: old.address)
                // The gas-spent running total leaves too (2026-07-20) — a
                // re-watch starts the count at zero, honest about what it can
                // actually know.
                WalletGas.clearTotals(address: old.address)
                // The Safe-detection cache leaves too (2026-07-20) — also
                // the only way to recover from a negative result still
                // inside its TTL.
                SafeBridge.clearCache(address: old.address)
                // Bitcoin's pending-confirmation watchlist leaves too
                // (2026-07-27) — same back-fill reason; a no-op for any
                // non-Bitcoin address, like every sibling clear above.
                BitcoinBridge.clearState(address: old.address)
                // Every clear above is passed the TYPED spelling, while the
                // sweeps key their state on the RESOLVED hex — so a wallet
                // watched as "vitalik.eth" leaves its state behind (review,
                // 2026-07-30). Repeat the round for the resolved form when
                // the two differ; each clear is idempotent and a no-op for a
                // key that isn't there. The seats don't depend on this
                // landing (`WalletSeatEvidence.count(in:)` intersects with
                // the live watch list either way) — but a stale cursor still
                // back-fills the unwatched gap on re-watch, which is what
                // every one of these clears exists to prevent.
                if let hex = self.resolvedForm(of: old.address),
                   hex.lowercased() != old.address.lowercased() {
                    WalletApprovals.clearCursors(address: hex)
                    PeerBridge.clearCursor(address: hex)
                    PrivacyPoolsBridge.clearState(address: hex)
                    RailgunBridge.clearState(address: hex)
                    GnosisPayBridge.clearState(address: hex)
                    MorphoDeFi.clearState(address: hex)
                    UniswapLiquidity.clearState(address: hex)
                    HyperliquidDeFi.clearState(address: hex)
                    AerodromeDeFi.clearState(address: hex)
                    WalletSafety.clearDelegation(address: hex)
                    WalletDeFi.clearSeatEvidence(address: hex)
                    WalletGas.clearTotals(address: hex)
                    SafeBridge.clearCache(address: hex)
                    BitcoinBridge.clearState(address: hex)
                }
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
    ///
    /// Cached under BOTH the watched spelling AND the resolved hex
    /// (2026-07-23) — a wallet watched by ENS name ("vitalik.eth") showed its
    /// real avatar in the roster/chip strip (which draw `WalletFace` from
    /// `entry.address` directly) but fell back to a bare identicon anywhere a
    /// landed `Thing`'s `walletAddress`/`counterpartyAddress` was the lookup
    /// key instead — those always store the resolved hex, never the ENS
    /// spelling, so the single-key cache missed every time (caught on-device:
    /// the "You" face in a transaction's from/to visualization). Same
    /// `avatarURL(for:)` reader either way; this just makes both spellings
    /// answer.
    @MainActor
    func loadAvatars() async {
        for entry in addresses {
            let key = entry.address.lowercased()
            guard avatarURLs[key] == nil else { continue }
            var found = await ENS.avatar(for: entry.address)
            if found == nil, ENS.looksLikeName(entry.label) {
                found = await ENS.avatar(for: entry.label)
            }
            guard let found else { continue }
            avatarURLs[key] = found
            if !ENS.isHexAddress(entry.address),
               let hex = await ENS.resolve(entry.address) {
                avatarURLs[hex.lowercased()] = found
            }
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

    /// The moments behind `combinedValueSamples()` — the WHEN of each point,
    /// so a chart drawn off that line can place things that happened in real
    /// time (a transaction, prd §155) against it. Same series, same rules.
    func combinedSampleDates() -> [Date] { combinedValueSamples().map(\.at) }

    /// The combined move attributed by TOKEN, or one wallet's, or (nil) for all
    /// together — the scoped twin (2026-07-21), so the Wallet feed's "what
    /// moved" whisper can speak in whatever scope the switcher is standing in.
    /// A single-wallet scope needs no alignment across wallets, but goes
    /// through the identical path so the two can never diverge on what counts.
    ///
    /// `since` narrows the window to a recent stretch (the day brief's own
    /// anchor, prd §166) — the start moves forward to the last snapshot at or
    /// before that date, but NEVER earlier than the cross-wallet alignment
    /// point, so a scoped read keeps §77's guarantee that a composition change
    /// can't masquerade as a move. nil (the default) reads the whole line, the
    /// behavior every existing caller already depends on.
    func holdingsDeltas(forAddress scope: String?,
                        since: Date? = nil) -> [(symbol: String, delta: Double)] {
        let watched = scope.map { s in addresses.filter { WalletWatch.sameAddress($0.address, s) } }
            ?? addresses
        let lines = watched
            .map { valueSamples(forAddress: $0.address).filter { $0.holdings != nil } }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty,
              let aligned = lines.compactMap({ $0.first?.at }).max(),
              let end = lines.compactMap({ $0.last?.at }).max()
        else { return [] }
        // The latest snapshot at or before `since`, across every line — the
        // day-scoped anchor, floored at the alignment point.
        let windowed = since.flatMap { cutoff in
            lines.compactMap { $0.last(where: { $0.at <= cutoff })?.at }.max()
        }
        let start = max(aligned, windowed ?? aligned)
        guard end > start else { return [] }
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

    /// How long the line keeps FULL 4-hourly resolution. Older than this and a
    /// day's worth of points collapses to one — see `thinned`.
    static let fullResolutionDays = 30
    /// The hard ceiling, a backstop rather than the working limit: with the
    /// recent month at 4h (about 180 points) and everything before it at one a
    /// day, this holds well over two years.
    static let sampleCap = 1000

    /// Ages the history instead of truncating it.
    ///
    /// This used to be `if samples.count > 240 { removeFirst(…) }`, which with
    /// the 4-hour throttle is a hard **40-day** ceiling — so §155's "watched"
    /// window chip quietly meant "the last 40 days" for anyone who had been
    /// watching longer, and the beginning of their history was dropped with no
    /// sign it had ever existed. A person's first year of holding something is
    /// exactly the span worth keeping.
    ///
    /// Recent history keeps every point, because that is what the sparkline and
    /// the 7d/30d windows actually draw. Beyond the window each calendar day
    /// collapses to its LAST sample — closing value, the convention every price
    /// chart uses, and the sample most likely to carry `holdings` (the newest
    /// pass wrote it). Only then does the cap apply, and reaching it now means
    /// years rather than weeks.
    static func thinned(_ samples: [ValueSample]) -> [ValueSample] {
        guard let newest = samples.last?.at else { return samples }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -fullResolutionDays, to: newest) ?? newest
        var kept: [ValueSample] = []
        var lastOldDay: Date?
        for sample in samples {
            guard sample.at < cutoff else { kept.append(sample); continue }
            let day = cal.startOfDay(for: sample.at)
            // Same day as the previous old sample → replace it, so the one that
            // survives is the day's last.
            if lastOldDay == day { kept.removeLast() }
            kept.append(sample)
            lastOldDay = day
        }
        if kept.count > sampleCap { kept.removeFirst(kept.count - sampleCap) }
        return kept
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
        samples = Self.thinned(samples)
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
        return displayName(for: match)
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
        // The book keys on identity, not spelling (prd §212) — a name and the
        // address it stands for are one entry, and this is the moment the two
        // forms meet. Folds any row already standing under the name.
        AddressBook.shared.noteResolution(watched, resolved: resolved)
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

    // MARK: - The watch cap (prd §170, 2026-07-21)

    /// How many wallets may be WATCHED at once. Watching is the expensive tier
    /// — a Zerion transactions call plus a share of the Portfolio holdings read
    /// per wallet on every foreground, forever, against a key shipped in the
    /// binary and shared by everyone. Naming an address stays unlimited
    /// (`AddressBook`), which is what makes this cap livable: the person
    /// tracking twenty addresses names twenty and watches their five.
    ///
    /// Five is also where the room's own design already tops out — the
    /// switcher chips crowd past six, and the combined line only starts once
    /// EVERY watched wallet has an aligned sample, so each extra wallet is one
    /// more thing that can stall the crown feature.
    static let watchLimit = 5

    /// Room for another watch? False when the list is full — the doors read
    /// this to STATE the limit up front rather than letting a person fill in a
    /// field that will refuse them (the §83 dead-control rule).
    var canWatchMore: Bool { addresses.count < Self.watchLimit }

    /// Why an add didn't take, so a door can say the true thing.
    enum AddOutcome: Equatable {
        case added
        case alreadyWatching
        case limitReached
        case invalid
    }

    /// Adds a pasted address. Light validation only — an address is public
    /// data and a bad one simply never produces things.
    ///
    /// The ONE choke point for the cap: every door (paste, ENS, `.sol`,
    /// WalletConnect, a Farcaster profile, the address card's toggle, the
    /// probe hooks) already funnels through here, so the limit can't be
    /// side-stepped by adding a new entry point later.
    ///
    /// GRANDFATHERED, never evicted: an install already past the limit keeps
    /// every wallet it has and simply can't add more. Silently dropping
    /// someone's sixth wallet would delete their data to enforce our cost
    /// policy.
    @discardableResult
    func add(_ raw: String, label: String = "") -> Bool {
        outcome(ofAdding: raw, label: label) == .added
    }

    /// The same add, reporting WHY when it refuses — for doors that word the
    /// refusal (`add` keeps its Bool for the many call sites that only branch).
    @discardableResult
    func outcome(ofAdding raw: String, label: String = "") -> AddOutcome {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addr.count >= 6 else { return .invalid }
        // Two spellings, one wallet (2026-07-25): "vitalik.eth" and the hex it
        // resolves to are the same watch, so BOTH sides compare in their
        // resolved form. Without this, the field (which resolves before
        // adding) and a door that watches the raw name (a probe hook, a
        // starred book row) could each land the same wallet once.
        let key = Self.dedupeKey(resolvedForm(of: addr) ?? addr)
        guard !addresses.contains(where: {
            Self.dedupeKey(resolvedForm(of: $0.address) ?? $0.address) == key
        }) else { return .alreadyWatching }
        guard canWatchMore else { return .limitReached }
        addresses.append(WatchedAddress(label: label, address: addr))
        // A watched wallet is ALWAYS a book entry too (2026-07-24, user: "if
        // you watch one, it should automatically be in your address book").
        // This used to skip an unnamed watch (a raw hex paste with no ENS
        // name) entirely — reasoned at the time as "the person names it when
        // they mean to", but the actual result was a watched wallet that
        // silently didn't show up in its own book, which read as a bug, not
        // a choice. A blank label gets the same short-address fallback
        // `AddressBook.addBulk` already uses for a bare pasted address, so
        // every watched wallet is findable in one list from the moment it's
        // watched — renaming it later is one tap either way.
        let bookName = label.trimmingCharacters(in: .whitespacesAndNewlines)
        AddressBook.shared.setName(bookName.isEmpty ? Self.shortAddress(addr) : bookName,
                                   for: addr, kind: .wallet)
        return .added
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
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        addresses[i].label = trimmed
        // Through to the book (prd §169): renaming a watched wallet renames
        // the ADDRESS, so the name outlives the watch and every surface — feed
        // tags, transfer titles, the switcher — keeps reading one word.
        // A blank rename falls back to the short-address name rather than
        // passing "" through — `setName("")` REMOVES the entry, and a watched
        // wallet is always a book entry (`add`'s own invariant); the alert's
        // "a blank name shows the address instead" promise depends on this.
        let addr = addresses[i].address
        AddressBook.shared.setName(trimmed.isEmpty ? Self.shortAddress(addr) : trimmed,
                                   for: addr, kind: .wallet)
    }

    /// The name for a watched wallet, book first. The stored `label` remains
    /// the fallback so installs that predate the book (and probe hooks that
    /// set a label directly) still read correctly.
    func displayName(for entry: WatchedAddress) -> String {
        AddressBook.shared.name(for: entry.address)
            ?? (entry.label.isEmpty ? entry.short : entry.label)
    }

    /// The name for the watched wallet a LANDED thing belongs to (2026-07-31,
    /// prd §241's follow-up) — for a surface holding a thing's stamped address
    /// that needs to say whose wallet it is.
    ///
    /// Things carry the RESOLVED hex while the roster holds the watched
    /// spelling, so this goes through `scopeMatches` rather than comparing
    /// raw strings — the exact mismatch that once emptied an ENS-watched
    /// wallet's scoped feed. nil when the address belongs to no watched
    /// wallet, so a caller states nothing rather than guessing.
    func displayName(forStored stored: String?) -> String? {
        guard let stored, !stored.isEmpty else { return nil }
        guard let entry = addresses.first(where: { scopeMatches(stored, scope: $0.address) })
        else { return nil }
        return displayName(for: entry)
    }

    /// The name for a wallet named in its WATCHED spelling — what
    /// `WalletWarning.address` carries. Same nil-rather-than-guess contract as
    /// `displayName(forStored:)`; the two exist separately because the two
    /// callers genuinely hold different forms of an address.
    func displayName(forWatched watched: String?) -> String? {
        guard let watched, !watched.isEmpty else { return nil }
        guard let entry = addresses.first(where: { WalletWatch.sameAddress($0.address, watched) })
        else { return nil }
        return displayName(for: entry)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
