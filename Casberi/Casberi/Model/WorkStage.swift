import Foundation

/// The receipt behind a Work row (2026-08-12, user: "less like a database
/// field, more like a receipt").
///
/// **The problem this solves.** Eighteen Work seats land ~45 row shapes, and
/// exactly two of them (GitHub releases, PostHog metrics) had any sheet
/// anatomy of their own. Every other one fell through `walletStage == nil` to
/// the generic path — title, a link-preview card, and a two-row label/value
/// grid reading "Site: vercel.com" and "From: in your things". That grid is
/// the database field the user is describing, and on a Work row it is very
/// nearly the whole sheet.
///
/// **Why the material was already there.** Each bridge composes a sentence
/// and then joins it into ONE string, because `Thing.title` is one slot:
/// `"Build failed · casberi/web · fix: guard the null case"`. That join is
/// also why §303 ruled the outcome must LEAD — `titleLine` clamps at 80 and
/// the tail is what the clamp eats. So the parts exist; they were flattened
/// on the way in. This type puts them back on separate rungs, the same move
/// §302 made when the wallet transfer stage became a ledger.
///
/// **THE CENTRAL RULE: the outcome is read from a STABLE signal, never from
/// the title.** Every `leadClause` in this codebase is `String(localized:)`,
/// so it is written in whatever language the device was in WHEN THE ROW
/// LANDED. prd §340 already ruled on exactly this for Cursor: parse the title
/// back and "change the language and every past failure silently reads as a
/// success", which is the §83 fake status in the most expensive possible
/// place. So `tone` and `statusWord` are derived from things that cannot
/// drift — the English facet tags the bridges already land, the raw state
/// encoded inside a `sourceRef` (`asc:version:<id>:REJECTED`), and `mark`.
///
/// The localized clause is used for ONE cosmetic job, described at
/// `subject(strippingClause:)`: removing a duplicate word from the headline
/// when it happens to match the current language. It fails safe — a
/// mismatched prefix leaves the title whole — and it can never change what
/// this type says HAPPENED.
///
/// Foundation-only by design (no SwiftUI, no SwiftData, no `Thing`), so
/// `scripts/work-stage-selftest.sh` can compile it WHOLE and unmodified —
/// the `ASCShape`/`StripeShape`/`CursorAgentStatus` precedent. That matters
/// more here than usual: a mis-derived receipt renders as a perfectly
/// good-looking sheet, so a build, a screen sweep and every probe pass while
/// the sheet quietly states the wrong outcome.
enum WorkStage {

    // MARK: - Tone

    /// The register a Work outcome speaks in. Four, not five: this is state
    /// colour (the §302 "a gain wears green" ruling), so each one has to earn
    /// a distinct meaning a person can act on.
    enum Tone: String {
        /// It broke, or it went against you. `DS.destructive`.
        case failed
        /// It is on somebody else's desk, or it stopped. `DS.attention`.
        case waiting
        /// It finished, and finishing was the good outcome. `DS.confirm`.
        case landed
        /// Something happened and it carries no verdict. Plain text colour —
        /// deliberately NOT a fifth hue, because a row with nothing to say
        /// about how it went should not be wearing a colour that implies it
        /// does.
        case neutral
    }

    /// What the hero rung is made of, which decides how it is set.
    ///
    /// The wallet's stage has one answer (a signed amount, `price40`) because
    /// a transfer's hero IS a number. A Work hero is usually a sentence, so
    /// the default is words at a reading weight; the exceptions each have a
    /// reason that isn't taste.
    enum Face: String {
        /// A commit subject, an issue title, a card name. The default.
        case words
        /// An error message IS code (`TypeError: undefined is not a
        /// function`), and setting it in the prose face makes it read as
        /// something a person wrote.
        case code
        /// Money moving — the module doctrine's own standing exception, and
        /// the one Work face that inherits the wallet's hero rung.
        case money
        /// A star rating: the verdict itself, already five glyphs.
        case stars
    }

    // MARK: - The reading

    /// One row's receipt. `nil` fields are "we have nothing true to say",
    /// never a placeholder — a slab row that invents a project is the fake
    /// status this codebase bans, and it renders indistinguishably from a
    /// correct one.
    struct Reading: Equatable {
        /// The outcome as a word, in the app's own voice ("Build failed").
        /// Nil when the row carries no verdict at all.
        var statusWord: String?
        var tone: Tone
        /// The headline — what you actually read.
        var subject: String
        /// The project/repo/service this belongs to, and ONLY when a stored
        /// FIELD carries it. Never sliced out of the title: a project name
        /// guessed from a separator lands in a labelled slab row, where being
        /// wrong is indistinguishable from being right.
        var project: String?
        var face: Face
    }

    // MARK: - Entry

