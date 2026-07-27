import Foundation
import SwiftData

/// A watched account posting again after a real quiet stretch is a moment
/// (delight pass 2026-07-21) — the app noticing your setup, the social
/// sibling of the wallet's new-high and Bitrefill's refill (SourceMoments).
/// Purely a read-only pass over things ALREADY landed after a network's own
/// refresh runs — no change to FarcasterIngest/BlueskyIngest's own landing
/// logic, so the two networks' ingest internals stay untouched.
///
/// Self-throttling by construction, no persisted "already announced" flag
/// needed: it only fires when the account's NEWEST post landed within THIS
/// pass (a tight recency window) and the post before it is a genuine 30+ day
/// gap. Next time this runs, that same post is no longer the fresh newest
/// one, so the same return can't fire twice — and a person who posts daily
/// never has a 30-day gap to trip on in the first place.
@MainActor
enum SocialMoments {
    /// A gap this long or more, ending just now, reads as "was away".
    private static let quietDays: Double = 30
    /// A post older than this when this pass runs is a re-scan, not a fresh
    /// arrival — only something that landed in roughly THIS refresh counts.
    private static let freshWindow: TimeInterval = 600

    static func checkFarcasterReturns(context: ModelContext) {
        checkReturns(source: "Farcaster", handles: FarcasterStore.shared.usernames, context: context)
    }

    static func checkBlueskyReturns(context: ModelContext) {
        checkReturns(source: "Bluesky", handles: BlueskyStore.shared.handles, context: context)
    }

    /// `authorHandle` stores a raw hex pubkey for Nostr (the stable matching
    /// key — see `NostrIngest.land`), so the fire message needs its own
    /// display resolve rather than the bare handle Farcaster/Bluesky wear.
    static func checkNostrReturns(context: ModelContext) {
        let handles = NostrStore.shared.accounts.map { $0.pubkeyHex.isEmpty ? $0.input : $0.pubkeyHex }
        checkReturns(source: "Nostr", handles: handles, context: context) {
            NostrStore.shared.displayHandle(for: $0)
        }
    }

    private static func checkReturns(source: String, handles: [String], context: ModelContext,
                                     display: (String) -> String = { $0 }) {
        guard !handles.isEmpty else { return }
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        guard let things = try? context.fetch(descriptor) else { return }
        let watched = Set(handles)
        var byHandle: [String: [Thing]] = [:]
        for thing in things {
            // Their OWN posts only (never a cast/post they merely liked or
            // were mentioned in) — authorHandle names who wrote it.
            guard let handle = thing.authorHandle, watched.contains(handle) else { continue }
            byHandle[handle, default: []].append(thing)
        }
        for (handle, posts) in byHandle {
            let sorted = posts.sorted { $0.capturedAt > $1.capturedAt }
            guard sorted.count >= 2 else { continue }
            let newest = sorted[0]
            guard newest.capturedAt.timeIntervalSinceNow > -freshWindow else { continue }
            let gapDays = sorted[1].capturedAt.distance(to: newest.capturedAt) / 86400
            guard gapDays >= quietDays else { continue }
            let label = display(handle)
            let prefixed = label.contains("@") ? label : "@\(label)"
            SourceMoments.shared.fire(
                String(localized: "\(prefixed) is back after \(Int(gapDays)) days"), source: source)
        }
    }
}
