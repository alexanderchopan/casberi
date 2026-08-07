import Foundation

/// THE APP STORE CONNECT ROOM'S HEAD (2026-08-06, prd §324) — where every app
/// stands right now.
///
/// §323 landed four kinds of event and led with a plain list of them, which is
/// the §247 gap exactly: a room holding the facts a developer refreshes App
/// Store Connect for, drawing none of them. The rows answer *what happened*.
/// This answers the question people actually have, which is present tense:
/// **where is my build, and how long has it been there?**
///
/// ## It spends nothing
///
/// Every field is already on the device — `ASCState.standing`, written by the
/// same pass that lands the rows, from the same responses. No request, no new
/// `Thing` field, no CloudKit deploy (the `StripeRoom`/`CloudflareRunway`
/// contract: a head that costs a call is a head that can fail, and a room's
/// lede must not fail differently from the rows beneath it).
///
/// ## The duration is the whole card, and it is the thing most easily faked
///
/// "In review · 2 days" is what makes this worth drawing. Apple publishes NO
/// timestamp for when a version entered its current state, so the only clock
/// available is our own — and on first connect that clock reads zero for a
/// version that has been in review since Tuesday. So a duration is shown ONLY
/// for a transition this device actually watched (`ASCStanding.observed`), and
/// the state stands alone until then. Showing "0 days" would be a confident
/// wrong answer about the one number being watched, which is §83 in the place
/// it costs most.
///
/// ## What it may NOT draw
///
/// No ratings curve, no download line, no "review usually takes N days"
/// estimate. The first two are tallies this bridge deliberately never fetches
/// (§216); the third would be an average computed from a sample of one
/// developer's history, rendered as a prediction. Apple's own review times are
/// not published per-app and this app has no business inventing them.
///
/// Foundation-only by design so `scripts/appstoreconnect-selftest.sh` can
/// compile it WHOLE and unmodified.
struct ASCRoom: Equatable {

    /// One app's standing, already reduced to what the card draws.
    struct App: Identifiable, Equatable {
        /// The App Store Connect app id — what the card hands back so the
        /// section can open the right row without the card holding a `Thing`.
        let id: String
        let name: String
        let version: String
        /// Nil when Apple reported a state this build has never heard of. The
        /// card still draws the app (its build runway is still true); it just
        /// says nothing it can't stand behind.
        let state: ASCVersionState?
        /// Whole days in the current state, or nil when we didn't watch it
        /// arrive there. See the type note.
        let days: Int?
        let build: String
        /// Whole days until the newest build stops working for testers, or nil
        /// when there is no build, no expiry, or it has already gone.
        let expiresInDays: Int?
    }

    /// Ranked — see `rank`. The lead is `apps.first`.
    let apps: [App]
    /// When the bridge last read Apple. Nil means never on this device, which
    /// is a different fact from "nothing has changed".
    let asOf: Date?

    var lead: App? { apps.first }
    /// Nothing worth a card. A connected key with no apps is a real state and
    /// gets no head — the connect screen already says so more usefully.
    var isEmpty: Bool { apps.isEmpty }

    // MARK: - Days

    /// Whole CALENDAR days, not `timeIntervalSince / 86400` — "expires Aug 20"
    /// means the day, so an 11pm read on the 19th is one day out, not 0.04.
    /// Negative is in the past.
    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Ranking

    /// Which app leads the card.
    ///
    /// Ordered by what a developer would want to see first if they could only
    /// see one line, and deliberately NOT by name or by recency:
    ///
    ///   4 — something is WRONG and only you can fix it (rejected, blocked).
    ///   3 — Apple is holding it: in review, or approved and waiting on you.
    ///   2 — a build is about to stop working for your testers.
    ///   1 — everything else that has a state at all.
    ///   0 — no readable state.
    ///
    /// An expiring build outranks a live app but never outranks a rejection:
    /// the rejection has no deadline and the expiry does, but the rejection is
    /// the one that stops the release entirely.
    static func rank(_ app: App, expirySoonDays: Int = 14) -> Int {
        if let state = app.state {
            if state.alarming { return 4 }
            if state == .inReview || state == .pendingDeveloperRelease
                || state == .pendingAppleRelease { return 3 }
        }
        if let expires = app.expiresInDays, expires <= expirySoonDays { return 2 }
        return app.state == nil ? 0 : 1
    }

