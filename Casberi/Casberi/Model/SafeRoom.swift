import Foundation

/// THE SAFE ROOM'S HEAD (2026-08-11, prd §349 amendment) — the signature
/// queue as rings, ranked by who it's actually waiting on.
///
/// Safe is the only wallet-riding seat where OTHER PEOPLE act on your behalf
/// and you wait on them (`SafeQueueCard`'s own framing, one screen deeper).
/// A plain list of "N of M signatures collected" rows answers "what's
/// pending" one row at a time; this answers the standing question — is
/// anything waiting on ME right now, and how long has the oldest thing been
/// sitting there.
///
/// ## The three states, and why two of them are not "pending" (2026-08-17)
///
/// The first cut had one axis — `yourTurn` — and read every open transaction
/// as a signature the queue was still waiting for. Two states hide inside
/// that and both were being reported wrongly:
///
///   - **Fully signed.** `have >= required` means the threshold is MET and
///     nothing more can be signed; what it waits on is an EXECUTION. Counting
///     it into "N signatures pending — waiting on others" is false twice over
///     (nobody's signature is pending, and it isn't the others who are
///     holding it up). §238 already named this moment — "Fully signed —
///     ready to execute" — for the delight toast, and then the head that
///     shipped later couldn't say it.
///   - **Your signature, when it is genuinely missing.** `yourTurn` is set
///     from `!hasSigned(owner)` alone, with no check that the threshold isn't
///     already met WITHOUT you: a 2-of-3 whose other two owners both signed
///     said "your signature is needed", ranked it first, and fired a lock
///     screen alarm for a transaction that needs nothing from you at all.
///     `awaitsYou` is the honest form and is what every count here uses.
///
/// Ranking keeps the file's original doctrine — the thing only YOU can
/// unblock leads — so `awaitsYou` outranks ready: any owner can execute an
/// already-signed transaction, and only you can add your own signature.
///
/// ## Rival transactions (2026-08-17)
///
/// A Safe executes exactly ONE transaction per nonce, so two live at one
/// position means a signature spent on the loser is spent for nothing (§238,
/// which surfaced this in the sheet and could not surface it here because the
/// tracking store carried no nonce). Rivals are drawn ADJACENT — `ordered`
/// pulls a contested sibling up beside its best-ranked partner — and said
/// out loud in `stateNote`, because a pair that reads as two unrelated rings
/// is worse than not drawing them: it invites exactly the wasted signature.
/// Stated plainly and never as an alarm: it is how Safes work, not a sign
/// anything is wrong.
///
/// ## It spends nothing
///
/// Every fact here comes off `SafeBridge.pendingSnapshot()` — the SAME
/// tracking store `SafeBridge.sync` already keeps to know when a pending
/// transaction resolves (its loop-closer, prd §349's own amendment (5)/(8)),
/// upserted with `have`/`required`/`yourTurn`/`nonce`/`submittedAt`/a cached
/// description every pass regardless of whether a new `Thing` landed. No
/// request, no new `Thing` property, no CloudKit deploy — the
/// `StripeRoom`/`CursorRoom` contract.
///
/// ## What it may NOT draw: a live recheck
///
/// The counts here are AS OF THE LAST SYNC PASS, not a fresh read — same as
/// every sibling room head. A tap opens the real thing, whose sheet
/// (`SafeQueueCard`) does the live re-check this card deliberately doesn't
/// pay for.
///
/// ## What it may NOT draw: the full signer roster
///
/// `SafeQueueCard` already draws every owner's face, lit or dim — that is
/// SHEET detail, reached by a tap on a specific transaction. This card is a
/// glance across every Safe at once; drawing a face row per pending item
/// would be the sheet's own card duplicated N times at 1/3 the size.
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can
/// compile it WHOLE and unmodified. Everything touching `Thing`/`SafeBridge`
/// lives in `SafeRoomSource`.
struct SafeRoom: Equatable {

    // MARK: - What a row is

