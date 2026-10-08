import Foundation
import Security
import SwiftData

/// The corpus's convergence onto a renamed seat's current name (prd §647,
/// 2026-09-08) — `Corpus.renamedSources` applied to the rows and to the bridge
/// record, at EVERY launch.
///
/// ## Why this is not a migration
///
/// It was one. §629's rename shipped as `RootShell`'s migration v9: one pass
/// over the corpus, gated on the `migrations.version` stamp in `UserDefaults`,
/// i.e. once per install, ever. That is the right shape for a fact about data
/// that is already on the device and the WRONG shape for this store, which
/// mirrors to CloudKit — a row landed on another device, or sitting unmerged in
/// the iCloud zone, arrives whenever it arrives, and every one that lands after
/// the stamp is written keeps the old name for good. A second device still on
/// an older build re-lands them indefinitely. The migration did not merely miss
/// some rows; it could not have caught them, because it answered a question
/// about data that had not arrived yet.
///
/// It reached a device exactly as its own comment predicted it would if it were
/// skipped — *"there is a random tile in the nav bar. looks like ethers gegota
/// and should be in the wallet room! icon missing too"*: no seat, so no
/// category, so the chip escaped `CategoryFold` and drew as a bare circle
/// beside a row of category words, wearing `BridgeGlyph`'s `app` fallback.
///
/// ## Why RESOLUTION being tolerant is not enough on its own
///
/// `Corpus.canonicalSource` (read by `BridgeCatalog.seatNameBySource`,
/// `BridgeIcon`, `BridgeGlyph` and `DS.brandHue`) already fixes what a stale row
/// LOOKS like, on the frame it arrives, with nothing having swept anything —
/// and that half is what makes a mid-session CloudKit merge render correctly.
/// But a ROOM is entered by `Thing.source`, and the surfaces that decide what a
/// room draws compare that string to a seat's own identity (`FeedScreen`'s room
/// heads: `source == FramesIdentity.source`; the venue switcher's scopes). Every
/// one of those would have to learn the alias independently, which is the
/// cross-file promise `Thing.swift`'s own corollary 4 was written about. So the
/// strings converge instead, and only display is tolerant.
///
/// ## The bound
///
/// One `fetchCount` per entry in `Corpus.renamedSources` (three today), on an
/// indexed `source ==` predicate, behind the first paint. Rows are only
/// materialised when a count comes back non-zero, which in the steady state is
/// never. NOT MEASURED on a device — the claim here is structural (two counted
/// reads whose fetch is skipped when they answer zero), and that is the only
/// claim it is entitled to make until a launch is sampled.
enum SourceRename {
    /// Rewrite every row still carrying a renamed seat's old `source` — and,
    /// where the rename moved the ref namespace too, its `sourceRef` prefix —
    /// and point the bridge record at the current name. Returns how many rows
    /// moved: zero on every launch but the one that finds stragglers.
    ///
    /// Runs BEFORE `SyncReconcile.dedupeBySourceRef` at the call site, so an
    /// old-named row and its new-named twin (both carrying the same
    /// `sourceRef`) collapse in the same pass rather than the next launch.
    ///
    /// ## `source ==` is a complete key for the REF too (prd §650)
    ///
    /// The fetch keys on the source alone and rewrites the ref off the rows it
    /// gets back, which is only sound if no build ever wrote the NEW source
    /// beside the OLD prefix. For the one entry that has a prefix it is a
    /// checked fact, not an assumption: a2618a2 (2026-07-13) moved
    /// `Thing.source` and the ref prefix in the same commit, so the two have
    /// never disagreed in a row this app wrote. A future rename that lets them
    /// drift apart must key on the ref instead, and the entry that does it owes
    /// its own note here.
    ///
    /// The alternative — a second fetch predicated on the ref prefix — is
    /// deliberately NOT taken. `sourceRef` is optional, and combining `?? ""`
    /// with `.starts(with:)` inside a `#Predicate` has no precedent in this
    /// tree; migration v6 refused to be the first to find out whether that
    /// combination traps, and a sweep that runs on EVERY launch is a worse
    /// place to find out than a one-shot was.
    @MainActor
    @discardableResult
    static func sweep(context: ModelContext) -> Int {
        var moved = 0
        for (old, rename) in Corpus.renamedSources {
            let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == old })
            // Counted first: the whole point of running this every launch is
            // that the launch it finds nothing must cost a count and not a
            // fetch.
            guard let count = try? context.fetchCount(descriptor), count > 0 else { continue }
            let rows = (try? context.fetch(descriptor)) ?? []
            for thing in rows where thing.isLive {
                thing.source = rename.current
                // The ref namespace, when the rename took it along. Converging
                // the source alone would leave the row half-way: it would find
                // its seat, its room and its mark, and stay invisible to every
                // consumer that matches the ref EXACTLY — for the one entry
                // that has a prefix, `TokenWatch.add`'s already-watching guard
                // (so the same coin lands twice), the search list's
                // already-watched filter, and `TokenQuickRoute.watchedThing`
                // (so a held token you watch reads as merely held).
                if let prefix = rename.refPrefix,
                   let ref = thing.sourceRef, ref.hasPrefix(prefix.old) {
                    thing.sourceRef = prefix.current + String(ref.dropFirst(prefix.old.count))
                }
                moved += 1
            }
        }
        // SAVED HERE, not by a caller. The one-shot this replaces sat inside
        // the migration block and rode ITS `saveHonestly()`; this runs on every
        // launch, where that block does not run at all, so a sweep that left
        // the save to somebody else would rewrite the rows in memory and lose
        // them — the same correct-looking screen for one session, wrong again
        // on the next launch.
        if moved > 0 { _ = context.saveHonestly() }
        return moved
    }

    /// The seat record's own name. Separate from the rows because it is a
    /// different store (`BridgeStore`'s JSON, not SwiftData) and free to run —
    /// `BridgeStore.rename` returns immediately when the name already matches,
    /// so this costs a walk of ~25 in-memory bridges and no write.
    ///
    /// Keyed by SEAT ID, not by the old name, so this is correct for a seat
    /// renamed twice and for one whose record was written by a build that never
    /// knew the old name at all.
    ///
    /// ## An id CAN change, and one did — the bound on what this fixes (§650)
    ///
    /// §647 justified the id key by saying an id never changes. That is false:
    /// a2618a2 re-keyed the token-watch seat `"dexscreener"` → `"tokens"` along
    /// with its name. So a record written before 2026-07-13 is not merely
    /// mis-named, it is UNREACHABLE from here — no entry below can find it, and
    /// adding one would not help, because this renames a record it locates by
    /// id and that id is the thing that moved.
    ///
    /// Left unfixed ON PURPOSE, with the consequence stated rather than
    /// implied. `AppsScreen` joins a stored bridge to its offer BY NAME
    /// (`$0.name == offer.name`), so such a record leaves Tokens reading
    /// disconnected while its own phantom is still inside `connectedCount`.
    /// Three things make it a different problem from the corpus one, not a
    /// smaller instance of it: `BridgeStore` is a LOCAL JSON file and does not
    /// mirror, so §647's whole argument — that a one-shot cannot be complete
    /// because rows keep arriving — does not apply to it and a one-shot WOULD
    /// be complete here; the repair is a RE-KEY, which `BridgeStore` has no
    /// operation for (renaming the record alone would leave a seat that looks
    /// connected and whose Disconnect removes nothing, i.e. trade a wrong
    /// label for a §83 dead control); and it can only exist on a device that
    /// connected the seat in the six days between the first TestFlight upload
    /// (2026-07-07) and the rename. Worth doing; not worth doing as a silent
    /// rider on a ruling about the corpus.
    @MainActor
    static func sweepSeats(_ store: BridgeStore) {
        for (id, name) in seatNames { store.rename(id, to: name) }
        // EVERY record under a renamed source takes its current name, and
        // twins merge (prd §1147, user: "in Settings under apps / Testnets…
        // both are called Frames Devnet"): Frames Devnet became Hegotá Frames
        // with no `seatNames` entry, so its records kept the old name, and
        // two of them drew as two rows in Settings › Apps.
        store.convergeNames(Corpus.canonicalSource)
        // Health records filed under a seat id move to the catalog name every
        // reader asks for (prd §1163). The four import riders' records are
        // dropped, not moved: they were stamped by calls that carry no key
        // (a public page, an avatar CDN, an expiring export link), so moving
        // them would say a working sign-in needs reconnecting. A live door's
        // real refusal under the same id re-stamps on its next read.
        BridgeHealth.adoptCatalogNames(healthSeatNames)
        ["instagram", "tiktok", "x", "snapchat"].forEach(BridgeHealth.forget)
    }

    /// Seat id → catalog name for every bridge `NetworkReach` spelled by id
    /// before prd §1163. Closed: the registry's audit now refuses an id, so
    /// nothing new is ever filed under one.
    private static let healthSeatNames: [String: String] = [
        "appstoreconnect": "App Store Connect", "aws": "AWS",
        "binance": "Binance", "cardpointers": "CardPointers",
        "cloudflare": "Cloudflare", "dodopayments": "Dodo Payments",
        "duolingo": "Duolingo", "ethvalidators": "ETH Validators",
        "geminiExchange": "Gemini Exchange", "l2beat": "L2BEAT",
        "lightning": "Lightning", "pagerduty": "PagerDuty", "polar": "Polar",
        "posthog": "PostHog", "pypi": "PyPI", "sentry": "Sentry",
        "slack": "Slack", "splits": "Splits", "spotify": "Spotify",
        "stripe": "Stripe", "vercel": "Vercel", "walletbeat": "Walletbeat",
        "wise": "Wise",
    ]

    /// Seat id → the name that seat answers to now. Only seats that have been
    /// renamed need an entry; every other bridge record was written under its
    /// current name and has nothing to correct.
    private static let seatNames: [String: String] = [
        // Tokens became Markets (2026-09-29); the id stayed "tokens".
        "tokens": TokenWatch.source,
    ]

    /// Stocktwits' WATCHED TICKERS converge onto Markets (2026-09-29), at
    /// EVERY launch, for `sweepVoice`'s reason. The watches move — a row keyed
    /// `stocktwits:sym:` — and keep that ref, the stock namespace `StockWatch`
    /// still writes. The traders' takes are DELETED (user: drop them): a take
    /// is a mirror of a ticker you watch, and §286 already ruled that such a
    /// mirror goes when its follow stops explaining it. Left under the retired
    /// source they would also make this count non-zero forever, so every
    /// launch would pay a fetch.
    ///
    /// NOT `Corpus.renamedSources`: that table moves every row of a source,
    /// and here half of them must not follow.
    @MainActor
    @discardableResult
    static func sweepStockWatches(context: ModelContext, store: BridgeStore) -> Int {
        // The seat records first, and on EVERY launch: `BridgeStore` is local
        // and does not mirror, so a device whose rows another device already
        // moved finds nothing below to sweep and would otherwise keep a
        // phantom Stocktwits seat and never register Markets. Both calls are
        // in-memory and return at once when there is nothing to change.
        if store.bridges.contains(where: { $0.id == "stocktwits" }) {
            store.remove("stocktwits")
            TokenWatch.registerBridge(store: store, context: context)
        }
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Stocktwits" })
        guard let count = try? context.fetchCount(descriptor), count > 0 else { return 0 }
        var moved = 0
        var dropped: [Thing] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            if (thing.sourceRef ?? "").hasPrefix(StockWatch.refPrefix) {
                thing.source = TokenWatch.source
                moved += 1
            } else {
                dropped.append(thing)
            }
        }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { context.delete(thing) }
        if moved > 0 || !dropped.isEmpty { _ = context.saveHonestly() }
        // The watches it held keep Markets connected.
        if moved > 0 { TokenWatch.registerBridge(store: store, context: context) }
        return moved
    }

    /// Voice notes converge onto `You` (prd §972), at EVERY launch.
    ///
    /// A voice note's source was "Voice" from 2026-07-06 — a source with no
    /// seat, filed under Notes by hand, which drew a "Voice" room in the tray
    /// and split the kind in two once the note sheet began keeping voice notes
    /// under `You`. The name is retired: every voice note is a note of yours,
    /// in the Notes room, with the kept-note anatomy.
    ///
    /// NOT `Corpus.renamedSources`, whose values must be live offers
    /// (`source-alias-audit.py` check A) — `You` is no seat, and bending that
    /// table would weaken the check that caught a real stranded seat. The
    /// SHAPE is the same one for the same reason: rows from another device
    /// still on an older build, or unmerged in the iCloud zone, land after any
    /// one-shot has run. One counted read on an indexed `source ==` predicate,
    /// and a fetch only when it answers non-zero — which in the steady state
    /// is never.
    @MainActor
    @discardableResult
    static func sweepVoice(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Voice" })
        guard let count = try? context.fetchCount(descriptor), count > 0 else { return 0 }
        var moved = 0
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            thing.source = NoteSheetSource.keptSource
            moved += 1
        }
        // Saved here for the reason `sweep` saves its own: this runs on every
        // launch, where the migration block that used to carry saves does not.
        if moved > 0 { _ = context.saveHonestly() }
        return moved
    }

    // MARK: - Seats that were deleted (prd §1038)

    /// The seats the 2026-10-01 ruling deleted — Altana, Reddit and three
    /// devnets (user: "devnets, lets get rid of these: altana, hegota utxo,
    /// vibenet, hegota privacy", then "may as well get rid of reddit") — and
    /// the two devnets' earlier names (§629, §685), so a row landed before a
    /// rename goes with the rest. Every one is also in `Corpus.retiredSources`,
    /// which keeps a row arriving mid-session from earning a chip before the
    /// next launch sweeps it; `category-fold-selftest.sh` holds the two lists
    /// together.
    ///
    /// Deals, Shopify and Cursor joined them the same day (prd §1049): the two
    /// shopping seats followed someone else's catalogue and nobody would use
    /// them, and Cursor went with them. Nostr joined them 2026-10-05 (user:
    /// "remove nostr"); Lightning keeps the relay client it reads through.
    /// Farcaster joined them the same day (prd §1110, user: "remove
    /// farcaster"): the seat, its casts, channels, likes and signer grants.
    static let droppedSources: Set<String> = [
        "Altana", "Base Vibenet", "Hegotá UTXO", "Hegotá Privacy", "Reddit",
        "Ethrex Hegot\u{00e1}", "Ethrex Privacy", "Hegota Devnet", "Privacy Devnet",
        "Deals", "Shopify", "Cursor", "Nostr", "Farcaster",
        // 1Claw's grants (retired §638): their sheet went with prd §1187.
        "1Claw",
    ]

    /// The address-book network tags those seats wrote (`AddressBook.Network`
    /// held all four until the same day).
    private static let droppedNetworks = ["vibenet", "hegota", "altana", "privacydevnet"]

    /// Every `UserDefaults` key those seats wrote begins with one of these —
    /// their watch lists, live-state caches, signer addresses, the Privacy
    /// devnet's sampled value history, Reddit's follows; Deals' source
    /// toggles (`deals.sources.v1`), Shopify's store list
    /// (`shopify.stores.v1`) and the throttle stamp of Cursor's pull-request
    /// pass (`heal.due.cursor.pullRequests`); Nostr's watched accounts,
    /// hashtags and heal stamp (`nostr.accounts`, `nostr.hashtags`,
    /// `nostr.lastHeal`); Farcaster's accounts, channels, heal stamp,
    /// follower ledgers and signer cursors (`farcaster.`).
    private static let droppedDefaultsPrefixes = [
        "altana.", "vibenet.", "hegota.", "privacydevnet.",
        "room.value.history.privacyDevnet", "feed.reddit",
        "deals.", "shopify.", "heal.due.cursor.", "nostr.", "farcaster.",
    ]

    /// The Keychain services the devnets' signing keys lived under. Test money
    /// only — a devnet faucet's — so nothing of value goes with them.
    private static let droppedKeychainServices = [
        "casberi-hegota-signer", "casberi-privacydevnet-signer",
        "casberi-privacydevnet-notes", "casberi-vibenet-signer",
    ]

    /// Cursor's API key, in the shared token vault (`TokenBridge.tokenKey`,
    /// "token.<seat id>") rather than a service of its own. Unlike the devnet
    /// keys above, this one could spend money and write code, so it must not
    /// outlive the seat that was its only reader.
    private static let droppedVaultKeys = ["token.cursor"]

    /// `.v2` since prd §1049 added three seats, `.v3` since Nostr joined,
    /// `.v4` since Farcaster joined (prd §1110): a device that ran the earlier
    /// pass would otherwise never clear the new seats' defaults. The work it
    /// repeats is idempotent — every delete finds nothing.
    private static let droppedLocalKey = "sourceRename.droppedSeats.local.v4"

    /// Drops what the deleted seats left behind, in `sweepVoice`'s shape: the
    /// ROWS at every launch, because the store mirrors to CloudKit and a
    /// device still on an older build keeps landing them; the seat records
    /// and the address book's tags at every launch too, for the same reason
    /// and because both are in-memory walks that write nothing when there is
    /// nothing to drop. The device-local half — defaults and Keychain items,
    /// which nothing syncs and nothing will write again — runs once.
    ///
    /// Deleted, not kept the way §638's retired seats' rows are: those seats
    /// left the catalogue with their code still in the tree for a release,
    /// and these left with it gone, so a kept row would be a row no room, no
    /// sheet and no bridge can read.
    @MainActor
    @discardableResult
    static func sweepRetiredSeats(context: ModelContext, store: BridgeStore) -> Int {
        // The seat records, by NAME: Hegotá Privacy's id was "privacy", which
        // Privacy.com's seat also answers to, so an id would take the wrong one.
        let stale = store.bridges.filter { droppedSources.contains($0.name) }
        if !stale.isEmpty {
            for seat in stale { BridgeHealth.forget(seat.name) }
            store.bridges.removeAll { droppedSources.contains($0.name) }
        }
        let book = AddressBook.shared
        for entry in book.all {
            for tag in droppedNetworks where (entry.networks ?? []).contains(tag) {
                book.removeNetwork(tag, for: entry.address)
            }
        }
        if !UserDefaults.standard.bool(forKey: droppedLocalKey) {
            // Reddit's follows first: each feed's HTTP record is keyed on the
            // feed URL, which only the follow list knows.
            if let data = UserDefaults.standard.data(forKey: "feed.reddit"),
               let follows = try? JSONDecoder().decode([FeedFollowEntry].self, from: data) {
                FeedFreshness.forget(follows.map(\.feedURL).filter { !$0.isEmpty })
            }
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where droppedDefaultsPrefixes.contains(where: { key.hasPrefix($0) }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            for service in droppedKeychainServices {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                ]
                SecItemDelete(query as CFDictionary)
            }
            for key in droppedVaultKeys { TokenVault.delete(key) }
            UserDefaults.standard.set(true, forKey: droppedLocalKey)
        }
        var dropped: [Thing] = []
        for name in droppedSources {
            let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == name })
            guard let count = try? context.fetchCount(descriptor), count > 0 else { continue }
            dropped += ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        }
        guard !dropped.isEmpty else { return 0 }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { context.delete(thing) }
        _ = context.saveHonestly()
        return dropped.count
    }

    // MARK: - The ask, retired (2026-10-01)

    /// What the ask kept on this device, and what nothing reads any more: the
    /// kept asks and their digests, the Today brief's last document, its
    /// ledger and its scope stamps, the day's notice, Home's model-written
    /// line, the cluster names, the composer's tap counters, the agent hint's
    /// spent flag, the Mac's MCP switch — every key one of them wrote.
    static let retiredAskDefaultsPrefixes = [
        "keptAsks.", "brief.", "agent.noticed.", "home.insight.", "mcp.server.",
    ]
    static let retiredAskDefaultsKeys = [
        "cluster.names", "cluster.named.asked",
        "composer.askShownCounts", "composer.asksMadeCounts", "composer.firstKeptAsk.done",
        "agent.everRaised", "demo.mode.retiredAsksSwept.v1", "today.firstBriefShown",
    ]
    /// The MCP door's pairing token (prd §34), in the data-protection
    /// Keychain. A credential for a listener that no longer exists.
    static let retiredAskKeychainService = "com.casberi.mcp.pairing"
    /// The `sourceRef` an MCP client's save request carried (`MCPTools`,
    /// prd §34): an approval row whose Approve committed the thing it held.
    static let retiredMCPSaveMarker = "mcp.save"

    private static let retiredAskLocalKey = "sourceRename.retiredAsk.local.v1"

    /// Drops what the ask left behind, in `sweepRetiredSeats`' shape: the
    /// MCP door's save requests at EVERY launch, because the store mirrors to
    /// CloudKit and another device on an older build can still land one; the
    /// device-local half — defaults and the pairing token, which nothing syncs
    /// and nothing will write again — once.
    ///
    /// No `Thing` the person kept is touched. A kept ask, a brief, a notice
    /// and a cluster name were never rows; an answer saved as a note is the
    /// person's note and stays. A sweep, never a migration (§647), and no
    /// schema field goes (CloudKit is additive only).
    @MainActor
    @discardableResult
    static func sweepRetiredAsk(context: ModelContext) -> Int {
        if !UserDefaults.standard.bool(forKey: retiredAskLocalKey) {
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where retiredAskDefaultsPrefixes.contains(where: { key.hasPrefix($0) })
                || retiredAskDefaultsKeys.contains(key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: retiredAskKeychainService,
            ]
            SecItemDelete(query as CFDictionary)
            UserDefaults.standard.set(true, forKey: retiredAskLocalKey)
        }
        let marker = retiredMCPSaveMarker
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == marker })
        guard let count = try? context.fetchCount(descriptor), count > 0 else { return 0 }
        let dropped = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        guard !dropped.isEmpty else { return 0 }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { context.delete(thing) }
        _ = context.saveHonestly()
        return dropped.count
    }
}
