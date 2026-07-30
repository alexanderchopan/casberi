import Foundation
import SwiftData

/// One foreground refresh for every connected polling bridge (RSS, Bluesky,
/// Farcaster, and each connected token bridge). RootShell fires it on
/// scenePhase → .active; screens can reuse it (e.g. pull-to-refresh) instead of
/// repeating the guard-then-Task shape per bridge. Each bridge refreshes
/// independently, fire-and-forget, on the main actor.
@MainActor
enum BridgeRefresh {
    /// Spreads a foreground refresh's ~25 independent bridge Tasks over
    /// roughly a second instead of firing every network request in the same
    /// instant (2026-07-15 — no cap or stagger existed before this). Each
    /// bridge still refreshes fully independently — this only delays ITS OWN
    /// first `await`, never queues one bridge behind another — so a slow
    /// bridge still can't block a fast one; it just spreads the peak of
    /// simultaneous new socket/TLS handshakes across the refresh instead of
    /// bursting them all at once.
    private static func stagger(_ slot: Int) async {
        guard slot > 0 else { return }
        try? await Task.sleep(for: .milliseconds(slot * 40))
    }

    /// When the whole sweep last ran — a rapid background→active bounce
    /// (a notification glance, Face ID, control center) used to re-fire all
    /// ~25 bridges every time (2026-07-21: no cooldown existed at all). The
    /// per-bridge `running` guards only stop a bridge overlapping ITSELF;
    /// they never stopped back-to-back sweeps. Mirrors the min-interval gate
    /// `GitHubGraphStore.refreshIfStale`/`KalshiWatch` already use per-store.
    private static var lastSweep: Date?
    private static let minSweepInterval: TimeInterval = 45

    /// Per-heal throttle (2026-07-24 perf): the pure DELETE-SYNC passes —
    /// removing rows whose upstream item is gone (Photos/Calendar) — are
    /// cleanup, not fresh content, so they needn't run on every foreground the
    /// way the "land new items" refreshes do. Each runs at most once per
    /// `healInterval`, keyed in UserDefaults so the throttle survives relaunch.
    /// A deleted item lingering a few extra minutes is invisible; a full
    /// source-wide fetch+diff on every foreground is not free. (Bluesky/
    /// Farcaster/Mail heals already carry their own 1h network throttle.)
    private static let healInterval: TimeInterval = 600
    static func dueForHeal(_ key: String) -> Bool {
        let k = "heal.due.\(key)"
        let now = Date.now.timeIntervalSince1970
        guard now - UserDefaults.standard.double(forKey: k) > healInterval else { return false }
        UserDefaults.standard.set(now, forKey: k)
        return true
    }

