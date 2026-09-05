import Foundation

/// WHAT BREAKS NEXT — the Cloudflare room's runway (2026-08-03, prd §296,
/// ruled from `design/cloudflare-viz/cloudflare-room-mocks.html`, option A).
///
/// Every row this bridge lands is a DATE something you own stops working: a
/// certificate that hasn't renewed, a registration coming up, the API token's
/// own expiry, a zone that isn't being served. The room listed them in
/// whatever order they arrived and drew nothing. This puts them on one axis.
///
/// ## Why the room needed a card at all
///
/// The Cloudflare room is **all alarms and no estate**. A healthy account
/// renders as a blank screen — which is indistinguishable from a broken token,
/// a lapsed permission, or a bridge that silently stopped reading. So the
/// card's EMPTY state is not a nicety, it is the reason to build it: "nothing
/// you own expires for four months" is a real answer, and it is the §291
/// empty-read ruling landing in the room that needs it most.
///
/// That is also why `quiet` names a date the room never lands. The bridge only
/// lands a deadline inside its own window (30 days for a certificate, 60 for a
/// registration), so the next date on a healthy account is by definition
/// something no `Thing` holds — `CloudflareEstate` records it during the pass
/// precisely so this card can state it instead of shrugging.
///
/// ## The rail, and what it is not
///
/// One axis, drawn ONCE, with a mark where each deadline actually falls. Not a
/// bar per row: §292 ruled those out ("too AI") and they were redundant beside
/// the number sitting two millimetres away. The rows underneath carry the
/// names, so the rail never needs labels of its own.
///
/// Nothing here is inferred. No risk score, no "your most exposed domain", no
/// ranking of zones by how many problems they have — every mark is one real
/// object with a real date on it (the §295 ruling: limit the analysis, it
/// should be factual). The one judgement the card makes is ORDER, and it
/// orders by the date, which is the only honest order for a deadline.
///
/// ## What it refuses to speak for
///
/// `uncovered` is not decoration. The pass reads certificates for at most
/// `CloudflareFetch.zoneCap` zones, and an account past that cap has zones
/// whose certificates were never looked at. A card that drew a confident
/// runway over an estate it only partly read would be the same lie
/// `CloudflareFetch.lastCovered` exists to prevent, one surface up.
///
/// ## Foundation-only, on purpose
///
/// Every failure mode here is a WRONG READING that renders perfectly — a
/// certificate placed at the wrong point on the rail, an overdue row sorted
/// last, a quiet headline claiming four months on an account that expires
/// tomorrow. So this file holds no `Thing`, no store and no network: it is
/// compiled AS SHIPPED by `scripts/cloudflare-selftest.sh` and fed cases whose
/// answers are known. The reading half lives in `CloudflareRunwaySource.swift`,
/// exactly as `WalletApprovalExposure` and its `…Source` are split.
struct CloudflareRunway: Equatable, Sendable {

    /// What kind of object a deadline belongs to. These read differently on
    /// purpose: a certificate is supposed to renew itself, so its lateness IS
    /// the fault; a registration is a decision you make; the token is the
    /// bridge's own credential.
    enum Kind: String, Equatable, Sendable {
        case certificate, registration, token, zone
    }

    /// One deadline, as the card states it.
    struct Item: Equatable, Sendable, Identifiable {
        /// The `sourceRef` of the thing this came from — the door to its row.
        let id: String
        /// The zone, the domain, or the token. See `named`.
        let name: String
        /// False when the estate snapshot couldn't name this object and `name`
        /// fell back to the landed row's own title. The card then omits the
        /// kind line, because the title already says what it is — honest
        /// degradation rather than a row wearing "casberi.app — TLS
        /// certificate expires in 6 days" above the word "TLS certificate".
        let named: Bool
        let kind: Kind
        /// Whole days from now. Negative is overdue, zero is today, and **nil
        /// means there is no date because it is already true** — a zone that
        /// isn't being served is not a deadline, it is a state.
        let days: Int?
        /// Registrations only. Stated rather than used as a filter, for the
        /// reason `CloudflareFetch.domainRow` gives: it is exactly the domains
        /// set to renew automatically that lapse, because the card behind them
        /// expired and nobody was told.
        let autoRenews: Bool?
    }

