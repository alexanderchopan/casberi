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

    // MARK: - Slack (2026-07-28)

    /// Slack's "quiet return", the sibling of `checkReturns` above with one
    /// twist: there's no watched-account roster to check against (the bridge
    /// searches mentions of YOU, not a followed list) — every landed Slack
    /// thing already IS a mention, so the author of one is implicitly
    /// "watched" the moment they first mention you. Same self-throttle as
    /// every other moment here: it only fires when the newest mention from
    /// that person landed within THIS pass, so a re-scan can't re-fire it.
    static func checkSlackReturns(context: ModelContext) {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Slack" })
        guard let things = try? context.fetch(descriptor) else { return }
        var byHandle: [String: [Thing]] = [:]
        for thing in things {
            guard let handle = thing.authorHandle else { continue }
            byHandle[handle, default: []].append(thing)
        }
        for (handle, mentions) in byHandle {
            let sorted = mentions.sorted { $0.capturedAt > $1.capturedAt }
            guard sorted.count >= 2 else { continue }
            let newest = sorted[0]
            guard newest.capturedAt.timeIntervalSinceNow > -freshWindow else { continue }
            let gapDays = sorted[1].capturedAt.distance(to: newest.capturedAt) / 86400
            guard gapDays >= quietDays else { continue }
            SourceMoments.shared.fire(
                String(localized: "@\(handle) mentioned you again after \(Int(gapDays)) days"),
                source: "Slack")
        }
    }

    /// The crossing Slack alone can never see: someone @-mentions you sharing
    /// a link you've ALREADY saved from somewhere else. A pure corpus join —
    /// comparing a URL already in the mention's text against every OTHER
    /// thing's `content` — no extra network call, and nothing outside this
    /// phone holds both halves. NEWS ONLY, self-throttled the same way as
    /// every other moment here: only a mention that landed within THIS pass
    /// is checked, so a rescan can't fire the same crossing twice.
    static func checkSlackCrossings(context: ModelContext) {
        let mentionsDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Slack" })
        guard let mentions = try? context.fetch(mentionsDescriptor) else { return }
        let fresh = mentions.filter { $0.capturedAt.timeIntervalSinceNow > -freshWindow }
        guard !fresh.isEmpty else { return }

        let othersDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source != "Slack" })
        guard let others = try? context.fetch(othersDescriptor) else { return }
        var savedByURL: [String: Thing] = [:]
        for candidate in others {
            guard let key = normalizedURL(candidate.content) else { continue }
            savedByURL[key] = candidate
        }
        guard !savedByURL.isEmpty else { return }

        for mention in fresh {
            guard let text = mention.postText, let url = Capture.detectURL(in: text),
                  let key = normalizedURL(url.absoluteString),
                  let saved = savedByURL[key],
                  saved.capturedAt < mention.capturedAt else { continue }
            let who = mention.authorHandle.map { "@\($0)" } ?? String(localized: "Someone")
            SourceMoments.shared.fire(
                String(localized: "\(who) just shared \u{201c}\(saved.title)\u{201d} — you already saved it"),
                source: "Slack")
        }
    }

    /// Loose equality for a link across sources — strips scheme, a leading
    /// "www.", and a trailing slash, so the same article posted via RSS and
    /// pasted into Slack still matches. Deliberately does NOT touch the query
    /// string or attempt tracking-param cleanup: a missed match is honest,
    /// an over-eager one that pairs two different pages isn't.
    private static func normalizedURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for prefix in ["https://www.", "http://www.", "https://", "http://"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s.lowercased()
    }
}
