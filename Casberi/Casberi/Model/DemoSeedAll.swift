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
    static let version = 1
    private static let versionKey = "demo.fullSeed.version"

    /// The three demo-watched tokens — (symbol, name, price, ref index),
    /// pulled up to a shared constant (2026-08-11) so `TokenPulse.seedDemo`
    /// can seed the SAME refs `rooms()` lands things under, rather than a
    /// second copy that can drift from it (the demo-parity discipline this
    /// file's own header states as a rule).
    static let tokenSeeds: [(symbol: String, name: String, price: Double, dayOffset: Double)] = [
        ("ETH", "Ethereum", 3_180, 1), ("SOL", "Solana", 176, 2),
        ("DEGEN", "Degen", 0.0071, 5),
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
                              // Peer/Privacy Pools rows carry the REAL
                              // bridges' own ref prefixes (2026-08-10, so
                              // their room heads' ref-shape matching
                              // recognises them) rather than the generic
                              // "demo:" family every other seed uses — so
                              // exit() needs its own entries or these rows
                              // outlive the demo, indistinguishable from a
                              // real synced deposit/fill.
                              "peer:demo", "privacypools:dep:demo",
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
                              "railgun:shield:demo", "railgun:unshield:demo"]

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
        if let index = WalletStore.shared.addresses
            .firstIndex(where: { $0.address.lowercased() == demoWallet.lowercased() }) {
            WalletStore.shared.remove(at: IndexSet(integer: index))
        }

        for event in demoMetrics { PostHogState.forget(event) }
        ChipMemory.forgetDemo(Array(demoVisits.keys))
        X402State.forget()
        // Same shape as PostHog above, and the same accepted risk: one
        // global cache, no per-account key, so this can't tell a demo
        // estate from a real one it might have overwritten — exactly what
        // `AccountScreen.demoReentryAvailable`'s own gate already exists to
        // keep off a lived-in install (a real Cloudflare bridge reads as
        // "Cloudflare" too, indistinguishable by name).
        CloudflareEstateStore.clear()

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
        SafeBridge.clearDemoSnapshot()

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

    /// The same picture as stored bytes, for the rooms that draw pixels from
    /// the corpus rather than a URL (Photos, Files, Snapchat memories).
    private static func pixels(_ n: Int) -> Data? {
        UIImage.demoSample(for: "sample:demo-shot-\((n % 4) + 1)")?
            .jpegData(compressionQuality: 0.7)
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
    static func rooms() -> [Thing] {
        var out: [Thing] = []
        out += photos()
        out += obsidian()
        out += xArchive()
        out += instagram()
        out += tiktok()
        out += snapchat()
        out += youtube()
        out += files()
        out += reading()
        out += listening()
        out += mail()
        out += saves()
        out += social()
        out += markets()
        out += walletRoom()
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
        return shots.enumerated().map { i, s in
            row(.screenshot, s.0, source: "Photos", ref: "sample:demo-shot-\(i + 5)",
                days: s.2, hour: s.3,
                content: "\(s.0)\n\(s.1.joined(separator: " · "))") { t in
                t.ocrTopics = s.1
                t.topicsAt = .now
                t.previewImageData = pixels(i)
            }
        }
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
        return notes.enumerated().map { i, n in
            row(.note, n.0, source: "Obsidian", ref: "demo:obsidian:\(i)",
                days: n.2, hour: 20, content: n.0) { t in
                t.ocrTopics = n.1
                t.topicsAt = .now
                t.enrichedText = "\(n.0)\n\nWritten in the vault. \(n.1.joined(separator: ", "))."
            }
        }
    }

    /// X is a `bulkImportSources` room: its rows stay out of ALL and it gets
    /// one receipt there instead. Posts are `.note` (the treemap's kind), likes
    /// are `.link` wearing somebody else's words — the split §308 draws.
    private static func xArchive() -> [Thing] {
        var out: [Thing] = [receipt("X", "412 posts · 180 liked", days: 3)]
        let posts: [(String, [String], Double)] = [
            ("Shipping is a habit, not an event.", ["Shipping", "Craft"], 4),
            ("The best interface is the one that answers.", ["Craft", "Interfaces"], 9),
            ("Shipping small beats planning big.", ["Shipping"], 16),
            ("Interfaces should say what they know.", ["Interfaces", "Craft"], 23),
            ("Craft is what survives the deadline.", ["Craft"], 31),
            ("Interfaces that hide state are lying.", ["Interfaces"], 44),
            ("Shipping again this week.", ["Shipping", "Craft"], 58),
        ]
        out += posts.enumerated().map { i, p in
            row(.note, p.0, source: "X", ref: "demo:x:post:\(i)", days: p.2, hour: 12,
                content: p.0, tags: ["Post"]) { t in
                t.postText = p.0
                t.ocrTopics = p.1
                t.topicsAt = .now
                t.authorHandle = "you"
                t.likeCount = 40 - i * 4
                t.replyCount = 6 - i / 2
            }
        }
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
                t.socialContext = "liked"
            }
        }
        return out
    }

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
                content: w.0) { t in
                t.ocrTopics = w.1
                t.topicsAt = .now
            }
        }
        let saved: [(String, String, Double)] = [
            ("Cafe with the marble counter", "@lisboneats", 8),
            ("Studio shelf, all wood", "@workspaces", 15),
            ("Ceramics, matte glaze", "@studiokoto", 22),
            ("Bakery window at six", "@lisboneats", 34),
            ("Desk setup, one lamp", "@workspaces", 48),
        ]
        out += saved.enumerated().map { i, s in
            row(.link, s.0, source: "Instagram", ref: "demo:ig:save:\(i)", days: s.2, hour: 23,
                tags: ["Saved"]) { t in
                t.authorHandle = s.1
                t.previewImageURL = art(i)
            }
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
                content: h.0)
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
                content: k.0)
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
                t.previewImageURL = art(i)
                t.enrichedText = "\(s.0) — by \(s.1) in \(s.2)."
            }
        }
        let rss: [(String, String, String, Double)] = [
            ("A quieter approach to notifications", "Dana Cole", "The Verge", 1),
            ("Inside a very small compiler", "Eli Rosen", "Hacker News", 4),
            ("The return of local-first", "Dana Cole", "The Verge", 7),
            ("Type systems, plainly", "Eli Rosen", "Hacker News", 15),
            ("Why your app feels slow", "Dana Cole", "TechCrunch", 24),
            ("The cost of a background sync", "Fay Ng", "TechCrunch", 32),
            ("Local-first, one year on", "Fay Ng", "The Verge", 41),
        ]
        out += rss.enumerated().map { i, r in
            row(.link, r.0, source: "RSS", ref: "demo:rss:\(i)", days: r.3, hour: 6) { t in
                t.postAuthor = r.1
                t.authorHandle = r.2
                t.previewImageURL = art(i)
                t.enrichedText = "\(r.0) — \(r.2)."
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
            row(.link, g.0, source: "Steam", ref: "demo:steam:\(i)", days: g.2, hour: 23,
                content: "Recently played · \(String(format: "%.1f", g.1))h in the last two weeks") { t in
                t.previewImageURL = art(i)
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
        out += raindrop.enumerated().map { i, u in
            row(.link, URL(string: u.0)?.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized ?? "Saved link",
                source: "Raindrop", ref: "demo:raindrop:\(i)", days: u.1, hour: 15,
                content: u.0)
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
    private static func social() -> [Thing] {
        var out: [Thing] = []
        let casts: [(String, String, String, Int, Double)] = [
            ("Shipped the panel today. Every room's figure in one place.", "/design", "you", 32, 1),
            ("A chart of everything at once is a chart of nothing.", "/design", "you", 21, 3),
            ("Reading about legibility again.", "/books", "you", 9, 6),
            ("The best demo is a real one.", "/design", "you", 44, 10),
            ("Onchain receipts are underrated.", "/base", "you", 12, 14),
            ("Books that changed how I plan.", "/books", "you", 7, 22),
            ("Base fees are basically nothing now.", "/base", "you", 15, 30),
        ]
        out += casts.enumerated().map { i, c in
            row(.chat, c.0, source: "Farcaster", ref: "demo:fc:\(i)", days: c.4, hour: 13) { t in
                t.postText = c.0
                t.channelName = c.1
                t.authorHandle = c.2
                t.likeCount = c.3
                t.replyCount = i % 4
                t.repostCount = i % 3
            }
        }
        let posts: [(String, String, Int, Double)] = [
            ("Small software, made carefully.", "you", 18, 2),
            ("The panel draws only figures. No sentences.", "you", 26, 4),
            ("Espresso and compilers, the eternal pairing.", "you", 11, 8),
            ("Local-first is just software that respects you.", "you", 33, 12),
            ("Notes from a quiet week.", "you", 6, 19),
            ("Reading, mostly.", "you", 4, 27),
        ]
        out += posts.enumerated().map { i, p in
            row(.chat, p.0, source: "Bluesky", ref: "demo:bsky:\(i)", days: p.3, hour: 16,
                content: "at://did:plc:demo/app.bsky.feed.post/\(i)") { t in
                t.postText = p.0
                t.authorHandle = p.1
                t.likeCount = p.2
                t.channelName = i % 2 == 0 ? "Design" : "Reading"
                t.replyCount = i % 3
            }
        }
        out += (0..<3).map { i in
            row(.chat, "Notes from the relays, part \(i + 1)", source: "Nostr",
                ref: "demo:nostr:\(i)", days: Double(3 + i * 9), hour: 20,
                content: "nostr:note1demo\(i)") { t in
                t.postText = "Notes from the relays, part \(i + 1)"
                t.authorHandle = "you"
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
        out += mood.enumerated().map { i, m in
            row(.chat, m.0, source: "Stocktwits", ref: "demo:stocktwits:\(i)",
                days: m.3, hour: 15, content: "$\(m.1) · \(m.0)",
                tags: m.2.isEmpty ? [m.1] : [m.1, m.2]) { t in
                t.authorHandle = "@trader\(i % 3)"
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
        out += tokenSeeds.enumerated().map { i, t in
            row(.link, "\(t.name) (\(t.symbol))", source: "Tokens", ref: "demo:token:\(i)",
                days: t.dayOffset, hour: 12) { thing in
                thing.watchPriceUsd = t.price
            }
        }
        out += (0..<3).map { i in
            row(.link, ["Trending on Base", "Trending on Solana", "Trending on Ethereum"][i],
                source: "GeckoTerminal", ref: "demo:gecko:\(i)", days: Double(1 + i * 3), hour: 14)
        }
        let drops: [(String, Double)] = [
            ("Terraforms by Mathcastles", 2), ("Opepen Edition", 5),
            ("Checks — VV Edition", 9), ("Blocks of Base", 16),
        ]
        out += drops.enumerated().map { i, d in
            row(.link, d.0, source: "OpenSea", ref: "demo:opensea:\(i)", days: d.1, hour: 19) { t in
                t.previewImageURL = art(i)
            }
        }
        let arrivals: [(String, String, Double)] = [
            ("Linen apron — natural", "€48", 1), ("Cast iron pan, 26cm", "€72", 3),
            ("Ceramic mug, set of two", "€34", 6), ("Oak chopping board", "€55", 12),
        ]
        out += arrivals.enumerated().map { i, a in
            row(.product, a.0, source: "Shopify", ref: "demo:shopify:\(i)", days: a.2, hour: 17,
                content: a.1) { t in
                t.previewImageURL = art(i)
                t.priceValue = Double(40 + i * 10)
                t.priceCurrency = "EUR"
            }
        }
        let deals: [(String, String, Double)] = [
            ("Anker 737 power bank — 38% off", "$89", 1),
            ("Kindle Paperwhite — lowest since March", "$109", 2),
            ("Baratza Encore — refurb", "$99", 4),
            ("AirPods Pro — $60 off", "$189", 7),
        ]
        out += deals.enumerated().map { i, d in
            row(.product, d.0, source: "Deals", ref: "demo:deals:\(i)", days: d.2, hour: 10,
                content: d.1) { t in
                t.previewImageURL = art(i)
            }
        }
        out += (0..<3).map { i in
            row(.product, ["Oat drink, barista", "Dark chocolate 70%", "Rye sourdough"][i],
                source: "Open Food Facts", ref: "demo:off:\(i)",
                days: Double(2 + i * 6), hour: 18,
                content: "Nutri-Score \(["B", "D", "A"][i]) · scanned")
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
                t.walletAddress = demoWallet
                t.transferDirection = m.0 ? "received" : "sent"
                t.transferAmount = m.1
                t.transferCounterparty = m.2
                t.counterpartyAddress = "0x" + String(repeating: "0", count: 36)
                    + String(format: "%04x", UInt16(0x1a00 + i))
                t.transferUSD = m.3
            }
        }
        // An approval, so the wallet room's exposure card has something real.
        out.append(row(.approval, "Uniswap can spend your USDC", source: "Wallet",
                       ref: "demo:wallet:approval:0", days: 6, hour: 14,
                       content: "https://revoke.cash/address/\(demoWallet)") { t in
            t.walletAddress = demoWallet
            t.grantedAt = at(6, 14)
        })
        // Privacy Pools rides the watched wallet; its rail reads the state TAG
        // `PrivacyPoolsBridge.retag` maintains, never the title's words.
        let pools: [(String, String, Double)] = [
            ("Put 0.0700 ETH into Privacy Pools", "Pending", 2),
            ("Put 0.1200 ETH into Privacy Pools", "Pending", 9),
            ("Put 0.2500 ETH into Privacy Pools", "Cleared", 17),
            ("Put 0.0400 ETH into Privacy Pools", "Cleared", 24),
            ("Put 0.3000 ETH into Privacy Pools", "Needs proof", 31),
            ("Put 0.0900 ETH into Privacy Pools", "Cleared", 45),
        ]
        out += pools.enumerated().map { i, p in
            // The ref must carry `PrivacyPoolsRoom.depositPrefix` — the room
            // head's `row(ref:tags:)` matches on that exact prefix, and a
            // `"demo:"`-prefixed ref (the family every other seed uses) falls
            // through as unrecognised, silently zeroing this card. Found
            // building the room-head coverage check (2026-08-10): all six
            // seeded deposits were landing and going straight to `nil`.
            row(.transaction, p.0, source: "Privacy Pools", ref: "privacypools:dep:demo\(i)",
                days: p.2, hour: 20, content: "Ethereum · 0xBow",
                tags: ["Shielded", p.1]) { t in
                t.walletAddress = demoWallet
                t.enrichedText = "The ETH pool holds about 3,900 accepted deposits."
            }
        }
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
        // Railgun ranks by token, read as DATA off `priceValue`/`priceCurrency`
        // — never parsed back out of the title. Ref must carry the real
        // `"railgun:shield:"`/`"railgun:unshield:"` prefix (`RailgunRoom
        // .direction(ref:)`'s exact match) or the move is dropped before
        // it's even counted, the same `"demo:"`-prefix miss as Peer/Privacy
        // Pools above.
        let railgunMoves: [(String, String, String, Double, Double)] = [
            ("Shielded 0.4000 ETH into Railgun", "shield", "ETH", 0.4000, 6),
            ("Shielded 500 DAI into Railgun", "shield", "DAI", 500, 14),
            ("Received 0.1500 ETH from Railgun", "unshield", "ETH", 0.1500, 23),
        ]
        out += railgunMoves.enumerated().map { i, r in
            row(.transaction, r.0, source: "Railgun", ref: "railgun:\(r.1):demo\(i)",
                days: r.4, hour: 21, content: "Ethereum · zk-SNARK") { t in
                t.walletAddress = demoWallet
                t.transferDirection = r.1 == "shield" ? "sent" : "received"
                t.priceValue = r.3
                t.priceCurrency = r.2
                if r.1 == "unshield" {
                    t.enrichedText = "Railgun can't tell you who sent this — inside the pool the sender is private by design."
                }
            }
        }
        // Safe gained its own source (2026-08-11, riding a Safe multisig's
        // pending-signature queue) — was "Wallet" before that, like Aave/
        // Morpho still are. Title shape and ref match `SafeBridge.swift`'s
        // real "N of M signatures collected on … — waiting on others / —
        // your signature is needed", `"wallet:safe:<chainSeg>:<txHash>"`.
        let safeTxs: [(String, Bool, Double)] = [
            ("2 of 3 signatures collected on sending 1,500 USDC to payroll.eth — your signature is needed", true, 2),
            ("1 of 3 signatures collected on approving Uniswap to spend 2,000 USDC — waiting on others", false, 9),
        ]
        out += safeTxs.enumerated().map { i, s in
            row(.transaction, s.0, source: "Safe", ref: "wallet:safe:eth:demo\(i)",
                days: s.2, hour: 15) { t in
                t.walletAddress = demoWallet
                if s.1 { t.tags = ["Your turn"] }
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
        out += (0..<3).map { i in
            row(.transaction, ["Netflix.com · $12.99", "Spotify · $10.99", "Figma · $15.00"][i],
                source: "Privacy", ref: "demo:privacy:\(i)", days: Double(4 + i * 10), hour: 8,
                content: "Virtual card · approved")
        }
        out += (0..<3).map { i in
            row(.transaction, ["Topped up €25 Amazon", "Bought $50 Uber gift card",
                               "Refilled €100 balance"][i],
                source: "Bitrefill", ref: "demo:bitrefill:\(i)",
                days: Double(6 + i * 14), hour: 19, content: "Paid in USDC")
        }
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
            row(.reminder, s.0, source: "Linear", ref: "demo:linear:\(i)", days: s.2, hour: 10,
                content: "Assigned to you") { t in
                t.mark = s.1
            }
        }
        let github: [(String, Double)] = [
            ("Merged: panel draws only figures (#412)", 1),
            ("Opened: seed every source on the sim (#414)", 1.5),
            ("Merged: serialize NLEmbedding inference (#409)", 6),
            ("Review requested: receipts reach map (#402)", 14),
        ]
        out += github.enumerated().map { i, g in
            row(.link, g.0, source: "GitHub", ref: "demo:github:\(i)", days: g.1, hour: 15) { t in
                t.starCount = 128 + i
                t.repoLanguage = "Swift"
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
        let ops: [(String, String, String, Double)] = [
            ("Resolved: elevated 5xx on the edge", "Sentry", "12 events", 2),
            ("New issue: nil unwrap in FeedScreen", "Sentry", "3 events", 6),
            ("Deployed casberi-site to production", "Vercel", "Ready in 24s", 1),
            ("Preview ready for pull/412", "Vercel", "Ready in 19s", 3),
            ("Acknowledged: latency alert", "PagerDuty", "Resolved in 8m", 8),
            ("casberi.app · 1.2M requests today", "Cloudflare", "Cached 92%", 1),
            ("Certificate renews in 21 days", "Cloudflare", "casberi.app", 4),
            ("swift-markdown 0.4.0 published", "npm", "2 dependents", 5),
            ("httpx 0.28.1 published", "PyPI", "security fix", 7),
        ]
        out += ops.enumerated().map { i, o in
            row(.link, o.0, source: o.1, ref: "demo:\(o.1.lowercased()):\(i)",
                days: o.3, hour: 14, content: o.2)
        }
        let asc: [(String, Double)] = [
            ("In review · Casberi 1.4", 1), ("★★★★★ \"Finally, one place for everything\"", 3),
            ("Build 285 ready to test", 2), ("Build 274 expires in 9 days", 5),
        ]
        out += asc.enumerated().map { i, a in
            row(.link, a.0, source: "App Store Connect", ref: "demo:asc:\(i)",
                days: a.1, hour: 10, content: "Casberi · iOS") { t in
                if i == 1 { t.summary = "Everything I save actually turns up when I look for it."
                            t.authorHandle = "grid_walker" }
                if i == 3 { t.dueAt = at(-9, 12) }
            }
        }
        let stripe: [(String, Double)] = [
            ("Payout paid · $4,120.00", 2), ("Dispute opened · $89.00", 4),
            ("Subscription canceled · Pro monthly", 11),
        ]
        out += stripe.enumerated().map { i, s in
            row(.transaction, s.0, source: "Stripe", ref: "demo:stripe:\(i)", days: s.1, hour: 13) { t in
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
                if i == 1 { t.dueAt = at(-5, 17); t.tags = ["Dispute"] }
            }
        }
        let hf: [(String, Double)] = [
            ("New model · kyutai/moshi-v2", 1), ("Daily paper · Scaling laws for retrieval", 2),
            ("New dataset · open-espresso-1k", 6),
        ]
        out += hf.enumerated().map { i, h in
            row(.link, h.0, source: "Hugging Face", ref: "demo:hf:\(i)", days: h.1, hour: 9) { t in
                if i == 1 {
                    t.enrichedText = "We study how retrieval quality scales with corpus size."
                    t.previewImageURL = art(i)
                }
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
            row(.link, ["Live now · building the panel", "Offline · last streamed Tuesday"][i],
                source: "Twitch", ref: "demo:twitch:\(i)", days: Double(1 + i * 5), hour: 21) { t in
                t.previewImageURL = art(i)
            }
        }
        out += (0..<3).map { i in
            row(.file, ["Contract — joinery.pdf", "Invoice 2026-081.pdf", "Floor plan.png"][i],
                source: "Dropbox", ref: "demo:dropbox:\(i)", days: Double(3 + i * 8), hour: 15,
                content: "PDF · 840 KB")
        }
        out += (0..<2).map { i in
            row(.approval, ["Vault read granted to Claude Desktop",
                            "Grant expires in 14 days"][i],
                source: "1Claw", ref: "demo:1claw:\(i)", days: Double(2 + i * 9), hour: 11,
                content: "Vault · personal") { t in
                if i == 1 { t.dueAt = at(-14, 12) }
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
        let journal = ["Slow morning, long walk", "Wrote for an hour before anything else",
                       "The panel finally looks like one thing", "Rain all day, read instead",
                       "Cooked properly for the first time in weeks", "Long call with Sam",
                       "Cleared the desk, cleared the head", "Ran the loop twice",
                       "Bought the tiles", "Quiet Sunday", "Fixed the shelf", "Started the new book"]
        out += journal.enumerated().map { i, j in
            row(.note, j, source: "Day One", ref: "demo:dayone:\(i)",
                days: Double(1 + i * 6), hour: 21, content: j)
        }
        out += (0..<8).map { i in
            row(.note, ["A good week", "Notes on the trip", "What I want from autumn",
                        "Three things that worked", "On finishing things", "A quieter month",
                        "Reading again", "Small wins"][i],
                source: "Apple Journal", ref: "demo:journal:\(i)",
                days: Double(3 + i * 9), hour: 22, content: "Journal entry")
        }
        let chats: [(String, String, Double)] = [
            ("Designing a bento panel", "ChatGPT", 1), ("SwiftData migration plan", "ChatGPT", 5),
            ("Explain PCA simply", "ChatGPT", 12), ("Naming things", "ChatGPT", 19),
            ("Espresso ratios", "ChatGPT", 28), ("Trip itinerary", "ChatGPT", 40),
            ("Reviewing the panel ruling", "Claude", 2), ("Writing the seed table", "Claude", 3),
            ("Liveness corollaries, explained", "Claude", 9), ("Copy for the connect screen", "Claude", 16),
            ("Refactoring the composer", "Claude", 24), ("Schema versioning", "Claude", 37),
            ("Summarise this paper", "Gemini", 6), ("Translate the release notes", "Gemini", 15),
            ("Compare these two charts", "Gemini", 30),
        ]
        out += chats.enumerated().map { i, c in
            row(.chat, c.0, source: c.1, ref: "demo:chat:\(c.1.lowercased()):\(i)",
                days: c.2, hour: 14, content: "A saved conversation about \(c.0.lowercased()).") { t in
                t.messageCount = 6 + (i % 9)
                t.enrichedText = "The thread settles on a plan for \(c.0.lowercased())."
            }
        }
        // Claude Code's title shape is `ClaudeCodeSession.title(project:
        // headline:)` — "project · headline", never a join this file invents.
        let claudeCode: [(String, Int, Double)] = [
            ("casberi · Fix the demo room-head coverage gaps", 42, 1),
            ("casberi · Wire the source tray packing self-test", 18, 4),
            ("casberi · Chase the embedding race on foreground", 61, 12),
        ]
        out += claudeCode.enumerated().map { i, c in
            row(.chat, c.0, source: "Claude Code", ref: "demo:claudecode:\(i)",
                days: c.2, hour: 20, tags: ["Session", "casberi"]) { t in
                t.messageCount = c.1
            }
        }
        out += (0..<10).map { i in
            row(.note, ["Roadmap", "Meeting notes — Tuesday", "Kitchen budget", "Trip plan",
                        "Reading list", "Panel spec", "Hiring loop", "Q4 goals",
                        "Home projects", "Recipes"][i],
                source: "Notion", ref: "demo:notion:\(i)", days: Double(2 + i * 7), hour: 12,
                content: "Page in your workspace")
        }
        out += (0..<3).map { i in
            row(.voice, ["Idea for the panel", "Shopping list", "Note to self — call Nils"][i],
                source: "Voice", ref: "demo:voice:\(i)", days: Double(1 + i * 4), hour: 8,
                content: "0:2\(i) · transcribed on device")
        }
        return out
    }

    private static func fitness() -> [Thing] {
        var out: [Thing] = []
        out += (0..<14).map { i in
            row(.event, ["Run · 5.2 km", "Strength · upper", "Run · 8.0 km", "Cycle · 22 km",
                         "Strength · legs", "Run · 10.4 km", "Swim · 1,200 m"][i % 7],
                source: "Apple Health", ref: "demo:health:\(i)",
                days: Double(1 + i * 4), hour: 7, content: "Workout")
        }
        out += (0..<10).map { i in
            row(.event, ["Morning run", "Hill repeats", "Long run", "Recovery jog", "Track night"][i % 5],
                source: "Strava", ref: "demo:strava:\(i)",
                days: Double(2 + i * 6), hour: 18, content: "Activity")
        }
        return out
    }

    private static func schedule() -> [Thing] {
        var out: [Thing] = []
        let events: [(String, Double, Int)] = [
            ("Standup", -0.3, 9), ("Design review", -1, 14), ("Dinner with Sam", -1, 19),
            ("Joiner site visit", -3, 11), ("Book club", -4, 19), ("Flight to Lisbon", -9, 8),
        ]
        out += events.enumerated().map { i, e in
            row(.event, e.0, source: "Calendar", ref: "demo:cal:\(i)", days: e.1, hour: e.2,
                content: "\(e.2):00 · calendar")
        }
        let tasks: [(String, Double)] = [
            ("Order the tiles", -1), ("Send the joinery deposit", -2), ("Book the dentist", 1),
            ("Renew the passport", -12),
        ]
        out += tasks.enumerated().map { i, t in
            row(.reminder, t.0, source: "Todoist", ref: "demo:todoist:\(i)",
                days: max(0, t.1), hour: 9, content: "Inbox") { thing in
                thing.dueAt = at(t.1, 12)
            }
        }
        out += (0..<2).map { i in
            row(.event, ["Intro call — 30 min", "Design pairing — 60 min"][i],
                source: ["Cal.com", "Calendly"][i], ref: "demo:booking:\(i)",
                days: Double(-2 - i * 2), hour: 15, content: "Booked by a guest")
        }
        return out
    }

    /// The two prediction rooms are LIVE rooms — they browse a book rather than
    /// sync rows — so a couple of watched markets is all a demo can honestly
    /// carry here.
    private static func odds() -> [Thing] {
        var out: [Thing] = []
        out += (0..<2).map { i in
            row(.link, ["Will the Fed cut in December?",
                        "Highest temperature in Lisbon this week?"][i],
                source: "Kalshi", ref: "demo:kalshi:\(i)", days: Double(1 + i * 3), hour: 16)
        }
        out += (0..<2).map { i in
            row(.link, ["Champions League winner", "Will SpaceX launch Starship again in 2026?"][i],
                source: "Polymarket", ref: "demo:polymarket:\(i)", days: Double(2 + i * 4), hour: 20)
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

    /// Three heads compose from stored bridge state rather than corpus rows, so
    /// no amount of seeded things can make them draw: PostHog's metric curve,
    /// x402's seller treemap, and the wallet's balance curve. This plants
    /// exactly what each reads — no request, no key, no network.
    @MainActor
    private static func seedBridgeState() {
        // 1 · The wallet's balance line. Spaced 4h+ apart so `recordSample`'s
        // throttle can never fold them into one point, and the newest sits 5
        // minutes back so a real fetch (there is none on a demo sim) wouldn't
        // append a seam onto the end of it.
        if WalletStore.shared.addresses.isEmpty {
            _ = WalletStore.shared.add(demoWallet, label: "Demo wallet")
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
        metrics["signed_up"] = PostHogState.Metric(
            total: 1_042, series: [18, 24, 31, 27, 44, 39, 52], announced: 1_000,
            seeded: true, fetchedAt: .now)
        metrics["answer_asked"] = PostHogState.Metric(
            total: 6_310, series: [210, 240, 198, 265, 288, 240, 301], announced: 5_000,
            seeded: true, fetchedAt: .now)
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
        // 6 · Safe's room head (2026-08-11) reads `SafeBridge`'s own bridge
        // state, not the seeded `.transaction` things above (`SafeRoomSource`'s
        // own doc) — refs match the `wallet:safe:eth:demo0/1` rows in `wallet()`
        // exactly, so a tap on either ring opens the real seeded thing.
        SafeBridge.seedDemoSnapshot(safeAddress: demoWallet, pending: [
            (ref: "wallet:safe:eth:demo0", have: 2, required: 3, yourTurn: true, daysAgo: 2,
             descriptionText: "a transfer of 1,500 USDC to payroll.eth"),
            (ref: "wallet:safe:eth:demo1", have: 1, required: 3, yourTurn: false, daysAgo: 9,
             descriptionText: "an approval for Uniswap to spend 2,000 USDC"),
        ])
    }

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
        ("Files", "Synced 12m ago", "Reads a folder you point it at."),
        ("Dropbox", "Synced 1h ago", "Reads the folder you name."),
        ("X", "Imported 412 posts", "Holds the archive you exported."),
        ("Instagram", "Imported 336 items", "Holds the export you pointed at."),
        ("TikTok", "Imported 276 items", "Holds the export you pointed at."),
        ("Snapchat", "Imported 248 items", "Holds the export you pointed at."),
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
        ("Gnosis Pay", "Rides your wallet", "Reads what the card settled onchain."),
        ("ether.fi", "Rides your wallet", "Reads what the card settled onchain."),
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
        ("Day One", "Imported 12 entries", "Holds the journal you exported."),
        ("Apple Journal", "Imported 8 entries", "Holds the journal you exported."),
        ("Apple Health", "Synced 1h ago", "Reads your workouts."),
        ("Strava", "Rides Apple Health", "Reads activities Strava wrote."),
        ("Todoist", "Synced 18m ago", "Reads your tasks."),
        ("Cal.com", "Synced 2h ago", "Reads what people booked."),
        ("Calendly", "Synced 2h ago", "Reads what people booked."),
        ("Voice", "3 notes", "Transcribes on device."),
    ]
}
