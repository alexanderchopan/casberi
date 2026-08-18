import Foundation

/// The Radicle wire, as measured (prd §400, 2026-08-18) — every decision this
/// bridge makes about what a seed just said, with no SwiftData, no networking
/// and no UIKit in it, so `scripts/radicle-selftest.sh` can compile the whole
/// file unmodified. That is the only proof these numbers are right: nothing on
/// this host can open a patch, merge one, or close an issue, so the harness
/// stands in for a live account the way `StripeRoom`'s and `PeerRoom`'s do.
///
/// **Everything here was measured against `rosa.radicle.network` and
/// `iris.radicle.network` on 2026-08-18**, both serving `apiVersion 6.1.0`
/// (`radicle-httpd` 0.25.0). The entry that proposed this bridge was written
/// from Radicle's own shipped client instead, and four of its six stated quirks
/// turned out to be wrong or stale — see §400. Re-measure before "fixing"
/// anything below.
enum RadicleWire {

    /// The payload key that carries a repo's project data. **Named, never
    /// "the first payload"** — 4 of 11 measured repos carry a second payload
    /// (`xyz.radicle.crefs`), and dictionary order is not a thing to bet a
    /// room on.
    static let projectPayload = "xyz.radicle.project"

    // MARK: - Time

    /// Radicle timestamps are epoch **SECONDS** (measured: a patch revision at
    /// `1783931502` is 2026-07-13 read as seconds and 1970-01-21 read as
    /// milliseconds). Read wrongly every row lands in 1970 — and a bridge that
    /// then fell back to `.now` would date a decade of patches "today".
    ///
    /// The plausibility window is the X-snowflake rule (§280): a value outside
    /// it is REFUSED rather than clamped, because a confident wrong date is
    /// worse than no row. Radicle's first commit predates 2018 by nothing that
    /// matters, and a timestamp in the future is a broken clock, not news.
    static func date(epochSeconds raw: Any?) -> Date? {
        let seconds: Double
        switch raw {
        case let n as Double: seconds = n
        case let n as Int:    seconds = Double(n)
        case let s as String: guard let n = Double(s) else { return nil }; seconds = n
        default: return nil
        }
        // 2015-01-01 … now + 2 days. The upper bound has slack for a seed
        // whose clock runs ahead; the lower one is well below Radicle itself.
        guard seconds >= 1_420_070_400,
              seconds <= Date().timeIntervalSince1970 + 172_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Repo

    /// What one `/repos/:rid` row says, once the nesting is unwrapped.
    ///
    /// **The nesting is the whole point.** §400's first draft put `name`,
    /// `description` and `meta` at the top level; measured, they live under
    /// `payloads["xyz.radicle.project"]` — `.data` for the names, `.meta` for
    /// `head` and the six counts. A bridge written to the flat shape reads nil
    /// for every field and renders an empty room **with no error**, which is
    /// this project's silent-wrong-answer class exactly.
    struct Repo: Equatable {
        let rid: String
        let name: String
        let description: String?
        let snapshot: Snapshot
        /// The people who can sign for this repo. Their `alias` is the only
        /// human-readable name Radicle publishes for a DID.
        let delegates: [Party]
    }

    /// A person, as every Radicle object names one: a DID plus an optional
    /// alias. **The alias is never invented** — a DID with no alias stays a
    /// DID, because a made-up handle on a row that says who wrote something is
    /// the §83 fake status in the one place it would be believed.
    struct Party: Equatable {
        let did: String
        let alias: String?

        /// What a row calls this person. The alias when there is one, else the
        /// DID's own tail, which at least differs between two people.
        var display: String {
            if let alias, !alias.isEmpty { return alias }
            return String(did.suffix(8))
        }
    }

    /// The six counts plus the head commit — everything the cheap sweep needs.
    ///
    /// **This is the whole change-detection mechanism.** A patch and an issue
    /// carry no timestamp at the top level (§400 quirk 2), so there is nothing
    /// to sort a "what's new since" query by; instead one `GET /repos/:rid`
    /// answers all six counts, and a diff against the stored snapshot decides
    /// whether to walk patches or issues **at all**. That bounds a quiet pass
    /// at one request per watched repo — the `HyperliquidDeFi.sync`
    /// snapshot-diff shape.
    struct Snapshot: Codable, Equatable {
        var head: String?
        var patchesOpen = 0
        var patchesDraft = 0
        var patchesArchived = 0
        var patchesMerged = 0
        var issuesOpen = 0
        var issuesClosed = 0

        /// Is it worth spending a request on this repo's patches?
        ///
        /// Deliberately `!=` and not `>`: a patch can be archived or reopened,
        /// which moves a count DOWN, and a bridge that only ever looked when a
        /// number grew would go permanently blind to a repo that churns. The
        /// walk is bounded anyway, so the cost of an extra look is one request
        /// and the cost of missing one is a room that silently stops.
        func patchesChanged(from old: Snapshot) -> Bool {
            patchesOpen != old.patchesOpen
                || patchesDraft != old.patchesDraft
                || patchesArchived != old.patchesArchived
                || patchesMerged != old.patchesMerged
        }

        func issuesChanged(from old: Snapshot) -> Bool {
            issuesOpen != old.issuesOpen || issuesClosed != old.issuesClosed
        }

        /// True when an issue was CLOSED between these two observations. This
        /// is the only evidence a close ever leaves — see `Issue.closedDate`.
        func sawIssueClose(from old: Snapshot) -> Bool {
            issuesClosed > old.issuesClosed
        }
    }

    // MARK: - What is still open

    /// One unresolved patch or issue, kept so the room can say what is STUCK
    /// (prd §401).
    ///
    /// **The date here is exact, and that is the whole reason this type
    /// exists.** §400 refused a room head because `/activity` is a trailing
    /// 365-day window and a span strip fed from it would claim a span it
    /// cannot see. This is the head it pointed at instead: `opened` is
    /// `revisions[0].timestamp` for a patch and `discussion[0].timestamp` for
    /// an issue — recovered from the record, not observed by us — so "open
    /// since March" is a fact rather than a note about when we first looked.
    /// Contrast `ASCStanding.observed`, which has to say "we watched this
    /// change" precisely because Apple publishes no such date.
    struct OpenItem: Codable, Equatable {
        enum Kind: String, Codable, Equatable { case patch, issue }
        let kind: Kind
        let id: String
        let title: String
        let opened: Date
        /// A patch still being drafted. Drawn apart from a proposed one,
        /// because a draft is not waiting on anybody — it is not stuck, it is
        /// unfinished, and ranking the two together would put your own
        /// scratch work at the top of a card about what needs attention.
        let isDraft: Bool
    }

    /// The unresolved patches and issues in one fetched page.
    ///
    /// Costs NOTHING extra: the sweep already fetches these lists whenever the
    /// snapshot diff says a count moved, and until now it read them only to
    /// decide what to land and then threw the rest away. An archived or merged
    /// patch is not here by construction — it is resolved, and the card is
    /// about what is not.
    static func openItems(patches: [Patch], issues: [Issue]) -> [OpenItem] {
        var out: [OpenItem] = []
        for p in patches {
            // `open` and `draft` only. A patch that is merged or archived is
            // finished; reading "not merged" as "open" would keep every
            // archived patch on this card forever, which is the silent-wrong
            // answer a status field exists to prevent.
            guard p.status == "open" || p.status == "draft", let opened = p.opened
            else { continue }
            out.append(OpenItem(kind: .patch, id: p.id, title: p.title,
                                opened: opened, isDraft: p.status == "draft"))
        }
        for i in issues {
            guard i.status == "open", let opened = i.opened else { continue }
            out.append(OpenItem(kind: .issue, id: i.id, title: i.title,
                                opened: opened, isDraft: false))
        }
        return out
    }

    /// Reads one entry of `/repos` or the whole of `/repos/:rid`.
    static func repo(_ root: [String: Any], rid fallbackRID: String? = nil) -> Repo? {
        guard let payloads = root["payloads"] as? [String: Any],
              let project = payloads[projectPayload] as? [String: Any]
        else { return nil }
        let data = project["data"] as? [String: Any] ?? [:]
        guard let rid = (root["rid"] as? String) ?? fallbackRID, !rid.isEmpty,
              let name = (data["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        let meta = project["meta"] as? [String: Any] ?? [:]
        let patches = meta["patches"] as? [String: Any] ?? [:]
        let issues = meta["issues"] as? [String: Any] ?? [:]
        func count(_ box: [String: Any], _ key: String) -> Int { box[key] as? Int ?? 0 }
        let description = (data["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Repo(
            rid: rid,
            name: name,
            description: (description?.isEmpty == false) ? description : nil,
            snapshot: Snapshot(
                head: meta["head"] as? String,
                patchesOpen: count(patches, "open"),
                patchesDraft: count(patches, "draft"),
                patchesArchived: count(patches, "archived"),
                patchesMerged: count(patches, "merged"),
                issuesOpen: count(issues, "open"),
                issuesClosed: count(issues, "closed")),
            delegates: (root["delegates"] as? [[String: Any]] ?? []).compactMap(party))
    }

    /// `{id, alias}` — the shape every author, delegate and merger wears.
    static func party(_ raw: Any?) -> Party? {
        guard let box = raw as? [String: Any],
              let did = (box["id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !did.isEmpty
        else { return nil }
        let alias = (box["alias"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Party(did: did, alias: (alias?.isEmpty == false) ? alias : nil)
    }

    // MARK: - Patch

    struct Patch: Equatable {
        let id: String
        let title: String
        let author: Party
        /// `open` / `draft` / `archived` / `merged`.
        let status: String
        /// `revisions[0].timestamp` — when this patch was proposed. Exact,
        /// recovered from the record rather than estimated (§400 quirk 2).
        let opened: Date?
        /// `merges[0].timestamp` — when it actually landed, and who landed it.
        let merged: Date?
        let mergedBy: Party?

        var isMerged: Bool { status == "merged" }
    }

    static func patch(_ root: [String: Any]) -> Patch? {
        guard let id = (root["id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let title = (root["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let author = party(root["author"])
        else { return nil }
        let state = root["state"] as? [String: Any] ?? [:]
        let status = (state["status"] as? String)?.lowercased() ?? "open"
        // The FIRST revision is the proposal. Later revisions are edits, and
        // dating a patch by its newest revision would move an old patch to
        // today every time somebody pushed a fixup.
        let revisions = root["revisions"] as? [[String: Any]] ?? []
        let opened = date(epochSeconds: revisions.first?["timestamp"])
        // A merge names its own author and moment. Several are possible when
        // more than one delegate merged; the EARLIEST is when it landed.
        let merges = (root["merges"] as? [[String: Any]] ?? [])
            .compactMap { box -> (Date, Party?)? in
                guard let when = date(epochSeconds: box["timestamp"]) else { return nil }
                return (when, party(box["author"]))
            }
            .sorted { $0.0 < $1.0 }
        return Patch(id: id, title: title, author: author, status: status,
                     opened: opened, merged: merges.first?.0, mergedBy: merges.first?.1)
    }

    // MARK: - Issue

    struct Issue: Equatable {
        let id: String
        let title: String
        let author: Party
        /// `open` / `closed`.
        let status: String
        /// `discussion[0].timestamp` — in Radicle's COB model the root comment
        /// IS the issue body, so the first comment's moment is when the issue
        /// was opened. Exact, not estimated.
        let opened: Date?

        var isClosed: Bool { status == "closed" }

        /// **There is none, and that is a measured fact, not an omission.**
        /// A closed issue carries `state: {status: "closed", reason: "solved"}`
        /// and no timestamp anywhere in the object; the discussion timestamps
        /// are comment times, which are not when it closed.
        ///
        /// So a close is dated by the only honest thing available — the moment
        /// this device SAW the closed count rise (`Snapshot.sawIssueClose`),
        /// which is true to within one refresh. That is why a close never
        /// backfills on first sight: an issue already closed when you started
        /// watching has a date nobody can recover, and stamping it `.now`
        /// would put years-old work in today's feed. Same rule as
        /// `ASCStanding.observed` and `PeerRoom`'s refusal to date a room from
        /// a fall-through.
        var closedDate: Date? { nil }
    }

    static func issue(_ root: [String: Any]) -> Issue? {
        guard let id = (root["id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let title = (root["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let author = party(root["author"])
        else { return nil }
        let state = root["state"] as? [String: Any] ?? [:]
        let status = (state["status"] as? String)?.lowercased() ?? "open"
        let discussion = root["discussion"] as? [[String: Any]] ?? []
        return Issue(id: id, title: title, author: author, status: status,
                     opened: date(epochSeconds: discussion.first?["timestamp"]))
    }

    // MARK: - Identity

    /// A Radicle repo id. Accepts what a person actually has: the bare id, an
    /// `app.radicle.xyz` / `radicle.network` explorer URL, or a percent-encoded
    /// `rad%3A` out of a copied address bar.
    ///
    /// Returns nil rather than guessing — an id that isn't one would otherwise
    /// become a watch entry that 404s forever with nothing on screen to say why.
    static func normalizeRID(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "rad%3A", with: "rad:")
            .replacingOccurrences(of: "rad%3a", with: "rad:")
        // Pull the id out of an explorer URL by finding the component that
        // starts with `rad:`, rather than counting path positions — the
        // explorer's own paths differ between a repo, a patch and an issue.
        //
        // **Only a URL is mined this way, and the distinction is load-bearing.**
        // Extracting from ANY slashed string means `rad:<valid-prefix>/../etc`
        // silently yields the valid prefix — a DIFFERENT repo from the one the
        // person named, watched forever with nothing on screen to say so. The
        // harness caught exactly that. A string that is not a URL must be a
        // clean id in its entirety or nothing at all.
        if s.contains("://") {
            let parts = s.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
            guard let hit = parts.first(where: { $0.hasPrefix("rad:") }) else { return nil }
            s = String(hit)
        }
        guard s.hasPrefix("rad:") else { return nil }
        let body = s.dropFirst(4)
        // Radicle ids are multibase base58btc — letters and digits only, and
        // long enough that a stray word can't pass. Measured ids run 28-32.
        guard body.count >= 20, body.count <= 64,
              body.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        return "rad:" + body
    }

    /// A seed host, as typed. Strips a scheme and any path so the person can
    /// paste a URL, and refuses anything that isn't a plain host — this string
    /// is interpolated into every request this bridge makes.
    static func normalizeSeed(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        s = s.split(separator: "/").first.map(String.init) ?? s
        guard !s.isEmpty, s.count <= 253,
              !s.hasPrefix("."), !s.hasSuffix("."), s.contains("."),
              s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" })
        else { return nil }
        return s
    }

    // MARK: - Links

    /// The public explorer's address for a repo, or something inside one.
    ///
    /// MEASURED 2026-08-18: `radicle.network/nodes/<seed>/<rid>` answers 307 to
    /// the same URL with the RID percent-encoded, then 200. So the encoding is
    /// written here and the redirect is skipped — a permalink that bounces is
    /// a permalink that fails the moment the redirect stops being served.
    static func permalink(seed: String, rid: String, path: String? = nil) -> String {
        let encoded = rid.replacingOccurrences(of: ":", with: "%3A")
        var url = "https://radicle.network/nodes/\(seed)/\(encoded)"
        if let path, !path.isEmpty { url += "/" + path }
        return url
    }

    // MARK: - Titles

    /// What a landed row says happened, in the shape every event bridge here
    /// uses: the repo leads, because a patch title is a fragment written
    /// against a context you had at the time (the Trello board rule, §303's
    /// clamp reasoning). The verb is a word, never a count.
    static func title(repo: String, verb: String, subject: String) -> String {
        "\(repo) · \(verb) · \(subject)"
    }
}
