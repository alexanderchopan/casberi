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
/// THE COVER, AND WHY THE OLD REFUSAL WAS RIGHT ABOUT THE WRONG THING
/// (2026-08-18, prd §395). This doc used to say "NO IMAGE", on a measured
/// fact: `og:image` is a real CDN URL that works, and it is SIGNED with its own
/// expiry — the sampled post's `oe=6A74B2B9` decoded to four days out. Storing
/// it as `previewImageURL` would give every row art that silently 404s within
/// the week, and re-fetching hundreds of rows to keep signatures warm is not a
/// trade worth making for decoration. All of that is still true.
///
/// It was an argument about the URL, and it was applied to the PIXELS. Every
/// other picture in this app is a 480pt JPEG on `previewImageData` — bytes,
/// which cannot expire — and `ImportMedia` has produced exactly that object,
/// from an import, since prd §310. So the cover is fetched ONCE, downscaled,
/// and kept; the signed URL is read, used and thrown away, never stored. In the
/// one room in this app that is a photo app, that is the difference between a
/// list of handles and Instagram.
///
/// BOUNDED HARDER THAN THE CAPTIONS, because pixels cost more than words:
/// `coverCap` covers in total, ever, across the whole library. At ~40KB each
/// that is a store this size (see the constant), and it is a CloudKit-mirrored
/// store — text is cheap to sync and pictures are not. Newest first, so the cap
/// keeps the saves a person is likeliest to be looking for.
///
/// THE HOST IS CHECKED, exactly as the post URL is. `og:image` is a string out
/// of a page, so it names whatever that page says — and following it blindly is
/// the same privacy leak `postURL` refuses one function down. Matched on the
/// label boundary against Meta's own two CDNs, never `contains`.
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
        /// Covers stored this pass (2026-08-18, prd §395). Counted apart from
        /// `enriched` because they succeed and fail independently: a post can
        /// answer with its words and no picture, and a picture can fail to
        /// download from a page that read perfectly.
        var covered = 0
        /// How many covers this library has stored in total, against the cap.
        /// Reported so "no new covers" can be told apart from "the cap is full",
        /// which look identical from outside.
        var coversHeld = 0
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

    /// Covers kept, ever, for this whole library.
    ///
    /// A thousand 480pt JPEGs at roughly 40KB each is about 40MB — the size of
    /// a short video, in a store that mirrors to CloudKit. The captions have no
    /// such cap because text is a rounding error beside this; pixels are not,
    /// and a cap chosen now beats one discovered by somebody's iCloud filling
    /// up. Newest first, so what it keeps is what a person is likeliest to be
    /// looking for.
    static let coverCap = 1_000
    private static let coverLedgerKey = "instagram.covers.attempts"
    /// How many covers are stored, kept as a counter rather than measured off
    /// the corpus. Counting for real means reading `previewImageData` on every
    /// row of a room that can hold thousands — and that column is deliberately
    /// absent from `FeedScreen.lightColumns`, so the measurement would fault
    /// the entire library to answer a question about a cap.
    private static let coverCountKey = "instagram.covers.stored"

    /// Meta's own two picture CDNs — where `og:image` points, and the only
    /// hosts a cover is ever fetched from.
    ///
    /// Matched on the LABEL BOUNDARY, never `contains`: the URL is a string out
    /// of a page, so `cdninstagram.com.attacker.example` must not match. Same
    /// rule, same reason, as `OEmbed.endpoints` and `postURL` below.
    private static let coverHosts = ["cdninstagram.com", "fbcdn.net"]

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
        var covers = coverAttempts()
        report.coversHeld = coversStored()

        let due = candidates(context: context, ledger: ledger)
        report.considered = due.count
        // Nothing left to caption is where the COVER backfill runs (2026-08-18,
        // prd §395). Sequenced rather than interleaved so a fresh import spends
        // its first passes on words — text is what retrieval needs, and a row
        // with a picture and no words is findable by nothing. It also means a
        // steady-state library never does both in one foreground.
        guard !due.isEmpty else {
            return await healCovers(context: context, report: report,
                                    covers: covers, trace: trace)
        }

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
                save(covers, key: coverLedgerKey)
                return report
            case .permanentlyGone:
                trace?("gone \(url.path()) — deleted or private, not asking again")
                report.failed += 1
                consecutiveFailures += 1
                bump(&ledger, ref, to: maxAttempts)
                // RECORD it, don't just stop asking (2026-08-05, prd §309).
                // The ledger above is a UserDefaults counter whose only job is
                // to end the retries — so the FACT that a saved post no longer
                // exists lived nowhere a person could reach, and this is the
                // one read no service can make about their own corpus: your
                // library remembers something Instagram has forgotten. A tag,
                // so it is filterable and searchable the day it lands and needs
                // no CloudKit deploy — the same shape X uses.
                if !thing.tags.contains("Gone") {
                    thing.tags.append("Gone")
                    context.saveHonestly()
                }
            case .unreachable:
                trace?("unreachable \(url.path()) — attempt \((ledger[ref] ?? 0) + 1)/\(maxAttempts)")
                report.failed += 1
                consecutiveFailures += 1
                bump(&ledger, ref)
            case .found(let caption, let retrieval, let image):
                consecutiveFailures = 0
                // The cover rides the SAME visit rather than a second fetch of
                // the same page — the page has already been read and the URL is
                // in hand. `healCovers` below exists only for rows a build
                // before this one already captioned.
                if coversStored() < coverCap, (covers[ref] ?? 0) < maxAttempts {
                    switch await store(cover: image, on: thing, context: context) {
                    case .stored:
                        trace?("cover \(url.path())")
                        report.covered += 1
                        bump(&covers, ref, to: maxAttempts)
                    case .missing:
                        bump(&covers, ref, to: maxAttempts)
                    case .retry:
                        bump(&covers, ref)
                    }
                }
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
        save(covers, key: coverLedgerKey)
        report.coversHeld = coversStored()
        return report
    }

    // MARK: - Covers for rows an earlier build already captioned

    /// The backfill half of the cover pass.
    ///
    /// It exists because the cover is otherwise taken during the caption visit,
    /// and a library captioned by a build before 2026-08-18 has no visits left
    /// to make: `enrichedText != nil` is precisely what drops a row out of
    /// `candidates`. Without this the feature would have reached only imports
    /// made after it shipped — the §313 `termsEpoch` problem, in a room where
    /// everything landed on one afternoon.
    ///
    /// It costs a second read of a page already read once, which is why it runs
    /// only when there is nothing left to caption and why every row it touches
    /// is marked in the ledger whether it succeeded or not. Bounded by the same
    /// `perPass`, `pace` and `coverCap` as everything else here.
    ///
    /// Takes and returns its state by VALUE rather than `inout`. Forwarding an
    /// `inout` parameter into another `async` call is a shape worth not having
    /// in a file this size — the ledger is a small dictionary and the report is
    /// six integers, so copying them costs nothing and removes the question.
    @MainActor
    private static func healCovers(context: ModelContext, report: Report,
                                   covers: [String: Int],
                                   trace: ((String) -> Void)?) async -> Report {
        var report = report
        var covers = covers
        guard coversStored() < coverCap else {
            trace?("covers: \(coverCap) held — the cap, not a failure")
            return report
        }
        let due = coverCandidates(context: context, ledger: covers)
        guard !due.isEmpty else { return report }
        var consecutiveFailures = 0
        for thing in due.prefix(perPass) {
            guard thing.isLive, coversStored() < coverCap else { break }
            let ref = thing.sourceRef ?? ""
            guard let url = postURL(thing) else {
                bump(&covers, ref, to: maxAttempts)
                continue
            }
            switch await fetch(url) {
            case .rateLimited:
                trace?("covers: RATE LIMITED at \(url.path()) — stopping this pass")
                report.backedOff = true
                break
            case .found(_, _, let image):
                consecutiveFailures = 0
                switch await store(cover: image, on: thing, context: context) {
                case .stored:
                    trace?("cover \(url.path())")
                    report.covered += 1
                    bump(&covers, ref, to: maxAttempts)
                case .missing:
                    // A page that answered with no usable picture will not grow
                    // one. Marked so the walk moves on rather than re-reading
                    // the same page every foreground for the rest of time.
                    trace?("covers: no picture on \(url.path())")
                    bump(&covers, ref, to: maxAttempts)
                case .retry:
                    trace?("covers: picture unreachable on \(url.path())")
                    bump(&covers, ref)
                }
            case .permanentlyGone:
                trace?("covers: gone \(url.path())")
                bump(&covers, ref, to: maxAttempts)
                consecutiveFailures += 1
            case .unreachable:
                trace?("covers: unreachable \(url.path())")
                bump(&covers, ref)
                consecutiveFailures += 1
            }
            if report.backedOff { break }
            if consecutiveFailures >= backOffAfter {
                trace?("covers: backing off — \(backOffAfter) rows failed in a row")
                report.backedOff = true
                break
            }
            try? await Task.sleep(for: pace)
        }
        save(covers, key: coverLedgerKey)
        report.coversHeld = coversStored()
        return report
    }

    /// Saves and likes this build has never asked a cover for.
    ///
    /// The LEDGER is the cursor here, where the caption pass uses
    /// `enrichedText == nil` — and it has to be: the honest test would be
    /// "carries no `previewImageData`", and that column faults per row on a
    /// library of thousands (see `coverCountKey`). A ledger entry answers the
    /// same question out of `UserDefaults`, and its worst failure is asking
    /// once more for a picture we already hold.
    @MainActor
    private static func coverCandidates(context: ModelContext,
                                        ledger: [String: Int]) -> [Thing] {
        IngestSupport.thingsByRef(context, source: InstagramImport.source)
            .filter { ref, thing in
                thing.isLive
                    && thing.kind == .link
                    && !thing.tags.contains("Gone")
                    && (ref.hasPrefix("instagram:saved:") || ref.hasPrefix("instagram:liked:"))
                    && (ledger[ref] ?? 0) < maxAttempts
            }
            .values
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// What one cover attempt did — three outcomes rather than a Bool, because
    /// the ledger treats them differently and a caller handed `false` cannot
    /// tell "this page has no picture, stop asking" from "the network blinked,
    /// ask again". Bookkeeping stays with the caller so nothing is passed
    /// `inout` into an `async` call.
    private enum CoverResult {
        case stored     // pixels landed
        case missing    // no picture, or one that will never decode — stop asking
        case retry      // a blip; worth asking again later
    }

    /// Downloads one cover, downscales it, and keeps the bytes.
    ///
    /// The signed URL is used and dropped — never written to
    /// `previewImageURL`, which is the whole of the §245 refusal this pass
    /// keeps.
    @MainActor
    private static func store(cover image: URL?, on thing: Thing,
                              context: ModelContext) async -> CoverResult {
        guard let image, thing.isLive else { return .missing }
        guard let data = await fetchCover(image) else { return .retry }
        guard let thumb = await ImportMedia.thumbnail(data: data) else {
            // The bytes arrived and would not decode. Not worth another try.
            return .missing
        }
        // Re-checked AFTER the two suspensions above: a heal or a CloudKit
        // delete can tombstone this row while we are on the network, and
        // writing to a tombstoned model traps inside SwiftData.
        guard thing.isLive else { return .missing }
        thing.previewImageData = thumb
        setCoversStored(coversStored() + 1)
        context.saveHonestly()
        return .stored
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
        case found(caption: String, retrieval: String, image: URL?)
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
        return .found(caption: caption, retrieval: description ?? caption,
                      image: coverURL(meta(html, "og:image")))
    }

    /// The picture on that page, when the page names one AND it is on a host we
    /// are willing to open.
    ///
    /// `og:image` is a string somebody else's server wrote. Following it because
    /// it appeared in a page we asked for is exactly the leak `postURL` refuses
    /// one function down — so the host is checked on the label boundary against
    /// Meta's own CDNs and nothing else is fetched.
    static func coverURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(),
              coverHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return nil }
        return url
    }

    /// The cover's bytes, capped. `maxCover` is a refusal, not a budget: a
    /// `Content-Length` is a claim, so the read is truncated on what actually
    /// arrives rather than on what the header promised.
    private static let maxCover = 4_194_304

    private static func fetchCover(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        // The receipts ledger — a reach nobody declared is the build-214 failure
        // this app's own privacy screen exists to make impossible.
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty
        else { return nil }
        return data.count > maxCover ? nil : data
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
        // The words the ROOM draws (2026-08-18, prd §395). `enrichedText` is
        // retrieval-only by the 2026-07-15 ruling, so until now a caption this
        // pass fetched was searchable and on no screen — the §313 X finding, in
        // the room beside it. `postText` is the field the post card reads; like
        // `content` it is deliberately outside `FeedScreen.lightColumns`, so it
        // faults on a VISIBLE row's appearance and never once per corpus row —
        // which is exactly the trade that pre-fetch list documents, and why the
        // room head next door reads none of it.
        //
        // The FACE, not the description: `og:title` reads "Author on Instagram:
        // "caption"" and is what the title already carries, while
        // `og:description` prefixes the counts ("6,800 likes, 29 comments - …").
        // A card is the post, so it shows the post.
        // The UNCLAMPED caption, deliberately — `face` above is
        // `titleLine`'s 80 characters, which is the row's fallback and exactly
        // what this field exists to beat.
        if caption != thing.postText, !caption.isEmpty {
            thing.postText = caption
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

    private static func coverAttempts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: coverLedgerKey) as? [String: Int] ?? [:]
    }

    static func coversStored() -> Int {
        UserDefaults.standard.integer(forKey: coverCountKey)
    }

    private static func setCoversStored(_ value: Int) {
        UserDefaults.standard.set(value, forKey: coverCountKey)
    }

    private static func bump(_ ledger: inout [String: Int], _ ref: String, to value: Int? = nil) {
        guard !ref.isEmpty else { return }
        ledger[ref] = value ?? ((ledger[ref] ?? 0) + 1)
    }

    /// Bounded so a decade-deep library can't grow this without limit. Trimmed
    /// by dropping the rows we've tried LEAST — a ref at `maxAttempts` is the
    /// one worth remembering, since forgetting it is what would put a dead
    /// post back in the queue forever.
    private static func save(_ ledger: [String: Int], key: String = ledgerKey) {
        var out = ledger
        if out.count > ledgerCap {
            out = Dictionary(uniqueKeysWithValues:
                out.sorted { $0.value > $1.value }.prefix(ledgerCap).map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(out, forKey: key)
    }

    /// DEBUG only — lets `-instagramCaptions` re-walk rows a previous run
    /// gave up on, so the pass can be exercised twice in a session.
    static func forgetFailures() {
        UserDefaults.standard.removeObject(forKey: ledgerKey)
        UserDefaults.standard.removeObject(forKey: coverLedgerKey)
    }
}
