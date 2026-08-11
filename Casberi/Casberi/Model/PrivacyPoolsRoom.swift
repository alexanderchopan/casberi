import Foundation

/// THE PRIVACY POOLS ROOM'S HEAD (2026-08-10, prd §349) — where your deposits
/// stand with the screener, and whether one of them needs you.
///
/// §162 built this seat around one moment (a deposit clearing) and §228 added
/// the two that also matter (declined, proof required). All three land as their
/// own alert rows and then scroll away, which is right for news and useless as
/// a standing answer: a deposit sits in review for days, and the room led with
/// a list newest-first, so **"what is still waiting, and is anything stuck?"**
/// had no answer anywhere in the app. That is what this card is.
///
/// ## It spends nothing
///
/// Every fact is a tag already on a landed row — `Pending` → `Cleared` /
/// `Declined` / `Needs proof`, moved in place by `PrivacyPoolsBridge.retag` as
/// the ASP answers (§311). No request, no ASP poll of its own, no new `Thing`
/// property, no CloudKit deploy: the `StripeRoom`/`CursorRoom` contract.
///
/// It deliberately does NOT read the pending WATCHLIST that drives the poll,
/// even though that watchlist is structured and right there in `UserDefaults`.
/// Two records of the same fact drift, and this one has already drifted once
/// (see `states`); the rows are also the only half that remembers a deposit
/// after it resolved, since the watchlist prunes terminal labels. One source of
/// truth, and it is the corpus.
///
/// ## What it may NOT draw: the anonymity set
///
/// §228 stores each deposit's cover — "Privacy Pools' ETH pool holds about
/// 3,900 accepted deposits" — and stores it as a SENTENCE, on `enrichedText`.
/// There is no number in the store to add up, only prose to re-parse, and
/// re-parsing display prose back into arithmetic is the thing `Thing`'s own doc
/// argues against. It would also be wrong per-deposit even if it worked: the
/// line is a snapshot taken at landing, so a card summing them would present
/// several different moments' pool sizes as one current figure, on the screen
/// where a number's meaning is the whole point. The cover reading stays where
/// it is honest — on the deposit it describes, in its own sheet.
///
/// ## What it may NOT draw: money
///
/// The amount lives only inside each row's title. Same limit, same reason, as
/// `PeerRoom` — and worse here, because deposits span pools in different assets
/// and a parsed sum would add ETH to USDC.
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can compile
/// it WHOLE and unmodified.
struct PrivacyPoolsRoom: Equatable {

    // MARK: - What a row is

    /// Where a deposit stands with the screener.
    ///
    /// The raw values ARE the tag strings `PrivacyPoolsBridge.retag` writes —
    /// one table, so the two halves cannot drift into disagreeing about what
    /// "Needs proof" is spelled like. That mirror matters more than most here:
    /// the bridge shipped §311 with its `retag` looking up a `sourceRef`
    /// spelled differently from the one it lands, so no tag ever moved and
    /// every deposit read `Pending` forever. A card built on tags is only as
    /// true as that agreement.
    enum State: String, Equatable, CaseIterable {
        /// The ASP has not ruled yet. Also the state a deposit lands in.
        case pending      = "Pending"
        /// Approved — the deposit is in the withdrawal tree and can be spent
        /// privately. This is the moment the whole seat exists for.
        case cleared      = "Cleared"
        /// Refused. The money is not lost; it has to be reclaimed to the
        /// original depositor instead of withdrawn privately.
        case declined     = "Declined"
        /// 0xBow wants proof of innocence before it can rule.
        case needsProof   = "Needs proof"

        /// Whether this state is waiting on the PERSON rather than on the
        /// screener. Only one is: proof is something only they can supply.
        /// A decline needs action too, but it is a decision already made — the
        /// difference is whether the outcome is still open.
        var needsYou: Bool { self == .needsProof }

        /// Whether the deposit's review is over, either way.
        var resolved: Bool { self == .cleared || self == .declined }
    }

