import Foundation
import SwiftData

/// Captions for imported Instagram saves and likes (2026-08-02, prd §245
/// amendment) — the pass that makes those rows findable.
///
/// WHY THIS EXISTS. §245 landed saves and likes as named links: a handle, a
/// permalink, a date, because that is the whole of what Meta's export gives
/// you for a post somebody else made. It also stated the consequence plainly —
/// search "pasta" and the pasta recipe you saved will not come back, because
/// the word was never in the export. That was true of the EXPORT and false of
/// the WEB, and the difference was measured on 2026-08-02: a logged-out
/// Instagram post URL serves full Open Graph tags to the same
/// `safariUserAgent` this app already sends. The login wall is in the page
/// BODY; the `<head>` is open, which is how every unfurler on the internet
/// still shows an Instagram preview.
///
///     og:title       Everyday Astronaut on Instagram: "I love @spacecenterhou!…"
///     og:description 6,800 likes, 29 comments - everydayastronaut on
///                    September 29, 2021: "I love @spacecenterhou!…"
///
/// So one keyless request per row turns "@everydayastronaut" into the post's
/// actual words, and the corpus can hold them. That is the entire feature.
///
/// NO IMAGE, and the reason is measured rather than assumed. `og:image` is a
/// real CDN URL and it works — but it is SIGNED and carries its own expiry:
/// the sampled post's `oe=6A74B2B9` decoded to 2026-08-06, four days out.
/// Storing it as `previewImageURL` would give every row art that silently 404s
/// within the week, and re-fetching 500 rows every few days to keep signatures
/// warm is not a trade worth making for decoration. Text is what retrieval
/// needs and text is what this pass takes.
///
/// BOUNDED, PACED AND RESUMABLE, because one measured request proves nothing
/// about five hundred. This is the Farcaster follow-graph lesson (CLAUDE.md):
/// there, single requests looked perfect and an unpaced walk silently returned
/// a truncated prefix wearing "that's all". So: `perPass` rows per foreground,
/// `pace` between requests, an abort the moment the host says 429 or five
/// rows fail in a row, and no cursor to corrupt — an unenriched row is simply
/// one whose `enrichedText` is still nil, so an interrupted pass resumes by
/// arithmetic rather than by bookkeeping.
///
/// THE FAILURE LEDGER IS IN USERDEFAULTS, NOT ON `Thing`, and that is
/// deliberate: a new `@Model` property is a CloudKit Production deploy of its
/// own (CLAUDE.md's standing rule), and "we tried this row twice" is local
/// bookkeeping that has no business syncing to every device. A ref is retried
/// up to `maxAttempts` times so a tunnel or a flaky minute doesn't orphan a
/// row forever, then left alone — a deleted or private post is not coming
/// back, and asking again every ten minutes for the rest of time is rude to a
/// host doing us a favour.
enum InstagramCaptions {

    struct Report {
        var enriched = 0
        var failed = 0
        var considered = 0
        /// The host pushed back (429) or five rows failed in a row. Reported
        /// rather than swallowed: "0 enriched because we stopped" and
        /// "0 enriched because there was nothing to do" are different facts,
        /// and only one of them means something is wrong.
        var backedOff = false
    }

    /// Rows per foreground pass. At `pace` this is about 25 seconds of
    /// background work — a 500-save library finishes over a couple of days of
    /// ordinary use rather than in one 10-minute burst against one host.
    static let perPass = 20

    /// Between requests. Not tuned by measurement (nobody here has 500 real
    /// saves to walk); chosen as the conservative end of "obviously polite"
    /// and worth re-measuring against a real library before raising.
    static let pace: Duration = .milliseconds(1200)

    /// Consecutive failures that end a pass. Five is enough to distinguish a
    /// couple of deleted posts from the host having stopped answering us.
    private static let backOffAfter = 5
    private static let maxAttempts = 3
    private static let ledgerKey = "instagram.captions.attempts"
    private static let ledgerCap = 2000

    // MARK: - The pass

