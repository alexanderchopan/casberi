import SwiftUI

/// **The conformance lives HERE and not on the model** — Hegotá's own split,
/// same reason: `FramesSection` is Foundation-only so
/// `scripts/frames-tx-selftest.sh` can compile it whole, and a
/// `DSSectionScope` conformance would drag SwiftUI in and take the harness
/// with it. `label` and `summary` are already declared there; this only
/// states that they satisfy the protocol.
extension FramesSection: DSSectionScope {}

/// THE FRAMES DEVNET ROOM (prd §548) — the figure slot and the rows beneath
/// it, in the shape Wallet, vibenet and Hegotá already wear.
///
/// **This seat lands no `Thing`, so this IS the room.** A nil head renders
/// nothing at all rather than an empty state (`FeedScreen`'s two arms both
/// fall through), which is how Hegotá reached a device black four times —
/// `FramesRoom.head` is written to never return nil while there is anything to
/// watch, and `LiveRoomSources` carries the source so the corpus-shaped empty
/// state is suppressed.
struct FramesRoomFigure: View {
    let head: FramesRoom.Head
    let accounts: [FramesAccount]
    let section: FramesSection

    private var moves: [FramesMove] {
        accounts.filter(\.reached).flatMap(\.moves).sorted { $0.blockNumber > $1.blockNumber }
    }

