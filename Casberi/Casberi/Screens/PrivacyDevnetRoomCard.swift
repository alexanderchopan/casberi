import SwiftUI

// The switcher's protocol is declared HERE, not on the enum, so
// `PrivacyDevnetSection` stays Foundation-only and the harness can compile it
// whole. Both sibling seats do exactly this and for the same reason — putting
// the conformance on the type broke `privacy-selftest` the moment the room
// gained a switcher.
extension PrivacyDevnetSection: DSSectionScope {}

/// The Ethrex Privacy room's drawing (prd §593).
///
/// **The window meter is the one thing this room has that nothing else in the
/// app does**, so it leads when there is one — and it is drawn only over a
/// LIVE root. An aged root gets the sentence and no meter, because a bar
/// reading near-empty and a bar with nothing to measure are different claims
/// (`PrivacyDevnetRoots.fraction` returns nil rather than zero for exactly
/// this reason, and the harness pins it).
///
/// **No colour carries state here.** The meter is the tint at one opacity and
/// the track is `DS.fillFaint`; nothing is red for aged or green for live,
/// because neither is good or bad — a proof whose snapshot has left the ring
/// was valid when it landed and its transaction is settled. Colour would say
/// something the chain does not.
struct PrivacyDevnetRoomCard: View {
    let head: PrivacyDevnetRoom.Head
    /// Which scope is showing. **Every chip must change what is drawn** — a
    /// strip whose seven chips all show one card is seven dead controls, which
    /// is worse than no strip at all (§83). Found by opening the room on a
    /// simulator; the scopes were computed correctly and drew the same thing.
    var section: PrivacyDevnetSection = .home
    /// The accounts the scope is showing, for the scopes that list them.
    var accounts: [PrivacyDevnetAccount] = []
    /// The chain's head slot, so a root can say how much window it has left.
    var headSlot: UInt64 = 0
    /// What the last walk could not read (prd §593d). Empty on every pass
    /// today; the room says so the day it is not.
    var walkCut = PrivacyDevnetLiveState.WalkCut()