    /// One currently-open pending transaction, reduced to what the card
    /// reads.
    struct Entry: Identifiable, Equatable {
        var id: String { ref }
        let ref: String
        let safeAddress: String
        let have: Int
        let required: Int
        /// Raw from the bridge: this signer hasn't signed yet. NOT the same
        /// question as "does this need you" — see `awaitsYou`, which is what
        /// every count and every sentence on this card uses.
        let yourTurn: Bool
        /// Safe's own `submissionDate` for the transaction — nil only when
        /// the wire didn't carry one. Real waiting time, not app-observed.
        let submittedAt: Date?
        /// "a transfer of 1,500 USDC to alice.eth" — `SafeBridge.describe`'s
        /// own rendering, cached at tracking time so this card never
        /// recomputes it.
        let descriptionText: String
        /// The Safe's own nonce for this transaction — the queue POSITION,
        /// which is what makes two transactions rivals. Nil when the wire
        /// didn't carry one, and a nil nonce is never a rival: an unknown
        /// position cannot be proven to collide with anything.
        let nonce: Int?

        init(ref: String, safeAddress: String, have: Int, required: Int, yourTurn: Bool,
             submittedAt: Date?, descriptionText: String, nonce: Int? = nil) {
            self.ref = ref
            self.safeAddress = safeAddress
            self.have = have
            self.required = required
            self.yourTurn = yourTurn
            self.submittedAt = submittedAt
            self.descriptionText = descriptionText
            self.nonce = nonce
        }

        /// The threshold is met — nothing further can be signed, and what
        /// this waits on is an execution. `required > 0` guards the unread
        /// case: a transaction whose `confirmationsRequired` didn't parse
        /// arrives as 0/0, and reading that as "fully signed" would report
        /// a transaction ready to execute on no evidence at all.
        var isReady: Bool { required > 0 && have >= required }

        /// Your signature is genuinely the missing one: you haven't signed
        /// AND the threshold isn't already met without you.
        var awaitsYou: Bool { yourTurn && !isReady }

        /// Identity of a queue POSITION — the Safe plus its nonce. Two
        /// entries sharing one are rivals; only one of them can ever execute.
        var nonceKey: String? {
            nonce.map { "\(safeAddress.lowercased())#\($0)" }
        }
    }

    /// One detected Safe that has at least one module enabled — funds movable
    /// WITHOUT a signature.
    struct ModuleSafe: Equatable {
        /// A name when the address book or Farcaster knows one, else a short
        /// hex — `WalletIngest.knownLabel`'s own chain, resolved in
        /// `SafeRoomSource` (this file never touches an address book).
        let label: String
        let count: Int
    }

    /// Ranked — see `ordered`.
    let entries: [Entry]
    /// Every Safe this app has ever confirmed real for the watched wallets
    /// (`SafeBridge.detectedCount()`) — the standing inventory this card
    /// reports on, independent of whether any of them currently has
    /// something pending.
    let safeCount: Int
    /// The Safes carrying enabled modules, named — the highest-stakes fact
    /// this bridge can state (`SafeBridge`'s own top-of-file doc). Named
    /// rather than merely counted since 2026-08-17: with more than one Safe
    /// watched, "1 module can move funds without a signature" tells you a
    /// drain is possible and not WHERE, which is the one thing you need to
    /// go do something about it.
    let moduleSafes: [ModuleSafe]
    /// Queue positions with more than one live transaction on them. Derived
    /// once in `compose` rather than recomputed per row, since the card asks
    /// per ring.
    let contestedKeys: Set<String>

    var moduleCount: Int { moduleSafes.reduce(0) { $0 + $1.count } }
    var pendingCount: Int { entries.count }
    /// Transactions whose missing signature is genuinely yours.
    var awaitsYouCount: Int { entries.filter(\.awaitsYou).count }
    /// Transactions fully signed and waiting only on an execution.
    var readyCount: Int { entries.filter(\.isReady).count }
    var lead: Entry? { entries.first }

    func isContested(_ entry: Entry) -> Bool {
        entry.nonceKey.map { contestedKeys.contains($0) } ?? false
    }
    var contestedCount: Int { entries.filter(isContested).count }

    /// Below this the card is not worth drawing: no Safe was ever detected
    /// at all, so there is nothing to report on, standing or pending.
    var isEmpty: Bool { safeCount == 0 }

    // MARK: - Composing

    static func compose(entries raw: [Entry], safeCount: Int,
                        moduleSafes: [ModuleSafe] = []) -> SafeRoom {
        let contested = contestedKeys(in: raw)
        return SafeRoom(entries: ordered(raw, contested: contested), safeCount: safeCount,
                        moduleSafes: moduleSafes, contestedKeys: contested)
    }