    /// The one line every scope puts in the slot's reserved row, so the drawing
    /// below it always starts at the same y. **`stat24` on every scope** —
    /// §551's ruling: the strip must not change the type scale of the screen.
    private var slotHeadline: String? {
        switch section {
        case .home, .sponsors:
            guard head.hasRead, !head.everythingUnreached else { return nil }
            return FramesMoney.balanceLine(weiHex: head.balanceWeiHex)
        case .activity:
            return head.moveCount == 1 ? String(localized: "1 transaction")
                                       : String(localized: "\(String(head.moveCount)) transactions")
        // **STEPS, not transactions** — Hegotá's ruling, and the same reason:
        // the transaction count is the Activity scope's headline one chip
        // away, so repeating it makes two scopes look like one reading twice.
        // What this scope adds is that those transactions have parts.
        case .frames:
            let steps = moves.reduce(0) { $0 + $1.rows.count }
            guard steps > 0 else { return nil }
            return steps == 1 ? String(localized: "1 step")
                              : String(localized: "\(String(steps)) steps")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let slotHeadline {
                Text(slotHeadline)
                    .dsText(.stat24)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            reading
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: DSRoomChassis.visualSlot, alignment: .top)
    }

    /// **Never a chart of one point, and never a zero drawn over an unread
    /// chain** (§515a). Every branch here says what it knows or says nothing.
    @ViewBuilder private var reading: some View {
        if !head.hasRead {
            note(String(localized: "Reading the chain…"))
        } else if head.everythingUnreached {
            // NOT a zero balance. An unreached read is not evidence of an
            // empty account, and on a devnet that may have been reset it is
            // the likeliest reading of all.
            note(String(localized: "Couldn't reach the chain."))
        } else {
            switch section {
            case .home, .sponsors: sponsorship
            case .activity:        activity
            case .frames:          frames
            }
        }
    }

    /// Home and Sponsors: what this account has DONE.
    ///
    /// **The slot is 210pt whatever it holds** (§551), so a branch that draws
    /// one line leaves 180pt of void — which is how this looked on a device
    /// the first time it was opened. Every line below is real: a nonce is
    /// sends made, a move count is transactions that touched the account, and
    /// both are already on screen elsewhere only as absences.
    @ViewBuilder private var sponsorship: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if head.rolledBackCount > 0 {
                // **THE ONLY THING IN THIS ROOM SOMEBODY MIGHT ACT ON**, so it
                // leads. Read from effects, never status (§548): a rolled-back
                // frame reports `status: 0x1`.
                note(head.rolledBackCount == 1
                     ? String(localized: "1 frame was rolled back and moved nothing.")
                     : String(localized: "\(String(head.rolledBackCount)) frames were rolled back and moved nothing."))
            }
            // WHAT THIS ACCOUNT HAS SENT. The nonce IS the count — it is
            // incremented per transaction the account signs — so this is a
            // fact off the chain rather than a tally of what happened to be
            // read back.
            // **THE CURVE, WHERE THERE IS ONE.** Two points is a line
            // between two facts and draws honestly; one point is a flat line
            // along the floor, which reads as "went to zero" — the most
            // alarming possible way to say nothing happened, and the reason
            // `AgentPanel.normalized` returns 0.5 for a flat series.
            if head.curve.count > 1 {
                FramesBalanceCurve(points: head.curve)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
            }
            if let account = accounts.first(where: \.reached) {
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: account.address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WalletStore.shortAddress(account.address))
                            .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        Text(sendLine(nonce: account.nonce))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            if head.moveCount > 0 {
                note(head.moveCount == 1
                     ? String(localized: "1 transaction has touched it.")
                     : String(localized: "\(String(head.moveCount)) transactions have touched it."))
            }
            if head.sponsoredCount > 0 {
                note(head.sponsoredCount == 1
                     ? String(localized: "Somebody else paid for 1 of them.")
                     : String(localized: "Somebody else paid for \(String(head.sponsoredCount)) of them."))
            }
            if head.partial {
                note(String(localized: "\(String(head.reached)) of \(String(head.watched)) addresses answered."))
            }
        }
    }

    /// **Nil is not zero.** A nonce that did not read is not an account that
    /// has never sent — §515a, on the one line somebody would take as a fact
    /// about their own history.
    private func sendLine(nonce: UInt64?) -> String {
        guard let nonce else { return String(localized: "Sends couldn't be read") }
        switch nonce {
        case 0:  return String(localized: "Nothing sent from here yet")
        case 1:  return String(localized: "1 sent from here")
        default: return String(localized: "\(String(nonce)) sent from here")
        }
    }

    @ViewBuilder private var activity: some View {
        // **SAY WHAT THEY ARE, not nothing.** The first cut drew this branch
        // empty whenever no frame transaction had landed, which on a fresh
        // account is always — leaving a 210pt slot holding one line. The chain
        // carries ordinary transfers too, and saying so is both true and the
        // thing somebody wants to know.
        if head.moveCount == 0 {
            note(String(localized: "Nothing has moved here yet."))
        } else if head.frameCount == 0 {
            note(String(localized: "All ordinary transfers so far — no frame transaction has landed here yet."))
        } else if head.frameCount == head.moveCount {
            note(head.frameCount == 1
                 ? String(localized: "It is a frame transaction.")
                 : String(localized: "All \(String(head.frameCount)) are frame transactions."))
        } else {
            note(head.frameCount == 1
                 ? String(localized: "1 of them is a frame transaction.")
                 : String(localized: "\(String(head.frameCount)) of them are frame transactions."))
        }
    }

    /// The MODE MIX — what the steps actually were. Counted rather than
    /// charted: a handful of frames is a sentence, and a bar over three values
    /// is a drawing pretending to be a measurement.
    @ViewBuilder private var frames: some View {
        let verify = moves.flatMap(\.rows).filter { $0.frame.mode == 1 }.count
        let sender = moves.flatMap(\.rows).filter { $0.frame.mode == 2 }.count
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if verify > 0 {
                note(String(localized: "\(String(verify)) authorised, \(String(sender)) moved value."))
            }
            note(String(localized: "Every transaction here carries a verify step, or it has no payer at all."))
        }
    }

    @ViewBuilder private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.subhead13)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The rows beneath the figure.
struct FramesRoomList: View {
    let head: FramesRoom.Head
    let accounts: [FramesAccount]
    let section: FramesSection
    let onSend: () -> Void
    let onOpenMove: (FramesMove) -> Void

    private var moves: [FramesMove] {
        accounts.filter(\.reached).flatMap(\.moves).sorted { $0.blockNumber > $1.blockNumber }
    }

    var body: some View {
        switch section {
        case .home:
            // **HOME HOLDS THE TILES, NOT A FORM** (§553's ruling, mirrored).
            FramesSendCard(onSend: onSend)
        case .activity:
            rows(moves)
        case .frames:
            rows(moves.filter { $0.rows.count > 1 })
        case .sponsors:
            rows(moves.filter(\.sponsored))
        }
    }

