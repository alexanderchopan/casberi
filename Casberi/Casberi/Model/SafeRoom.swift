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
        /// The owners still to sign, ALREADY NAMED — address-book name,
        /// Farcaster handle, else short hex, resolved by `SafeRoomSource`
        /// through the same `WalletIngest.knownLabel` chain every other Safe
        /// surface uses. Labels rather than addresses because this file is
        /// Foundation-only by design and must never reach the naming chain
        /// itself.
        ///
        /// EMPTY MEANS NOT KNOWN, never "nobody" — a pass that could not read
        /// the owner list leaves it empty, and every reader below falls back
        /// to the signature COUNT rather than claiming an empty roster.
        let waitingOn: [String]
        /// The Safe's own next-to-execute nonce, so this entry's `nonce`
        /// becomes a place in a queue rather than a bare number.
        let safeNonce: Int?

        init(ref: String, safeAddress: String, have: Int, required: Int, yourTurn: Bool,
             submittedAt: Date?, descriptionText: String, nonce: Int? = nil,
             waitingOn: [String] = [], safeNonce: Int? = nil) {
            self.ref = ref
            self.safeAddress = safeAddress
            self.have = have
            self.required = required
            self.yourTurn = yourTurn
            self.submittedAt = submittedAt
            self.descriptionText = descriptionText
            self.nonce = nonce
            self.waitingOn = waitingOn
            self.safeNonce = safeNonce
        }

        /// How many transactions must execute before this one can — the gap
        /// between this entry's queue position and the Safe's own next nonce.
        ///
        /// Nil when either number is unknown, and nil (not zero) is the right
        /// answer there: a blocked transaction that says nothing is a missing
        /// caption, while an unblocked one asserted from a number we do not
        /// have is a person told to go and execute something that cannot run.
        var blockedBy: Int? {
            guard let nonce, let safeNonce, nonce > safeNonce else { return nil }
            return nonce - safeNonce
        }

        /// The threshold is met AND nothing sits in front of it — the only
        /// state in which "ready to execute" is literally true.
        ///
        /// `isReady` deliberately does NOT fold this in: it answers "can any
        /// more signatures be added", which is what the ranking and the
        /// awaits-you arithmetic need, and which stays true whatever the
        /// queue does. This answers "may somebody go and send it", which is
        /// what the WORDS on screen promise.
        var isExecutable: Bool { isReady && blockedBy == nil }

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
    /// The Safes running a transaction GUARD, named (2026-09-07).
    ///
    /// The MIRROR of `moduleSafes` and drawn beside it. A module moves funds
    /// with NO signature; a guard sits in front of every transaction and can
    /// refuse them all — including, at the limit, the owner-management
    /// transaction that would remove it. `SafeBridge` has read this field
    /// since 2026-07-30 and only ever alerted when it CHANGED, so a guard set
    /// before this app first looked was invisible forever.
    ///
    /// **Not an alarm, and the copy must not make it one.** Running a guard is
    /// a normal, deliberate choice (a spending policy, an allowlist), and the
    /// person who set it knows they did. The reason to state it is that
    /// somebody reading this room should not have to remember.
    let guardSafes: [String]

    var moduleCount: Int { moduleSafes.reduce(0) { $0 + $1.count } }
    var guardCount: Int { guardSafes.count }
    var pendingCount: Int { entries.count }
    /// Transactions whose missing signature is genuinely yours.
    var awaitsYouCount: Int { entries.filter(\.awaitsYou).count }
    /// Transactions fully signed and waiting only on an execution.
    var readyCount: Int { entries.filter(\.isReady).count }
    /// Fully signed AND at the front of the queue — the ones somebody can
    /// actually go and send right now (2026-09-07).
    ///
    /// Split from `readyCount` because the headline PROMISES an action ("ready
    /// to execute") and a threshold met behind two earlier transactions cannot
    /// be acted on. `readyCount` keeps its old meaning for the RANKING, which
    /// is about whether more signatures can be added; this one carries the
    /// WORDS, which are about whether anybody can do anything.
    var executableCount: Int { entries.filter(\.isExecutable).count }
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
                        moduleSafes: [ModuleSafe] = [],
                        guardSafes: [String] = []) -> SafeRoom {
        let contested = contestedKeys(in: raw)
        return SafeRoom(entries: ordered(raw, contested: contested), safeCount: safeCount,
                        moduleSafes: moduleSafes, contestedKeys: contested,
                        guardSafes: guardSafes)
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
    /// WHICH TRANSACTIONS THE HEAD IS ABOUT — decided ONCE, read twice
    /// (prd §585).
    ///
    /// `headline` and `lede` both open on the same ladder (awaiting you, then
    /// ready, then pending), which is §349's trouble-leads rule: one signature
    /// needed from you outranks forty that are not. Spelling that ladder in
    /// both functions is how they drift into naming different transactions —
    /// and it is not hypothetical, it was caught the hour it was written.
    /// `wallet-rooms-selftest` mutates the ready rung's own condition to prove
    /// ready is ranked; with the ladder written twice that mutation edited the
    /// FIRST copy and the assertion, which reads `headline`, still passed. The
    /// harness reported its own guard as no longer testing anything.
    ///
    /// The rung's condition is deliberately NOT quoted in this comment: the
    /// mutation is a `sed` and prose above the code it edits is prose the
    /// `sed` edits instead (the comment-stripping lesson this repo has paid
    /// for six times, arriving here within the hour).
    enum Lead: Equatable {
        case awaitsYou(Int)
        case ready(Int)
        case pending(Int)
        case quiet
    }

    static func lead(_ room: SafeRoom) -> Lead {
        if room.awaitsYouCount > 0 { return .awaitsYou(room.awaitsYouCount) }
        if room.readyCount > 0 { return .ready(room.readyCount) }
        if room.pendingCount > 0 { return .pending(room.pendingCount) }
        return .quiet
    }

    /// THE LEDE (prd §585) — how many transactions are waiting, and on whom.
    ///
    /// Nil on the quiet state deliberately: "0" at the head rung on a Safe is
    /// a figure that reads as an alarm about nothing.
    static func lede(_ room: SafeRoom) -> RoomLede? {
        switch lead(room) {
        case .awaitsYou(let n):
            return RoomLede(figure: n.formatted(),
                            caption: String(localized: "waiting on your signature"),
                            numeric: Double(n))
        case .ready(let n):
            // Same rule as the headline: the caption may only promise an
            // action for transactions that are actually at the front.
            return RoomLede(figure: n.formatted(),
                            caption: room.executableCount > 0
                                ? String(localized: "fully signed, ready to execute")
                                : String(localized: "fully signed, waiting their turn"),
                            numeric: Double(n))
        case .pending(let n):
            return RoomLede(figure: n.formatted(),
                            caption: String(localized: "pending, waiting on others"),
                            numeric: Double(n))
        case .quiet:
            return nil
        }
    }

    static func headline(_ room: SafeRoom) -> String {
        switch lead(room) {
        case .awaitsYou(let n):
            return n == 1
                ? String(localized: "Your signature is needed on 1 transaction")
                : String(localized: "Your signature is needed on \(n) transactions")
        case .ready(let n):
            // "Ready to execute" is a promise somebody will act on, so it is
            // made only about transactions at the front of the queue. When
            // every fully-signed one sits behind an earlier transaction, the
            // headline says what is actually true instead.
            guard room.executableCount > 0 else {
                return n == 1
                    ? String(localized: "1 transaction is fully signed — waiting its turn in the queue")
                    : String(localized: "\(n) transactions are fully signed — waiting their turn in the queue")
            }
            return n == 1
                ? String(localized: "1 transaction is fully signed — ready to execute")
                : String(localized: "\(n) transactions are fully signed — ready to execute")
        case .pending(let n):
            return n == 1
                ? String(localized: "1 signature pending — waiting on others")
                : String(localized: "\(n) signatures pending — waiting on others")
        case .quiet:
            return room.safeCount == 1
                ? String(localized: "Nothing pending on your Safe")
                : String(localized: "Nothing pending across your \(room.safeCount) Safes")
        }
    }

    /// The line under it — the module warning, when there is one. Nil rather
    /// than restating the headline's own count: a second sentence earns its
    /// place only when it says something new. (`RailgunRoom.note` used to be
    /// the reference here and was DELETED 2026-08-26 for failing exactly this
    /// test — it restated in prose what that card's rows already drew.)
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

    /// The guard line — the standing fact, in the register a normal setting
    /// deserves.
    ///
    /// It NAMES the Safe on the same rule `note` uses: with more than one Safe
    /// watched, "a guard checks every transaction" says a thing is true and
    /// not where, which sends somebody to open all of them.
    ///
    /// Deliberately NOT tinted like the module line. A module is a way funds
    /// leave without a signature; a guard is a rule the owners chose. Drawing
    /// them in one colour would say they are one kind of news, and the module
    /// line would lose the urgency that is its whole point.
    static func guardNote(_ room: SafeRoom) -> String? {
        guard !room.guardSafes.isEmpty else { return nil }
        if room.guardSafes.count > 1 {
            return String(localized:
                "\(room.guardSafes.count) of your Safes run a guard that checks every transaction")
        }
        guard room.safeCount > 1, let only = room.guardSafes.first else {
            return String(localized: "A guard checks every transaction on this Safe")
        }
        return String(localized: "A guard checks every transaction on \(only)")
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
        // Only the SENDABLE ones are worth a second sentence: this slot exists
        // to tell somebody there is something to go and do, and a fully-signed
        // transaction stuck behind two others is not that.
        guard room.awaitsYouCount > 0, room.executableCount > 0 else { return nil }
        return room.executableCount == 1
            ? String(localized: "1 other is fully signed — ready to execute")
            : String(localized: "\(room.executableCount) others are fully signed — ready to execute")
    }

    /// What the row is ABOUT — `SafeBridge.describe`'s own rendering, cached
    /// at tracking time, else a plain noun.
    ///
    /// It exists as a function rather than a read of `descriptionText` at the
    /// call site because there are now TWO readers — the row title and
    /// `voiceLabel` — and a fallback spelled twice is a fallback that drifts.
    /// The noun is capitalized and article-less on purpose: it heads a row as
    /// a subject, and it still reads correctly mid-sentence in the VoiceOver
    /// list, where every other clause is a fragment too.
    static func subject(_ entry: Entry) -> String {
        entry.descriptionText.isEmpty
            ? String(localized: "Pending transaction") : entry.descriptionText
    }

    /// The entry's state, IN WORDS (2026-08-24).
    ///
    /// The card used to carry this in colour alone — `DS.tint` for your turn,
    /// `DS.confirm` for ready, tertiary for everything else, painted onto the
    /// wait caption. Three rings reading "3 days" in three tints are one ring
    /// in a greyscale screenshot, a PDF export, or to a red-green viewer, and
    /// the state is the more important of the two facts. So it is said, and
    /// then reinforced by the tint — §83's honesty rule applied to an
    /// encoding rather than to a control.
    ///
    /// **The waiting form NAMES PEOPLE since 2026-09-07, and until then could
    /// not.** This doc used to say the opposite — "the waiting form counts
    /// SIGNATURES, never people: this card holds no owner roster (that is
    /// `SafeQueueCard`'s, one screen deeper), so '2 others' would be a claim
    /// about who, made from a number that only says how many more" — and that
    /// reasoning was exactly right about the DATA available at the time. The
    /// claim was forbidden because the tracking store kept counts and no
    /// roster, so the only honest sentence was arithmetic.
    ///
    /// `SafeBridge.TrackEntry.unsignedOwners` now keeps the outstanding owners
    /// themselves, taken from the same `confirmations` array the counts come
    /// from, and `SafeRoomSource` names them through the same chain the sheet
    /// uses. So the claim is no longer made from a number — and §238's whole
    /// finding ("a Safe is the only object in this app where other people act
    /// on your behalf and you wait on them; the integer throws away the one
    /// thing a person needs, which is who to go ask") finally reaches the
    /// glance surface instead of only the sheet one tap deeper.
    ///
    /// The ARITHMETIC FORM IS NOT DELETED, and that is deliberate: an empty
    /// roster means the owner list did not read this pass, and falling back to
    /// the count is what keeps a failed read from rendering as "waiting on
    /// nobody". A transaction whose `confirmationsRequired` never parsed
    /// arrives as 0/0 and gets the bare word — the `isReady` guard's own
    /// reasoning, one rung down.
    static func stateLabel(_ entry: Entry) -> String {
        if entry.awaitsYou { return String(localized: "Your turn") }
        if entry.isReady {
            // FULLY SIGNED IS NOT THE SAME AS SENDABLE. A Safe executes one
            // transaction per nonce in order, so a threshold met at position
            // N+2 waits on the two in front of it — and "Ready to execute" on
            // that row is the honesty rule's dead control in sentence form:
            // it sends somebody to their Safe app to press a button that is
            // not there yet.
            if let blocked = entry.blockedBy {
                return blocked == 1
                    ? String(localized: "Fully signed — behind 1 earlier transaction")
                    : String(localized: "Fully signed — behind \(blocked) earlier transactions")
            }
            return String(localized: "Ready to execute")
        }
        let short = entry.required - entry.have
        guard entry.required > 0, short > 0 else { return String(localized: "Waiting") }
        // WHO, when we know who.
        if let named = waitingOnPhrase(entry) { return named }
        return short == 1
            ? String(localized: "1 more signature needed")
            : String(localized: "\(short) more signatures needed")
    }

    /// "Waiting on alice.eth" / "Waiting on alice.eth and 2 others" — the
    /// sentence §238 wanted at the head and could not have.
    ///
    /// **One name, then a count.** Naming two runs to "Waiting on alice.eth
    /// and bob.eth", which fits; naming three does not fit a row that also
    /// carries a position and a wait, and a list that truncates at a
    /// screen-width boundary is worse than a count that never does. So the
    /// FIRST outstanding owner is named and the rest are counted — and the
    /// first is chosen by the order `SafeRoomSource` hands them over, which is
    /// the Safe's own owner order, so it is stable between passes rather than
    /// rotating under a person watching one row.
    ///
    /// Nil whenever the roster is empty (not read this pass) — the caller
    /// falls back to the signature count, which is always true.
    static func waitingOnPhrase(_ entry: Entry) -> String? {
        let names = entry.waitingOn.filter { !$0.isEmpty }
        guard let first = names.first else { return nil }
        let others = names.count - 1
        if others == 0 { return String(localized: "Waiting on \(first)") }
        if others == 1 { return String(localized: "Waiting on \(first) and 1 other") }
        return String(localized: "Waiting on \(first) and \(others) others")
    }

    /// The queue POSITION, for a row that contests one — the pairing the card
    /// used to make with a 9pt glyph in a ring's corner, said instead.
    ///
    /// **The nonce is never grouped.** `String(localized: "position \(n)")`
    /// over an `Int` renders 1042 as "position 1,042" — a queue slot printed
    /// as a quantity, which is §375's own defect (a year set as "2,019") in a
    /// second place. Interpolating the already-formatted string is what keeps
    /// the separator out.
    static func positionLabel(_ entry: Entry) -> String? {
        guard let nonce = entry.nonce else { return nil }
        let plain = String(nonce)
        return String(localized: "position \(plain)")
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