    /// Every queue position carrying more than one live transaction.
    static func contestedKeys(in entries: [Entry]) -> Set<String> {
        var counts: [String: Int] = [:]
        for entry in entries {
            guard let key = entry.nonceKey else { continue }
            counts[key, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    // MARK: - Ranking

    /// Your turn first (the thing only you can unblock), then fully-signed
    /// (anybody can execute it, so it ranks below the one that needs you
    /// specifically), then longest-waiting within each group, then the ref
    /// for stability when two entries carry the same or no `submittedAt` —
    /// TOTAL, the `PeerRoom.ordered`/`RailgunRoom.ordered` reasoning: a card
    /// that reshuffles between opens over identical data reads as broken.
    ///
    /// Rivals are then pulled adjacent: a contested sibling follows its
    /// best-ranked partner immediately, so a pair reads as a pair. This is a
    /// stable regroup over an already-total order, so it stays deterministic.
    static func ordered(_ entries: [Entry]) -> [Entry] {
        ordered(entries, contested: contestedKeys(in: entries))
    }

    static func ordered(_ entries: [Entry], contested: Set<String>) -> [Entry] {
        let sorted = entries.sorted { a, b in
            if a.awaitsYou != b.awaitsYou { return a.awaitsYou && !b.awaitsYou }
            if a.isReady != b.isReady { return a.isReady && !b.isReady }
            let da = a.submittedAt ?? .distantPast
            let db = b.submittedAt ?? .distantPast
            if da != db { return da < db }
            return a.ref < b.ref
        }
        guard !contested.isEmpty else { return sorted }
        var out: [Entry] = []
        var placed = Set<String>()
        for entry in sorted where !placed.contains(entry.ref) {
            out.append(entry)
            placed.insert(entry.ref)
            guard let key = entry.nonceKey, contested.contains(key) else { continue }
            for sibling in sorted
            where sibling.nonceKey == key && !placed.contains(sibling.ref) {
                out.append(sibling)
                placed.insert(sibling.ref)
            }
        }
        return out
    }

    // MARK: - Words

    /// The one line at the top of the card. "Your turn" always leads when
    /// there is one — the shape of news nothing else in this app carries:
    /// somebody else is waiting on a decision only you can make. Fully-signed
    /// leads next, because it is an act rather than a wait.
    static func headline(_ room: SafeRoom) -> String {
        if room.awaitsYouCount > 0 {
            return room.awaitsYouCount == 1
                ? String(localized: "Your signature is needed on 1 transaction")
                : String(localized: "Your signature is needed on \(room.awaitsYouCount) transactions")
        }
        if room.readyCount > 0 {
            return room.readyCount == 1
                ? String(localized: "1 transaction is fully signed — ready to execute")
                : String(localized: "\(room.readyCount) transactions are fully signed — ready to execute")
        }
        if room.pendingCount > 0 {
            return room.pendingCount == 1
                ? String(localized: "1 signature pending — waiting on others")
                : String(localized: "\(room.pendingCount) signatures pending — waiting on others")
        }
        return room.safeCount == 1
            ? String(localized: "Nothing pending on your Safe")
            : String(localized: "Nothing pending across your \(room.safeCount) Safes")
    }

    /// The line under it — the module warning, when there is one. Nil rather
    /// than restating the headline's own count, the `RailgunRoom.note`
    /// shape: a second sentence earns its place only when it says something
    /// new.
    ///
    /// It NAMES the Safe once more than one is watched. A module is the one
    /// fact here that asks you to go and act, and an unnamed one sends you to
    /// check every Safe you have.
    static func note(_ room: SafeRoom) -> String? {
        let carriers = room.moduleSafes.filter { $0.count > 0 }
        guard !carriers.isEmpty else { return nil }
        let total = carriers.reduce(0) { $0 + $1.count }
        // More than one Safe carries modules: naming them all is a list, so
        // the count of Safes is the locating fact.
        if carriers.count > 1 {
            return String(localized:
                "\(total) modules across \(carriers.count) Safes can move funds without a signature")
        }
        // One Safe carries them, and it is the only one watched — there is
        // nothing to disambiguate, so the name would be noise.
        guard room.safeCount > 1, let only = carriers.first else {
            return total == 1
                ? String(localized: "1 module can move funds without a signature")
                : String(localized: "\(total) modules can move funds without a signature")
        }
        return total == 1
            ? String(localized: "1 module on \(only.label) can move funds without a signature")
            : String(localized: "\(total) modules on \(only.label) can move funds without a signature")
    }

    /// The third line: the highest-priority state fact the headline could not
    /// carry. Nil whenever the headline already covers everything, so this
    /// slot can never restate what is already on screen.
    ///
    /// Rivals outrank the ready count on purpose. A fully-signed transaction
    /// is discoverable from its own full ring; a nonce collision is visible
    /// nowhere else in this app, and the cost of not knowing is a signature
    /// spent on a transaction that can never execute.
    static func stateNote(_ room: SafeRoom) -> String? {
        if room.contestedCount > 1 {
            let groups = room.contestedKeys.count
            if groups > 1 {
                return String(localized:
                    "\(room.contestedCount) transactions contest \(groups) queue positions — only one of each can execute")
            }
            return String(localized:
                "\(room.contestedCount) transactions share a queue position — only one of them can execute")
        }
        // Ready is only ever news here when the headline led with your turn;
        // otherwise the headline said it already.
        guard room.awaitsYouCount > 0, room.readyCount > 0 else { return nil }
        return room.readyCount == 1
            ? String(localized: "1 other is fully signed — ready to execute")
            : String(localized: "\(room.readyCount) others are fully signed — ready to execute")
    }

    /// "today" / "1 day" / "N days" — how long a pending entry has waited,
    /// off Safe's own `submissionDate`. "waiting" when the wire carried none
    /// — never a fabricated duration.
    static func waitLabel(_ entry: Entry, now: Date = .now) -> String {
        guard let submittedAt = entry.submittedAt else { return String(localized: "waiting") }
        let days = max(0, Int(now.timeIntervalSince(submittedAt) / 86_400))
        if days == 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "1 day") }
        return String(localized: "\(days) days")
    }

    /// The card draws at most this many entries; the rest are counted in
    /// the footnote rather than silently dropped.
    static let rowCap = 3

    /// The quiet line at the foot: pending entries not drawn.
    static func footnote(_ room: SafeRoom, drawn: Int) -> String? {
        let hidden = room.entries.count - drawn
        guard hidden > 0 else { return nil }
        return hidden == 1 ? String(localized: "1 more pending")
                           : String(localized: "\(hidden) more pending")
    }

    // MARK: - Elsewhere

    /// How long the oldest transaction genuinely waiting on YOU has sat, in
    /// whole days — nil when nothing awaits you, or when none of the ones
    /// that do carried a submission date to measure from.
    ///
    /// Read by the Today brief (`TodayBrief`) and nothing on this card. A
    /// your-turn signature notifies ONCE, at landing, and §306's 36-hour news
    /// window means it can never notify again — so a request that has sat for
    /// a week has no surface that re-raises it. The brief is the honest one:
    /// it is a thing you open, not a buzz, so restating a standing obligation
    /// there is a recap rather than a second alarm.
    static func stuckDays(_ room: SafeRoom, now: Date = .now) -> Int? {
        let dates = room.entries.filter(\.awaitsYou).compactMap(\.submittedAt)
        guard let oldest = dates.min() else { return nil }
        let days = Int(now.timeIntervalSince(oldest) / 86_400)
        return days > 0 ? days : nil
    }

    /// The brief's own sentence for the fact above. Nil below `stuckFloor`,
    /// which is what keeps this from being a daily repeat of yesterday's
    /// notification: a signature asked for this morning is not stuck.
    static let stuckFloor = 3

    /// No singular branch, and that is not an oversight: `stuckFloor` is 3, so
    /// a one-day form here would be unreachable code claiming to be a case.
    /// A description that never made it into the tracking store falls back to
    /// the generic noun rather than leaving a sentence with a hole in it.
    static func stuckLine(_ room: SafeRoom, now: Date = .now) -> String? {
        guard let days = stuckDays(room, now: now), days >= stuckFloor,
              let entry = room.entries.first(where: \.awaitsYou)
        else { return nil }
        let subject = entry.descriptionText.isEmpty
            ? String(localized: "a pending transaction") : entry.descriptionText
        return String(localized: "Your signature has been waiting \(days) days on \(subject)")
    }
}