    @ViewBuilder private func rows(_ list: [FramesMove]) -> some View {
        if list.isEmpty {
            Text(String(localized: "Nothing here yet."))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
                .padding(.vertical, DS.Space.s3)
        } else {
            VStack(spacing: DS.Space.s2) {
                ForEach(list) { move in
                    Button { onOpenMove(move) } label: { FramesMoveRow(move: move) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One transaction, said honestly.
///
/// **The verdict is drawn from EFFECTS, never from status** (§548, second
/// follow-up). A transaction reporting `status: 0x0` can still have moved
/// money, and a frame reporting `status: 0x1` can have been rolled back — so
/// "Failed" alone lies about the money and "Sent" alone lies about the
/// outcome. This row says both when they disagree, which is the whole reason
/// the seat draws frames rather than outcomes.
struct FramesMoveRow: View {
    let move: FramesMove

    private var verdict: String {
        if move.movedValue == true && !move.succeeded {
            return String(localized: "Failed, but value moved")
        }
        if !move.rolledBack.isEmpty {
            return String(localized: "Rolled back")
        }
        return move.succeeded ? String(localized: "Ran") : String(localized: "Failed")
    }

    private var tone: Color {
        if !move.rolledBack.isEmpty || (move.movedValue == true && !move.succeeded) {
            return DS.destructive
        }
        return move.succeeded ? DS.textTertiary : DS.destructive
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                // **AN ORDINARY TRANSACTION IS NOT "0 FRAMES".** This chain
                // carries both — the faucet pays out as a plain type-0x2
                // transfer — and a row reading "0 frames" over one of them is
                // a count where a noun belongs. Reported from a screenshot on
                // the very first launch, which is how the faucet's own payment
                // arrives.
                Text(move.rows.isEmpty
                     ? String(localized: "Transfer")
                     : move.rows.count == 1
                       ? String(localized: "1 frame")
                       : String(localized: "\(String(move.rows.count)) frames"))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                HStack(spacing: DS.Space.s2) {
                    Text(verdict).dsText(.label12).foregroundStyle(tone)
                    if move.sponsored {
                        Text(String(localized: "Somebody else paid"))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            if let gas = move.gasUsed {
                // The TRANSACTION's own gas, never a sum of its frames —
                // measured 100 + 3,000 against a receipt of 210,790.
                Text(String(localized: "\(String(gas)) gas"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}


/// THE BALANCE, AT ROOM SCALE.
///
/// **`Sparkline` is the wrong component and its own frame says so**: it pins
/// itself to 46x14, because it is the inline mark a feed ROW carries. Handed a
/// room's crown it draws a 46pt line in the corner, which is what a device
/// showed — an outer `.frame` cannot widen a view that has already fixed its
/// own. Reused rather than copied wherever the size fits; this is the case
/// where it does not.
///
/// The grammar is `Sparkline`'s and deliberately so: **solid up, dashed down**
/// (prd, 2026-07-21) so direction survives greyscale rather than living in hue
/// alone, and the same two tokens.
struct FramesBalanceCurve: View {
    let points: [Double]

    private var rising: Bool { (points.last ?? 0) >= (points.first ?? 0) }

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2, let lo = points.min(), let hi = points.max() else { return }
            let span = hi - lo
            let inset: CGFloat = 1.5          // half the stroke, so peaks are not clipped
            let stepX = (size.width - inset * 2) / CGFloat(points.count - 1)
            var path = Path()
            for (i, value) in points.enumerated() {
                // **A FLAT SERIES SITS IN THE MIDDLE, NEVER ON THE FLOOR.** A
                // line along the bottom reads as "went to zero", which is the
                // most alarming possible way to say nothing happened —
                // `AgentPanel.normalized`'s rule, and it matters more here
                // because a devnet balance genuinely does sit still for days.
                let t = span > 0 ? (value - lo) / span : 0.5
                let point = CGPoint(x: inset + CGFloat(i) * stepX,
                                    y: inset + CGFloat(1 - t) * (size.height - inset * 2))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            ctx.stroke(path,
                       with: .color(rising ? DS.confirm : DS.destructive),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round,
                                          dash: rising ? [] : [4, 3]))
        }
        .accessibilityElement()
        .accessibilityLabel(Text(rising ? String(localized: "Balance rising")
                                        : String(localized: "Balance falling")))
    }
}
