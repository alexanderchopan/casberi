import Foundation
import SwiftData

/// One foreground refresh for every connected polling bridge (RSS, Bluesky,
/// Farcaster, and each connected token bridge). RootShell fires it on
/// scenePhase → .active; screens can reuse it (e.g. pull-to-refresh) instead of
/// repeating the guard-then-Task shape per bridge. Each bridge refreshes
/// independently, fire-and-forget, on the main actor.
@MainActor
enum BridgeRefresh {
    static func refreshAllConnected(context: ModelContext) {
        if !RSSStore.shared.feeds.isEmpty {
            Task { @MainActor in _ = await RSSIngest.refresh(context: context) }
        }
        if !BlueskyStore.shared.handle.isEmpty {
            Task { @MainActor in _ = await BlueskyIngest.refresh(context: context) }
        }
        if !FarcasterStore.shared.username.isEmpty {
            Task { @MainActor in _ = await FarcasterIngest.refresh(context: context) }
        }
        for bridge in TokenBridge.allCases where bridge.connected {
            Task { @MainActor in _ = await TokenIngest.refresh(bridge, context: context) }
        }
        for provider in MailProvider.allCases where provider.connected {
            Task { @MainActor in _ = await MailIngest.refresh(provider, context: context) }
        }
    }
}