    /// Enriches up to `perPass` unenriched saves/likes, newest first.
    ///
    /// Newest first because a save from last week is likelier to be searched
    /// for than one from 2019, and a bounded pass has to choose. The whole
    /// library still finishes — later passes take what earlier ones left.
    /// `trace` is the probe's window and nothing else uses it. One line PER
    /// ROW rather than a joined summary, because a walk that goes wrong goes
    /// wrong at a particular row — and because a single long NSLog gets
    /// truncated by the log reader (the `-todayProbe` lesson, paid for twice).
    @MainActor
    static func heal(context: ModelContext,
                     trace: ((String) -> Void)? = nil) async -> Report {
        var report = Report()
        var ledger = attempts()

        let due = candidates(context: context, ledger: ledger)
        report.considered = due.count
        guard !due.isEmpty else { return report }

        var consecutiveFailures = 0
        for thing in due.prefix(perPass) {
            // The row was chosen before any await; a heal or a CloudKit
            // delete can tombstone it while we are on the network, and
            // reading a stored property off a tombstoned model traps inside
            // SwiftData (the liveness rule, CLAUDE.md).
            guard thing.isLive else { continue }
            let ref = thing.sourceRef ?? ""
            guard let url = postURL(thing) else {
                bump(&ledger, ref, to: maxAttempts)   // never fetchable, stop asking
                continue
            }

            let outcome = await fetch(url)
            switch outcome {
            case .rateLimited:
                trace?("RATE LIMITED at \(url.path()) — stopping this pass")
                report.backedOff = true
                save(ledger)
                return report
            case .permanentlyGone:
                trace?("gone \(url.path()) — deleted or private, not asking again")
                report.failed += 1
                consecutiveFailures += 1
                bump(&ledger, ref, to: maxAttempts)
            case .unreachable:
                trace?("unreachable \(url.path()) — attempt \((ledger[ref] ?? 0) + 1)/\(maxAttempts)")
                report.failed += 1
                consecutiveFailures += 1
                bump(&ledger, ref)
            case .found(let caption, let retrieval):
                consecutiveFailures = 0
                if apply(caption: caption, retrieval: retrieval, to: thing, context: context) {
                    trace?("ok \(url.path()) → \(caption.prefix(90))")
                    report.enriched += 1
                } else {
                    trace?("nothing to write \(url.path()) — answered, but with no usable change")
                    // Answered, but with nothing usable in it. Counted as a
                    // failure against the ledger so a page that will never
                    // carry og tags isn't asked forever.
                    report.failed += 1
                    bump(&ledger, ref)
                }
            }

            if consecutiveFailures >= backOffAfter {
                trace?("backing off — \(backOffAfter) rows failed in a row")
                report.backedOff = true
                break
            }
            try? await Task.sleep(for: pace)
        }

        save(ledger)
        return report
    }