    /// The tag vocabulary, as strings — the set `retag` strips before writing a
    /// new state, so a row always carries exactly one and the card can never
    /// double-count a deposit that changed its mind.
    static let states: [String] = State.allCases.map(\.rawValue)

    /// The `sourceRef` prefixes `PrivacyPoolsBridge` lands.
    ///
    /// Only the first two are DEPOSITS in any sense the card counts. The other
    /// two are ALERTS about a deposit that is already counted — landing one is
    /// how the person hears the news, and counting it here would report a
    /// cleared deposit twice, once as itself and once as its own announcement.
    /// Excluded by construction rather than by remembering.
    static let depositPrefix   = "privacypools:dep:"
    static let reclaimedPrefix = "privacypools:ragequit:"
    static let statusPrefix    = "privacypools:status:"
    static let poiPrefix       = "privacypools:poi:"

    /// What a landed row records.
    enum Row: Equatable {
        /// A deposit into a pool, wearing its current state.
        case deposit(State?)
        /// A ragequit — taken back out to the original depositor.
        case reclaimed
        /// An alert about a deposit. Never counted; see `depositPrefix`.
        case alert
    }

    /// Which row shape a `sourceRef` and its tags record, or nil for anything
    /// this build does not recognise.
    static func row(ref: String?, tags: [String]) -> Row? {
        guard let ref else { return nil }
        if ref.hasPrefix(depositPrefix) { return .deposit(state(tags: tags)) }
        if ref.hasPrefix(reclaimedPrefix) { return .reclaimed }
        if ref.hasPrefix(statusPrefix) || ref.hasPrefix(poiPrefix) { return .alert }
        return nil
    }

    /// The deposit's ASP label, off either a deposit ref or its status alert
    /// — `PrivacyPoolsBridge` lands both under the SAME label suffix
    /// (`depositPrefix + label`, `statusPrefix + label`), which is what lets
    /// this card join "when it landed" to "when we saw it resolve" without a
    /// new field or a second read. Nil for a ref shape neither prefix names.
    static func label(ref: String?) -> String? {
        guard let ref else { return nil }
        if ref.hasPrefix(depositPrefix) { return String(ref.dropFirst(depositPrefix.count)) }
        if ref.hasPrefix(statusPrefix) { return String(ref.dropFirst(statusPrefix.count)) }
        return nil
    }

    /// The one state tag on a row, or nil.
    ///
    /// Nil is a real answer and is counted as `untagged`, never defaulted to
    /// `.pending`: a deposit landed before §311 carries no state tag at all,
    /// and calling it pending would report a deposit that cleared two months
    /// ago as still waiting — a claim about the screener we have no evidence
    /// for, on the card whose entire subject is that claim.
    static func state(tags: [String]) -> State? {
        for tag in tags {
            if let found = State(rawValue: tag) { return found }
        }
        return nil
    }

    /// One landed row, reduced to what this card reads.
    struct Sighting: Equatable {
        let ref: String?
        let tags: [String]
        let at: Date
    }

    // MARK: - Values

    /// One state's share of the deposits, ready to draw.
    struct Segment: Identifiable, Equatable {
        var id: String { state.rawValue }
        let state: State
        let count: Int
        /// The OLDEST deposit currently in this state (2026-08-11) — the
        /// room used to say "3 deposits in review" with no way to tell a
        /// three-day wait from a three-week one. `capturedAt` is when the
        /// deposit LANDED, which is the honest floor for "how long has this
        /// been sitting" even though a deposit can spend part of that window
        /// unwatched (before the wallet was connected).
        let oldestAt: Date?
    }

