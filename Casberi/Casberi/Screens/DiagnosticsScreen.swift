import SwiftUI
import SwiftData
import Photos
import MusicKit

/// Diagnostics (2026-07-09) — runs the exact device paths that have been
/// failing in the field (the Home cover's photo load, the pinned token's
/// chart fetch) and prints every step's real result, so a TestFlight report
/// can be a screenshot of facts instead of a guess. Dev-facing words are
/// fine here: this screen exists for debugging sessions, not daily use.
struct DiagnosticsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// The LIVE room scope (2026-08-31). See the room-pipeline block in
    /// `run()`: the one fact no fetch on this screen can supply is which room
    /// the person is actually standing in, and it is the first thing that has
    /// to be ruled out when rows show in All and not in their own room.
    /// OPTIONAL on purpose: this screen is presented as a SHEET, and a
    /// non-optional `@Environment(FeedFilter.self)` traps at runtime if the
    /// sheet's environment does not carry one. A diagnostics screen that can
    /// crash the app is worse than one that reports a missing reading.
    @Environment(FeedFilter.self) private var filter: FeedFilter?
    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .dsText(.mono13)
                        .foregroundStyle(line.hasPrefix("FAIL") ? DS.attention
                                         : line.hasPrefix("OK") ? DS.confirm : DS.textPrimary)
                        .dsListCardRow()
                        .listRowSeparator(.hidden)
                        .textSelection(.enabled)
                }
                if running {
                    // The instrument beats while it listens. A generic spinner
                    // says "something is happening"; the stethoscope from the
                    // Settings row that opened this screen says WHAT — and it
                    // stops the instant the last real line lands, so the beat
                    // is never decoration over a finished run.
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: "stethoscope")
                            .accessibilityHidden(true)
                            .dsGlyph(15)
                            .foregroundStyle(DS.textSecondary)
                            .symbolEffect(.pulse, options: .repeating, isActive: running)
                        Text("Running…").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    .dsListCardRow()
                }
            } footer: {
                Text("Screenshot this screen and send it back — every line is a real result from this device.")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        // `.inline` + the shared dismiss (prd §560, 2026-09-01). This screen is
        // only ever a SHEET, and `dsScreenTitle` is the full-screen title — so
        // it wore a large title inside a presentation, and its Done sat
        // trailing while four sibling sheets put theirs leading.
        .navigationTitle(Text("Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .dsSheetDismiss { dismiss() }
        .task { await run() }
    }

    private func log(_ s: String) { lines.append(s) }

    @MainActor
    private func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        lines = []

        // Which build is actually installed — rules out stale-build reports.
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        log("Build \(v) (\(b))")

        // Corpus basics.
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        log("Things: \(all.count)")
        if let newest = all.first {
            log("Newest: \(newest.kind.typeTag) · \(newest.source) · \(short(newest.capturedAt))")
        }

        // Every room's empty-state gate ultimately asks `Corpus.hasSurfaced`
        // (2026-08-30 field report: things exist per the raw fetch above, but
        // every room — All, Wallet's own row list, a freshly-poured demo —
        // renders as empty on one specific device, surviving a full delete +
        // reinstall). This runs `hasSurfaced`/`surfaced` on the EXACT SAME
        // array `all` above, already proven non-empty, to separate two very
        // different bugs that look identical from the feed: the FILTER
        // logic disagreeing with a raw fetch (a code bug, reachable here),
        // vs. the live `@Query` a room actually renders from disagreeing
        // with a fresh fetch on the same store (a binding/store bug, NOT
        // reachable from this screen — this call cannot rule that out, only
        // rule the filter itself in or out).
        log("hasSurfaced(all): \(Corpus.hasSurfaced(all) ? "YES — filter is not the cause" : "NO — filter itself excludes every thing here")")
        let surfacedCount = Corpus.surfaced(all).count
        log("surfaced(all).count: \(surfacedCount) of \(all.count)")

        // Round 2 (2026-08-30): the All-room and per-source-room safety
        // nets both shipped, were both exercised (the room was actually
        // visited), and the Vercel room still rendered empty. Both fixes
        // lean on a `source ==` PREDICATE — the same shape every
        // per-source `@Query` and `TokenSetupScreen`'s empty-read check
        // already use. This isolates the one thing neither fix could rule
        // out: whether that PREDICATE itself answers correctly on this
        // device, independent of `@Query` entirely. `bySource` is plain
        // Swift filtering of the array already proven correct above;
        // `predicated` is SwiftData evaluating the identical predicate
        // through `fetchCount`. Agreement here doesn't prove `@Query`'s
        // live observation is healthy — it never touches `@Query` — but
        // disagreement would mean the predicate, not the live-observation
        // bug, is where this actually lives.
        var counts: [String: Int] = [:]
        for t in all { counts[t.source, default: 0] += 1 }
        for (src, bySource) in counts.sorted(by: { $0.key < $1.key }) {
            let predicated = (try? modelContext.fetchCount(
                FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == src }))) ?? -1
            let mark = predicated == bySource ? "OK" : "MISMATCH"
            log("\(mark) source \"\(src)\": in-memory=\(bySource) predicated-fetchCount=\(predicated)")
        }

        // Round 4 (2026-08-31): THE ROOM PIPELINE, STAGE BY STAGE.
        //
        // The field report is "rows show in All and the source's own room is
        // empty", and rounds 1-3 all answered it by assuming FB14619787 (a
        // stuck `@Query`) and shipping a fallback. Round 3's own tester data
        // then showed the store and the `source ==` predicate BOTH healthy
        // (22 of 22, `predicated-fetchCount` agreeing) — so the premise was
        // wrong and three fixes were aimed at a bug that device does not
        // have. This block exists so the next report is diagnosed instead of
        // guessed at.
        //
        // It matters because the room's filter is strictly MORE PERMISSIVE
        // than the All room's: `liveVisible` gates on
        // `Corpus.showsInAll(thing)` for All and skips it entirely for a
        // source room. So a row visible in All must render in its own room —
        // UNLESS the room is scoped to something other than that source, or
        // the room's own live query never delivered. Those are different
        // bugs with one symptom, and only the first is visible from here.
        //
        // `filter.source` is the single most diagnostic value on this screen
        // and no fetch can supply it: a folded category chip shows the
        // CATEGORY name while `filter.source` holds a real seat, so "I am in
        // the Vercel room" is a claim about a value nobody can see.
        if let filter {
            log("Room scope: filter.source=\"\(filter.source)\" filter.tag=\"\(filter.tag)\"")
            let roomSource = filter.source
            let roomTag = filter.tag
            if roomSource != "All" {
                let scoped = (try? modelContext.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate<Thing> { $0.source == roomSource }))) ?? []
                let surfacedScoped = Corpus.surfaced(scoped)
                let tagged = roomTag == "All"
                    ? surfacedScoped
                    : surfacedScoped.filter { $0.tags.contains(roomTag) }
                log("This room would draw: predicate=\(scoped.count) → surfaced=\(surfacedScoped.count) → afterTag=\(tagged.count)")
                if scoped.isEmpty && !all.isEmpty {
                    log("→ NO ROW CARRIES source==\"\(roomSource)\" — this room is scoped to a source nothing is stamped with")
                } else if tagged.count > 0 {
                    log("→ the room's own data is FINE — \(tagged.count) row(s) should draw. If the room looks empty, the view is at fault, not the store")
                }
            } else {
                log("This room is All — open the source's own room, then re-run this")
            }
        } else {
            log("Room scope: UNREADABLE (no FeedFilter in this sheet's environment)")
        }

        // — The cover path, step by step —
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        log("Photos access: \(authWord(auth))")

        // — Screenshot detection: what does each fetch path actually find on
        // THIS device? Field report 2026-07-24 (build 138, iOS 26): new
        // screenshots existed in Photos but never landed in Casberi. This
        // reports both paths' counts and a dry-run ingest so drift between
        // "album says 20 screenshots" and "mediaSubtypes predicate says 0"
        // is immediately visible instead of hidden inside a silent skip.
        if auth == .authorized || auth == .limited {
            let report = ScreenshotIngest.ingestWithReport(context: modelContext)
            log("Screenshots album: \(report.albumFound) most recent")
            log("Screenshots mediaSubtypes predicate: \(report.predicateFound) most recent")
            log("After merge/dedupe: \(report.merged) unique · \(report.added) newly landed")
            // The backwards walk (2026-07-25) — "older screenshots are
            // missing" is either a walk still in progress or LIMITED access,
            // and those look identical from the feed.
            let landed = all.filter { $0.source == "Photos" && $0.kind == .screenshot }.count
            let backfilled = ScreenshotIngest.backfill(context: modelContext)
            log("Backfill: \(ScreenshotIngest.backfillDone ? "whole library walked" : "still walking") · \(backfilled) landed this pass · \(landed + report.added + backfilled) screenshots in")
            if auth == .limited {
                log("FAIL LIMITED access is why older/new screenshots are missing — only the picked set is readable")
            }
        }

        let images = all.filter { $0.kind == .screenshot && $0.sourceRef != nil }
        let cover = images.first { Calendar.current.isDateInToday($0.capturedAt) }
            ?? images.first { $0.capturedAt > .now.addingTimeInterval(-7 * 86_400) }
        if let cover {
            log("Cover thing: \(short(cover.capturedAt)) ref \(String(cover.sourceRef!.prefix(18)))…")
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [cover.sourceRef!], options: nil)
            if let asset = assets.firstObject {
                log("OK asset found (\(asset.pixelWidth)×\(asset.pixelHeight))")
                await loadImage(asset)
            } else {
                log("FAIL asset NOT found for that ref — the identifier doesn't resolve in this library")
            }
        } else {
            log("No screenshot thing this week — the cover has nothing to show (quiet cover is correct)")
        }

        // — The token chart path — (any watched token; the chart lives on the
        //   token's sheet and in Feed now, and Tokens pins as a watchlist
        //   tile — pinning is per-app, not per-token.)
        let pinnedTokens = all.filter { TokenChart.route(from: $0.content) != nil }
        if pinnedTokens.isEmpty {
            log("No token thing (nothing watched has a resolvable token link)")
        }
        for t in pinnedTokens.prefix(2) {
            let route = TokenChart.route(from: t.content)!
            // `shortAddress`, not a head slice: this line is on a screen, and
            // the app has one truncation rule (2026-08-12). A head slice also
            // hid the half that tells two token contracts apart.
            log("Token: \(t.title) → \(route.chain)/\(WalletStore.shortAddress(route.address))")
            if let chart = await TokenChart.fetch(chain: route.chain, address: route.address) {
                log("OK chart: \(chart.closes.count) points, price \(chart.price)")
            } else {
                log("FAIL chart fetch — neither GeckoTerminal, Alchemy, nor Dexscreener had a price")
            }
        }

        // — The Apple Music artwork path (field report 2026-07-11: music
        // rows still wear the glyph). Gated on authorization having been
        // decided, NOT on stored songs — "connected but every request
        // fails" lands zero songs and is exactly the state that must show
        // up here. The model layer runs the real path (recent-feed art, the
        // catalog fallback, one test fetch); the watchdog keeps a stalled
        // request from holding up the rest of the report (same guard as
        // the cover load above). —
        let songs = all.filter { $0.source == "Apple Music" }
        if !songs.isEmpty || MusicAuthorization.currentStatus != .notDetermined {
            let withArt = songs.filter { $0.previewImageURL != nil }.count
            log("Apple Music: \(songs.count) songs in, \(withArt) with art stored")
            let context = modelContext
            let musicLines: [String] = await withCheckedContinuation { cont in
                var finished = false
                Task { @MainActor in
                    let probe = await AppleMusicIngest.artworkDiagnostic(context: context)
                    guard !finished else { return }
                    finished = true
                    cont.resume(returning: probe)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(25))
                    guard !finished else { return }
                    finished = true
                    cont.resume(returning: ["FAIL music probe timed out after 25s — a request never returned"])
                }
            }
            for line in musicLines { log(line) }
        }

        // — Wallet state —
        let wallet = WalletStore.shared
        log("Wallet: \(wallet.addresses.count) address(es)")
        if !wallet.addresses.isEmpty {
            for line in await WalletIngest.holdingsDiagnostic() { log(line) }
            // The flow band's own verdict (prd §589): the one place on a
            // device that says WHY the Activity slot declined, since
            // `-flowProbe` needs a launch argument nobody has on a phone.
            for line in WalletFlowSource.probeLines(context: modelContext, days: nil) {
                log("Flow: \(line)")
            }
        }
    }

    /// The cover's exact load call, with every callback reported.
    private func loadImage(_ asset: PHAsset) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            var finished = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1200, height: 900),
                contentMode: .aspectFill, options: opts
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? NSError
                Task { @MainActor in
                    if let error {
                        log("FAIL image callback: \(error.domain) \(error.code) — \(error.localizedDescription)")
                    } else if let img {
                        log("\(degraded ? "(degraded) " : "OK ")image \(Int(img.size.width))×\(Int(img.size.height))\(cancelled ? " cancelled" : "")")
                    } else {
                        log("\(degraded ? "(degraded) " : "FAIL ")image nil\(cancelled ? " (cancelled)" : "") — the final image never arrived")
                    }
                    if !degraded, !finished { finished = true; cont.resume() }
                }
            }
            // A network fetch that stalls would otherwise hang this screen.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if !finished {
                    finished = true
                    log("FAIL image timed out after 20s — iCloud download never completed")
                    cont.resume()
                }
            }
        }
    }

    private func authWord(_ s: PHAuthorizationStatus) -> String {
        switch s {
        case .authorized:    "full"
        case .limited:       "LIMITED — only selected photos are readable"
        case .denied:        "DENIED"
        case .restricted:    "restricted"
        case .notDetermined: "never asked"
        @unknown default:    "unknown"
        }
    }

    private func short(_ d: Date) -> String {
        d.formatted(.dateTime.month().day().hour().minute())
    }
}
