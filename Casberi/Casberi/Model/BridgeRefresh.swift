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

    static func refreshAllConnected(context: ModelContext, store: BridgeStore) {
        var nextSlot = 0
        func slot() -> Int { defer { nextSlot += 1 }; return nextSlot }
        // The native-framework bridges (Photos/Calendar/Reminders/Health/
        // Music) only ever ingested at the moment of connect — nothing
        // re-scanned them, so a screenshot taken an hour later never
        // landed (report 2026-07-09). Their ingest calls already dedupe on
        // sourceRef exactly like every polling bridge ("reconnects and
        // refreshes are cheap" — HealthIngest's own doc comment); they were
        // just never wired into the foreground refresh. Re-requesting an
        // already-decided system permission resolves instantly, no repeat
        // prompt — gated on BridgeStore so a never-connected bridge is
        // never silently asked.
        func connected(_ id: String) -> Bool {
            store.bridges.contains { $0.id == id && $0.status == .connected }
        }
        if connected("pho") {
            _ = ScreenshotIngest.ingest(context: context)
            // Thumbnails for new rows, removal of confirmed-gone hollow ones.
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScreenshotIngest.heal(context: context)
            }
        }
        if connected("cal") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScheduleIngest.connectCalendar(context: context)
            }
        }
        if connected("rem") {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ScheduleIngest.connectReminders(context: context)
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
        }
        if FarcasterStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await FarcasterIngest.refresh(context: context)
                SocialMoments.checkFarcasterReturns(context: context)
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
        for provider in MailProvider.allCases where provider.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await MailIngest.refresh(provider, context: context)
            }
        }
        if SteamBridge.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await SteamIngest.refresh(context: context)
            }
        }
        if ObsidianStore.shared.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await ObsidianIngest.refresh(context: context)
            }
        }
        if TwitchAuth.connected {
            let s = slot(); Task { @MainActor in
                await BridgeRefresh.stagger(s)
                _ = await TwitchIngest.refresh(context: context)
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
