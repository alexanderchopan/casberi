import Foundation
import SwiftData

/// Delight for the Media bridges (2026-07-28) — YouTube, Twitch, Spotify,
/// Apple Music, Podcasts, Steam, Pinterest never fired a single moment
/// (`SourceMoments` had zero media callers) because none of them stamped
/// `authorHandle`, so there was nothing to group by and nothing to join on.
/// YouTube already gained a quiet return, a view-doubling and a retitle
/// moment alongside Reddit (`FeedFollowMoments`, same day) — Podcasts now
/// rides that SAME generalized `checkReturns` (BridgeRefresh wires it in),
/// so this file adds only what those two don't cover:
///
/// 1. TWITCH'S QUIET RETURN — a followed streamer live again after a real
///    gap. `FeedFollowMoments.checkReturns` is scoped to `FeedFollowKind`
///    (Substack/Reddit/YouTube/Podcasts, one shared ingest engine); Twitch
///    is its own bridge, so it gets its own copy of the same shape here
///    rather than a cross-file dependency between two otherwise-independent
///    moments files (the `SocialMoments`/`FeedFollowMoments` precedent: they
///    duplicate the same ~15-line pattern rather than share it).
/// 2. TWITCH × STEAM CROSSING — a followed streamer goes live playing a game
///    already in your Steam library. The `SocialMoments.checkSlackCrossings`
///    shape: both halves are already-landed things, compared locally.
/// 3. ARTIST CROSSING — a new YouTube upload or podcast episode names an
///    artist you've liked/played on Spotify or Apple Music. Same shape as
///    #2, the other direction across Media's two halves (watching/listening
///    vs. following).
///
/// Steam's own return (a game replayed after months) fires INLINE in
/// `SteamBridge.refresh` instead — Steam dedupes a game to ONE thing
/// forever, so there's no second landing here to diff a gap against; only
/// the live `playtime_2weeks` signal proves a replay, and only the ingest
/// itself reads that (see `SourceMoments.notedReturn`).
///
/// Pinterest carries no moment here — it mirrors YOUR OWN public boards
/// (like Spotify/Apple Music/Steam), so there's no third party who can "go
/// quiet then return"; nothing else in Media crosses it either.
///
/// BridgeRefresh is the only caller, once per foreground pass after the
/// relevant bridges have synced.
@MainActor
enum MediaMoments {

    /// A gap this long or more, ending just now, reads as "was away" — same
    /// threshold SocialMoments/FeedFollowMoments/PredictionMoments use.
    private static let quietDays: Double = 30
    /// A post older than this when this pass runs is a re-scan, not a fresh
    /// arrival — only something that landed in roughly THIS refresh counts.
    private static let freshWindow: TimeInterval = 600

    /// Every landed Twitch thing's channel is implicitly "watched" — a
    /// channel that went live once IS a followed channel (Twitch's own
    /// followed-streams endpoint guarantees that) — so there's no separate
    /// roster to intersect against, just a gap between the newest landing
    /// and the one before it for that same channel. Self-throttling by
    /// construction: once this pass sees the fresh stream, it's no longer
    /// "fresh" next time.
    static func checkTwitchReturns(context: ModelContext) {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Twitch" })
        guard let things = try? context.fetch(descriptor) else { return }
        var byChannel: [String: [Thing]] = [:]
        for thing in things {
            guard let channel = thing.authorHandle, !channel.isEmpty else { continue }
            byChannel[channel, default: []].append(thing)
        }
        for (channel, streams) in byChannel {
            let sorted = streams.sorted { $0.capturedAt > $1.capturedAt }
            guard sorted.count >= 2 else { continue }
            let newest = sorted[0]
            guard newest.capturedAt.timeIntervalSinceNow > -freshWindow else { continue }
            let gapDays = sorted[1].capturedAt.distance(to: newest.capturedAt) / 86400
            guard gapDays >= quietDays else { continue }
            SourceMoments.shared.fire(
                String(localized: "\(channel) is live again after \(Int(gapDays)) days"), source: "Twitch")
        }
    }

    /// A followed streamer's live game (parsed off the title `TwitchIngest`
    /// itself builds and reads — the one shared source of truth) matched
    /// against every game already in your Steam library. Only Twitch things
    /// that landed THIS pass are checked, so a rescan can't re-fire the same
    /// crossing.
    static func checkTwitchSteamCrossing(context: ModelContext) {
        let twitchDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Twitch" })
        guard let twitchThings = try? context.fetch(twitchDescriptor) else { return }
        let fresh = twitchThings.filter { $0.capturedAt.timeIntervalSinceNow > -freshWindow }
        guard !fresh.isEmpty else { return }

        let steamDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Steam" })
        guard let steamThings = try? context.fetch(steamDescriptor) else { return }
        var gamesPlayed: Set<String> = []
        for thing in steamThings {
            guard let name = thing.authorHandle, !name.isEmpty else { continue }
            gamesPlayed.insert(name.lowercased())
        }
        guard !gamesPlayed.isEmpty else { return }

        for stream in fresh {
            guard let channel = stream.authorHandle,
                  let game = TwitchIngest.game(fromTitle: stream.title),
                  gamesPlayed.contains(game.lowercased()) else { continue }
            SourceMoments.shared.fire(
                String(localized: "\(channel) is playing \(game) on Twitch — you've played it too"),
                source: "Twitch")
        }
    }

    /// A fresh YouTube/Podcasts thing whose title or summary names an artist
    /// already in Spotify/Apple Music's landed things. Two separate
    /// single-equality fetches per side, merged in Swift, rather than an
    /// OR'd `#Predicate` — every existing predicate in this codebase sticks
    /// to plain equality, and there's no precedent this file should be the
    /// first to break that on. Substring containment (not a stop-word/
    /// significant-word overlap like PredictionMoments) is enough here:
    /// artist names are proper nouns, so a false positive would need one to
    /// coincidentally appear verbatim in unrelated text — a >=3-char floor
    /// guards the shortest edge case ("Sia", "Adele"-length names still
    /// pass; initials/single words that short don't).
    static func checkArtistCrossing(context: ModelContext) {
        let youtubeDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "YouTube" })
        let podcastsDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Podcasts" })
        let feedThings = ((try? context.fetch(youtubeDescriptor)) ?? [])
            + ((try? context.fetch(podcastsDescriptor)) ?? [])
        let fresh = feedThings.filter { $0.capturedAt.timeIntervalSinceNow > -freshWindow }
        guard !fresh.isEmpty else { return }

        let spotifyDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Spotify" })
        let appleMusicDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Apple Music" })
        let musicThings = ((try? context.fetch(spotifyDescriptor)) ?? [])
            + ((try? context.fetch(appleMusicDescriptor)) ?? [])
        var artists: Set<String> = []
        for thing in musicThings {
            guard let handle = thing.authorHandle, !handle.isEmpty else { continue }
            for name in handle.components(separatedBy: ", ") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 3 { artists.insert(trimmed) }
            }
        }
        guard !artists.isEmpty else { return }

        for item in fresh {
            let haystack = (item.title + " " + (item.summary ?? "")).lowercased()
            guard let match = artists.first(where: { haystack.contains($0.lowercased()) }) else { continue }
            let noun = item.source == "YouTube" ? String(localized: "A video") : String(localized: "An episode")
            SourceMoments.shared.fire(
                String(localized: "\(noun) mentions \(match) — you've been listening"),
                source: item.source)
        }
    }
}