    /// Everything the reading is derived from. A plain value rather than a
    /// `Thing` so the whole type stays Foundation-only and the harness can
    /// compile it as shipped.
    struct Row {
        var source: String
        var sourceRef: String?
        var title: String
        var tags: [String]
        /// `Thing.mark`'s raw value — "todo" / "doing" / "done" / "none".
        /// Passed as a string rather than the enum for the same
        /// Foundation-only reason.
        var mark: String
        /// Whatever stored field carries the owning project. Today that is
        /// `authorHandle`, which Cursor has meant "org/repo" on since it
        /// shipped (§303).
        var projectField: String?
        var hasPrice: Bool

        init(source: String, sourceRef: String? = nil, title: String,
             tags: [String] = [], mark: String = "none",
             projectField: String? = nil, hasPrice: Bool = false) {
            self.source = source
            self.sourceRef = sourceRef
            self.title = title
            self.tags = tags
            self.mark = mark
            self.projectField = projectField
            self.hasPrice = hasPrice
        }
    }

    /// The reading, or nil when this row is not a Work row we can speak about.
    ///
    /// Nil is a real answer and the common one for a seat we have no shape
    /// for — the sheet then renders exactly as it does today, which is why
    /// this can land without touching the seats it doesn't cover.
    static func reading(_ row: Row) -> Reading? {
        guard let (word, tone) = outcome(row) else { return nil }
        return Reading(statusWord: word,
                       tone: tone,
                       subject: subject(row, strippingClause: word),
                       project: project(row),
                       face: face(row))
    }

    // MARK: - Outcome  (stable signals only)

    /// The verdict, from signals that cannot drift with the device language.
    ///
    /// Keyed on (source, tag) rather than tag alone, and that is load-bearing:
    /// "Release" means a shipped package on npm (landed), a new model on
    /// Hugging Face (neutral) and a version row on App Store Connect (whose
    /// verdict lives in its ref instead). A tag-only table would give all
    /// three the same colour, and two of them would be wrong.
    static func outcome(_ row: Row) -> (String, Tone)? {
        let tags = Set(row.tags)
        switch row.source {

        // ── Outcome archetype: it finished, and how it finished is the news ──
        case "Vercel":
            if tags.contains("Build failure") { return (word("Build failed"), .failed) }
            if tags.contains("Deploy")        { return (word("Deployed"), .landed) }
            return nil

        case "Cursor":
            // The three facet tags §340 landed precisely so this read would
            // not have to touch the title. A run with none of them finished.
            if tags.contains("Failed")    { return (word("Failed"), .failed) }
            if tags.contains("Expired")   { return (word("Expired"), .waiting) }
            if tags.contains("Cancelled") { return (word("Cancelled"), .waiting) }
            if tags.contains("Agent run") { return (word("Finished"), .landed) }
            return nil

        case "npm", "PyPI":
            if tags.contains("Deprecated") { return (word("Deprecated"), .failed) }
            if tags.contains("Release")    { return (word("Released"), .landed) }
            return nil

        // ── Alarm archetype ──
        case "Sentry":
            if tags.contains("Regression") { return (word("Regressed"), .failed) }
            if tags.contains("Issue")      { return (word("New error"), .waiting) }
            return nil

        case "PagerDuty":
            // "Resolved after 2 hours" is computed at ingest and already leads
            // the stored title, so the DURATION is recovered by the clause
            // strip below rather than recomputed here — recomputing it would
            // need the triggering row, a second read, for a string we already
            // have.
            if tags.contains("Resolved") { return (word("Resolved"), .landed) }
            if tags.contains("Incident") { return (word("Triggered"), .failed) }
            return nil

        // ── Money archetype ──
        case "Stripe":
            return stripeOutcome(tags)

        // ── Verdict archetype ──
        case "App Store Connect":
            return ascOutcome(row)

        // ── Ticket archetype: the outcome is the state you left it in ──
        case "Linear", "Jira", "Trello", "GitLab", "GitHub":
            return markOutcome(row.mark)

        // ── Analytics ──
        case "PostHog":
            if tags.contains("Milestone") { return (word("Milestone"), .landed) }
            if tags.contains("Silence")   { return (word("Stopped firing"), .waiting) }
            return nil

        default:
            return nil
        }
    }

