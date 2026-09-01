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

    /// **THE CHASSIS DRAWS THE ROW, NOT THIS FILE** (prd §495).
    ///
    /// The first cut hand-rolled the slot — its own `VStack`, its own `stat24`
    /// headline, its own `.frame(height: visualSlot)` — which is the exact
    /// drift `DSRoomChassis`'s doc names ("one drawing its own headline, one
    /// passing it to the chassis"), and it cost the thing that doc says
    /// reserving the row buys: **the settings gear's clearance**. That control
    /// floats over the slot's top-right, a `stat24` line is shorter than the
    /// reserved row, and so every drawing began ~7pt too high and ran under
    /// the cog — seen on all three chart scopes at once, on the simulator.
    ///
    /// It also cost the 12pt `contentInset`, so the drawing was wider than the
    /// toggle bar that scopes it — Hegotá's own note on the same line.
    var body: some View {
        DSRoomSlot(headline: slotHeadline) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                reading
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // **EVERY DRAWING IN THIS ROOM ENDS AT THE SAME x, AND IT IS THE
            // GEAR'S.** Applied here rather than per chart for the reason the
            // constant's own note gives: three charts each remembering the
            // clearance is three chances to forget it, and a chart that ends
            // 44pt short beside one that reaches the edge reads as a bug in
            // the shorter one.
            .padding(.trailing, DSRoomChassis.gearColumn)
        }
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
            case .home:     sponsorship
            case .sponsors: sponsors
            case .activity:        activity
            case .frames:          frames
            }
        }
    }

    /// HOME: THE CURVE, AND WHOSE ACCOUNT IT IS. Nothing else.
    ///
    /// **Every tally that used to sit here is now another scope's headline**
    /// (2026-09-01, user: "also you have clipping", with a screenshot of the
    /// fifth line cut off by the slot's own `.clipped()`). It stacked a
    /// rolled-back note, the curve, the account row and three more sentences
    /// into a fixed 210pt box, and the box did what it says it does.
    ///
    /// The fix is not a shorter box, it is that the sentences stopped being
    /// true of THIS scope. When Home was the only scope with a reading, saying
    /// "5 transactions have touched it" and "somebody else paid for 1 of them"
    /// here was the only place they could be said. Activity and Sponsors now
    /// DRAW both of those, one chip away — so on Home they are another scope's
    /// headline repeated in smaller type, which is exactly the argument that
    /// removed the frame-count sentence from Activity in the same pass.
    ///
    /// The rolled-back note went the same way and took a replacement with it:
    /// it was the one thing here somebody might act on, so dropping it silently
    /// would lose a fact rather than move it. `FramesSection.attention` marks
    /// the Frames chip instead, which is a pointer to the drawing that shows
    /// which steps they were — strictly more than the sentence said.
    ///
    /// `partial` stays, and is the test for what belongs: it is not a reading
    /// at all, it is a caveat about how much of the room was READ, and no
    /// other scope can carry it because it applies to all of them.
    @ViewBuilder private var sponsorship: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
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
                        // The nonce IS the count — it is incremented per
                        // transaction the account signs — so this is a fact off
                        // the chain rather than a tally of what was read back.
                        Text(sendLine(nonce: account.nonce))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
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

    /// **ACTIVITY: WHAT MOVED, PER TRANSACTION.** One bar each, newest on the
    /// right, above the line for arriving and below for leaving — the shape a
    /// list of amounts cannot give you, which is that this account received
    /// once and has been spending since.
    ///
    /// Drawn from `deltaWei`, which is exact (§548): every ETH movement is a
    /// log and the receipt names the fee AND its payer. A transaction whose
    /// delta could not be read draws NO bar rather than a zero-height one — an
    /// unread amount and an amount of nothing must not look alike.
    @ViewBuilder private var activityChart: some View {
        let bars = moves.reversed().compactMap { move -> (Decimal, Bool)? in
            guard let delta = move.deltaWei else { return nil }
            return (delta, move.succeeded)
        }
        // ONE BAR IS STILL A READING — its size and its direction are both
        // real. The threshold was 2 while a sentence sat under the chart to
        // carry the single-movement case; with that sentence gone (below) a
        // 2-bar floor would leave the slot empty on exactly the account that
        // has just made its first send.
        if !bars.isEmpty {
            FramesMovementBars(bars: bars).frame(height: 64)
        }
    }

    @ViewBuilder private var activity: some View {
        activityChart
        // **NO FRAME-COUNT SENTENCE (user ruling, 2026-09-01).** It read
        // "4 of them are frame transactions" under the chart, and on THIS
        // chain that is a tally of very nearly everything: a frame transaction
        // is what this devnet is for, so the count separates almost nothing
        // and costs a line under a drawing that already says more than it did.
        //
        // What survives is the one branch a chart cannot draw: an account
        // where nothing has moved. That is not a tally, it is the reason the
        // slot is empty, and without it the scope reads as broken rather than
        // as new.
        if head.moveCount == 0 {
            note(String(localized: "Nothing has moved here yet."))
        }
    }

    /// The MODE MIX — what the steps actually were. Counted rather than
    /// charted: a handful of frames is a sentence, and a bar over three values
    /// is a drawing pretending to be a measurement.
    /// **FRAMES: EVERY TRANSACTION AS ITS PARTS.** The reading this seat
    /// exists for, and one no other room in this app can draw.
    @ViewBuilder private var frames: some View {
        let runs = moves.filter { $0.rows.count > 1 }.prefix(6).map(\.rows)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !runs.isEmpty {
                FramesSequenceStrip(runs: Array(runs))
                    .frame(height: CGFloat(runs.count) * 20)
            }
            let rolled = moves.flatMap(\.rolledBack).count
            if rolled > 0 {
                // The dashed cells above, said in words — a legend for the one
                // state somebody must not misread.
                note(rolled == 1
                     ? String(localized: "The dashed step ran and was rolled back.")
                     : String(localized: "The \(String(rolled)) dashed steps ran and were rolled back."))
            } else {
                note(String(localized: "Every transaction here carries a verify step, or it has no payer at all."))
            }
        }
    }

    /// **SPONSORS: WHOSE GAS.** Exact — `gasUsed` and `effectiveGasPrice` are
    /// on every receipt and `payer` says whose it was.
    @ViewBuilder private var sponsors: some View {
        let paid = moves.compactMap { move -> (Double, Bool)? in
            guard let gas = move.gasUsed else { return nil }
            return (Double(gas), move.sponsored)
        }
        let theirs = paid.filter(\.1).map(\.0).reduce(0, +)
        let mine = paid.filter { !$0.1 }.map(\.0).reduce(0, +)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if theirs + mine > 0 {
                FramesSponsorBar(mine: mine, theirs: theirs)
            }
            if theirs > 0 {
                note(String(localized: "Somebody else paid \(Int((theirs / (theirs + mine) * 100).rounded()))% of the gas here."))
            } else {
                // NOT "nobody has sponsored you" — that is a claim about other
                // people. This says only what was observed.
                note(String(localized: "Every transaction here paid its own gas."))
            }
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


/// WHAT EACH TRANSACTION DID TO THE BALANCE — signed bars from a centre line.
///
/// **The centre line is drawn even when every bar points the same way**, so a
/// column of outgoing bars reads as outgoing rather than as a bar chart that
/// happens to start at the top. Without it the sign is carried by nothing.
struct FramesMovementBars: View {
    /// Signed wei, and whether the transaction itself succeeded.
    let bars: [(Decimal, Bool)]

    var body: some View {
        Canvas { ctx, size in
            let magnitudes = bars.map { abs(NSDecimalNumber(decimal: $0.0).doubleValue) }
            guard let peak = magnitudes.max(), peak > 0 else { return }
            let mid = size.height / 2
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: mid))
                              $0.addLine(to: CGPoint(x: size.width, y: mid)) },
                       with: .color(DS.textTertiary.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1))

            let slot = size.width / CGFloat(bars.count)
            let width = min(slot * 0.55, 14)
            for (i, bar) in bars.enumerated() {
                let value = NSDecimalNumber(decimal: bar.0).doubleValue
                // **A MOVEMENT THAT HAPPENED MUST NOT DRAW AS NOTHING.** On
                // this chain a faucet claim is 1 ETH and a send is 0.001, a
                // 1000:1 ratio — so a purely proportional bar renders four
                // real transactions as invisible hairlines, which says "these
                // did not happen". Same principle as nil-is-not-zero, one
                // surface over.
                //
                // The floor is 4pt: enough to be seen, small enough that the
                // shape still carries magnitude. NOT a log scale — that makes
                // every height a claim about a ratio nobody can read back.
                let height = max(4, CGFloat(abs(value) / peak) * (mid - 3))
                let x = slot * CGFloat(i) + (slot - width) / 2
                let rect = value >= 0
                    ? CGRect(x: x, y: mid - height, width: width, height: height)
                    : CGRect(x: x, y: mid, width: width, height: height)
                // **A FAILED TRANSACTION IS OUTLINED, NOT FILLED.** It may
                // still have moved money (§548), so it belongs on the chart —
                // but it must not read as an ordinary movement.
                let path = Path(roundedRect: rect, cornerRadius: min(3, width / 2))
                if bar.1 {
                    ctx.fill(path, with: .color(value >= 0 ? DS.confirm : DS.textSecondary))
                } else {
                    ctx.stroke(path, with: .color(DS.destructive), style: StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "\(String(bars.count)) movements")))
    }
}