    /// §299: a drawing sized from data gets an entrance, and the entrance
    /// honours Reduce Motion. The meter is the only thing here whose SIZE
    /// carries a number, so the wipe is on it and nothing else — animating the
    /// sentence would be motion on text that says the same thing either way.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // **The row is NOT reserved** (§495's rule): this card's own sentence
        // IS the headline, so reserving a blank line above it would push the
        // whole card down and misalign it with every other scope.
        DSRoomSlot(headline: nil, reservesHeadline: false) { content }
    }

    /// **THE SLOT HOLDS THE FIGURE, NEVER THE LIST (prd §593d).**
    ///
    /// `DSRoomSlot` is a HARD 300pt box that `.clipped()`s, and this card drew
    /// the figure AND the scope's rows inside it — so the figure's 84pt plus
    /// its gap left ~200pt, and everything past the third or fourth row was
    /// cut off the bottom with no scroll and no sign it had been. Reported as
    /// "lists weren't showing in the privacy room", which is exactly what it
    /// looked like: on Home the sentence, the ring and the tallies filled the
    /// box on their own, so the moves the scope's own summary promises were
    /// clipped away entirely.
    ///
    /// **Frames already had the answer and this room did not take it**:
    /// `FramesRoomFigure` sits in the slot and `FramesRoomList` is its own feed
    /// section underneath, unclipped, scrolling with the feed. That split is
    /// what every scope here needs, and it is why the acts and the example
    /// doors moved out too — the send panel alone is ~300pt and would have been
    /// clipped out of existence by the box it was added to.
    @ViewBuilder private var content: some View {
        switch section {
        case .home:       home
        default:          figure(for: section)
        }
    }

    var moves: [PrivacyDevnetLiveState.Move] { accounts.flatMap(\.moves) }

    @ViewBuilder private var home: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(PrivacyDevnetRoom.sentence(head))
                .dsText(.heading22)
                .fixedSize(horizontal: false, vertical: true)

            if !marks.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    PrivacyDevnetTrack(marks: marks, reduceMotion: reduceMotion)
                    HStack {
                        Text(String(localized: "leaves the chain's memory"))
                        Spacer(minLength: DS.Space.s3)
                        Text(String(localized: "now"))
                    }
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                }
            }

            if !facts.isEmpty {
                HStack(spacing: DS.Space.s4) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.value)
                                .dsText(.stat24)
                                .monospacedDigit()
                            Text(fact.label)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            // **The moves this scope's own summary promises** ("the line, and
            // the last few moves") and the room drew none of. Nothing here was
            // dead, but a scope that says it will show you something and does
            // not is §83's failure in its mildest form.
            //
            // The count comes off the BOX rather than a constant, so when the
            // send panel lands on this scope the rows stop fitting and
            // disappear on their own — no second decision, and no list quietly
            // clipped by the slot's edge.
            if homeMoveCount > 0 {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(moves.prefix(homeMoveCount)) { move in
                        moveRow(move)
                    }
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    /// Every snapshot this address has proved against, placed on the ring.
    ///
    /// **Not just the freshest, which is what the meter could draw.**
    /// `head.windowFraction` carries ONE root by construction, so the bar it
    /// fed showed the reference with the most window left and a room with three
    /// proofs said nothing about the other two — including any that had already
    /// aged out, which had no picture at all, only a sentence.
    private var marks: [PrivacyDevnetFigure.Mark] {
        PrivacyDevnetFigure.marks(accounts.flatMap(\.roots), headSlot: headSlot)
    }

    private var homeMoveCount: Int {
        guard !moves.isEmpty else { return 0 }
        return PrivacyDevnetFigure.homeMoves(hasTrack: !marks.isEmpty,
                                             box: Double(DSRoomChassis.visualSlot))
    }

    /// The counts under the sentence.
    ///
    /// **A count of ZERO is omitted rather than drawn**, and Sponsors is why
    /// that matters: no transaction measured on this chain has a payer
    /// differing from its sender, so a "0 sponsored" tile would be a permanent
    /// zero on every device — the dead control §83 bans, wearing a number.
    private struct Fact { let value: String; let label: String }

    private var facts: [Fact] {
        var out: [Fact] = []
        if head.nullifierCount > 0 {
            out.append(Fact(value: "\(head.nullifierCount)",
                            label: head.nullifierCount == 1
                                ? String(localized: "spend key")
                                : String(localized: "spend keys")))
        }
        if head.frameCount > 0 {
            out.append(Fact(value: "\(head.frameCount)",
                            label: head.frameCount == 1
                                ? String(localized: "frame")
                                : String(localized: "frames")))
        }
        if head.sponsoredCount > 0 {
            out.append(Fact(value: "\(head.sponsoredCount)",
                            label: String(localized: "sponsored")))
        }
        return out
    }
}

// MARK: - The scopes

extension PrivacyDevnetRoomCard {