    /// The next date this card knows about but the room does not hold — used
    /// only by the quiet state. See the type doc.
    struct Next: Equatable, Sendable {
        let days: Int
        let date: Date
        let name: String
        let kind: Kind
    }

    /// Ranked: already-true first, then soonest.
    let items: [Item]
    /// How many zones the account has, and how many of them this card cannot
    /// speak for.
    let zonesSeen: Int
    let uncovered: Int
    /// Present only when `items` is empty — see the type doc.
    let next: Next?

    /// The rail's length in days. DERIVED, never stored: a span held beside
    /// the items it was computed from is a pair that can disagree, and the
    /// card threads it into four places that all assume it can't.
    var span: Int { Self.span(for: items) }

    /// Nothing to draw. A card with no deadlines AND no next date knows
    /// nothing about the account, which is what a bridge that has never
    /// completed a pass looks like; drawing "all clear" off that would be the
    /// exact claim this file exists to avoid.
    var isEmpty: Bool { items.isEmpty && next == nil }

    // MARK: - Order

    /// Already-true first, then by date, then by name so the order is stable
    /// between passes (an unstable rank re-animates rows nobody touched).
    ///
    /// A stalled zone leads everything with a date because it is not a
    /// warning about the future: the site is not being served right now.
    static func rank(_ items: [Item]) -> [Item] {
        items.sorted { a, b in
            switch (a.days, b.days) {
            case (nil, nil): return a.name < b.name
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x == y ? a.name < b.name : x < y
            }
        }
    }

    /// The rail's length: 60 days by default — the bridge's own widest landing
    /// window, so a mark can never fall off the end — and wider only if some
    /// row somehow reaches past it. Rounded to whole months so the ticks below
    /// it stay on 30-day boundaries.
    ///
    /// A drift guard in `scripts/cloudflare-selftest.sh` ties the 60 to
    /// `CloudflareFetch.domainWindow`: widen that window without widening this
    /// and every distant registration would pile up on the rail's last pixel.
    static func span(for items: [Item]) -> Int {
        let furthest = items.compactMap(\.days).max() ?? 0
        guard furthest > 60 else { return 60 }
        return Int((Double(furthest) / 30).rounded(.up)) * 30
    }

    /// The 30-day gridlines strictly INSIDE the rail — never one under either
    /// end label. Model-side rather than view-side for the reason the type doc
    /// gives: an axis whose gridlines or end label disagree with its own span
    /// is a wrong reading that renders perfectly.
    static func gridDays(span: Int) -> [Int] {
        Array(stride(from: 30, to: max(span, 1), by: 30))
    }

    /// The rail's right-hand tick. Reads the same `span` the marks are placed
    /// against, so the axis can never be labelled with a length it isn't.
    static func spanLabel(span: Int) -> String {
        String(localized: "\(span) days")
    }

    /// Where a mark sits, 0…1. Overdue and already-true both pin to the left
    /// edge: there is no negative room on a runway, and a row that has already
    /// happened belongs at "now", not off the axis.
    static func position(days: Int?, span: Int) -> Double {
        RoomRunway.position(days: days, span: span)
    }

    // MARK: - Words

    /// The headline — the whole finding as a sentence, the anatomy ruled in
    /// for `WalletApprovalExposureCard`.
    ///
    /// Three branches, because a stalled zone has no date and folding it into
    /// "come due in the next 60 days" would say something false about it.
    static func headline(items: [Item], span: Int) -> String {
        let stalled = items.filter { $0.days == nil }.count
        let dated = items.count - stalled
        if items.count == 1, let only = items.first { return sentence(only) }
        if stalled > 0, dated == 0 {
            return String(localized: "\(stalled) of your zones aren't being served")
        }
        if stalled > 0 {
            let rest = dated == 1
                ? String(localized: "1 more thing comes due")
                : String(localized: "\(dated) more things come due")
            return stalled == 1
                ? String(localized: "A zone of yours isn't being served, and \(rest)")
                : String(localized: "\(stalled) of your zones aren't being served, and \(rest)")
        }
        return String(localized: "\(dated) things you own come due in the next \(span) days")
    }