    /// `force: true` (pull-to-refresh) always runs live, matching the
    /// gesture's own contract of bypassing every other TTL/cache in the
    /// refresh path — only the automatic scenePhase-driven sweep is gated.
    static func refreshAllConnected(context: ModelContext, store: BridgeStore, force: Bool = false) {
        if !force, let last = lastSweep, Date.now.timeIntervalSince(last) < minSweepInterval { return }
        lastSweep = .now
        var nextSlot = 0
        func slot() -> Int { defer { nextSlot += 1 }; return nextSlot }
        // The native-framework bridges (Photos/Calendar/Reminders/Health/
        // Music) only ever ingested at the moment of connect — nothing
        // re-scanned them, so a screenshot taken an hour later never
        // landed (report 2026-07-09). Their ingest calls already dedupe on
        // sourceRef exactly like every polling bridge ("reconnects and
        // refreshes are cheap" — HealthIngest's own doc comment); they were
        // just never wired into the foreground refresh. Calendar/Reminders
        // re-present the system dialog on every foreground if you call the
        // request API again unconditionally (field report 2026-07-13) — the
        // refresh path below must go through a bare re-scan that checks
        // authorizationStatus first, same fix already applied to
        // AppleMusicIngest/ContactsIngest — gated on BridgeStore so a
        // never-connected bridge is never silently asked.
        func connected(_ id: String) -> Bool {
            store.bridges.contains { $0.id == id && $0.status == .connected }
        }
        // Photos gates on the REAL authorization, not the stored bridge status
        // (2026-07-24 fix): the `pho` status could drift off exactly
        // `.connected` while full Photos access was granted the whole time, and
        // the old `connected("pho")` gate then silently stopped every
        // foreground/pull from ingesting new screenshots — connect landed the
        // first batch and nothing refreshed after (user report). Run whenever
        // access is live and the user hasn't explicitly PAUSED the bridge.
        if let photoBridge = store.bridges.first(where: { $0.id == "pho" }),
           photoBridge.status != .paused {
            if ScreenshotIngest.hasAccess {
                // LIMITED access is the silent version of this bridge's own
                // bug report (2026-07-25): every fetch still succeeds, so
                // nothing downstream can tell "your library has 4 screenshots"
                // from "iOS only lets us see the 4 you picked" — new
                // screenshots never land and older ones are missing wholesale,
                // which reads exactly like a broken sync. Say it instead
                // (honesty rule); Photos' detail screen carries the remedy.
                let limitedLine = String(localized: "Limited access — only the photos you picked can land")
                if ScreenshotIngest.accessIsLimited {
                    if photoBridge.status != .attention || photoBridge.statusLine != limitedLine {
                        store.markAttention("pho", statusLine: limitedLine)
                    }
                } else if photoBridge.status != .connected || photoBridge.statusLine == limitedLine {
                    // Self-heal a drifted status so the Apps catalog reads true.
                    store.reconnect("pho", proof: "Synced just now")
                }
                // Staggered off the synchronous call path (2026-07-24 perf):
                // this runs TWO PHAsset library scans and must stay on the main
                // actor for its SwiftData inserts, so calling it inline stalled
                // the main thread mid-animation — the chip-flip and refresh
                // confetti stuttered. A Task defers it a beat past the frame the
                // animation starts on; new screenshots still land this sweep.
                let ps = slot(); Task { @MainActor in
                    await BridgeRefresh.stagger(ps)
                    _ = ScreenshotIngest.ingest(context: context)
                    // …and one batch of the walk BACKWARDS through the library,
                    // so screenshots older than the head fetch's window finally
                    // arrive. Costs nothing once the walk has reached the end.
                    ScreenshotIngest.backfill(context: context)
                }
                // Thumbnails for new rows, removal of confirmed-gone hollow
                // ones. Throttled — new screenshots still land via `ingest` —
                // but a deliberate pull runs it live, same contract as Mail's
                // heal below: `force` bypasses every other TTL in this path.
                if force || BridgeRefresh.dueForHeal("photos") {
                    let s = slot(); Task { @MainActor in
                        await BridgeRefresh.stagger(s)
                        _ = await ScreenshotIngest.heal(context: context)
                        // Then lift the treemap terms off whatever OCR text the
                        // heal (and prior passes) have written — no PHAsset walk,
                        // just `content`, so it's cheap and self-terminating once
                        // the library is fully topic'd (2026-07-30).
                        _ = await ScreenshotTopics.healTopics(context: context)
                    }
                }
            } else if photoBridge.status != .attention {
                // Access revoked since connect — say so instead of silently
                // ingesting nothing forever (honesty rule).
                store.markAttention("pho", statusLine: "Photos access is off — reconnect to resume")
            }
        }
        if connected("cal") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScheduleIngest.refreshCalendar(context: context)
            }
            // Delete-sync: an event deleted outright (not just aged out of
            // the ingest window) — local EventKit check. Throttled: refresh
            // above still lands new/changed events every foreground.
            if BridgeRefresh.dueForHeal("calendar") {
                let s2 = slot(); Task { @MainActor in
                    await BridgeRefresh.stagger(s2)
                    _ = ScheduleIngest.healCalendar(context: context)
                }
            }
        }
        if connected("rem") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScheduleIngest.refreshReminders(context: context)
            }
        }
        let healthOn = connected("hlt"), stravaOn = connected("strava")
        if healthOn || stravaOn {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await HealthIngest.connectAndIngest(context: context,
                                                        healthOn: healthOn, stravaOn: stravaOn)
            }
        }
        if connected("music") {
            // The bare re-scan — refresh must never re-present the
            // permission dialog (2026-07-10).
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await AppleMusicIngest.ingest(context: context)
            }
        }
        if !RSSStore.shared.feeds.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await RSSIngest.refresh(context: context)
            }
        }
        if BlueskyStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await BlueskyIngest.refresh(context: context)
                // A watched account posting again after a real quiet
                // stretch is its own moment (delight 2026-07-21) — a
                // read-only pass over what just landed, touching nothing
                // in the ingest above.
                SocialMoments.checkBlueskyReturns(context: context)
            }
            // Delete-sync: a post removed by its author or moderation.
            // Own network round trip and its own hourly throttle.
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await BlueskyIngest.heal(context: context)
            }
        }
        if FarcasterStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await FarcasterIngest.refresh(context: context)
                SocialMoments.checkFarcasterReturns(context: context)
            }
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await FarcasterIngest.heal(context: context)
            }
        }
        if NostrStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await NostrIngest.refresh(context: context)
                SocialMoments.checkNostrReturns(context: context)
            }
            // Delete-sync: own network round trip and its own hourly
            // throttle, same shape as Farcaster/Bluesky's heals above.
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await NostrIngest.heal(context: context)
            }
        }
        if !PinterestStore.shared.username.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await PinterestIngest.refresh(context: context)
            }
        }
        // The feed-follow bridges (Substack/Reddit/YouTube/Podcasts) — each
        // polls only when it's watching something.
        for kind in FeedFollowKind.allCases where !kind.store.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await FeedFollowIngest.refresh(kind, context: context)
                // Read-only passes over what just landed, touching nothing in
                // the ingest above — same shape as the social bridges' own
                // return-check (delight pass 2026-07-28). YouTube's view
                // doubling and retitle checks already ran inside the ingest
                // itself (they need the per-item feed data, not just the
                // landed corpus), so only the corpus-wide checks live here.
                // Podcasts joined YouTube/Reddit here 2026-07-28 (a show off
                // hiatus is the exact same shape).
                if kind == .youtube || kind == .reddit || kind == .podcasts {
                    FeedFollowMoments.checkReturns(kind, context: context)
                }
                if kind == .reddit {
                    FeedFollowMoments.checkRedditLinkCrossings(context: context)
                    FeedFollowMoments.checkRedditCrossPosters(context: context)
                }
                // A new upload/episode naming an artist you've liked/played
                // elsewhere in Media — a pure local join, so it's harmless
                // to re-run once per feed-follow kind (self-throttled by
                // the freshWindow filter on the YouTube/Podcasts side, same
                // as every other crossing here).
                if kind == .youtube || kind == .podcasts {
                    MediaMoments.checkArtistCrossing(context: context)
                }
            }
        }
        if connected("contacts") {
            // The bare re-scan — refresh must never re-present the permission
            // dialog; it runs only when access is already granted.
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ContactsIngest.refresh(context: context)
            }
        }
        if connected("homekit") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await HomeKitIngest.refresh(context: context)
            }
        }
        for bridge in TokenBridge.allCases where bridge.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TokenIngest.refresh(bridge, context: context)
            }
        }
        // Peer & Privacy Pools ride the watched wallets automatically (prd
        // §207) — reflect that in the catalog every foreground: connected
        // while a wallet is watched, dropped when the last one goes.
        store.reconcileWalletSeats()
        if !WalletStore.shared.addresses.isEmpty {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await WalletIngest.refresh(context: context)
            }
            // The wallet's delight + faces pass (2026-07-15): fetch the full
            // holdings (records value samples, checks the combined/single new
            // high) so a moment fires from a plain foreground on Home, not only
            // from the Wallet screen. Holdings sample-throttle at 4h. The moments
            // enqueue on SourceMoments, which MainSurface drains into the berry
            // rain + toast. Faces resolve here too, so a wallet wears its ENS
            // avatar before you ever open its screen.
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await WalletIngest.topHoldingsByWallet()
                await WalletStore.shared.loadAvatars()
            }
        }
        // Not an ingest — the watchlist's 24h pulse for the feed-row
        // sparkline. Exits instantly when no tokens are watched.
        let s = slot(); Task { @MainActor in
            await BridgeRefresh.stagger(s)
            await TokenPulse.shared.refresh(context: context)
        }
        // Same shape for watched prediction markets (Kalshi/Polymarket) —
        // without this a watched market goes dead the moment its own screen
        // closes, since nothing else ever refetches its odds. It is also
        // what stamps a settled market and fires its resolution moment.
        let sp = slot(); Task { @MainActor in
            await BridgeRefresh.stagger(sp)
            await PredictionPulse.shared.refresh(context: context)
        }
        for provider in MailProvider.allCases where provider.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await MailIngest.refresh(provider, context: context)
            }
            // Delete-sync: reconciles against what the server still has.
            // Own network round trip and its own hourly throttle, so it
            // runs as an independent staggered task rather than tacked onto
            // refresh above. `force` must ride along here too (2026-07-24
            // fix) — this call used to always default to `force: false`, so
            // heal's own hourly throttle silently ate a person's deliberate
            // pull-to-refresh: a mail deleted in Mail.app kept reappearing
            // in Casberi for up to an hour after a pull that looked, from
            // the gesture, like it should have caught it immediately —
            // exactly the contract `force` exists to guarantee (see the
            // comment on `refreshAllConnected` above).
            let s2 = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s2)
                _ = await MailIngest.heal(provider, context: context, force: force)
            }
        }
        if SteamBridge.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await SteamIngest.refresh(context: context)
                // A followed streamer playing a game already in this
                // library — a pure local join (delight pass 2026-07-28).
                // Runs after Steam too, not just Twitch, since either
                // bridge's refresh can be the one that makes the join true.
                MediaMoments.checkTwitchSteamCrossing(context: context)
            }
        }
        if ObsidianStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ObsidianIngest.refresh(context: context)
            }
        }
        if FilesStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await FilesIngest.refresh(context: context)
            }
            // Thumbnails + OCR for the image files a sync already landed —
            // same throttle contract as Photos' heal above.
            if force || BridgeRefresh.dueForHeal("files") {
                let s2 = slot(); Task { @MainActor in
                    await BridgeRefresh.stagger(s2)
                    _ = await FilesIngest.heal(context: context)
                }
            }
        }
        if DropboxStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await DropboxIngest.refresh(context: context)
            }
        }
        if SlackAuth.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await SlackIngest.refresh(context: context)
                // Read-only passes over what just landed, touching nothing in
                // the ingest above — same shape as the other networks' own
                // return-check, plus the corpus join only Slack can offer
                // (a mention sharing a link you already saved elsewhere).
                SocialMoments.checkSlackReturns(context: context)
                SocialMoments.checkSlackCrossings(context: context)
            }
        }
        if TwitchAuth.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TwitchIngest.refresh(context: context)
                // Read-only passes over what just landed, touching nothing
                // in the ingest above — same shape as the social bridges'
                // own return-check (delight pass 2026-07-28).
                MediaMoments.checkTwitchReturns(context: context)
                MediaMoments.checkTwitchSteamCrossing(context: context)
            }
        }
        if OpenSeaStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await OpenSeaIngest.refresh(context: context)
            }
        }
        if TrendingStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TrendingIngest.refresh(context: context)
            }
        }
        // Stocktwits — the watch lives in the corpus (the thing IS the
        // watch); the seat gates the foreground poll so a person who never
        // connected it doesn't pay the watched-tickers fetch every
        // foreground, and a disconnected seat stays disconnected.
        if connected("stocktwits") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await StocktwitsIngest.refresh(context: context)
            }
        }
        if ShopifyStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ShopifyIngest.refresh(context: context)
            }
        }
        if DealsStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await DealsIngest.refresh(context: context)
            }
        }
    }
}