    /// Stripe's shape tag says WHICH kind of money event this is; for the two
    /// that have a direction, the direction is landed as its own tag by this
    /// pass (the §340 facet-tag precedent) so it survives a language change.
    private static func stripeOutcome(_ tags: Set<String>) -> (String, Tone)? {
        if tags.contains("Dispute") {
            if tags.contains("Won")  { return (word("Dispute won"), .landed) }
            if tags.contains("Lost") { return (word("Dispute lost"), .failed) }
            // An open dispute is the flagship: money challenged, clock running.
            return (word("Dispute opened"), .failed)
        }
        if tags.contains("Payout") {
            return tags.contains("Failed")
                ? (word("Payout failed"), .failed)
                : (word("Paid out"), .landed)
        }
        if tags.contains("Dunning") {
            return tags.contains("Recovered")
                ? (word("Payment recovered"), .landed)
                : (word("Payment failed"), .failed)
        }
        if tags.contains("Churn")   { return (word("Subscription canceled"), .waiting) }
        if tags.contains("Silence") { return (word("Payments stopped"), .waiting) }
        if tags.contains("Runway")  { return (word("Runway low"), .waiting) }
        return nil
    }

    /// App Store Connect encodes the RAW state in its own ref
    /// (`asc:version:<id>:REJECTED`), which is the strongest stable signal any
    /// Work seat carries — Apple's own constant, never localized, already
    /// stored. Builds do the same (`asc:build:<id>:VALID`).
    private static func ascOutcome(_ row: Row) -> (String, Tone)? {
        guard let ref = row.sourceRef else { return nil }
        if ref.hasPrefix("asc:version:"), let raw = ref.split(separator: ":").last {
            switch String(raw) {
            case "REJECTED":                     return (word("Rejected"), .failed)
            case "METADATA_REJECTED":            return (word("Metadata rejected"), .failed)
            case "INVALID_BINARY":               return (word("Invalid binary"), .failed)
            case "IN_REVIEW":                    return (word("In review"), .waiting)
            case "PENDING_CONTRACT":             return (word("Blocked — a contract needs signing"), .waiting)
            case "WAITING_FOR_EXPORT_COMPLIANCE":return (word("Waiting on export compliance"), .waiting)
            case "REMOVED_FROM_SALE":            return (word("Removed from sale"), .failed)
            case "ACCEPTED":                     return (word("Approved"), .landed)
            case "PENDING_DEVELOPER_RELEASE":    return (word("Approved — yours to release"), .landed)
            case "PENDING_APPLE_RELEASE":        return (word("Approved — Apple is releasing it"), .landed)
            case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION":
                                                 return (word("Live on the App Store"), .landed)
            default:                             return nil
            }
        }
        if ref.hasPrefix("asc:build:"), let raw = ref.split(separator: ":").last {
            switch String(raw) {
            case "VALID":   return (word("Ready to test"), .landed)
            case "FAILED":  return (word("Failed processing"), .failed)
            case "INVALID": return (word("Invalid build"), .failed)
            default:        return nil
            }
        }
        // A customer review's verdict is its rating, which already leads the
        // title as five glyphs — the stars ARE the status line, so there is no
        // word to add and adding one would say it twice.
        if ref.hasPrefix("asc:review:") { return (word("Review"), .neutral) }
        if ref.hasPrefix("asc:buildexpiry:") { return (word("Expiring"), .waiting) }
        return nil
    }

    /// A ticket's outcome is the state it is in. `mark` is a stored enum, so
    /// unlike every clause in this file it was never localized in the first
    /// place.
    private static func markOutcome(_ mark: String) -> (String, Tone)? {
        switch mark {
        case "todo":  return (word("Open"), .waiting)
        case "doing": return (word("In progress"), .waiting)
        case "done":  return (word("Done"), .landed)
        default:      return nil
        }
    }

    // MARK: - Subject

    /// The headline: the title, minus a leading clause it is already saying.
    ///
    /// **This is cosmetic and fails safe, and that is the whole reason it is
    /// allowed to touch the title at all.** The verdict has already been
    /// decided above from a stable signal. All this does is avoid printing
    /// the same word twice when the status line and the stored title agree —
    /// so a row that landed in another language simply keeps its title whole,
    /// which is mildly redundant and never wrong. Nothing downstream reads
    /// this to decide what happened.
    ///
    /// Matched against the CURRENT localization of the clause, prefix-only,
    /// and only when a separator follows it — `"Deprecated · left-pad"`
    /// strips, while a release genuinely titled `"Deprecated APIs in 3.0"`
    /// does not, because the word is the start of a sentence rather than a
    /// clause of its own.
    static func subject(_ row: Row, strippingClause clause: String?) -> String {
        var title = row.title.trimmingCharacters(in: .whitespaces)
        if let clause, !clause.isEmpty {
            // PagerDuty's clause carries a duration that this type never
            // recomputes ("Resolved after 2 hours"), so the match is on the
            // stored prefix up to the separator rather than on the bare word.
            title = dropLeadingSegment(title) { $0 == clause || $0.hasPrefix(clause + " ") }
        }
        // The project too, when a FIELD proved it (never a guess) and the
        // title is repeating it. Without this a PagerDuty subject reads
        // "casberi-api · API latency above 2s" while the slab below is
        // already headed "Service: casberi-api" — the stutter §302 removed
        // from the wallet's own spec table, arriving one seat over.
        if let project = project(row) {
            title = dropLeadingSegment(title) { $0 == project }
        }
        return title
    }

