#if DEBUG
import Foundation
import SwiftData
import UIKit

/// The demo CENSUS — `-demoCensus YES` (2026-09-05).
///
/// One launch, every surface the app can draw over a populated corpus, each
/// asked the same question over the poured demo: *does it draw?* The room-head
/// step in `verify.sh` asks that of ~28 source heads; the sheet-anatomy step
/// asks it of seven anatomies; the All-room step asks it of the opening
/// screen. This asks it of everything else — the ask kinds, search, the widgets,
/// the notify plan, related/links/facts, the wallet cards, the social rosters,
/// the sheet verbs, and every room the demo furnishes that the head map never
/// named — and prints one line per surface:
///
///     demoCensus| <surface> | required|ranked | ok|empty|skipped | <detail>
///
/// `required` surfaces are a pure function of the corpus (no ranking, no model,
/// no network): an `empty` there is a real gap and `verify.sh` HARD-FAILS on it.
/// `ranked` surfaces compete for a slot or depend on the on-device model, so an
/// `empty` warns. `skipped` names a precondition the host cannot meet (no
/// on-device model on a simulator) and is never a failure — it is printed so
/// the gap in evidence is visible rather than silently green.
///
/// WHY IN-PROCESS AND NOT ~30 PROBE LAUNCHES: every surface here already has a
/// `-…Probe` hook, and none of them ever ran over the demo, because each costs
/// a terminate + launch + poll (~3.4s) and nobody strung thirty of them
/// together. This calls the same composers the probes call, in one process, so
/// what is asserted is what the probes would have said — only the launches are
/// gone (the `-roomInsightSweep` lesson, one level up).
///
/// The registry is a Swift array so a new surface is one row; the closing line
/// carries the row count, and `verify.sh` refuses a log whose row count does
/// not match, so a surface that crashed mid-census cannot pass by silence.
@MainActor
enum DemoCensus {
    enum Gate: String { case required, ranked }
    enum Verdict {
        case ok(String), empty(String), skipped(String)
        var word: String {
            switch self {
            case .ok: return "ok"
            case .empty: return "empty"
            case .skipped: return "skipped"
            }
        }
        var detail: String {
            switch self {
            case .ok(let d), .empty(let d), .skipped(let d): return d
            }
        }
    }
    struct Surface {
        let name: String
        let gate: Gate
        let read: @MainActor () async -> Verdict
    }

    /// No hand list of "rooms that lead with rows on purpose". A room with a
    /// bespoke `FeedScreen.Shape` is judged by its own surface below and
    /// reported `skipped` here; a plain room that leads with rows is reported
    /// `empty`, and `verify.sh` decides whether that is a gap by reading
    /// `FeedInsight.swift` itself — a source named in one of its insight
    /// switches and still leading with rows is a gap; a source named nowhere
    /// leads with rows in the real app too, and the demo is faithful to that.

