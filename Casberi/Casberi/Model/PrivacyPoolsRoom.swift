import Foundation

/// THE PRIVACY POOLS ROOM'S HEAD (2026-08-10, prd §349) — where your deposits
/// stand with the screener, whether one of them needs you, how much is actually
/// in there, and how much cover it has.
///
/// §162 built this seat around one moment (a deposit clearing) and §228 added
/// the two that also matter (declined, proof required). All three land as their
/// own alert rows and then scroll away, which is right for news and useless as
/// a standing answer: a deposit sits in review for days, and the room led with
/// a list newest-first, so **"what is still waiting, and is anything stuck?"**
/// had no answer anywhere in the app. That is what this card is.
///
/// 2026-08-17 (prd §397) widened it three ways, each closing a gap the first
/// cut named in its own doc as out of reach:
///
///  1. **The reclaim loop closes.** A ragequit landed as its own row and the
///     deposit it undid kept whatever state it had — so a card whose whole job
///     is "trouble leads" went on leading with "A deposit was declined —
///     reclaim to your wallet" FOREVER, on a deposit already back in the
///     wallet. See `reclaimedLabels`.
///  2. **What is in the pools, per asset.** §349 refused a figure because the
///     amount lived only inside each row's title. It does not any more:
///     `PrivacyPoolsBridge` stamps `priceValue`/`priceCurrency` at landing
///     (2026-08-17), the same structured pair `RailgunRoom` and
///     `GnosisPayRoom` already read. Never summed across assets.
///  3. **Cover became a number.** See `Cover`.
///
/// ## It spends nothing per open
///
/// Every fact is a tag or a stamped field already on a landed row — `Pending`
/// → `Cleared` / `Declined` / `Needs proof` / `Reclaimed`, moved in place by
/// `PrivacyPoolsBridge.retag` as the ASP answers (§311). No request per open,
/// no new `Thing` property, no CloudKit deploy: the `StripeRoom`/`CursorRoom`
/// contract. The one read this room's data costs is the once-a-day pools-stats
/// refresh behind `Cover`, which is bought by the BRIDGE on its own sweep and
/// never by drawing.
///
/// It deliberately does NOT read the pending WATCHLIST that drives the poll,
/// even though that watchlist is structured and right there in `UserDefaults`.
/// Two records of the same fact drift, and this one has already drifted once
/// (see `states`); the rows are also the only half that remembers a deposit
/// after it resolved, since the watchlist prunes terminal labels. One source of
/// truth, and it is the corpus.
///
/// ## What it may NOT draw: the anonymity set, as prose
///
/// §228 stores each deposit's cover — "Privacy Pools' ETH pool holds about
/// 3,900 accepted deposits" — as a SENTENCE, on `enrichedText`, and §349
/// refused to draw anything from it: there is no number in that sentence to add
/// up, only prose to re-parse, and a card summing several deposits' lines would
/// present several different moments' pool sizes as one current figure.
///
/// That refusal stands, and `Cover` does not reverse it — it goes around it.
/// The count is read as a NUMBER, from the same `pools-stats` endpoint §228
/// already calls, kept per pool as an integer, and stated as ONE current
/// reading for ONE asset rather than a sum of snapshots. The per-deposit
/// sentence stays exactly where it is honest: on the deposit it describes.
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
        /// Taken back out to the original depositor (2026-08-17) — the only
        /// state that means the money is no longer in a pool at all. See
        /// `reclaimedLabels` for why this is decided by EVIDENCE and not only
        /// by the tag.
        case reclaimed    = "Reclaimed"

        /// Whether this state is waiting on the PERSON rather than on the
        /// screener. Only one is: proof is something only they can supply.
        /// A decline needs action too, but it is a decision already made — the
        /// difference is whether the outcome is still open.
        var needsYou: Bool { self == .needsProof }

        /// Whether the deposit's review is over, either way.
        var resolved: Bool { self != .pending && self != .needsProof }

        /// Whether the money is still inside a pool. A decline does NOT take
        /// it out — a declined deposit sits there until it is reclaimed, which
        /// is exactly why the two are different states and why the reclaim is
        /// worth landing at all.
        var inPool: Bool { self != .reclaimed }
    }

    /// The tag vocabulary, as strings — the set `retag` strips before writing a
    /// new state, so a row always carries exactly one and the card can never
    /// double-count a deposit that changed its mind.
    static let states: [String] = State.allCases.map(\.rawValue)

    /// The `sourceRef` prefixes `PrivacyPoolsBridge` lands.
    ///
    /// Only the first is a DEPOSIT in the sense the card counts. `reclaimed`
    /// is the EXIT — a real row, and since 2026-08-17 also the evidence that
    /// resolves its own deposit (see `reclaimedLabels`) rather than a second
    /// thing to add up. The other two are ALERTS about a deposit that is
    /// already counted — landing one is how the person hears the news, and
    /// counting it would report a cleared deposit twice, once as itself and
    /// once as its own announcement. Excluded by construction rather than by
    /// remembering.
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

    /// The deposit's ASP label, off a deposit ref, its status alert, or its
    /// ragequit — `PrivacyPoolsBridge` lands all three under the SAME label
    /// suffix (`depositPrefix + label`, `statusPrefix + label`,
    /// `reclaimedPrefix + label`), which is what lets this card join "when it
    /// landed" to "when we saw it resolve" and to "when it came back out"
    /// without a new field or a second read. Nil for a ref shape no prefix
    /// names.
    static func label(ref: String?) -> String? {
        guard let ref else { return nil }
        for prefix in [depositPrefix, statusPrefix, reclaimedPrefix]
        where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
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
        /// `Thing.priceCurrency` — the pool's token symbol, stamped at landing
        /// (2026-08-17). Nil for every deposit that landed before that, and
        /// for a pool this build's table doesn't name (those land titled
        /// "crypto" and must never be bucketed under an invented symbol).
        let asset: String?
        /// `Thing.priceValue` — the deposit's size in that token's own units.
        /// Read as DATA and never parsed back out of `transferAmount`, which
        /// is a rounded display string whose thousands separator is
        /// locale-dependent (`GnosisPayRoomSource`'s rule).
        let amount: Double?
        let at: Date

        init(ref: String?, tags: [String], asset: String? = nil,
             amount: Double? = nil, at: Date) {
            self.ref = ref
            self.tags = tags
            self.asset = asset
            self.amount = amount
            self.at = at
        }
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

    /// What a legend row NAMES, and therefore what tapping it opens
    /// (2026-08-26, prd §486).
    ///
    /// A state is not the only thing the legend can be about. An untagged
    /// deposit is a real slice of this room — it is the GAP the split bar
    /// deliberately leaves — and until this existed it was said only in a
    /// footnote clause, so the one unlabelled part of the drawing could be
    /// decoded only by reading a line of tertiary text several blocks below
    /// it. It gets a legend row of its own now, in the same colour the bar's
    /// track is drawn in, which is what makes the gap self-explaining.
    enum Slice: Equatable, Hashable, Identifiable {
        case state(State)
        /// Deposits carrying no state tag at all — never assumed pending.
        case unknown

        var id: String {
            switch self {
            case .state(let state): return state.rawValue
            case .unknown:          return "Unknown"
            }
        }
    }

    /// One row of the legend: a slice, how many deposits are in it, and how
    /// long the oldest of them has been there.
    struct LegendRow: Identifiable, Equatable {
        var id: String { slice.id }
        let slice: Slice
        let count: Int
        let oldestAt: Date?
    }

    /// What one asset still has sitting in the pools (2026-08-17).
    ///
    /// Deposits only, and only ones still IN — a reclaimed deposit is money
    /// back in the wallet and counting it here would state a shielded balance
    /// that isn't shielded.
    struct Holding: Identifiable, Equatable {
        var id: String { symbol }
        let symbol: String
        /// How many of this asset's deposits are in the pools.
        let deposits: Int
        /// How many of those are still open with the screener.
        let waiting: Int
        /// Sum of `amount` across them — nil unless EVERY deposit counted
        /// here carried a readable one. `RailgunRoom.Token`'s all-or-nothing
        /// rule: a partial sum presented as a total is the failure this stays
        /// silent to avoid, and the card falls back to stating the count.
        let amount: Double?
    }

    /// How much cover one asset's deposits have (2026-08-17) — the anonymity
    /// set they hide in, as a NUMBER rather than §228's frozen sentence.
    ///
    /// `current` is the pool's live `acceptedDepositsCount`, read at most once
    /// a day by the bridge. `atLanding` is the same count snapshotted when the
    /// person's OLDEST deposit in that pool landed, so the pair can state
    /// growth — the one genuinely good piece of news this seat can deliver
    /// that nothing else reports, since a set that grows makes a deposit
    /// already made MORE private without anybody doing anything.
    ///
    /// `atLanding` is nil for anyone whose deposits predate the snapshot
    /// store, and then the line simply states the current set and no growth.
    struct Cover: Equatable {
        let symbol: String
        let current: Int
        let atLanding: Int?
    }

    /// Ranked — see `ordered`. Only states with at least one deposit appear, so
    /// a card never draws an empty segment.
    let segments: [Segment]
    /// Deposits carrying no state tag at all. Counted, never assumed pending.
    let untagged: Int
    /// Ragequit rows whose deposit is NOT in this room — see
    /// `reclaimedLabels`. A matched one is not counted here at all; it turns
    /// its own deposit `.reclaimed` and is reported there, once.
    let unattachedReclaims: Int
    /// The newest deposit, for the idle clause. Over deposits only: an alert
    /// row is stamped when we polled, not when anything was deposited.
    let newest: Date?
    /// The MEDIAN days between a deposit landing and this device observing
    /// its status alert (2026-08-11) — see `compose` for how it's paired,
    /// and the type doc for why it's a real but partial sample rather than a
    /// claim about the screener in general. Nil when no deposit has both
    /// ends observed yet.
    let reviewDays: Int?
    /// What is still in the pools, by asset, ranked — see `orderedHoldings`.
    let holdings: [Holding]
    /// Deposits still in the pools whose asset or size could not be read.
    /// Counted and named, never folded into a holding under a guessed symbol.
    let unpriced: Int
    /// Cover for the leading holding's asset, when the bridge has a reading.
    let cover: Cover?

    /// Below this there is nothing a card can say that the row does not.
    static let minimumDeposits = 1

    /// The card names at most this many assets; the rest are counted in the
    /// shielded note rather than silently dropped (`RailgunRoomSource.rowCap`).
    static let holdingCap = 3

    /// Every deposit the card knows about, tagged or not, in or out.
    var deposits: Int { segments.reduce(0) { $0 + $1.count } + untagged }

    /// Deposits still in review — the number this card exists to state.
    var waiting: Int {
        segments.filter { !$0.state.resolved }.reduce(0) { $0 + $1.count }
    }

    /// Deposits whose money is still inside a pool. Untagged ones count: we
    /// have no evidence they came out, and a ragequit would have said so.
    var inPools: Int {
        segments.filter { $0.state.inPool }.reduce(0) { $0 + $1.count } + untagged
    }

    /// The one deposit state that needs the person, if any.
    var needsYou: Segment? { segments.first { $0.state.needsYou } }

    /// The state whose money is sitting in a pool waiting for the person to
    /// take it back out. An errand like `needsYou`, and the second of the two
    /// slices that light the scope's dot — see `PrivacyPoolsSection.attention`
    /// for why being in review is not one.
    var needsReclaim: Segment? { segments.first { $0.state == .declined } }

    var lead: Segment? { segments.first }

    var leadHolding: Holding? { holdings.first }

    /// A room with no deposits at all. A reclaim-only room still draws — the
    /// card can honestly say everything came back out, which is a real standing
    /// and the row list alone does not add it up.
    var isEmpty: Bool {
        deposits < PrivacyPoolsRoom.minimumDeposits && unattachedReclaims == 0
    }

    // MARK: - Composing

    static func compose(rows sightings: [Sighting],
                        covers: [Cover] = []) -> PrivacyPoolsRoom {
        // Every label this room has seen come back OUT. Built in full before
        // any deposit is placed, because a ragequit row can sort either side
        // of the deposit it undoes and a single pass would place a deposit
        // before learning its fate.
        let reclaimed = reclaimedLabels(sightings)

        var counts: [State: Int] = [:]
        var oldestByState: [State: Date] = [:]
        var untagged = 0, attachedReclaims = 0, reclaimRows = 0, unpriced = 0
        var newest: Date?
        var byAsset: [String: (deposits: Int, waiting: Int, sum: Double, complete: Bool)] = [:]
        // Label → when the deposit landed, and label → when this device saw
        // its STATUS alert (approved/declined only — never the poi alert,
        // which isn't a resolution). Both keyed the same way `retag` and
        // `landDeposits` already key them, so no new read is needed to pair
        // them; see `compose`'s reviewDays clause below.
        var depositAt: [String: Date] = [:]
        var resolvedAt: [String: Date] = [:]

        for sighting in sightings {
            switch row(ref: sighting.ref, tags: sighting.tags) {
            case .deposit(let tagged):
                if newest == nil || sighting.at > newest! { newest = sighting.at }
                let label = label(ref: sighting.ref)
                if let label { depositAt[label] = sighting.at }
                // EVIDENCE BEATS THE RECORD. A ragequit row for this label is
                // proof the money came back out; the tag is only a note the
                // bridge left. They agree for anything landed after
                // 2026-08-17, and where they disagree — a deposit tagged
                // `Declined` months ago and reclaimed the same week — the
                // proof is right and the note is stale.
                let out = label.map { reclaimed.contains($0) } ?? false
                if out { attachedReclaims += 1 }
                let state: State? = out ? .reclaimed : tagged
                if let state {
                    counts[state, default: 0] += 1
                    if oldestByState[state] == nil || sighting.at < oldestByState[state]! {
                        oldestByState[state] = sighting.at
                    }
                } else {
                    untagged += 1
                }
                // Holdings count what is still IN. An untagged deposit counts
                // (nothing says it left), a reclaimed one never does.
                guard state?.inPool ?? true else { continue }
                guard let asset = sighting.asset, !asset.isEmpty else {
                    unpriced += 1
                    continue
                }
                var bucket = byAsset[asset] ?? (0, 0, 0, true)
                bucket.deposits += 1
                if !(state?.resolved ?? false) { bucket.waiting += 1 }
                if let amount = sighting.amount { bucket.sum += amount }
                else { bucket.complete = false }
                byAsset[asset] = bucket
            case .reclaimed:
                reclaimRows += 1
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
        let holdings = byAsset.map {
            Holding(symbol: $0.key, deposits: $0.value.deposits,
                    waiting: $0.value.waiting,
                    amount: $0.value.complete ? $0.value.sum : nil)
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

        let ranked = orderedHoldings(holdings)
        return PrivacyPoolsRoom(
            segments: ordered(segments),
            untagged: untagged,
            // Only the ORPHANS. A ragequit that found its deposit is already
            // reported as that deposit's state, and counting it here too is
            // the double-count this room refuses everywhere else.
            unattachedReclaims: max(reclaimRows - attachedReclaims, 0),
            newest: newest,
            reviewDays: medianDays(durations),
            holdings: ranked,
            unpriced: unpriced,
            cover: cover(for: ranked.first, in: covers))
    }

    /// Every label with a ragequit row — the deposits this room can PROVE came
    /// back out.
    ///
    /// This is what closes §228's loop. Before it, a declined deposit that was
    /// then reclaimed kept its `Declined` tag for life, so `rank` went on
    /// putting it at the top of the card with "reclaim it to your wallet" —
    /// telling the person to do a thing they had already done, permanently, on
    /// the one card whose job is to say what still needs them.
    static func reclaimedLabels(_ sightings: [Sighting]) -> Set<String> {
        var out: Set<String> = []
        for sighting in sightings {
            guard case .reclaimed? = row(ref: sighting.ref, tags: sighting.tags),
                  let label = label(ref: sighting.ref) else { continue }
            out.insert(label)
        }
        return out
    }

    /// The cover reading for the asset the card is about to lead with, or nil.
    ///
    /// ONE asset, deliberately. Several cover lines would be several different
    /// pools' set sizes stacked up, which reads as one aggregate privacy
    /// figure and is not one — the pools are separate sets and a deposit hides
    /// only in its own.
    static func cover(for holding: Holding?, in covers: [Cover]) -> Cover? {
        guard let holding else { return nil }
        return covers.first { $0.symbol == holding.symbol }
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
    ///   4 — proof required: only you can move this, and nothing moves until
    ///       you do.
    ///   3 — declined: the money needs reclaiming, but the decision is made.
    ///   2 — pending: waiting on somebody else.
    ///   1 — cleared: the good outcome, and the one that needs nothing.
    ///   0 — reclaimed: over, and the money is already back in the wallet.
    ///
    /// Deliberately NOT by count. A single deposit stuck on proof outranks
    /// forty that cleared, because the forty need nothing from anybody and the
    /// one is the entire reason to look. Ranking by size would bury it exactly
    /// on the accounts that use this seat most.
    static func rank(_ state: State) -> Int {
        switch state {
        case .needsProof: return 4
        case .declined:   return 3
        case .pending:    return 2
        case .cleared:    return 1
        case .reclaimed:  return 0
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

    /// Most deposits first, then symbol — TOTAL, for the reason `ordered` is.
    /// Deliberately NOT by amount: amounts in different tokens do not compare,
    /// so sorting by them would rank 0.4 ETH below 500 USDC and imply a
    /// conversion this room refuses to make.
    static func orderedHoldings(_ holdings: [Holding]) -> [Holding] {
        holdings.sorted { a, b in
            if a.deposits != b.deposits { return a.deposits > b.deposits }
            return a.symbol < b.symbol
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
        case .reclaimed:  return String(localized: "back in your wallet")
        }
    }

    static func segmentLine(_ segment: Segment) -> String {
        String(localized: "\(segment.count) \(meaning(segment.state))")
    }

    /// The legend's trailing text (2026-08-17): what this state means, plus
    /// how long its oldest deposit has been waiting when that is worth saying.
    ///
    /// The headline already carries the wait for the state it leads with;
    /// this puts it on the OTHER open states too, which is where the useful
    /// comparison lives — "3 in review · oldest 4 days" beside "1 waiting on
    /// your proof · oldest 22 days" says which one has actually gone quiet,
    /// and no arrangement of counts alone can.
    static func legendLine(_ segment: Segment, now: Date = .now) -> String {
        guard let wait = waitLabel(segment, now: now) else { return segmentLine(segment) }
        return String(localized: "\(segmentLine(segment)) · \(wait)")
    }

    /// Below this the wait isn't worth naming — a deposit a few hours into
    /// review reading "waited 0 days" is noise, not news.
    static let noteworthyWaitDays = 3

    /// "9 days" for the legend's trailing slot (2026-08-17), empty under
    /// `noteworthyWaitDays` and for any state nobody is waiting on. A cleared
    /// or reclaimed deposit finished waiting, and how long a decline took to
    /// arrive is not the fact that matters once it has.
    static func waitLabel(_ segment: Segment, now: Date = .now) -> String? {
        guard !segment.state.resolved, let oldestAt = segment.oldestAt else { return nil }
        let waited = days(from: oldestAt, to: now)
        guard waited >= noteworthyWaitDays else { return nil }
        return String(localized: "oldest \(waited) days")
    }

    /// The legend, top to bottom (2026-08-26, prd §486): every state that has
    /// a deposit, in the card's own ranked order, then the untagged ones.
    ///
    /// Unknown goes LAST and is never ranked among the states, because it is
    /// not a verdict — it is the absence of one, and putting it in `rank`'s
    /// ladder would have this card assert where it sits relative to a decline.
    static func legendRows(_ room: PrivacyPoolsRoom) -> [LegendRow] {
        var rows = room.segments.map {
            LegendRow(slice: .state($0.state), count: $0.count, oldestAt: $0.oldestAt)
        }
        if room.untagged > 0 {
            rows.append(LegendRow(slice: .unknown, count: room.untagged, oldestAt: nil))
        }
        return rows
    }

    /// A legend row's leading word. The states spell themselves — the raw
    /// values ARE the bridge's own tags — and the absence of one is named
    /// plainly rather than left blank.
    static func name(_ slice: Slice) -> String {
        switch slice {
        case .state(let state): return state.rawValue
        case .unknown:          return String(localized: "Unknown")
        }
    }

    /// The legend's trailing text for any row.
    ///
    /// Forwards to the `Segment` form for a real state, so there is exactly
    /// one place that decides what a state means and how its wait is worded.
    static func legendLine(_ row: LegendRow, now: Date = .now) -> String {
        switch row.slice {
        case .state(let state):
            return legendLine(Segment(state: state, count: row.count, oldestAt: row.oldestAt),
                              now: now)
        case .unknown:
            return unknownLine(row.count)
        }
    }

    /// "1 deposit's status is unknown".
    ///
    /// This clause used to live in the footnote, several blocks below the bar
    /// whose gap it explained. It is the legend's own row now — same words,
    /// beside the thing it is about. It is NOT politeness: a deposit this card
    /// cannot place is missing from every segment above it, and a standing
    /// that silently omits rows is the failure the import drop counters exist
    /// to prevent, one room over.
    static func unknownLine(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 deposit's status is unknown")
            : String(localized: "\(count) deposits' status is unknown")
    }

    /// "— the oldest has waited 9 days" (2026-08-11), appended to a headline
    /// that is already naming a state someone is WAITING on. Silent under
    /// `noteworthyWaitDays`, and silent for a `nil` segment (the `.declined`,
    /// `.cleared` and `.reclaimed` headline branches never call this).
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
            // a room of pre-§311 deposits, and a room whose only rows are
            // ragequits whose deposits we never held.
            if room.deposits > 0 {
                return String(localized: "\(depositsLabel(room.deposits)) in Privacy Pools")
            }
            return room.unattachedReclaims == 1
                ? String(localized: "1 deposit reclaimed — nothing shielded")
                : String(localized: "\(room.unattachedReclaims) deposits reclaimed — nothing shielded")
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
        case .reclaimed:
            // Every deposit is out. Nothing here needs anybody, so the
            // headline states the standing rather than an action.
            return lead.count == 1
                ? String(localized: "Your deposit is back in your wallet")
                : String(localized: "All \(lead.count) deposits are back in your wallet")
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
        // Said before the review clauses on purpose: once everything is out,
        // whether its review finished is no longer the interesting fact.
        if room.inPools == 0 {
            return String(localized: "All of it has been taken back out")
        }
        // NOTHING IS TAGGED AT ALL, so nothing can be said about the screener.
        // Without this the `waiting == 0` clause below fires — `waiting` counts
        // segments, and a room of pre-§311 deposits has none — and a room whose
        // every deposit's standing is unrecorded announced "Every review is
        // finished": the exact claim-without-evidence the untagged rule exists
        // to prevent, made in the note directly under a headline that had just
        // correctly declined to make it (2026-08-26, prd §486).
        if room.segments.isEmpty {
            return String(localized: "Where these stand isn't recorded")
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

    // MARK: - What's in the pools

    /// "0.44 ETH" — plain units, not `.formatted(.currency())`: a token symbol
    /// is not an ISO 4217 code. Self-contained (not `WalletIngest.format`) so
    /// this file stays Foundation-only.
    ///
    /// `mask` is the §374 hide-balances string, PASSED IN rather than read,
    /// for the reason `RailgunRoom.amountText` states: this file cannot reach
    /// `BalancePrivacy`. The SYMBOL survives the mask — a hidden line still
    /// says which asset is in there, which is the shape §374 rule 3 keeps.
    static func amountText(_ amount: Double, symbol: String, mask: String? = nil) -> String {
        guard let mask else {
            let formatted = amount.formatted(.number.precision(.fractionLength(0...4)))
            return "\(formatted) \(symbol)"
        }
        return "\(mask) \(symbol)"
    }

    /// One asset's line: its size when every deposit behind it is readable,
    /// otherwise a bare count. A count of deposits is not a balance, so the
    /// fallback is unaffected by `mask`.
    static func holdingText(_ holding: Holding, mask: String? = nil) -> String {
        if let amount = holding.amount {
            return amountText(amount, symbol: holding.symbol, mask: mask)
        }
        return holding.deposits == 1
            ? String(localized: "1 \(holding.symbol) deposit")
            : String(localized: "\(holding.deposits) \(holding.symbol) deposits")
    }

    /// "0.44 ETH · 500 USDC in the pools" — nil when nothing is in there or no
    /// asset could be read at all.
    ///
    /// Assets are listed side by side and NEVER summed: 0.44 ETH and 500 USDC
    /// have no common unit, and the one figure that would combine them is a
    /// dollar total this room has no price to compute and no business
    /// inventing. Capped at `holdingCap`; the remainder is named in the
    /// shielded note rather than dropped.
    static func holdingsLine(_ room: PrivacyPoolsRoom, mask: String? = nil) -> String? {
        let shown = room.holdings.prefix(holdingCap)
        guard !shown.isEmpty else { return nil }
        let parts = shown.map { holdingText($0, mask: mask) }
        return String(localized: "\(parts.joined(separator: " · ")) in the pools")
    }

    // MARK: - Cover

    /// "3,900" from 3,947, "12" from 12 — two significant figures, grouped.
    ///
    /// The exact count is noise and the ORDER OF MAGNITUDE is the privacy
    /// fact, which is also why `coverLine` compares ROUNDED values before it
    /// will claim growth. `PrivacyPoolsBridge` calls this for the per-deposit
    /// sentence it stores, so the number on the card and the number in the
    /// sheet are rounded by one function and cannot disagree.
    static func roundedSet(_ n: Int) -> String {
        guard n >= 100 else { return "\(n)" }
        let digits = String(n).count
        let unit = Int(pow(10.0, Double(digits - 2)))
        let rounded = (n / unit) * unit
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    /// "Your ETH hides among about 3,900 accepted deposits — up from 2,400
    /// when you first deposited." Nil when there is no reading.
    ///
    /// Growth is stated ONLY when the two ROUNDED figures differ. At two
    /// significant figures a set that moved from 3,947 to 3,961 renders as
    /// "up from 3,900 to 3,900", which reads as a broken sentence rather than
    /// as the honest "no material change" it actually is.
    ///
    /// A set that SHRANK is never narrated. `acceptedDepositsCount` going down
    /// means deposits left the tree, which is real, but "your cover shrank" on
    /// a privacy screen is alarming enough that it should be said only by
    /// something that knows why — and this reading does not.
    static func coverLine(_ cover: Cover?) -> String? {
        guard let cover, cover.current > 0 else { return nil }
        let now = roundedSet(cover.current)
        guard let landed = cover.atLanding, landed > 0, cover.current > landed,
              roundedSet(landed) != now else {
            return String(localized: "Your \(cover.symbol) hides among about \(now) accepted deposits.")
        }
        return String(localized: "Your \(cover.symbol) hides among about \(now) accepted deposits — up from \(roundedSet(landed)) when you first deposited.")
    }

    /// The one quiet line under what's SHIELDED: the deposits whose size this
    /// card could not read, and the assets it had no room to name.
    ///
    /// Half of what used to be a single `footnote`, which joined up to six
    /// clauses with `·` into a paragraph of tertiary text under the whole card
    /// (2026-08-26, prd §486). Nothing is dropped — every clause moved to the
    /// scope it is about, which is the difference between a footnote and a
    /// caption. These two are the money line's own caveats, and they belong
    /// beside the money line: `unpriced` and the holdings overflow are both
    /// "this figure does not cover everything", said where the figure is.
    static func shieldedNote(_ room: PrivacyPoolsRoom) -> String? {
        var parts: [String] = []
        if room.unpriced > 0 {
            parts.append(room.unpriced == 1
                         ? String(localized: "1 deposit's size is unknown")
                         : String(localized: "\(room.unpriced) deposits' sizes are unknown"))
        }
        let overflow = room.holdings.count - holdingCap
        if overflow > 0 {
            parts.append(String(localized: "\(overflow) more assets"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The one quiet line under the room's own events: reclaims that arrived
    /// without a deposit we hold, how long review has taken HERE, and how long
    /// the room has been still.
    ///
    /// The other half of the old `footnote`. All three are facts about what
    /// has HAPPENED rather than about what is standing, which is exactly what
    /// this scope is — a review time is the observed gap between two events,
    /// and an idle clause is the absence of one.
    ///
    /// `reviewDays` is only what THIS device has watched resolve — never a
    /// claim about 0xBow's screener in general. See `compose`'s own note.
    static func activityNote(_ room: PrivacyPoolsRoom, now: Date = .now) -> String? {
        var parts: [String] = []
        if room.unattachedReclaims > 0 {
            parts.append(room.unattachedReclaims == 1
                         ? String(localized: "1 reclaimed before you watched")
                         : String(localized: "\(room.unattachedReclaims) reclaimed before you watched"))
        }
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