    /// Drop `title`'s first " · " segment when `matches` accepts it.
    ///
    /// Never strips a title down to nothing: a row whose whole title IS its
    /// clause (a Cloudflare expiry, a Stripe silence) keeps it, because a
    /// blank hero is worse than a repeated word.
    private static func dropLeadingSegment(_ title: String,
                                           matches: (String) -> Bool) -> String {
        guard let sep = title.range(of: " · ") else { return title }
        let head = String(title[title.startIndex..<sep.lowerBound])
        guard matches(head) else { return title }
        let rest = String(title[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? title : rest
    }

    /// The clause the strip actually removed, when it carried more than the
    /// status word does — PagerDuty's "Resolved after 2 hours" is the only
    /// shape that does today, and that duration is worth keeping.
    static func statusDetail(_ row: Row, clause: String?) -> String? {
        guard let clause, let sep = row.title.range(of: " · ") else { return nil }
        let head = String(row.title[row.title.startIndex..<sep.lowerBound])
        guard head.hasPrefix(clause + " ") else { return nil }
        return head
    }

    // MARK: - Project

    /// The owning project, from a stored field ONLY.
    ///
    /// Cursor has stamped `authorHandle` with `org/repo` since it shipped
    /// (§303 — "not a person"), and this pass stamps the same field on the
    /// three other seats that know their project at ingest. Everything else
    /// answers nil and draws no project row, which is the honest outcome: the
    /// value is sitting in the middle of a joined title, and slicing it out on
    /// a separator would put half an issue title in a row labelled "Project"
    /// whenever a title contained one.
    static func project(_ row: Row) -> String? {
        guard ["Cursor", "Vercel", "Sentry", "PagerDuty"].contains(row.source),
              let p = row.projectField?.trimmingCharacters(in: .whitespaces),
              !p.isEmpty
        else { return nil }
        return p
    }

    // MARK: - Face

    static func face(_ row: Row) -> Face {
        switch row.source {
        case "Stripe": return row.hasPrice ? .money : .words
        case "Sentry": return .code
        case "App Store Connect":
            return (row.sourceRef?.hasPrefix("asc:review:") ?? false) ? .stars : .words
        default:       return .words
        }
    }

    // MARK: - Chrome

    /// Tags that name the row's SHAPE rather than the person's own taxonomy.
    ///
    /// These are our editorial marks — the same strings `outcome` reads above
    /// — so a chip strip that showed them would be printing the status line
    /// back at you in a quieter font. A GitHub label, a Linear project or a
    /// Trello label is the person's own word and stays.
    static let shapeTags: Set<String> = [
        "Deploy", "Build failure", "Agent run", "Failed", "Expired", "Cancelled",
        "Release", "Deprecated", "Issue", "Regression", "Incident", "Resolved",
        "Dispute", "Payout", "Dunning", "Churn", "Silence", "Runway",
        "Won", "Lost", "Recovered",
        "Review", "Build", "Annotation", "Milestone", "Watchlist", "Paper", "PR",
    ]

    /// The person's own labels: what's left after the shape marks and the
    /// kind's own type tag come out. Empty means draw no strip at all, never
    /// an empty rail.
    static func labels(_ row: Row, typeTags: Set<String>) -> [String] {
        row.tags.filter { !shapeTags.contains($0) && !typeTags.contains($0) }
    }

    /// The word under the dial's first disc — WHERE you land, never "Open"
    /// (§302's Explorer ruling, generalised). Nil keeps whatever
    /// `VerbDerivation` already derived.
    static func destination(_ row: Row) -> String? {
        switch row.source {
        case "Cursor":
            // A Cursor row's link is `prUrl ?? url`, so the two land in
            // different places and the word has to follow the link rather
            // than the seat.
            return row.tags.contains("PR") ? String(localized: "Pull request") : nil
        case "App Store Connect": return String(localized: "Connect")
        case "Vercel", "Sentry", "PagerDuty", "Linear", "Trello", "Jira",
             "GitLab", "Notion", "PostHog", "Stripe":
            return row.source
        default: return nil
        }
    }

    /// Localization seam. Every status word this type returns is user-facing
    /// copy, and it is deliberately produced HERE rather than read off the
    /// bridges' own `leadClause`s — those are what the row was stamped with
    /// at ingest, in the language of that day, and reading them back is the
    /// §340 bug. This says the word in the language the sheet is being read
    /// in, today.
    private static func word(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
