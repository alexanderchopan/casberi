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

            if let fraction = head.windowFraction {
                window(fraction)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How much of the 8192-slot ring the freshest referenced root has left.
    @ViewBuilder private func window(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule()
                        .fill(DS.tint)
                        // Clamped, because a head slot behind the reference
                        // would otherwise draw a bar wider than its track —
                        // and that state is real (a lagging RPC), not
                        // hypothetical.
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            // The wipe reveals the bar left to right, in the direction the
            // window actually drains.
            .chartWipe(reduceMotion: reduceMotion)
            Text(String(localized: "How much of the chain's memory this proof's snapshot still has"))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Snapshot window"))
        .accessibilityValue(Text(String(format: "%.0f%%", fraction * 100)))
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
                    row(Self.moveLine(move), Self.tail(move))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The identity line — which transaction, and where it landed.
    static func tail(_ m: PrivacyDevnetLiveState.Move) -> String {
        let short = m.hash.count > 12
            ? String(m.hash.prefix(8)) + "…" + String(m.hash.suffix(4)) : m.hash
        if let b = m.block { return "\(short) · block \(b)" }
        return short
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
        case .frames:     depth(moves.filter { $0.frameCount > 0 })
        case .accounts:   shares
        case .nullifiers: spentKeys
        case .roots:      windows
        case .sponsors:   depth(moves.filter(\.sponsored))
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

    /// How many steps each transaction ran — the reading this chain exists for.
    @ViewBuilder private func depth(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        let counts = moves.map(\.frameCount)
        if counts.isEmpty {
            EmptyView()
        } else {
            let peak = max(counts.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: DS.Space.s2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, n in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DS.tint)
                            .frame(height: max(4, Self.figureHeight * 0.62
                                                  * Double(n) / Double(peak)))
                        Text("\(n)")
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 40)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.figureHeight, alignment: .bottom)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Steps per transaction"))
            .accessibilityValue(counts.map(String.init).joined(separator: ", "))
        }
    }

    /// What SHARE of the watched total each address holds.
    ///
    /// Addresses the chain did not answer for are excluded rather than drawn at
    /// zero — a share computed over a failed read is a claim about somebody's
    /// balance (§515a). With nothing readable there is no figure at all.
    @ViewBuilder private var shares: some View {
        let readable = accounts.filter { $0.reached && $0.balanceWei != nil }
        let total = readable.compactMap(\.balanceWei).reduce(Decimal(0), +)
        if readable.isEmpty || total == 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(readable) { account in
                    let share = NSDecimalNumber(
                        decimal: (account.balanceWei ?? 0) / total).doubleValue
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.fillFaint)
                            Capsule().fill(DS.tint)
                                .frame(width: geo.size.width * min(max(share, 0), 1))
                        }
                    }
                    .frame(height: 8)
                }
            }
            .frame(height: Self.figureHeight, alignment: .center)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Share of the balance you watch"))
        }
    }

    /// One mark per spent key. The drawing IS the claim: each was used once.
    @ViewBuilder private var spentKeys: some View {
        let keys = accounts.flatMap(\.nullifiers)
        if keys.isEmpty {
            EmptyView()
        } else {
            // A cap, so an address with hundreds does not draw hundreds — the
            // count is stated beside it, so the figure is a sense of scale
            // rather than an inventory.
            let shown = Array(keys.prefix(24))
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DS.tint)
                            .frame(width: 10, height: 22)
                    }
                    Spacer(minLength: 0)
                }
                if keys.count > shown.count {
                    Text(String(localized: "and \(keys.count - shown.count) more"))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .frame(height: Self.figureHeight, alignment: .center)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Spend keys used"))
            .accessibilityValue("\(keys.count)")
        }
    }

    /// Every referenced snapshot's remaining window at once — the Home meter
    /// shows only the freshest.
    @ViewBuilder private var windows: some View {
        let refs = accounts.flatMap(\.roots)
        if refs.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(PrivacyDevnetRoots.bySource(refs), id: \.source) { group in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.fillFaint)
                            // **An aged root draws NO bar, not an empty one.**
                            // `fraction` returns nil rather than zero for
                            // exactly this: "nearly gone" and "gone" are
                            // different claims.
                            if let f = PrivacyDevnetRoots.fraction(group.newest,
                                                                   headSlot: headSlot) {
                                Capsule().fill(DS.tint)
                                    .frame(width: geo.size.width * min(max(f, 0), 1))
                            }
                        }
                    }
                    .frame(height: 8)
                }
            }
            .frame(height: Self.figureHeight, alignment: .center)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "How much window each snapshot has left"))
        }
    }
}