    /// Ranked — see `ordered`. Only states with at least one deposit appear, so
    /// a card never draws an empty segment.
    let segments: [Segment]
    /// Deposits carrying no state tag at all. Counted, never assumed pending.
    let untagged: Int
    /// Deposits taken back out to the depositor. Not a state — a ragequit is
    /// its own row and the deposit it undoes keeps whatever state it had, so
    /// this is reported beside the segments and never inside them.
    let reclaimed: Int
    /// The newest deposit, for the idle clause. Over deposits only: an alert
    /// row is stamped when we polled, not when anything was deposited.
    let newest: Date?
    /// The MEDIAN days between a deposit landing and this device observing
    /// its status alert (2026-08-11) — see `compose` for how it's paired,
    /// and the type doc for why it's a real but partial sample rather than a
    /// claim about the screener in general. Nil when no deposit has both
    /// ends observed yet.
    let reviewDays: Int?

    /// Below this there is nothing a card can say that the row does not.
    static let minimumDeposits = 1

    /// Every deposit the card knows about, tagged or not.
    var deposits: Int { segments.reduce(0) { $0 + $1.count } + untagged }

    /// Deposits still in review — the number this card exists to state.
    var waiting: Int {
        segments.filter { !$0.state.resolved }.reduce(0) { $0 + $1.count }
    }

    /// The one deposit state that needs the person, if any.
    var needsYou: Segment? { segments.first { $0.state.needsYou } }

    var lead: Segment? { segments.first }

    /// A room with no deposits at all. A reclaimed-only room still draws — the
    /// card can honestly say everything came back out, which is a real standing
    /// and the row list alone does not add it up.
    var isEmpty: Bool { deposits < PrivacyPoolsRoom.minimumDeposits && reclaimed == 0 }

    // MARK: - Composing

    static func compose(rows sightings: [Sighting]) -> PrivacyPoolsRoom {
        var counts: [State: Int] = [:]
        var oldestByState: [State: Date] = [:]
        var untagged = 0, reclaimed = 0
        var newest: Date?
        // Label → when the deposit landed, and label → when this device saw
        // its STATUS alert (approved/declined only — never the poi alert,
        // which isn't a resolution). Both keyed the same way `retag` and
        // `landDeposits` already key them, so no new read is needed to pair
        // them; see `compose`'s reviewDays clause below.
        var depositAt: [String: Date] = [:]
        var resolvedAt: [String: Date] = [:]

        for sighting in sightings {
            switch row(ref: sighting.ref, tags: sighting.tags) {
            case .deposit(let state):
                if newest == nil || sighting.at > newest! { newest = sighting.at }
                if let state {
                    counts[state, default: 0] += 1
                    if oldestByState[state] == nil || sighting.at < oldestByState[state]! {
                        oldestByState[state] = sighting.at
                    }
                } else {
                    untagged += 1
                }
                if let label = label(ref: sighting.ref) { depositAt[label] = sighting.at }
            case .reclaimed:
                reclaimed += 1
            // An alert about a deposit already counted; a ref this build does
            // not know is not evidence of anything. A STATUS alert (not a poi
            // one) also marks the moment this device saw that deposit resolve.
            case .alert:
                if let ref = sighting.ref, ref.hasPrefix(statusPrefix),
                   let label = label(ref: ref) {
                    resolvedAt[label] = sighting.at
                }
            case .none:
                continue
            }
        }

        let segments = counts.map {
            Segment(state: $0.key, count: $0.value, oldestAt: oldestByState[$0.key])
        }

        // Observed review time: only labels whose landing AND resolution
        // this device both saw — never estimated, never a claim about the
        // screener's typical speed, only what actually happened here. A
        // negative gap (a resolution somehow before the deposit) is treated
        // as unusable rather than as a real zero.
        let durations = depositAt.compactMap { label, landed -> Int? in
            guard let resolved = resolvedAt[label], resolved >= landed else { return nil }
            return days(from: landed, to: resolved)
        }

        return PrivacyPoolsRoom(segments: ordered(segments), untagged: untagged,
                                reclaimed: reclaimed, newest: newest,
                                reviewDays: medianDays(durations))
    }