    /// Rank first, then soonest expiry, then name — so the order is total and
    /// two runs over the same data can never disagree (a card that reshuffles
    /// on every foreground reads as broken).
    static func ordered(_ apps: [App], expirySoonDays: Int = 14) -> [App] {
        apps.sorted { a, b in
            let ra = rank(a, expirySoonDays: expirySoonDays)
            let rb = rank(b, expirySoonDays: expirySoonDays)
            if ra != rb { return ra > rb }
            let ea = a.expiresInDays ?? Int.max
            let eb = b.expiresInDays ?? Int.max
            if ea != eb { return ea < eb }
            return a.name < b.name
        }
    }

    // MARK: - Words

    /// The state, in the words the card shows. Distinct from
    /// `ASCVersionState.verdict`, which is written for a FEED ROW announcing a
    /// change ("Approved — yours to release") and reads wrong as a standing
    /// ("Casberi · Approved — yours to release · 2 days"). Present tense here,
    /// past tense there.
    static func stateLabel(_ state: ASCVersionState?) -> String {
        guard let state else { return String(localized: "Unknown") }
        switch state {
        case .prepareForSubmission:       return String(localized: "Not submitted")
        case .readyForReview:             return String(localized: "Ready to submit")
        case .waitingForReview:           return String(localized: "Waiting for review")
        case .inReview:                   return String(localized: "In review")
        case .pendingContract:            return String(localized: "Contract needed")
        case .waitingForExportCompliance: return String(localized: "Export compliance")
        case .pendingDeveloperRelease:    return String(localized: "Ready to release")
        case .pendingAppleRelease:        return String(localized: "Apple is releasing")
        case .processingForDistribution,
             .processingForAppStore:      return String(localized: "Processing")
        case .readyForDistribution,
             .readyForSale:               return String(localized: "Live")
        case .accepted:                   return String(localized: "Approved")
        case .rejected:                   return String(localized: "Rejected")
        case .metadataRejected:           return String(localized: "Metadata rejected")
        case .invalidBinary:              return String(localized: "Invalid binary")
        case .developerRejected:          return String(localized: "You withdrew it")
        case .developerRemovedFromSale:   return String(localized: "You removed it")
        case .removedFromSale:            return String(localized: "Removed from sale")
        case .replacedWithNewVersion:     return String(localized: "Superseded")
        case .notApplicable:              return String(localized: "Not applicable")
        }
    }

    /// "· 2 days" — nil when we never watched it arrive, and nil on day zero,
    /// where "0 days" reads as a measurement and "today" is the truth.
    static func waitLabel(days: Int?) -> String? {
        guard let days, days > 0 else { return nil }
        return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
    }

    /// The build line: what it is and how long it has left. Nil when there is
    /// no build to talk about.
    static func buildLabel(_ app: App) -> String? {
        guard !app.build.isEmpty else { return nil }
        let name = String(localized: "Build \(app.build)")
        guard let days = app.expiresInDays else { return name }
        if days <= 0 { return name + " · " + String(localized: "expires today") }
        if days == 1 { return name + " · " + String(localized: "expires tomorrow") }
        return name + " · " + String(localized: "\(days) days left")
    }

    /// The one line at the top of the card.
    ///
    /// It states the LEAD app rather than counting apps, because a count is the
    /// thing the module doctrine forbids and because almost every account here
    /// has one or two apps — "2 apps" would be a worse sentence than the one
    /// fact worth reading.
    static func headline(_ room: ASCRoom) -> String {
        guard let lead = room.lead else { return String(localized: "Nothing to report") }
        var line = "\(lead.name) · \(stateLabel(lead.state))"
        if let wait = waitLabel(days: lead.days) { line += " · \(wait)" }
        return line
    }

    /// The quiet line under the card: how many more apps aren't drawn, and how
    /// old the reading is. Both, or either, or nothing.
    ///
    /// Staleness is stated past a day because this bridge reads on the
    /// foreground sweep — a number from this morning is normal, a number from
    /// last week means the key stopped working and nothing else on the card
    /// would say so.
    static func note(_ room: ASCRoom, drawn: Int, now: Date = .now) -> String? {
        var parts: [String] = []
        let hidden = room.apps.count - drawn
        if hidden > 0 {
            parts.append(hidden == 1 ? String(localized: "1 more app")
                                     : String(localized: "\(hidden) more apps"))
        }
        if let stale = staleNote(asOf: room.asOf, now: now) { parts.append(stale) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func staleNote(asOf: Date?, now: Date = .now) -> String? {
        guard let asOf else { return String(localized: "not read on this device yet") }
        let days = days(from: asOf, to: now)
        guard days >= 1 else { return nil }
        return days == 1 ? String(localized: "read yesterday")
                         : String(localized: "read \(days) days ago")
    }
}
