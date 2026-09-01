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

    /// Who paid. The reading this chain publishes that ordinary chains hide —
    /// and a comparison of two fields on one receipt, never an inference.
    @ViewBuilder private var sponsorship: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if head.rolledBackCount > 0 {
                // **THE ONLY THING IN THIS ROOM SOMEBODY MIGHT ACT ON.** Read
                // from effects, never status (§548): a rolled-back frame
                // reports `status: 0x1`.
                note(head.rolledBackCount == 1
                     ? String(localized: "1 frame was rolled back and moved nothing.")
                     : String(localized: "\(String(head.rolledBackCount)) frames were rolled back and moved nothing."))
            }
            if head.sponsoredCount > 0 {
                note(head.sponsoredCount == 1
                     ? String(localized: "Somebody else paid for 1 transaction.")
                     : String(localized: "Somebody else paid for \(String(head.sponsoredCount)) transactions."))
            }
            if head.partial {
                note(String(localized: "\(String(head.reached)) of \(String(head.watched)) addresses answered."))
            }
        }
    }

    @ViewBuilder private var activity: some View {
        if head.moveCount == 0 {
            note(String(localized: "Nothing has moved here yet."))
        } else if head.frameCount > 0 {
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
                Text(move.rows.count == 1
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
