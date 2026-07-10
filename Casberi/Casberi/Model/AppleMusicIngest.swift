import Foundation
import SwiftData
import MusicKit

/// The Apple Music bridge (2026-07-08) — native MusicKit, the same "Apple
/// provides the framework" pattern as HealthKit and Photos. No key, no server:
/// the user grants access with the system prompt, and what they've recently
/// played lands as link things opening in Apple Music. Read-only; nothing is
/// ever added to their library or queue.
enum AppleMusicIngest {

    @MainActor private static var running = false

    /// Asks for Apple Music access (in context), then lands recently-played
    /// songs. Returns the new count, or nil when access is denied/unavailable.
    @MainActor
    static func connectAndIngest(context: ModelContext) async -> Int? {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            NSLog("[Casberi] Apple Music: authorization %@", String(describing: status))
            return nil
        }
        return await ingest(context: context)
    }

    /// The bare re-scan BridgeRefresh uses — NEVER requests authorization
    /// (2026-07-10: the refresh path called the full connect, so an
    /// unanswered permission dialog re-presented on every foreground).
    @MainActor
    static func ingest(context: ModelContext) async -> Int? {
        guard MusicAuthorization.currentStatus == .authorized else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 25
        let response: MusicRecentlyPlayedResponse<Song>
        do {
            response = try await request.response()
        } catch {
            // The one MusicKit failure the other Apple bridges can't have:
            // recently-played needs the App ID registered for the MusicKit
            // service (developer portal) AND an Apple Music subscription —
            // authorization succeeding doesn't prove either. Log the real
            // reason so Console/diagnostics can say which (2026-07-10).
            NSLog("[Casberi] Apple Music request failed: %@", String(describing: error))
            return nil
        }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0
        for song in response.items {
            let ref = "applemusic:\(song.id.rawValue)"
            guard !existing.contains(ref) else { continue }
            let artist = song.artistName
            let title = artist.isEmpty ? song.title : "\(song.title) — \(artist)"
            let thing = Thing(
                kind: .link,
                title: title,
                content: song.url?.absoluteString ?? "",
                source: "Apple Music",
                capturedAt: song.lastPlayedDate ?? .now,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}