    /// The middle value, sorted — MEDIAN rather than mean, the
    /// `StripeSilence` discipline: one deposit that took months to resolve
    /// (POI, most likely) would drag a mean into overstating every other
    /// deposit's real wait.
    static func medianDays(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    // MARK: - Ranking

    /// Which state leads the card.
    ///
    ///   3 — proof required: only you can move this, and nothing moves until
    ///       you do.
    ///   2 — declined: the money needs reclaiming, but the decision is made.
    ///   1 — pending: waiting on somebody else.
    ///   0 — cleared: the good outcome, and the one that needs nothing.
    ///
    /// Deliberately NOT by count. A single deposit stuck on proof outranks
    /// forty that cleared, because the forty need nothing from anybody and the
    /// one is the entire reason to look. Ranking by size would bury it exactly
    /// on the accounts that use this seat most.
    static func rank(_ state: State) -> Int {
        switch state {
        case .needsProof: return 3
        case .declined:   return 2
        case .pending:    return 1
        case .cleared:    return 0
        }
    }

    /// Rank, then count, then name — TOTAL, so two composes over the same data
    /// can never disagree and the card cannot reshuffle between opens.
    static func ordered(_ segments: [Segment]) -> [Segment] {
        segments.sorted { a, b in
            let ra = rank(a.state), rb = rank(b.state)
            if ra != rb { return ra > rb }
            if a.count != b.count { return a.count > b.count }
            return a.state.rawValue < b.state.rawValue
        }
    }

    // MARK: - The split bar

    /// A segment's share of all deposits, 0…1.
    ///
    /// A proportional split IS honest here, where `CursorRoom` refused one:
    /// there a pass/fail bar would have been a success rate over an arbitrary
    /// window nobody chose, while these states are mutually exclusive, cover
    /// every deposit the room holds, and are a COMPLETE current standing rather
    /// than a sample. The bar says "this is where all of it sits", which is
    /// exactly true.
    ///
    /// The denominator is `deposits`, INCLUDING untagged ones, so the drawn
    /// segments legitimately fall short of the full width when some deposits
    /// have no state — the gap is the unknown, and the note names it. Filling
    /// the bar by dividing through the tagged count alone would silently
    /// present partial knowledge as complete.
    static func share(count: Int, of deposits: Int) -> Double {
        guard deposits > 0 else { return 0 }
        return min(max(Double(count) / Double(deposits), 0), 1)
    }

    // MARK: - Days

    /// Whole CALENDAR days — see `PeerRoom.days` for why not an interval.
    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Words

    static func depositsLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 deposit") : String(localized: "\(count) deposits")
    }

    /// What a state MEANS, in the person's terms rather than the screener's —
    /// a segment label of "Declined" states the verdict and not the
    /// consequence, and the consequence is the part that changes what you do.
    static func meaning(_ state: State) -> String {
        switch state {
        case .needsProof: return String(localized: "waiting on your proof")
        case .declined:   return String(localized: "reclaim to your wallet")
        case .pending:    return String(localized: "in review")
        case .cleared:    return String(localized: "ready to withdraw privately")
        }
    }

    static func segmentLine(_ segment: Segment) -> String {
        String(localized: "\(segment.count) \(meaning(segment.state))")
    }

    /// Below this the wait isn't worth naming — a deposit a few hours into
    /// review reading "waited 0 days" is noise, not news.
    static let noteworthyWaitDays = 3

    /// "— the oldest has waited 9 days" (2026-08-11), appended to a headline
    /// that is already naming a state someone is WAITING on. Silent under
    /// `noteworthyWaitDays`, and silent for a `nil` segment (the `.declined`
    /// and `.cleared` headline branches never call this — a cleared deposit
    /// finished waiting, and how long a decline took to arrive isn't the
    /// fact that matters once it has).
    static func ageClause(_ segment: Segment?, now: Date = .now) -> String {
        guard let oldestAt = segment?.oldestAt else { return "" }
        let waited = days(from: oldestAt, to: now)
        guard waited >= noteworthyWaitDays else { return "" }
        return String(localized: " — the oldest has waited \(waited) days")
    }