    /// One item stated on its own — the headline when there is exactly one,
    /// which is the common case on a small estate.
    static func sentence(_ item: Item) -> String {
        guard let days = item.days else {
            return String(localized: "\(item.name) isn't being served")
        }
        switch item.kind {
        case .certificate:
            return days <= 0
                ? String(localized: "\(item.name)'s certificate has expired")
                : String(localized: "\(item.name)'s certificate expires in \(days) days")
        case .registration:
            return days <= 0
                ? String(localized: "\(item.name) has expired")
                : (item.autoRenews == true
                    ? String(localized: "\(item.name) renews in \(days) days")
                    : String(localized: "\(item.name) expires in \(days) days"))
        case .token:
            return days <= 0
                ? String(localized: "Your Cloudflare token has expired")
                : String(localized: "Your Cloudflare token expires in \(days) days")
        case .zone:
            return String(localized: "\(item.name) isn't being served")
        }
    }

    /// The line under the headline: why the nearest one matters. Named "the
    /// nearest" rather than restating it, so the sub never duplicates the
    /// headline it sits beneath.
    static func note(for head: Item, alone: Bool) -> String {
        let why = reason(head.kind, autoRenews: head.autoRenews)
        return alone ? why : String(localized: "The nearest: \(why)")
    }

    /// What each kind means for the person reading it. These mirror the
    /// summaries the bridge already writes onto its rows — one voice, whether
    /// you meet the fact on the card or in the sheet.
    static func reason(_ kind: Kind, autoRenews: Bool?) -> String {
        switch kind {
        case .certificate:
            return String(localized: "a certificate that should have renewed itself by now")
        case .registration:
            return autoRenews == false
                ? String(localized: "a registration with auto-renew off — nothing will renew it for you")
                : String(localized: "a registration set to renew automatically, which still fails on an expired card")
        case .token:
            return String(localized: "this connection's own token — when it lapses Casberi stops reading, and nothing else here will know why")
        case .zone:
            return String(localized: "a zone Cloudflare isn't serving while it's in this state")
        }
    }

