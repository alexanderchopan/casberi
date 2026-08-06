import Foundation
import SwiftData

/// Telling a Short from a video (2026-08-05).
///
/// A YouTube follow lands uploads and Shorts in one undifferentiated stream —
/// `videos.xml` mixes them and says nothing about which is which. For a
/// channel that posts both (most do now), that means a room where a 20-minute
/// review and a 30-second clip are the same kind of row, and no way to ask for
/// one without the other.
///
/// NOTHING IN THE FEED CAN ANSWER THIS, measured rather than assumed. Every
/// entry's `media:content` is a fixed `640x390` flash placeholder and every
/// `media:thumbnail` a fixed `480x360` hqdefault — identical on a Short and on
/// a landscape upload, so aspect ratio isn't in the payload. There is no
/// duration field, no `yt:` marker, nothing. The one keyless read that
/// separates them is what `youtube.com/shorts/<id>` ANSWERS:
///
///     HEAD /shorts/f7y2XikE7sY   → 200          (a Short)
///     HEAD /shorts/Df5Y-2ndQyU   → 200          (a Short)
///     HEAD /shorts/Z6z_feacXW8   → 303 → /watch (a regular video)
///     HEAD /shorts/_xjxwl1zLMc   → 303 → /watch (a regular video)
///
/// Measured 2026-08-05, 4/4, and asserted nightly (`live-integrations.sh`)
/// because it is an undocumented behaviour that could collapse to one status
/// without notice — at which point every video would classify alike and the
/// tag would be noise instead of a filter.
///
/// HEAD, AND REDIRECTS REFUSED. HEAD downloads zero bytes either way (a watch
/// page is ~1.2MB and a Shorts page ~2MB, so following even one would make
/// this pass absurd). Refusing the redirect is what makes the STATUS the
/// observable — the exact thing measured — rather than inferring from where
/// URLSession ended up after a hop we neither need nor want.
///
/// ONLY SHORTS ARE TAGGED. A `Video` tag on the ~90% of rows that are ordinary
/// uploads is chrome, not information, and §308's facet rule already handles
/// the other side: `Shorts` filters only alongside a named source, so "shorts
/// from youtube" narrows and a bare "short" can never silently hide anything.
/// Which rows have been ASKED lives in a UserDefaults ledger rather than a
/// tag, so an ordinary video costs one request once and never again — and so
/// no new `@Model` property is introduced (a CloudKit Production deploy of its
/// own, CLAUDE.md's standing rule).
enum YouTubeShorts {

    /// The tag a Short wears. Matched by `Retriever.facetFilter`.
    static let tag = "Shorts"

    enum Kind {
        case short
        case video
    }

    struct Report {
        var asked = 0
        var shorts = 0
        var videos = 0
        /// Neither 200 nor a redirect — YouTube didn't tell us. Not recorded
        /// in the ledger, so the row is asked again on a later pass.
        var unclear = 0
        var considered = 0
        /// The host pushed back, or several rows in a row went unclear. A
        /// pass that stops early and a pass that had nothing to do both end
        /// with `asked == 0`, and only one of them means something is wrong.
        var backedOff = false
    }

    /// Rows per pass. Small: this is a HEAD apiece, but it is a HEAD against a
    /// host doing us a favour, and a channel's back catalogue is not urgent.
    /// A 15-video sync classifies in two foregrounds.
    static let perPass = 8

    /// Between requests. Not measured against a rate limit (none is
    /// published); the conservative end of obviously polite, and the same
    /// pacing `InstagramCaptions` settled on.
    static let pace: Duration = .milliseconds(700)

    /// Consecutive unclear answers that end a pass — enough to tell a couple
    /// of deleted videos from the host having stopped answering us.
    private static let backOffAfter = 4

    private static let ledgerKey = "youtube.shorts.asked"
    private static let ledgerCap = 4000

    // MARK: - The video id

    /// The 11-character video id inside a YouTube link, or nil. Handles the
    /// three shapes a landed row can carry: the feed's own
    /// `watch?v=<id>` (every row this bridge lands), a `youtu.be/<id>` short
    /// link, and `/shorts/<id>` for a row that arrived already knowing.
    static func videoID(in link: String) -> String? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host()?.lowercased() else { return nil }
        let isYouTube = host == "youtu.be" || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
        guard isYouTube else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value, plausible(v) {
            return v
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "youtu.be", let id = parts.first, plausible(id) { return id }
        if let i = parts.firstIndex(of: "shorts"), parts.count > i + 1,
           plausible(parts[i + 1]) { return parts[i + 1] }
        return nil
    }