    static func run(context: ModelContext, store: BridgeStore) async {
        // The pour lands in a prior launch under `verify.sh`; on a bare
        // `-demoEnter YES -demoCensus YES` run it is still landing, so wait for
        // the pending flag to clear (bounded — a stuck pour is its own finding).
        for _ in 0..<60 where UserDefaults.standard.bool(forKey: "demo.mode.pourPending") {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard DemoMode.isActive else {
            NSLog("[Casberi] demoCensus: demo is not active — pair with -demoEnter YES")
            return
        }
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 2000
        let all = ((try? context.fetch(d)) ?? []).live
        let surfaced = Corpus.surfaced(all)
        NSLog("[Casberi] demoCensus: begin things=%d surfaced=%d embedding=%@ model=%@",
              all.count, surfaced.count,
              EmbeddingIndex.isAvailable ? "YES" : "NO",
              OnDeviceModel.isAvailable ? "YES" : "NO")

        // Retrieval-shaped surfaces read vectors; index the poured rows first
        // (bounded by the store's own batch loop — ~400 rows is a few seconds).
        if EmbeddingIndex.isAvailable {
            let n = await EmbeddingIndex.indexPending(context: context)
            NSLog("[Casberi] demoCensus: indexed %d pending rows", n)
        }

        let surfaces = registry(all: all, surfaced: surfaced, context: context, store: store)
        var ok = 0, empty = 0, skipped = 0
        for s in surfaces {
            let v = await s.read()
            switch v {
            case .ok: ok += 1
            case .empty: empty += 1
            case .skipped: skipped += 1
            }
            NSLog("[Casberi] demoCensus| %@ | %@ | %@ | %@", s.name, s.gate.rawValue, v.word, v.detail)
        }
        NSLog("[Casberi] demoCensus: done (%d surfaces, ok=%d empty=%d skipped=%d)",
              surfaces.count, ok, empty, skipped)
    }

    // MARK: - The registry

    private static func registry(all: [Thing], surfaced: [Thing], context: ModelContext,
                                 store: BridgeStore) -> [Surface] {
        var out: [Surface] = []

        // ── Agent: every ask kind the composer can be handed ──────────────
        // Pure composers over the corpus: an empty one is a real gap.
        let pureKinds = ["today", "away", "wallet", "walletdefi", "walletuniswap", "walletgas",
                         "walletsafe", "watchlist", "overdue", "upcoming", "throwback",
                         "moneyflow", "spend", "showtag:Release", "showtag:Alert"]
        for kind in pureKinds {
            out.append(Surface(name: "ask.\(kind)", gate: .required) {
                await askVerdict(kind, things: surfaced, context: context)
            })
        }
        // `noticed` reads the home-insight store, which the on-device model
        // fills — ranked, and skipped where there is no model to fill it.
        out.append(Surface(name: "ask.noticed", gate: .ranked) {
            guard OnDeviceModel.isAvailable else { return .skipped("no on-device model") }
            return await askVerdict("noticed", things: surfaced, context: context)
        })
        // The category ask takes a BRIEF SCOPE (Money / Work / Life), not a
        // catalog category — derived from the catalog through the same map the
        // composer uses, so the set can never be a hand copy.
        let scopes = Set(BridgeCatalog.categories.map { BriefScope.scope(forCatalogCategory: $0.name) })
        for scope in scopes.sorted() {
            out.append(Surface(name: "ask.category.\(scope)", gate: .required) {
                let v = await askVerdict("category:\(scope)", things: surfaced, context: context)
                if case .ok(let d) = v, d.contains("unconnected") { return .empty(d) }
                return v
            })
        }

        // ── Search: the retriever over the demo's own words ───────────────
        for q in ["what did I save about work", "ETH", "release", "dispute", "screenshot"] {
            out.append(Surface(name: "search.\(q.replacingOccurrences(of: " ", with: "_"))",
                               gate: .required) {
                guard let r = KeptAskComposers.search(q, things: surfaced) else {
                    return .empty("no hits")
                }
                return .ok("\(r.doc.count) lines · \(r.digest)")
            })
        }

        // ── Related / links / facts / digests ─────────────────────────────
        // `related.neighbours` retired with the shelf it censused (prd §632).
        out.append(Surface(name: "related.keptBefore", gate: .required) {
            let hits = surfaced.prefix(120).filter { RelatedThings.keptBefore($0, in: all) != nil }.count
            return hits > 0 ? .ok("\(hits) rows have an earlier copy")
                            : .empty("no demo row has an earlier copy — the 'kept before' line never draws")
        })
        out.append(Surface(name: "links.ties", gate: .required) {
            // A tie needs another row MENTIONING the link's URL, so pre-filter
            // in memory to the links some other row mentions and ask `ties`
            // only about those — `ties` fetches per call and the corpus holds
            // ~200 link rows.
            var mentioned: [String: Int] = [:]
            for t in all {
                for field in [t.content, t.postText ?? "", t.enrichedText ?? ""] {
                    for link in ThingLinks.canonicalLinks(in: field) { mentioned[link, default: 0] += 1 }
                }
            }
            let candidates = surfaced.filter { $0.kind == .link }.filter {
                guard let link = ThingLinks.canonicalLink($0.content) else { return false }
                return (mentioned[link] ?? 0) >= 2
            }
            guard !candidates.isEmpty else { return .empty("no link's URL is mentioned by another row") }
            let tied = candidates.filter { !ThingLinksSource.ties(for: $0, context: context).isEmpty }.count
            return tied > 0 ? .ok("\(tied)/\(candidates.count) mentioned links have ties")
                            : .empty("\(candidates.count) links are mentioned elsewhere but ties() finds nothing")
        })
        out.append(Surface(name: "facts.dates", gate: .required) {
            let shots = surfaced.filter { $0.kind == .screenshot && !$0.content.isEmpty }
            let dated = shots.filter { !ScreenshotFacts.dates(in: $0.content).isEmpty }.count
            return dated > 0 ? .ok("\(dated)/\(shots.count) screenshots carry a date")
                             : .empty("no screenshot's text yields a date")
        })
        out.append(Surface(name: "facts.rows", gate: .ranked) {
            guard OnDeviceModel.isAvailable else { return .skipped("no on-device model") }
            var n = 0
            for t in surfaced.filter({ $0.kind == .screenshot }).prefix(6) {
                n += await ScreenshotFacts.facts(for: t).count
            }
            return n > 0 ? .ok("\(n) facts over 6 screenshots") : .empty("no facts")
        })
        out.append(Surface(name: "digest.threads", gate: .required) {
            let threads = surfaced.filter { $0.kind == .chat && ThreadDigest.wants($0) || ($0.kind == .chat && $0.enrichedText != nil) }
            let seeded = threads.filter { $0.enrichedText != nil }.count
            return seeded > 0 ? .ok("\(seeded) threads carry a digest")
                              : .empty("no chat thread carries a digest")
        })

        // ── Widgets / notify ──────────────────────────────────────────────
        // The widgets are COMPOSED here and never published: nothing the demo
        // makes reaches a Home Screen (§217 doctrine, `WidgetPublish.publishAll`
        // returns under the demo). What is judged is what each tile WOULD draw.
        out.append(Surface(name: "widget.lede", gate: .required) {
            .skipped("the Today lede never publishes under the demo (§217 doctrine)")
        })
        out.append(Surface(name: "widget.asks", gate: .required) {
            let kinds = KeptAskStore.shared.order
            return kinds.isEmpty ? .empty("no kept ask for the asks tile") : .ok(kinds.joined(separator: ","))
        })
        out.append(Surface(name: "widget.dayLead", gate: .required) {
            WidgetPublish.dayLead(things: surfaced).map { .ok("\($0.kind.rawValue) pictures=\($0.pictures)") }
                ?? .empty("no day lead")
        })
        out.append(Surface(name: "widget.flow", gate: .required) {
            WidgetPublish.flow(things: surfaced) != nil ? .ok("composed") : .empty("no flow band")
        })
        out.append(Surface(name: "widget.deadlines", gate: .required) {
            let d = WidgetPublish.deadlines(context: context) ?? []
            return d.isEmpty ? .empty("no deadlines") : .ok("\(d.count) deadlines")
        })
        out.append(Surface(name: "widget.safeCall", gate: .required) {
            WidgetPublish.safeCall(things: surfaced) != nil ? .ok("composed") : .empty("no Safe call")
        })
        out.append(Surface(name: "notify.plans", gate: .required) {
            let things = WalletBackgroundRefresh.sweepCorpus(context) ?? []
            let plans = NotifySweep.plans(things: things).plans
            return plans.isEmpty ? .empty("nothing would notify") : .ok("\(plans.count) planned")
        })
        out.append(Surface(name: "notify.devnet", gate: .ranked) {
            let plans = DevnetNotify.plans()
            return plans.isEmpty ? .empty("no devnet plan") : .ok("\(plans.count) planned")
        })

        // ── Rooms: every source the demo furnishes, through the same reader ─
        let sources = Array(Set(all.map(\.source))).filter { Corpus.earnsRoom($0) }.sorted()
        for source in sources {
            out.append(Surface(name: "room.\(source)", gate: .required) {
                if let lead = ProbeHooks.roomInsightReport(source: source, context: context) {
                    return .ok("leads with \(lead)")
                }
                guard FeedScreen.rendersPlain(source) else {
                    return .skipped("bespoke shape, no insight — judged by its own surface")
                }
                let rows = all.filter { $0.source == source }
                let tagged = rows.filter { !$0.tags.isEmpty }.count
                let authors = Set(rows.compactMap(\.authorHandle)).count
                let images = rows.filter { $0.previewImageURL != nil || !$0.imageURLs.isEmpty }.count
                return .empty("rows only · rows=\(rows.count) tagged=\(tagged) authors=\(authors) images=\(images)")
            })
        }
        // Shape-based heads the insight reader does not reach.
        for source in AgentRoomSource.sources.sorted() where sources.contains(source) {
            out.append(Surface(name: "agentRoom.\(source)", gate: .required) {
                let rows = all.filter { $0.source == source }
                return AgentRoomSource.compose(source: source, things: rows) != nil
                    ? .ok("\(rows.count) rows") : .empty("compose returned nil over \(rows.count) rows")
            })
        }
        for source in JournalRoomSource.sources.sorted() where sources.contains(source) {
            out.append(Surface(name: "journalRoom.\(source)", gate: .required) {
                let rows = all.filter { $0.source == source }
                return JournalRoomSource.compose(things: rows) != nil
                    ? .ok("\(rows.count) rows") : .empty("compose returned nil over \(rows.count) rows")
            })
        }
        out.append(Surface(name: "awsRoom", gate: .required) {
            AWSRoomSource.compose(things: all.filter { $0.source == "AWS" }) != nil
                ? .ok("composed") : .empty("compose returned nil")
        })
        out.append(Surface(name: "altanaRoom", gate: .required) {
            let lines = AltanaRoom.probeLines()
            let readings = lines.first.flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
            return readings > 0 ? .ok("\(readings) readings") : .empty(lines.first ?? "no lines")
        })
        out.append(Surface(name: "framesRoom", gate: .required) {
            FramesRoomSource.compose() != nil ? .ok("composed") : .empty("compose returned nil")
        })
        out.append(Surface(name: "hegotaRoom", gate: .required) {
            HegotaRoomSource.compose() != nil ? .ok("composed") : .empty("compose returned nil")
        })
        out.append(Surface(name: "privacyDevnetRoom", gate: .required) {
            let head = PrivacyDevnetRoomSource.compose()
            return head.watching > 0 ? .ok("watching=\(head.watching)") : .empty("watching=0")
        })
        out.append(Surface(name: "walletbeat.cards", gate: .required) {
            let n = WalletbeatState.cards().count
            return n > 0 ? .ok("\(n) cards") : .empty("no wallet cards read")
        })

        // ── Wallet: the cards under the crown ─────────────────────────────
        out.append(Surface(name: "wallet.portfolio", gate: .required) {
            guard let read = await WalletIngest.portfolioRead(scopeTo: nil) else {
                return .empty("nothing read")
            }
            let p = read.portfolio
            return p.tokenCount > 0 && p.walletCount > 1
                ? .ok("tokens=\(p.tokenCount) wallets=\(p.walletCount) total=\(TokenStats.compact(p.totalUSD))")
                : .empty("tokens=\(p.tokenCount) wallets=\(p.walletCount) — not a combined map")
        })
        out.append(Surface(name: "wallet.history", gate: .required) {
            guard let first = WalletStore.shared.addresses.first else { return .empty("no watched wallet") }
            let n = WalletStore.shared.valueSamples(forAddress: first.address).count
            return n >= 2 ? .ok("\(n) samples") : .empty("\(n) samples — the curve cannot draw")
        })
        let live = LiveOnce(context: context)
        out.append(Surface(name: "wallet.composition", gate: .required) {
            let s = await live.state()
            let c = WalletComposition.from(aave: s.positions, morpho: s.morpho, uniswap: s.uniswap,
                                           hyperliquid: s.hyperliquid, aerodrome: s.aerodrome,
                                           etherfiCash: s.etherfiCash, etherfiUnstake: s.etherfiUnstake)
            return c.isEmpty ? .empty("no protocol composition") : .ok(c.probeLines.first ?? "composed")
        })
        out.append(Surface(name: "wallet.exposure", gate: .required) {
            let e = await live.state().exposure
            return e.all.isEmpty ? .empty("no approvals") : .ok("\(e.all.count) spenders")
        })
        out.append(Surface(name: "wallet.riskStrip", gate: .required) {
            let s = await live.state()
            let n = WalletRiskScaleSource.entries(aave: s.positions, morpho: s.morpho,
                                                  hyperliquid: s.hyperliquid).count
            return n > 0 ? .ok("\(n) entries") : .empty("no risk entries")
        })
        out.append(Surface(name: "wallet.worthALook", gate: .required) {
            let s = await live.state()
            let n = s.warnings.count + s.flagged.count + s.activeApprovals.count
            return n > 0 ? .ok("warnings=\(s.warnings.count) flagged=\(s.flagged.count) approvals=\(s.activeApprovals.count)")
                         : .empty("nothing worth a look")
        })
        out.append(Surface(name: "wallet.flow", gate: .required) {
            let first = WalletFlowSource.probeLines(context: context, days: nil).first ?? ""
            let legs = first.split(separator: " ").first { $0.hasPrefix("legs=") }
                .flatMap { Int($0.dropFirst(5)) } ?? 0
            return legs > 0 ? .ok(first) : .empty(first)
        })
        out.append(Surface(name: "wallet.connections", gate: .required) {
            let lines = AddressConnections.probeLines(context: context)
            return lines.contains { $0.hasPrefix("DECLINED") }
                ? .empty(lines.joined(separator: " · ")) : .ok(lines.first ?? "composed")
        })
        out.append(Surface(name: "wallet.nftShelf", gate: .required) {
            guard let first = WalletStore.shared.addresses.first else { return .empty("no watched wallet") }
            let pieces = await WalletNFTShelf.pieces(for: first.address, book: WalletNFTStore.shared.book)
            return pieces.isEmpty ? .empty("no pieces") : .ok("\(pieces.count) pieces")
        })
        out.append(Surface(name: "wallet.actingParties", gate: .required) {
            let lines = await WalletActingParties.probeLines()
            return lines.isEmpty ? .empty("no lines") : .ok(lines.first ?? "")
        })

        // ── Social: rosters and the inbound half ──────────────────────────
        for source in ["Farcaster", "Bluesky"] where sources.contains(source) {
            out.append(Surface(name: "social.\(source)", gate: .required) {
                let rows = all.filter { $0.source == source }
                let text = rows.filter { !($0.postText ?? "").isEmpty }.count
                let images = rows.filter { !$0.imageURLs.isEmpty }.count
                let quotes = rows.filter { $0.quote != nil }.count
                let replies = rows.filter { $0.parent != nil }.count
                let channels = rows.filter { $0.channelName != nil }.count
                let detail = "rows=\(rows.count) text=\(text) images=\(images) quotes=\(quotes) replies=\(replies) channels=\(channels)"
                return (text > 0 && images > 0 && quotes > 0 && replies > 0) ? .ok(detail) : .empty(detail)
            })
        }
        out.append(Surface(name: "social.inbound", gate: .required) {
            let fc = FarcasterStore.shared.accounts.filter(\.mine).map(\.username)
            let bsky = BlueskyStore.shared.accounts.filter(\.mine).map(\.handle)
            guard !fc.isEmpty || !bsky.isEmpty else { return .empty("no account marked mine") }
            var own = 0
            for h in fc {
                own += SocialInbound.ownRecentPosts(IngestSupport.thingsByRef(context, source: "Farcaster"),
                                                    handle: h, refPrefix: "fc:").count
            }
            for h in bsky {
                own += SocialInbound.ownRecentPosts(IngestSupport.thingsByRef(context, source: "Bluesky"),
                                                    handle: h, refPrefix: "bsky:").count
            }
            return own > 0 ? .ok("mine fc=\(fc.count) bsky=\(bsky.count) ownPosts=\(own)")
                           : .empty("mine fc=\(fc.count) bsky=\(bsky.count) but no own posts eligible")
        })
        out.append(Surface(name: "social.likers", gate: .required) {
            let n = SocialLikers.shared.rolls.count
            return n > 0 ? .ok("\(n) posts with a roll") : .empty("no post has a likers roll")
        })

        // ── Sheets: what the newest row of each kind OFFERS ───────────────
        for kind in ThingKind.allCases {
            let sample = Array(surfaced.filter { $0.kind == kind }.prefix(6))
            guard !sample.isEmpty else { continue }
            out.append(Surface(name: "verbs.\(kind.rawValue)", gate: .required) {
                var offered: [String] = []
                var mute: [String] = []
                for t in sample {
                    let verbs = VerbDerivation.verbs(for: t)
                    if verbs.isEmpty { mute.append(t.title) }
                    else { offered += verbs.map(\.shortLabel) }
                }
                let detail = "\(Set(offered).sorted().joined(separator: ",")) · \(mute.count)/\(sample.count) offer none"
                return offered.isEmpty ? .empty("none of the newest \(sample.count) offers a verb") : .ok(detail)
            })
        }
        out.append(Surface(name: "verbs.deadLinks", gate: .required) {
            var dead: [String] = []
            for t in surfaced.prefix(200) {
                for v in VerbDerivation.verbs(for: t) {
                    // A scheme-only URL (`calshow://`) is a hand-off, not a
                    // dead link; only a web URL with no host is dead.
                    if case .openURL(let url) = v.action,
                       ["http", "https"].contains(url.scheme ?? ""), (url.host ?? "").isEmpty {
                        dead.append("\(t.source): \(url.absoluteString)")
                    }
                }
            }
            return dead.isEmpty ? .ok("no hostless Open verb in the newest 200")
                : .empty("\(dead.count) hostless — " + dead.prefix(4).joined(separator: " · "))
        })

        return out
    }

    // MARK: - Helpers

    private static func askVerdict(_ kind: String, things: [Thing], context: ModelContext) async -> Verdict {
        guard let r = await KeptAskComposers.compose(kind, things: things, context: context) else {
            return .empty("compose returned nil")
        }
        return r.doc.isEmpty ? .empty("empty doc · \(r.digest)") : .ok("\(r.doc.count) lines · \(r.digest)")
    }

    /// `WalletWatch.liveState` is read ONCE for the five cards that share it.
    private final class LiveOnce {
        private let context: ModelContext
        private var cached: WalletLiveState?
        init(context: ModelContext) { self.context = context }
        func state() async -> WalletLiveState {
            if let cached { return cached }
            let s = await WalletWatch.liveState(context: context)
            cached = s
            return s
        }
    }
}
#endif