    /// A scope with nothing in it says so, rather than drawing an empty column.
    /// **`present()` should have kept you out of here** — a scope with no
    /// content has no chip — so this is the honest floor rather than the
    /// expected path.
    @ViewBuilder func empty(_ what: String) -> some View {
        Text(what)
            .dsText(.body17)
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **THE CROWN SAYS WHAT IT IS; THE TAIL SAYS WHICH ONE** (§571).
    ///
    /// Every list here first shipped inverted — a truncated hash at `body17` in
    /// the crown with the meaning in `subhead13` tertiary underneath — and a
    /// person with a fully populated room reported seeing "nothing in the
    /// lists", which was exactly right: four of seven scopes were a column of
    /// hex. **A hash IDENTIFIES, it does not INFORM.** It belongs in a
    /// monospace tail, quiet, where somebody who needs to match one can find
    /// it; the crown belongs to what happened.
    @ViewBuilder private func row(_ crown: String, _ tail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(crown)
                .dsText(.body17)
                .fixedSize(horizontal: false, vertical: true)
            Text(tail)
                .dsText(.mono12)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The scope's own rows, drawn by `PrivacyDevnetRoomList` OUTSIDE the
    /// clipped slot (prd §593d). Internal rather than private for exactly that
    /// reason — the two are one room split across two feed sections, so the
    /// rows and the figure above them are computed from the same inputs and
    /// cannot disagree about which scope is showing.
    @ViewBuilder var scopeList: some View {
        switch section {
        // HOME already draws its own newest moves inside the slot, budgeted to
        // what fits (`homeMoveCount`). Repeating them here would print the same
        // three transactions twice on one screen.
        case .home:       EmptyView()
        case .activity:   list(moves)
        case .accounts:   roster
        case .frames:     framesScope
        case .nullifiers: nullifierScope
        case .roots:      rootScope
        case .sponsors:   sponsorScope
        }
    }

    @ViewBuilder func list(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        if moves.isEmpty {
            empty(String(localized: "Nothing from this address on the chain yet."))
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(moves) { move in
                    moveRow(move)
                }
                walkCeiling
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// **WHAT THIS LIST DOES NOT CONTAIN (prd §593d).**
    ///
    /// Three sentences, and only ever the ones that are true. A truncated room
    /// and a complete one look IDENTICAL from outside, which is this repo's
    /// oldest recurring defect (§307, §309) and one the figures were already
    /// guarding against while the walk feeding them cut silently.
    ///
    /// The standing ceiling is said EVERY time and the two cuts only when they
    /// bit, because they are different kinds of fact: the first is how this
    /// room works and stays true forever, the other two are what happened on
    /// this pass. Neither cut is ever attributed to an address — the cap drops
    /// the oldest candidates chain-wide, and which of them were whose is
    /// exactly what reading them would have told us.
    @ViewBuilder var walkCeiling: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let stopped = walkCut.scannedTo {
                Text(String(localized: "This chain is long enough that the search stopped at block \(String(stopped)) — anything before that wasn't looked at."))
            }
            if walkCut.unread > 0 {
                Text(walkCut.unread == 1
                     ? String(localized: "One older transaction on this chain wasn't read.")
                     : String(localized: "\(walkCut.unread) older transactions on this chain weren't read."))
            }
            Text(String(localized: "Found by following the chain's logs, so a transaction that emitted none isn't here."))
        }
        .dsText(.subhead13)
        .foregroundStyle(DS.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One transaction: what it was made of, what that means, and which one.
    ///
    /// The anatomy draws the SAME facts the sentence beside it states, which is
    /// deliberate rather than redundant — the shapes are what make a column of
    /// rows scannable (a pool transaction wears a disc and a diamond, a plain
    /// send does not), and the sentence is what makes one row readable.
    @ViewBuilder func moveRow(_ move: PrivacyDevnetLiveState.Move) -> some View {
        PrivacyDevnetMoveRow(
            hash: move.hash,
            block: move.block,
            items: PrivacyDevnetFigure.anatomy(
                frames: move.frames.map {
                    PrivacyDevnetFigure.Frame(gasLimit: $0.gasLimit,
                                              stateLimit: $0.stateLimit,
                                              succeeded: $0.succeeded)
                },
                keys: move.nullifierCount,
                roots: move.rootCount,
                sponsored: move.sponsored),
            words: Self.moveLine(move),
            reduceMotion: reduceMotion)
    }

    /// What one transaction did, in the room's own vocabulary.
    static func moveLine(_ m: PrivacyDevnetLiveState.Move) -> String {
        var parts: [String] = []
        parts.append(m.frameCount == 1 ? String(localized: "1 frame")
                                       : String(localized: "\(m.frameCount) frames"))
        if m.nullifierCount > 0 {
            parts.append(m.nullifierCount == 1 ? String(localized: "1 spend key")
                                               : String(localized: "\(m.nullifierCount) spend keys"))
        }
        if m.rootCount > 0 { parts.append(String(localized: "named a snapshot")) }
        if m.sponsored { parts.append(String(localized: "somebody else paid")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(accounts) { account in
                // **Nil is not zero.** An address the chain did not answer for
                // says so in the crown, rather than showing a balance of 0 —
                // which would be a claim made from a failed read (§515a).
                row(account.reached
                        ? (Self.eth(account.balanceWei) ?? String(localized: "Balance unread"))
                        : String(localized: "The chain didn't answer"),
                    PrivacyDevnetWatch.shared.name(for: account.address)
                        ?? WalletStore.shortAddress(account.address))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func eth(_ wei: Decimal?) -> String? {
        guard let wei else { return nil }
        let eth = wei / Decimal(sign: .plus, exponent: 18, significand: 1)
        return "\(NSDecimalNumber(decimal: eth).doubleValue.formatted(.number.precision(.fractionLength(4)))) ETH"
    }

    @ViewBuilder var framesScope: some View {
        list(moves.filter { $0.frameCount > 0 })
    }

    @ViewBuilder var nullifierScope: some View {
        let keys = accounts.flatMap(\.nullifiers)
        if keys.isEmpty {
            empty(String(localized: "No one-time spend keys from this address."))
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(String(localized: "Each of these was used once and can never be used again. That is what stops a spend being repeated — it does not hide who sent it."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                    row(String(localized: "Spent once"), Self.shortHex(key))
                        .accessibilityLabel(String(localized: "Spend key \(i + 1), used once"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder var rootScope: some View {
        let refs = accounts.flatMap(\.roots)
        if refs.isEmpty {
            empty(String(localized: "This address hasn't proved against a snapshot."))
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(PrivacyDevnetRoots.bySource(refs), id: \.source) { group in
                    row(Self.standingLine(group.newest, headSlot: headSlot, count: group.count),
                        Self.shortHex(group.newest.root))
                }
                Text(Self.windowNote)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// **HOW BIG THE WINDOW IS, ONCE, HEDGED (prd §593d).**
    ///
    /// Every line above counts in SLOTS and that ruling stands: the slot count
    /// is measured and the seconds are an assumption about this devnet's slot
    /// time. But a reader who has never met a slot has no way to size "8,192
    /// slots" at all, and `PrivacyDevnetRoots.duration(slots:)` existed to
    /// answer exactly that and was called by nothing.
    ///
    /// So the conversion is stated ONCE, at the bottom, about the WINDOW rather
    /// than about anybody's proof — and it says "about" and names the
    /// assumption, which is the difference between a hedge and a claim (§83).
    /// A per-row countdown in minutes would be the same assumption repeated as
    /// a fact, on the one number somebody might act on.
    static var windowNote: String {
        let hours = Int((PrivacyDevnetRoots.duration(slots: PrivacyDevnetRoots.windowSlots) / 3600)
                        .rounded())
        return String(localized: "The chain remembers \(String(PrivacyDevnetRoots.windowSlots)) slots — about \(hours) hours, if this devnet keeps to \(String(PrivacyDevnetRoots.secondsPerSlot)) seconds a slot.")
    }

    /// Where one reference stands, in slots — never in minutes, because the
    /// slot count is measured and this devnet's slot time is an assumption.
    static func standingLine(_ r: PrivacyDevnetRoots.Reference,
                             headSlot: UInt64, count: Int) -> String {
        switch PrivacyDevnetRoots.standing(of: r, headSlot: headSlot) {
        case .live(let left):
            return String(localized: "\(left) slots left in the chain's memory · \(count) proofs")
        case .aged(let by):
            return String(localized: "Left the chain's memory \(by) slots ago · \(count) proofs")
        case .ahead:
            // The head is behind the reference — a lagging node, not freshness.
            return String(localized: "Waiting for the chain to catch up · \(count) proofs")
        }
    }

    @ViewBuilder var sponsorScope: some View {
        list(moves.filter(\.sponsored))
    }

    static func shortHex(_ d: Data) -> String {
        let hex = d.map { String(format: "%02x", $0) }.joined()
        guard hex.count > 16 else { return "0x" + hex }
        return "0x" + hex.prefix(8) + "…" + hex.suffix(6)
    }
}

// MARK: - The figures

/// A figure for every scope (user, 2026-09-04: *"we need them for each scope"*).
///
/// **Each says something a list of the same rows cannot**, which is the bar a
/// figure has to clear here — the room draws the list underneath either way, so
/// a chart that merely restates it costs a slot and earns nothing.
///
///   • Activity — WHEN, which the hashes cannot say. Blocks, not dates: a
///     transaction carries no timestamp and reading every header to date them
///     would double the walk for an axis.
///   • Accounts — the SHARE each address holds, which reading four balances
///     down a column does not give you.
///   • Frames — how DEEP each transaction was. The whole point of this chain is
///     that one transaction is several steps, and a count of 4 hides whether
///     that was four one-step sends or two two-step ones.
///   • Nullifiers — one mark per key, spent. The visual IS the claim: each was
///     used once and can never be used again.
///   • Roots — every snapshot's remaining window at once, which the Home meter
///     shows for the freshest one only.
///
/// **No colour carries state anywhere below.** Every fill is the one tint, and
/// nothing is red or green — a spent key is not bad and an aged root is not a
/// failure. Scale is the only encoding.
extension PrivacyDevnetRoomCard {

    /// The height every figure occupies, so the six scopes align.
    static let figureHeight: CGFloat = 84

    @ViewBuilder func figure(for section: PrivacyDevnetSection) -> some View {
        switch section {
        case .activity:   blocks(moves)
        case .frames:     budgets(moves.filter { $0.frameCount > 0 })
        case .accounts:   tallies
        case .nullifiers: spentKeys
        case .roots:      windows
        case .sponsors:   budgets(moves.filter(\.sponsored))
        case .home:       EmptyView()
        }
    }

    /// WHEN each transaction landed, along the span it landed in.
    ///
    /// A single transaction draws ONE mark centred rather than a span of zero
    /// width — a lone dot at the left edge reads as "at the beginning of
    /// something", and there is no something.
    ///
    /// **MARKS ARE SPACED SO THEY STAY COUNTABLE (prd §593d).** Placing each
    /// one at its true fraction of the span is the honest drawing and on THIS
    /// chain it collapses: the pool address's four transactions sit in two
    /// pairs five blocks apart across a span of ~10,500, which is 0.05% of the
    /// width — four marks rendering as two, on the figure whose whole job is
    /// how many there were. The fix is not to lie about position but to refuse
    /// to draw two marks closer than one mark's width, keeping their ORDER and
    /// their span exactly (`PrivacyDevnetFigure.spaced`); the range is stated
    /// underneath, which is where the precision the nudge costs actually lives.
    @ViewBuilder private func blocks(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        let blocks = moves.compactMap(\.block)
        if blocks.isEmpty {
            EmptyView()
        } else {
            let lo = blocks.min()!, hi = blocks.max()!
            GeometryReader { geo in
                let positions = PrivacyDevnetFigure.spaced(
                    blocks, width: Double(geo.size.width), mark: 9)
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint).frame(height: 3)
                    ForEach(Array(positions.enumerated()), id: \.offset) { _, x in
                        Circle()
                            .fill(DS.tint)
                            .frame(width: 9, height: 9)
                            .offset(x: x)
                    }
                }
                .frame(height: geo.size.height, alignment: .center)
            }
            .frame(height: Self.figureHeight)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "When these landed"))
            .accessibilityValue(hi == lo
                ? String(localized: "All in block \(hi)")
                : String(localized: "Blocks \(lo) to \(hi)"))
        }
    }

    /// What each transaction's steps were ALLOWED — the reading this chain
    /// exists for.
    ///
    /// **This replaces a bar per transaction whose height was its frame COUNT,
    /// and the count is already on every row beneath it.** A strip per
    /// transaction says the same thing (its segments are countable) and adds
    /// the one fact nothing else here shows: how the budget was divided between
    /// the steps, so a transaction that spent almost everything on one step
    /// reads differently from one that split it evenly.
    ///
    /// **Weighted only when EVERY frame carries a budget**
    /// (`PrivacyDevnetFigure.shares`); a partial read draws equal widths rather
    /// than presenting the unread frame's leftover as its budget.
    ///
    /// **`gasUsed` and `succeeded` are nil on this chain — measured, not
    /// assumed**: `eth_getTransactionReceipt` on 8141 carries no per-frame
    /// breakdown (§593a). So no segment is ever drawn as failed, and the strip
    /// is the budget rather than the spend.
    @ViewBuilder private func budgets(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        if moves.isEmpty {
            EmptyView()
        } else {
            let shown = Array(moves.prefix(Self.budgetRows))
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // **THE STRIP TAKES THE WIDTH IT IS GIVEN (prd §593d).** It
                // was a flat 240pt, which is a phone's measurement wearing no
                // label: on an iPad or a Mac window the strip sat in the left
                // third of an empty row, and on the narrowest phone it ran
                // past the card's own inset. The cap keeps it from becoming a
                // ruler across a 900pt window, where a two-frame transaction
                // would read as a progress bar.
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        ForEach(shown) { move in
                            PrivacyDevnetAnatomy(
                                items: PrivacyDevnetFigure.anatomy(
                                    frames: move.frames.map {
                                        PrivacyDevnetFigure.Frame(gasLimit: $0.gasLimit,
                                                                  stateLimit: $0.stateLimit,
                                                                  succeeded: $0.succeeded)
                                    },
                                    keys: 0, roots: 0, sponsored: false),
                                stripWidth: min(max(geo.size.width, 120), 360),
                                reduceMotion: reduceMotion)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
                PrivacyDevnetMore(count: moves.count - shown.count,
                                  noun: String(localized: "more below"))
            }
            .frame(height: Self.figureHeight, alignment: .center)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "What each transaction's steps were allowed"))
        }
    }

    /// How many strips fit above the list. Derived from the figure's own box,
    /// never a constant (`PrivacyDevnetFigure.rowCap`'s reason).
    static var budgetRows: Int {
        PrivacyDevnetFigure.rowCap(box: Double(figureHeight), rowHeight: 14,
                                   spacing: Double(DS.Space.s2), chrome: 18)
    }

    /// WHAT EACH ADDRESS HAS DONE — frames, spend keys, snapshots.
    ///
    /// **This replaces a share-of-balance bar, and the replacement is a
    /// correctness fix rather than a preference.** That bar divided each
    /// address's balance by the watched total, which on THIS chain is a ranking
    /// by faucet luck: test ETH has no market, the balances come from a tap
    /// anybody can pull, and a bar three times longer than its neighbour
    /// invites a comparison that means nothing. It also put a second reading of
    /// money on a card whose crown is already the balance, one line above.
    ///
    /// The tally answers what the scope is actually for, and it is COUNTABLE:
    /// pips up to `PrivacyDevnetFigure.pipCap`, then a count of the rest. No
    /// length encodes a magnitude anywhere.
    ///
    /// **An address the chain did not answer for draws NO tally**, not a row of
    /// empty pips — empty pips are a claim that the address has done nothing,
    /// made from a read that failed (§515a).
    @ViewBuilder private var tallies: some View {
        let rows = accounts.filter(\.reached)
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(rows) { account in
                    HStack(spacing: DS.Space.s3) {
                        Text(PrivacyDevnetWatch.shared.name(for: account.address)
                             ?? WalletStore.shortAddress(account.address))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .frame(width: 96, alignment: .leading)
                        PrivacyDevnetTally(
                            tally: .init(frames: account.frameCount,
                                         keys: account.nullifiers.count,
                                         roots: account.roots.count),
                            reduceMotion: reduceMotion)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: Self.figureHeight, alignment: .center)
        }
    }

    /// One mark per spent key, drawn as SPENT.
    ///
    /// **A ring with a hole, not a filled block.** The hole is the whole claim
    /// — this key was used once and can never be used again — where a solid
    /// bar is a quantity and says only "there are this many". Same facts, and
    /// the shape now carries the sentence printed under the list.
    @ViewBuilder private var spentKeys: some View {
        let keys = accounts.flatMap(\.nullifiers)
        if keys.isEmpty {
            EmptyView()
        } else {
            // A cap, so an address with hundreds does not draw hundreds — the
            // rest is COUNTED rather than dropped, since a grid cut at the
            // slot's edge and a complete one look identical (§307).
            let shown = Array(keys.prefix(24))
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: 7) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, _ in
                        PrivacyDevnetSpentKey(size: 16)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                    Spacer(minLength: 0)
                }
                PrivacyDevnetMore(count: keys.count - shown.count)
            }
            .frame(height: Self.figureHeight, alignment: .center)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Spend keys used"))
            .accessibilityValue("\(keys.count)")
        }
    }

    /// Every referenced snapshot on the ring, one lane per source.
    ///
    /// **This replaces a bar per source whose length was the newest root's
    /// remaining window**, which had two problems the lanes fix. It drew ONE
    /// reference per source, so a source with five proofs showed its newest and
    /// hid four; and an aged root drew no bar at all, correctly refusing to
    /// claim "nearly gone", but leaving an empty track that reads as a source
    /// with nothing in it.
    ///
    /// On the ring an aged root is a HOLLOW mark just outside the leading edge:
    /// out of the window, which is exactly where it is, and visibly a thing
    /// rather than an absence.
    ///
    /// **No colour separates the lanes.** They are the same reading over
    /// different sources, and a hue per source would say the sources differ in
    /// kind, which they do not — the label says which is which.
    @ViewBuilder private var windows: some View {
        let refs = accounts.flatMap(\.roots)
        if refs.isEmpty {
            EmptyView()
        } else {
            let placed = PrivacyDevnetFigure.lanes(refs, headSlot: headSlot,
                                                   cap: Self.laneCap)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(placed.lanes) { lane in
                    HStack(spacing: DS.Space.s2) {
                        Text(Self.shortHex(lane.source))
                            .dsText(.mono12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                            .frame(width: 84, alignment: .leading)
                        // Labels off in the stack: at lane height there is no
                        // room for a reading beside each mark, and the list
                        // below states every one of them in words.
                        PrivacyDevnetTrack(marks: lane.marks, labelled: false,
                                           reduceMotion: reduceMotion)
                    }
                }
                PrivacyDevnetMore(count: placed.overflow,
                                  noun: String(localized: "more sources"))
                HStack {
                    Text(String(localized: "leaves the chain's memory"))
                    Spacer(minLength: DS.Space.s3)
                    Text(String(localized: "now"))
                }
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
                .padding(.leading, 84 + DS.Space.s2)
            }
            .frame(height: Self.figureHeight, alignment: .center)
        }
    }

    /// How many source lanes fit. Derived, never a constant.
    static var laneCap: Int {
        PrivacyDevnetFigure.rowCap(box: Double(figureHeight), rowHeight: 22,
                                   spacing: Double(DS.Space.s2), chrome: 18)
    }
}

// MARK: - The quiet state's door (prd §593d)

/// Two rows offering the addresses that have something to show.
///
/// **Not a re-pitch and not a list of every address on the chain** — the two
/// measured examples, each named for the READING it makes possible, which is
/// the same claim the connect screen's own rows make and in the same words. The
/// pool participant leads because it is the only one of the two whose
/// transactions reference a root, so it is the only way to see the Roots scope
/// at all without waiting for somebody else to use the chain.
///
/// A DOOR, never a claim: tapping watches the address, which is a read.
struct PrivacyDevnetExampleDoors: View {
    let onWatch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "Or watch one that has something to show"))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
            ForEach(PrivacyDevnetExample.all) { example in
                Button { onWatch(example.address) } label: {
                    HStack(spacing: DS.Space.s3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(example.title)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                            Text(example.detail)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: DS.Space.s3)
                        Image(systemName: "plus.circle")
                            .foregroundStyle(DS.textTertiary)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - The rows, outside the box (prd §593d)

/// Every scope's LIST, as its own feed section.
///
/// **This exists because `DSRoomSlot` clips at 300pt.** The card above draws
/// the figure into that box; these rows scroll with the feed, which is the
/// split `FramesRoomList` has had since the Frames room shipped and this room
/// did not take. Reported as "lists weren't showing in the privacy room", and
/// they were not — they were drawn, and cut off the bottom of a fixed box.
///
/// The acts live here too rather than in the card, for the same reason and more
/// sharply: the send panel is two 146pt tiles and a gap, so inside the slot it
/// would have been clipped out of existence.
struct PrivacyDevnetRoomList: View {
    let head: PrivacyDevnetRoom.Head
    var section: PrivacyDevnetSection = .home
    var accounts: [PrivacyDevnetAccount] = []
    var headSlot: UInt64 = 0
    var walkCut = PrivacyDevnetLiveState.WalkCut()
    /// Raise the send form. Nil for a preview and for the demo's own card.
    var onSend: (() -> Void)?
    /// Watch one of the measured example addresses from the quiet state.
    var onWatchExample: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var card: PrivacyDevnetRoomCard {
        PrivacyDevnetRoomCard(head: head, section: section, accounts: accounts,
                              headSlot: headSlot, walkCut: walkCut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            card.scopeList

            // **THE ACTS ARE LAST.** The reading is what the room is for and
            // the panel is what you came to do — §594 put vibenet's acts on
            // Home without moving its readings off it, and the same order
            // holds: the sentence and the ring above, the two tiles under.
            //
            // On HOME only. A send panel repeated under every scope is the same
            // control four times, and §594's own line is that an act belongs
            // where you land rather than everywhere you look.
            if section == .home, let onSend {
                PrivacyDevnetSendCard(onSend: onSend)
            }

            // **THE QUIET STATE HAD NO DOOR.** Somebody who pasted their own
            // address landed on "Nothing on this chain from the address you
            // watch, yet." with no next step anywhere on screen — and the two
            // addresses that DO have something to show lived only on the
            // connect screen, which you reach this room by leaving. Offered
            // only where it is really the answer: not while a relaunch is being
            // announced (which outranks everything), and not once there is
            // something to read.
            if section == .home, let onWatchExample, showsExamples {
                PrivacyDevnetExampleDoors(onWatch: onWatchExample)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsExamples: Bool {
        switch head.lede {
        case .quiet, .unwatched: return true
        case .reading, .relaunched, .rootLive, .rootsAged, .spends: return false
        }
    }
}