    /// A YouTube video id is exactly 11 base64url characters. Checked rather
    /// than trusted: a path segment that isn't one would send this pass
    /// knocking on `/shorts/about`.
    private static func plausible(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-"
        }
    }

    // MARK: - The read

    /// Refuses every redirect so the 303 is delivered as itself. Without this
    /// URLSession follows to `/watch`, answers 200, and a regular video reads
    /// as a Short — the classification inverted, silently, for every row.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    /// What YouTube says `<id>` is, or nil when it didn't say.
    static func classify(_ id: String) async -> Kind? {
        guard plausible(id), let url = URL(string: "https://www.youtube.com/shorts/\(id)")
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)",
                         forHTTPHeaderField: "User-Agent")
        // `www.youtube.com` is already the YouTube entry's declared host in
        // `NetworkReach` — this pass reaches nowhere new.
        NetworkLedger.shared.record(request, as: "YouTube")
        guard let (_, response) = try? await URLSession.shared.data(
                for: request, delegate: NoRedirect()),
              let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200:          return .short
        case 300..<400:    return .video
        default:           return nil
        }
    }

    // MARK: - The pass

    /// Classifies up to `perPass` unasked YouTube rows, newest first, tagging
    /// the Shorts.
    ///
    /// Newest first because a bounded pass has to choose and a video from this
    /// week is likelier to be asked about than one from two years ago. The
    /// whole room still finishes — later passes take what earlier ones left.
    /// `trace` is the probe's window; one line PER ROW, since a walk that goes
    /// wrong goes wrong at a particular row and a joined NSLog gets truncated
    /// by the log reader (the `-todayProbe` lesson).
    @discardableResult
    @MainActor
    static func sweep(context: ModelContext, limit: Int? = nil,
                      trace: Bool = false) async -> Report {
        var report = Report()
        var asked = Set(UserDefaults.standard.stringArray(forKey: ledgerKey) ?? [])
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == "YouTube" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        // A stated ceiling, not a silent one: rows past the newest 500 are
        // never classified. It costs nothing in practice — every video passes
        // through "newest" as it lands, and the ledger stops it being asked
        // twice — so the only rows this can miss are ones that were already
        // more than 500 deep when the feature shipped. Unbounded, this would
        // fault the whole room on every foreground for a pass that usually has
        // nothing to do.
        descriptor.fetchLimit = 500
        // `.live` at the boundary (CLAUDE.md corollary 4) — this array is held
        // across every await below, and a foreground heal can delete under it.
        let rows = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        // The identity is the REF, not the row: a re-import or a CloudKit
        // merge can hand the same video a new `Thing`, and re-asking YouTube
        // about a video we already classified is exactly the waste this ledger
        // exists to prevent.
        let pending = rows.compactMap { thing -> (ref: String, id: String)? in
            guard let ref = thing.sourceRef, !asked.contains(ref),
                  !thing.tags.contains(tag),
                  let id = videoID(in: thing.content) else { return nil }
            return (ref, id)
        }
        report.considered = pending.count
        var unclearRun = 0

        for (ref, id) in pending.prefix(limit ?? perPass) {
            let kind = await classify(id)
            // The fetch is an await and this row can be deleted under it, so
            // the row is re-found by ref rather than held across the
            // suspension (CLAUDE.md corollary 6).
            guard let thing = rows.first(where: { $0.isLive && $0.sourceRef == ref }) else { continue }
            report.asked += 1
            switch kind {
            case .short:
                unclearRun = 0
                report.shorts += 1
                asked.insert(ref)
                if !thing.tags.contains(tag) { thing.tags.append(tag) }
                if trace { NSLog("ytShort| SHORT | %@ | %@", id, thing.title) }
            case .video:
                unclearRun = 0
                report.videos += 1
                asked.insert(ref)
                if trace { NSLog("ytShort| video | %@ | %@", id, thing.title) }
            case nil:
                // Not recorded — a row YouTube declined to answer about is
                // asked again later, unlike one it answered.
                report.unclear += 1
                unclearRun += 1
                if trace { NSLog("ytShort| unclear | %@ | %@", id, thing.title) }
                if unclearRun >= backOffAfter {
                    report.backedOff = true
                }
            }
            if report.backedOff { break }
            try? await Task.sleep(for: pace)
        }

        if report.shorts > 0 { context.saveHonestly() }
        if asked.count > ledgerCap { asked = Set(asked.suffix(ledgerCap)) }
        UserDefaults.standard.set(Array(asked), forKey: ledgerKey)
        return report
    }
}