    /// Saves and likes still wearing only their handle, newest first.
    ///
    /// `enrichedText == nil` IS the cursor: a row this pass finishes drops out
    /// of the next one's candidates by itself, so an interrupted pass has no
    /// state to resume from and no way to skip a row it never reached.
    @MainActor
    private static func candidates(context: ModelContext,
                                   ledger: [String: Int]) -> [Thing] {
        IngestSupport.thingsByRef(context, source: "Instagram")
            .filter { ref, thing in
                thing.isLive
                    && thing.kind == .link
                    && thing.enrichedText == nil
                    && (ref.hasPrefix("instagram:saved:") || ref.hasPrefix("instagram:liked:"))
                    && (ledger[ref] ?? 0) < maxAttempts
            }
            .values
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// The post to ask about — but ONLY when it really is an Instagram post.
    ///
    /// The permalink comes out of a file Meta wrote and the person picked; it
    /// is DATA, not a promise. Without this check an export carrying an href
    /// to anywhere at all would make this pass fetch that host on the person's
    /// behalf, which is both a privacy leak and the one thing `NetworkReach`
    /// exists to make impossible to do quietly. Matched on the label boundary,
    /// never `contains` — the `OEmbed` allowlist rule, same reasoning.
    private static func postURL(_ thing: Thing) -> URL? {
        guard let url = URL(string: thing.content.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host()?.lowercased(),
              host == "instagram.com" || host.hasSuffix(".instagram.com"),
              url.scheme?.lowercased() == "https"
        else { return nil }
        return url
    }

    // MARK: - The read

    private enum Outcome {
        case found(caption: String, retrieval: String)
        case permanentlyGone      // deleted, or private: never coming back
        case unreachable          // a blip; worth asking again later
        case rateLimited          // the host asked us to stop
    }

    /// One request, three fields, no key and no account.
    ///
    /// The byte cap is generous rather than tight: the sampled post carried
    /// `og:title` at byte 10,539 of a 638KB page, but Instagram front-loads a
    /// great deal of inline script and another post could sit deeper. 256KB
    /// covers the measured head (which ended at ~137KB) with room to spare and
    /// still refuses to read a whole page into memory.
    private static func fetch(_ url: URL) async -> Outcome {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        // The receipts ledger, same as `OEmbed.resolve` and `LinkTitle`'s two
        // fetches. Without it a caption pass would reach instagram.com once per
        // imported save and show up NOWHERE in "What it actually reached" — the
        // invisible-by-construction failure that shipped an undisclosed host in
        // build 214, and the reason the coverage audit exists.
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unreachable }
        switch http.statusCode {
        case 200: break
        case 404, 410: return .permanentlyGone
        case 429: return .rateLimited
        default: return .unreachable
        }

        let html = String(decoding: data.prefix(262_144), as: UTF8.self)
        let title = meta(html, "og:title")
        let description = meta(html, "og:description")
        // `og:title` is the face — it already reads "Author on Instagram:
        // "caption"" — and `og:description` is the richer retrieval line,
        // carrying the handle, the date and the counts alongside the same
        // words. Either alone is worth having; neither means this page told
        // us nothing and the row keeps the handle it has.
        guard let caption = title ?? description else { return .unreachable }
        return .found(caption: caption, retrieval: description ?? caption)
    }

    /// An Open Graph value, in both attribute orders (providers write them
    /// either way round) with entities decoded.
    private static func meta(_ html: String, _ property: String) -> String? {
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(property)[\"'][^>]*content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(property)[\"']",
        ]
        for pattern in patterns {
            guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else { continue }
            let match = String(html[range])
            guard let value = match.range(of: "content=[\"']([^\"']+)", options: .regularExpression)
            else { continue }
            let raw = String(match[value]).dropFirst("content=".count).dropFirst()
            let clean = IngestSupport.decodeHTMLEntities(String(raw))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return clean }
        }
        return nil
    }

    // MARK: - Writing it down

    /// True when something actually changed. Mirrors `LinkTitle`'s save
    /// discipline: no write unless there is news, and a write drops the stale
    /// vector so the next semantic sweep re-embeds on the real words.
    @MainActor
    private static func apply(caption: String, retrieval: String,
                              to thing: Thing, context: ModelContext) -> Bool {
        guard thing.isLive else { return false }
        var changed = false
        let face = IngestSupport.titleLine(caption)
        if face != thing.title, !face.isEmpty {
            thing.title = face
            changed = true
        }
        let text = retrieval.count > 1200 ? String(retrieval.prefix(1200)) + "…" : retrieval
        if text != thing.enrichedText {
            thing.enrichedText = text
            changed = true
        }
        guard changed else { return false }
        thing.embedding = nil
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return true
    }

    // MARK: - The attempt ledger

    private static func attempts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Int] ?? [:]
    }

    private static func bump(_ ledger: inout [String: Int], _ ref: String, to value: Int? = nil) {
        guard !ref.isEmpty else { return }
        ledger[ref] = value ?? ((ledger[ref] ?? 0) + 1)
    }

    /// Bounded so a decade-deep library can't grow this without limit. Trimmed
    /// by dropping the rows we've tried LEAST — a ref at `maxAttempts` is the
    /// one worth remembering, since forgetting it is what would put a dead
    /// post back in the queue forever.
    private static func save(_ ledger: [String: Int]) {
        var out = ledger
        if out.count > ledgerCap {
            out = Dictionary(uniqueKeysWithValues:
                out.sorted { $0.value > $1.value }.prefix(ledgerCap).map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(out, forKey: ledgerKey)
    }

    /// DEBUG only — lets `-instagramCaptions` re-walk rows a previous run
    /// gave up on, so the pass can be exercised twice in a session.
    static func forgetFailures() {
        UserDefaults.standard.removeObject(forKey: ledgerKey)
    }
}
