import Foundation
import SwiftData

/// One foreground refresh for every connected polling bridge (RSS, Bluesky,
/// Farcaster, and each connected token bridge). RootShell fires it on
/// scenePhase → .active; screens can reuse it (e.g. pull-to-refresh) instead of
/// repeating the guard-then-Task shape per bridge. Each bridge refreshes
/// independently, fire-and-forget, on the main actor.
@MainActor
enum BridgeRefresh {
    static func refreshAllConnected(context: ModelContext, store: BridgeStore) {
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
        }
        if connected("cal") {
            Task { @MainActor in _ = await ScheduleIngest.connectCalendar(context: context) }
        }
        if connected("rem") {
            Task { @MainActor in _ = await ScheduleIngest.connectReminders(context: context) }
        }
        if connected("hlt") {
            Task { @MainActor in _ = await HealthIngest.connectAndIngest(context: context) }
        }
        if connected("music") {
            // The bare re-scan — refresh must never re-present the
            // permission dialog (2026-07-10).
            Task { @MainActor in _ = await AppleMusicIngest.ingest(context: context) }
        }
        if !RSSStore.shared.feeds.isEmpty {
            Task { @MainActor in _ = await RSSIngest.refresh(context: context) }
        }
        if !BlueskyStore.shared.handle.isEmpty {
            Task { @MainActor in _ = await BlueskyIngest.refresh(context: context) }
        }
        if !FarcasterStore.shared.username.isEmpty {
            Task { @MainActor in _ = await FarcasterIngest.refresh(context: context) }
        }
        if !PinterestStore.shared.username.isEmpty {
            Task { @MainActor in _ = await PinterestIngest.refresh(context: context) }
        }
        for bridge in TokenBridge.allCases where bridge.connected {
            Task { @MainActor in _ = await TokenIngest.refresh(bridge, context: context) }
        }
        if !WalletStore.shared.addresses.isEmpty {
            Task { @MainActor in _ = await WalletIngest.refresh(context: context) }
        }
        for provider in MailProvider.allCases where provider.connected {
            Task { @MainActor in _ = await MailIngest.refresh(provider, context: context) }
        }
        if SteamBridge.connected {
            Task { @MainActor in _ = await SteamIngest.refresh(context: context) }
        }
        if ObsidianStore.shared.connected {
            Task { @MainActor in _ = await ObsidianIngest.refresh(context: context) }
        }
        if TwitchAuth.connected {
            Task { @MainActor in _ = await TwitchIngest.refresh(context: context) }
        }
    }
}
