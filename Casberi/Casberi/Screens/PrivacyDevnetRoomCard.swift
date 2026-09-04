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
        case .activity:   list(moves)
        case .accounts:   roster
        case .frames:     framesScope
        case .nullifiers: nullifierScope
        case .roots:      rootScope
        case .sponsors:   sponsorScope
        }
    }

    private var moves: [PrivacyDevnetLiveState.Move] { accounts.flatMap(\.moves) }

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

    @ViewBuilder private func list(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        if moves.isEmpty {
            empty(String(localized: "Nothing from this address on the chain yet."))
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(moves) { move in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WalletStore.shortAddress(move.hash))
                            .dsText(.body17).monospaced()
                        Text(Self.moveLine(move))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What one transaction did, in the room's own vocabulary.
    static func moveLine(_ m: PrivacyDevnetLiveState.Move) -> String {
        var parts: [String] = []
        parts.append(m.frames == 1 ? String(localized: "1 frame")
                                   : String(localized: "\(m.frames) frames"))
        if m.nullifiers > 0 {
            parts.append(m.nullifiers == 1 ? String(localized: "1 spend key")
                                           : String(localized: "\(m.nullifiers) spend keys"))
        }
        if m.roots > 0 { parts.append(String(localized: "named a snapshot")) }
        if m.sponsored { parts.append(String(localized: "somebody else paid")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(accounts) { account in
                VStack(alignment: .leading, spacing: 2) {
                    Text(PrivacyDevnetWatch.shared.name(for: account.address)
                         ?? WalletStore.shortAddress(account.address))
                        .dsText(.body17)
                    // **Nil is not zero.** An address the chain did not answer
                    // for says so, rather than showing a balance of 0 — which
                    // would be a claim made from a failed read (§515a).
                    Text(account.reached
                         ? (Self.eth(account.balanceWei) ?? String(localized: "Balance unread"))
                         : String(localized: "The chain didn't answer"))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                }
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
        list(moves.filter { $0.frames > 0 })
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
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(Self.shortHex(key))
                        .dsText(.body17).monospaced()
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.shortHex(group.newest.root))
                            .dsText(.body17).monospaced()
                        Text(Self.standingLine(group.newest, headSlot: headSlot, count: group.count))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                    }
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
