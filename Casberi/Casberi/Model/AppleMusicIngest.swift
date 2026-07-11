import Foundation
import SwiftData
import MusicKit
import UIKit

/// The Apple Music bridge (2026-07-08) — native MusicKit, the same "Apple
/// provides the framework" pattern as HealthKit and Photos. No key, no server:
/// the user grants access with the system prompt, and what they've recently
/// played lands as link things opening in Apple Music. Read-only; nothing is
/// ever added to their library or queue.
enum AppleMusicIngest {

    @MainActor private static var running = false

    /// The song's cover as a plain https URL (mzstatic CDN, no auth) — the
    /// same previewImageURL hook Pinterest uses, so the feed row leads with
    /// the cover instead of the bridge glyph. 300pt square: crisp at the
    /// row's 26pt thumb on 3× screens, small enough that RemoteThumb's
    /// downsample stays cheap. nil when the song carries no artwork or only
    /// a musickit:// library URL URLSession can't fetch — the ONE helper
    /// both the ingest and the Diagnostics probe go through, so the probe
    /// can never test a different URL shape than the app stores.
    static func artURL(_ song: Song) -> String? {
        IngestSupport.imageURL(song.artwork?.url(width: 300, height: 300)?.absoluteString)
    }

    private static func sourceRef(_ song: Song) -> String {
        "applemusic:\(song.id.rawValue)"
    }

    /// The ref embeds the song id, so a stored artless row can be looked up
    /// in the catalog without ever re-appearing in the recent feed.
    private static func songID(fromRef ref: String) -> MusicItemID {
        MusicItemID(String(ref.dropFirst("applemusic:".count)))
    }

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
        // Stored rows still wearing the glyph. The recent feed's own items
        // don't reliably carry usable art — library plays come back with no
        // artwork, or with a musickit:// library URL (field report
        // 2026-07-11: every music row but one wore the glyph) — and a row
        // that ages out of the 25-item recent window would otherwise never
        // heal. The catalog copy of a song always carries mzstatic https
        // art, so everything still artless — stored rows AND fresh landings
        // — gets one batched catalog lookup (the SteamBridge artless-refs
        // pattern, async edition). Empty in the steady state: no request.
        let artlessStored = IngestSupport.artlessThings(context, source: "Apple Music")

        var artByRef: [String: String] = [:]
        for song in response.items {
            if let art = artURL(song) { artByRef[sourceRef(song)] = art }
        }

        var lookupIDs: [MusicItemID] = artlessStored.keys
            .filter { artByRef[$0] == nil }
            .map { songID(fromRef: $0) }
        for song in response.items
        where artByRef[sourceRef(song)] == nil && !existing.contains(sourceRef(song)) {
            lookupIDs.append(song.id)
        }
        if !lookupIDs.isEmpty {
            do {
                let lookup = MusicCatalogResourceRequest<Song>(matching: \.id,
                                                               memberOf: lookupIDs)
                for song in try await lookup.response().items {
                    if let art = artURL(song) { artByRef[sourceRef(song)] = art }
                }
            } catch {
                // Surfaced, never swallowed: a library-format ID can fail
                // the whole batch, and "the lookup failed" must read
                // differently in Console than "the catalog has no art".
                NSLog("[Casberi] Apple Music catalog artwork lookup failed: %@",
                      String(describing: error))
            }
            let stillArtless = lookupIDs.filter { artByRef["applemusic:\($0.rawValue)"] == nil }
            if !stillArtless.isEmpty {
                NSLog("[Casberi] Apple Music: %d of %d looked-up songs still have no usable artwork",
                      stillArtless.count, lookupIDs.count)
            }
        }

        var patched = 0
        for (ref, thing) in artlessStored {
            guard let art = artByRef[ref] else { continue }
            thing.previewImageURL = art
            patched += 1
        }

        var added = 0
        for song in response.items {
            let ref = sourceRef(song)
            if existing.contains(ref) { continue }
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
            thing.previewImageURL = artByRef[ref]
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || patched > 0 { try? context.save() }
        return added
    }

    /// The Diagnostics probe (2026-07-11: music rows still wore the glyph
    /// in the field) — runs the REAL artwork path read-only and returns one
    /// printable line per step: access, what the recent feed hands us per
    /// song, whether the catalog fallback resolves art for everything still
    /// artless (stored rows included), and whether one candidate URL
    /// actually downloads and decodes. Lives here, not in the screen, so
    /// the probe and the ingest can never drift apart.
    @MainActor
    static func artworkDiagnostic(context: ModelContext) async -> [String] {
        guard MusicAuthorization.currentStatus == .authorized else {
            return ["FAIL Music access: \(String(describing: MusicAuthorization.currentStatus))"]
        }
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 25
        let recent: [Song]
        do {
            recent = Array(try await request.response().items)
        } catch {
            return ["FAIL recently-played request: \(error.localizedDescription)"]
        }

        var lines: [String] = []
        var candidates = recent.compactMap { artURL($0) }
        lines.append("Recently played: \(recent.count) songs, \(candidates.count) with fetchable https art")
        for song in recent.prefix(3) {
            let raw = song.artwork?.url(width: 300, height: 300)?.absoluteString ?? "no artwork"
            lines.append("· \(song.title.prefix(16)): \(raw.prefix(44))")
        }

        // The catalog fallback, exercised for real — the same lookup set
        // the ingest builds: artless recent songs plus stored artless refs.
        var lookupIDs = Set(recent.filter { artURL($0) == nil }.map(\.id))
        let artlessStored = IngestSupport.artlessThings(context, source: "Apple Music")
        lookupIDs.formUnion(artlessStored.keys.map { songID(fromRef: $0) })
        if lookupIDs.isEmpty {
            lines.append("OK nothing needs the catalog fallback")
        } else {
            do {
                let lookup = MusicCatalogResourceRequest<Song>(matching: \.id,
                                                               memberOf: Array(lookupIDs))
                let matched = Array(try await lookup.response().items)
                let art = matched.compactMap { artURL($0) }
                lines.append("\(art.isEmpty ? "FAIL" : "OK") catalog fallback: asked \(lookupIDs.count), matched \(matched.count), \(art.count) with https art")
                candidates += art
            } catch {
                lines.append("FAIL catalog fallback: \(error.localizedDescription)")
            }
        }

        if let first = candidates.first, let url = URL(string: first) {
            do {
                let (data, urlResponse) = try await URLSession.shared.data(from: url)
                let code = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
                if UIImage(data: data) != nil {
                    lines.append("OK artwork fetch: HTTP \(code), \(data.count) bytes, decodes as an image")
                } else {
                    lines.append("FAIL artwork fetch: HTTP \(code), \(data.count) bytes — not image bytes")
                }
            } catch {
                lines.append("FAIL artwork fetch: \(error.localizedDescription)")
            }
        } else {
            lines.append("FAIL no artwork URL from any path — every row will wear the glyph")
        }
        return lines
    }
}