    /// The one line at the top of the card. Trouble leads, always — see `rank`.
    static func headline(_ room: PrivacyPoolsRoom, now: Date = .now) -> String {
        if let stuck = room.needsYou {
            let base = stuck.count == 1
                ? String(localized: "A deposit needs your proof")
                : String(localized: "\(stuck.count) deposits need your proof")
            return base + ageClause(stuck, now: now)
        }
        guard let lead = room.lead else {
            // Nothing tagged at all. Two shapes reach here and both are real:
            // a room of pre-§311 deposits, and a room where everything has
            // been reclaimed.
            if room.deposits > 0 {
                return String(localized: "\(depositsLabel(room.deposits)) in Privacy Pools")
            }
            return room.reclaimed == 1
                ? String(localized: "1 deposit reclaimed — nothing shielded")
                : String(localized: "\(room.reclaimed) deposits reclaimed — nothing shielded")
        }
        switch lead.state {
        case .declined:
            return lead.count == 1
                ? String(localized: "A deposit was declined")
                : String(localized: "\(lead.count) deposits were declined")
        case .pending:
            let base = lead.count == 1
                ? String(localized: "1 deposit is still in review")
                : String(localized: "\(lead.count) deposits are still in review")
            return base + ageClause(lead, now: now)
        case .cleared:
            return lead.count == 1
                ? String(localized: "Your deposit is ready to withdraw")
                : String(localized: "All \(lead.count) deposits are ready to withdraw")
        case .needsProof:
            // Unreachable — `needsYou` above claims this state first. Stated
            // rather than crashed, because a `fatalError` in a card composer
            // would take the feed down over a ranking bug.
            return String(localized: "A deposit needs your proof")
        }
    }

    /// The line under it. Never a restatement: the headline carries whichever
    /// state leads, so this carries the SHAPE of the rest — how much is still
    /// open versus settled.
    static func note(_ room: PrivacyPoolsRoom) -> String {
        guard room.deposits > 0 else {
            return String(localized: "Nothing in the pools right now")
        }
        let waiting = room.waiting
        if waiting == 0 {
            return String(localized: "Every review is finished")
        }
        if waiting == room.deposits {
            return String(localized: "None of them have been ruled on yet")
        }
        return String(localized: "\(waiting) of \(room.deposits) still waiting on the screener")
    }

    /// The quiet line at the foot: deposits with no state we can read, ones
    /// already taken back out, and how long the room has been still.
    ///
    /// The untagged clause is not politeness. A deposit this card cannot place
    /// is a deposit missing from every segment above it AND a gap in the bar,
    /// and a standing that silently omits rows is the failure the import drop
    /// counters exist to prevent, one room over.
    static func footnote(_ room: PrivacyPoolsRoom, now: Date = .now) -> String? {
        var parts: [String] = []
        if room.untagged > 0 {
            parts.append(room.untagged == 1
                         ? String(localized: "1 deposit's status is unknown")
                         : String(localized: "\(room.untagged) deposits' status is unknown"))
        }
        if room.reclaimed > 0 {
            parts.append(room.reclaimed == 1
                         ? String(localized: "1 reclaimed")
                         : String(localized: "\(room.reclaimed) reclaimed"))
        }
        // Only what THIS device has actually watched resolve — never a claim
        // about 0xBow's screener in general. See `compose`'s `reviewDays`.
        if let reviewDays = room.reviewDays {
            parts.append(reviewDays == 0
                         ? String(localized: "review has taken same-day here")
                         : String(localized: "review has taken about \(reviewDays) days here"))
        }
        if let idle = idleNote(newest: room.newest, now: now) { parts.append(idle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "nothing new for 45 days" — only once the quiet is long enough to mean
    /// something. Deliberately long: depositing into a privacy pool is an
    /// occasional act, and a card narrating every ordinary gap is one people
    /// stop reading.
    static func idleNote(newest: Date?, now: Date = .now, quietAfter: Int = 45) -> String? {
        guard let newest else { return nil }
        let days = days(from: newest, to: now)
        guard days >= quietAfter else { return nil }
        return String(localized: "nothing new for \(days) days")
    }
}
