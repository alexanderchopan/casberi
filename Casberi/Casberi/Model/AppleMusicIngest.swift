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

    /// Lowercase, alphanumerics only — drops punctuation, spacing, and case
    /// so a forgiving title compare survives "Daddy Your Rose!" vs
    /// "daddy your rose" without matching across different songs.
    private static func normalizedTitle(_ s: String) -> String {
        String(String.UnicodeScalarView(
            s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// A catalog search hit is the track we asked for when either title
    /// contains the other's normalized form — tolerates a catalog copy's
    /// "(Remastered)"/" - Single" suffix while still rejecting an unrelated
    /// song (a non-empty containment both ways, never two empty strings).
    private static func titleMatches(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.contains(b) || b.contains(a)
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

        let existing = IngestSupport.existingSourceRefs(context, source: "Apple Music")
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
        // Stored rows with no per-track URL — a library play's `Song.url` is
        // often nil, so `content` landed empty and "Open in Apple Music"
        // falls back to the bare app scheme (`music://`, opens the main
        // screen, not the song). Healed the same way artless rows are:
        // whatever catalog copy the passes below turn up also carries a
        // usable https deep link.
        let contentlessStored = IngestSupport.contentlessThings(context, source: "Apple Music")

        var artByRef: [String: String] = [:]
        var urlByRef: [String: String] = [:]
        // A title+artist search term for every ref that's missing art OR a
        // per-track URL the direct way — the fuel for the last-resort catalog
        // search below.
        var termForRef: [String: String] = [:]
        // The pure track title per ref — used to VERIFY a catalog search hit
        // actually is the track we asked for before trusting its art (an
        // obscure library track's top search hit can be a totally unrelated
        // popular song; field report 2026-07-12: "Daddy Your Rose" wore
        // Nirvana's cover).
        var titleForRef: [String: String] = [:]
        for song in response.items {
            let ref = sourceRef(song)
            if let art = artURL(song) { artByRef[ref] = art }
            if let url = song.url { urlByRef[ref] = url.absoluteString }
            if artByRef[ref] == nil || urlByRef[ref] == nil {
                termForRef[ref] = "\(song.title) \(song.artistName)"
                titleForRef[ref] = song.title
            }
        }
        for (ref, thing) in artlessStored where artByRef[ref] == nil {
            // The stored title is "Title — Artist"; the em-dash split is a
            // clean search term (and the only handle a stored row that aged
            // out of the recent window still has).
            termForRef[ref] = thing.title.replacingOccurrences(of: " — ", with: " ")
            titleForRef[ref] = thing.title.components(separatedBy: " — ").first ?? thing.title
        }
        for (ref, thing) in contentlessStored where termForRef[ref] == nil {
            termForRef[ref] = thing.title.replacingOccurrences(of: " — ", with: " ")
            titleForRef[ref] = thing.title.components(separatedBy: " — ").first ?? thing.title
        }

        // Pass 1 — catalog id lookup: resolves plays that came from the
        // catalog directly.
        var lookupIDs: [MusicItemID] = Set(artlessStored.keys).union(contentlessStored.keys)
            .filter { artByRef[$0] == nil || urlByRef[$0] == nil }
            .map { songID(fromRef: $0) }
        for song in response.items
        where !existing.contains(sourceRef(song))
            && (artByRef[sourceRef(song)] == nil || urlByRef[sourceRef(song)] == nil) {
            lookupIDs.append(song.id)
        }
        if !lookupIDs.isEmpty {
            do {
                let lookup = MusicCatalogResourceRequest<Song>(matching: \.id,
                                                               memberOf: lookupIDs)
                for song in try await lookup.response().items {
                    let ref = sourceRef(song)
                    if let art = artURL(song) { artByRef[ref] = art }
                    if let url = song.url { urlByRef[ref] = url.absoluteString }
                }
            } catch {
                NSLog("[Casberi] Apple Music catalog id lookup failed: %@",
                      String(describing: error))
            }
        }

        // Pass 2 — catalog SEARCH by title+artist (2026-07-11 fix): a LIBRARY
        // play's id can't be resolved by the catalog id lookup at all, so its
        // row was stuck glyph-only; searching the catalog for the same track
        // finds the copy that carries mzstatic art (and a per-track URL).
        // This is what heals a corpus that re-ingested without art (device
        // report: music covers "worked before, broke recently" — a
        // schema-change reinstall wiped the stored URLs and the id lookup
        // alone couldn't rebuild them). One request per still-unresolved ref,
        // capped so a large backlog can't stall a foreground refresh; the
        // rest heal on later passes.
        let searchable = termForRef.filter { artByRef[$0.key] == nil || urlByRef[$0.key] == nil }
        var healedBySearch = 0
        for (ref, term) in searchable.prefix(25) {
            var search = MusicCatalogSearchRequest(term: term, types: [Song.self])
            // A few candidates, not one: the very top hit for an obscure
            // library track is often an unrelated chart-topper, but the right
            // track frequently sits just below it — so scan a handful and take
            // the first whose TITLE actually matches (2026-07-12: `.first`
            // alone stored Nirvana's cover on "Daddy Your Rose").
            search.limit = 5
            guard let songs = try? await search.response().songs else { continue }
            let want = titleForRef[ref].map { Self.normalizedTitle($0) }
            if let hit = songs.first(where: {
                    guard let want else { return true }
                    return Self.titleMatches(Self.normalizedTitle($0.title), want)
                }) {
                if let art = artURL(hit) { artByRef[ref] = art }
                if let url = hit.url { urlByRef[ref] = url.absoluteString }
                healedBySearch += 1
            }
            // No matching hit: leave the ref artless/URL-less (the honest
            // glyph and app-scheme fallback) rather than pinning a stranger's
            // track to this one.
        }
        NSLog("[Casberi] Apple Music artwork: %d recent-played, %d stored artless, %d stored URL-less, %d id-lookups, %d art resolved / %d URLs resolved (%d via search), %d still unresolved",
              response.items.count, artlessStored.count, contentlessStored.count, lookupIDs.count,
              artByRef.count, urlByRef.count, healedBySearch, searchable.count - healedBySearch)

        var patched = 0
        for (ref, thing) in artlessStored {
            guard let art = artByRef[ref] else { continue }
            thing.previewImageURL = art
            patched += 1
        }
        for (ref, thing) in contentlessStored {
            guard let url = urlByRef[ref] else { continue }
            thing.content = url
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
                content: song.url?.absoluteString ?? urlByRef[ref] ?? "",
                source: "Apple Music",
                capturedAt: song.lastPlayedDate ?? .now,
                sourceRef: ref
            )
            thing.previewImageURL = artByRef[ref]
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || patched > 0 { context.saveHonestly() }
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
