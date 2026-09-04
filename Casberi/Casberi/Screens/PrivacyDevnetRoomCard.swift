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

    @ViewBuilder private var content: some View {
        switch section {
        case .home:       home
        case .activity:   withFigure(.activity) { list(moves) }
        case .accounts:   withFigure(.accounts) { roster }
        case .frames:     withFigure(.frames) { framesScope }
        case .nullifiers: withFigure(.nullifiers) { nullifierScope }
        case .roots:      withFigure(.roots) { rootScope }
        case .sponsors:   withFigure(.sponsors) { sponsorScope }
        }
    }

    private var moves: [PrivacyDevnetLiveState.Move] { accounts.flatMap(\.moves) }

    /// **FIGURE ABOVE, LIST BELOW** — Wallet's order, and the same reason the
    /// switcher sits under the drawing it scopes: the shape is what you read
    /// first and the rows are what you read after.
    @ViewBuilder private func withFigure<Content: View>(
        _ section: PrivacyDevnetSection,
        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            figure(for: section)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
    @ViewBuilder private func empty(_ what: String) -> some View {
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

    @ViewBuilder private func list(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        if moves.isEmpty {
            empty(String(localized: "Nothing from this address on the chain yet."))
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(moves) { move in
                    moveRow(move)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    @ViewBuilder private var roster: some View {
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

    @ViewBuilder private var framesScope: some View {
        list(moves.filter { $0.frameCount > 0 })
    }

    @ViewBuilder private var nullifierScope: some View {
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

    @ViewBuilder private var rootScope: some View {
        let refs = accounts.flatMap(\.roots)
        if refs.isEmpty {
            empty(String(localized: "This address hasn't proved against a snapshot."))
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(PrivacyDevnetRoots.bySource(refs), id: \.source) { group in
                    row(Self.standingLine(group.newest, headSlot: headSlot, count: group.count),
                        Self.shortHex(group.newest.root))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    @ViewBuilder private var sponsorScope: some View {
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
    @ViewBuilder private func blocks(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        let blocks = moves.compactMap(\.block)
        if blocks.isEmpty {
            EmptyView()
        } else {
            let lo = blocks.min()!, hi = blocks.max()!
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint).frame(height: 3)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        let t = hi == lo ? 0.5 : Double(b - lo) / Double(hi - lo)
                        Circle()
                            .fill(DS.tint)
                            .frame(width: 9, height: 9)
                            .offset(x: (geo.size.width - 9) * t)
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
                ForEach(shown) { move in
                    PrivacyDevnetAnatomy(
                        items: PrivacyDevnetFigure.anatomy(
                            frames: move.frames.map {
                                PrivacyDevnetFigure.Frame(gasLimit: $0.gasLimit,
                                                          stateLimit: $0.stateLimit,
                                                          succeeded: $0.succeeded)
                            },
                            keys: 0, roots: 0, sponsored: false),
                        stripWidth: 240,
                        reduceMotion: reduceMotion)
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
