import Foundation
import SwiftData
import UIKit

/// The FURNISHED demo corpus (2026-08-07) — one room per source, each carrying
/// the fields that room's own hero reads.
///
/// `DemoCorpus` seeds 35 things across eight sources, which was the whole app
/// when it was written. Since then every room grew a hero — a topic treemap, a
/// leaderboard, a mood rail, a thumbnail wall, a year grid — and the agent's
/// panel (§334) gathers those figures onto one surface. None of it could ever
/// appear on a dev simulator, because **a hero is composed from STORED FIELDS,
/// not from a row's existence**: a leaderboard needs `authorHandle`, a treemap
/// needs `ocrTopics`, a wall needs `previewImageURL`, a flow band needs
/// `transferDirection` + `transferUSD`, a merchant board needs `priceValue` +
/// `priceCurrency`. A seed that sets only title/source renders as a plain
/// `BandRow` list — the §313 X failure, in every room at once.
///
/// So this is a table of ROOMS, not of rows, and each entry exists to make one
/// named figure draw. Three rules it keeps:
///
///   • **DEBUG-gated by `DemoState.seedsDemoData`**, like `DemoCorpus` — never
///     a release build, never a `-fresh YES` install, never an install that
///     went through onboarding (the 2026-07-07 ruling: the empty states are
///     the product too, and fake approvals read as real).
///   • **Deterministic.** No `Date.now` arithmetic that lands on a random
///     hour, no shuffles: the same install produces the same panel, because a
///     surface that reshuffles between two opens over identical data reads as
///     broken (`AgentPanel.rank`'s own reasoning).
///   • **No network, ever.** Every picture is a bundled sample addressed as
///     `sample:demo-shot-N`; `RemoteImageLoader` resolves that scheme in DEBUG.
///     A demo that hotlinks images is a demo that breaks on a plane, and a
///     host literal here would be an undeclared reach
///     (`scripts/network-reach-audit.sh`).
///
/// It is idempotent by a stored VERSION rather than by checking each row: bump
/// `version` when the table changes and the next dev launch re-seeds. `clear`
/// removes everything it owns, keyed on the ref namespaces below.
enum DemoSeedAll {

    /// Bump to re-seed on the next dev launch.
    ///
    /// **Sat at 1 from the day it was written until 2026-08-17**, through
    /// dozens of table changes — so `seedIfNeeded` short-circuited on every
    /// launch of every dev install that had ever seeded, and the DEBUG
    /// auto-seed path silently served a corpus years of edits out of date.
    /// It never bit hard because the doors people actually use (`-demoSeed
    /// force`, `-demoEnter`) both bypass this guard, which is exactly why
    /// nothing ever pointed at it.
    ///
    /// Deliberately still a HAND-BUMPED integer. A fingerprint derived from
    /// the table would never go stale, and was declined twice over: Swift's
    /// `hashValue` is randomly seeded per process, so the obvious spelling is
    /// not even stable across two launches of the same binary; and a
    /// fingerprint that DOES change re-runs `seed`, which is an insert path,
    /// on a corpus that may already hold those rows. Getting that wrong
    /// double-seeds a dev install rather than failing loudly. The honest
    /// version of "make it mechanical" here is a check that the stamp moved
    /// when the table did, not a stamp that moves itself.
    static let version = 3
    private static let versionKey = "demo.fullSeed.version"

    /// The three demo-watched tokens — (symbol, name, price, ref index),
    /// pulled up to a shared constant (2026-08-11) so `TokenPulse.seedDemo`
    /// can seed the SAME refs `rooms()` lands things under, rather than a
    /// second copy that can drift from it (the demo-parity discipline this
    /// file's own header states as a rule).
    /// `marketCap` is what fills `TokenRow`'s vitals line ("SOL · $83.1B
    /// cap"); a real Dexscreener read always carries one, so seeding nil left
    /// every demo row's second line blank (2026-08-12).
    static let tokenSeeds: [(symbol: String, name: String, price: Double,
                             marketCap: Double, dayOffset: Double)] = [
        ("ETH", "Ethereum", 3_180, 383_000_000_000, 1),
        ("SOL", "Solana", 176, 83_100_000_000, 2),
        ("DEGEN", "Degen", 0.0071, 71_400_000, 5),
    ]

    /// The `sourceRef` namespaces this seeder owns — what `clear` deletes.
    ///
    /// Two of them are NOT `demo:` and can't be: `ScreenshotIngest`'s sample
    /// resolver keys on `sample:demo-shot-`, and `FilesIngest.isImageRef`
    /// refuses anything that isn't `files:<path>.<image ext>` — which is
    /// exactly the test the Files room's treemap membership runs. A ref is
    /// data other code parses, so the demo joins those namespaces rather than
    /// inventing its own and rendering as an unhealed room.
    /// `import:receipt:` is here for a fourth reason again: a bulk room's
    /// receipt is identified by an EXACT ref (`Corpus.importReceiptRef`), so
    /// the demo cannot namespace it. On a DEBUG dev install that ref can only
    /// belong to a demo import or to one the developer ran themselves, and
    /// `clear` is a debug verb — but it is the one prefix here that could reach
    /// a row this file did not write.
    /// `cloudflare:cert:demo` is here for the SAME reason as the first two —
    /// `CloudflareRunwaySource.item(ref:)` matches `hasPrefix("cloudflare:
    /// cert:")` exactly, so `infra()`'s two rows can't carry a `demo:` ref and
    /// still compose. The `demo` suffix on the id (`cloudflare:cert:demo0`)
    /// is what keeps this scoped to rows this file actually wrote, since a
    /// real connected Cloudflare account's OWN cert refs share the same
    /// prefix (`cloudflare:cert:<real zone id>`) and must never be swept up
    /// by `clear`/`teardown`.
    static let refPrefixes = ["demo:", "sample:demo-shot-", "files:demo/",
                              "import:receipt:", "cloudflare:cert:demo",
                              // Vibenet's demo rows carry the REAL bridge's
                              // ref shape for the same reason Peer's do
                              // below — so its own dedupe recognises them —
                              // which means teardown needs this entry or
                              // they outlive the demo, indistinguishable
                              // from a real landed key authorization.
                              "vibenet:",
                              // Peer/Privacy Pools rows carry the REAL
                              // bridges' own ref prefixes (2026-08-10, so
                              // their room heads' ref-shape matching
                              // recognises them) rather than the generic
                              // "demo:" family every other seed uses — so
                              // exit() needs its own entries or these rows
                              // outlive the demo, indistinguishable from a
                              // real synced deposit/fill.
                              // …including the RAGEQUIT that closes the loop
                              // (2026-08-17, prd §397). Without its own entry
                              // the exit row outlives the demo AND goes on
                              // joining to nothing, which is the one shape
                              // that could make a real deposit read
                              // "Reclaimed" on evidence that isn't real.
                              // Telegram (prd §456), the same reasoning a
                              // fourth time, and here it cuts both ways: the
                              // channel posts MUST carry the real
                              // `telegram:post:` shape or `Corpus.arrivedLive`
                              // never lets them into All and the demo shows
                              // the wrong behaviour for the one rule this seat
                              // exists to prove — while a bare real prefix in
                              // teardown would delete a REAL followed
                              // channel's rows off a lived-in install. Hence
                              // a demo marker inside the real shape, so both
                              // halves are exact.
                              "telegram:post:demo-", "telegram:saved:demo-",
                              "telegram:chat:demo-",
                              "peer:demo", "privacypools:dep:demo",
                              "privacypools:ragequit:demo",
                              // Radicle (prd §401), same reasoning again: the
                              // rows carry the real `radicle:<kind>:<rid>:…`
                              // shape so the head's tap can find them, and the
                              // demo RID is what scopes teardown to this
                              // file's rows. Two entries because the KIND sits
                              // before the rid, so no single prefix covers a
                              // patch and an issue.
                              "radicle:patch:rad:zDEMO",
                              "radicle:issue:rad:zDEMO",
                              // Walletbeat (prd §419) carries the REAL ref
                              // shapes for the same reason as Radicle above —
                              // the room head joins a watch to its stored card
                              // by the wallet id inside the ref, so a "demo"
                              // segment would make every seeded wallet resolve
                              // to no directory entry and draw as unrated.
                              "walletbeat:wallet:", "walletbeat:news:",
                              "walletbeat:rev:",
                              // L2BEAT (prd §428) carries the REAL ref shapes for
                              // Walletbeat's exact reason above — the room head joins
                              // a watch to its assessment by the project id inside the
                              // ref, so a "demo" segment would make every seeded chain
                              // resolve to no directory entry and draw as unassessed.
                              "l2beat:chain:", "l2beat:news:", "l2beat:rev:",
                              // The two PostHog WATCH rows (2026-08-10) carry
                              // the real `PostHogWatch.metricRef` shape for
                              // the same reason — no "demo" segment is
                              // possible here since the event name itself
                              // must be real for the room head to read it.
                              // Scoped to the EXACT two names the demo uses
                              // (never a bare "posthog:metric:" prefix, which
                              // would sweep up a real custom watch) — the
                              // same accepted risk `PostHogState.forget`
                              // already carries for these same two names:
                              // a real PostHog connection watching a metric
                              // literally called "signed_up" or
                              // "answer_asked" would lose it on demo exit.
                              // Not reachable through the UI (`demoReentryAvailable`
                              // hides the re-entry door the moment anything
                              // real is connected), only through the DEBUG
                              // `-demoEnter` hook.
                              PostHogWatch.metricRef("signed_up"),
                              PostHogWatch.metricRef("answer_asked"),
                              // Railgun rows (2026-08-11) carry the real
                              // "railgun:shield:"/"railgun:unshield:" prefix
                              // for the same ref-shape-matching reason as
                              // Peer/Privacy Pools above.
                              "railgun:shield:demo", "railgun:unshield:demo",
                              // Stocktwits watches join the REAL namespace —
                              // `StocktwitsScreen` builds its watchlist by
                              // filtering on that exact prefix, so a "demo:"
                              // ref would land rows the setup screen cannot
                              // see. EXACT refs, never the bare prefix, for
                              // the PostHog reason above: a real watch on one
                              // of these three symbols must survive demo exit.
                              StockWatch.symbolRef("AAPL"),
                              StockWatch.symbolRef("NVDA"),
                              StockWatch.symbolRef("TSLA"),
                              // The purchase seats (2026-08-12, prd §368) carry
                              // the REAL ref shapes for the Peer/Privacy Pools
                              // reason exactly: `PurchaseStage.archetype` forks
                              // on those prefixes, so a "demo:" ref would leave
                              // every seeded receipt wearing the generic sheet
                              // and the category would look unbuilt in the one
                              // place anyone can see it without an account.
                              // They keep a "demo" SEGMENT, so nothing real can
                              // collide with them.
                              "privacy:txn:demo", "bitrefill:order:demo",
                              "bitrefill:invoice:demo",
                              // Open Food Facts keys on the barcode itself and
                              // there is nowhere to put a "demo" segment — the
                              // ref IS the product's code, and the scanned
                              // card's own barcode rung reads it back. EXACT
                              // refs, never a bare "off:" prefix, for the
                              // PostHog/Stocktwits reason above: a real scan of
                              // one of these three products must survive demo
                              // exit, and a bare prefix would take every scan
                              // in the corpus with it.
                              "off:5060403320102", "off:8717677332304",
                              "off:5391520941016",
                              // The demo vault. Scoped to its own FOLDER,
                              // never the bare "obsidian:" prefix, so exiting
                              // the demo can never delete a real vault's
                              // notes — `files:demo/`'s shape, same reason.
                              "obsidian:demo-vault/",
                              // App Store Connect joins the REAL `asc:` shapes
                              // because `WorkStage.ascOutcome` parses the ref
                              // itself. EXACT refs, never a bare "asc:" prefix
                              // — the PostHog/Stocktwits reason: a real
                              // version, review or build row must survive.
                              "asc:version:demo1:IN_REVIEW", "asc:review:demo1",
                              "asc:build:demo285", "asc:buildexpiry:demo274",
                              // The approval joins the REAL `wallet:approval:`
                              // namespace because `WalletPrepare.applies`
                              // parses it. The "demo" segment keeps it clear
                              // of a real grant (the `peer:demo` shape).
                              "wallet:approval:demo",
                              // **The three families that were MISSING until
                              // 2026-08-17.** Each joins a real namespace for
                              // the `peer:demo` reason above and each kept a
                              // "demo" segment, so the seeder was right — it
                              // was this list that was short, and the failure
                              // is silent in the worst direction: `clear`
                              // walks these prefixes, so the rows outlived
                              // every exit, and `restampIfStale` walks the
                              // same list, so they also froze in place while
                              // the other ~390 rows moved forward.
                              //
                              // Safe is the one that mattered most, because
                              // `teardown` DOES call `SafeBridge
                              // .clearDemoSnapshot()`: the head went and the
                              // rows stayed, leaving orphans still tagged
                              // "Your turn" and "Ready to execute" with
                              // nothing behind them to be your turn AT. A
                              // demo that cannot be left is the one promise
                              // `DemoBanner` makes out loud.
                              "wallet:safe:eth:demo", "1claw:policy:demo",
                              // Bitcoin keys on the demo wallet address, so
                              // the prefix stops before it — `bitcoin:settled:`
                              // alone would take a real settled transfer with
                              // it, the bare-prefix trap the PostHog and
                              // Stocktwits entries above are scoped against.
                              "bitcoin:settled:\(demoWallet):demo",
                              // Dropbox joins the real namespace so its images
                              // can satisfy `FilesBridge.isStoredPicture`
                              // (2026-08-17) — scoped to the demo FOLDER, never
                              // the bare `dropbox:` prefix, which would take a
                              // real connected folder's rows with it.
                              "dropbox:demo/"]

    // MARK: - Entry point