/// **THE ROOM'S SIGNATURE DRAWING: a transaction as its parts.**
///
/// One run per transaction, one cell per frame, each cell's width its share of
/// the gas the frames themselves report. Nothing else in this app draws a
/// transaction as a sequence, because no other chain this app reads publishes
/// one.
///
/// **Three states, and the third is the whole point.** A frame that ran is
/// filled; one that reverted is filled in the destructive tone; one that was
/// ROLLED BACK is outlined — because it reports `status: 0x1` and did nothing,
/// so filling it like a success would be the lie §548 was written about.
struct FramesSequenceStrip: View {
    let runs: [[FramesFrameRow]]

    private static let rowHeight: CGFloat = 14
    private static let gap: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            guard !runs.isEmpty else { return }
            let rowGap = Self.gap
            let height = min(Self.rowHeight,
                             (size.height - rowGap * CGFloat(runs.count - 1)) / CGFloat(runs.count))
            for (row, run) in runs.enumerated() {
                let y = (height + rowGap) * CGFloat(row)
                // Gas SHARE, so a cell's width says what that frame cost —
                // falling back to equal widths when the receipt did not report
                // it, rather than dropping the frame from the drawing.
                let costs = run.map { Double($0.outcome?.gasUsed ?? 0) }
                let total = costs.reduce(0, +)
                var x: CGFloat = 0
                for (i, cell) in run.enumerated() {
                    let share = total > 0 ? costs[i] / total : 1.0 / Double(run.count)
                    let w = max(3, CGFloat(share) * (size.width - CGFloat(run.count - 1) * 2))
                    let rect = CGRect(x: x, y: y, width: w, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: 3)
                    let ran = cell.outcome?.succeeded ?? true
                    if cell.valueLanded == false {
                        ctx.stroke(path, with: .color(DS.destructive),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    } else if ran {
                        // VERIFY reads lighter than SENDER: the first
                        // authorises, the second acts.
                        ctx.fill(path, with: .color(cell.frame.mode == 1
                                                    ? DS.textTertiary : DS.tint))
                    } else {
                        ctx.fill(path, with: .color(DS.destructive))
                    }
                    x += w + 2
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "\(String(runs.count)) transactions, drawn frame by frame")))
    }
}

/// WHO PAID THE GAS — one bar, split.
///
/// Exact: `gasUsed` and `effectiveGasPrice` are on every receipt and the
/// `payer` says whose it was. The reading no ordinary chain can give.
struct FramesSponsorBar: View {
    let mine: Double
    let theirs: Double

    /// **A DRAWING SIZED FROM DATA GETS AN ENTRANCE** (prd §299) — caught by
    /// `design-motion-audit`, not by looking. It grows from the leading edge,
    /// which is the direction the split is read in, and Reduce Motion lands it
    /// at full width on the first frame rather than animating faster.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            let total = mine + theirs
            let split = total > 0 ? CGFloat(theirs / total) : 0
            HStack(spacing: 2) {
                if split < 1 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.textTertiary)
                        .frame(width: max(0, geo.size.width * (1 - split) - 1))
                }
                if split > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.tint)
                }
            }
            .scaleEffect(x: grown ? 1 : 0.001, anchor: .leading)
            .onAppear {
                guard !reduceMotion else { grown = true; return }
                withAnimation(DS.Motion.standard) { grown = true }
            }
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "Gas paid by others, against gas you paid")))
    }
}