    /// The right-hand column. "Now" for a state, never a fake zero.
    static func value(days: Int?) -> String {
        guard let days else { return String(localized: "Now") }
        if days < 0 { return String(localized: "Overdue") }
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "1 day") }
        return String(localized: "\(days) days")
    }

    /// The kind line under a name. Nil when the estate couldn't name the
    /// object, since `name` is then the landed row's whole title.
    static func kindLine(_ item: Item) -> String? {
        guard item.named else { return nil }
        switch item.kind {
        case .certificate: return String(localized: "TLS certificate")
        case .registration:
            return item.autoRenews == true
                ? String(localized: "Registration · renews automatically")
                : String(localized: "Registration")
        case .token: return String(localized: "Casberi stops reading when it lapses")
        case .zone: return String(localized: "Cloudflare isn't serving it")
        }
    }

    /// The one chip, and it is the one fact that changes what you'd do — the
    /// `Unlimited` reasoning from §292. Everything else is the text ramp.
    static func chip(_ item: Item) -> String? {
        item.kind == .registration && item.autoRenews == false
            ? String(localized: "No auto-renew") : nil
    }

    /// Dim the number when the thing takes care of itself. A registration set
    /// to renew automatically is on the rail because the date is real, not
    /// because you have to do anything today.
    static func isQuiet(_ item: Item) -> Bool {
        item.kind == .registration && item.autoRenews == true && (item.days ?? 0) > 0
    }

    // MARK: - The quiet state

    /// "Nothing you own expires for four months." Months once it's far enough
    /// out that counting days is noise — nobody reads 118 as a duration.
    static func quietHeadline(days: Int) -> String {
        if days >= 60 {
            let months = Int((Double(days) / 30.0).rounded())
            return String(localized: "Nothing you own expires for \(months) months")
        }
        if days <= 1 { return String(localized: "Nothing you own expires before tomorrow") }
        return String(localized: "Nothing you own expires for \(days) days")
    }

    /// What the next date actually is, named and dated. A quiet card that
    /// couldn't say this would be indistinguishable from a card with no data.
    static func quietNote(_ next: Next) -> String {
        let when = quietDate(next.date)
        let what: String
        switch next.kind {
        case .certificate: what = String(localized: "\(next.name)'s certificate")
        case .registration: what = String(localized: "\(next.name)'s registration")
        case .token: what = String(localized: "this connection's token")
        case .zone: what = next.name
        }
        return String(localized: "The next date is \(what), on \(when).")
    }

    /// Day and month, no year — the quiet state only ever names a date inside
    /// the coming year, and a year on it reads as a legal document.
    ///
    /// `formatted(.dateTime…)` rather than a `DateFormatter`: it is the house
    /// idiom, and this one is reached during a body evaluation on the card's
    /// COMMON state, where allocating a formatter per render is real work for
    /// nothing.
    static func quietDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }

    // MARK: - Coverage

    /// What this card cannot speak for. Nil when it covered everything, which
    /// is every account under `CloudflareFetch.zoneCap` zones — so the note is
    /// absent rather than reassuring, and its presence always means something.
    static func coverageNote(uncovered: Int, zonesSeen: Int) -> String? {
        guard uncovered > 0, zonesSeen > 0 else { return nil }
        return uncovered == 1
            ? String(localized: "1 of your \(zonesSeen) zones wasn't read — nothing here speaks for it.")
            : String(localized: "\(uncovered) of your \(zonesSeen) zones weren't read — nothing here speaks for them.")
    }
}

/// What the last completed pass SAW — the runway's reading of the account
/// (prd §296, `CloudflareRunway`).
///
/// Three things live here and none of them can be recovered from the landed
/// rows, which is the whole reason it exists:
///
/// - **`zoneNames`** — a certificate row's `sourceRef` carries the zone ID and
///   only its title carries the name, and a title is localized prose, not data.
/// - **`autoRenew`** — the same fact, one level worse: it survives on a landed
///   row only as the difference between the words "renews" and "expires".
/// - **`next…`** — the earliest deadline on the whole account **regardless of
///   window**. The bridge lands nothing outside 30/60 days, so on a healthy
///   account the next date is by definition something no `Thing` holds; the
///   quiet card names it because the alternative is a card that can only say
///   "nothing", which is what a broken connection says too.
///
/// UserDefaults rather than the Keychain: a domain name and a renewal date are
/// public records — `whois` answers both — so they are not secrets. Cleared on
/// disconnect beside the DNS ledger, so a reconnected different account never
/// draws a runway over a stranger's estate.
struct CloudflareEstate: Codable, Equatable {
    var zoneNames: [String: String] = [:]
    var autoRenew: [String: Bool] = [:]
    var zonesSeen = 0
    var zonesCovered = 0
    var nextDate: Date?
    var nextName: String?
    /// `CloudflareRunway.Kind.rawValue`. Stored as the raw value, never as the
    /// rendered sentence: a language change would otherwise leave last week's
    /// English sitting inside a German card.
    var nextKind: String?

    /// Offers a deadline as the next one. Keeps the EARLIEST still in the
    /// future — a date already past is not "next", it's a row that already
    /// landed, and letting it win would freeze the quiet state on a
    /// certificate that expired in March.
    mutating func consider(_ date: Date, name: String, kind: CloudflareRunway.Kind,
                           now: Date = .now) {
        guard date > now else { return }
        guard nextDate == nil || date < nextDate! else { return }
        nextDate = date
        nextName = name
        nextKind = kind.rawValue
    }

    /// Zones this pass could not read certificates for — the cap, or a failed
    /// per-zone read. Never negative, whatever the two counts say.
    var uncovered: Int { max(zonesSeen - zonesCovered, 0) }
}