    /// Seed unless this exact version is already in. Safe to call on every
    /// launch; costs one UserDefaults read when there's nothing to do.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard DemoState.seedsDemoData else { return }
        guard UserDefaults.standard.integer(forKey: versionKey) != version else { return }
        seed(context)
        UserDefaults.standard.set(version, forKey: versionKey)
    }

    /// Insert the rooms and the bridge state the room heads read.
    ///
    /// Deduped on `sourceRef` the way every real ingest is, and for the same
    /// reason: `-demoSeed force` exists so an edit to the table can be checked
    /// without reinstalling, and without this a second run files a second copy
    /// of every row. That is not merely untidy — a leaderboard's SUBTITLE sums
    /// the rows it counted, so five forced runs read "43,875 saved messages"
    /// over five identical bars. Caught exactly that way on the sim.
    @MainActor
    static func seed(_ context: ModelContext) {
        let landed = Set(((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
            .compactMap(\.sourceRef))
        for thing in rooms() where !landed.contains(thing.sourceRef ?? "") {
            context.insert(thing)
        }
        context.saveHonestly()
        seedBridgeState()
    }

    /// Remove everything this seeder owns — things and the state it planted.
    /// Returns the row count deleted.
    @MainActor
    @discardableResult
    static func clear(_ context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        let mine = all.filter { thing in
            guard let ref = thing.sourceRef else { return false }
            return refPrefixes.contains { ref.hasPrefix($0) }
        }
        for thing in mine { context.delete(thing) }
        context.saveHonestly()
        UserDefaults.standard.removeObject(forKey: versionKey)
        return mine.count
    }

    // MARK: - Teardown

    /// The rooms whose visit history `seedBridgeState` plants, hoisted so the
    /// seed and the unseed read ONE list. Split apart they drift, and the
    /// failure is silent in the direction that matters: a room dropped from
    /// the seed keeps its affinity forever, so the panel goes on ranking a
    /// room the demo no longer furnishes.
    ///
    /// Affinity is the panel's PRIMARY sort inside a grade (`AgentPanel.rank`),
    /// so with none of it the tiles fall back to alphabetical — which reads as
    /// arbitrary and, worse, starves whole figure kinds: the three mood rails
    /// in the app all sat below the twenty-tile cap behind rooms whose only
    /// advantage was their name. These are the rooms a demo should lead with,
    /// and they cover every figure the panel can draw.
    ///
    /// `Pinterest`/`OpenSea` are here so one image room holds a slot and the
    /// thumbnail WALL is on the panel too — every other figure kind has a room
    /// above the cap, and a demo showing seven of the eight is the one thing
    /// this seed exists to prevent. (`pulse` is deliberately absent: §336
    /// grades a year wall below everything, and a demo that fought that ruling
    /// would be showing a panel the app doesn't actually build.)
    static let demoVisits: [String: Int] = [
        "Photos": 9, "X": 8, "Stocktwits": 7, "Obsidian": 6, "Linear": 6,
        "Snapchat": 5, "YouTube": 5, "Instagram": 4, "Privacy Pools": 4,
        "Farcaster": 4, "Apple Wallet": 3, "Circle x402": 3, "TikTok": 3,
        "Gmail": 2, "Files": 2, "Pinterest": 5, "OpenSea": 3,
        // Base Vibenet (2026-08-23) — a landless seat like Cloudflare and
        // Apple Wallet, so its chip needs its OWN visit weight rather than
        // riding a landed row's — `ChipMemory` ranks the source chip strip,
        // not the corpus, and a seat with no Things would otherwise sort
        // to the back of the strip despite reading as "connected".
        "Base Vibenet": 3,
        // Cloudflare (2026-08-08) — the `runway` figure kind had NO room
        // above the panel's 20-card cap, and the reason wasn't affinity, it
        // was that `runway` could not draw at all: `CloudflareRunwaySource
        // .compose` returns nil without a saved `CloudflareEstateStore`
        // snapshot, which nothing here seeded until `seedCloudflareEstate`
        // (see `seedBridgeState`). Found via `-agentOpenProbe` over a fully
        // poured demo — a coverage sweep across every `AgentPanel.Figure`
        // case, not a guess. Now that the figure genuinely composes, it
        // needs the same affinity boost every other single-figure-kind room
        // here got (Pinterest/OpenSea for `wall`), or it still loses the
        // ranking race on affinity=0 and the fix is invisible in the panel
        // that motivated it.
        "Cloudflare": 4,
        // PostHog (2026-08-10) — the SECOND half of the Cloudflare lesson, and
        // the half that comment above predicted: `curve` is PostHog's alone (the
        // wallet's is `worth(curve:cells:)`, a different case), the state behind
        // it has been seeded correctly since the room-head pass — a 7-point
        // series, `fetchedAt` stamped — so the card composes perfectly and then
        // ranks 21st on affinity=0 and is cut by the 20-card cap. Every run,
        // identically: the visit table is a fixed seed, so the ranking is
        // deterministic and "re-run to see if it's consistent" cannot tell this
        // apart from a wiring gap. Four verify runs and a manual re-run all
        // reported the same one missing kind, which is what settled it.
        //
        // At 4 it clears the affinity=3 tail. That evicts one of
        // TikTok/OpenSea/Apple Wallet/Circle x402, each of whose figure kind is
        // already drawn by a room ranked above it — so the cap costs a card and
        // never a KIND, which is the only thing this seed is protecting.
        "PostHog": 4,
    ]

    /// The PostHog metrics `seedBridgeState` plants, named once for the same
    /// reason as `demoVisits` — `PostHogState.clear()` would take a real
    /// project's readings with them.
    static let demoMetrics = ["signed_up", "answer_asked"]

    /// Undo everything `seed` did — the rows AND the state it planted.
    ///
    /// The mirror of `seed`, and it lives beside it deliberately: `clear`
    /// alone deletes the Things and leaves the demo wallet watched, its
    /// balance curve on disk, two PostHog metrics, a seller table and a visit
    /// history — so "exit the demo" landed on an empty feed wearing five
    /// furnished rooms and a $12,480 crown. That is worse than not exiting,
    /// because the corpus is gone and the numbers above it are not.
    ///
    /// Every unwind here is BY NAME rather than a blanket wipe: this is
    /// reachable from a dev install that also holds real watched wallets and
    /// real readings, and leaving the demo must never cost those.
    /// Returns the row count deleted.
    @MainActor
    @discardableResult
    static func teardown(_ context: ModelContext) -> Int {
        let rows = clear(context)

        // The wallet, and only the one this file added. `WalletStore.remove`
        // drops the history key with the address (see its `addresses`
        // observer), so the curve needs no separate delete — but a wallet the
        // person watched themselves keeps both.
        for wallet in demoWallets {
            if let index = WalletStore.shared.addresses
                .firstIndex(where: { $0.address.lowercased() == wallet.address.lowercased() }) {
                WalletStore.shared.remove(at: IndexSet(integer: index))
            }
        }

        for event in demoMetrics { PostHogState.forget(event) }
        ChipMemory.forgetDemo(Array(demoVisits.keys))
        X402State.forget()
        // The keystore snapshot and its seat evidence (prd §403).
        AltanaState.clear()   // takes the seeded ghosts with it (§410)
        AltanaKeystore.evidence.forget(demoWallet)
        // The other eleven wallet-riding seats' marks (prd §484). BY WALLET,
        // never a blanket clear of the key: a dev install may have real
        // evidence for the same protocol at a real address, and this is the
        // one demo mark that governs whether a seat exists at all.
        for evidence in walletSeatEvidence { evidence.forget(demoWallet) }
        // The seeded anonymity sets (prd §397). Scoped BY LABEL, unlike the
        // PostHog/Cloudflare stores above, and that is not fussiness: the
        // live sizes are global and re-bought within a day, but a landing
        // snapshot is the size of a set at a moment that has passed and can
        // never be re-read — so a real depositor who walked the demo would
        // permanently lose the growth half of their cover line to a blanket
        // wipe. Demo labels are `demo…`, a real one is a decimal uint256.
        PrivacyPoolsCover.forgetCurrent()
        PrivacyPoolsCover.forget(labels: ["demo2", "demo7"])
        // Same shape as PostHog above, and the same accepted risk: one
        // global cache, no per-account key, so this can't tell a demo
        // estate from a real one it might have overwritten — exactly what
        // `AccountScreen.demoReentryAvailable`'s own gate already exists to
        // keep off a lived-in install (a real Cloudflare bridge reads as
        // "Cloudflare" too, indistinguishable by name).
        CloudflareEstateStore.clear()

        // Base Vibenet — the four demo-seeded addresses, by NAME, never a
        // blanket `removeAll()`: a real vibenet watch this device already
        // held before entering the demo (implausible, but the rule the
        // other bridges above already keep) must survive exiting it.
        for address in [
            "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
            "0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c",
            "0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
            "0x4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e",
        ] { VibenetWatch.shared.remove(address) }
        // The balance curve goes with them. Unlike the watch list above there
        // is no "kept it themselves" case to protect: the store holds ONE
        // series for the room, so a real watcher's readings and the demo's
        // seeded ones cannot be told apart once mixed — and the seeded shape
        // ends on the fixture's total, which is not their balance. Dropped
        // whole, and it refills from their own next sweep.
        VibenetValueStore.forget()
        // …and the contracts the demo cached (prd §476), or a real install
        // that has never connected vibenet keeps a demo's faucet address
        // behind its own undeployed accounts. A live install re-fetches on its
        // next sweep, so this can only ever cost a cache miss.
        VibenetConfig.forgetCache()
        // And the seen-keys ledger, for the same reason and one step
        // stronger: the demo fixture's four addresses are not theirs, so a
        // ledger left behind would diff a real roster against a demo's.
        VibenetKeysSeen.forget()

        // Apple Wallet's own bespoke connected flag, and App Store Connect's
        // planted standing — same accepted risk as Cloudflare above: a real
        // Apple Wallet or App Store Connect bridge answers to the same name
        // and there is no per-account key to tell a demo estate from a real
        // one, which is exactly what `demoReentryAvailable`'s gate exists to
        // keep off a lived-in install.
        AppleWalletBridge.connected = false
        ASCState.apps = [:]
        ASCState.standing = [:]
        ASCState.lastRead = nil
        // BY NAME (prd §401) — a dev install watches real repos through this
        // same store, so a blanket wipe would take them with it.
        RadicleStore.shared.forgetDemo(rid: "rad:zDEMOheartwood0000000000001")
        // BY NAME (prd §401), same reasoning: a dev install may watch these very
        // wallets for real through this same store.
        WalletbeatState.forgetDemo(demoWalletbeatIDs)
        WalletbeatIncidentBook.forgetDemo(demoWalletbeatSlugs)
        // BY NAME (prd §401), same reasoning. `L2beatState` is deliberately NOT
        // touched: the demo seeds no assessment into it — the bundled directory
        // already answers for every chain, which is exactly what a device that
        // has never synced sees, so the demo shows the real first-run state.
        L2beatMilestoneBook.forgetDemo(demoL2beatKeys)
        SafeBridge.clearDemoSnapshot()
        forgetAddressBook()
        // The watched social accounts, by HANDLE — never a blanket wipe, since
        // a dev install watches real people through the same stores.
        let fcDemo = Set(demoFarcaster.map(\.handle))
        FarcasterStore.shared.accounts.removeAll { fcDemo.contains($0.username) }
        let bskyDemo = Set(demoBluesky.map(\.handle))
        BlueskyStore.shared.accounts.removeAll { bskyDemo.contains($0.handle) }
        // Nostr, the third social roster — seeded since 2026-08-12 and never
        // unwound until 2026-08-17, so three watched accounts survived every
        // demo exit. Worse than a stray row: `nostr.accounts` is a REQUIRED
        // floor in the `-floorProbe` registry, so the leak sat inside a
        // control something already checks the presence of, and presence was
        // all it checked.
        //
        // Keyed on the PUBKEY, not the handle. Farcaster and Bluesky match on
        // what the person typed because that is what their stores hold, but a
        // Nostr `Account.input` is normalized on the way in (an npub, a hex
        // key or a NIP-05 identifier all land differently), so a handle match
        // is a guess about that normalization. `pubkeyHex` is set from
        // `demoNostr` verbatim two functions up, which makes it the one field
        // both halves are certain to agree on.
        let nostrDemo = Set(demoNostr.map(\.pubkey))
        NostrStore.shared.accounts.removeAll { nostrDemo.contains($0.pubkeyHex) }

        // `clear` REMOVES the version stamp, which is right for the dev verb
        // it was written for (`-demoSeed clear`, where the next launch should
        // re-furnish). Leaving the demo is the opposite intent, and on a DEBUG
        // install `seedIfNeeded` would re-seed every room on the very next
        // launch — an exit that silently undoes itself. Stamping the current
        // version says "this one is handled" without touching `clear`'s
        // meaning for the harness.
        UserDefaults.standard.set(version, forKey: versionKey)
        return rows
    }

    // MARK: - Clock

    /// `daysAgo` days back, at `hour` local, on a stable minute.
    ///
    /// Anchored to a DAY boundary rather than a raw hour offset, for
    /// `DemoCorpus.stampDeadlines`' reason: a screen audit runs at an
    /// arbitrary time of day, and `now - 20h` drifts across midnight into a
    /// different bucket on every run. The minute is derived from the hour so
    /// the day dial (§337) shows a spread rather than marks on the hour lines.
    private static func at(_ daysAgo: Double, _ hour: Int) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date.now.addingTimeInterval(-daysAgo * 86_400))
        return day.addingTimeInterval(Double(hour) * 3600 + Double((hour * 17) % 60) * 60)
    }

    // MARK: - Row builder

    /// One seeded row. `tune` sets the fields that make a room's hero draw —
    /// they are all post-init properties on `Thing`, which is why this takes a
    /// closure rather than growing thirty parameters.
    private static func row(_ kind: ThingKind, _ title: String,
                            source: String, ref: String,
                            days: Double, hour: Int = 10,
                            content: String = "", tags: [String] = [],
                            _ tune: ((Thing) -> Void)? = nil) -> Thing {
        let when = at(days, hour)
        let thing = Thing(kind: kind, title: title, content: content, source: source,
                          createdAt: when, capturedAt: when, tags: tags,
                          sourceRef: ref)
        tune?(thing)
        return thing
    }

    /// The bundled sample photos, as the URL string `RemoteImageLoader`
    /// resolves in DEBUG. Four exist; a mosaic needs four DISTINCT urls (it
    /// dedupes on the url), so this cycles 1…4.
    private static func art(_ n: Int) -> String { "sample:demo-shot-\((n % 4) + 1)" }

    /// The bundled product stills, generated by
    /// `scripts/make-demo-art.swift`. Shopify's four arrivals take
    /// 1–4 and Deals' four offers take 5–8, matching that script's own
    /// `products` order — so a row and the still it opens can't drift apart
    /// without the script being re-run.
    ///
    /// Separate from `art(_:)` on purpose: that one hands back the sample
    /// PHOTOS, which is right for a screenshot or a pin and wrong for
    /// something being sold (a linen apron illustrated by a stock portrait,
    /// reported from the room itself, 2026-08-11).
    private static func productArt(_ n: Int) -> String { "sample:product-\(n)" }

    /// The demo cast's profile pictures — see `scripts/make-demo-art.swift`.
    /// Both social stores hydrate a real `avatarURL` for every watched
    /// account, and every landed post carries its author's, so a demo without
    /// them draws the source's brand glyph where the app draws a person.
    /// A demo person's face. The leading "@" is stripped because handles are
    /// stored BOTH ways across the corpus — X's archive keeps the "@" and the
    /// social bridges don't — and an asset called `sample:avatar-@lindsey`
    /// resolves to nothing at all, which renders as the source glyph and reads
    /// exactly like a person who has no picture.
    private static func avatarArt(_ handle: String) -> String {
        "sample:avatar-\(handle.hasPrefix("@") ? String(handle.dropFirst()) : handle)"
    }

    /// A publication's own mark. `RSSIngest` stamps the site's favicon onto
    /// `authorAvatarURL`, so a real reading room carries the publisher beside
    /// every byline; without it the demo's rooms showed the article art and
    /// no source.
    ///
    /// Lowercase and drop the spaces, and nothing else — an earlier cut also
    /// stripped a leading "the", which sent "The Verge" to `-verge` while the
    /// asset is `-theverge`, so that publisher alone would have resolved to
    /// nothing. The names here are literals in this file's own tables; a rule
    /// clever enough to need testing is the wrong rule for that.
    private static func publisherArt(_ name: String) -> String {
        avatarArt(name.lowercased().replacingOccurrences(of: " ", with: ""))
    }

    /// The same picture as stored bytes, for the rooms that draw pixels from
    /// the corpus rather than a URL (Photos, Files, Snapchat memories).
    private static func pixels(_ n: Int) -> Data? {
        UIImage.demoSample(for: "sample:demo-shot-\((n % 4) + 1)")?
            .jpegData(compressionQuality: 0.7)
    }

    /// A cast face as STORED BYTES, for the rows whose picture rides
    /// `previewImageData` rather than a `sample:` ref — `ContactsIngest`
    /// stamps `CNContact.thumbnailImageData` there, so that is the field the
    /// contact card reads and the only one a face can arrive by.
    ///
    /// PNG, never JPEG: the avataaars faces are circle-styled with transparent
    /// corners, and a JPEG has no alpha, so a re-encoded face arrives on a
    /// black square (the generator's own lesson, one file over).
    private static func facePixels(_ handle: String) -> Data? {
        UIImage.demoSample(for: "sample:avatar-\(handle)")?.pngData()
    }

    /// The import receipt a bulk-import room needs so ALL shows one row for it
    /// instead of the whole archive (`Corpus.showsInAll`).
    private static func receipt(_ source: String, _ line: String, days: Double) -> Thing {
        row(.note, "Imported from \(source)", source: source,
            ref: Corpus.importReceiptRef(source: source),
            days: days, hour: 9, content: line)
    }

    // MARK: - The rooms

    /// Plant the state the three stored-state heads read, from `DemoMode`'s
    /// pour — internal shim over the private seeder below, so the state is in
    /// place BEFORE the rows arrive (a room head that lands after its own
    /// rows reads as a late correction rather than an app filling up).
    @MainActor
    static func seedBridgeStateForDemo() { seedBridgeState() }

    /// Internal so `DemoMode` can pour these in chunks rather than landing
    /// them all in one transaction — see `DemoMode.pourIfNeeded`.
    // MARK: - Walletbeat (prd §419)

    /// The wallets the demo says you use.
    ///
    /// THREE, chosen to exercise the coverage gate rather than to flatter the card:
    /// Rabby and MetaMask are two of only six wallets Walletbeat has examined in depth,
    /// and Ledger is one of the many it has barely started on. Seeding three well-rated
    /// wallets would demo a feature that does not exist — measured 2026-08-20, sixteen of
    /// the 32 rated wallets have under a quarter of their attributes judged, so "not rated
    /// yet" is the COMMON row and the demo has to show it.
    static let demoWalletbeatIDs = ["rabby", "metamask", "ledger"]

    /// The sentence a demo wallet's row leads with — Walletbeat's own, taken from the same
    /// seeded ratings the report card draws, so the two can never disagree.
    private static func walletbeatDemoLead(_ id: String) -> String? {
        guard let attributes = WalletbeatDirectory.demoAttributes[id],
              let entry = WalletbeatDirectory.wallets.first(where: { $0.id == id })
        else { return nil }
        let card = WalletbeatCard(
            walletID: id, name: entry.name, hardware: entry.hardware, stage: entry.stage,
            lastUpdated: entry.updated, site: nil, attributes: attributes,
            fetchedAt: Date(timeIntervalSince1970: 1_787_000_000))
        if case .finding(let attribute) = card.lead, !attribute.explanation.isEmpty {
            return attribute.explanation
        }
        return nil
    }

    /// CardPointers (prd §420) — offers on two cards, spread so the room's
    /// head has something true to lead with on the first open: one inside the
    /// week (so the deadline headline fires) and one further out. A demo whose
    /// offers all expired in one week would make the head correctly decline
    /// and `verify.sh`'s room-head coverage read that decline as a gap — the
    /// §375 X lesson, two rooms over.
    ///
    /// **It seeds all THREE of the room's groups (prd §487)**, because a demo
    /// that fills one of them proves only that one exists: a dated pair for
    /// "Coming up", one live offer CardPointers gave no expiry for ("No end
    /// date"), and one finished for "Not active". The last is the one worth
    /// having — before §487 a spent coupon was indistinguishable from a live
    /// dateless one, and a demo that seeds no finished offer cannot show that
    /// it now is. Note the old comment here claimed the Hilton row was
    /// "snoozed" while the seed only left it undated; the two groups are
    /// separate now, so it says what it does.
    private static func cardPointers() -> [Thing] {
        [
            ("Amex Gold · Amazon", "cardpointers:offer:demo1", 4.0, "$10 back on $50+", Mark.none),
            ("Amex Gold · Shell", "cardpointers:offer:demo2", 19.0, "20% back, up to $8", Mark.none),
            ("Chase Sapphire · Uber", "cardpointers:offer:demo3", 0.0, "$5 back on rides", Mark.none),
            ("Chase Sapphire · Hilton", "cardpointers:offer:demo4", 0.0, "$50 back on $250+", Mark.done),
        ].map { title, ref, dueInDays, terms, mark in
            row(.reminder, title, source: "CardPointers", ref: ref, days: 1.0, hour: 9) { thing in
                thing.summary = terms
                thing.authorHandle = title.components(separatedBy: " · ").first
                thing.mark = mark
                // A finished offer keeps no deadline, exactly as
                // `CardPointersIngest.heal` leaves it.
                if dueInDays > 0, mark != .done { thing.dueAt = at(-dueInDays, 12) }
            }
        }
    }

    /// Base Vibenet's landed events (R4.2, 2026-08-23). The seat used to be
    /// LANDLESS — it drew a chip and a room head and nothing in the room —
    /// which stopped being tenable the moment the room got a `Shape` of its
    /// own: `demo-selftest.py`'s check F proves every shape has a seeded
    /// source, and a room nobody can see in the demo is exactly the gap that
    /// check exists to catch.
    ///
    /// Addresses match `VibenetRoom.demoFixture()`'s own, so the head above
    /// and the rows beneath it describe the same accounts rather than two
    /// unrelated sets. `authorHandle` is the account and `summary` the event
    /// without the address — the two fields `VibenetEventRow` reads.
    private static func vibenet() -> [Thing] {
        [
            // **`actor:`, NOT `auth:` — the REAL bridge's own ref segment**
            // (`VibenetEventKind.refSegment`), corrected 2026-08-25. The demo
            // invented its own spelling, and the moment anything downstream
            // matched on the real one — the event sheet asks `vibenet:actor`
            // to decide whether an event is about a KEY (§467) — every demo
            // authorization silently failed the test and drew no permissions
            // and no expiry. Same class as §349's Peer/Privacy Pools demo
            // refs: the rows land, the room renders, and the one reading that
            // needed the ref is quietly absent.
            //
            // **THE REFS CARRY A REAL-SHAPED HASH** (prd §495). They were
            // `vibenet:actor:demo1` — three components — and the event sheet's
            // transaction door reads the hash POSITIONALLY out of the real
            // bridge's own four-component ref, so every demo event failed the
            // shape and drew no door. The §349 class again, one field over:
            // the rows land, the sheet renders, and the one control it has is
            // silently absent from the corpus the demo exists to show.
            //
            // The hashes are invented and could not be otherwise — nothing
            // here reaches a chain — so tapping one opens an explorer page
            // that says no such transaction. That is the honest failure for a
            // demo and the same one every other demo permalink here makes; a
            // real hash would send somebody to a stranger's transaction and
            // imply it was theirs.
            ("0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b", "New passkey authorized",
             "actor:0x7c1d4e9a2b6f83c05d17e4a9b820f36cd15e7a48b93c206df41e85a7cb90d24f:0", 1.0),
            ("0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b", "New secp256k1 key authorized",
             "actor:0x3f8b25c6d017a94e5b83f2016cd74a9e8b520371fc6ad9e04b18752c3ae6f091:1", 1.0),
            ("0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c", "Locked on vibenet",
             "locked:0x9e04a71b3c8d526f0a94e7128bd35c6f807a1e29d4b60358cf9a2e714d80b365:0", 2.0),
            ("0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d", "Key revoked",
             "actor:0x5a2c9e18b7043fd61c85920ae3b47d6f0c19a5e8347b26df10a95c8e2b4713a9:0", 4.0),
        ].map { address, phrase, ref, days in
            let short = VibenetRoom.shortAddress(address)
            // The TITLE keeps naming the account — it is what the All feed,
            // search and Spotlight show, where no face is present.
            let title = phrase == "Locked on vibenet"
                ? "\(short) locked on vibenet"
                : "\(phrase) for \(short)"
            return row(.event, title, source: "Base Vibenet",
                       ref: "vibenet:\(ref)", days: days, hour: 11) { thing in
                thing.authorHandle = address
                thing.summary = phrase
                // ONE authorization carries the expiry of a real key in the
                // fixture, so the event sheet's permission chips and its
                // "Expires" row are exercised by the demo (§467). The value is
                // `demoFixture`'s own actor-1 expiry on this account, and that
                // is the whole requirement: `VibenetEventFacts` names a key's
                // permissions only when EXACTLY ONE key on the account matches
                // the event's expiry, so a number invented here would silently
                // match nothing and the chips would never draw. The account's
                // other two actors carry expiry 0 ("never"), which is what
                // makes this match unique.
                //
                // Keyed on the PHRASE rather than the ref since §495 gave the
                // refs real transaction hashes: a ref is now a 70-character
                // string nobody can match by eye, and a demo whose branches
                // are keyed to one is a demo that breaks silently the next
                // time a hash is regenerated.
                if phrase == "New secp256k1 key authorized" {
                    thing.dueAt = Date(timeIntervalSince1970: 4_102_444_800)
                }
                // The §308 facets the real bridge stamps (prd §468) — without
                // them the demo's four vibenet rows are the only rows in this
                // room a facet ask can never reach, which is exactly the demo
                // parity §349 made a standing rule.
                switch phrase {
                case "Locked on vibenet": thing.tags = ["Locked"]
                case "Key revoked":       thing.tags = ["Key", "Revoked"]
                default:                  thing.tags = ["Key"]
                }
                // ONE demo authorization is an ADMIN key, so the row that
                // reaches the lock screen (`NotifySweep.classify`) exists in
                // the demo at all. `demoFixture`'s own scope-0 actor lives on
                // a different account, and that is fine: the tag is the whole
                // gate and nothing joins the two.
                if phrase == "New passkey authorized" { thing.tags.append("Admin key") }
            }
        }
    }

    private static func walletbeat() -> [Thing] {
        var out: [Thing] = []

        out += [
            ("rabby", "Rabby", 0.0),
            ("metamask", "MetaMask", 0.0),
            ("ledger", "Ledger Wallet", 0.0),
        ].map { id, name, days in
            row(.link, name, source: "Walletbeat",
                ref: WalletbeatWatch.walletRef(id),
                days: days, hour: 9,
                content: "https://\(WalletbeatHost.site)/\(id)/",
                tags: ["Watchlist", id == "ledger" ? "Hardware" : "Software"]) { thing in
                thing.authorHandle = id
                // DERIVED from the seeded ratings, never hand-written.
                //
                // The first cut hardcoded these and put "MetaMask hides some transaction
                // fees" on MetaMask's row — which is RABBY's finding. A fabricated
                // finding attributed to a real company, inside the one feature built to
                // stop exactly that (§83). Deriving it also keeps the row and the report
                // card naming the same finding, which hand-written copy cannot promise.
                thing.summary = walletbeatDemoLead(id)
            }
        }

        // REAL incidents, with their REAL statuses. Deliberately no fabricated
        // "unresolved" row: the open-incident branch is worth demoing, but not at the
        // price of the demo asserting that a named company currently has an unpatched
        // vulnerability it does not have.
        out.append(
            row(.link, "Silent Signature Extraction Vulnerability in Rabby Browser Extension",
                source: "Walletbeat", ref: "walletbeat:news:rabby-silent-signature-extraction",
                days: 1.0, hour: 14,
                content: "https://\(WalletbeatHost.site)/news/",
                tags: ["Vulnerability", "Rabby"]) { thing in
                thing.authorHandle = "rabby"
                thing.summary = "A malicious app could queue a fund-draining signature request hidden by a Chrome pop-under bug, and unlocking the wallet signed it without the request ever being seen. Rabby shipped a fix; no funds were reported lost."
            })

        out.append(
            row(.link, "Serious · Unauthorized Access to SafePal Customer Order Information",
                source: "Walletbeat", ref: "walletbeat:news:safepal-customer-order-data-exposure",
                days: 4.0, hour: 11,
                content: "https://\(WalletbeatHost.site)/news/",
                tags: ["Data breach"]) { thing in
                thing.summary = "An authorization flaw in SafePal's order-tracking plug-in allowed unauthorized access to customer order records, including shipping details."
            })

        out.append(
            row(.link, "Customer Data Exposed in Trezor Shipping Provider Incident",
                source: "Walletbeat", ref: "walletbeat:news:trezor-shipmonk-data-breach",
                days: 7.0, hour: 16,
                content: "https://\(WalletbeatHost.site)/news/",
                tags: ["Data breach"]) { thing in
                thing.summary = "A fulfillment partner's breach exposed buyer names and addresses. Keys and devices were untouched — the risk is phishing that knows your name."
            })

        // The INCIDENT BOOK, which nothing seeded until now (prd §422) — so the
        // sheet's fact card, the row's "you use this" marker and the directory's
        // unresolved flag all read a store that was empty in the demo, and the
        // sheet-anatomy check passed over a head drawing nothing beneath it. The
        // teardown half already existed (`WalletbeatIncidentBook.forgetDemo`,
        // §401) with nothing to forget.
        //
        // REAL statuses, holding the ruling above: every one of these was fixed
        // or contained, so nothing here claims a named company currently has an
        // unpatched hole. That means the OPEN branch stays undemoed — correct,
        // and the reason `verify.sh` cannot cover the notification this feeds.
        seedWalletbeatIncidents()

        // A revision, so the third row shape in this room is demoed too.
        out.append(
            row(.link, "Walletbeat changed its rating of Rabby's app isolation",
                source: "Walletbeat", ref: "walletbeat:rev:rabby:appIsolation:FAIL:2026-07-20",
                days: 2.0, hour: 10,
                content: "https://\(WalletbeatHost.site)/rabby/",
                tags: ["Rating"]) { thing in
                thing.authorHandle = "rabby"
                thing.summary = "Rabby does not have an option to create a new account as part of the app connection flow."
            })

        return out
    }

    /// The slugs this demo plants in `WalletbeatIncidentBook`, so the teardown can
    /// take exactly those and leave a dev install's real incidents alone (§401).
    static let demoWalletbeatSlugs = [
        "rabby-silent-signature-extraction",
        "safepal-customer-order-data-exposure",
        "trezor-shipmonk-data-breach",
    ]

    // MARK: - L2BEAT (prd §428)

    /// The chains the demo says you use.
    ///
    /// Read from the SNAPSHOT's own list rather than re-spelled here, so the demo and the
    /// generator can never disagree about which three the bundle was built around.
    /// `scripts/l2beat-snapshot.py` picks them to exercise the range rather than to
    /// flatter the card: one on a higher rung, one at the bottom with a flagged sequencer,
    /// and Arbitrum because its exit window is the measured second-reading case.
    static var demoL2beatIDs: [String] { L2beatDirectory.demoChains }

    /// How many of L2BEAT's recorded incidents the demo lands.
    ///
    /// Six, which at the time of writing reaches back about three months — far enough that
    /// the room's 90-day window has something in it AND something outside it, which is the
    /// pair the head's two branches need to be worth demoing.
    private static let demoL2beatIncidentCount = 6

    /// The incidents the demo lands: the newest few across the whole registry, plus the
    /// newest for each watched chain so the risk card's "On record" section is not empty.
    ///
    /// DERIVED FROM THE BUNDLE, never hand-written — the rule the Walletbeat demo lead
    /// already follows, and stronger here because these are real companies and real
    /// outages. Their REAL dates are kept too, so the timeline is the one the feature
    /// actually produces rather than three rows invented to look recent.
    private static var demoL2beatMilestones: [L2beatMilestone] {
        let all = L2beatDirectory.seededIncidents
        var picked = Array(all.prefix(demoL2beatIncidentCount))
        var seen = Set(picked.map(\.ref))
        for id in demoL2beatIDs {
            guard let hit = all.first(where: { $0.projectID == id }),
                  seen.insert(hit.ref).inserted
            else { continue }
            picked.append(hit)
        }
        return picked
    }

    /// The keys this demo plants in `L2beatMilestoneBook`, so the teardown can take
    /// exactly those and leave a dev install's real milestones alone (§401).
    static var demoL2beatKeys: [String] {
        demoL2beatMilestones.map { String($0.ref.dropFirst(L2beatIdentity.newsPrefix.count)) }
    }

    private static func l2beat() -> [Thing] {
        var out: [Thing] = []

        out += demoL2beatIDs.compactMap { id -> Thing? in
            guard let project = L2beatDirectory.project(id) else { return nil }
            var tags = ["Watchlist", project.layer.label]
            if let stage = project.stage, stage != .notApplicable { tags.append(stage.label) }
            return row(.link, project.name, source: "L2BEAT",
                       ref: L2beatWatch.chainRef(id),
                       days: 0.0, hour: 9,
                       content: project.pageURL?.absoluteString ?? "",
                       tags: tags) { thing in
                thing.authorHandle = id
                // DERIVED from the bundled assessment, never hand-written — the same rule
                // the Walletbeat demo lead follows, and for the same reason: a fabricated
                // finding attributed to a real chain, inside the one feature built to stop
                // exactly that (§83). Deriving it also keeps the row and the risk card
                // naming the same finding, which hand-written copy cannot promise.
                if case .finding(let risk) = project.lead, !risk.worstExplanation.isEmpty {
                    thing.summary = risk.worstExplanation
                }
            }
        }

        // REAL incidents at their REAL dates, derived from the bundle. Nothing here is
        // invented, so the demo cannot claim an outage a named chain did not have.
        for milestone in demoL2beatMilestones {
            let project = L2beatDirectory.project(milestone.projectID)
            var tags = [L2beatMilestoneKind.incident.label]
            if let project { tags.append(project.name) }
            let daysAgo = max(Date.now.timeIntervalSince(milestone.date) / 86_400, 0)
            out.append(
                row(.link, L2beatIngest.milestoneTitle(milestone, project: project),
                    source: "L2BEAT", ref: milestone.ref,
                    days: daysAgo, hour: 13,
                    content: milestone.url ?? project?.pageURL?.absoluteString ?? "",
                    tags: tags) { thing in
                    thing.authorHandle = milestone.projectID
                    thing.summary = milestone.summary
                    thing.externalLink = project?.pageURL?.absoluteString
                })
        }

        // The MILESTONE BOOK, so the sheet's fact card and the directory's incident flag
        // read a store that is actually populated — the gap §422 found in Walletbeat's own
        // demo, closed here on the first pass rather than three days later.
        seedL2beatMilestones()

        // A stage move, so the third row shape in this room is demoed too — and the one
        // that is the whole reason to follow this registry. REAL: Base really did reach
        // Stage 1, which is why the bundled snapshot has it there.
        if let base = L2beatDirectory.project("base"), let stage = base.stage {
            let day = "2026-08-19"
            out.append(
                row(.link, L2beatIngest.revisionTitle(
                        project: base, change: .stage(before: .stage0, after: stage)),
                    source: "L2BEAT",
                    ref: "\(L2beatIdentity.revisionPrefix)base:\(L2beatSheet.stageSubject):\(L2beatSheet.token(for: stage)):\(day)",
                    days: 2.0, hour: 10,
                    content: base.pageURL?.absoluteString ?? "",
                    tags: ["Rating", "Stage"]) { thing in
                    thing.authorHandle = "base"
                    thing.summary = stage.meaning
                })
        }

        return out
    }

    private static func seedL2beatMilestones() {
        for milestone in demoL2beatMilestones {
            L2beatMilestoneBook.record(
                milestone, projectName: L2beatDirectory.project(milestone.projectID)?.name)
        }
    }

    private static func seedWalletbeatIncidents() {
        // Severities match the ROW TITLES above and cannot drift from them by
        // accident: `WalletbeatIngest.incidentTitle` prefixes "Serious · " at
        // exactly `.high`, which is why SafePal's demo row wears that word and
        // the other two do not.
        let facts: [WalletbeatIncident] = [
            WalletbeatIncident(
                slug: "rabby-silent-signature-extraction",
                title: "Silent Signature Extraction Vulnerability in Rabby Browser Extension",
                summary: "A malicious app could queue a fund-draining signature request hidden by a Chrome pop-under bug.",
                type: .vulnerability, severity: .medium, status: .resolved,
                publishedAt: Date().addingTimeInterval(-1 * 86_400), updatedAt: nil,
                wallets: ["rabby"], fundsImpacted: false,
                sources: [WalletbeatSource(label: "Rabby security advisory",
                                           url: "https://\(WalletbeatHost.site)/news/")]),
            WalletbeatIncident(
                slug: "safepal-customer-order-data-exposure",
                title: "Unauthorized Access to SafePal Customer Order Information",
                summary: "An authorization flaw in SafePal's order-tracking plug-in exposed customer order records.",
                type: .dataBreach, severity: .high, status: .mitigated,
                publishedAt: Date().addingTimeInterval(-4 * 86_400), updatedAt: nil,
                // Legitimately EMPTY — SafePal is not a wallet Walletbeat rates,
                // which is the documented real case and the one that proves the
                // marker declines rather than guessing.
                wallets: [], fundsImpacted: false,
                sources: [WalletbeatSource(label: "Disclosure",
                                           url: "https://\(WalletbeatHost.site)/news/")]),
            WalletbeatIncident(
                slug: "trezor-shipmonk-data-breach",
                title: "Customer Data Exposed in Trezor Shipping Provider Incident",
                summary: "A fulfillment partner's breach exposed buyer names and addresses.",
                type: .dataBreach, severity: .medium, status: .resolved,
                publishedAt: Date().addingTimeInterval(-7 * 86_400), updatedAt: nil,
                wallets: ["trezor"], fundsImpacted: false,
                sources: [WalletbeatSource(label: "Trezor statement",
                                           url: "https://\(WalletbeatHost.site)/news/")]),
        ]
        for incident in facts { WalletbeatIncidentBook.record(incident) }
    }

    static func rooms() -> [Thing] {
        var out: [Thing] = []
        out += photos()
        out += obsidian()
        out += ownCaptures()
        out += xArchive()
        out += instagram()
        out += tiktok()
        out += snapchat()
        out += telegram()
        out += youtube()
        out += files()
        out += reading()
        out += listening()
        out += mail()
        out += saves()
        out += social()
        out += markets()
        out += walletRoom()
        out += walletbeat()
        out += l2beat()
        out += cardPointers()
        out += vibenet()
        out += appleWallet()
        out += cards()
        out += work()
        out += infra()
        out += writing()
        out += fitness()
        out += schedule()
        out += odds()
        return out
    }

    // MARK: Rooms that lead with a topic treemap

    /// Terms recur on purpose: `ScreenshotTopics.cells` only ranks a term seen
    /// on TWO or more items (`minTermShots`), and `FeedInsight.topicMap`
    /// declines under six items carrying terms. A table of unique subjects
    /// would produce no map at all — the commonest way a seeded room looks
    /// broken.
    private static func photos() -> [Thing] {
        let shots: [(String, [String], Double, Int)] = [
            ("Figma — spacing tokens", ["Figma", "Design system"], 1, 11),
            ("SwiftUI — scroll transitions", ["SwiftUI", "Design system"], 2, 15),
            ("Lisbon — Alfama walking route", ["Lisbon", "Maps"], 5, 9),
            ("Espresso dial-in notes", ["Espresso"], 8, 8),
            ("Figma — colour ramp", ["Figma", "Espresso"], 12, 14),
            ("SwiftUI — matchedGeometry demo", ["SwiftUI"], 19, 21),
            ("Lisbon — tram 28 timetable", ["Lisbon", "Maps"], 26, 10),
            ("Espresso — grind chart", ["Espresso", "Design system"], 40, 16),
        ]
        var out = shots.enumerated().map { i, s in
            row(.screenshot, s.0, source: "Photos", ref: "sample:demo-shot-\(i + 5)",
                days: s.2, hour: s.3,
                content: "\(s.0)\n\(s.1.joined(separator: " · "))") { t in
                t.ocrTopics = s.1
                t.topicsAt = .now
                t.previewImageData = pixels(i)
            }
        }
        // TWO WORDLESS SHOTS (2026-08-17) — §218's picture rows, which the demo
        // could not draw at all. `FeedScreen.isWordless` asks a screenshot for
        // `ocrAt != nil && content.isEmpty`: OCR RAN and found no words, so the
        // picture is the row. Every shot above sets `topicsAt` and never
        // `ocrAt`, and every one carries `content`, so not one could qualify —
        // `imageOnly` measured 0 over the whole poured demo while the app
        // produces these constantly (a photographed scene, a chart, a shot with
        // no text in it).
        //
        // `ocrAt` set with `content` EMPTY is the honest pairing, and the order
        // matters: `ocrAt` alone would claim we looked and found nothing while
        // words sat in `content`, and empty `content` alone reads as a shot
        // still waiting to be read (which draws its byte size, not a picture).
        //
        // On two SEPARATE days, each already carrying several worded rows,
        // because the gate is a minority test per day (`wordless * 2 <
        // dayThings.count`). Two on one day would be likelier to tip that day
        // into a gallery, which is exactly what the gate exists to prevent.
        let wordless: [(days: Double, hour: Int, n: Int)] = [(1, 17, 0), (4, 12, 2)]
        out += wordless.enumerated().map { i, w in
            row(.screenshot, "", source: "Photos", ref: "sample:demo-shot-\(11 + i)",
                days: w.days, hour: w.hour, content: "") { t in
                t.ocrAt = .now
                t.previewImageData = pixels(w.n)
            }
        }
        return out
    }

    private static func obsidian() -> [Thing] {
        let notes: [(String, [String], Double)] = [
            ("Weekly review — week 32", ["Review", "Focus"], 2),
            ("Reading — Seeing Like a State", ["Reading", "Legibility"], 6),
            ("Focus: one surface at a time", ["Focus", "Design system"], 11),
            ("Legibility and the corpus", ["Legibility", "Review"], 17),
            ("Reading — The Timeless Way", ["Reading", "Design system"], 24),
            ("Focus blocks that actually held", ["Focus"], 33),
            ("Review — what shipped in July", ["Review", "Focus"], 45),
            ("Legibility notes for the panel", ["Legibility", "Design system"], 55),
            ("Reading list, autumn", ["Reading"], 63),
        ]
        // REAL `obsidian:` ref shape (2026-08-12). `NoteSheet`'s `.note`
        // anatomy — the one built for a vault note, where the NAME is the
        // identity and so leads — is gated on `NoteSheetSource.isNamed`,
        // which asks `ObsidianLink.relativePath` for the ref's path and
        // checks its stem against the title. A `demo:obsidian:0` ref fails
        // that prefix test outright, so every demo vault note degraded to
        // `.entry` and the anatomy could not be reached at all.
        //
        // The exact class CLAUDE.md already records twice (Peer and Privacy
        // Pools rows wearing `demo:` refs their own room heads could not
        // match). Scoped to a `demo-vault/` folder rather than the bare
        // `obsidian:` prefix so demo teardown can never delete a REAL vault
        // note — the `files:demo/` shape, for the same reason.
        return notes.enumerated().map { i, n in
            row(.note, n.0, source: "Obsidian", ref: "obsidian:demo-vault/\(n.0).md",
                days: n.2, hour: 20, content: n.0) { t in
                t.ocrTopics = n.1
                t.topicsAt = .now
                // A REAL BODY, not a one-line stub (2026-08-12).
                // `NoteSheetSource.body` prefers `enrichedText`, and the vault
                // card counts its words — so a stub read "10 words" and,
                // being under `NoteSheet.readTimeFloor` (100), never showed a
                // read time at all. The reading built for the longest-form
                // room in the app could not fire in the demo, which is the
                // "state below a control's declared floor" drift: nothing
                // renders wrong, the reading just never appears.
                t.enrichedText = vaultBody(title: n.0, tags: n.1)
            }
        }
    }

    /// The counterparties the wallet transfers name, and the synthetic address
    /// each one owns (2026-08-11). Ordered as the address book should read.
    ///
    /// `kind` is not decoration — the book draws a face for a `wallet`, the
    /// machinery mark for a `contract`, and its own mark for a `safe`, so the
    /// three named here are what make the demo exercise all three rather than
    /// twelve identical rows. Assigned by what each counterparty really IS: a
    /// person or an exchange deposit address is a wallet, a router or an
    /// orchestrator is a contract, and Gnosis Pay settles through a Safe.
    static let demoCounterparties: [(name: String, kind: AddressBook.Kind)] = [
        ("Sam", .wallet), ("Mia", .wallet), ("Coinbase", .wallet),
        ("Stripe", .wallet), ("Bitrefill", .wallet),
        ("Uniswap", .contract), ("Peer", .contract),
        ("Gnosis Pay", .safe),
    ]

    /// The watched social accounts the demo seeds, and the rows that name
    /// them. `mine` is true for "you" alone — it is what the inbound half
    /// (§239) reads to know whose likes and replies to look for, so marking
    /// all three would claim three accounts are yours.
    static let demoFarcaster: [(handle: String, name: String, bio: String)] = [
        ("you", "You", "Making a small thing carefully."),
        ("mia", "Mia", "Design, mostly. Occasionally onchain."),
        ("sam", "Sam", "Building in the open."),
    ]
    /// Nostr's watched accounts. Same three people as the rows above — one
    /// cast across the whole demo reads as a life; a fresh set per room reads
    /// as filler. The pubkeys are 64 hex characters because that is what the
    /// field holds; they resolve to nothing, and nothing asks them to.
    static let demoNostr: [(handle: String, name: String, bio: String, pubkey: String)] = [
        ("you", "You", "Making a small thing carefully.",
         String(repeating: "a1b2c3d4", count: 8)),
        ("uma", "Uma", "Signed, not hosted.",
         String(repeating: "b2c3d4e5", count: 8)),
        ("nils", "Nils", "Coffee, compilers, quiet weeks.",
         String(repeating: "c3d4e5f6", count: 8)),
    ]

    static let demoBluesky: [(handle: String, name: String, bio: String)] = [
        ("you", "You", "Making a small thing carefully."),
        ("uma", "Uma", "Product design. Book club organiser."),
        ("nils", "Nils", "Woodwork, coffee, and slow software."),
    ]

    /// One stable synthetic address per counterparty NAME — same name, same
    /// address, every time, so a landed row and its book entry are the same
    /// address rather than two that merely look alike. Derived from the name's
    /// own hash rather than a table of literals so a new counterparty above
    /// needs nothing else.
    static func counterpartyAddress(for name: String) -> String {
        // A stable, deterministic digest of the name — `hashValue` is seeded
        // per process and would hand back a different address every launch,
        // which for an address is not a cosmetic difference: rows landed on
        // one launch would stop matching the book on the next.
        var digest: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return "0x" + String(repeating: "0", count: 24)
            + String(format: "%016lx", digest)
    }

    /// Names those counterparties in the address book, so the wallet's people
    /// have faces and the connections card has nodes to draw (2026-08-11).
    ///
    /// Found by probing the demo's own book: `1 named · 1/5 watched`, that one
    /// being the demo wallet itself. Every transfer carried a counterparty
    /// NAME on the row, so the feed read correctly, and nothing that reads the
    /// BOOK — a saved name, a face, `AddressConnections`' whole graph — had a
    /// single entry to draw. The rows were never the gap; the book was.
    ///
    /// `setName` MERGES by design (it fills provenance/kind without erasing a
    /// rename), so this is safe on a dev install that already names one of
    /// these addresses — and the addresses are synthetic, so a real book can't
    /// collide with them anyway.
    @MainActor
    static func seedAddressBook() {
        for party in demoCounterparties {
            _ = AddressBook.shared.setName(party.name,
                                           for: counterpartyAddress(for: party.name),
                                           kind: party.kind)
        }
        // FACES for the two counterparties who are PEOPLE (2026-08-12). Sam
        // and Mia have a face in every social room and were identicons in the
        // one room that calls them by name — the same person, twice, and only
        // one of them recognizable.
        //
        // People only, deliberately. An ENS avatar is a picture somebody set
        // on their own name, so Coinbase, Stripe and Bitrefill keep their
        // identicons (a venue is not a face), and Uniswap, Peer and Gnosis Pay
        // are a contract and two protocols — `AddressKind` already draws those
        // as machinery, and putting a face on one would say a person is
        // standing behind an address that nobody stands behind.
        WalletStore.shared.seedDemoAvatars(
            Dictionary(uniqueKeysWithValues: demoFacedParties.map {
                (counterpartyAddress(for: $0), avatarArt($0.lowercased()))
            }))
    }

    /// The counterparties who are people, and so have a face. Named once so
    /// the seed and its unwind can never disagree about who they are.
    static let demoFacedParties = ["Sam", "Mia"]

    /// Unwinds `seedAddressBook`, BY ADDRESS — never a blanket wipe, since a
    /// dev install's book holds real people under the same store.
    @MainActor
    static func forgetAddressBook() {
        for party in demoCounterparties {
            AddressBook.shared.remove(counterpartyAddress(for: party.name))
        }
        WalletStore.shared.forgetDemoAvatars(demoFacedParties.map(counterpartyAddress(for:)))
    }

    /// What the person captured THEMSELVES — the share sheet, a drop, a paste
    /// (2026-08-11). `source: "You"` is `Thing`'s own default and the honest
    /// provenance of every own-capture; it is `chiplessSources`, so these earn
    /// no chip and no room by the 2026-08-02 ruling, and land in All where
    /// your own things belong.
    ///
    /// **These were seeded as `source: "Apple Notes"` for one day and that was
    /// wrong** — a demo-parity audit read "Apple Notes is a catalog offer with
    /// no demo seat" as a gap and furnished one, without checking whether the
    /// real app ever creates that seat. It deliberately never does:
    /// `NotesShareScreen` is an INSTRUCTION CARD, not a bridge — its own intro
    /// says "there is nothing to connect", and unlike its neighbours (Day One,
    /// Apple Journal, Bookmarks) it calls no `registerConnected`. iOS never
    /// tells a share extension which app a share came from, so a note shared
    /// out of Apple Notes lands exactly like any other own-capture, under
    /// "You" — which is what these rows now say. The catalog entry is right to
    /// exist and right to stay; the demo was claiming a connected state the
    /// screen behind it explicitly refuses to claim (§83's fake status).
    private static func ownCaptures() -> [Thing] {
        // **A note's body is not its title (2026-08-17).** These rows shipped
        // with `content` set to the title, so every one of them rendered an
        // excerpt that restated the line above it — the thinnest possible row,
        // in the one room that models what YOUR OWN saves look like.
        //
        // The fix is parity, not enrichment: `RootShell.keepAnswer` lands a
        // real capture as `Thing(kind: .note, title:, content: text, source:
        // "You")` and stamps nothing else — no tags, no image, no handle — so
        // these carry a real body and nothing more. Checked against that path
        // before writing, which is the rule this pass had to learn: whether a
        // demo room is thin is answered by the bridge, never by comparing it
        // to a richer room next door.
        //
        // They are also what `ScreenshotTopics.prose` reads for the All room's
        // map, so a body that is a duplicated title contributed a term that
        // was already the row's own name.
        let notes: [(String, String, Double)] = [
            ("Packing list",
             "Passport, chargers, the grey jacket. Swim stuff if the pool is open — check.",
             3),
            ("Wifi passwords",
             "Flat: the usual one. Studio: ask Uma, hers rotates monthly.",
             8),
            ("Gift ideas",
             "Sam — the Lisbon cookbook. Mia — proper secateurs, hers are shot.",
             14),
            ("Book recs from Sam",
             "The one about the lighthouse keeper, and anything by the Norwegian essayist.",
             21),
            ("Standup talking points",
             "Ship the import receipt. Flag the Thursday review moving. Ask about the joinery quote.",
             26),
            ("Recipe — weeknight pasta",
             "Anchovy, garlic, chilli, breadcrumbs. Twenty minutes, one pan, no cream.",
             34),
            ("Car maintenance log",
             "Tyres rotated at 41,200. Next service due around 46,000 or spring.",
             48),
        ]
        return notes.enumerated().map { i, n in
            row(.note, n.0, source: "You", ref: "demo:own:\(i)",
                days: n.2, hour: 21, content: n.1)
        }
    }

    /// X is a `bulkImportSources` room: its rows stay out of ALL and it gets
    /// one receipt there instead. Posts are `.note` (the treemap's kind), likes
    /// are `.link` wearing somebody else's words — the split §308 draws.
    private static func xArchive() -> [Thing] {
        var out: [Thing] = [receipt("X", "412 posts · 180 liked", days: 3)]
        // AN ARCHIVE HAS DEPTH, and the demo has to have it too (2026-08-13,
        // prd §375). The room's head is `XRoom` — years, their subjects and
        // the loudest one — which DECLINES under three distinct years or
        // twenty posts, so a seven-post table all inside one season made the
        // demo's biggest room the one place that card could never be seen.
        // The older years are deliberately thinner than the recent ones and
        // one year is deliberately silent: a strip where every bar is the same
        // height demonstrates nothing about a strip whose whole job is shape.
        let posts: [(String, [String], Double)] = [
            ("Shipping is a habit, not an event.", ["Shipping", "Craft"], 4),
            ("The best interface is the one that answers.", ["Craft", "Interfaces"], 9),
            ("Shipping small beats planning big.", ["Shipping"], 16),
            ("Interfaces should say what they know.", ["Interfaces", "Craft"], 23),
            ("Craft is what survives the deadline.", ["Craft"], 31),
            ("Interfaces that hide state are lying.", ["Interfaces"], 44),
            ("Shipping again this week.", ["Shipping", "Craft"], 58),
            ("A room should answer the question you walked in with.", ["Interfaces"], 96),
            ("Every registry drifts. Check the registry.", ["Craft"], 140),
            ("Shipping is mostly deleting.", ["Shipping"], 190),
            ("Interfaces are promises you have to keep.", ["Interfaces", "Craft"], 240),
            ("The demo is the product, briefly.", ["Craft"], 300),
            // Last year — the busiest, and the one the head names.
            ("Notes on reading your own archive.", ["Archives"], 430),
            ("An archive is a corpus, not a feed.", ["Archives", "Craft"], 455),
            ("Archives outlive the app that made them.", ["Archives"], 480),
            ("Shipping in public, year three.", ["Shipping"], 505),
            ("Interfaces that age well say less.", ["Interfaces"], 530),
            ("Archives are the only honest analytics.", ["Archives"], 560),
            ("Craft is legible from the outside.", ["Craft"], 590),
            ("Archives, again, because nobody else keeps them.", ["Archives"], 620),
            // Two years back — thinner.
            ("Starting to keep things properly.", ["Archives"], 900),
            ("Notes to myself, in public.", ["Craft"], 960),
            ("A feed you can't search isn't a record.", ["Archives"], 1010),
            // …and the first year, one post. The year between it and the next
            // is SILENT on purpose — the strip draws a gap, which is the one
            // reading no other card in this room can make.
            ("First post. Let's see how this goes.", [], 1830),
        ]
        out += posts.enumerated().map { i, p in
            row(.note, p.0, source: "X", ref: "demo:x:post:\(i)", days: p.2, hour: 12,
                content: p.0, tags: ["Post"]) { t in
                t.postText = p.0
                t.ocrTopics = p.1
                t.topicsAt = .now
                t.authorHandle = "you"
                // `XArchiveImport`'s face pass (`-xFaces`) stamps this, so a
                // real archive room is a column of faces; without it every
                // post in the busiest room in the corpus wore the X glyph.
                t.authorAvatarURL = avatarArt("you")
                // Floored (2026-08-13): the table is four times longer than it
                // was, and the old straight-line formula ran negative past the
                // tenth row — which `XRoom` would have read as a real count and
                // ranked as this year's loudest post.
                t.likeCount = max(1, 44 - i * 2)
                t.replyCount = max(0, 6 - i / 2)
                // Reposts (2026-08-17). §308's superlatives ride
                // `likeCount`/`repostCount` straight off the archive's own
                // `favorite_count`/`retweet_count`, and the demo set the first
                // and never the second — so "most reposted" could never answer
                // over the busiest room in the corpus. Floored for the reason
                // the line above documents: a straight-line formula runs
                // negative down a long table, and `XRoom` reads a negative as
                // a real count.
                t.repostCount = max(0, 12 - i)
            }
        }
        // The replies, so the room's second board ("Who you reply to") and the
        // sheet's `ReplyingToCard` both have something real — and so the demo
        // shows what a self-reply's free context looks like beside a reply to
        // somebody else, which is the pair `fetchReplyContext` exists for.
        let replies: [(String, String, String, Double)] = [
            ("Agreed — and the archive is where you find out.",
             "lindsey", "The best product decisions are legible a year later.", 12),
            ("This, but for rooms as well as rows.",
             "rauno", "Latency is a design problem, not an infrastructure one.", 34),
            ("Still true.", "lindsey", "", 210),
            // A THIRD reply to the same person, on purpose (2026-08-18, prd
            // §397). `XPerson.minimumSightings` is 3, so with two the person
            // card — the whole "your years with @lindsey" reading, reached by
            // tapping the room's own board — correctly declines and the demo
            // becomes the one place it can never be seen. Dated years back so
            // the card's span has a shape rather than one column.
            ("The archive answered it. Took nine years.",
             "lindsey", "Does anyone remember what we decided about this?", 1240),
        ]
        out += replies.enumerated().map { i, r in
            row(.note, "To @\(r.1) · \(r.0)", source: "X", ref: "demo:x:reply:\(i)",
                days: r.3, hour: 15, content: r.0, tags: ["Reply"]) { t in
                t.postText = r.0
                t.ocrTopics = ["Craft"]
                t.topicsAt = .now
                t.authorHandle = "you"
                t.authorAvatarURL = avatarArt("you")
                t.likeCount = 9 - i
                // The third has a permalink and NO words — the state a reply
                // sits in until the second act names what it answered, and the
                // one `-xReplyContext` reports as pending.
                t.parent = SocialCard(handle: r.1, text: r.2,
                                      avatarURL: avatarArt(r.1),
                                      url: "https://x.com/\(r.1)/status/17\(i)0000000000000000")
            }
        }
        // A wordless picture post — the room's grid half (prd §375). Seeded the
        // way the importer lands one — pixels, the medium tag, and NO
        // `postText` — since it is the absent `postText` that `isXPhotoTile`
        // reads (prd §397); a demo that faked it with a title would prove
        // nothing about the room's real membership test.
        out += (0..<3).map { i in
            row(.note, "Photo", source: "X", ref: "demo:x:photo:\(i)",
                days: 20 + Double(i) * 27, hour: 18, tags: ["Post", "Photo"]) { t in
                t.previewImageData = pixels(i)
                t.authorHandle = "you"
                t.authorAvatarURL = avatarArt("you")
                t.likeCount = 30 - i
            }
        }
        // A VIDEO POST (2026-08-18, prd §397). The same shape as a picture
        // post and a different tag, because until this pass a video landed
        // with no pixels at all and read as a row saying "Photo" — so the
        // demo is where the poster frame, the corner mark and the fact that
        // `Video` is its own facet are all visible at once.
        out.append(
            row(.note, "Video", source: "X", ref: "demo:x:video:0",
                days: 61, hour: 18, tags: ["Post", "Video"]) { t in
                t.previewImageData = pixels(3)
                t.authorHandle = "you"
                t.authorAvatarURL = avatarArt("you")
                t.likeCount = 38
            })
        // The account's own record (2026-08-18, prd §397) — the three
        // categories nothing had ever read. They are `.link` rows, so they
        // stay out of `XRoom`'s year counts (which are your writing alone) and
        // draw as plain bands rather than as posts nobody wrote.
        //
        // Plain `demo:` refs, NOT the real `x:app:`/`x:joined:` shapes the
        // importer writes. Peer and Privacy Pools carry their bridges' real
        // prefixes because their room heads MATCH on the ref shape; nothing
        // here does — `FeedScreen` tells these rows apart by their tag — so a
        // real prefix would buy nothing and cost the one thing that matters:
        // `refPrefixes` is what `teardown` sweeps, and a row outside it
        // outlives the demo, indistinguishable from a real grant.
        out.append(
            row(.link, "Can post as you · Tweetbot", source: "X", ref: "demo:x:app:0",
                days: 3100, hour: 9, content: "https://x.com/settings/connected_apps",
                tags: ["Access"]) { t in
                t.summary = "Tapbots · A Twitter client."
            })
        out.append(
            row(.link, "Can read your account · Timeline Cleaner", source: "X",
                ref: "demo:x:app:1", days: 1400, hour: 11,
                content: "https://x.com/settings/connected_apps", tags: ["Access"]))
        out.append(
            row(.link, "@firstname became @you", source: "X", ref: "demo:x:handle:0",
                days: 2200, hour: 10, content: "https://x.com/you", tags: ["Account"]))
        out.append(
            row(.link, "You joined X", source: "X", ref: "demo:x:joined:0",
                days: 3650, hour: 8, content: "https://x.com/you", tags: ["Account"]))
        let likes: [(String, String, Double)] = [
            ("A good demo is a real one", "@lindsey", 5),
            ("On drawing data honestly", "@tufte_bot", 10),
            ("Ship the boring version first", "@lindsey", 18),
            ("Latency is a design problem", "@rauno", 27),
            ("Notes on legible systems", "@tufte_bot", 39),
        ]
        out += likes.enumerated().map { i, l in
            row(.link, l.0, source: "X", ref: "demo:x:like:\(i)", days: l.2, hour: 22,
                tags: ["Liked"]) { t in
                t.postText = l.0
                t.authorHandle = l.1
                // The author of the post you liked — `avatarArt` strips the
                // "@" the archive keeps.
                t.authorAvatarURL = avatarArt(l.1)
                t.socialContext = "liked"
            }
        }
        return out
    }

    /// Instagram — the room a person recognises, which means the room has to
    /// be MOSTLY OTHER PEOPLE (prd §395). The old seed was six captions and
    /// five saves across three accounts, which drew nothing this room actually
    /// looks like and, once `InstagramRoom` shipped, could not compose its head
    /// at all: that card needs `minimumKept` kept posts across
    /// `minimumAccounts` accounts before it will claim a library exists.
    ///
    /// Four things it now carries deliberately, each exercising a branch that
    /// otherwise renders as the same silent nothing: kept posts with WORDS and
    /// a COVER (what `InstagramCaptions` produces, so the room draws post cards
    /// rather than handles), a wordless PHOTO post (the grid), a save tagged
    /// `Gone` (the head's footnote — the reading no service can make about your
    /// own library), and a `Reel` (the facet read off Meta's own permalink).
    private static func instagram() -> [Thing] {
        var out: [Thing] = [receipt("Instagram", "96 saved · 240 comments", days: 6)]
        let written: [(String, [String], Double)] = [
            ("Pastel de nata, finally right", ["Baking", "Lisbon"], 7),
            ("Sourdough at 78% hydration", ["Baking"], 14),
            ("Lisbon light in October", ["Lisbon", "Photography"], 21),
            ("Shot on the 35mm, no crop", ["Photography"], 29),
            ("Baking notes from the weekend", ["Baking"], 37),
            ("Photography walk, blue hour", ["Photography", "Lisbon"], 50),
        ]
        out += written.enumerated().map { i, w in
            row(.note, w.0, source: "Instagram", ref: "demo:ig:note:\(i)", days: w.2, hour: 19,
                content: w.0, tags: ["Post"]) { t in
                t.ocrTopics = w.1
                t.topicsAt = .now
                // The words the room's post card draws — `title` is only ever
                // the 80-character clamp.
                t.postText = w.0
                t.authorHandle = "you"
            }
        }
        // The wordless half: a photograph is a post with nothing to say, and
        // its pixels are what make it a grid tile rather than a row titled
        // "Photo" (`FeedScreen.isInstagramPhotoTile`).
        let photos: [(Double, Int)] = [(9, 0), (17, 1), (26, 2), (41, 3)]
        out += photos.enumerated().map { i, p in
            row(.note, "Photo", source: "Instagram", ref: "demo:ig:photo:\(i)",
                days: p.0, hour: 20, tags: ["Post", "Photo"]) { t in
                t.previewImageData = pixels(p.1)
                t.authorHandle = "you"
            }
        }
        // Fourteen kept posts across five accounts — over `minimumKept` and
        // `minimumAccounts`, so the head composes, and unevenly spread so the
        // board has a real shape rather than five equal bars.
        let saved: [(caption: String, handle: String, days: Double, reel: Bool)] = [
            ("Cafe with the marble counter", "lisboneats", 8, false),
            ("Studio shelf, all wood", "workspaces", 15, false),
            ("Ceramics, matte glaze", "studiokoto", 22, false),
            ("Bakery window at six", "lisboneats", 34, false),
            ("Desk setup, one lamp", "workspaces", 48, false),
            ("Thirty seconds on lamination", "lisboneats", 55, true),
            ("The tile shop nobody posts about", "lisboneats", 61, false),
            ("Two chairs, one window", "workspaces", 74, false),
            ("Wheel-thrown, trimmed wet", "studiokoto", 88, true),
            ("Blue hour over the bridge", "lightsonlisboa", 103, false),
            ("Pastry lamination, slowly", "lisboneats", 119, false),
            ("Kiln opening, third firing", "studiokoto", 140, false),
            ("Rooftop, no filter", "lightsonlisboa", 166, false),
            ("A shelf of nothing but bowls", "quietrooms", 190, false),
        ]
        out += saved.enumerated().map { (i, s) -> Thing in
            var tags = ["Saved"]
            if s.reel { tags.append("Reel") }
            // The two oldest are gone from Instagram — what the caption pass
            // records when a saved post answers 404 (prd §309), and the only
            // input to the head's footnote.
            if i >= saved.count - 2 { tags.append("Gone") }
            return row(.link, s.caption, source: "Instagram", ref: "demo:ig:save:\(i)",
                       days: s.days, hour: 23, content: "https://www.instagram.com/p/demo\(i)/",
                       tags: tags) { t in
                t.authorHandle = s.handle
                t.socialContext = "saved"
                // What `InstagramCaptions` leaves behind on a row it reached:
                // the post's own words on `postText`, its cover as bytes, and
                // the retrieval line. A `Gone` row keeps its handle and nothing
                // else, which is exactly what a 404 leaves you with.
                if !t.tags.contains("Gone") {
                    t.postText = s.caption
                    t.enrichedText = s.caption
                    t.previewImageData = pixels(i)
                }
            }
        }
        let liked: [(String, String, Double)] = [
            ("Every bench in the park, ranked", "quietrooms", 11),
            ("One pot, forty minutes", "lisboneats", 24),
            ("Shelf brackets that aren't ugly", "workspaces", 58),
        ]
        out += liked.enumerated().map { i, l in
            row(.link, l.0, source: "Instagram", ref: "demo:ig:like:\(i)",
                days: l.2, hour: 21, content: "https://www.instagram.com/p/demolike\(i)/",
                tags: ["Liked"]) { t in
                t.authorHandle = l.1
                t.socialContext = "liked"
                t.postText = l.0
                t.previewImageData = pixels(i)
            }
        }
        let comments: [(String, String, Double)] = [
            ("The crumb on this is unreal", "lisboneats", 12),
            ("Which glaze is that?", "studiokoto", 31),
        ]
        out += comments.enumerated().map { i, c in
            row(.note, "\(c.0) — on @\(c.1)", source: "Instagram",
                ref: "demo:ig:comment:\(i)", days: c.2, hour: 18,
                content: c.0, tags: ["Comment"])
        }
        return out
    }

    private static func tiktok() -> [Thing] {
        var out: [Thing] = [receipt("TikTok", "212 saved · 64 comments", days: 9)]
        let captions: [(String, [String], Double)] = [
            ("Two minutes on espresso ratios", ["Espresso", "Coffee"], 10),
            ("Grinder teardown, part one", ["Espresso"], 20),
            ("Coffee at altitude, why it tastes flat", ["Coffee"], 30),
            ("Espresso puck prep, honestly", ["Espresso", "Coffee"], 42),
        ]
        out += captions.enumerated().map { i, c in
            row(.link, c.0, source: "TikTok", ref: "demo:tt:post:\(i)", days: c.2, hour: 18,
                tags: ["Post"]) { t in
                t.ocrTopics = c.1
                t.topicsAt = .now
                t.authorHandle = "you"
                t.previewImageURL = art(i)
                t.likeCount = 300 - i * 40
            }
        }
        let comments: [(String, [String], Double)] = [
            ("Coffee this good is a bit unfair", ["Coffee"], 11),
            ("Espresso people are very serious", ["Espresso"], 25),
            ("Coffee on the trip was the highlight", ["Coffee", "Lisbon"], 36),
            ("Espresso machine finally arrived", ["Espresso"], 52),
        ]
        out += comments.enumerated().map { i, c in
            row(.note, c.0, source: "TikTok", ref: "demo:tt:comment:\(i)", days: c.2, hour: 21,
                content: c.0, tags: ["Comment"]) { t in
                t.ocrTopics = c.1
                t.topicsAt = .now
            }
        }
        let saved: [(String, String, Double)] = [
            ("Knife skills in 40 seconds", "@chefdaily", 12),
            ("One-pan dinner, no fuss", "@chefdaily", 19),
            ("Bike maintenance basics", "@fixitfast", 28),
            ("Rack organisation that lasts", "@fixitfast", 41),
        ]
        out += saved.enumerated().map { i, s in
            row(.link, s.0, source: "TikTok", ref: "demo:tt:save:\(i)", days: s.2, hour: 22,
                tags: ["Saved", "Liked"]) { t in
                t.authorHandle = s.1
                t.previewImageURL = art(i + 1)
            }
        }
        return out
    }

    /// Snapchat is the app's first MIXED room: memories draw as a grid,
    /// conversations as rows. The board ranks on `messageCount` — a stamped
    /// field, never the stored transcript's line count.
    private static func snapchat() -> [Thing] {
        var out: [Thing] = [receipt("Snapchat", "38 chats · 210 memories", days: 13)]
        let chats: [(String, Int, Double)] = [
            ("Sam", 4_820, 2), ("Mia", 2_140, 4), ("Dad", 960, 9),
            ("Climbing crew", 610, 16), ("Uma", 245, 30),
        ]
        out += chats.enumerated().map { i, c in
            row(.chat, c.0, source: "Snapchat", ref: "demo:snap:chat:\(i)", days: c.2, hour: 21,
                content: "Saved messages with \(c.0).", tags: ["Conversation"]) { t in
                t.authorHandle = c.0
                t.messageCount = c.1
            }
        }
        out += (0..<6).map { i in
            row(.file, "Memory", source: "Snapchat", ref: "demo:snap:memory:\(i)",
                days: Double(3 + i * 11), hour: 17, tags: ["Memory"]) { t in
                t.previewImageURL = art(i)
                t.previewImageData = pixels(i)
            }
        }
        return out
    }

    /// Telegram is the app's only room holding a LIVE drip and an IMPORT under
    /// one source (prd §456), so it is seeded as both — otherwise the demo
    /// shows half a room and the mixed shape never draws.
    ///
    /// **The channel posts carry the REAL live ref prefix**, not a `demo:` one.
    /// That is §349's lesson as a rule: `Corpus.arrivedLive` matches on
    /// `telegram:post:`, and it is what lets a followed channel's posts into
    /// the All feed while the imported half stays out — seed them under a
    /// demo prefix and the demo silently shows the wrong behaviour for the one
    /// thing this seat had to get right.
    private static func telegram() -> [Thing] {
        var out: [Thing] = [receipt("Telegram", "38 chats · 176 saved", days: 9)]

        // The live half: four followed channels, captioned posts and wordless
        // pictures, so the room draws its grid AND its post cards.
        let posts: [(String, String, String, Double, Bool)] = [
            ("durov", "Telegram now supports gifting a subscription to anyone in your contacts.", "Pavel Durov", 0.3, false),
            ("telegram", "AI Text Editor. The message bar now fixes grammar and translates inline.", "Telegram News", 1.2, false),
            ("tginfo", "", "Telegram Info", 2.1, true),
            ("durov", "A fully native Telegram app for Apple Watch is out.", "Pavel Durov", 3.4, false),
            ("telegram", "", "Telegram News", 5.0, true),
            ("tginfo", "Channels can now schedule posts up to a year ahead.", "Telegram Info", 7.5, false),
        ]
        out += posts.enumerated().map { i, p in
            row(.link, p.1.isEmpty ? "Photo" : p.1, source: "Telegram",
                ref: "telegram:post:demo-\(p.0)/\(1200 + i)",
                days: p.3, hour: 11,
                content: "https://t.me/\(p.0)/\(1200 + i)",
                tags: p.4 ? ["Photo"] : []) { t in
                t.authorHandle = p.2
                if !p.1.isEmpty { t.postText = p.1 }
                if p.4 { t.previewImageData = pixels(i) }
            }
        }

        // The imported half: Saved Messages — the pile of links you send
        // yourself, which is the strongest reason this seat exists.
        let saved: [(String, String, Double)] = [
            ("Kettlebell complexes for cyclists", "https://example.com/complexes", 1.6),
            ("Book: The Making of Prince of Persia", "https://example.com/prince", 4.2),
            ("Sourdough hydration, explained", "https://example.com/hydration", 8.8),
            ("Flight deal — Lisbon in March", "https://example.com/lisbon", 15.0),
        ]
        out += saved.enumerated().map { i, m in
            row(.link, m.0, source: "Telegram", ref: "telegram:saved:demo-\(9000 + i)",
                days: m.2, hour: 22, content: m.1, tags: ["Saved"]) { t in
                t.authorHandle = "Saved Messages"
            }
        }

        // And conversations, one thing each, ranked by `messageCount` exactly
        // as Snapchat's are.
        let chats: [(String, Int, Double)] = [
            ("Ada", 6_310, 0.8), ("Climbing crew", 2_480, 2.6),
            ("Mum", 1_140, 6.0), ("Flat admin", 305, 19.0),
        ]
        out += chats.enumerated().map { i, c in
            row(.chat, "Chat with \(c.0)", source: "Telegram",
                ref: "telegram:chat:demo-\(700 + i)", days: c.2, hour: 20,
                content: "Messages with \(c.0).", tags: ["Conversation"]) { t in
                t.authorHandle = c.0
                t.messageCount = c.1
            }
        }
        return out
    }

    /// YouTube leads with the topic map over its channels' own descriptions,
    /// and falls back to the wall of stills — both are seeded, so the chain's
    /// order is visible rather than assumed.
    private static func youtube() -> [Thing] {
        let videos: [(String, String, [String], Double)] = [
            ("How a compiler actually reads your code", "Computerphile", ["Compilers", "Systems"], 1),
            ("The physics of a good espresso shot", "James Hoffmann", ["Espresso", "Coffee"], 3),
            ("Systems that scale down", "Strange Loop", ["Systems"], 6),
            ("Compilers from scratch, part four", "Computerphile", ["Compilers"], 12),
            ("Coffee grinders, measured", "James Hoffmann", ["Coffee", "Espresso"], 18),
            ("Systems thinking for small teams", "Strange Loop", ["Systems", "Compilers"], 25),
            ("Espresso, but for filter drinkers", "James Hoffmann", ["Espresso"], 35),
            ("A tour of modern type systems", "Strange Loop", ["Compilers", "Systems"], 47),
        ]
        return videos.enumerated().map { i, v in
            row(.link, v.0, source: "YouTube", ref: "demo:yt:\(i)", days: v.3, hour: 20) { t in
                t.authorHandle = v.1
                t.postAuthor = v.1
                t.ocrTopics = v.2
                t.topicsAt = .now
                t.previewImageURL = art(i)
                t.enrichedText = "\(v.0) — \(v.2.joined(separator: ", "))"
            }
        }
    }

    /// A connected folder: healed images (grid + treemap) beside documents
    /// (rows). The image refs must satisfy `FilesIngest.isImageRef` or the
    /// room's map counts nothing and the pictures never draw.
    private static func files() -> [Thing] {
        var out: [Thing] = []
        let images: [(String, [String], Double)] = [
            ("Kitchen plan v3", ["Kitchen", "Plans"], 2),
            ("Hallway measurements", ["Kitchen", "Measurements"], 5),
            ("Shelf bracket spec", ["Plans", "Measurements"], 10),
            ("Kitchen tile samples", ["Kitchen", "Tiles"], 15),
            ("Plans — lighting run", ["Plans"], 23),
            ("Tiles, second batch", ["Tiles", "Kitchen"], 38),
        ]
        out += images.enumerated().map { i, f in
            row(.file, f.0, source: "Files", ref: "files:demo/\(f.0.lowercased().replacingOccurrences(of: " ", with: "-")).png",
                days: f.2, hour: 13, content: "\(f.0)\n\(f.1.joined(separator: " · "))") { t in
                t.ocrTopics = f.1
                t.topicsAt = .now
                t.previewImageData = pixels(i)
            }
        }
        let docs = [("Lease agreement.pdf", 7.0), ("Quote — joinery.pdf", 12.0), ("Notes.txt", 20.0)]
        out += docs.map { d in
            row(.file, d.0, source: "Files", ref: "files:demo/\(d.0)", days: d.1, hour: 16,
                content: "PDF · 1.2 MB")
        }
        return out
    }

    // MARK: Rooms that lead with a leaderboard

    /// A demo book's cover ref. Nil for a title with no generated spine —
    /// Kindle's books have none on purpose, since a My Clippings.txt import
    /// carries no cover and inventing one would show the demo doing something
    /// the real importer cannot.
    private static func bookCover(_ bookAndAuthor: String) -> String? {
        if bookAndAuthor.hasPrefix("Seeing Like a State") { return "sample:cover-state" }
        if bookAndAuthor.hasPrefix("The Timeless Way") { return "sample:cover-timeless" }
        if bookAndAuthor.hasPrefix("Thinking in Systems") { return "sample:cover-systems" }
        return nil
    }

    private static func reading() -> [Thing] {
        var out: [Thing] = []
        // Readwise / Kindle group on "Book — Author" in `content`.
        let highlights: [(String, String, Double)] = [
            ("Seeing Like a State — James C. Scott", "Legibility is the state's way of seeing.", 3),
            ("Seeing Like a State — James C. Scott", "Local knowledge resists the map.", 9),
            ("The Timeless Way — Christopher Alexander", "The quality has no name.", 14),
            ("The Timeless Way — Christopher Alexander", "Patterns are alive or they are dead.", 21),
            ("Thinking in Systems — Donella Meadows", "The system is what it does.", 28),
            ("Thinking in Systems — Donella Meadows", "Leverage points are counterintuitive.", 44),
        ]
        out += highlights.enumerated().map { i, h in
            row(.note, h.1, source: "Readwise", ref: "demo:readwise:\(i)", days: h.2, hour: 8,
                content: h.0) { t in
                // The book's cover, which the real bridge stamps from the
                // book `cover` field (2026-08-12) — keyed off the title so
                // the two highlights from one book share one spine.
                t.previewImageURL = bookCover(h.0)
                // The note you wrote under the highlight (2026-08-17).
                // `TokenBridges` stamps Readwise's `note` onto `summary` as
                // display copy; without it the demo's highlights were quotes
                // with nothing of yours attached, which is half of what a
                // read-later room is for.
                t.summary = "Why it stuck: \(h.0) says this better than I would."
            }
        }
        let kindle: [(String, String, Double)] = [
            ("Piranesi — Susanna Clarke", "The beauty of the house is immeasurable.", 4),
            ("Piranesi — Susanna Clarke", "The kindness of the sea is infinite.", 11),
            ("Project Hail Mary — Andy Weir", "Science is a process, not a fact.", 18),
            ("Project Hail Mary — Andy Weir", "Rocky reads the spectrometer.", 33),
            ("Piranesi — Susanna Clarke", "I am the beloved child of the house.", 49),
        ]
        out += kindle.enumerated().map { i, k in
            row(.note, k.1, source: "Kindle", ref: "demo:kindle:\(i)", days: k.2, hour: 22,
                content: k.0) { t in
                // The work, on `authorHandle` — where §366's importer stamps
                // it and where a room can rank it. `NoteSheetSource.citation`
                // still reads `content` as its legacy fallback, so the
                // `.passage` shape was reachable either way; stamping it
                // means the demo shows the era the app WRITES rather than the
                // older one it tolerates.
                t.authorHandle = k.0
                // §366's importer stamps a passage's note onto `summary`, and
                // the demo set none — so the room showed passages with no
                // reader in them (2026-08-17).
                t.summary = "Marked while reading \(k.0)."
            }
        }
        // Substack and RSS lead with the BYLINE (`postAuthor`) when enough
        // items name one, and fall back to the publication (`authorHandle`).
        let substack: [(String, String, String, Double)] = [
            ("The case for small software", "Anna Reid", "Small Things", 2),
            ("What a good changelog says", "Anna Reid", "Small Things", 8),
            ("Notes on interface latency", "Ben Ito", "Latency Club", 13),
            ("Latency is a feature", "Ben Ito", "Latency Club", 20),
            ("Writing for people who skim", "Cara Vale", "Small Things", 31),
            ("The end of the settings screen", "Cara Vale", "Latency Club", 46),
        ]
        out += substack.enumerated().map { i, s in
            row(.link, s.0, source: "Substack", ref: "demo:substack:\(i)", days: s.3, hour: 7) { t in
                t.postAuthor = s.1
                t.authorHandle = s.2
                t.authorAvatarURL = publisherArt(s.2)
                t.previewImageURL = art(i)
                t.enrichedText = "\(s.0) — by \(s.1) in \(s.2)."
            }
        }
        // A FEED SYNC LANDS SEVERAL AT ONCE — three on day 4 (2026-08-17). RSS
        // is the most bundleable source in the corpus and the demo laid every
        // article on its own day, so the one source most likely to fold in real
        // use never did. Day 4, not day 1 or 2: the social rooms fold on those,
        // and three sources folding on one day reads as a staged burst rather
        // than a week of ordinary use.
        let rss: [(String, String, String, Double)] = [
            ("A quieter approach to notifications", "Dana Cole", "The Verge", 1),
            ("Inside a very small compiler", "Eli Rosen", "Hacker News", 4),
            ("The return of local-first", "Dana Cole", "The Verge", 4),
            ("Type systems, plainly", "Eli Rosen", "Hacker News", 4),
            ("Why your app feels slow", "Dana Cole", "TechCrunch", 24),
            ("The cost of a background sync", "Fay Ng", "TechCrunch", 32),
            ("Local-first, one year on", "Fay Ng", "The Verge", 41),
        ]
        out += rss.enumerated().map { i, r in
            row(.link, r.0, source: "RSS", ref: "demo:rss:\(i)", days: r.3,
                hour: 6 + (i % 3)) { t in
                t.postAuthor = r.1
                t.authorHandle = r.2
                t.authorAvatarURL = publisherArt(r.2)
                t.previewImageURL = art(i)
                t.enrichedText = "\(r.0) — \(r.2)."
                // The item's own paragraph, as DISPLAY copy (2026-08-17).
                // `RSSIngest` stamps the feed's `<summary>` onto `Thing.summary`
                // — text the publisher wrote and handed us, which is exactly
                // that field's contract, and distinct from the `enrichedText`
                // above, which is retrieval-only and reaches no screen. Without
                // it the demo's reading room showed headlines where the app
                // shows a headline and a sentence.
                t.summary = "\(r.1) on \(r.0.lowercased()) — what changed, "
                    + "what it costs, and who it is actually for."
            }
        }
        return out
    }

    private static func listening() -> [Thing] {
        var out: [Thing] = []
        // Music groups on "Song — Artist" in the TITLE.
        let spotify: [(String, Double)] = [
            ("Weightless — Marconi Union", 1), ("Motion — Kiasmos", 2),
            ("Blue — Kiasmos", 5), ("Lull — Marconi Union", 9),
            ("Swept — Kiasmos", 13), ("Distance — Nils Frahm", 19),
            ("Says — Nils Frahm", 27), ("Ode — Marconi Union", 36),
        ]
        out += spotify.enumerated().map { i, s in
            row(.link, s.0, source: "Spotify", ref: "demo:spotify:\(i)", days: s.1, hour: 18) { t in
                t.previewImageURL = art(i)
                // `SpotifyBridge` stamps the show's own description onto
                // `summary` (2026-08-17) — the sentence that says what an
                // episode IS, which a track title never does.
                t.summary = "\(s.0) — the episode's own description, as the "
                    + "publisher wrote it."
            }
        }
        let music: [(String, Double)] = [
            ("Reckoner — Radiohead", 3), ("Nude — Radiohead", 7),
            ("Teardrop — Massive Attack", 12), ("Angel — Massive Attack", 22),
            ("Svefn-g-englar — Sigur Rós", 30), ("Hoppípolla — Sigur Rós", 43),
        ]
        out += music.enumerated().map { i, m in
            row(.link, m.0, source: "Apple Music", ref: "demo:music:\(i)", days: m.1, hour: 8) { t in
                t.previewImageURL = art(i + 2)
            }
        }
        let shows: [(String, String, Double)] = [
            ("The one about compilers", "Signals and Threads", 2),
            ("Latency, end to end", "Signals and Threads", 11),
            ("Making things for two people", "Design Details", 5),
            ("The shape of a good demo", "Design Details", 17),
            ("Coffee, measured", "Filter Stories", 25),
            ("Roasting at altitude", "Filter Stories", 39),
        ]
        out += shows.enumerated().map { i, s in
            row(.link, s.0, source: "Podcasts", ref: "demo:podcast:\(i)", days: s.2, hour: 7) { t in
                t.authorHandle = s.1
                t.previewImageURL = art(i)
            }
        }
        let steam: [(String, Double, Double)] = [
            ("Factorio", 6.4, 1), ("Balatro", 3.1, 2), ("Outer Wilds", 2.2, 4),
            ("Slay the Spire", 1.4, 8), ("Tunic", 0.8, 12),
        ]
        out += steam.enumerated().map { i, g in
            // "Played <game>" is the shape `SteamBridge` lands (2026-08-12),
            // with the game itself on `authorHandle` — the row's trailing
            // slot, and the join key MediaMoments reads. The demo titled rows
            // with the bare game name, so the sentence the real room reads as
            // an ACTIVITY read here as a catalogue entry.
            row(.link, "Played \(g.0)", source: "Steam", ref: "demo:steam:\(i)",
                days: g.2, hour: 23,
                content: "Recently played · \(String(format: "%.1f", g.1))h in the last two weeks") { t in
                t.previewImageURL = art(i)
                t.authorHandle = g.0
            }
        }
        return out
    }

    private static func mail() -> [Thing] {
        var out: [Thing] = []
        let gmail: [(String, String, Double)] = [
            ("Design review moved to Thursday", "Uma Patel <uma@studio.example>", 1),
            ("Re: joinery quote", "Nils Berg <nils@joinery.example>", 2),
            ("Your October statement", "Statements <no-reply@bank.example>", 4),
            ("Re: Lisbon dates", "Sam Ellis <sam@example.com>", 6),
            ("Uma shared a file with you", "Uma Patel <uma@studio.example>", 10),
            ("Re: joinery quote (v2)", "Nils Berg <nils@joinery.example>", 16),
        ]
        out += gmail.enumerated().map { i, m in
            row(.mail, m.0, source: "Gmail", ref: "demo:gmail:\(i)", days: m.2, hour: 9,
                content: "Thanks — see the thread for the details.") { t in
                t.authorHandle = m.1
            }
        }
        let icloud: [(String, String, Double)] = [
            ("Your receipt from the hardware store", "Receipts <receipts@shop.example>", 3),
            ("Flight TAP 1147 — check in now", "TAP Air <noreply@flytap.example>", 5),
            ("Book club — October pick", "Mia Rowe <mia@example.com>", 9),
            ("Re: book club", "Mia Rowe <mia@example.com>", 14),
            ("Your order has shipped", "Receipts <receipts@shop.example>", 21),
        ]
        out += icloud.enumerated().map { i, m in
            row(.mail, m.0, source: "iCloud Mail", ref: "demo:icloud:\(i)", days: m.2, hour: 11,
                content: "Opened on this device.") { t in
                t.authorHandle = m.1
            }
        }
        return out
    }

    private static func saves() -> [Thing] {
        var out: [Thing] = []
        // Reddit groups on the subreddit; Raindrop on the saved URL's host.
        let reddit: [(String, String, Double)] = [
            ("The espresso machine that lasted 20 years", "r/espresso", 1),
            ("Puck prep, settled", "r/espresso", 6),
            ("What I learned rewriting our sync layer", "r/programming", 3),
            ("A small compiler in 400 lines", "r/programming", 12),
            ("Lisbon in three days — what worked", "r/travel", 8),
            ("Tram 28 is a trap (kind of)", "r/travel", 20),
        ]
        out += reddit.enumerated().map { i, r in
            row(.link, r.0, source: "Reddit", ref: "demo:reddit:\(i)", days: r.2, hour: 22) { t in
                t.authorHandle = r.1
                t.previewImageURL = art(i)
            }
        }
        let raindrop: [(String, Double)] = [
            ("https://developer.apple.com/design/human-interface-guidelines", 2),
            ("https://developer.apple.com/documentation/swiftui", 7),
            ("https://github.com/apple/swift-evolution", 11),
            ("https://github.com/swiftlang/swift/blob/main/README.md", 19),
            // A real, stable page — not `example.com` (2026-08-08, P4): every
            // OTHER row in this array is a real doc URL whose title is
            // DERIVED from the URL's own last path component, so the fix
            // has to be a real matching page, not a dropped link (dropping it
            // would leave `URL(string:)?.lastPathComponent` with nothing to
            // read and the row with no title at all).
            ("https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_scroll-driven_animations", 26),
            ("https://developer.apple.com/documentation/swiftdata", 34),
        ]
        // Raindrop stamps the save's own TYPE and tags, and its excerpt on
        // `summary` (2026-08-12) — the sheet renders that excerpt, and the
        // type is what makes a Raindrop room filterable at all. The demo
        // carried neither, so every save was an untyped, untagged, wordless
        // link where the real room shows what kind of thing it saved.
        let raindropTags = [["Article", "Design"], ["Article", "SwiftUI"], ["Document"],
                            ["Document"], ["Article", "CSS"], ["Article", "SwiftUI"]]
        let raindropNotes = [
            "The platform conventions, in one place.",
            "Declarative views, state and layout.",
            "Every accepted proposal, with its rationale.",
            "Building the toolchain from source.",
            "Animations driven by scroll position rather than time.",
            "Persistence with the model layer Swift already knows.",
        ]
        out += raindrop.enumerated().map { i, u in
            row(.link, URL(string: u.0)?.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized ?? "Saved link",
                source: "Raindrop", ref: "demo:raindrop:\(i)", days: u.1, hour: 15,
                content: u.0, tags: raindropTags[i % raindropTags.count]) { t in
                t.summary = raindropNotes[i % raindropNotes.count]
                // The saved page's cover (2026-08-17). `RaindropBridge` stamps
                // the bookmark's own `cover` and its media list, and the demo
                // set neither — so a room of saved ARTICLES drew as a column
                // of bare titles, which is the §313 X finding one room over.
                t.previewImageURL = art(i)
                if i % 3 == 0 { t.imageURLs = [art(i), art(i + 1)] }
            }
        }
        let bookmarks: [(String, String, Double)] = [
            ("Human Interface Guidelines", "https://developer.apple.com/design", 5),
            ("Swift concurrency notes", "https://github.com/apple/swift-evolution", 13),
            // No real page named "The grid system" exists to link — title
            // and URL are independent fields here, unlike `raindrop` above,
            // so the P4 fix is to drop the URL rather than invent a match.
            ("The grid system", "", 29),
        ]
        out += bookmarks.enumerated().map { i, b in
            row(.link, b.0, source: "Bookmarks", ref: "demo:bookmarks:\(i)", days: b.2, hour: 12,
                content: b.1)
        }
        let pinterest: [(String, Double)] = [
            ("Kitchen — open shelving", 4), ("Studio — one lamp", 9),
            ("Ceramics — matte glaze", 15), ("Hallway — narrow bench", 23),
            ("Kitchen — tile grid", 31), ("Studio — cork board", 44),
        ]
        out += pinterest.enumerated().map { i, p in
            row(.link, p.0, source: "Pinterest", ref: "demo:pin:\(i)", days: p.1, hour: 21) { t in
                t.previewImageURL = art(i)
            }
        }
        return out
    }

    // MARK: Social — posts, and the channel treemap the panel draws

    /// `channelName` has been stamped on every cast since §81 and nothing drew
    /// it until the panel did; two channels minimum or the treemap declines.
    /// The cast a demo cast is replying UNDER, for the handful that reply.
    /// No `url`/`ref`: `ReplyingToRow` draws the handle and the words, and a
    /// fabricated `fc:<hash>` would make the sheet offer to walk a thread
    /// that does not exist (P4 — a door that opens on nothing).
    private static func castParent(_ i: Int) -> SocialCard? {
        switch i {
        case 1: SocialCard(handle: "you",
                           text: "Shipped the panel today. Every room's figure in one place.",
                           avatarURL: avatarArt("you"))
        case 4: SocialCard(handle: "sam", text: "Onchain receipts, but for what exactly?",
                           avatarURL: avatarArt("sam"))
        default: nil
        }
    }

    /// The cast a demo cast QUOTES. Same no-permalink rule as `castParent`.
    private static func castQuote(_ i: Int) -> SocialCard? {
        switch i {
        case 3: SocialCard(handle: "mia",
                           text: "Most product demos show a screen nobody has ever had.",
                           avatarURL: avatarArt("mia"))
        default: nil
        }
    }

    /// A demo vault note's body — long enough that the sheet's word count and
    /// read-time reading behave the way they do on a real note (over
    /// `NoteSheet.readTimeFloor`), and written as notes actually are: a claim,
    /// what it rests on, and what to do next. Wikilinks are deliberately
    /// present — a vault's neighbours are written in everybody else's text,
    /// and `[[…]]` is what `ObsidianNote` reads them out of.
    private static func vaultBody(title: String, tags: [String]) -> String {
        let neighbours = tags.map { "[[\($0)]]" }.joined(separator: " · ")
        // Paragraphs are single lines on purpose. A `"""` block with `\`
        // continuations keeps the TRAILING whitespace of the line before the
        // backslash, which rendered as gaps in the middle of sentences —
        // visible only once the note was actually drawn, never in the source.
        let paragraphs = [
            "The thing I keep relearning is that a note is only worth keeping if it says what it is FOR. A title that names a topic gives me nothing back six weeks later; a title that names a decision does. So the rule now is one claim per note, in the first line, in words I would say out loud.",
            "What this rests on: three weeks of writing them the other way, and finding I re-read almost none of it. The ones I did come back to were the ones that had already committed to something — where past me had taken the argument far enough to be wrong in a useful way.",
            "The failure I want to avoid is the tidy vault nobody reads. Structure is cheap to add and expensive to maintain, and every folder I have made so far has outlived its reason by months. Links do the same work and cost nothing when they turn out to be wrong.",
            "Next: go back through the last month and rewrite the titles that name a topic instead of a claim. Anything I cannot restate as a claim is a note I did not need.",
            "Related: \(neighbours)",
        ]
        return ([title] + paragraphs).joined(separator: "\n\n")
    }

    private static func social() -> [Thing] {
        var out: [Thing] = []
        // NEW FOLLOWERS — the `.person` sheet anatomy (prd §363, 2026-08-12).
        // `SocialSheet.shape` returns `.person` for exactly one condition,
        // `socialContext == "follow"`, and no demo row carried it — so the
        // one anatomy whose whole point is that a follower is A PERSON and
        // not a link to one could not be reached in the demo at all. Landed
        // by `SocialInbound.landFollower` in the real app (§239).
        //
        // The handles are ones the demo already POSTS as, so the sheet's
        // "their recent posts" section (`SocialSheetSource.recentPosts`) has
        // something real to find — a person card with an empty shelf under it
        // is the emptiest possible version of this shape.
        //
        // NO profile URL in `content` (P4): these handles are short and
        // plausible, so a real `bsky.app/profile/uma` would open a stranger's
        // page. The `.person` branch never reads `content` — it draws from
        // `authorHandle` and `authorAvatarURL` — so the field costs nothing
        // to leave empty and a dead door costs the demo its credibility.
        let followers: [(handle: String, name: String, source: String, days: Double)] = [
            ("sam", "Sam", "Farcaster", 2),
            ("uma", "Uma", "Bluesky", 5),
        ]
        out += followers.map { f in
            row(.link, "\(f.name) (@\(f.handle)) started following you",
                // `demo:` ref, not the real `<source>:follower:<id>` shape:
                // nothing anywhere PARSES a follower ref (it exists purely
                // for `SocialInbound`'s dedupe set), so joining that
                // namespace would buy nothing and cost teardown — only
                // `refPrefixes` entries are removed on demo exit.
                source: f.source, ref: "demo:follower:\(f.handle)",
                days: f.days, hour: 11) { t in
                t.authorHandle = f.handle
                t.authorAvatarURL = avatarArt(f.handle)
                t.socialContext = "follow"
            }
        }
        let casts: [(String, String, String, Int, Double)] = [
            // THREE ON ONE DAY, AND THAT IS THE POINT (2026-08-17). Measured
            // over the poured demo: 380 rows in the All feed, of which 378 were
            // plain singles — `strip=0`, so §377's fold-into-members had never
            // once drawn on the room the demo OPENS ON. The cause was not the
            // fold, which works; it was these dates. `FeedFold.decide` needs
            // `bundleThreshold` (3) rows of ONE source on ONE day, and the
            // demo laid every cast on a separate day, so no run could ever
            // exist. Real use arrives in bursts — an afternoon of posting, a
            // sync landing twenty articles at once — and a corpus spread
            // perfectly evenly is the one shape that can never fold.
            //
            // Distinct hours within the day, not one repeated: identical
            // timestamps tie the sort, and a run whose order changes between
            // renders is the reshuffling this codebase already refuses
            // elsewhere.
            ("Shipped the panel today. Every room's figure in one place.", "/design", "you", 32, 1),
            ("A chart of everything at once is a chart of nothing.", "/design", "mia", 21, 1),
            ("Reading about legibility again.", "/books", "you", 9, 1),
            ("The best demo is a real one.", "/design", "sam", 44, 10),
            ("Onchain receipts are underrated.", "/base", "mia", 12, 14),
            ("Books that changed how I plan.", "/books", "you", 7, 22),
            ("Base fees are basically nothing now.", "/base", "sam", 15, 30),
        ]
        out += casts.enumerated().map { i, c in
            row(.chat, c.0, source: "Farcaster", ref: "demo:fc:\(i)", days: c.4,
                hour: 13 - (i % 4)) { t in
                t.postText = c.0
                t.channelName = c.1
                t.authorHandle = c.2
                t.authorAvatarURL = avatarArt(c.2)
                t.likeCount = c.3
                t.replyCount = i % 4
                t.repostCount = i % 3
                // WHAT A CAST REPLIES TO AND WHAT IT QUOTES (2026-08-12).
                // `FarcasterIngest` stamps `parent` and `quote` — and
                // CLAUDE.md's own note on this bridge says nearly every cast
                // it lands has one or the other, because channel casts,
                // mentions and likes are mostly replies. The demo had
                // neither on any row, so `ReplyingToRow` and
                // `SocialQuoteCard` — two of the room's most distinctive
                // pieces — never drew once. Sparse rather than on every row:
                // a column where every entry quotes something reads as
                // noise, and the point is that the shapes EXIST.
                if let card = castParent(i) { t.parent = card }
                if let card = castQuote(i) { t.quote = card }
                // A cast's own pictures — the bundled photos, since a post
                // attachment is a photograph, not a generated card. BOTH
                // paths are exercised on purpose: `PostCard` draws a SINGLE
                // image from `previewImageURL` (`PostMedia`) and only
                // switches to `PostImageGrid` at two or more, so seeding one
                // array of one would have drawn nothing at all — the array
                // branch requires `count > 1` and the fallback reads a field
                // that was never set.
                if i == 0 { t.previewImageURL = art(0) }
                if i == 5 {
                    t.previewImageURL = art(1)
                    t.imageURLs = [art(1), art(2)]
                }
            }
        }
        let posts: [(String, String, Int, Double)] = [
            // Clustered onto one day for the cast block's reason above — this
            // room needs a run of its own or it can never fold either, and the
            // two social rooms folding on DIFFERENT days is what keeps the feed
            // from reading as one synthetic burst.
            ("Small software, made carefully.", "you", 18, 2),
            ("The panel draws only figures. No sentences.", "uma", 26, 2),
            ("Espresso and compilers, the eternal pairing.", "nils", 11, 2),
            ("Local-first is just software that respects you.", "you", 33, 12),
            ("Notes from a quiet week.", "uma", 6, 19),
            ("Reading, mostly.", "nils", 4, 27),
        ]
        out += posts.enumerated().map { i, p in
            row(.chat, p.0, source: "Bluesky", ref: "demo:bsky:\(i)", days: p.3,
                hour: 16 - (i % 3),
                content: "at://did:plc:demo/app.bsky.feed.post/\(i)") { t in
                t.postText = p.0
                t.authorHandle = p.1
                t.authorAvatarURL = avatarArt(p.1)
                t.likeCount = p.2
                t.channelName = i % 2 == 0 ? "Design" : "Reading"
                t.replyCount = i % 3
                // EVERYTHING FARCASTER GOT ON 2026-08-12, WHICH BLUESKY DID
                // NOT (2026-08-17). The two rooms share one renderer
                // (`SocialBridge`, `PostCard`) and `BlueskyIngest` stamps every
                // field below — `imageURLs`/`previewImageURL` at its post
                // hydration, `quote` and `parent` beside them — so the demo's
                // Bluesky room drew flat text rows next to a Farcaster room
                // full of replies, quotes and pictures. Same shape, visibly
                // poorer, and nothing could see it: both rooms render
                // perfectly, and every other demo check looks at a different
                // question.
                //
                // Sparse rather than on every row, for the reason the cast
                // block already gives: a column where every entry quotes
                // something reads as noise, and the point is that the shapes
                // EXIST.
                t.repostCount = i % 4
                if i == 1 {
                    t.parent = SocialCard(handle: "you",
                                          text: "Small software, made carefully.",
                                          avatarURL: avatarArt("you"))
                }
                if i == 3 {
                    t.quote = SocialCard(handle: "nils",
                                         text: "Espresso and compilers, the eternal pairing.",
                                         avatarURL: avatarArt("nils"))
                }
                // BOTH picture paths, the cast block's own lesson: `PostCard`
                // draws a SINGLE image from `previewImageURL` and only switches
                // to `PostImageGrid` at two or more, so one array of one would
                // have drawn nothing at all.
                if i == 2 { t.previewImageURL = art(2) }
                if i == 4 {
                    t.previewImageURL = art(3)
                    t.imageURLs = [art(3), art(0)]
                }
            }
        }
        // An article somebody SHARED, which is a different row from a post
        // about one (2026-08-17). `BlueskyIngest.landLinkedArticle` lands a
        // post's external card as its own `.link` thing carrying the card's
        // thumbnail and — uniquely on this bridge — the publisher's own
        // paragraph on `summary`, which is display copy rather than the
        // retrieval-only `enrichedText`. In `.social` a `.link` is an article a
        // post shared and draws as a `ReadingRow`, so without one the demo's
        // Bluesky room had no reading shape at all.
        //
        // A `demo:` ref rather than the bridge's own `link:<url>`: nothing
        // anywhere PARSES that ref (it exists purely for `landLinkedArticle`'s
        // dedupe set), so joining its namespace would buy nothing and cost
        // teardown — only `refPrefixes` entries are removed on demo exit. The
        // follower rows above make the same call for the same reason.
        out.append(row(.link, "The quiet case for local-first software",
                       source: "Bluesky", ref: "demo:bskylink:0", days: 7, hour: 9,
                       content: "https://example.com/local-first") { t in
            t.authorHandle = "uma"
            t.authorAvatarURL = avatarArt("uma")
            t.previewImageURL = art(1)
            t.summary = "Why software that keeps your data on your own machine "
                + "ends up feeling faster, calmer and more yours."
        })
        // Three voices, not one (2026-08-12). Every Nostr row was authored by
        // "you", so the room read as a private notebook where the other two
        // social rooms read as networks — and `NostrStore.accounts`, which the
        // face rail and the roster both walk, was never seeded at all, so the
        // rail could not draw whatever the rows said.
        let nostr: [(text: String, handle: String, days: Double)] = [
            ("Relays are just people who agreed to keep talking.", "you", 3),
            ("Signed, not hosted. That is the whole idea.", "uma", 12),
            ("A quiet week on the relays, which is the good kind.", "nils", 21),
        ]
        out += nostr.enumerated().map { i, n in
            row(.chat, n.text, source: "Nostr",
                ref: "demo:nostr:\(i)", days: n.days, hour: 20,
                content: "nostr:note1demo\(i)") { t in
                t.postText = n.text
                t.authorHandle = n.handle
                t.authorAvatarURL = avatarArt(n.handle)
                // The same five fields Bluesky was missing (2026-08-17), for
                // the same reason: `NostrIngest` stamps `channelName` (the
                // note's hashtag), both picture fields, `quote` and `parent`,
                // and this room had none of them — so the third social room
                // read plainer than the two beside it while sharing their
                // renderer. Sparse, per the cast block's ruling.
                t.channelName = ["design", "bitcoin", "reading"][i % 3]
                t.likeCount = 14 - i * 3
                if i == 1 {
                    t.parent = SocialCard(handle: "you",
                                          text: "Relays are just people who agreed to keep talking.",
                                          avatarURL: avatarArt("you"))
                }
                if i == 2 {
                    t.quote = SocialCard(handle: "uma",
                                         text: "Signed, not hosted. That is the whole idea.",
                                         avatarURL: avatarArt("uma"))
                    // Both picture paths, the cast block's lesson again:
                    // `PostCard` draws one from `previewImageURL` and only
                    // reaches `PostImageGrid` at two or more.
                    t.previewImageURL = art(0)
                    t.imageURLs = [art(0), art(2)]
                }
                if i == 0 { t.previewImageURL = art(3) }
            }
        }
        return out
    }

    // MARK: Markets — the mood rail, the watchlists, the browse rooms

    private static func markets() -> [Thing] {
        var out: [Thing] = []
        let mood: [(String, String, String, Double)] = [
            ("NVDA looks extended here", "NVDA", "Bearish", 1),
            ("Adding on any dip", "NVDA", "Bullish", 1.2),
            ("Earnings setup is clean", "AAPL", "Bullish", 2),
            ("Not touching this until it bases", "AAPL", "Bearish", 2.4),
            ("Volume finally showing up", "AAPL", "Bullish", 4),
            ("Sideways for weeks now", "TSLA", "", 5),
            ("Watching the 200d", "TSLA", "", 7),
            ("This is the long-term hold", "NVDA", "Bullish", 9),
        ]
        // The WATCHED TICKERS (2026-08-12). Stocktwits' primary rows are the
        // watches themselves — `StockWatch.watch` lands one `.link`
        // thing per symbol, titled `"\(company) · $\(TICKER)"`, and
        // `StocktwitsScreen` builds its whole watchlist by filtering on that
        // ref prefix. The demo seeded only the POSTS, so the room was a wall
        // of chat with nothing being watched, and the setup screen's
        // watchlist was empty on a "connected" bridge.
        //
        // Real refs, spelled through `StockWatch`s own builder — and listed in
        // `refPrefixes` as EXACT refs rather than the bare
        // "stocktwits:sym:" prefix, so demo exit can never delete a real
        // watch (the `PostHogWatch.metricRef` reasoning, same hazard).
        let tickers: [(company: String, symbol: String, watchedAt: Double, days: Double)] = [
            ("Apple Inc", "AAPL", 214.60, 6),
            ("NVIDIA Corp", "NVDA", 118.20, 8),
            ("Tesla Inc", "TSLA", 246.90, 11),
        ]
        out += tickers.map { t in
            row(.link, "\(t.company) · $\(t.symbol)", source: "Stocktwits",
                ref: StockWatch.symbolRef(t.symbol), days: t.days, hour: 10,
                tags: [t.symbol]) { thing in
                thing.watchPriceUsd = t.watchedAt
                // The company's own mark, which the bridge stamps
                // (2026-08-17) — without it every watched stock wore the
                // source glyph and the watchlist read as one repeated icon.
                thing.previewImageURL = "sample:coin-\(t.symbol.lowercased())"
            }
        }
        out += mood.enumerated().map { i, m in
            row(.chat, m.0, source: "Stocktwits", ref: "demo:stocktwits:\(i)",
                days: m.3, hour: 15, content: "$\(m.1) · \(m.0)",
                tags: m.2.isEmpty ? [m.1] : [m.1, m.2]) { t in
                t.authorHandle = "@trader\(i % 3)"
                t.authorAvatarURL = avatarArt("trader\(i % 3)")
                t.postText = m.0
            }
        }
        // No dexscreener content URL on any row here (P4, 2026-08-07) — this
        // is sharper than the usual dead-door case: `TokenChart.route(from:)`
        // does NO validation, it blindly reads `pathComponents[0]`/`[1]` off
        // any URL whose host contains "dexscreener.com". A fabricated
        // `/base/demo0` path parses clean as `chain: "base", address:
        // "demo0"`, and `ThingChart.kind(for:)` would hand that straight to
        // `TokenChartContent`, which fetches a LIVE price curve for that
        // bogus address the moment the row is opened — a real network call
        // for garbage data, on the sheet's PRIMARY content, and one that
        // `BridgeRefresh`'s demo gate can't see because it's a per-view
        // on-open fetch, not part of the foreground sweep. Dropping the
        // content URL means `route(from:)`'s host check fails and nothing is
        // ever attempted. `TokenPulse.seedDemo` (2026-08-11) is what gives
        // these rows a sparkline/price/chart instead — a synthetic in-memory
        // pulse, never a URL, so it can never trigger a fetch either.
        // Title format is LOAD-BEARING, not cosmetic (2026-08-12).
        // `TokenWatch` lands `"\(name) · $\(symbol)"` and `TokensAsk`
        // .name/.symbol is the format's one parser — it splits on the literal
        // " · $". The demo's old "Ethereum (ETH)" matched nothing, so
        // `symbol(of:)` returned the WHOLE title, `TokenRow.vitals` read that
        // as "no symbol", and every row lost its second line while the first
        // rendered the ticker inline as "(ETH)". The logo is the same story:
        // the real bridge stamps `previewImageURL`, and without it the row
        // and the watchlist roster both fall back to the Tokens source glyph.
        out += tokenSeeds.enumerated().map { i, t in
            row(.link, "\(t.name) · $\(t.symbol)", source: "Tokens", ref: "demo:token:\(i)",
                days: t.dayOffset, hour: 12) { thing in
                thing.watchPriceUsd = t.price
                thing.previewImageURL = "sample:token-\(t.symbol.lowercased())"
            }
        }
        // GeckoTerminal lands TRENDING TOKENS, not chain summaries (2026-08-12).
        // The old rows were titled "Trending on Base" / "Trending on Solana",
        // which is not a shape this bridge has ever produced: `GeckoTrending`
        // lands one row per token, titled `"\(name) · $\(symbol)"`, tagged
        // "Trending", carrying the token's logo — so the demo room read as a
        // list of three chains where the real one is a list of coins. Same
        // title format as `TokenWatch` (see `tokenSeeds`), so `TokensAsk`'s
        // one parser splits these too.
        // Clustered, not one per day: `GeckoTrending` stamps `capturedAt:
        // .now` on every token in a pass, so a real room shows them together
        // under one heading. Spread across three days they drew three
        // one-row day sections separated by empty space.
        // SYMBOLS THIS APP ALREADY SHIPS A MARK FOR (2026-08-26). The third
        // row was Brett, whose logo is bundled nowhere, so it drew a generated
        // monogram beside two more — the room read as three coloured letters
        // where a real trending list is three logos. Curve is on Ethereum, so
        // the three still span the seat's three demo chains (Base, Solana,
        // Ethereum) and no two share one.
        let trending: [(name: String, symbol: String, days: Double, price: Double)] = [
            ("Aerodrome", "AERO", 0.2, 0.82),
            ("Curve DAO", "CRV", 0.3, 0.61),
            ("Jupiter", "JUP", 0.45, 0.47),
        ]
        out += trending.map { t in
            row(.link, "\(t.name) · $\(t.symbol)", source: "GeckoTerminal",
                ref: "demo:gecko:\(t.symbol.lowercased())", days: t.days, hour: 14,
                tags: ["Trending"]) { thing in
                thing.previewImageURL = "sample:coin-\(t.symbol.lowercased())"
                // THE PRICE AS DATA, not as words (2026-08-17) — the same
                // ruling the Shopify drops already carry. `GeckoTrending`
                // stamps `priceValue`/`priceCurrency`, which is what
                // `ThingContent.productPrice` reads to draw the figure as the
                // sheet's own heading; carried only in the title, that branch
                // takes its nil path and the sheet falls through to the small
                // grey fallback line.
                thing.priceValue = t.price
                thing.priceCurrency = "USD"
            }
        }
        let drops: [(String, Double)] = [
            ("Terraforms by Mathcastles", 2), ("Opepen Edition", 5),
            ("Checks — VV Edition", 9), ("Blocks of Base", 16),
        ]
        out += drops.enumerated().map { i, d in
            row(.link, d.0, source: "OpenSea", ref: "demo:opensea:\(i)", days: d.1, hour: 19) { t in
                t.previewImageURL = art(i)
                // The collection's own blurb, which `OpenSeaBridge` stamps
                // onto `summary` (2026-08-17). It is the only thing that
                // distinguishes one drop's name from another's.
                t.summary = "\(d.0) — a new collection, described by its own "
                    + "creator on the marketplace."
            }
        }
        // The price is STRUCTURED here, not just words in `content`
        // (2026-08-12). `ThingContent.productPrice` reads `priceValue` +
        // `priceCurrency` and renders the formatted figure as the sheet's
        // own heading — `ShopifyBridge` stamps both, so a real drop's sheet
        // leads with a bold "€48.00". The demo carried the price only as
        // display text, which took that branch's nil path: the sheet fell
        // through to the small grey fallback line and no product in the
        // demo ever showed a price the way the app shows one.
        let arrivals: [(String, String, Double, Double)] = [
            ("Linen apron — natural", "€48", 1, 48), ("Cast iron pan, 26cm", "€72", 3, 72),
            ("Ceramic mug, set of two", "€34", 6, 34), ("Oak chopping board", "€55", 12, 55),
        ]
        out += arrivals.enumerated().map { i, a in
            row(.product, a.0, source: "Shopify", ref: "demo:shopify:\(i)", days: a.2, hour: 17,
                content: a.1) { t in
                t.priceValue = a.3
                t.priceCurrency = "EUR"
                t.authorHandle = "Small Things"
                // A product STILL, not `art(i)` (2026-08-11). That one hands
                // back the four bundled sample photos, so every product wore
                // a stock shot of a person in a luchador mask — reported from
                // the room itself, and the §83 rule in picture form: the row's
                // words were right and its image contradicted them.
                //
                // Not left blank either, though that was the first fix:
                // `ThingContent`'s `.product` case leads with this image and
                // says in its own comment that it does "the work of not
                // leaving the sheet blank". An honest blank is still a blank.
                t.previewImageURL = productArt(i + 1)
                t.priceValue = Double(40 + i * 10)
                t.priceCurrency = "EUR"
                // ONE of the four has DROPPED (2026-08-12, prd §368). The
                // watch card's price bar draws the old figure and the
                // percentage off a recorded move, and `ShopifyIngest` only
                // ever writes one when a real catalogue read comes back
                // cheaper — so without a seeded move the demo can never show
                // the half of that card the feature exists for. Recorded the
                // way the bridge records it, through `PriceHistory.compose`,
                // rather than hand-writing the line: a demo that fakes the
                // format is a demo that keeps passing after the format
                // changes.
                if i == 1 {
                    t.tags = ["Price drop"]
                    t.enrichedText = PriceHistory.compose(
                        was: 65, now: 50, currency: "EUR",
                        wasUntil: at(a.2 + 5, 17))
                }
            }
        }
        let deals: [(String, String, Double, String)] = [
            ("Anker 737 power bank — 38% off", "$89", 1, "Slickdeals"),
            ("Kindle Paperwhite — lowest since March", "$109", 2, "Slickdeals"),
            ("Baratza Encore — refurb", "$99", 4, "DealNews"),
            ("AirPods Pro — $60 off", "$189", 7, "DealNews"),
        ]
        out += deals.enumerated().map { i, d in
            row(.product, d.0, source: "Deals", ref: "demo:deals:\(i)", days: d.2, hour: 10,
                content: d.1) { t in
                t.previewImageURL = productArt(i + 5)
                // WHO is offering it — `DealsBridge` stamps the publisher
                // here and the row draws it in its trailing slot, so a deal
                // without one reads as coming from nowhere.
                t.authorHandle = d.3
            }
        }
        out += (0..<3).map { i in
            // A REAL `off:<barcode>` ref and REAL tags (2026-08-12, prd §368).
            // The grade lived only in `content` prose while the bridge lands it
            // as a tag, and the ref was `demo:off:<n>` while the bridge keys on
            // the barcode — so the scanned card's Nutri-Score scale and its
            // barcode rung, the two things a scan has that nothing else does,
            // could not draw in the demo. The same shape as the Peer/Privacy
            // Pools room-head gap: a demo ref that doesn't match the real one
            // is a feature that silently never renders.
            row(.product, ["Oat drink, barista", "Dark chocolate 70%", "Rye sourdough"][i],
                source: "Open Food Facts", ref: "off:\(["5060403320102", "8717677332304", "5391520941016"][i])",
                days: Double(2 + i * 6), hour: 18,
                content: "Nutri-Score \(["B", "D", "A"][i]) · scanned",
                tags: ["Food", "Nutri-Score \(["B", "D", "A"][i])"]) { t in
                // `OpenFoodFactsBridge` stamps the product photo and the
                // BRAND (2026-08-12) — a `.product` sheet leads with that
                // image, so a scanned item with neither rendered as a bare
                // line of text where the real room shows a picture.
                t.previewImageURL = productArt(i + 1)
                t.authorHandle = ["Oatly", "Tony's Chocolonely", "Bread Ahead"][i]
            }
        }
        // The x402 room's rows; its treemap head reads `X402State` (seeded in
        // `seedBridgeState`), not these.
        let sellers: [(String, String, Double)] = [
            ("Orthogonal", "310 services · from $0.0010", 1),
            ("QuickNode", "88 services · from $0.0001", 2),
            ("Chainbase", "41 services · from $0.0025", 4),
            ("AIsa API", "18 services · from $0.0004", 8),
        ]
        out += sellers.enumerated().map { i, s in
            row(.link, s.0, source: "Circle x402", ref: "demo:x402:\(i)", days: s.2, hour: 11,
                content: s.1) { t in
                t.authorHandle = s.0
                t.summary = "Sells API calls settled per request in USDC."
            }
        }
        return out
    }

    // MARK: Wallet — the flow band, the curve, the approvals, the pools

    /// The flow band needs BOTH sides priced (`WalletFlow.minPricedShare`), a
    /// direction on every leg, and no security flag — an unpriced or one-sided
    /// window is declined by design, which is exactly what an under-seeded
    /// wallet looks like.
    private static func walletRoom() -> [Thing] {
        var out: [Thing] = []
        let moves: [(Bool, String, String, Double, Double)] = [
            (true,  "0.42 ETH",   "Coinbase",  1_336, 2),
            (false, "1,200 USDC", "Uniswap",   1_200, 3),
            (true,  "2,400 USDC", "Peer",      2_400, 5),
            (false, "0.15 ETH",   "Sam",         477, 7),
            (true,  "0.30 ETH",   "Coinbase",    954, 11),
            (false, "600 USDC",   "Bitrefill",   600, 13),
            (true,  "850 USDC",   "Stripe",      850, 16),
            (false, "0.08 ETH",   "Uniswap",     254, 19),
            (true,  "0.25 ETH",   "Mia",         795, 22),
            (false, "300 USDC",   "Gnosis Pay",  300, 25),
            (true,  "1,000 USDC", "Peer",      1_000, 27),
            (false, "0.05 ETH",   "Sam",         159, 29),
        ]
        out += moves.enumerated().map { i, m in
            let verb = m.0 ? "Received" : "Sent"
            return row(.transaction, "\(verb) \(m.1) \(m.0 ? "from" : "to") \(m.2)",
                       source: "Wallet", ref: "demo:wallet:tx:\(i)", days: m.4, hour: 9 + (i % 12),
                       content: "Base · \(m.2)") { t in
                // Spread across the watched wallets (2026-08-11) — see
                // `walletFor(move:)`. Every row keyed to one wallet made the
                // face shelf's other two faces open empty rooms.
                t.walletAddress = walletFor(move: i)
                t.transferDirection = m.0 ? "received" : "sent"
                t.transferAmount = m.1
                t.transferCounterparty = m.2
                // Keyed on the NAME, not the row index (2026-08-11). Indexed
                // addresses gave one counterparty a different address per
                // transfer, so "Sam" was two strangers to anything reading
                // addresses rather than the title — the address book couldn't
                // name them, and `AddressConnections` drew each as its own
                // node. One name, one address: the rows and the book below
                // now agree by construction.
                t.counterpartyAddress = counterpartyAddress(for: m.2)
                t.transferUSD = m.3
            }
        }
        // An approval, so the wallet room's exposure card has something real.
        // `.transaction` and a REAL `wallet:approval:` ref (2026-08-12).
        // `WalletApprovals` lands an approval as a `.transaction`, and the
        // demo landed `.approval` — a kind whose sheet is the agent's CONSENT
        // surface, Approve and Deny, for a row that in the app is a read-only
        // record of something that already happened onchain.
        //
        // The ref mattered as much: `WalletPrepare.applies` gates the whole
        // prepare card on `hasPrefix("wallet:approval:")` PLUS a wallet and a
        // counterparty address, so on `demo:wallet:approval:0` the card — the
        // live allowance read, the revoke calldata, the fee quote — could
        // never draw. The seventh instance of a gate keyed on a ref shape
        // that a `demo:` row cannot satisfy.
        out.append(row(.transaction, "Uniswap can spend your USDC", source: "Wallet",
                       ref: "wallet:approval:demo:0", days: 6, hour: 14,
                       content: "https://revoke.cash/address/\(demoWallet)") { t in
            t.walletAddress = demoWallet
            t.counterpartyAddress = counterpartyAddress(for: "Uniswap")
            t.grantedAt = at(6, 14)
        })
        // THE WALLET'S RECONCILING DEADLINES (2026-08-17). Four bridges land a
        // `dueAt` row under `source: "Wallet"` — ENS name expiry, the Bitcoin
        // halving, a staked-HYPE unlock and Aerodrome's weekly vote — and the
        // demo had NONE of them, so the wallet's entire forward-looking half
        // was missing: nothing in the runway, nothing in the "Needs you" tile,
        // nothing for `NotifySweep.deadlineNear` to find. The room read as a
        // pure ledger of things that already happened, which is half of what
        // the app's wallet actually is.
        //
        // REAL REF SHAPES, not `demo:` — each of these bridges reconciles its
        // own row by ref on every pass, and the eighth instance of a gate keyed
        // on a ref shape a `demo:` row cannot satisfy is not one worth adding.
        // Dates sit at the spacing each deadline really has: a vote closes
        // this week, an unlock in a month, a name in a season, a halving years
        // out — which is also what gives the runway a real span to draw.
        let deadlines: [(title: String, ref: String, due: Double, tag: String)] = [
            ("Aerodrome vote closes", "aerodrome:vote:\(demoWallet):4821", -3, "Onchain"),
            ("Staked HYPE unlocks", "hyperliquid:unlock:\(demoWallet):0xvalidator", -29, "Onchain"),
            ("casberi.eth expires", "wallet:ensexpiry:casberi.eth", -96, "Onchain"),
        ]
        out += deadlines.map { d in
            row(.transaction, d.title, source: "Wallet", ref: d.ref,
                days: 4, hour: 11, tags: [d.tag]) { t in
                t.walletAddress = demoWallet
                t.dueAt = at(d.due, 11)
            }
        }
        // Bitcoin is the ONLY wallet path that stamps a fiat figure on a
        // transfer (`priceValue`/`priceCurrency`, from the sats and the spot
        // price), so without a BTC row the demo could not draw a money receipt
        // carrying a second reading in dollars — §363's anatomy at its fullest.
        // `transferVenue` carries the BLOCK, which is Bitcoin's own named
        // moment and renders through `ThingStage` with no new UI.
        out.append(row(.transaction, "Received 0.0250 BTC", source: "Wallet",
                       ref: "bitcoin:settled:\(demoWallet):demo0", days: 11, hour: 15,
                       content: "https://mempool.space/tx/demo0", tags: ["Onchain"]) { t in
            t.walletAddress = demoWallet
            t.transferDirection = "received"
            t.transferAmount = "0.0250 BTC"
            t.transferVenue = "Block 959,701"
            t.priceValue = 2_640.0
            t.priceCurrency = "USD"
        })
        // Privacy Pools rides the watched wallet; its rail reads the state TAG
        // `PrivacyPoolsBridge.retag` maintains, never the title's words.
        // TWO assets on purpose (prd §397): the room states what is in the
        // pools per asset and must NEVER sum across them, and a single-asset
        // demo cannot show the difference between a card that respects that
        // and one that adds 0.86 to 400. The reclaimed pair below is the
        // other deliberate shape — see `poolExits`.
        // `amount` is ONE string, spent twice — the title says it and
        // `transferAmount` stamps it (2026-08-26). They have to be the same
        // characters, not merely the same number: `BandRow`'s money column
        // lifts the figure out of the sentence by SUBSTRING, so a seed whose
        // title reads "0.1500 ETH" and whose stamp reads "0.15 ETH" prints the
        // amount twice in the demo while the real bridge, which builds both
        // from one `WalletIngest.format`, prints it once.
        let pools: [(label: String, amount: String, state: String,
                     days: Double, symbol: String, value: Double)] = [
            ("demo0", "0.0700 ETH", "Pending",     2,  "ETH",  0.07),
            ("demo1", "0.1200 ETH", "Pending",     9,  "ETH",  0.12),
            ("demo2", "250 USDC", "Cleared",     13, "USDC", 250),
            ("demo3", "0.2500 ETH", "Cleared",     17, "ETH",  0.25),
            ("demo4", "0.0400 ETH", "Cleared",     24, "ETH",  0.04),
            ("demo5", "0.3000 ETH", "Needs proof", 31, "ETH",  0.30),
            // Reclaimed: still TAGGED `Declined`, deliberately. Its ragequit
            // row below is what turns it `Reclaimed` on the card, so the demo
            // exercises the §397 join — evidence beating a stale tag — rather
            // than pre-baking the answer into the tag and proving nothing.
            ("demo6", "0.1500 ETH", "Declined",    38, "ETH",  0.15),
            ("demo7", "0.0900 ETH", "Cleared",     45, "ETH",  0.09),
        ]
        out += pools.map { p in
            // The ref must carry `PrivacyPoolsRoom.depositPrefix` — the room
            // head's `row(ref:tags:)` matches on that exact prefix, and a
            // `"demo:"`-prefixed ref (the family every other seed uses) falls
            // through as unrecognised, silently zeroing this card. Found
            // building the room-head coverage check (2026-08-10): all six
            // seeded deposits were landing and going straight to `nil`.
            row(.transaction, "Put \(p.amount) into Privacy Pools", source: "Privacy Pools",
                ref: PrivacyPoolsRoom.depositPrefix + p.label,
                days: p.days, hour: 20, content: "Ethereum · 0xBow",
                tags: ["Shielded", p.state]) { t in
                t.walletAddress = demoWallet
                // The amount as DATA (prd §369) — the receipt states a figure
                // only from a stamped field, never by parsing the title, so
                // without this the demo's deposits lead with their title and
                // the sheet's headline number never draws.
                t.transferAmount = p.amount
                // The side, so the room draws its ledger column (2026-08-26) —
                // the same stamp `PrivacyPoolsBridge` makes. Money into the
                // pool is money out of the wallet.
                t.transferDirection = "sent"
                // …and the structured pair the ROOM reads (prd §397). Without
                // it every demo deposit is `unpriced`, the holdings line never
                // draws, and the cover line has no asset to join against —
                // three readings silently absent from the demo while the card
                // still looks complete.
                t.priceValue = p.value
                t.priceCurrency = p.symbol
                t.enrichedText = "The \(p.symbol) pool holds about "
                    + "\(p.symbol == "USDC" ? "700" : "3,900") accepted deposits."
            }
        }
        // The exit that closes the loop. Same label as `demo6`, which is what
        // joins them — `PrivacyPoolsRoom.reclaimedLabels` keys on exactly this.
        out.append(row(.transaction, "Reclaimed 0.1500 ETH from Privacy Pools",
                       source: "Privacy Pools",
                       ref: PrivacyPoolsRoom.reclaimedPrefix + "demo6",
                       days: 35, hour: 20, content: "Ethereum · 0xBow") { t in
            t.walletAddress = demoWallet
            t.transferAmount = "0.1500 ETH"
            t.transferDirection = "received"
            t.priceValue = 0.15
            t.priceCurrency = "ETH"
        })
        // ONE DEPOSIT WITH NO STATE TAG (2026-08-26, prd §486) — a pre-§311
        // deposit, the shape every real long-lived depositor has and the demo
        // had none of. It is what makes the split bar fall short of the full
        // width and what puts the "Unknown" row in the legend, so the reading
        // that closed §486's complaint — the gap in the bar being labelled
        // rather than explained in a footnote — is exercised on the corpus the
        // demo actually shows. Without it the demo's bar is always full and
        // that row can only be seen by someone who happens to have an old
        // deposit of their own.
        //
        // It carries no `priceValue` either, which is the same honesty one
        // reading over: it lands in `unpriced` and the money line's caption
        // says so, rather than the demo quietly presenting a partial figure as
        // a total.
        out.append(row(.transaction, "Put 0.0500 ETH into Privacy Pools",
                       source: "Privacy Pools",
                       ref: PrivacyPoolsRoom.depositPrefix + "demo8",
                       days: 52, hour: 20, content: "Ethereum · 0xBow",
                       tags: ["Shielded"]) { t in
            t.walletAddress = demoWallet
            t.transferAmount = "0.0500 ETH"
            t.transferDirection = "sent"
        })
        // Peer ranks on the funding RAIL, stamped on `authorHandle`.
        let fills: [(String, String, Double)] = [
            ("Bought 250 USDC with Venmo on Peer", "Venmo", 3),
            ("Bought 100 USDC with Cash App on Peer", "Cash App", 8),
            ("Bought 500 USDC with Venmo on Peer", "Venmo", 15),
            ("Bought 75 USDC with Revolut on Peer", "Revolut", 26),
            ("Bought 300 USDC with Cash App on Peer", "Cash App", 38),
        ]
        out += fills.enumerated().map { i, f in
            // Plain descriptive content, matching every sibling `.transaction`
            // row in this room (`moves`/`pools` above both use "Base · …") —
            // not a fabricated basescan.org tx link (P4, 2026-08-07): a real
            // host with a fake hash reads as "transaction not found" on a
            // trusted explorer, which is a sharper dead door than most.
            // Ref must carry the real bare `"peer:"` prefix (never
            // `"peer:sell:"`/`"peer:expired:"`, which mean something else) or
            // `PeerRoom.kind(ref:)` returns nil and the fill is dropped before
            // it's even counted toward `fellThrough` — the same
            // `"demo:"`-prefix miss as the Privacy Pools fix above.
            row(.transaction, f.0, source: "Peer", ref: "peer:demo\(i)", days: f.2, hour: 12,
                content: "Base · \(f.1)") { t in
                t.authorHandle = f.1
                t.walletAddress = demoWallet
            }
        }
        // Altana's keystore rides the watched wallet (prd §403). The refs must
        // carry the REAL `altana:key:<chain>:<address>:<keyid>` shape
        // `AltanaKeystore.ref` builds — a `"demo:"`-prefixed ref is the miss
        // that silently zeroed the Peer and Privacy Pools cards on their own
        // first coverage run, twice.
        //
        // These MIRROR `seedAltanaKeystore()`'s snapshot on purpose: the room
        // HEAD composes from that snapshot and the rows are what sits beneath
        // it, so a demo where the two disagree shows a card describing keys
        // the room does not list.
        let keys: [(String, Int, Bool, Double)] = [
            ("A root key can sign as \(WalletStore.shortAddress(demoWallet))", 0, true, 62),
            ("A session key was granted for \(WalletStore.shortAddress(demoWallet)), until tomorrow", 1, false, 0.6),
            ("A session key was granted for \(WalletStore.shortAddress(demoWallet)), until next month", 2, false, 4),
            ("A session key was granted for \(WalletStore.shortAddress(demoWallet)), until last week", 3, false, 6),
        ]
        out += keys.map { k in
            row(.link, k.0, source: "Altana",
                ref: AltanaKeystore.ref(chain: "BNB Smart Chain", address: demoWallet,
                                        keyID: demoAltanaKeyIDValue(k.1)),
                days: k.3, hour: 10,
                content: AltanaKeystore.explorerURL(address: demoWallet),
                tags: [k.2 ? "Root key" : "Session key", "BNB Smart Chain"]) { t in
                t.walletAddress = demoWallet
                t.externalLink = AltanaKeystore.explorerURL(address: demoWallet)
            }
        }
        // …and the SECOND account's rows (§407a): its tokens are tap targets
        // like any others, and a token whose sheet never opens is §83's dead
        // control hiding in the demo. Same ref shape, the second address.
        let keys2: [(String, Int, Bool, Double)] = [
            ("A root key can sign as …160f", 4, true, 30),
            ("A session key was granted for …160f, until next month", 2, false, 4),
        ]
        out += keys2.map { k in
            row(.link, k.0, source: "Altana",
                ref: AltanaKeystore.ref(chain: "BNB Smart Chain", address: demoAltanaSecondAccount,
                                        keyID: demoAltanaKeyIDValue(k.1)),
                days: k.3, hour: 11,
                content: AltanaKeystore.explorerURL(address: demoAltanaSecondAccount),
                tags: [k.2 ? "Root key" : "Session key", "BNB Smart Chain"]) { t in
                t.walletAddress = demoAltanaSecondAccount
                t.externalLink = AltanaKeystore.explorerURL(address: demoAltanaSecondAccount)
            }
        }
        // Railgun ranks by token, read as DATA off `priceValue`/`priceCurrency`
        // — never parsed back out of the title. Ref must carry the real
        // `"railgun:shield:"`/`"railgun:unshield:"` prefix (`RailgunRoom
        // .direction(ref:)`'s exact match) or the move is dropped before
        // it's even counted, the same `"demo:"`-prefix miss as Peer/Privacy
        // Pools above.
        // `amount` is ONE string spent twice — see the Privacy Pools seed
        // above for why the title and the stamp have to be the same
        // characters rather than the same number.
        let railgunMoves: [(amount: String, verb: String, symbol: String,
                            value: Double, days: Double)] = [
            ("0.4000 ETH", "shield", "ETH", 0.4000, 6),
            ("500 DAI", "shield", "DAI", 500, 14),
            ("0.1500 ETH", "unshield", "ETH", 0.1500, 23),
        ]
        out += railgunMoves.enumerated().map { i, r in
            let title = r.verb == "shield"
                ? "Shielded \(r.amount) into Railgun"
                : "Received \(r.amount) from Railgun"
            return row(.transaction, title, source: "Railgun",
                ref: "railgun:\(r.verb):demo\(i)",
                days: r.days, hour: 21, content: "Ethereum · zk-SNARK") { t in
                t.walletAddress = demoWallet
                t.transferDirection = r.verb == "shield" ? "sent" : "received"
                // The amount as the ROW reads it (2026-08-26). The bridge has
                // stamped this since it shipped; the demo never did, so every
                // seeded Railgun move kept its figure inside its sentence and
                // the room's new ledger column drew on no row at all.
                t.transferAmount = r.amount
                t.priceValue = r.value
                t.priceCurrency = r.symbol
                if r.verb == "unshield" {
                    t.enrichedText = "Railgun can't tell you who sent this — inside the pool the sender is private by design."
                }
            }
        }
        // Safe gained its own source (2026-08-11, riding a Safe multisig's
        // pending-signature queue) — was "Wallet" before that, like Aave/
        // Morpho still are. Title shape and ref match `SafeBridge.swift`'s
        // real "N of M signatures collected on … — waiting on others / —
        // your signature is needed", `"wallet:safe:<chainSeg>:<txHash>"`.
        //
        // Four rows, not two, since 2026-08-17 — the demo has to be able to
        // SHOW the three states the head distinguishes, or the states ship
        // unseen (the standing demo-parity rule, and `verify.sh`'s room-head
        // check reads this corpus). Titles and tags match `SafeBridge.rowFace`
        // exactly, including the fully-signed face, which is a different
        // sentence and a different tag rather than "3 of 3".
        let safeTxs: [(title: String, tags: [String], days: Double)] = [
            ("2 of 3 signatures collected on sending 1,500 USDC to payroll.eth — your signature is needed",
             ["Your turn"], 5),
            ("Fully signed — sending 900 USDC to vendor.eth is ready to execute",
             ["Ready to execute"], 4),
            ("1 of 3 signatures collected on approving Uniswap to spend 2,000 USDC — waiting on others",
             [], 9),
            // The rival: same Safe, same nonce as the row above it. Only one of
            // the two can ever execute, which is the fact §238 could state in
            // the sheet and the head could not until the nonce was tracked.
            ("1 of 3 signatures collected on revoking Uniswap's spending approval — waiting on others",
             [], 6),
        ]
        out += safeTxs.enumerated().map { i, s in
            row(.transaction, s.title, source: "Safe", ref: "wallet:safe:eth:demo\(i)",
                days: s.days, hour: 15) { t in
                t.walletAddress = demoWallet
                t.tags = s.tags
            }
        }
        return out
    }

    /// Apple Wallet's board ranks merchants by share of settled spend — the one
    /// source in the app that sees a merchant NAME, which is why the room leads
    /// with WHO rather than when.
    private static func appleWallet() -> [Thing] {
        let spends: [(String, Double, Double)] = [
            ("Whole Foods", 84.20, 1), ("Whole Foods", 61.05, 8), ("Whole Foods", 73.40, 15),
            ("Apple", 12.99, 2), ("Apple", 12.99, 32),
            ("Uber", 24.30, 3), ("Uber", 18.75, 11), ("Uber", 31.10, 20),
            ("Blue Bottle", 6.50, 4), ("Blue Bottle", 6.50, 9), ("Blue Bottle", 7.25, 18),
            ("Delta", 412.00, 26),
        ]
        return spends.enumerated().map { i, s in
            row(.transaction, "\(s.0) · $\(String(format: "%.2f", s.1))",
                source: "Apple Wallet", ref: "demo:applewallet:\(i)", days: s.2, hour: 12 + (i % 8),
                content: "Apple Card") { t in
                t.priceValue = s.1
                t.priceCurrency = "USD"
                t.transferCounterparty = s.0
                // The account as DATA (prd §369) — the receipt's "on Apple
                // Card, ending 4821" line reads `authorHandle`, and taking it
                // back out of the joined `enrichedText` blob below would mean
                // guessing which component is which.
                t.authorHandle = "Apple Card, ending 4821"
                // The receipt's state stamps — and its TEAR, which is flat
                // while an amount can still change. Without a pending and a
                // refunded row in the demo, two of the three states this seat
                // can be in never draw anywhere (the §369 parity rule: a demo
                // that furnishes only the happy path proves only the happy
                // path). The newest row is the pending one, so it is the one
                // an opened demo lands on.
                if i == 0 { t.tags = ["Card", "Pending"] }
                else if i == 1 { t.tags = ["Card", "Refund"] }
                else { t.tags = ["Card"] }
                t.enrichedText = "\(s.0.uppercased()) #\(4000 + i)"
            }
        }
    }

    /// The two onchain cards lead with `cardMonths` — spend by month, which
    /// needs `priceValue` across at least two calendar months.
    private static func cards() -> [Thing] {
        var out: [Thing] = []
        let gnosis: [(String, Double, Double)] = [
            ("Supermarket", 42.80, 3), ("Pharmacy", 12.40, 9), ("Restaurant", 68.00, 20),
            ("Supermarket", 51.25, 38), ("Transit", 22.50, 44), ("Bookshop", 31.90, 61),
        ]
        out += gnosis.enumerated().map { i, g in
            row(.transaction, "\(g.0) · €\(String(format: "%.2f", g.1))",
                source: "Gnosis Pay", ref: "demo:gnosispay:\(i)", days: g.2, hour: 13,
                content: "Gnosis Chain · EURe") { t in
                t.priceValue = g.1
                t.priceCurrency = "EUR"
                t.walletAddress = demoWallet
            }
        }
        let etherfi: [(String, Double, Double)] = [
            ("Coffee", 4.20, 2), ("Hardware store", 88.10, 12), ("Groceries", 39.60, 27),
            ("Coffee", 4.20, 35), ("Cinema", 17.00, 52),
        ]
        out += etherfi.enumerated().map { i, e in
            row(.transaction, "\(e.0) · $\(String(format: "%.2f", e.1))",
                source: "ether.fi", ref: "demo:etherfi:\(i)", days: e.2, hour: 16,
                content: "ether.fi Cash") { t in
                t.priceValue = e.1
                t.priceCurrency = "USD"
                t.walletAddress = demoWallet
            }
        }
        // REAL ref shapes, and the fields the receipt reads (2026-08-12, prd
        // §368). Both seats used `demo:<seat>:<n>`, which matches none of
        // `PurchaseStage.purchaseRefs` — so every one of these rows fell
        // straight past the receipt and kept the generic sheet, and the whole
        // category would have looked unbuilt in the one place anyone can see
        // it without an account. Same failure as the Peer / Privacy Pools room
        // heads, which dropped every seeded row for exactly this reason.
        //
        // Netflix appears FOUR times on purpose: the recurrence sentence
        // ("You've paid Netflix.com 4 times · $12.99 every time since…") needs
        // more than one charge to the same merchant, and an unchanged amount
        // is the branch that says the most.
        let card: [(String, Double, Double, Bool)] = [
            ("Netflix.com", 12.99, 4, true), ("Spotify", 10.99, 14, true),
            ("Figma", 15.00, 24, false), ("Netflix.com", 12.99, 35, true),
            ("Netflix.com", 12.99, 66, true), ("Netflix.com", 12.99, 96, true),
        ]
        out += card.enumerated().map { i, c in
            row(.transaction, "\(c.0) · $\(String(format: "%.2f", c.1))",
                source: "Privacy", ref: "privacy:txn:demo\(i)",
                days: c.2, hour: 8, content: "https://privacy.com/account",
                // `Settled` vs `Pending` is the §317 distinction this pass gave
                // Privacy — the newest charge is deliberately unsettled, since
                // an authorization that can still change is the state the badge
                // exists to say and the state a demo would otherwise never show.
                tags: ["Card", c.3 ? "Settled" : "Pending"]) { t in
                t.priceValue = c.1
                t.priceCurrency = "USD"
                t.transferCounterparty = c.0
            }
        }
        // An ORDER and a REFILL, which are two different receipts: one names
        // the merchant, the other names the rail the money came in on. Both
        // ride `transferCounterparty` — one field, one meaning ("the other
        // side of the money"), with the verb telling them apart.
        let orders: [(String, Double, String, Double)] = [
            ("Amazon.com", 25, "EUR", 6), ("Uber", 50, "USD", 20),
        ]
        out += orders.enumerated().map { i, o in
            row(.link, "\(o.0) · \(o.2 == "EUR" ? "€" : "$")\(Int(o.1))",
                source: "Bitrefill", ref: "bitrefill:order:demo\(i)",
                days: o.3, hour: 19, content: "https://www.bitrefill.com/account/orders",
                tags: ["Delivered"]) { t in
                t.priceValue = o.1
                t.priceCurrency = o.2
                t.transferCounterparty = o.0
                t.previewImageURL = productArt(i + 3)
            }
        }
        out.append(
            row(.link, "Balance refill · €100 in bitcoin", source: "Bitrefill",
                ref: "bitrefill:invoice:demo0", days: 34, hour: 19,
                content: "https://www.bitrefill.com/account/invoices") { t in
                t.priceValue = 100
                t.priceCurrency = "EUR"
                t.transferCounterparty = "Bitcoin"
            })
        return out
    }

    // MARK: Work — the rooms whose rows are one-line facts

    /// Cloudflare's certificate expiries — the one row-shape no other
    /// function in this file provides (2026-08-07, revised).
    ///
    /// This function used to also seed Sentry/PagerDuty/Vercel/npm/PyPI/
    /// Cal.com/Calendly, written in an earlier session against a version of
    /// this file where those eight sources furnished nothing at all (a real
    /// bug: a seat claiming "Synced 20m ago" in the catalog over a room with
    /// no rows, reported as "the source tray doesn't show all the sources").
    /// A LATER, independent pass (`work`'s `ops` array, `schedule`'s Cal.com/
    /// Calendly bookings) fixed the same gap its own way while this file was
    /// being edited concurrently — and because `Thing.sourceRef` carries NO
    /// unique constraint, the two fixes didn't conflict loudly, they
    /// silently DUPLICATED: `demo:sentry:0`, `demo:sentry:1`,
    /// `demo:pagerduty:4` and `demo:vercel:2` were each about to land as TWO
    /// separate `Thing`s sharing one ref — exactly the class this file's own
    /// `seed()` doc warns about ("a leaderboard's subtitle sums the rows it
    /// counted... five forced runs read 43,875 saved messages"). Caught
    /// before either build ran, not after.
    ///
    /// `ops` covers Sentry/PagerDuty/Vercel/Cloudflare/npm/PyPI with real
    /// non-empty rows and SAFE plain-text `content` (no P4 fabricated-URL
    /// issue there to begin with); `schedule` covers Cal.com/Calendly the
    /// same way. Only Cloudflare needed anything beyond what they already
    /// give it: its room head (`CloudflareRunwaySource.compose`) reads
    /// `Thing.dueAt` off real rows to build its runway, and `ops`'s two
    /// Cloudflare rows set none — a runway with no dated row is an empty
    /// rail. These two are what's left.
    ///
    /// **The ref must be `cloudflare:cert:<id>`, not a `demo:`-prefixed one
    /// (found 2026-08-08, via `-agentOpenProbe` — the panel's `runway` figure
    /// never appeared for the demo corpus, one of three figure kinds a
    /// coverage sweep flagged as missing).** `CloudflareRunwaySource.item(
    /// ref:…)` matches `hasPrefix("cloudflare:cert:")` EXACTLY — a
    /// `demo:cloudflare:0` ref, which is what every other room's seeder uses,
    /// fails that check and the row is silently dropped before it ever
    /// becomes a rail item. Kept out of the general `demo:` ref family on
    /// purpose (the real bridge's own convention is the only one the parser
    /// honours), so `DemoSeedAll.refPrefixes`/`teardown` carry an explicit
    /// second entry for it — see there.
    private static func infra() -> [Thing] {
        let certs: [(String, String, Double, Double)] = [
            ("demo0", "casberi.app certificate renews", 3, -34),
            ("demo1", "api.casberi.app certificate renews", 6, -71),
        ]
        return certs.map { id, title, days, dueDays in
            row(.reminder, title, source: "Cloudflare", ref: "cloudflare:cert:\(id)",
                days: days, hour: 8, content: "Auto-renews") { t in
                t.dueAt = at(dueDays, 8)
                // `CloudflareBridge` stamps the certificate's own detail onto
                // `summary` (2026-08-17) — the issuer and what it covers, which
                // is the difference between "a cert expires" and knowing which.
                t.summary = "Universal SSL, issued by Let's Encrypt, covering "
                    + "the apex and one wildcard."
            }
        }
    }

    /// `CloudflareEstateStore`'s saved state — the SECOND thing the runway
    /// figure needs beyond the two rows above. `CloudflareRunwaySource
    /// .compose` bails at its very first guard (`guard let estate =
    /// CloudflareEstateStore.load() else { return nil }`) with NO estate
    /// saved, regardless of how many Cloudflare things exist — the exact
    /// "room head reads UserDefaults, not rows" shape the wallet curve,
    /// PostHog metrics and x402 sellers already needed a seed for, just not
    /// one this file had gotten to. `zoneNames` keys match `infra()`'s cert
    /// ids exactly, so `item()`'s `estate.zoneNames[id]` lookup resolves a
    /// real name instead of falling back to the row's own title.
    @MainActor
    /// Altana's keystore snapshot (prd §403).
    ///
    /// The room head composes from `AltanaState`, NOT from rows — it is chain
    /// state, and re-reading it on every draw would spend an `eth_call` per
    /// scroll. So a demo that seeded only rows would furnish the room and
    /// leave its head permanently empty, which is the Cloudflare `runway` gap
    /// (2026-08-08) in a new seat: a card that cannot draw, looking exactly
    /// like a card with nothing to say.
    ///
    /// The shape mirrors what was MEASURED on BNB: one root key with no
    /// expiry, 24-hour session grants, and — deliberately — one session key
    /// already past its expiry while the registry still lists it, so the
    /// demo exercises the hygiene line rather than pre-baking it away.
    /// A demo key id that is REAL HEX.
    ///
    /// The first cut spelled these `0xdem0…`, which reads nicely and is not a
    /// hex string — `m` is not a hex digit, and it was 63 characters rather
    /// than 64. `AltanaKeySheet.parse` refuses both, correctly, so every demo
    /// key row fell back to the generic link sheet while the room head (which
    /// never validates an id) rendered perfectly. A demo that furnishes one
    /// surface and silently starves another is exactly the §349 class, one
    /// layer down — and no static check covers a sheet anatomy.
    ///
    /// Shared by the snapshot and the rows deliberately: they must agree, or
    /// the sheet composes for an id the room does not list.

    /// The demo's second Altana account — snapshot-only, never watched.
    private static let demoAltanaSecondAccount = "0x9e8d7c6b5a49382716059483726150493827160f"

    private static func seedAltanaKeystore() {
        let now = Date.now
        // A REAL secp256k1 point, measured off BNB 2026-08-18 — so the demo's
        // curve label ("secp256k1 key") is computed by the shipped detector from
        // key material that genuinely lies on the curve, not asserted. A made-up
        // point would satisfy neither equation and render as `.unknown`, which
        // is exactly the demo silently under-showing a feature.
        let realPoint = "04a376e7011da0888af6a46b1803c93760db185736229fbcf96d2c9750f9e3eacb"
                      + "021abf6eeffcd4f7645c343e2d43c3dc5e2a352ee7ab15c7b8f16649531ba940"
        func key(_ id: String, root: Bool, registeredDaysAgo: Double,
                 grantHours: Double?, signatures: Int = 0,
                 publicKey: String? = nil) -> AltanaKeystore.Key {
            let registered = now.addingTimeInterval(-registeredDaysAgo * 86_400)
            return AltanaKeystore.Key(
                id: id, isRoot: root,
                expiry: grantHours.map { registered.addingTimeInterval($0 * 3600) },
                signatureCount: signatures, publicKey: publicKey,
                registeredAt: registered, chainLabel: "BNB Smart Chain")
        }
        // A REAL P-256 point (the curve's own base point), so the demo shows
        // the word the whole label exists for — "Passkey" — computed by the
        // shipped detector rather than asserted.
        let realP256 = "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
                     + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
        // SEEDED OUT OF ORDER, deliberately (§405). Expired first, root last —
        // the exact arrangement that used to reach the card untouched, because
        // `compose` mapped whatever it was handed. Now the card sorts its own
        // rows, so the demo proves the fix instead of hiding it: whatever order
        // this array is in, the head must draw root → live → expired.
        AltanaState.save([
            AltanaKeystore.Reading(address: demoWallet, keys: [
                // EXPIRED but still listed — the reading nothing else has.
                key(demoAltanaKeyIDValue(3), root: false,
                    registeredDaysAgo: 6, grantHours: 24),
                // Live, a 30-day grant with most of its runway left, and never
                // used — the notable state a count can say and a Bool cannot.
                key(demoAltanaKeyIDValue(2), root: false,
                    registeredDaysAgo: 4, grantHours: 24 * 30,
                    signatures: 0, publicKey: realP256),
                // Live, a little over halfway through a 24-hour grant — and the
                // one that puts a clock in the headline.
                key(demoAltanaKeyIDValue(1), root: false,
                    registeredDaysAgo: 0.6, grantHours: 24,
                    signatures: 47, publicKey: realPoint),
                key(demoAltanaKeyIDValue(0), root: true,
                    registeredDaysAgo: 62, grantHours: nil,
                    signatures: 128, publicKey: realPoint),
            ], truncated: false),
            // A SECOND account (§407a): the keyring's whole point is the
            // aggregate the old card footnoted, and a one-account demo would
            // hide the grouping exactly the way the sorted-input demo hid the
            // ordering defect. Its passkey shares demoAltanaKeyIDValue(2)'s id
            // with the first account ON PURPOSE — the same credential under
            // two accounts is the link-badge fact, otherwise unreachable in a
            // demo. Not a watched wallet, which is fine: the head composes
            // from the snapshot, and the demo banner already says none of
            // this is yours.
            AltanaKeystore.Reading(address: demoAltanaSecondAccount, keys: [
                key(demoAltanaKeyIDValue(4), root: true,
                    registeredDaysAgo: 30, grantHours: nil,
                    signatures: 12, publicKey: realPoint),
                key(demoAltanaKeyIDValue(2), root: false,
                    registeredDaysAgo: 4, grantHours: 24 * 30,
                    signatures: 0, publicKey: realP256),
            ], truncated: false),
        ])
        // A GHOST (§410): a credential revoked while watching, so the demo
        // shows the severed tie rather than leaving the whole reading
        // invisible until somebody's real key is revoked — which for this
        // registry could be months. Noticed 3 days ago, inside `ghostLifetime`.
        AltanaState.rememberGone(.init(
            address: demoWallet,
            keyID: demoAltanaKeyIDValue(5),
            isRoot: false,
            kindLabel: String(localized: "Passkey"),
            chainLabel: "BNB Smart Chain",
            noticedAt: now.addingTimeInterval(-3 * 86_400)))
        AltanaKeystore.evidence.remember(demoWallet)
    }

    /// The vibenet room's balance curve — see `seedBridgeState`'s 5c-i. The
    /// SHAPE is `VibenetDemoHistoryShape`, pure and harness-held; this only
    /// writes it into the store the shipped app records into.
    private static func seedVibenetHistory() {
        // THE CONTRACTS FIRST (prd §476). The fixture's undeployed account
        // states its explainer from `VibenetRoom.undeployedExplainer`, which
        // needs nothing — but the faucet door beside it is gated on the cached
        // config naming a faucet, and a demo install has never fetched one. So
        // the demo drew the problem and withheld the button that answers it.
        // See `VibenetConfig.seedDemo`.
        VibenetConfig.seedDemo()
        VibenetValueStore.replace(VibenetDemoHistoryShape.samples(now: .now))
        // Per account too, or picking a face on the rail drops the curve the
        // aggregate just showed — the scoped room reads its OWN series (see
        // `VibenetValueStore.recordAccounts` for why it must not borrow the
        // room's). Each is scaled to end on that account's own balance, so
        // every line ends on the figure its own crown states.
        var book: [String: [VibenetValueSample]] = [:]
        for item in VibenetRoom.demoFixture().items {
            guard let native = item.nativeBalance else { continue }
            book[item.address.lowercased()] =
                VibenetDemoHistoryShape.samples(endingOn: native, now: .now)
        }
        VibenetValueStore.replaceAccounts(book)
    }

    /// The vibenet room's "since you last looked" ledger (prd §468).
    ///
    /// A first sight seeds SILENTLY by design — otherwise a newly-watched
    /// account reports every key it has ever had as new — so a demo with no
    /// ledger can never draw that line, and the one reading in this room that
    /// answers "did anything change while I wasn't looking" would be invisible
    /// in the tour.
    ///
    /// DERIVED FROM THE FIXTURE, never a hand list of ids: the book is the
    /// fixture's own advanced state with one real key removed (so it reads as
    /// NEW) and one phantom added (so it reads as REVOKED). A fixture edit
    /// therefore cannot leave this seeding a set of ids that match nothing —
    /// the §349 demo-ref lesson, avoided by construction rather than by care.
    private static func seedVibenetSeenKeys() {
        let items = VibenetRoom.demoFixture().items
        var book = VibenetKeySeenDiff.advanced(seen: [:], items: items)
        guard let account = items.first(where: { $0.actors.count > 1 }) else { return }
        let bookKey = account.address.lowercased()
        var set = book[bookKey] ?? []
        // SORTED before dropping, so the same key is chosen on every run —
        // a `Set`'s iteration order is not stable across launches, and a demo
        // whose card says "1 key new" about a different key each time is a
        // demo nobody can screenshot twice.
        if let dropped = set.sorted().first { set.remove(dropped) }
        set.insert(VibenetKeySeenDiff.keyID(address: account.address, actorId: "0xdemorevokedkey"))
        book[bookKey] = set
        VibenetKeysSeen.seed(book)
    }

    private static func seedCloudflareEstate() {
        CloudflareEstateStore.save(CloudflareEstate(
            zoneNames: ["demo0": "casberi.app", "demo1": "api.casberi.app"],
            autoRenew: [:], zonesSeen: 2, zonesCovered: 2))
    }

    private static func work() -> [Thing] {
        var out: [Thing] = []
        // Linear's rail reads `mark`, which the bridge maps from Linear's own
        // state TYPE — an unclassified issue counts in neither bucket.
        let issues: [(String, Mark, Double)] = [
            ("CAS-412 Panel reshuffles between opens", .doing, 1),
            ("CAS-408 Seed every room on the sim", .doing, 2),
            ("CAS-401 Flow band declines one-sided windows", .todo, 4),
            ("CAS-399 Heatmap outranks the topic map", .done, 7),
            ("CAS-396 Chip strip freezes mid-reach", .done, 12),
            ("CAS-390 Receipts screen misses runtime hosts", .todo, 18),
            ("CAS-384 Embedding race on foreground", .done, 25),
        ]
        out += issues.enumerated().map { i, s in
            // `.link`, which is what `TokenBridges` lands for Linear — the
            // demo's `.reminder` gave it a different sheet and a different row
            // shape than any real issue ever gets (2026-08-12).
            row(.link, s.0, source: "Linear", ref: "demo:linear:\(i)", days: s.2, hour: 10,
                content: "Assigned to you") { t in
                t.mark = s.1
                // THE ISSUE'S OWN DESCRIPTION AND ITS DUE DATE (2026-08-17).
                // `TokenBridges` stamps both for Linear — the description on
                // `summary` as display copy (the Trello card-back contract),
                // the target date on `dueAt` — and the demo set neither, so
                // this room showed bare titles where the app shows a task you
                // can actually judge, and none of its work ever reached the
                // runway or the "Needs you" tile.
                //
                // A date on SOME, not all: plenty of real issues carry none,
                // and a room where every row has a deadline reads as a
                // deadline list rather than a backlog.
                t.summary = "\(s.0). Scoped this week; blocked on nothing."
                if i % 2 == 0 { t.dueAt = at(-Double(3 + i * 4), 17) }
            }
        }
        // WHO DID IT, with their face (2026-08-12). `GitHubFeeds` stamps the
        // event's own actor onto `authorHandle` and their avatar onto
        // `authorAvatarURL`; the demo stamped neither, so a room whose every
        // row is somebody's action showed no one performing it. The review
        // request is a COLLABORATOR's — that is what makes it a request rather
        // than a note to self.
        // The fourth entry has always READ as a review request and carried no
        // ask TAG, so the §401 head — which ranks on the tag and never on the
        // title — saw nothing and correctly declined. `verify.sh`'s room-head
        // coverage would then have reported a real gap that was only ever a
        // demo one (§375's X lesson, two rooms over). Three asks are seeded so
        // the card can demonstrate its whole ranking, not just its lead.
        let github: [(String, String, Double, String?)] = [
            ("Merged: panel draws only figures (#412)", "you", 1, nil),
            ("Mentioned you · casberi/app · seed every source on the sim (#414)", "you", 1.5, "Mentioned"),
            ("Assigned to you · casberi/app · serialize NLEmbedding inference (#409)", "you", 6, "Assigned"),
            ("Review requested · casberi/app · receipts reach map (#402)", "mia", 14, "Review"),
        ]
        out += github.enumerated().map { i, g in
            row(.link, g.0, source: "GitHub", ref: "demo:github:\(i)", days: g.2, hour: 15) { t in
                if let ask = g.3 { t.tags = t.tags + ["Notifications", ask] }
                t.starCount = 128 + i
                t.repoLanguage = "Swift"
                t.authorHandle = g.1
                t.authorAvatarURL = avatarArt(g.1)
                // The repository's social preview image, which `GitHubFeeds`
                // stamps (2026-08-17). The avatar above says WHO; this says
                // what the project looks like, and the room drew neither.
                t.previewImageURL = art(i)
            }
        }
        let slack: [(String, String, Double)] = [
            ("Uma: can we ship the panel this week?", "#design", 1),
            ("Nils: joinery quote came back under budget", "#home", 3),
            ("Mia: book club moved to Thursday", "#book-club", 5),
        ]
        out += slack.enumerated().map { i, s in
            row(.chat, s.0, source: "Slack", ref: "demo:slack:\(i)", days: s.2, hour: 11,
                content: s.1) { t in
                t.channelName = s.1
                t.authorHandle = String(s.0.prefix(while: { $0 != ":" }))
                // The message itself on `postText` (2026-08-17), where the
                // bridge puts it and where the card renders it — `title` is
                // the 80-character clamp, so without this a long Slack message
                // was readable only as its own truncation.
                t.postText = s.0
            }
        }
        let trello: [(String, Double)] = [
            ("Kitchen · Order the tiles", 2), ("Kitchen · Confirm the joiner", 5),
            ("Trip · Book the Lisbon flat", 9),
        ]
        out += trello.enumerated().map { i, c in
            row(.reminder, c.0, source: "Trello", ref: "demo:trello:\(i)", days: c.1, hour: 9,
                content: "Assigned to you") { t in
                t.dueAt = at(-Double(2 + i * 3), 12)
                t.summary = "Card back: check the measurements first."
                // A card's cover image, which Trello serves and the bridge
                // stamps (2026-08-17). Sparse, because a real board mixes
                // covered cards with plain ones and a board where every card
                // has art reads as a gallery rather than a list of work.
                if i % 2 == 0 { t.previewImageURL = art(i) }
            }
        }
        // GitLab's own title shape: `references.full` (group/project#N or
        // !N) leads, matching `gitlabThing`'s real join. No `content` URL —
        // the P4 rule (a real host with a fabricated path/id is a sharper
        // dead door than none), the same choice Trello/Linear/GitHub above
        // already made.
        let gitlab: [(String, Mark, Double)] = [
            ("casberi/casberi#58 · Fix the flat curve on refresh", .doing, 2),
            ("casberi/casberi!61 · Serialize NLEmbedding inference", .done, 5),
            ("casberi/casberi#54 · Receipts screen misses runtime hosts", .todo, 11),
        ]
        out += gitlab.enumerated().map { i, g in
            row(.link, g.0, source: "GitLab", ref: "demo:gitlab:\(i)", days: g.2, hour: 13) { t in
                t.mark = g.1
                // Same pair as Linear above, same bridge file, same two fields
                // the demo never set — an issue's description and its due date.
                t.summary = "\(g.0). Opened against the current milestone."
                if i == 0 { t.dueAt = at(-8, 17) }
            }
        }
        // Jira's title shape: the key leads on its own (`"PROJ-123 · summary"`,
        // legible without a join the way a bare Trello/Linear title isn't).
        let jira: [(String, Mark, Double, Double?)] = [
            ("CAS-201 · Draft the launch email", .todo, 3, 5),
            ("CAS-198 · Review the App Store screenshots", .doing, 6, nil),
            ("CAS-190 · File the CloudKit schema deploy", .done, 15, nil),
        ]
        out += jira.enumerated().map { i, j in
            row(.reminder, j.0, source: "Jira", ref: "demo:jira:\(i)", days: j.2, hour: 9,
                tags: ["Casberi"]) { t in
                t.mark = j.1
                if let due = j.3 { t.dueAt = at(-due, 17) }
            }
        }
        let cursor: [(String, Double)] = [
            ("casberi · seed every room", 1), ("casberi · fix the flat curve", 4),
            ("Failed · casberi · migrate the schema", 9),
        ]
        out += cursor.enumerated().map { i, c in
            row(.link, c.0, source: "Cursor", ref: "demo:cursor:\(i)", days: c.1, hour: 22) { t in
                t.summary = "Ran for 6 minutes. Opened a PR with the change and a test."
                // `CursorRoomSource` groups on `authorHandle` (where
                // `CursorFetch` stamps the real repo, §340), never the
                // clamped title — without it `CursorRoom.compose` sees zero
                // repos and the head is nil no matter how many rows landed.
                // Found by the room-head coverage check's own first run
                // (2026-08-10): all three seeded runs were missing it.
                t.authorHandle = "alexanderchopan/casberi"
            }
        }
        // `ops` rows carry the tag their bridge stamps (2026-08-12), because
        // `WorkStage.outcome` is keyed on (source, TAG) and nothing else —
        // a row whose title says "New issue" and whose tags are empty reads
        // correctly to a person and produces no reading at all, so the whole
        // Work anatomy (its outcome word, its tone, its `code` face) never
        // drew for Sentry. `SentryBridge` stamps exactly one of Issue /
        // Regression; Vercel, PagerDuty, npm and PyPI have their own.
        let ops: [(String, String, String, Double, [String])] = [
            ("Resolved: elevated 5xx on the edge", "Sentry", "12 events", 2, ["Regression"]),
            ("New issue: nil unwrap in FeedScreen", "Sentry", "3 events", 6, ["Issue"]),
            ("Deployed casberi-site to production", "Vercel", "Ready in 24s", 1, ["Deploy"]),
            ("Preview ready for pull/412", "Vercel", "Ready in 19s", 3, ["Deploy"]),
            ("Acknowledged: latency alert", "PagerDuty", "Resolved in 8m", 8, ["Resolved"]),
            // Cloudflare's rows are readings, not outcomes — its bridge stamps
            // no outcome tag and `WorkStage.outcome` has no case for it, so
            // these two correctly produce no Work reading. Left tagless on
            // purpose rather than given an invented tag to make a card appear.
            ("casberi.app · 1.2M requests today", "Cloudflare", "Cached 92%", 1, []),
            ("Certificate renews in 21 days", "Cloudflare", "casberi.app", 4, []),
            ("swift-markdown 0.4.0 published", "npm", "2 dependents", 5, ["Release"]),
            ("httpx 0.28.1 published", "PyPI", "security fix", 7, ["Release"]),
        ]
        out += ops.enumerated().map { i, o in
            row(.link, o.0, source: o.1, ref: "demo:\(o.1.lowercased()):\(i)",
                days: o.3, hour: 14, content: o.2, tags: o.4)
        }
        // REAL `asc:` ref shapes (2026-08-12). `WorkStage.ascOutcome` reads the
        // outcome STRAIGHT OUT OF THE REF — `asc:version:<id>:<STATE>` — and
        // `WorkStage.face` gives the `stars` face only to `asc:review:`. On
        // `demo:asc:N` refs both tests fail, so App Store Connect produced no
        // Work reading at all and the star face was unreachable: the whole
        // point of that seat (where is my build, what did a reviewer say) was
        // furnished in the feed and dead in the sheet.
        //
        // The fourth time this exact class has bitten — Peer, Privacy Pools
        // and the Obsidian vault were the others. A gate that keys on a ref
        // shape cannot be satisfied by a row that merely looks right.
        let asc: [(String, String, Double)] = [
            ("In review · Casberi 1.4", "asc:version:demo1:IN_REVIEW", 1),
            ("★★★★★ \"Finally, one place for everything\"", "asc:review:demo1", 3),
            ("Build 285 ready to test", "asc:build:demo285", 2),
            ("Build 274 expires in 9 days", "asc:buildexpiry:demo274", 5),
        ]
        out += asc.enumerated().map { i, a in
            row(.link, a.0, source: "App Store Connect", ref: a.1,
                days: a.2, hour: 10, content: "Casberi · iOS") { t in
                if i == 1 { t.summary = "Everything I save actually turns up when I look for it."
                            t.authorHandle = "grid_walker" }
                if i == 3 { t.dueAt = at(-9, 12) }
            }
        }
        // `.link`, NOT `.transaction`, and priced (2026-08-12). Stripe's rows
        // are Work rows: `StripeBridge` lands `kind: .link` with a tag and a
        // `priceValue`/`priceCurrency` pair, and `WorkStage.face` gives a
        // priced Stripe row the `money` face — the one Work face that inherits
        // the wallet's hero rung.
        //
        // The demo had them as `.transaction`, which is worse than a missing
        // face: `MoneyReceiptSource.receipt` gates on exactly that kind, so
        // every demo Stripe row drew a MONEY RECEIPT — an anatomy §369 built
        // for the nine wallet sources and never for Stripe — while
        // `ThingSheetView.workReading` stands down whenever a receipt exists.
        // So the demo showed the wrong anatomy AND suppressed the right one,
        // and both halves rendered perfectly. Parity runs in both directions:
        // the demo must not show what the app cannot.
        let stripe: [(title: String, days: Double, tag: String, amount: Double?)] = [
            ("Payout paid · $4,120.00", 2, "Payout", 4_120),
            ("Dispute opened · $89.00", 4, "Dispute", 89),
            ("Subscription canceled · Pro monthly", 11, "Churn", nil),
        ]
        out += stripe.enumerated().map { i, s in
            row(.link, s.title, source: "Stripe", ref: "demo:stripe:\(i)",
                days: s.days, hour: 13, tags: [s.tag]) { t in
                if let amount = s.amount {
                    t.priceValue = amount
                    t.priceCurrency = "USD"
                }
                // The dispute wears the SAME markers `StripeBridge` stamps on a
                // real one — `tag: "Dispute"` plus the evidence `dueAt`
                // (2026-08-10). Without the tag it had a deadline and nothing
                // else, so `NotifySweep.classify` answered nil and the demo
                // could not show the alerts callout at all: the row read as a
                // dispute to a human and as an ordinary transaction to every
                // piece of code that asks what it is. That is the §334 seat
                // problem one level down — a demo row that furnishes the feed
                // but exercises none of the logic keyed off it — and it is why
                // a demo row should carry a real bridge's markers, not just its
                // words.
                // The evidence deadline a real dispute carries — the tag now
                // rides the row's own `tags:` above, so this sets only the
                // clock (2026-08-10's reasoning, unchanged).
                if i == 1 { t.dueAt = at(-5, 17) }
            }
        }
        // Titled the way `HuggingFaceBridge` titles a release — "<owner>/<id>
        // · <noun>", with the OWNER on `authorHandle` and their mark on
        // `authorAvatarURL` (2026-08-14). The old rows led with the kind ("New
        // model · …"), a shape that bridge never lands, and named nobody — so
        // the demo's hub room drew three identical yellow glyphs where a real
        // one draws each lab's logo. A PAPER carries no mark on purpose: its
        // `authorHandle` is a human author with no hub account behind it, so
        // there is no picture to show and inventing one would be a claim.
        let hf: [(String, String, Double)] = [
            ("kyutai/moshi-v2 · Model", "kyutai", 1),
            ("Scaling laws for retrieval · Paper", "", 2),
            ("espresso-lab/open-espresso-1k · Dataset", "espresso-lab", 6),
        ]
        out += hf.enumerated().map { i, h in
            row(.link, h.0, source: "Hugging Face", ref: "demo:hf:\(i)", days: h.2, hour: 9) { t in
                if !h.1.isEmpty {
                    t.authorHandle = h.1
                    t.authorAvatarURL = publisherArt(h.1)
                }
                if i == 1 {
                    t.enrichedText = "We study how retrieval quality scales with corpus size."
                    t.previewImageURL = art(i)
                    t.authorHandle = "Rin Adeyemi"
                }
            }
        }
        // Radicle (prd §400) — the row shape the real bridge lands: the REPO
        // leads, then the verb, then the patch or issue title, with the
        // author's alias on `authorHandle`. Refs carry the real
        // `radicle:<kind>:<rid>:<id>:<event>` shape rather than a `demo:`
        // prefix — §349's lesson, where demo rows wearing a demo ref were
        // silently dropped by room heads matching on the bridge's real one.
        // No mark: Radicle publishes no avatar for a DID, so there is nothing
        // to show and inventing one would be a claim.
        // A DEMO rid, not heartwood's real one. Two reasons, both the
        // `cloudflare:cert:demo` reasoning: it is what lets `refPrefixes`
        // scope teardown to rows this file wrote, and it means a dev install
        // that genuinely watches heartwood can never have its real rows swept
        // up by `clear`/`teardown`. Shaped so `RadicleWire.normalizeRID`
        // accepts it.
        let radicleRID = "rad:zDEMOheartwood0000000000001"
        let radicle: [(String, String, [String], Double)] = [
            ("heartwood · merged · Fix seed discovery on cold start", "lorenz", ["Patch", "Merged"], 1),
            ("heartwood · patch · Cache the inventory read", "fintohaps", ["Patch", "Proposed"], 3),
            ("heartwood · issue · NO_COLOR disables all styling", "ade", ["Issue", "Opened"], 7),
        ]
        out += radicle.enumerated().map { i, r in
            let kind = r.2.first == "Issue" ? "issue" : "patch"
            let event = r.2.last?.lowercased() ?? "opened"
            return row(.link, r.0, source: "Radicle",
                ref: "radicle:\(kind):\(radicleRID):demo\(i):\(event == "proposed" ? "opened" : event)",
                days: r.3, hour: 11) { t in
                t.authorHandle = r.1
                t.tags = r.2
            }
        }
        let posthog: [(String, Double)] = [
            ("signed_up crossed 1,000", 3), ("Annotation · shipped the panel", 5),
            ("answer_asked has gone quiet", 8),
        ]
        out += posthog.enumerated().map { i, p in
            row(.note, p.0, source: "PostHog", ref: "demo:posthog:\(i)", days: p.1, hour: 16,
                content: "Casberi · production")
        }
        // The room head reads WATCH rows, not these alert rows — a watch IS
        // the `Thing` (`PostHogWatch.add`, the TokenWatch precedent), keyed
        // on `sourceRef: "posthog:metric:<event>"`, kind `.link`, tagged
        // "Watchlist". Without one for each event `PostHogRoomSource.compose`
        // has nothing to iterate and the head stays nil forever — found
        // building the room-head coverage check (2026-08-10): three alert
        // rows landed and the card never once appeared.
        out += ["signed_up", "answer_asked"].map { event in
            row(.link, IngestSupport.titleLine(event), source: "PostHog",
                ref: PostHogWatch.metricRef(event), days: 3, hour: 16,
                content: "https://us.posthog.com", tags: ["Watchlist"])
        }
        out += (0..<2).map { i in
            // No `twitch.tv/demo` content (P4, 2026-08-07) — "demo" is a
            // short, plausible handle that could belong to a REAL channel,
            // which is worse than an obvious dead link: tapping it could land
            // on a real stranger's stream with no warning it isn't ours.
            // Titled the way `TwitchBridge` titles a stream — "<name> live
            // — <game>", with the streamer on `authorHandle` (2026-08-12).
            // The old rows led with the STATE ("Live now · …", "Offline ·
            // …"), which is a shape that bridge never lands: liveness is
            // carried by `TwitchIngest.liveRefs`, not by the words, and
            // `DemoSeedAll.seedBridgeState` seeds ref 0 into it so the live
            // hero can actually draw.
            row(.link, ["nova live — Software and Game Development",
                        "kestrel live — Factorio"][i],
                source: "Twitch", ref: "demo:twitch:\(i)", days: Double(1 + i * 5), hour: 21) { t in
                t.previewImageURL = "sample:frame-\(i + 1)"
                t.authorHandle = ["nova", "kestrel"][i]
                // The streamer's face (2026-08-14). `TwitchIngest` reads it in
                // one batched `helix/users` call, so a real Twitch room leads
                // every row with the channel's picture and the live frame
                // rides after the title — the "both" pattern. Seeded without
                // it, the demo drew the purple Twitch glyph twice.
                t.authorAvatarURL = avatarArt(["nova", "kestrel"][i])
            }
        }
        // **The refs join the REAL `dropbox:` namespace (2026-08-17).**
        // `FilesBridge.isStoredPicture` decides picture-grid membership for
        // this room by reading the EXTENSION off a `dropbox:<path>` ref, so
        // under `demo:dropbox:2` the floor plan could never join the grid it
        // belongs in — the §349 shape, in the mixed room §283 built the grid
        // half for. They keep a "demo/" FOLDER segment so nothing real can
        // collide, the `files:demo/` and `obsidian:demo-vault/` shape, and
        // `refPrefixes` carries it so exit and re-stamp still reach them.
        //
        // The size line is per file too: every row said "PDF · 840 KB",
        // including the PNG.
        let dropbox: [(name: String, note: String)] = [
            ("Contract — joinery.pdf", "PDF · 840 KB"),
            ("Invoice 2026-081.pdf", "PDF · 210 KB"),
            ("Floor plan.png", "PNG · 1.4 MB"),
        ]
        out += dropbox.enumerated().map { i, f in
            row(.file, f.name, source: "Dropbox",
                ref: "dropbox:demo/\(f.name.lowercased())",
                days: Double(3 + i * 8), hour: 15, content: f.note)
        }
        // 1Claw grants, wearing what `OneClawFetch.policyThing` really stamps
        // (2026-08-12, prd §367): the joined title, the parts as fields, and the
        // ref shape the grant anatomy keys off. The old rows were `.approval`
        // things titled "Grant expires in 14 days" under `demo:1claw:<i>` —
        // sentences the bridge has never written, under a ref
        // `OneClawFetch.isGrantRef` answers false for, so the demo could not
        // show the grant sheet at all. The §349 lesson (a demo ref that does not
        // match the bridge's own shape is invisible to every reader keyed off
        // it), in a fourth place.
        //
        // ONE of the two has an expiry, deliberately: most grants have no clock,
        // and a demo where every grant is expiring teaches the reader that the
        // clock is the normal state rather than the exception it draws for.
        let grants: [(vault: String, path: String, perms: [String], expiring: Bool)] = [
            ("personal", "openai/*", ["read", "list"], true),
            ("work", "stripe/live/*", ["read"], false),
        ]
        out += grants.enumerated().map { i, g in
            let title = ([g.vault, g.path] + [g.perms.joined(separator: ", ")])
                .joined(separator: " · ")
            return row(.link, title, source: "1Claw", ref: "1claw:policy:demo\(i)",
                       days: Double(2 + i * 9), hour: 11,
                       content: OneClawFetch.dashboard,
                       tags: [OneClawFetch.grantTag] + g.perms) { t in
                t.summary = g.path
                t.authorHandle = g.vault
                if g.expiring { t.dueAt = at(-6, 12) }
            }
        }
        return out
    }

    // MARK: Writing and chats — the rooms that lead with a year grid

    /// Heatmap rooms need SPREAD, not volume: `AgentPanel.richness` scores a
    /// pulse on its LIVE DAYS, so twenty entries on one day rank below eight
    /// across eight weeks — and a grid with one bright smudge reads as a bug.
    private static func writing() -> [Thing] {
        var out: [Thing] = []
        // THE TWO JOURNALS SPAN YEARS (2026-08-17, prd §398). They were twelve
        // and eight entries inside one season, which is what a journal looks
        // like six weeks after you start one and nothing like the object
        // `JournalRoom` was built to read — so that head would have correctly
        // declined and `verify.sh`'s room-head coverage would have read the
        // decline as a gap. §375 seeded X's years for exactly this reason;
        // this is the same fix, two rooms over.
        //
        // Three things each list is shaped to carry, because each is a branch
        // of the card that would otherwise never draw in a demo: a STREAK (the
        // opening run of consecutive days — without one the headline takes its
        // fallback and the branch that reads a journal's own signature fact is
        // never seen), a SPAN past `minimumSpanDays`, and RECURRING SUBJECTS —
        // the same handful of places and people across a year, so
        // `ScreenshotTopics` has something that survives its recurrence floor
        // and the year rows carry a "mostly …" clause.
        //
        // Content is the entry's opening line and then its BODY, which is how
        // both importers really store it (`title` is the first line, `content`
        // is the whole thing). A seed whose content equalled its title made
        // every row draw a title and no excerpt, and would have hidden the
        // §398 `bodyBelowTitle` fix entirely.
        let dayOne: [(Double, String, String)] = [
            (2,   "Slow morning, long walk", "Out along the canal before anything else was awake. Berlin does this about four days a year and I keep forgetting to be outside for them."),
            (3,   "Wrote for an hour before anything else", "Kept the phone in the other room. Two pages, both keepable."),
            (4,   "Cooked properly for the first time in weeks", "Sam came over. We ate late and nobody looked at a screen."),
            (5,   "The panel finally looks like one thing", "Six weeks of it being four things stacked up. Today it stopped arguing with itself."),
            (11,  "Rain all day, read instead", "Finished the book I have been carrying around since Lisbon."),
            (18,  "Cleared the desk, cleared the head", "The studio is workable again."),
            (26,  "Ran the loop twice", "Slower than the spring but the whole way without stopping."),
            (33,  "Long call with Sam", "About the move, mostly. Neither of us said the obvious thing."),
            (41,  "Bought the tiles", "Green, in the end. The studio will look like somewhere."),
            (55,  "Quiet Sunday", "Nothing worth writing down, which is worth writing down."),
            (68,  "Started the new book", "Slow first fifty pages and I do not mind."),
            (82,  "Back from Lisbon", "Ten days and I did not open the laptop once."),
            (97,  "The last week before Lisbon", "Everything at once, the way it always is before going anywhere."),
            (113, "A better week than the one before", "Berlin finally warm. Ate outside three nights."),
            (130, "Sam's birthday", "Twelve of us round a table too small for twelve."),
            (152, "Moved the desk to the window", "Should have done it in January."),
            (174, "Cold snap", "Did not leave the studio for two days."),
            (196, "A year since the move", "Berlin still does not feel like a decision I made."),
            (221, "Long walk, no route", "Ended up somewhere I have never been, forty minutes from the flat."),
            (248, "Finished the thing", "Eight months. It is out and I feel nothing yet."),
            (275, "Sam is leaving", "Told me over coffee like it was ordinary news."),
            (305, "Studio day", "Nothing but the work from nine until it got dark."),
            (340, "Christmas, quietly", "Just the two of us and too much food."),
            (372, "New year, no list", "Trying it without one this time."),
            (405, "The Lisbon flat fell through", "Probably for the best. Berlin then."),
            (440, "Two weeks in", "The routine is holding, which is new."),
            (478, "Swimming again", "First time since school. Terrible and completely worth it."),
            (515, "A hard week", "Nothing specific. Wrote anyway, which was the point."),
            (552, "Sam moved back", "Round for dinner within a week, as if nothing had happened."),
            (596, "Spring, apparently", "The whole city outside at once."),
            (640, "Started keeping this", "Not sure what it is for yet. Every morning, ten minutes."),
            (688, "The flat is finally empty", "Boxes gone. Berlin from Monday."),
            (735, "Told them I was leaving", "Kinder about it than I deserved."),
            (790, "Something has to change", "Wrote three pages about it and did not solve anything."),
        ]
        // A HANDFUL CARRY A PHOTOGRAPH (prd §399, 2026-08-17). §398 landed both
        // journal exports' pictures and §399 is what finally draws them, so the
        // demo has to hold some or the one branch this pass exists for never
        // renders in the room anybody actually looks at. Four of thirty-four,
        // which is roughly how often a journal entry really has one — seeding
        // every entry would make the sheet read as a photo app.
        let dayOnePhotos: Set<Int> = [0, 11, 14, 18]
        out += dayOne.enumerated().map { i, e in
            row(.note, e.1, source: "Day One", ref: "demo:dayone:\(i)",
                days: e.0, hour: 21, content: "\(e.1)\n\(e.2)") { t in
                if dayOnePhotos.contains(i) { t.previewImageData = pixels(i) }
            }
        }
        let appleJournal: [(Double, String, String)] = [
            (7,   "A good week", "Three things went right and I noticed all three, which is the rarer part."),
            (8,   "Notes on the trip", "Lisbon again in the autumn if the work allows it."),
            (9,   "What I want from autumn", "Less of the calendar, more of the studio."),
            (16,  "Three things that worked", "Mornings without the phone. Walking to the studio. Saying no once."),
            (29,  "On finishing things", "The last ten per cent is the whole job and I keep pretending it isn't."),
            (44,  "A quieter month", "Deliberately. It worked."),
            (60,  "Reading again", "Two books in three weeks after a year of none."),
            (78,  "Small wins", "The shelf, the tiles, the invoice I had been avoiding since June."),
            (100, "Sam, after a long gap", "Picked up exactly where we left it."),
            (125, "The studio in summer", "Unbearable by two in the afternoon. Working mornings now."),
            (150, "Halfway", "Six months of this and it has not slipped once."),
            (180, "Berlin in the rain", "Better than Berlin in August, honestly."),
            (215, "A week off", "No plans made and none needed."),
            (255, "Back to it", "Slower start than I wanted. Fine."),
            (300, "The end of a long project", "Relief first, then the odd flatness that always follows."),
            (350, "Winter routine", "Dark by four. Studio lamps on from three."),
            (400, "Starting over on the same idea", "Third attempt. This one might hold."),
            (460, "Lisbon, briefly", "Four days. Came back with a plan I did not have going out."),
            (525, "Something worth keeping", "A conversation with Sam I have thought about every week since."),
            (600, "First entry", "Trying this properly. Every Sunday, whatever happened."),
        ]
        let journalPhotos: Set<Int> = [1, 11]
        out += appleJournal.enumerated().map { i, e in
            row(.note, e.1, source: "Apple Journal", ref: "demo:journal:\(i)",
                days: e.0, hour: 22, content: "\(e.1)\n\(e.2)") { t in
                if journalPhotos.contains(i) { t.previewImageData = pixels(i) }
            }
        }
        // WIDE ENOUGH FOR THE ROOM HEAD (2026-08-23, prd §457). This table was
        // six ChatGPT chats over 39 days, six Claude and three Gemini — under
        // every one of `AgentRoom`'s floors (12 conversations, 2 months, 45
        // days), so all four heads would have declined CORRECTLY and
        // `verify.sh`'s room-head coverage would have reported four gaps that
        // were not gaps. That is §375's lesson exactly, where the demo's X
        // room was seven posts in one season; a demo thin enough to make a
        // head decline is a demo that cannot tell a decline from a defect.
        //
        // The SHAPE is deliberate too, not just the volume. ChatGPT is spread
        // over the older half of the span and Claude is dense in the recent
        // one, so the cross-assistant line has a real crossover to find
        // (`AgentRoom.leadSince`) rather than one seat leading from the first
        // month — and Gemini trails both, which exercises the third branch,
        // the one that says so plainly instead of going quiet.
        //
        // The fourth field is TURNS, explicit per row rather than derived from
        // the index. The old `6 + (i % 9)` topped out at 14, below
        // `AgentRoom.longestFloor`, so no demo room could ever have drawn the
        // headline branch — the card's own lead, unreachable in the corpus
        // built to prove the card draws.
        let chats: [(String, String, Double, Int)] = [
            ("Designing a bento panel", "ChatGPT", 3, 9),
            ("SwiftData migration plan", "ChatGPT", 18, 31),
            ("Explain PCA simply", "ChatGPT", 33, 7),
            ("Naming things", "ChatGPT", 48, 12),
            ("Espresso ratios", "ChatGPT", 70, 5),
            ("Trip itinerary", "ChatGPT", 85, 18),
            ("Rewriting the onboarding copy", "ChatGPT", 100, 24),
            ("Why is this query slow", "ChatGPT", 115, 41),
            ("Reading list for the quarter", "ChatGPT", 130, 6),
            ("Explain CRDTs", "ChatGPT", 145, 15),
            ("Budget spreadsheet formulas", "ChatGPT", 160, 8),
            ("Draft the release notes", "ChatGPT", 175, 11),
            ("Compare two hosting options", "ChatGPT", 190, 19),
            ("Sourdough troubleshooting", "ChatGPT", 205, 7),
            ("Reviewing the panel ruling", "Claude", 1, 22),
            ("Writing the seed table", "Claude", 2, 14),
            ("Liveness corollaries, explained", "Claude", 4, 38),
            ("Copy for the connect screen", "Claude", 6, 9),
            ("Refactoring the composer", "Claude", 8, 27),
            ("Schema versioning", "Claude", 11, 16),
            ("The room-head ranking chain", "Claude", 14, 33),
            ("Why the harness passed wrongly", "Claude", 17, 45),
            ("Naming the two title kinds", "Claude", 21, 12),
            ("A month strip, not a year one", "Claude", 26, 20),
            ("Reading the export's shape", "Claude", 31, 29),
            ("Redundancy in the card", "Claude", 38, 8),
            ("Migrating the store", "Claude", 95, 17),
            ("An old question about layout", "Claude", 150, 6),
            ("First look at the corpus", "Claude", 200, 13),
            ("Summarise this paper", "Gemini", 6, 1),
            ("Translate the release notes", "Gemini", 15, 1),
            ("Compare these two charts", "Gemini", 30, 1),
            ("What is this plant", "Gemini", 45, 1),
            ("Convert these units", "Gemini", 60, 1),
            ("Summarise this thread", "Gemini", 75, 1),
            ("Rewrite this paragraph", "Gemini", 90, 1),
            ("Explain this error", "Gemini", 105, 1),
            ("Draft a short reply", "Gemini", 120, 1),
            ("Name three alternatives", "Gemini", 135, 1),
            ("Check this arithmetic", "Gemini", 150, 1),
            ("Translate a menu", "Gemini", 165, 1),
        ]
        out += chats.enumerated().map { i, c in
            // `content` is the OPENING ASK, exactly as all four importers land
            // it — not a description of the chat. The old seed wrote "A saved
            // conversation about x", which is a sentence no importer has ever
            // written and which the sheet would then set as the first thing you
            // read (2026-08-12, prd §367).
            row(.chat, c.0, source: c.1, ref: "demo:chat:\(c.1.lowercased()):\(i)",
                days: c.2, hour: 14, content: demoAsk(c.0)) { t in
                // Gemini's count is 1 BY CONSTRUCTION, not by coincidence:
                // Takeout carries one prompt per row, so anything else here
                // would be the demo teaching a reader something untrue about
                // their own export — and it is what makes `AgentRoom` decline
                // to name a "longest" in that room, which is the correct
                // answer there and the note branch of the card.
                let turns = c.3
                t.messageCount = turns
                // A REAL transcript in the importers' own wire format
                // (`"<Speaker>: <text>"`, newline-joined). The old seed put one
                // summarising sentence here, which parses to zero turns — so
                // the demo would have shown an empty conversation on the very
                // pass that exists to draw one, and `verify.sh` could not have
                // told that apart from the parser being broken.
                //
                // Gemini gets ONE turn and no reply, because that is what
                // Takeout actually carries (§367's one-sided clause): a demo
                // that invents a Gemini answer teaches the reader something
                // untrue about their own export.
                t.enrichedText = c.1 == "Gemini"
                    ? "You: \(demoAsk(c.0))"
                    : demoTranscript(ask: demoAsk(c.0), assistant: c.1,
                                     subject: c.0.lowercased(), turns: turns)
            }
        }
        // Claude Code's title shape is `ClaudeCodeSession.title(project:
        // headline:)` — "project · headline", never a join this file invents.
        // Twelve sessions over ten weeks (2026-08-23, prd §457) — three over
        // twelve days was under every `AgentRoom` floor, for the reason the
        // `chats` table above now carries in full.
        //
        // TWO projects, not one, because the project is a TAG and the room
        // narrows by it: a demo where every session ran in the same repo
        // cannot show that filter doing anything.
        let claudeCode: [(String, Int, Double)] = [
            ("casberi · Fix the demo room-head coverage gaps", 42, 1),
            ("casberi · Wire the source tray packing self-test", 18, 4),
            ("casberi · Chase the embedding race on foreground", 61, 12),
            ("casberi · Measure the transcript format", 88, 16),
            ("casberi · The month strip and its floors", 27, 23),
            ("casberi · Why the drift guard passed wrongly", 34, 30),
            ("notes-cli · First pass at the parser", 12, 38),
            ("notes-cli · Handle the empty-folder case", 9, 45),
            ("casberi · Redundancy sweep on the cards", 21, 52),
            ("notes-cli · Ship the release script", 15, 59),
            ("casberi · The comparison line's honesty rule", 36, 66),
            ("casberi · Read the ledger before proposing", 24, 71),
        ]
        out += claudeCode.enumerated().map { i, c in
            let headline = c.0.components(separatedBy: " · ").last ?? c.0
            // The project comes off the title rather than being hardcoded, so
            // the tag and the words can never disagree — which is what
            // `ClaudeCodeSession` guarantees on a real import, where both come
            // from the same `cwd`.
            let project = c.0.components(separatedBy: " · ").first ?? "casberi"
            return row(.chat, c.0, source: "Claude Code", ref: "demo:claudecode:\(i)",
                days: c.2, hour: 20,
                // The OPENING ASK, as `ClaudeCodeImport` lands it: the session
                // name is the title, and the ask is the subtitle beneath it.
                content: demoAsk(headline),
                tags: ["Session", project]) { t in
                t.messageCount = c.1
                // Claude Code's assistant label is "Claude", NOT the seat name
                // — the one thing about this wire format that is easy to get
                // wrong, so the demo carries the real spelling rather than a
                // plausible one (prd §367).
                t.enrichedText = demoTranscript(ask: headline, assistant: "Claude",
                                                subject: headline.lowercased(),
                                                turns: min(c.1, 8))
                // `Thing.summary` is deliberately NOT set (2026-08-23, prd
                // §457). It used to carry an invented sentence standing in for
                // a `summary` line — a line the format does not have, measured
                // across 247,085 real lines. The session's own name is the
                // TITLE now, and repeating it here would print it twice.
            }
        }
        out += (0..<10).map { i in
            row(.note, ["Roadmap", "Meeting notes — Tuesday", "Kitchen budget", "Trip plan",
                        "Reading list", "Panel spec", "Hiring loop", "Q4 goals",
                        "Home projects", "Recipes"][i],
                source: "Notion", ref: "demo:notion:\(i)", days: Double(2 + i * 7), hour: 12,
                content: "Page in your workspace") { t in
                // A page's cover and its date property (2026-08-17). The
                // Notion bridge stamps both and the demo had neither, so ten
                // pages drew as ten identical grey rows and none of the ones
                // with a real date ever reached the runway.
                //
                // Sparse on purpose, both of them: most Notion pages carry no
                // cover and no date, and a workspace where every page has both
                // is not a workspace anyone recognises.
                if i % 3 == 0 { t.previewImageURL = art(i) }
                if i == 1 || i == 4 { t.dueAt = at(-Double(5 + i * 6), 12) }
            }
        }
        out += (0..<3).map { i in
            row(.voice, ["Idea for the panel", "Shopping list", "Note to self — call Nils"][i],
                source: "Voice", ref: "demo:voice:\(i)", days: Double(1 + i * 4), hour: 8,
                content: "0:2\(i) · transcribed on device")
        }
        return out
    }

    /// The opening ask a demo chat landed with — a real question, because
    /// `content` on all four chat importers is the first user line and the
    /// sheet reads it as one (prd §367).
    private static func demoAsk(_ title: String) -> String {
        "How should I think about \(title.lowercased())?"
    }

    /// A demo transcript in the importers' OWN wire format — `"<Speaker>: …"`,
    /// newline-joined, oldest first (prd §367).
    ///
    /// Written as the format rather than as prose on purpose: `AgentSheet.turns`
    /// recovers turns by matching a known speaker at the start of a line, so a
    /// seed that reads well but is not in this shape parses to nothing and the
    /// demo shows an empty conversation — which is indistinguishable, from
    /// outside, from the parser being broken. One turn deliberately runs to two
    /// paragraphs, so the demo also exercises the rule that a newline inside an
    /// answer does NOT open a new turn.
    private static func demoTranscript(ask: String, assistant: String,
                                       subject: String, turns: Int) -> String {
        var lines = ["You: \(ask)",
                     "\(assistant): It helps to separate what's true of \(subject) from what's only "
                     + "conventional about it.\n\nThe first part is worth writing down; the second is "
                     + "worth re-deciding every time."]
        var i = 2
        while i < turns {
            lines.append(i % 2 == 0
                ? "You: And when that trade-off actually bites?"
                : "\(assistant): Then the cheaper instrument first, and the plausible fix second.")
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    /// A workout's own numbers, so the demo exercises `MetricBand` and the
    /// stub's duration (prd §365). Distance is stated only for the workouts
    /// that covered ground — a strength session has none, and inventing one
    /// would make the demo prove something the real bridge refuses to do.
    private static let workoutStats: [(km: Double?, minutes: Int, writer: String)] = [
        (5.2, 26, "Apple Watch"), (nil, 45, "Apple Watch"), (8.0, 41, "Apple Watch"),
        (22.0, 58, "Apple Watch"), (nil, 38, "Apple Watch"), (10.4, 53, "Apple Watch"),
        (1.2, 34, "Apple Watch"),
    ]

    /// `26:14` from whole minutes — the same shape `HealthIngest.clock` writes.
    private static func clock(_ minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d:%02d:00", minutes / 60, minutes % 60)
                      : String(format: "%d:00", minutes)
    }

    private static func workoutFacts(_ s: (km: Double?, minutes: Int, writer: String)) -> [String] {
        var facts: [ThingFact] = []
        if let km = s.km { facts.append(ThingFact("km", String(format: "%.2f", km), .metric)) }
        facts.append(ThingFact("Duration", clock(s.minutes), .metric))
        if let km = s.km, km > 0 {
            facts.append(ThingFact("Pace / km",
                                   clock(Int((Double(s.minutes) / km).rounded())), .metric))
        }
        facts.append(ThingFact("Written by", s.writer))
        return facts.map(\.encoded)
    }

    private static func fitness() -> [Thing] {
        var out: [Thing] = []
        out += (0..<14).map { i in
            let stats = workoutStats[i % 7]
            return row(.event, ["Run · 5.2 km", "Strength · upper", "Run · 8.0 km", "Cycle · 22 km",
                                "Strength · legs", "Run · 10.4 km", "Swim · 1,200 m"][i % 7],
                       source: "Apple Health", ref: "demo:health:\(i)",
                       days: Double(1 + i * 4), hour: 7, content: "Workout") { t in
                t.facts = workoutFacts(stats)
                t.endAt = t.capturedAt.addingTimeInterval(Double(stats.minutes) * 60)
            }
        }
        out += (0..<10).map { i in
            let stats = workoutStats[(i + 2) % 7]
            return row(.event, ["Morning run", "Hill repeats", "Long run", "Recovery jog", "Track night"][i % 5],
                       source: "Strava", ref: "demo:strava:\(i)",
                       days: Double(2 + i * 6), hour: 18, content: "Activity") { t in
                t.facts = workoutFacts(stats)
                t.endAt = t.capturedAt.addingTimeInterval(Double(stats.minutes) * 60)
            }
        }
        return out
    }

    private static func schedule() -> [Thing] {
        var out: [Thing] = []
        // Minutes and a place per event, so the demo exercises the stub's
        // range, its duration and its `.map` fact (prd §365). Standup carries
        // no place on purpose — a stub with only a clock is the common case and
        // must look right too.
        let events: [(String, Double, Int, Int, String?)] = [
            ("Standup", -0.3, 9, 15, nil),
            ("Design review", -1, 14, 60, "Studio, 2nd floor"),
            ("Dinner with Sam", -1, 19, 120, "Ilica 42, Zagreb"),
            ("Joiner site visit", -3, 11, 90, "Site — Hoyt Street"),
            ("Book club", -4, 19, 120, nil),
            ("Mira's birthday", -6, 0, 0, nil),
            ("Flight to Lisbon", -9, 8, 195, "Terminal 2"),
        ]
        out += events.enumerated().map { i, e in
            row(.event, e.0, source: "Calendar", ref: "demo:cal:\(i)", days: e.1, hour: e.2,
                content: "\(e.2):00 · calendar", tags: ["Work"]) { t in
                // Minutes of 0 means all-day — the stub must show the words,
                // never the midnight start EventKit reports for one. Seeded so
                // the demo covers that branch, which is otherwise invisible
                // until somebody's own calendar happens to hold a holiday.
                var facts: [ThingFact] = []
                if e.3 == 0 {
                    facts.append(ThingFact("When", "All day", .allDay))
                } else {
                    t.endAt = t.capturedAt.addingTimeInterval(Double(e.3) * 60)
                }
                if let place = e.4 { facts.append(ThingFact("Where", place, .map)) }
                t.facts = facts.map(\.encoded)
            }
        }
        let tasks: [(String, Double)] = [
            ("Order the tiles", -1), ("Send the joinery deposit", -2), ("Book the dentist", 1),
            ("Renew the passport", -12),
        ]
        out += tasks.enumerated().map { i, t in
            row(.reminder, t.0, source: "Todoist", ref: "demo:todoist:\(i)",
                days: max(0, t.1), hour: 9, content: "Inbox") { thing in
                thing.dueAt = at(t.1, 12)
                // A task's own note (2026-08-17) — `TokenBridges` stamps
                // Todoist's description onto `summary`, and without it the
                // demo's tasks were titles with nothing behind them.
                thing.summary = "\(t.0). Added from the inbox; no sub-tasks."
            }
        }
        out += (0..<2).map { i in
            row(.event, ["Intro call — 30 min", "Design pairing — 60 min"][i],
                source: ["Cal.com", "Calendly"][i], ref: "demo:booking:\(i)",
                days: Double(-2 - i * 2), hour: 15, content: "Booked by a guest") { t in
                t.endAt = t.capturedAt.addingTimeInterval(Double(i == 0 ? 30 : 60) * 60)
                // A booking's fact is WHO booked it — the thing a calendar
                // entry doesn't have, and the reason these two are their own
                // seats rather than more Calendar rows.
                t.facts = [ThingFact("Booked by", ["Ana Kovač", "Sam Rees"][i]).encoded]
            }
        }
        out += contactsAndHome()
        return out
    }

    /// The two Life seats that had NO demo rows at all (prd §365) — which is
    /// exactly why their sheets could render as grey prose for as long as they
    /// did: nothing in the demo, and therefore nothing in any screenshot sweep,
    /// ever opened one.
    ///
    /// Both are `Corpus.searchOnlySources`, so these never crowd the feed —
    /// they turn up when you search, which is the whole contract of those two
    /// bridges and is worth the demo proving.
    private static func contactsAndHome() -> [Thing] {
        var out: [Thing] = []
        // The sixth field is the cast face (2026-08-26). `ContactsIngest` stamps
        // `CNContact.thumbnailImageData` onto `previewImageData`, so a real
        // address book answers a search with people you recognize; the demo's
        // three carried none, and `PersonCard` falls back to INITIALS on a grey
        // disc — two letters standing in for a person, on the one card in this
        // app whose entire subject is who somebody is.
        let people: [(String, String, String, String, String, String)] = [
            ("Ana Kovač", "Designer", "Studio", "+385 91 234 5678", "ana@studio.com", "ana"),
            ("Sam Rees", "Joiner", "Rees & Sons", "+44 7700 900 118", "sam@reesandsons.co.uk", "samrees"),
            ("Mira Novak", "Architect", "Novak Atelier", "+385 98 765 4321", "mira@novakatelier.hr", "mira"),
        ]
        out += people.enumerated().map { i, p in
            row(.contact, p.0, source: "Contacts", ref: "demo:contact:\(i)",
                days: Double(30 + i), content: "\(p.1) · \(p.2) · \(p.4)") { t in
                t.previewImageData = facePixels(p.5)
                t.facts = [
                    ThingFact("Role", p.1), ThingFact("Company", p.2),
                    ThingFact("Mobile", p.3, .call), ThingFact("Work", p.4, .mail),
                ].map(\.encoded)
            }
        }
        // One of each state — a reachable accessory and an unreachable one —
        // because the whole point of this anatomy is that the two must not
        // render identically, and a demo with only the happy one proves
        // nothing.
        let accessories: [(String, String, String, Bool)] = [
            ("Front door", "Lock", "Entryway", true),
            ("Studio heater", "Thermostat", "Studio", true),
            ("Back gate", "Door", "Garden", false),
        ]
        out += accessories.enumerated().map { i, a in
            row(.accessory, a.0, source: "HomeKit", ref: "demo:homekit:\(i)",
                days: Double(20 + i),
                content: "\(a.1) · \(a.2) · \(a.3 ? "Reachable" : "Unreachable")") { t in
                t.facts = [
                    ThingFact("Checked just now",
                              a.3 ? "Reachable" : "Unreachable", .state),
                    ThingFact("Type", a.1), ThingFact("Room", a.2),
                ].map(\.encoded)
            }
        }
        return out
    }

    /// The two prediction rooms are LIVE rooms — they browse a book rather than
    /// sync rows — so a couple of watched markets is all a demo can honestly
    /// carry here.
    /// `watchPriceUsd` is the odds THE DAY YOU FOLLOWED — the anchor
    /// `PredictionRow` turns into "You followed at 42%" once a market
    /// settles (prd §235), and the only number in this room no market site
    /// can show you. Without it a settled row loses its receipt entirely.
    /// `marketResolvedYes` is what makes `demo:kalshi:1` a settled market;
    /// the matching odds live in `PredictionPulse.seedDemo`, which is what
    /// mounts these rows as `PredictionRow` at all.
    private static func odds() -> [Thing] {
        var out: [Thing] = []
        let kalshi: [(title: String, watchedAt: Double, settled: Bool)] = [
            ("Will the Fed cut rates in December?", 0.66, false),
            ("Will CPI come in under 3% in July?", 0.42, true),
        ]
        out += kalshi.enumerated().map { i, k in
            row(.link, k.title, source: "Kalshi", ref: "demo:kalshi:\(i)",
                days: Double(1 + i * 3), hour: 16) { t in
                t.watchPriceUsd = k.watchedAt
                if k.settled { t.marketResolvedYes = true }
                // WHEN THE MARKET CLOSES (2026-08-17). Both prediction bridges
                // stamp `dueAt = market.closeTime` — "a market's close IS a
                // real deadline", in `KalshiWatch`'s own words — and the demo
                // set it on neither, so its markets reached no runway, no
                // countdown and no "Needs you" tile. A watched market with no
                // close is the one fact about it that decides whether you still
                // have time to act.
                //
                // A SETTLED market's close is in the PAST, and getting that
                // backwards is worse than leaving it empty: a resolved market
                // wearing a future deadline reads as still open, on the row
                // whose whole point is that it isn't.
                t.dueAt = k.settled ? at(1, 16) : at(-21, 16)
            }
        }
        let poly: [(title: String, watchedAt: Double)] = [
            ("Champions League winner", 0.19),
            ("Will SpaceX launch Starship again in 2026?", 0.61),
        ]
        out += poly.enumerated().map { i, p in
            row(.link, p.title, source: "Polymarket", ref: "demo:polymarket:\(i)",
                days: Double(2 + i * 4), hour: 20) { t in
                t.watchPriceUsd = p.watchedAt
                // `PolymarketBridge` stamps the same field for the same reason
                // (see the Kalshi rows above). Both open, so both future — and
                // far enough out that they sort behind the week's real work
                // rather than crowding the top of a runway built for it.
                t.dueAt = at(Double(-45 - i * 15), 20)
            }
        }
        return out
    }

    // MARK: - Bridge state (the room heads that read UserDefaults, not rows)

    /// The demo wallet — one address, so `combinedValueSamples` has a complete
    /// set (it only starts once EVERY watched wallet has a sample). Internal,
    /// not private (2026-08-07): `DemoMode.restampIfStale` needs this exact
    /// address to find and shift the wallet curve it seeds below — a second
    /// copy of the literal is how that drifts silently.
    static let demoWallet = "0x1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"

    /// Every wallet the demo watches, in shelf order. The FIRST is
    /// `demoWallet` — the one every seeded row, the balance curve, the Safe
    /// snapshot and the approvals all key on, so it must stay first and must
    /// stay this address. The other two exist so the face shelf (§356) has a
    /// choice to offer; `walletFor(move:)` gives each of them a real share of
    /// the transfers, because a face that opens an empty room is the dead
    /// control §83 forbids.
    ///
    /// Labels are what a person would actually type — the demo banner already
    /// says none of this is theirs, so the wallets don't have to say it again.
    static let demoWallets: [(address: String, label: String)] = [
        (demoWallet, "Everyday"),
        ("0x7f3e9b2c5a184d6e0f9b3c7a2d5e8f1b4c6a9d20", "Savings"),
        ("0x4c8d1a7e3b9f2650c8d4a1e7b3f9526048d1a7e3", "Hardware"),
    ]

    /// Which watched wallet a given transfer belongs to. Most stay on the
    /// everyday wallet — the shelf should read as one wallet you live in and
    /// two you keep, not three equal thirds, because the first is what every
    /// other seeded reading (balance, curve, protocols) describes.
    static func walletFor(move index: Int) -> String {
        switch index {
        case 3, 8:  return demoWallets[1].address   // Sam, Mia — savings
        case 11:    return demoWallets[2].address   // the cold one, used once
        default:    return demoWallet
        }
    }

    /// Three heads compose from stored bridge state rather than corpus rows, so
    /// no amount of seeded things can make them draw: PostHog's metric curve,
    /// x402's seller treemap, and the wallet's balance curve. This plants
    /// exactly what each reads — no request, no key, no network.
    @MainActor
    private static func seedBridgeState() {
        // 0 · The live stream. `FeedScreen.isLive` reads
        // `TwitchIngest.liveRefs`, so without this the Twitch room's hero
        // card and float-to-top could never fire — see `TwitchIngest.seedDemo`.
        TwitchIngest.seedDemo(["demo:twitch:0"])

        // 0b · Walletbeat's stored ratings (prd §419). Without these every seeded
        // wallet reads "not read yet" and the room head draws no bars at all — the
        // PostHog lesson one seat over: a reading the composer cannot see is a head
        // that renders as nil while the rows beneath it look perfectly healthy.
        // `fetchedAt` is a FIXED date, never `.now`: these seeds must be
        // deterministic, and the field is only ever compared against the refresh
        // window, never displayed.
        var walletbeatCards: [String: WalletbeatCard] = [:]
        for id in demoWalletbeatIDs {
            guard let attributes = WalletbeatDirectory.demoAttributes[id],
                  let entry = WalletbeatDirectory.wallets.first(where: { $0.id == id })
            else { continue }
            walletbeatCards[id] = WalletbeatCard(
                walletID: id, name: entry.name, hardware: entry.hardware,
                stage: entry.stage, lastUpdated: entry.updated, site: nil,
                attributes: attributes,
                fetchedAt: Date(timeIntervalSince1970: 1_787_000_000))
        }
        if !walletbeatCards.isEmpty {
            var merged = WalletbeatState.cards()
            for (id, card) in walletbeatCards { merged[id] = card }
            WalletbeatState.replace(merged)
        }

        // 1 · The wallet's balance line. Spaced 4h+ apart so `recordSample`'s
        // throttle can never fold them into one point, and the newest sits 5
        // minutes back so a real fetch (there is none on a demo sim) wouldn't
        // append a seam onto the end of it.
        // THREE watched wallets, not one (2026-08-11). The wallet scope's face
        // shelf — the avatars under the room strip, §356 — gates on
        // `wallet.addresses.count > 1`, so a demo watching a single wallet
        // built the control correctly and gave it nothing to draw: the shelf
        // never appeared, and the demo looked a generation behind the app.
        // Not new state, just under-seeded state, which is the harder kind to
        // notice — nothing is missing, a control is simply below its own floor.
        //
        // Three rather than the cap of five: enough that the shelf is a real
        // choice and the "All" pill means something, few enough that each one
        // has a believable share of the transfers below.
        // PER WALLET, not all-or-nothing (2026-08-17). This used to be gated
        // on `addresses.isEmpty`, which meant the three landed only on a store
        // that had never watched anything — so ONE leftover watch (a dev
        // simulator, a previous run, a `-walletAddress` probe) seeded ZERO of
        // them and the demo watched a single wallet again. That is exactly the
        // state `verify.sh`'s floor step has been reporting since it landed
        // ("1 watched, 3 seeded"), and why that step is warn-only: the seeding
        // was conditional on a precondition nothing guarantees, so the shelf
        // it exists to fill drew nothing on any sim that had been used.
        //
        // Safe to ask per wallet because `add` is already dedupe-aware (it
        // compares in resolved form, so a demo address present under either
        // spelling is `.alreadyWatching`, not a second row), and `exit` removes
        // these BY ADDRESS, so a real watch sitting beside them is neither
        // clobbered on the way in nor forgotten on the way out. The one case
        // this still cannot satisfy is a store already at the five-wallet cap,
        // where `add` answers `.limitReached` — correct behaviour, and a state
        // no first-time opener is ever in.
        for wallet in demoWallets {
            _ = WalletStore.shared.add(wallet.address, label: wallet.label)
        }
        let curve: [Double] = [11_240, 11_180, 11_610, 11_540, 11_890, 12_050,
                               11_960, 12_310, 12_180, 12_460, 12_400, 12_480]
        let newest = Date.now.addingTimeInterval(-300)
        // EVERY watched wallet, not just the demo one — `combinedValueSamples`
        // only starts once all of them have a line, so a dev simulator with a
        // real address already watched would otherwise get no balance curve at
        // all and the panel would silently lose its hero. Each wallet after the
        // first gets a scaled copy so the stacked line has distinct bands
        // rather than one doubled.
        for (n, entry) in WalletStore.shared.addresses.enumerated() {
            let key = WalletStore.historyKey(entry.address)
            let existing = (UserDefaults.standard.data(forKey: key))
                .flatMap { try? JSONDecoder().decode([WalletStore.ValueSample].self, from: $0) }
            guard (existing?.count ?? 0) < 3 else { continue }
            let scale = n == 0 ? 1.0 : 1.0 / Double(n + 2)
            let samples = curve.enumerated().map { i, raw in
                let usd = raw * scale
                return WalletStore.ValueSample(
                    at: newest.addingTimeInterval(Double(i - (curve.count - 1)) * 4 * 3600),
                    usd: usd,
                    holdings: ["ETH": usd * 0.62, "USDC": usd * 0.28, "DEGEN": usd * 0.10])
            }
            if let data = try? JSONEncoder().encode(samples) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }

        // 2 · PostHog — the busiest watched metric's seven-day curve. `seeded`
        // is true because these are a READING, not a first sight: a metric
        // first seen at its current total has announced nothing legitimately.
        var metrics = PostHogState.all()
        // `fetchedAt` is what tells `PostHogRoomSource.compose` a reading has
        // ever been READ on this device (vs. a fresh row with no state
        // behind it) — omitting it left both metrics permanently "unread"
        // and the head nil no matter how the watch rows above were seeded.
        //
        // FOURTEEN days, not seven (2026-08-11). Both `PostHogRoom.change`
        // and the screen's own `weekChange` guard on `series.count >= 14` —
        // a week-over-week claim needs two weeks to compare — so a 7-point
        // series left every "this week against last" slot silently nil. The
        // curve drew, the totals read, and the one number the card is FOR
        // never appeared. Nothing was broken or missing; the series simply
        // sat under the floor its own reader declares, which is the shape of
        // demo drift no static check can see (the wallet face rail, one
        // screen over, the same day).
        //
        // Both series rise week over week — a demo should show the reading
        // working, and a fall would need the copy to explain itself.
        metrics["signed_up"] = PostHogState.Metric(
            total: 1_042,
            series: [15, 20, 24, 22, 30, 28, 35,
                     18, 24, 31, 27, 44, 39, 52],
            announced: 1_000, seeded: true, fetchedAt: .now)
        metrics["answer_asked"] = PostHogState.Metric(
            total: 6_310,
            series: [180, 205, 190, 220, 240, 215, 250,
                     210, 240, 198, 265, 288, 240, 301],
            announced: 5_000, seeded: true, fetchedAt: .now)
        PostHogState.replace(metrics)

        // 2b · Apple Wallet — its room head gates on its own bespoke
        // `connected` flag (a plain UserDefaults bool, distinct from the
        // generic catalog "connected" status `seats` grants below), which
        // nothing was ever setting. Found the same way as the PostHog gap.
        AppleWalletBridge.connected = true

        // 2c · App Store Connect — its room head gates on `ASCAuth.configured`
        // (a REAL `.p8` key in the Keychain), which a demo must never fake —
        // so `ASCRoomSource.compose` widens for `DemoMode.isActive` instead,
        // and this plants the standing it reads once that door is open.
        // Matches the alert row above ("In review · Casberi 1.4", build 285).
        ASCState.apps = ["casberi": "Casberi"]
        ASCState.standing = [
            "casberi": ASCStanding(
                appID: "casberi", app: "Casberi", version: "1.4",
                state: ASCVersionState.inReview.rawValue, since: at(1, 10), observed: true,
                build: "285", buildState: ASCBuildState.valid.rawValue, expires: nil),
        ]
        ASCState.lastRead = .now

        // Radicle's open work (prd §401). The head reads bridge STATE, not
        // rows, so seeding the three patch/issue rows above is not enough to
        // make it compose — this is what it actually reads. Dates match the
        // seeded rows, so the card and the room beneath it agree.
        RadicleStore.shared.seedDemo(
            rid: "rad:zDEMOheartwood0000000000001",
            name: "heartwood",
            open: [
                RadicleWire.OpenItem(kind: .issue, id: "demo2",
                                     title: "NO_COLOR disables all styling",
                                     opened: at(41, 11), isDraft: false),
                RadicleWire.OpenItem(kind: .patch, id: "demo1",
                                     title: "Cache the inventory read",
                                     opened: at(12, 11), isDraft: false),
                RadicleWire.OpenItem(kind: .patch, id: "demo3",
                                     title: "Try a smaller gossip window",
                                     opened: at(4, 11), isDraft: true),
            ])

        // 3 · A visit history, so the panel ranks on something.
        ChipMemory.seedDemo(demoVisits)

        // 4 · Circle x402 — the sellers behind the room's treemap. Service
        // counts are the measured shape of the real directory (Orthogonal
        // alone lists 310 of ~955 listings), so the map has one dominant cell
        // and a real tail rather than four equal blocks.
        X402State.save(sellers: [
            .init(slug: "orthogonal", name: "Orthogonal", services: 310, minPrice: 1_000,
                  maxPrice: 50_000, hasFree: false, lanes: ["Financial analysis", "Data enrichment"]),
            .init(slug: "quicknode", name: "QuickNode", services: 88, minPrice: 100,
                  maxPrice: 100, hasFree: true, lanes: ["Blockchain data"]),
            .init(slug: "chainbase", name: "Chainbase", services: 41, minPrice: 2_500,
                  maxPrice: 12_000, hasFree: false, lanes: ["Blockchain data"]),
            .init(slug: "aisa", name: "AIsa API", services: 18, minPrice: 400,
                  maxPrice: 9_000, hasFree: false, lanes: ["Prediction markets"]),
            .init(slug: "tollbit", name: "TollBit", services: 12, minPrice: 300,
                  maxPrice: 3_000, hasFree: true, lanes: ["Content"]),
        ], listings: 955, medianPrice: 1_000)

        // 5 · Cloudflare's estate snapshot — see `seedCloudflareEstate`'s own
        // doc for why the two cert rows alone don't reach the runway figure.
        seedCloudflareEstate()
        // 5b · Altana's keystore snapshot — see `seedAltanaKeystore`.
        seedAltanaKeystore()
        // 5c-i · Base Vibenet's balance history — the crown's sparkline.
        //
        // This seeds the REAL store the shipped app records into
        // (`VibenetValueStore`), never a demo-only curve. The distinction is
        // the whole reason the history exists: a demo drawing a chart the app
        // cannot draw is a promise about the product made on the screen people
        // judge it by. Live, this store fills from the sweep at one point
        // every four hours; here it is handed the same shape it would have
        // reached after a fortnight of watching, so the line the demo draws is
        // the line a real watcher gets.
        //
        // The walk is deterministic — no randomness, so two demo entries draw
        // the identical curve — and ends on `demoFixture`'s own native total
        // (2.514), because the crown states that number directly above the
        // line and a chart ending anywhere else would contradict it.
        seedVibenetHistory()
        seedVibenetSeenKeys()
        // 5c · Base Vibenet — the watch list, not the room's content.
        // `VibenetRoomSource.compose()` returns `VibenetRoom.demoFixture()`
        // whole under `DemoMode.isActive` and never touches these addresses
        // for what it DRAWS (this room keeps no persistence layer of its own
        // to seed a snapshot into, unlike Cloudflare/Altana above) — but
        // `VibenetScreen.connected` reads `VibenetWatch.shared` directly, so
        // without this the setup screen would show the empty "watch an
        // address" state over a catalog that claims the seat is connected.
        // The four addresses match the fixture's own, so a person who opens
        // the setup screen sees the same accounts the card already named.
        for address in [
            "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
            "0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c",
            "0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
            "0x4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e",
        ] { _ = VibenetWatch.shared.add(address) }
        // 5b · The anonymity sets behind the Privacy Pools deposits seeded in
        // `wallet()` (prd §397). Two numbers, and the pair is the point: the
        // CURRENT set, plus the set at the moment the oldest deposit in each
        // pool landed, which is the only way the card can say cover has GROWN.
        // Without this the room head still draws and the cover line is simply
        // absent — the silent-gap shape `verify.sh`'s room-head coverage step
        // exists to catch, one reading down.
        //
        // Symbols must match the `priceCurrency` those rows are stamped with
        // (`PrivacyPoolsCover`'s own rule); a mismatch unjoins the line with
        // nothing on screen to say so. Labels are the deposit refs minus their
        // prefix: `demo7` is the oldest ETH deposit, `demo2` the only USDC one.
        //
        // Deliberately NOT preceded by a wipe: `save(current:)` replaces the
        // live sizes wholesale anyway, and `snapshot` never overwrites, so a
        // real depositor's own landing snapshots — which cannot be re-bought,
        // being the size of a set at a moment that has passed — survive
        // entering the demo untouched.
        PrivacyPoolsCover.save(current: ["ETH": 4_180, "USDC": 742])
        PrivacyPoolsCover.snapshot(label: "demo7", count: 3_240)
        PrivacyPoolsCover.snapshot(label: "demo2", count: 690)
        // 6 · Safe's room head (2026-08-11) reads `SafeBridge`'s own bridge
        // state, not the seeded `.transaction` things above (`SafeRoomSource`'s
        // own doc) — refs match the `wallet:safe:eth:demo0/1` rows in `wallet()`
        // exactly, so a tap on either ring opens the real seeded thing.
        // Nonces are the point of the last two: 44 twice is a real rival pair,
        // so the head draws them adjacent, marks both rings and says only one
        // of them can execute. `demo0` sits 5 days back so the brief's stuck-
        // signature lede (`SafeRoom.stuckFloor`, 3 days) has something true to
        // say in the demo rather than shipping unseen.
        SafeBridge.seedDemoSnapshot(safeAddress: demoWallet, pending: [
            (ref: "wallet:safe:eth:demo0", have: 2, required: 3, yourTurn: true, daysAgo: 5,
             descriptionText: "a transfer of 1,500 USDC to payroll.eth", nonce: 42),
            (ref: "wallet:safe:eth:demo1", have: 3, required: 3, yourTurn: false, daysAgo: 4,
             descriptionText: "a transfer of 900 USDC to vendor.eth", nonce: 43),
            (ref: "wallet:safe:eth:demo2", have: 1, required: 3, yourTurn: false, daysAgo: 9,
             descriptionText: "an approval for Uniswap to spend 2,000 USDC", nonce: 44),
            (ref: "wallet:safe:eth:demo3", have: 1, required: 3, yourTurn: false, daysAgo: 6,
             descriptionText: "a revoke of Uniswap's spending approval", nonce: 44),
        ])

        // 8 · The watched social accounts (2026-08-11). The social rooms grew
        // a face rail (§362, the same control the wallets wear) which gates on
        // `accounts > 1`, and the SocialRosterHero it replaced was retired in
        // the same pass — so with no watched accounts seeded those rooms had
        // the rail's floor unmet AND the head it replaced gone: two features
        // deep, showing neither. Third instance today of existing state
        // sitting under a control's minimum (the wallet rail, PostHog's
        // fourteen days, now this).
        //
        // Handles match the authors on the seeded rows, and the cast is the
        // demo's own — Sam and Mia already move money in the wallet, Nils and
        // Uma already talk in Slack. One set of people across the whole demo
        // reads as a life; four disjoint sets read as filler.
        if FarcasterStore.shared.accounts.isEmpty {
            FarcasterStore.shared.accounts = demoFarcaster.map {
                var a = FarcasterStore.Account(username: $0.handle)
                a.displayName = $0.name
                a.bio = $0.bio
                a.avatarURL = avatarArt($0.handle)
                a.mine = $0.handle == "you"
                return a
            }
        }
        if BlueskyStore.shared.accounts.isEmpty {
            BlueskyStore.shared.accounts = demoBluesky.map {
                var a = BlueskyStore.Account(handle: $0.handle)
                a.displayName = $0.name
                a.bio = $0.bio
                a.avatarURL = avatarArt($0.handle)
                a.mine = $0.handle == "you"
                return a
            }
        }

        // Nostr's roster, which nothing seeded until 2026-08-12 — the third
        // social room had rows and no accounts, so its face rail and its
        // roster were empty while the other two were full. `pubkeyHex` is
        // filled because an account with an empty one reads as "still
        // resolving" forever, which is a spinner, not a demo.
        if NostrStore.shared.accounts.isEmpty {
            NostrStore.shared.accounts = demoNostr.map {
                var a = NostrStore.Account(input: $0.handle)
                a.pubkeyHex = $0.pubkey
                a.displayName = $0.name
                a.bio = $0.bio
                a.avatarURL = avatarArt($0.handle)
                return a
            }
        }

        // 7 · The address book — the counterparties the transfers above name,
        // so the wallet's people have faces. See `seedAddressBook`.
        seedAddressBook()

        // 9 · The wallet-riding seats' EVIDENCE. See `seedWalletSeatEvidence`.
        seedWalletSeatEvidence()
    }

    /// The evidence marks behind every `BridgeStore.walletSeats` member
    /// (2026-08-26, prd §484), and the reconcile that turns them into seats.
    ///
    /// **This fixes a latent bug as well as filling five gaps, and the bug is
    /// the more interesting half.** A wallet-riding seat is not claimed by
    /// `seatTable` alone — `reconcileWalletSeats()` re-derives all eleven from
    /// evidence and REMOVES any whose count is zero. The demo reaches no
    /// network, so it earns no evidence, and `BridgeRefresh.refreshAllConnected`
    /// returns before that reconcile while `DemoMode.isActive` — which is the
    /// only reason the demo's Peer, Privacy Pools, Railgun, Gnosis Pay and
    /// ether.fi seats survived at all. They did not survive a visit to their
    /// own setup screens: `PeerScreen`, `PrivacyPoolsScreen`, `RailgunScreen`,
    /// `SafeScreen` and the wallet picker each call `reconcileWalletSeats()`
    /// on appear, so opening any one of them mid-demo silently stripped those
    /// seats out of the catalog. Marking the evidence makes the reconcile
    /// AGREE with the seat table instead of fighting it, everywhere it runs.
    ///
    /// It also backs the five that had no seat at all — Aave, Morpho,
    /// Hyperliquid, Aerodrome and Uniswap — which is the honest reading now
    /// that the demo really does furnish each one's book
    /// (`WalletDemoState.state`): a seat is a claim about what is connected,
    /// and every one of those five draws a card in the demo's own Positions
    /// scope. Altana already did this one seat at a time (§403); this is the
    /// same act for the other eleven, in one place, so the next wallet-riding
    /// bridge has an obvious line to add itself to.
    ///
    /// **It marks and does not reconcile.** `reconcileWalletSeats()` needs a
    /// `BridgeStore`, which this path has none of — and calling it from
    /// `DemoMode.begin`, which does, would run BEFORE any of this, since the
    /// rows and the bridge state are poured after the mode is claimed. The
    /// seats themselves come from `seatTable` at `begin`; what this changes is
    /// that every later reconcile — a setup screen's `onAppear`, a foreground
    /// pass after the demo is left — now AGREES with that table instead of
    /// emptying it.
    ///
    /// Scoped to `demoWallet` alone rather than all three: the proof line
    /// states a COUNT, and every seeded position, deposit, fill and card
    /// spend keys on the first wallet, so "Watching 1 wallet" is the true
    /// sentence. Safe is absent on purpose — `SafeBridge.seedDemoSnapshot`
    /// marks its own detected registry (§6 above), which is what that seat
    /// counts, and a second mark here would be a second source of truth.
    /// `teardown` forgets every one of these by the same list.
    private static func seedWalletSeatEvidence() {
        for evidence in walletSeatEvidence { evidence.remember(demoWallet) }
    }

    /// Every wallet-riding seat's evidence mark, seeded together and forgotten
    /// together. ONE list, read by both halves — two copies is how a demo
    /// leaves a mark behind on the way out.
    private static let walletSeatEvidence: [WalletSeatEvidence] = [
        PeerBridge.evidence, PrivacyPoolsBridge.evidence, RailgunBridge.evidence,
        GnosisPayBridge.evidence, WalletDeFi.evidence, MorphoDeFi.evidence,
        HyperliquidDeFi.evidence, AerodromeDeFi.evidence, UniswapLiquidity.evidence,
        EtherFiUnstake.evidence, EtherFiCash.evidence,
    ]

    // MARK: - Seats

    /// The catalog seats a furnished demo should show as connected.
    ///
    /// Read by `BridgeStore.init` when nothing is saved yet — the store's own
    /// demo path, widened from the original eight. Ids follow the convention
    /// the real connect screens use (a lowercased, punctuation-free name);
    /// `registerConnected` dedupes on NAME, so a later real connection to any
    /// of these reconnects the same seat rather than adding a second.
    static var seats: [BridgeApp] {
        seatTable
            .map { entry in
                BridgeApp(id: entry.0.lowercased()
                            .replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: ".", with: ""),
                          name: entry.0, status: .connected, statusLine: entry.1,
                          can: [entry.2])
            }
    }

    /// name · status line · the one sentence the seat says it can do.
    private static let seatTable: [(String, String, String)] = [
        ("Obsidian", "Synced 4m ago", "Reads the notes in your vault."),
        ("CardPointers", "Synced 6m ago", "Reads the offers on your cards."),
        ("Files", "Synced 12m ago", "Reads a folder you point it at."),
        ("Dropbox", "Synced 1h ago", "Reads the folder you name."),
        ("X", "Imported 412 posts", "Holds the archive you exported."),
        ("Instagram", "Imported 336 items", "Holds the export you pointed at."),
        ("TikTok", "Imported 276 items", "Holds the export you pointed at."),
        ("Snapchat", "Imported 248 items", "Holds the export you pointed at."),
        ("Telegram", "4 channels · imported 214 items", "Follows public channels, read-only."),
        ("YouTube", "3 channels", "Follows channels without an account."),
        ("Reddit", "3 subreddits", "Follows subreddits, read-only."),
        ("RSS", "4 feeds", "Follows any feed you add."),
        ("Substack", "2 publications", "Follows writers you read."),
        ("Podcasts", "3 shows", "Follows shows you listen to."),
        ("Spotify", "Synced 20m ago", "Reads what you played."),
        ("Apple Music", "Synced 35m ago", "Reads what you played."),
        ("Steam", "Synced 2h ago", "Reads what you played."),
        ("Readwise", "Synced 1h ago", "Brings your highlights in."),
        ("Kindle", "Synced 3h ago", "Brings your highlights in."),
        ("Raindrop", "Synced 30m ago", "Reads your bookmarks."),
        ("Bookmarks", "Imported 3 links", "Holds the bookmarks you imported."),
        ("Pinterest", "Synced 1h ago", "Reads your pins."),
        ("iCloud Mail", "Synced 8m ago", "Reads your mail."),
        ("Farcaster", "2 accounts", "Follows accounts, no sign-in."),
        ("Bluesky", "1 account", "Follows accounts, no sign-in."),
        ("Nostr", "1 relay", "Reads the relays you name."),
        ("Stocktwits", "3 tickers", "Watches tickers you add."),
        ("GeckoTerminal", "3 chains", "Reads what's trending, keyless."),
        ("OpenSea", "2 chains", "Reads new drops, keyless."),
        ("Shopify", "1 store", "Watches a store's new arrivals."),
        ("Deals", "4 sources", "Reads public deal feeds."),
        ("Open Food Facts", "3 scans", "Reads the public food database."),
        ("Circle x402", "5 lanes", "Reads Circle's public directory."),
        ("Kalshi", "Browsing", "Reads the public order book."),
        ("Polymarket", "Browsing", "Reads the public order book."),
        ("Peer", "Rides your wallet", "Lands settled fills, never trades."),
        ("Privacy Pools", "Rides your wallet", "Reads your deposits' review status."),
        ("Altana", "Rides your wallet", "Reads which keys can sign for you."),
        // NOT "Rides your wallet" like its neighbours above — vibenet has
        // nothing to do with a watched mainnet wallet, it's its own address
        // list (`VibenetWatch`), the Farcaster/Bluesky/Stocktwits "N watched"
        // shape instead.
        ("Base Vibenet", "4 accounts watched", "Reads which keys can act for a watched account."),
        ("Gnosis Pay", "Rides your wallet", "Reads what the card settled onchain."),
        ("ether.fi", "Rides your wallet", "Reads what the card settled onchain."),
        // The five wallet-riding PROTOCOLS (2026-08-26, prd §484). They were
        // the largest hole in the demo — five connectable offers in the
        // catalog's biggest group, every one of them read on a real wallet by
        // `WalletWatch.liveState` every foreground pass, and none of them
        // claimed here. Their rows are not rows: each lands under
        // `source: "Wallet"` or nothing at all, so `demo-selftest.py` check E
        // cannot see them and they are named in its `KNOWN_ROWLESS_SEAT`,
        // where check M proves each one's BOOK instead. Aave, Morpho and
        // Aerodrome have drawn in the demo since §351; Uniswap and
        // Hyperliquid joined `WalletDemoState` in this pass, so all five now
        // say something in the Positions scope rather than merely appearing
        // in the catalog.
        ("Aave", "Rides your wallet", "Reads your collateral and debt."),
        ("Morpho", "Rides your wallet", "Reads your positions and vault deposits."),
        ("Hyperliquid", "Rides your wallet", "Reads your open positions and staked HYPE."),
        ("Aerodrome", "Rides your wallet", "Reads your veAERO locks."),
        ("Uniswap", "Rides your wallet", "Reads your liquidity, in range or out."),
        // The four exchanges (2026-08-26, prd §484). NOT "Rides your wallet" —
        // an exchange is a read-only KEY, the one thing the demo will not fake
        // (see `ExchangeBridge.demoBalances`), so the proof line states the
        // verdict that bridge's whole design turns on rather than a watch it
        // does not have. Their balances merge into the crown and the treemap
        // via `WalletPortfolio.demoFixture`; they land no rows, so they are
        // `KNOWN_ROWLESS_SEAT` members too.
        ("Coinbase", "Read-only key", "Reads your balances, never trades."),
        ("Kraken", "Read-only key", "Reads your balances, never trades."),
        ("Binance", "Read-only key", "Reads your balances, never trades."),
        ("Gemini Exchange", "Read-only key", "Reads your balances, never trades."),
        ("Apple Wallet", "Synced 6m ago", "Reads Apple Card, Cash and Savings."),
        ("Privacy", "Synced 2h ago", "Reads your virtual-card purchases."),
        ("Bitrefill", "Synced 4h ago", "Reads your orders and refills."),
        ("Stripe", "Synced 10m ago", "Reads what your money did."),
        ("PostHog", "2 metrics", "Reads the numbers behind what you ship."),
        ("GitHub", "Synced 5m ago", "Reads what you wrote."),
        ("GitLab", "Synced 10m ago", "Reads issues and merge requests assigned to you."),
        ("Jira", "Synced 20m ago", "Reads the issues assigned to you."),
        ("Claude Code", "Synced 1h ago", "Brings in your Claude Code sessions."),
        // Already had real seeded rows (the `chats` array's Gemini entries)
        // but no seatTable membership — the app catalog and the feed
        // disagreed, the exact §215/894481c failure the checks below exist
        // to catch. Found building the catalog-completeness check
        // (2026-08-11).
        ("Gemini", "Synced 30m ago", "Brings in your Gemini chats."),
        ("Railgun", "Synced 45m ago", "Reads your wallet's shielded moves."),
        ("Safe", "Synced 15m ago", "Reads your Safe's pending signatures."),
        ("Linear", "Synced 15m ago", "Reads the work assigned to you."),
        ("Notion", "Synced 25m ago", "Reads your pages."),
        ("Slack", "3 channels", "Reads the channels you name."),
        ("Trello", "Synced 40m ago", "Reads cards assigned to you."),
        ("Cursor", "Synced 1h ago", "Reads cloud agents that finished."),
        ("Radicle", "1 repo", "Reads patches and issues, keyless."),
        ("Walletbeat", "3 wallets", "Reads public wallet reviews, keyless."),
        ("L2BEAT", "3 chains", "Reads public layer-2 risk reviews, keyless."),
        ("Sentry", "Synced 20m ago", "Reads what broke."),
        ("Vercel", "Synced 12m ago", "Reads what deployed."),
        ("PagerDuty", "Synced 1h ago", "Reads what paged you."),
        ("Cloudflare", "Synced 30m ago", "Reads your site's own numbers."),
        ("npm", "2 packages", "Watches packages you publish."),
        ("PyPI", "1 package", "Watches packages you publish."),
        ("App Store Connect", "In review", "Reads where your build stands."),
        ("Hugging Face", "3 watched", "Reads new models and papers."),
        ("Twitch", "1 channel", "Reads who's live."),
        ("1Claw", "1 vault", "Reads which agents were granted what."),
        ("Day One", "Imported 34 entries", "Holds the journal you exported."),
        ("Apple Journal", "Imported 20 entries", "Holds the journal you exported."),
        ("Apple Health", "Synced 1h ago", "Reads your workouts."),
        ("Strava", "Rides Apple Health", "Reads activities Strava wrote."),
        ("Todoist", "Synced 18m ago", "Reads your tasks."),
        ("Cal.com", "Synced 2h ago", "Reads what people booked."),
        ("Calendly", "Synced 2h ago", "Reads what people booked."),
        // The two search-only Life seats (prd §365). Their rows never enter
        // the feed by design, so the seat is the only place the demo can say
        // they are connected at all.
        ("Contacts", "Synced 6m ago", "Reads the people you know."),
        ("HomeKit", "Live", "Reads your accessories, never controls them."),
        ("Voice", "3 notes", "Transcribes on device."),
    ]
}

/// A demo Altana key id that is REAL HEX — file-scope so both the (MainActor)
/// seeder and the nonisolated row builder can reach it.
///
/// The first cut spelled these `0xdem0…`, which reads nicely and is not hex:
/// `m` is not a hex digit, and the string was 63 characters rather than 64.
/// `AltanaKeySheet.parse` refuses both, correctly — so every demo key row fell
/// back to the generic link sheet while the room head, which never validates
/// an id, rendered perfectly. A demo that furnishes one surface and silently
/// starves another is the §349 class one layer down, and no static check
/// covers a sheet anatomy.
func demoAltanaKeyIDValue(_ n: Int) -> String {
    "0xde" + String(n) + String(repeating: "0", count: 61)
}
