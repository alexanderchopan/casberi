import SwiftUI

/// The Ethrex Hegotá room's drawings.
///
/// **The room is FOUR SECTIONS, not one card** — figure, rail, switcher, list —
/// emitted by `FeedScreen` exactly as Wallet emits its own. That is why this
/// file holds two views rather than one: three sections cannot share a single
/// card's `@State`, which is what left this room's rails carrying a card's
/// padding instead of the room's own insets.
///
/// **The conformance lives here and not in the model file** — `HegotaSection`
/// is Foundation-only so its harness can compile it whole, and a
/// `DSSectionScope` conformance would drag SwiftUI in and take the harness too.
extension HegotaSection: DSSectionScope {}

// MARK: - The figure

/// Whatever the active scope draws into the room's fixed slot.
///
/// `DSRoomSlot` is the template's own component: it reserves the headline row
/// and clamps to `DSRoomChassis.visualSlot`, which is WHY the toggle lands at
/// the same height on every scope. Reproducing that geometry by hand is how a
/// room drifts off the template one constant at a time.
struct HegotaRoomFigure: View {
    @Environment(\.colorScheme) private var scheme

    let head: HegotaRoom.Head
    let accounts: [HegotaAccount]
    /// Handed DOWN from the shell, never held here.
    let scoped: String?
    let section: HegotaSection

    /// The pressed lane, and the task that lets it go. `@State`, so it dies
    /// with the room the way `x402Lane` does — a press is a question about
    /// right now, not a scope worth keeping.
    @State private var pickedLane: HegotaFlow.Lane?
    @State private var laneRevert: Task<Void, Never>?
    /// How many transactions the frame anatomy draws.
    ///
    /// **The budget is 166pt and the sum is written down, because the drawing
    /// is not the only thing in it.** `DSRoomSlot` is a hard 210pt with
    /// `.clipped()`, less its 30pt reserved headline row AND that row's own
    /// `DS.Space.s3` bottom pad — 14pt on iOS, and the part that is easy to
    /// miss because it lives in the chassis rather than here. The figure
    /// spends: caption 16 + 4 + rows + 4 + legend 16 + 4 + the population
    /// note 16. At five rows that is 5×14 + 4×5 = 90, so the total is 150 and
    /// the slack is 16 — which is what absorbs a step or two of Dynamic Type,
    /// since `label12` is `.caption1`-relative and the slot is not.
    ///
    /// **The caption is clamped to ONE line here** for the same sum: at its
    /// shared two-line limit the total is 166 exactly, zero slack, and the
    /// line that goes over the edge is the last one — the population note.
    ///
    /// It was SIX, and the note did not exist. Adding it takes six rows to
    /// 169 and the clip lands on the note itself, which is the one line that
    /// exists to stop the cap being silent — the failure the old comment here
    /// was already warning about, arriving through the disclosure rather than
    /// through a seventh row. A fifth multiple shows the same shape as a
    /// sixth; a clipped disclosure shows a card that lies.
    ///
    /// **Re-do this sum before raising it (prd §510).**
    private static let frameRows = 5

    var body: some View {
        DSRoomSlot(headline: slotHeadline) { slotFigure }
            .task { await HegotaLiveState.shared.refreshIfStale() }
    }

    // MARK: Shared reads

    private var shown: [HegotaAccount] {
        guard let scoped else { return accounts }
        return accounts.filter { $0.address.caseInsensitiveCompare(scoped) == .orderedSame }
    }
    private var primary: HegotaAccount? {
        shown.filter(\.reached).max { $0.moves.count < $1.moves.count }
    }
    private var shownBalance: Decimal? {
        let reached = shown.filter(\.reached)
        guard !reached.isEmpty else { return nil }
        return reached.compactMap(\.balanceWei).reduce(Decimal(0), +)
    }
    private var coins: [HegotaCoin] {
        shown.filter(\.hasCoins).flatMap { $0.unspent ?? [] }.sorted { $0.index < $1.index }
    }
    private var lanes: [HegotaNonceLane] {
        shown.flatMap(\.lanes).sorted { $0.lastBlock > $1.lastBlock }
    }
    private var moves: [HegotaMove] {
        shown.flatMap(\.moves).sorted { $0.block > $1.block }
    }
    /// The transactions whose frames were actually read, newest first.
    ///
    /// Folded by hash across accounts as well as within one: watching both
    /// sides of a transfer means the same transaction is in two accounts'
    /// `moves`, and the Frames scope's subject is the TRANSACTION.
    private var framedMoves: [HegotaMove] {
        var seen = Set<String>()
        return moves.filter { move in
            guard let f = move.frames, !f.isEmpty else { return false }
            return seen.insert(move.hash.lowercased()).inserted
        }
    }
    /// The census behind the coins figure — chain-wide, and only when the whole
    /// set reconciled. Taken from the primary account because every account's
    /// sweep computes the same whole-chain set; they can only disagree if one
    /// of them failed, and the reconciled gate already excludes that.
    private var census: HegotaCensus? {
        shown.filter(\.reached).compactMap(\.census).first
    }

    // MARK: The slot

    /// The one line every scope puts in the slot's reserved row, so the drawing
    /// below it always starts at the same y.
    private var slotHeadline: String? {
        switch section {
        case .home, .sponsors:
            guard head.hasRead, !head.everythingUnreached,
                  let wei = shownBalance ?? head.balanceWei else { return nil }
            return HegotaFormat.crown(wei)
        case .activity:
            return moves.count == 1 ? String(localized: "1 transaction")
                                    : String(localized: "\(String(moves.count)) transactions")
        // **A COUNT, NOT THE MONEY (prd §555, user: "accounts isn't about
        // balances. it could sum how many or how many watching").** This scope
        // led with the summed balance of every reached address, which is the
        // Home crown's own subject one chip away — so the room drew two totals
        // and the second one had to apologise for its scale. `HegotaSection`
        // already says what this scope is: "a watched address always has a
        // roster row, even one that says the chain could not be reached, which
        // is itself the answer." The roster is the subject, so the headline is
        // how many, and the room is back to one crown (§506).
        case .accounts:
            return accounts.count == 1 ? String(localized: "1 address")
                                       : String(localized: "\(String(accounts.count)) addresses")
        case .coins:
            return coins.isEmpty ? nil : HegotaFormat.crown(HegotaCoins.total(coins))
        case .nonces:
            return lanes.count == 1 ? String(localized: "1 nonce key")
                                    : String(localized: "\(String(lanes.count)) nonce keys")
        // **STEPS, not transactions.** The transaction count is already the
        // Activity scope's headline one chip away, so repeating it here would
        // make the two scopes look like the same reading twice. What this scope
        // adds is that those transactions are made of parts.
        case .frames:
            guard let mix = HegotaFrameMix.of(framedMoves) else { return nil }
            return mix.total == 1 ? String(localized: "1 step")
                                  : String(localized: "\(String(mix.total)) steps")
        }
    }

    @ViewBuilder private var slotFigure: some View {
        switch section {
        case .home, .sponsors: crownFigure
        case .activity:        activityFigure
        case .accounts:        accountsFigure
        case .frames:          framesFigure
        case .coins:           coinsFigure
        case .nonces:          noncesFigure
        }
    }

    /// Home: the delta and the curve. The figure itself is the slot's headline,
    /// so it is not drawn twice.
    @ViewBuilder private var crownFigure: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !head.hasRead {
                Text(String(localized: "Reading the chain…"))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            } else if head.everythingUnreached {
                Text(String(localized: "Couldn't reach the chain — nothing below is current."))
                    .dsText(.subhead13).foregroundStyle(DS.attention)
            } else if head.partial {
                Text(String(localized: "\(String(head.watched - head.reached)) of \(String(head.watched)) couldn't be read"))
                    .dsText(.subhead13).foregroundStyle(DS.attention)
            } else if let account = primary, let delta = HegotaRoom.valueDelta(account) {
                Text(PriceObject.percent(delta))
                    .dsText(.subhead13).monospacedDigit()
                    .foregroundStyle(TokenChartStyle.accent(change: delta, scheme: scheme))
            } else {
                Text(head.watched == 1 ? String(localized: "1 address")
                                       : String(localized: "\(String(head.watched)) addresses"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            // EXACT, not sampled: every ETH movement on this chain is a log, so
            // the whole line reconstructs from the moves with no gaps.
            if let account = primary, let series = HegotaRoom.valueSeries(account) {
                let delta = HegotaRoom.valueDelta(account) ?? 0
                TokenChartPlot(chart: TokenChart(closes: series,
                                                 price: series.last ?? 0,
                                                 change: delta),
                               accent: TokenChartStyle.accent(change: delta, scheme: scheme),
                               // **THE BOX, NOT 120 (prd §588)** — the same
                               // EXPRESSION Wallet and vibenet draw, with this
                               // room's own two terms. The box is `figureSlot`
                               // and NOT `visualSlot`: this room passes a
                               // headline, so the chassis has already spent 44
                               // of the slot on the row above. The chrome is
                               // 28, being the `subhead13` delta line 18 and
                               // the `s2` under it 10.
                               //
                               // Serves Home AND Sponsors — both scopes draw
                               // this figure, so a literal here was two rooms'
                               // worth of dead air, not one.
                               height: DSRoomChassis.crownLine(box: DSRoomChassis.figureSlot,
                                                               chrome: 28),
                               pulses: false,
                               lineWidth: 2.6, fillOpacity: 0.24, endpointDot: true)
            }
        }
    }

    /// **ACTIVITY — what came in, what went out, and what carried it.**
    ///
    /// Wallet's flow band, which is the right shape because the question is
    /// identical: money crossed this address's edge, from and to somebody. It
    /// is a REDUCTION of that band and not a reuse — see `HegotaFlow` — because
    /// these amounts are ETH quantities with no price behind them, and a view
    /// that formats dollars would confidently print "$1.00" over one Ether.
    ///
    /// **Hegotá's own bone is the lane colour.** A lane is tinted by the frame
    /// mode that did most of its work, so the drawing says not only that money
    /// went into the vault but that a UTXO step put it there — the one reading
    /// no other chain in this app can offer, arriving inside the flow figure
    /// rather than instead of it. A lane with no frames (an ordinary type-`0x2`
    /// transfer) draws neutral, which is exactly what it is.
    ///
    /// **THE CAPTION IS THE FIGURE NOW (prd §555, user: "i don't like all the
    /// helper text and i want something more juicy for the charts").** The two
    /// numbers this scope is actually about — what came in, what went out —
    /// were a 12pt sentence in the quietest tier on the card, under a second
    /// 12pt sentence apologising for the scale. They are the two column heads
    /// at `price16` instead, sitting over the stacks they total, and the
    /// sentence that said them is deleted rather than moved.
    ///
    /// **The log disclaimer is an AXIS TAG, not a sentence.** It labels the
    /// spine it governs, and what the sentence was protecting — that the
    /// figures are exact — is carried by every lane already printing its own.
    @ViewBuilder private var activityFigure: some View {
        if let band = HegotaFlow.band(moves) {
            // **ONE scale decision across BOTH sides**, for the reason
            // `HegotaScale` exists: this address's biggest inflow is thirty
            // times everything else it has ever done put together, so drawn
            // proportionally every other lane is a four-point sliver — the
            // exact failure the accounts bar hit, in a second figure.
            let amounts = (band.inLanes + band.outLanes).map(\.wei)
            let scale = HegotaScale.of(amounts)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                bandHead(band, scale: scale)
                HStack(alignment: .top, spacing: 0) {
                    laneStack(band.inLanes, band: band, incoming: true,
                              amounts: amounts, scale: scale)
                    // The spine: the address itself, which both sides cross.
                    // Top-aligned with the lane stacks: centred, it hung below
                    // the rows it is supposed to join and read as a stray mark.
                    // It GRADES away from the head now, so the eye starts at
                    // the two totals and runs down into the lanes that make
                    // them up rather than reading the band as two lists.
                    Capsule()
                        .fill(LinearGradient(
                            colors: [DS.tint.opacity(0.75), DS.tint.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: 5, height: spineHeight(band))
                        .padding(.horizontal, DS.Space.s2)
                        .padding(.top, 4)
                    laneStack(band.outLanes, band: band, incoming: false,
                              amounts: amounts, scale: scale)
                }
            }
            // **CENTRED, not top-pinned.** `DSRoomSlot` is a fixed 210pt
            // whatever it holds and aligns its content to the top, so a figure
            // shorter than the box left every pixel of the surplus in one lump
            // underneath it — which read as the drawing falling toward the face
            // rail. Splitting the surplus is what makes a two-lane band and a
            // four-lane one both look deliberate.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// The band's two totals, and the axis tag between them.
    ///
    /// **Net is deliberately absent**: it is not a balance, the crown on Home
    /// already carries that, and two figures that look like totals on one card
    /// is how a reader ends up believing the wrong one. In and out are stated
    /// as two, wearing their own signs, so the band can never be read against
    /// the wrong side.
    ///
    /// **The sub-line is where a pressed lane answers** (§503, moment 05):
    /// the fact takes a row that is always there, so the card never changes
    /// height and the eye is already on the head. It replaces BOTH move
    /// counts rather than one, because a line that swaps only the left half
    /// reads as the left lane having said something about the right one.
    ///
    /// The trailing inset is the settings gear's — `figureCaption`'s own
    /// clearance, spelled here because this row is not a caption.
    /// **THE TWO TOTALS ARE THE FIGURE (prd §566).**
    ///
    /// §555 moved them out of a 12pt caption into `price16` column heads and
    /// deleted the sentences around them. This finishes that move: what the
    /// scope is ABOUT is how much came in and how much went out, so they take
    /// the head rung and everything else on the card drops to `label12`. The
    /// lanes, the spine, the gradient and the log tag are untouched.
    ///
    /// **THE QUALIFIER IS INLINE, AND THAT IS A BUDGET DECISION.** §555's sum
    /// leaves 8pt of slack in the 166pt box and `price40` costs 18 more than
    /// `price16`, so a separate sub-line row would overflow — which is §552's
    /// failure, a card that renders perfectly and continues past the fold. The
    /// caption sits beside each baseline instead, and the head stays ONE row:
    ///
    /// ```
    ///   one line of price40                40
    ///   s3                                 14
    ///   four lanes at 24, three s1 gaps   108
    ///   ─────────────────────────────────────
    ///                                     162   of 166
    /// ```
    ///
    /// **§503's press-in-place survives, by a different route.** That ruling
    /// gave the picked lane a sub-line "a row that is always there, so the card
    /// never changes height" — and with the figure at the head rung there is no
    /// room for one. The answer takes the QUALIFIER's slot instead, so the
    /// height is still constant and the readout is still in place. It drops the
    /// lane's "who", which `laneSteps` prefixes: the picked lane is lit in the
    /// band directly below, so the who is on screen already and the slot spends
    /// its width on the part that is not.
    @ViewBuilder private func bandHead(_ band: HegotaFlow.Band,
                                       scale: HegotaScale) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: DS.Space.s2) {
            sideFigure(band.inWei, incoming: true, band: band, scale: scale)
            Spacer(minLength: DS.Space.s1)
            sideFigure(band.outWei, incoming: false, band: band, scale: scale)
        }
    }

    /// One side of the band: the total, and what it is of.
    ///
    /// Mirrored — the incoming figure leads its caption and the outgoing one
    /// trails it — so each pair hangs off the spine the way its lanes do.
    @ViewBuilder private func sideFigure(_ wei: Decimal,
                                         incoming: Bool,
                                         band: HegotaFlow.Band,
                                         scale: HegotaScale) -> some View {
        let has = wei > 0
        let figure = Text(HegotaFormat.signed(wei, incoming: incoming))
            .dsText(.price40).monospacedDigit().lineLimit(1)
            // A four-decimal ETH total at 40pt heavy is wider than half this
            // card. It SHRINKS rather than rounding: a rounded figure here
            // would be a different number, and §555's log tag exists precisely
            // to promise that these two are exact.
            .minimumScaleFactor(0.45)
            .foregroundStyle(has ? (incoming ? DS.confirm : DS.textPrimary)
                                 : DS.textTertiary)
        let caption = sideQualifier(band, incoming: incoming, scale: scale)
        HStack(alignment: .lastTextBaseline, spacing: DS.Space.s1) {
            if incoming {
                figure
                caption
            } else {
                caption
                figure
            }
        }
    }

    /// What the figure beside it is OF — or, while a lane is pressed, what that
    /// lane ran (§503's readout, moved into this slot; see `bandHead`).
    @ViewBuilder private func sideQualifier(_ band: HegotaFlow.Band,
                                            incoming: Bool,
                                            scale: HegotaScale) -> some View {
        VStack(alignment: incoming ? .leading : .trailing, spacing: 1) {
            // The tag draws ONLY on the log scale, so its absence is how a
            // linear band says linear — §555's rule, kept, and moved to the
            // side whose figure it qualifies first.
            if incoming, scale == .logarithmic {
                Text(String(localized: "log"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(DS.fillFaint))
                    .accessibilityLabel(String(localized: "Bar lengths are a log scale — the figures are exact"))
            }
            Text(qualifierText(band, incoming: incoming))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(incoming ? .leading : .trailing)
        }
        .frame(maxWidth: 96, alignment: incoming ? .leading : .trailing)
    }

    private func qualifierText(_ band: HegotaFlow.Band, incoming: Bool) -> String {
        if let lane = pickedLane {
            // The picked lane's own answer. Only the incoming slot carries it:
            // split across both it would read as two different lanes.
            return incoming ? laneModes(lane) : ""
        }
        return sideCaption(incoming ? band.inLanes : band.outLanes, incoming: incoming)
    }

    /// A pressed lane's steps, without the "who" — see `bandHead`.
    private func laneModes(_ lane: HegotaFlow.Lane) -> String {
        lane.modes.isEmpty
            ? String(localized: "an ordinary transfer, no steps")
            : lane.modes.map(\.label).joined(separator: ", ")
    }

    private func sideCaption(_ lanes: [HegotaFlow.Lane], incoming: Bool) -> String {
        let moves = lanes.reduce(0) { $0 + $1.count }
        if incoming {
            return moves == 1 ? String(localized: "in · 1 move")
                              : String(localized: "in · \(String(moves)) moves")
        }
        return moves == 1 ? String(localized: "out · 1 move")
                          : String(localized: "out · \(String(moves)) moves")
    }

    /// A figure's caption line.
    ///
    /// **The trailing inset is the settings gear.** `DSRoomSlot` gives a figure
    /// the full width, and the chassis floats its gear over the slot's
    /// top-right — so a caption long enough to reach it renders UNDER it, which
    /// is what put "bar lengths are a log scale" behind a cog. Every scope's
    /// caption goes through here so the clearance is stated once rather than
    /// remembered four times.
    /// `lines` is 2 for every figure but Frames, whose slot budget is spent
    /// to the pt (see `frameRows`) — there a wrapped caption pushes the
    /// population note off the bottom edge.
    @ViewBuilder private func figureCaption(_ text: String,
                                            lines: Int = 2) -> some View {
        Text(text)
            .dsText(.label12).foregroundStyle(DS.textTertiary)
            .lineLimit(lines).fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The spine's height is the TALLER side's rows, so it spans exactly what
    /// crosses it rather than a constant that is too long for a one-lane side
    /// and too short for a four-lane one.
    private func spineHeight(_ band: HegotaFlow.Band) -> CGFloat {
        let rows = max(1, max(band.inLanes.count, band.outLanes.count))
        // A row is `laneRowHeight` with `DS.Space.s1` under it, and the last
        // row has no gap — so the spine ends level with the last lane rather
        // than four points past it. The ceiling is the four-lane case, which
        // is `HegotaFlow.laneLimit` plus its folded tail.
        return min(Self.laneRowHeight * 4 + DS.Space.s1 * 3,
                   Self.laneRowHeight * CGFloat(rows) + DS.Space.s1 * CGFloat(rows - 1))
    }

    /// **24, and the four points came out of the two deleted captions
    /// (prd §555).** The band's budget is 168 less the head's 22 + 16 and the
    /// `s3` under it: 118, against four rows at 24 plus three `s1` gaps = 108.
    /// It was 20 while two sentences held the rest.
    ///
    /// **§588 made it derive, and the sum above is the same sum.** The box
    /// went 166 → 256, so the band's budget is `figureSlot` less the head's
    /// `price40` 40 and the `s3` under it — and a row is that, divided by the
    /// four-lane ceiling, less the three `s1` gaps between them. Written as
    /// arithmetic rather than as 24 because this figure CENTRES what it does
    /// not use (`:263`), so getting it wrong is symmetric air rather than a
    /// clip — the quiet kind of wrong nobody reports.
    private static var laneRowHeight: CGFloat {
        let band = DSRoomChassis.figureSlot - 40 - DS.Space.s3
        return max(24, (band - DS.Space.s1 * 3) / 4)
    }

    /// One side of the band, as a mirrored bar chart.
    ///
    /// **Bars grow AWAY from the spine** — inflow leftward, outflow rightward —
    /// which is the whole of why this reads as in-and-out rather than as two
    /// unrelated lists. Rows are a FIXED height and the bar's WIDTH carries the
    /// amount; the first cut sized slabs by height the way Wallet's band does,
    /// and at this slot's height four lanes of proportional height simply
    /// collided with each other.
    ///
    /// **Both sides share ONE scale** (`band.scaleWei`): if each normalised to
    /// its own total, a 0.02 ETH outflow would draw exactly as wide as a 1.03
    /// ETH inflow, and the band's only real claim — that these two are not the
    /// same size — would be the one thing it got wrong.
    @ViewBuilder private func laneStack(_ lanes: [HegotaFlow.Lane],
                                        band: HegotaFlow.Band,
                                        incoming: Bool,
                                        amounts: [Decimal],
                                        scale: HegotaScale) -> some View {
        VStack(alignment: incoming ? .trailing : .leading, spacing: 4) {
            if lanes.isEmpty {
                Text(incoming ? String(localized: "Nothing in")
                              : String(localized: "Nothing out"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity,
                           alignment: incoming ? .trailing : .leading)
            } else {
                ForEach(lanes) { lane in
                    laneRow(lane, incoming: incoming, amounts: amounts, scale: scale)
                }
            }
        }
        // **No Spacer in here.** A VStack holding one takes whatever height is
        // offered, so the band grew to fill the slot and dropped its own
        // caption 80pt below the drawing — the gap read as the figure spilling
        // toward the face rail. The outer stack owns the alignment.
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// One counterparty: a bar for the amount, and its name beside it.
    ///
    /// The label sits OUTSIDE the bar, on the far side from the spine, so a
    /// small lane is as readable as a large one — inside-the-bar labels were
    /// what put "…7a51 · 1 ETH" in the middle of a grey box and left the
    /// small lanes with nowhere to put their names.
    @ViewBuilder private func laneRow(_ lane: HegotaFlow.Lane,
                                      incoming: Bool,
                                      amounts: [Decimal],
                                      scale: HegotaScale) -> some View {
        let share = HegotaScale.share(lane.wei, in: amounts, scale: scale)
        HStack(spacing: 5) {
            if incoming {
                laneLabelView(lane, incoming: true)
                laneBar(lane, share: share, incoming: true)
            } else {
                laneBar(lane, share: share, incoming: false)
                laneLabelView(lane, incoming: false)
            }
        }
        .frame(height: Self.laneRowHeight)
        .contentShape(Rectangle())
        // The press that reveals a lane's steps (§503, moment 05) had no trait,
        // so VoiceOver had nothing to announce and nothing to activate — the
        // fact was reachable by sighted press alone.
        .dsTapCard()
        .onTapGesture {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { pickedLane = lane }
            // Reverts itself: a caption stuck on one lane is a control the
            // room has no way to say is on.
            laneRevert?.cancel()
            laneRevert = Task {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { withAnimation(DS.Motion.standard) { pickedLane = nil } }
            }
        }
    }

    /// What a pressed lane says: which steps carried its money.
    ///
    /// **The one fact the band cannot show and the room has nowhere else to
    /// put** — a lane is tinted by its LEADING mode, so a lane that was half
    /// verify and half UTXO looks exactly like one that was all UTXO.

    /// The bar itself. A floor, because a bar of no width is indistinguishable
    /// from a lane that is not there — and the small lanes are the ones a
    /// person is least able to account for.
    @ViewBuilder private func laneBar(_ lane: HegotaFlow.Lane,
                                      share: Double, incoming: Bool) -> some View {
        GeometryReader { geo in
            // **IT FADES AWAY FROM THE SPINE (prd §555).** A flat capsule is a
            // bar chart drawn twice; a bar that is densest where it meets the
            // address and thins as it leaves reads as movement, which is what
            // the figure is about. The hue is unchanged — it is still the
            // lane's leading frame mode, and the gradient never touches which
            // end is which, because the STRONG end is always the spine.
            Capsule()
                .fill(LinearGradient(
                    colors: [laneTint(lane).opacity(0.9), laneTint(lane).opacity(0.3)],
                    startPoint: incoming ? .trailing : .leading,
                    endPoint: incoming ? .leading : .trailing))
                .frame(width: max(4, geo.size.width * CGFloat(share)), height: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: incoming ? .trailing : .leading)
        }
        // 44, not 52: the lane mark grew 15 -> 20 when it moved onto the face
        // ramp's `badge` tier, and it took the width out of the LABEL — which
        // truncated "0.0313 · vault ×3" to "0.0313 · vault…", dropping the
        // count. The bar can spare the points; the label could not.
        .frame(width: 44)
    }

    @ViewBuilder private func laneLabelView(_ lane: HegotaFlow.Lane,
                                            incoming: Bool) -> some View {
        HStack(spacing: 5) {
            if !incoming { laneMark(lane) }
            Text(laneLabel(lane))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
            if incoming { laneMark(lane) }
        }
        .frame(maxWidth: .infinity, alignment: incoming ? .trailing : .leading)
    }

    @ViewBuilder private func laneMark(_ lane: HegotaFlow.Lane) -> some View {
        if lane.isOther {
            Circle().fill(DS.fillFaint).frame(width: 15, height: 15)
        } else if lane.address.caseInsensitiveCompare(HegotaChain.vault) == .orderedSame {
            Image(systemName: "tray.full").dsGlyph(9)
                .foregroundStyle(DS.tint)
                .frame(width: DS.Face.badge, height: DS.Face.badge)
        } else {
            // `badge` — the ramp's own smallest tier, and its definition
            // exactly ("inside a pill, or beside dense inline text — a mark,
            // not a portrait"). It was a raw 15 until `face-ramp-audit` named
            // it; the vault glyph beside it moves with it, or the two marks in
            // one column stop sharing a baseline.
            WalletFace(address: lane.address, size: DS.Face.badge, circular: true)
        }
    }

    /// **The amount, then who** — the figure is about money, and a lane whose
    /// name runs long must lose the name rather than the number.
    private func laneLabel(_ lane: HegotaFlow.Lane) -> String {
        // **Short on purpose.** Each side gets about a hundred points once the
        // bar and the mark are paid for, and "0.031337 ETH · the UTXO vault ×5"
        // does not fit in it — it truncated to "0.031337 ET…", losing the
        // counterparty entirely, which is the half the label existed for. The
        // amount leads because the figure is about money, and the count rides
        // it because five deposits and one are different facts.
        let who = lane.isOther
            ? String(localized: "others")
            : lane.address.caseInsensitiveCompare(HegotaChain.vault) == .orderedSame
                ? String(localized: "vault")
                : (HegotaWatch.shared.name(for: lane.address)
                   ?? String(lane.address.suffix(4)))
        // The unit is dropped: the caption above already says ETH twice, and
        // repeating it four more times is what pushed "the UTXO vault" out of
        // its own label.
        let amount = HegotaFormat.compact(lane.wei)
        return lane.count > 1
            ? String(localized: "\(amount) · \(who) ×\(String(lane.count))")
            : String(localized: "\(amount) · \(who)")
    }

    /// The mode that did most of this lane's work. **Neutral when there were no
    /// frames** — colouring an ordinary transfer with a step's hue would give
    /// it a step it does not have.
    private func laneTint(_ lane: HegotaFlow.Lane) -> Color {
        guard let lead = lane.modes.first else { return DS.textTertiary }
        return HegotaModeStyle.hue(lead)
    }





    /// **ACCOUNTS — the roster, and what each address does on this chain.**
    ///
    /// See `HegotaRoster` for the ruling (prd §555). It drew a balance bar per
    /// address until this pass, which restated the Home crown on a log scale it
    /// had to apologise for; the money is gone from here entirely and the
    /// headline is a count.
    ///
    /// **No face.** The fused rail sits four points under this figure and the
    /// list four points under that, both drawing the same silhouettes at
    /// `DS.Face.list` — a third size in the same column said nothing the other
    /// two did not (user, 2026-09-01: *"i don't like seeing so many different
    /// sizes of silhouette avatars"*). The name is the identity here and the
    /// card spends its width on what the address IS.
    @ViewBuilder private var accountsFigure: some View {
        let rows = HegotaRoster.rows(accounts)
        let drawn = Array(rows.prefix(HegotaRoster.cap))
        let rest = rows.count - drawn.count
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(drawn) { rosterRow($0) }
            if rest > 0 { rosterMore(rest) }
        }
        // Centred in the slot for `activityFigure`'s reason: the surplus is
        // split rather than pooled under the rows.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// One watched address: its name, and the scopes it has something to say in.
    /// **THE ROW IS WHAT THIS SCOPE IS ABOUT (prd §566).**
    ///
    /// §555 settled what Accounts means — "a watched address always has a
    /// roster row, even one that says the chain could not be reached, which is
    /// itself the answer" — and then drew every word of it at `label12`, the
    /// quiet tier, on the one scope whose subject is these addresses. The name
    /// steps to `price16` and gains the face §555 asked for in its own words
    /// ("i don't like seeing so many different sizes of silhouette avatars"):
    /// ONE size, `DS.Face.list`, the same 36pt disc the hero lockup uses.
    ///
    /// Three rows at 48 with two `s2` gaps is 164 of the 166pt box, which is
    /// why `HegotaRoster.cap` is 3 and why this height is written down.
    ///
    /// The badges are untouched. An unreached address dims its face as well as
    /// its name, so the state is in the drawing and not only in the words.
    @ViewBuilder private func rosterRow(_ row: HegotaRoster.Row) -> some View {
        HStack(spacing: DS.Space.s3) {
            WalletFace(address: row.address, size: DS.Face.list, circular: true)
                .opacity(row.reached ? 1 : 0.45)
            Text(HegotaWatch.shared.name(for: row.address)
                 ?? WalletStore.shortAddress(row.address))
                .dsText(.price16)
                .foregroundStyle(row.reached ? DS.textPrimary : DS.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: DS.Space.s2)
            HStack(spacing: 6) {
                ForEach(row.badges) { rosterBadge($0) }
            }
        }
        .frame(height: Self.rosterRowHeight)
    }

    /// **DERIVED SINCE §588.** Three rows (`HegotaRoom.cap`) filled 164 of the
    /// old 166pt box exactly, which is why it was a literal; at 256 the same
    /// three rows leave ~46pt of air each side, since this figure centres.
    /// The fold row and its gap are subtracted whether or not they draw, so a
    /// roster that gains a "…N more" line does not re-flow the three above it.
    private static var rosterRowHeight: CGFloat {
        let room = DSRoomChassis.figureSlot - 16 - DS.Space.s2
        return max(48, (room - DS.Space.s2 * 2) / 3)
    }

    /// One mark. **A figure only where the mark is an inventory** — see
    /// `HegotaRoster.Mark.counted`; the other two are a glyph in a circle,
    /// which is what keeps four badges inside a row that also has to hold a
    /// name.
    @ViewBuilder private func rosterBadge(_ badge: HegotaRoster.Badge) -> some View {
        let tint = rosterTint(badge.mark)
        if badge.mark == .unread {
            // **The one badge that keeps its words.** It is the alarm this
            // scope is unconditional in order to be able to raise, and a bare
            // triangle beside three cheerful marks is not something a person
            // reads as "we could not reach the chain for this one".
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle").dsGlyph(10, weight: .semibold)
                Text(String(localized: "couldn't read")).dsText(.label12)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
        } else if badge.mark.counted {
            HStack(spacing: 4) {
                Image(systemName: rosterGlyph(badge.mark)).dsGlyph(10, weight: .semibold)
                Text(String(badge.count)).dsText(.label12).monospacedDigit()
            }
            .foregroundStyle(tint)
            .padding(.leading, 6).padding(.trailing, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .accessibilityElement()
            .accessibilityLabel(rosterReadout(badge))
        } else {
            Image(systemName: rosterGlyph(badge.mark)).dsGlyph(10, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: DS.Face.badge, height: DS.Face.badge)
                .background(Circle().fill(tint.opacity(0.15)))
                .accessibilityElement()
                .accessibilityLabel(rosterReadout(badge))
        }
    }

    /// **The hues are the room's own, and two of them deliberately are not.**
    ///
    /// Coins take `hue(.utxo)` because the vault is exactly what that colour
    /// means everywhere else in this room. Frames take a NEUTRAL rather than a
    /// mode hue: a frame transaction is not one step, and painting the badge
    /// verify-purple would tell somebody this address runs verify frames when
    /// its frames may be all UTXO work. Sponsored takes `confirm` — money that
    /// somebody else spent for you is the good news in this room — and keys
    /// take the plain tint, since a nonce counter is machinery rather than a
    /// mode.
    private func rosterTint(_ mark: HegotaRoster.Mark) -> Color {
        switch mark {
        case .unread:    return DS.attention
        case .coins:     return HegotaModeStyle.hue(.utxo)
        case .keys:      return DS.tint
        case .frames:    return DS.textSecondary
        case .sponsored: return DS.confirm
        }
    }

    private func rosterGlyph(_ mark: HegotaRoster.Mark) -> String {
        switch mark {
        case .unread:    return "exclamationmark.triangle"
        case .coins:     return "tray.full"
        case .keys:      return "key.fill"
        case .frames:    return "square.stack.3d.up"
        case .sponsored: return "fuelpump"
        }
    }

    /// What a badge says out loud. The glyphs are learned from the Frames scope
    /// and the sheet heads; VoiceOver has never seen them.
    private func rosterReadout(_ badge: HegotaRoster.Badge) -> String {
        switch badge.mark {
        case .unread:
            return String(localized: "The chain couldn't be read for this address")
        case .coins:
            return badge.count == 1 ? String(localized: "holds 1 UTXO")
                                    : String(localized: "holds \(String(badge.count)) UTXOs")
        case .keys:
            return badge.count == 1 ? String(localized: "1 named nonce key")
                                    : String(localized: "\(String(badge.count)) named nonce keys")
        case .frames:    return String(localized: "sends frame transactions")
        case .sponsored: return String(localized: "somebody else has paid its gas")
        }
    }

    /// The fold. **NAMED, never silent** — a roster showing three of five with
    /// nothing to say so looks exactly like a roster of three.
    @ViewBuilder private func rosterMore(_ rest: Int) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "…").dsText(.label12).foregroundStyle(DS.textTertiary)
            Text(rest == 1 ? String(localized: "1 more")
                           : String(localized: "\(String(rest)) more"))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(rest == 1
            ? String(localized: "1 more address, in the list below")
            : String(localized: "\(String(rest)) more addresses, in the list below"))
    }

    /// **FRAMES — the shape of your transactions, one row each.**
    ///
    /// Small multiples of the strip the sheet already draws, because a frame
    /// transaction IS a sequence and every alternative throws the sequence
    /// away: a mode tally says you ran nine UTXO steps and four verifies
    /// without saying that they came in the same order four times, which is the
    /// only thing the shape of your usage actually looks like.
    ///
    /// **Each row normalises to full width, so the rows compare COMPOSITION,
    /// not size.** Widths within a row are gas-weighted — the strip's own
    /// contract — so a step that burned most of the gas is most of the bar.
    /// Comparing gas ACROSS transactions was tried and refused for
    /// `HegotaScale`'s reason one figure over: the spread is wide enough that
    /// every ordinary transaction draws as a sliver beside one heavy one, and
    /// what the scope is for is what the steps WERE.
    ///
    /// The legend names the modes actually present, in the mix's own ranked
    /// order, so the colours are learnable from the drawing rather than from a
    /// sheet you have to open first.
    /// How tall one frame strip is, so the drawing FILLS the box rather than
    /// sitting at a fixed 14pt inside it (prd §566).
    ///
    /// A sum rather than a guess, in the shape §553 and §555 both use — the
    /// slot is fixed, the chrome under it is known, and what is left is the
    /// drawing's. Floored at the old 14 so a many-rowed band can never be
    /// worse than it was, and capped at 34 so a single strip does not become a
    /// slab: a frame strip is a texture, and one bar filling the box reads as a
    /// progress meter.
    private static func frameStripHeight(rows: Int, hasMore: Bool) -> CGFloat {
        guard rows > 0 else { return 14 }
        // The caption, the legend, §510's remainder line where it draws, and
        // the gaps the `s1` stack puts between all of them.
        let chrome = 16 + DS.Space.s1
                   + 16 + DS.Space.s1
                   + (hasMore ? 16 + DS.Space.s1 : 0)
        let gaps = 5 * CGFloat(rows - 1)
        let room = DSRoomChassis.figureSlot - chrome - gaps
        // **THE CEILING WENT 34 → 44 (prd §588).** It is a ceiling and not a
        // fit for the reason a strip is a strip: one run stretched to a whole
        // 256pt box is a progress meter, not a texture. But 34 was chosen when
        // the box was 166, so at 256 a one-row strip drew 34pt and left ~180
        // under it. 44 is what five rows plus their gaps and this figure's own
        // chrome spend of the new box.
        return max(14, min(44, room / CGFloat(rows)))
    }

    @ViewBuilder private var framesFigure: some View {
        if let mix = HegotaFrameMix.of(framedMoves) {
            let rows = Array(framedMoves.prefix(Self.frameRows))
            // `s1`, not `s2`: the caption, the legend and the note all belong
            // TO the drawing rather than beside it, and the three gaps are
            // also what buys the note its room inside `frameRows`' budget.
            // **THE STRIPS FILL THE BOX (prd §566).** The drawing this scope
            // exists for sat at a fixed 14pt inside a 166pt slot while every
            // word around it was larger. It takes the room that is actually
            // left instead — see `frameStripHeight`.
            //
            // **THE CAPTION STAYS, and deleting it was the mistake this
            // comment exists to record.** It looks like a duplicate of the
            // headline and is not: the headline counts STEPS and the caption
            // counts TRANSACTIONS — §510's exact confusion — and it is also
            // the only place a FAILED step is named. Removing it lost two
            // facts to win 16pt, and orphaned `HegotaFrameMix.leaders`, which
            // this room's harness spends twenty assertions and three mutations
            // on. The strips grow 14 → 22 with every fact kept, which is the
            // trade that was actually available.
            //
            // **§510's line stays whole for the same reason.**
            // The obvious tidy — folding "4 of 11" into the legend's trailing
            // end — drops "step counts cover all", and §510 says in its own
            // words that "naming the remainder without naming the census
            // leaves the contradiction intact": the legend counts steps over
            // every framed transaction while the bars are capped, so both
            // halves have to be said or the two numbers on the card cannot be
            // reconciled by any arithmetic.
            let strip = Self.frameStripHeight(rows: rows.count,
                                              hasMore: framedMoves.count > rows.count)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                figureCaption(framesCaption(mix), lines: 1)
                VStack(spacing: 5) {
                    ForEach(rows) { move in
                        HegotaFrameStrip(frames: move.frames ?? [], height: strip,
                                         weighted: true)
                    }
                }
                framesLegend(mix)
                if framedMoves.count > rows.count {
                    // **THE LEGEND AND THE BARS COUNT DIFFERENT POPULATIONS,
                    // and until this line nothing said so** (prd §510). The
                    // legend is a census over every framed transaction — it
                    // is what the "N steps" headline is made of — while the
                    // drawing is capped at `frameRows`. So on twelve
                    // transactions the legend totalled nineteen steps above
                    // six bars carrying nine of them, and a reader counting
                    // segments against the legend could not make them agree
                    // by any arithmetic. Reported as exactly that.
                    //
                    // Both facts, one line: what is drawn, and what the
                    // counts are over. The no-silent-caps rule is the floor
                    // here, not the whole of it — naming the remainder
                    // without naming the census leaves the contradiction
                    // intact.
                    //
                    // **"step counts", not "counts".** The legend's numbers
                    // are STEPS and this line's are TRANSACTIONS, which is
                    // the 19-against-12 confusion itself — a line naming
                    // neither unit leaves the two numbers on the lower half
                    // of the card still uncomparable.
                    //
                    // Short on purpose beyond that: `lineLimit(1)` and a long
                    // localization truncate to the same silence this line
                    // exists to end, and es/ja/ko/zh all have to fit too.
                    Text(String(localized: "Newest \(String(rows.count)) of \(String(framedMoves.count)) · step counts cover all"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// What the mix says in one line. The commonest step LEADS, because on this
    /// chain that is the sentence — an address that mostly moves UTXOs and one
    /// that mostly verifies are doing different things with the same chain.
    ///
    /// **Only when there IS a commonest step (prd §510).** This read
    /// `mix.busiest` and narrated it as a superlative, which on a tie is a
    /// winner picked by `HegotaFrameMix.of`'s alphabetical tiebreak — a
    /// stable ORDER, never a claim. Shipped as "mostly Send steps" over a
    /// 7–7 Send/Verify split with the legend printing both sevens two lines
    /// down: §83's fake status, refuted on its own card, and reported as the
    /// card not adding up. A tie is a real and interesting answer here, so it
    /// is said rather than broken.

    /// The modes present, in the mix's ranked order, each with its count.
    ///
    /// Deliberately NOT every mode the chain defines: a legend listing four
    /// colours this address has never used teaches the palette and says nothing
    /// about the person, and it is the same dead-chrome objection §83 makes.
    private func framesCaption(_ mix: HegotaFrameMix) -> String {
        let leaders = mix.leaders
        guard !leaders.isEmpty else {
            return String(localized: "What your transactions ran")
        }
        let what = mix.transactions == 1
            ? String(localized: "1 transaction")
            : String(localized: "\(String(mix.transactions)) transactions")
        // A failure is rare here by construction, so it is worth the whole
        // caption when it happens rather than a share of one.
        if mix.failed > 0 {
            return mix.failed == 1
                ? String(localized: "\(what) · 1 step failed")
                : String(localized: "\(what) · \(String(mix.failed)) steps failed")
        }
        // **NOT lowercased.** A mode label is a NAME, and one of them is an
        // initialism — `.lowercased()` rendered the chain's own word as
        // "mostly utxo steps", which is the §500 naming ruling broken by a
        // string transform rather than by a decision. `allcaps-audit` exempts
        // UTXO precisely because it is an initialism; lowercasing it here
        // undoes that from the other side.
        //
        // ONE mode present is not "mostly" anything — it is all of them, and
        // saying "mostly" of a clean sweep understates the one address shape
        // this chain makes most legible.
        if mix.hasCommonest {
            return String(localized: "\(what) · mostly \(leaders[0].mode.label) steps")
        }
        if mix.slices.count == 1 {
            return String(localized: "\(what) · all \(leaders[0].mode.label) steps")
        }
        // Two tied modes are worth naming — "Send and Verify, evenly" is a
        // real reading of an address that verifies everything it sends. Three
        // or more is not a shape, so it is reported as the absence of one
        // rather than as a list nobody can hold.
        if leaders.count == 2 {
            return String(localized: "\(what) · \(leaders[0].mode.label) and \(leaders[1].mode.label), evenly")
        }
        return String(localized: "\(what) · no commonest step")
    }

    @ViewBuilder private func framesLegend(_ mix: HegotaFrameMix) -> some View {
        HStack(spacing: DS.Space.s3) {
            ForEach(mix.slices.prefix(4)) { slice in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(HegotaModeStyle.hue(slice.mode).opacity(0.85))
                        .frame(width: 8, height: 8)
                    Text("\(slice.mode.label) \(String(slice.count))")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// **THE UTXO SET AS A TREEMAP** — the app's own `UnitTreemap`, the same
    /// component Wallet's composition uses.
    ///
    /// Discs sized by area were the first cut and the real data killed them:
    /// the set spans SIXTEEN ORDERS OF MAGNITUDE (0.0059 ETH beside a UTXO of
    /// 1 wei), so every piece but the largest two sat on the minimum radius.
    /// `UnitTreemap` is rank-ordered rather than area-proportional for exactly
    /// this reason, so each UTXO gets a readable, labelled cell.
    @ViewBuilder private var coinsFigure: some View {
        let drawn = tiledCoins
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // **THROUGH `figureCaption`, like every other scope.** This was a
            // bare `Text`, so it took neither of that helper's two guarantees:
            // the 56pt settings-gear clearance, and a line clamp — and an
            // unclamped caption is what turns the 4pt overflow below into a
            // 20pt one on a set whose sentence happens to wrap.
            figureCaption(coinsLine, lines: 1)
            if !drawn.isEmpty {
                // **SIZED TO WHAT IS LEFT OF THE SLOT, AND THE SUM IS WRITTEN
                // DOWN** (prd §555 follow-up, user: *"hegota utxo treemap is
                // clipping on the rail below it"*).
                //
                // `DSRoomSlot` is a hard 210pt with `.clipped()`, less its
                // 30pt reserved headline row AND that row's own `DS.Space.s3`
                // bottom pad — 14 on iOS, and the part that is easy to miss
                // because it lives in the chassis rather than here. So the
                // figure's budget is **166**, exactly as `frameRows` says.
                //
                // 144 did not fit and never had: caption 16 + the stack's gap
                // 10 + 144 is 170, four points over, so `.clipped()` shaved
                // the map's bottom row against the rail slab directly beneath
                // (that section is emitted at `bottom: 0` / `top: 0`, so the
                // cut edge lands flush on the rail).
                //
                // 128 spends 16 + 10 + 128 = 154 and leaves 12 of slack, which
                // is what absorbs a step of Dynamic Type — `label12` is
                // `.caption1`-relative and the slot is not, the same reasoning
                // `frameRows` keeps 16 for.
                //
                // It was 116 while the census line sat underneath, and 116 + a
                // two-line census is 180 in a 168pt box — so the slot clipped,
                // silently, and the map lost its bottom edge (prd §555, user:
                // *"we need to get rid of the '1% of everything…' helper text
                // bc it clips the image of the treemap"*). Raising it to 144
                // fixed that clip by overrunning the budget by less.
                //
                // **Re-do this sum before raising it.**
                //
                // **§588 re-did it, and made it stop being a literal.** The
                // box went 166 → 256, and a 128pt map top-pinned in it was
                // ~102pt of dead air under the drawing this scope exists for.
                // The sum is unchanged in shape and is now written as itself:
                // caption 16 + the stack's gap 10 + the same 12 of slack that
                // absorbs a step of Dynamic Type = 38 of chrome. The tiles
                // take it for free — `tall` is decided by RANK, not by height,
                // and every tile is already `maxHeight: .infinity`.
                UnitTreemap(count: drawn.count,
                            height: DSRoomChassis.crownLine(box: DSRoomChassis.figureSlot,
                                                            chrome: 38),
                            cell: { i in
                    tile(drawn[i], rank: i)
                }, readout: { i in
                    switch drawn[i] {
                    case .coin(let coin):
                        return coin.isChange
                            ? String(localized: "\(HegotaFormat.eth(coin.wei)) — change")
                            : String(localized: "\(HegotaFormat.eth(coin.wei)) — received")
                    case .rest(let count, let wei):
                        return String(localized: "\(String(count)) smaller UTXOs — \(HegotaFormat.eth(wei)) together")
                    }
                })
            }
        }
    }

    /// What a tile holds: one UTXO, or the folded tail.
    private enum CoinTile {
        case coin(HegotaCoin)
        case rest(count: Int, wei: Decimal)
    }

    /// **`UnitTreemap` LAYS OUT AT MOST SIX CELLS** — its `frames(_:)` table
    /// returns six tuples for any larger count, so a seventh cell has no frame
    /// to sit in and the tiles collide and spill out of the slot. That is
    /// exactly what happened here: a real address holds seven UTXOs.
    ///
    /// So the caller folds, which is this component's contract everywhere it is
    /// used (`NetworkReceiptsInsight` does the same). The tail is NAMED and
    /// carries its own total rather than being dropped — a set of seven drawn
    /// as six is a lie about how many pieces the balance is in.
    ///
    /// **FOUR, NOT SIX, AND THAT IS ARITHMETIC (prd §555).** The six-cell table
    /// ends `(2,2,1,1), (3,2,1,1)` — two cells one unit wide. At the slot's
    /// width a unit is 79pt, so 63pt of content, and this room's figures are
    /// `HegotaFormat.eth` strings like "0.000737 ETH" at `callout15`: they do
    /// not fit, and `minimumScaleFactor` shrinks them out of the ramp instead.
    /// The FOUR-cell table is two square heroes over two full-width rows —
    /// every cell at least two units wide, so nothing shrinks and nothing
    /// clips. On this chain that is also the truer picture: a real set spans
    /// sixteen orders of magnitude, so two pieces genuinely are the balance.
    private var tiledCoins: [CoinTile] {
        let cap = 4
        guard coins.count > cap else { return coins.map { .coin($0) } }
        // Biggest first for the drawn slots, since the treemap is rank-ordered;
        // the tail is what is left, smallest pieces together.
        let ranked = coins.sorted { $0.wei > $1.wei }
        let head = ranked.prefix(cap - 1)
        let rest = ranked.dropFirst(cap - 1)
        return head.map { .coin($0) }
            + [.rest(count: rest.count, wei: rest.reduce(Decimal(0)) { $0 + $1.wei })]
    }

    /// One tile. **The cell paints its own ground** — `UnitTreemap` lays out
    /// frames and nothing else, so a cell that is only text has no shape to
    /// see. The well rather than the sheet, for the receipts map's own reason:
    /// a cell washed in the surrounding tone vanishes at low share.
    ///
    /// **THE SECOND LINE IS NO LONGER THE WORD "change" (prd §555, user: *"if
    /// we are in utxo's i dunno why we say 'change' on all the treemap
    /// cells"*).** On a real set most coins are change coming back from your
    /// own spends — five of this address's seven — so the word was on nearly
    /// every cell and distinguished none of them. Worse, the two coins that
    /// were NOT change here are 1 and 2 wei, which fold into the tail, so it
    /// was on literally every visible cell.
    ///
    /// What replaces it is a share and an age, both of which VARY: three of
    /// this set's cells read `0.000737 ETH` to the last digit, and nothing on
    /// them said which coin it was. The share is also what `UnitTreemap`
    /// structurally cannot draw — it tiles by RANK, not by area — so it is the
    /// one number the map owes its reader.
    ///
    /// Origin is not lost: it stays in the FILL, and the caption above names
    /// the mix once. Saying it once beats saying it seven times, which is the
    /// whole of the complaint.
    ///
    /// `rank` is the treemap slot. **Slots 0 and 1 are two units tall and
    /// everything after is one** (`UnitTreemap.frames(4)`), and one unit is
    /// 36pt — enough for a single `callout15` line and not for two, so the
    /// short cells set their amount and share on ONE line rather than clipping
    /// the second. Coupling the cell to the table is the same coupling the
    /// fold above already makes, and it is stated rather than discovered.
    ///
    /// Deliberately NOT a `@ViewBuilder`: the words are resolved by a `switch`
    /// before anything is drawn, and a builder cannot hold statements.
    private func tile(_ tile: CoinTile, rank: Int) -> some View {
        let tall = rank < 2
        let amount: String
        let sub: String
        let dim: Bool
        switch tile {
        case .coin(let coin):
            amount = HegotaFormat.eth(coin.wei)
            sub = coinTileSub(coin)
            dim = false
        case .rest(let count, let wei):
            amount = HegotaFormat.eth(wei)
            sub = restTileSub(count: count, wei: wei)
            dim = true
        }
        return VStack(alignment: .leading, spacing: 2) {
            if tall {
                Text(amount)
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(dim ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sub)
                    .dsText(.label12)
                    .foregroundStyle(dim ? DS.textTertiary : DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // **The share, drawn, in the two cells that have room for it.**
                // The map's own tiling says rank and not magnitude, so the
                // leader and the runner-up can sit in equal squares over very
                // unequal money; this is the one place the difference is
                // visible rather than read.
                if case .coin(let coin) = tile, let share = HegotaCoins.share(coin.wei, of: coins) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.fillLine)
                            Capsule().fill(DS.textPrimary.opacity(0.42))
                                .frame(width: max(2, geo.size.width * CGFloat(share)))
                        }
                    }
                    .frame(height: 3)
                }
            } else {
                HStack(spacing: DS.Space.s2) {
                    Text(amount)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(dim ? DS.textSecondary : DS.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(sub)
                        .dsText(.label12)
                        .foregroundStyle(dim ? DS.textTertiary : DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.Space.s2)
        // **A SHORT CELL CANNOT AFFORD `s2` TOP AND BOTTOM, AND NEVER COULD.**
        // One unit is `(height - 2 × gap) / 3` = 36pt at the height above (it
        // was 41 at 144), while a one-unit cell's content is 10 + a `callout15`
        // line of 25 + 10 = 45. So the row overran its own frame at BOTH
        // heights — the amount sat hard against the cell's bottom edge and the
        // fill stopped short of the text. `s1` takes it to 4 + 25 + 4 = 33,
        // inside 36 with room to spare, and leaves the two-unit heroes at `s2`
        // where they have 82pt for 66pt of content.
        .padding(.vertical, tall ? DS.Space.s2 : DS.Space.s1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                DS.surfaceWell
                fill(tile)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }

    /// A cell's second line: how much of the set it is, and how old it is.
    ///
    /// **The age is what tells identical amounts apart** — three of this
    /// address's coins are `0.000737 ETH` to the last digit. Nil is a real
    /// answer for both (the header read that dates a coin is bounded), and the
    /// line degrades rather than inventing: share alone, age alone, or the
    /// coin's own ordinal, which is always there.
    private func coinTileSub(_ coin: HegotaCoin) -> String {
        let share = HegotaCoins.share(coin.wei, of: coins).map { String(localized: "\(Int(($0 * 100).rounded()))%") }
        let when = HegotaFormat.time(coin.timestamp)
        switch (share, when) {
        case let (.some(s), .some(w)): return "\(s) · \(w)"
        case let (.some(s), .none):    return s
        case let (.none, .some(w)):    return w
        case (.none, .none):           return String(localized: "#\(String(coin.index))")
        }
    }

    /// The folded tail's second line. It says HOW MANY, first and always —
    /// that is the no-silent-caps rule — and its share only when the set has
    /// one to give.
    private func restTileSub(count: Int, wei: Decimal) -> String {
        let more = count == 1 ? String(localized: "1 more")
                              : String(localized: "\(String(count)) more")
        guard let share = HegotaCoins.share(wei, of: coins) else { return more }
        return String(localized: "\(more) · \(String(Int((share * 100).rounded())))%")
    }

    /// The fill says where a UTXO came from: on a real address most of the set
    /// is change from your own spends, and the pieces somebody actually sent
    /// you are the minority worth picking out. The folded tail takes neither —
    /// it is several coins of mixed origin and must not claim one.
    private func fill(_ tile: CoinTile) -> Color {
        switch tile {
        case .coin(let coin): return coin.isChange ? DS.tint.opacity(0.16) : DS.tint.opacity(0.42)
        case .rest:           return DS.fillFaint
        }
    }

    /// A total alone is the very thing this model is not: the balance IS these
    /// unequal pieces, and most of them came back as change from your own
    /// spends rather than arriving from somebody else.
    private var coinsLine: String {
        let change = coins.filter(\.isChange).count
        let held = coins.count == 1 ? String(localized: "held as 1 UTXO")
                                    : String(localized: "held as \(String(coins.count)) UTXOs")
        guard change > 0 else { return held }
        return change == coins.count
            ? String(localized: "\(held), all of it change from your own spends")
            : String(localized: "\(held), \(String(change)) of them change")
    }

    /// **NONCES — the three facts the list below cannot state.**
    ///
    /// **There is no chart here, and that is the finding.** Three were built
    /// and all three were unreadable for one reason: a real address keeps two
    /// or three counters with one or two sends each, and a bar chart, a pip
    /// grid and a staircase all need more steps than that to say anything. A
    /// figure invented for two data points is noise wearing a chart's clothes.
    ///
    /// So: numbers, and specifically the ones the rows underneath are
    /// structurally incapable of showing. **The list enumerates NAMED keys** —
    /// that is what a keyed nonce is — so key 0, the single counter every other
    /// chain gives you and usually the busiest thing on the account, appears
    /// nowhere in it. Nor does any total, because a list of per-key counts
    /// never sums itself.
    @ViewBuilder private var noncesFigure: some View {
        // **The ordinary count comes off the CHAIN now (§504).** Every other
        // reading in this room is reconstructed from transfer logs, and this one
        // could not be: a transaction that moved no ETH emits no transfer log,
        // so counting outgoing moves undercounts — on the chain whose whole
        // subject is transactions that verify, check and call rather than pay,
        // and in the scope whose entire claim is to count sends.
        let account = primary
        let totals = HegotaNonceTotals.of(moves, lanes: lanes,
                                          nonceCount: account?.nonceCount,
                                          valuelessSends: account?.valuelessSends)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            figureCaption(noncesCaption(totals))
            HStack(alignment: .top, spacing: DS.Space.s2) {
                stat(String(totals.counters),
                     String(localized: "Counters in all"), tint: DS.textPrimary)
                stat(String(totals.ordinarySends),
                     String(localized: "On the ordinary nonce"), tint: DS.textSecondary)
                stat(String(totals.keyedSends),
                     String(localized: "On named keys"), tint: DS.tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// The line above the three counters.
    ///
    /// **The independence sentence is the scope's whole content**, so it is the
    /// default — three numbers sitting still say none of it, which is why the
    /// figures count up on their own clocks (§503, moment 04).
    ///
    /// It gives way only for the fact that is strictly newer than it: sends the
    /// chain counted that no transfer log can show. Those are frame
    /// transactions that verified, checked or called and paid nobody — real
    /// sends, invisible to every other reading in this room, and the concrete
    /// evidence for what the Frames scope one chip away is about.
    private func noncesCaption(_ totals: HegotaNonceTotals) -> String {
        guard let quiet = totals.valuelessSends else {
            return String(localized: "Each counter sends without waiting on the others")
        }
        return quiet == 1
            ? String(localized: "1 send moved no value — a step, not a payment")
            : String(localized: "\(String(quiet)) sends moved no value — steps, not payments")
    }

    /// One figure and what it counts. `stat24` is the ramp's own stat size —
    /// big enough to be the drawing, small enough that three sit side by side.
    @ViewBuilder private func stat(_ value: String, _ caption: String,
                                   tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HegotaCountUp(target: Int(value) ?? 0, tint: tint)
            Text(caption)
                // **THREE lines, and the padding pays for the width.** Three
                // boxes across a 342pt slot leave each about 60pt of text once
                // its own inset is paid, and "On the ordinary nonce" wants
                // three lines at that width — at two it truncated mid-word to
                // "ordinary no…", which loses the noun the box exists to name.
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.9)
        }
        // **A FLOOR THAT NOW FILLS THE BOX (prd §588).** 88 was the whole of
        // a stat block in a 166pt slot; at 256 three of them drew ~138 and
        // centred the rest as air. A `minHeight` can only grow a block, so
        // deriving it is safe in the direction that matters — the caption
        // above is clamped and these blocks are the only other thing here.
        .frame(maxWidth: .infinity,
               minHeight: DSRoomChassis.crownLine(box: DSRoomChassis.figureSlot,
                                                  chrome: 60),
               alignment: .topLeading)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s2)
        // A well, so three numbers in a row read as three FACTS rather than as
        // a sentence that lost its words. `surfaceWell` is the ground every
        // other slab in this app sits on; the radius is the card's.
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.surfaceWell)
        }
    }


}

// MARK: - What a frame IS, in colour

/// **A FRAME MODE IS AN IDENTITY, NOT A STATE.**
///
/// Frames are what this chain has that no other chain in this app has, and
/// until this they were drawn by OUTCOME — every strip a wall of one green,
/// because almost every frame succeeds. That palette spent the room's whole
/// colour budget saying "fine" and left the interesting axis, which step ran,
/// as text nobody reads at row size.
///
/// So mode takes the hue and outcome takes an exception: a failed frame gets a
/// destructive border and a pip, and because failure is rare it stands out far
/// more than it did when it was one of two fills. The same five hues are used
/// in the row strip, the sheet strip and the frame's own sheet, so the mapping
/// is learned once and then read everywhere.
enum HegotaModeStyle {
    /// **THE ROOM'S OWN HUE — and it no longer pours** (2026-08-29).
    ///
    /// It was the colour behind every Hegotá sheet head, on the reasoning
    /// that the sheet head's paper needed a colour or it drew a plain raised
    /// surface with nothing saying which room the paper came out of — and
    /// since the catalog gives this seat no brand mark (`DS.brandHue` answers
    /// nil for a devnet, which is right: there is no logo to be faithful to)
    /// the pour was BORROWED from `hue(.utxo)` rather than invented.
    ///
    /// The ink ruling took the pour and left the borrowing intact: every
    /// paper pours `DS.pourInk` now, and "which room did this come out of" is
    /// answered by the sheet you are standing in and the mode disc on it. The
    /// constant STAYS because `hue(.utxo)` is it — the vault segment, the
    /// strips and the frame discs all still draw this cyan, and those are
    /// marks rather than washes.
    ///
    /// `hue(.utxo)` reads it below rather than repeating the literal, or the
    /// pour and the vault segment drift into two cyans that are nearly the
    /// same — the drift nobody sees in a screenshot of one of them.
    static let room = Color(red: 0.30, green: 0.78, blue: 0.92)

    static func hue(_ mode: HegotaFrame.Mode) -> Color {
        switch mode {
        case .verify:    return Color(red: 0.55, green: 0.47, blue: 0.93)   // the signature check
        case .sender:    return DS.confirm                                   // value actually moving
        case .general:   return DS.tint                                      // a call
        case .assertion: return DS.attention                                 // a condition
        case .utxo:      return room                                         // the vault
        case .unknown:   return DS.textTertiary
        }
    }

    /// The step's mark, for a sheet head's disc.
    ///
    /// A GLYPH rather than a face: a frame is a piece of machinery, and an
    /// identicon on one would give it a portrait — the `AssetMark` refusal the
    /// move sheet's own `endpoint(_:mine:)` already makes for the vault and the
    /// nonce manager.
    static func glyph(_ mode: HegotaFrame.Mode) -> String {
        switch mode {
        case .verify:    return "checkmark.shield"
        case .sender:    return "arrow.right"
        case .general:   return "chevron.left.forwardslash.chevron.right"
        case .assertion: return "exclamationmark.triangle"
        case .utxo:      return "tray.full"
        case .unknown:   return "questionmark"
        }
    }

    /// What the step DOES, in a sentence. The mode label is a noun somebody
    /// has to already know; this is the reading, and it is the reason a frame
    /// is worth opening at all.
    static func meaning(_ mode: HegotaFrame.Mode) -> String {
        switch mode {
        case .verify:
            return String(localized: "Checked that the transaction was really authorised by the account — the step that replaces a signature.")
        case .sender:
            return String(localized: "Moved value on the sender's behalf.")
        case .general:
            return String(localized: "Called a contract, the way an ordinary transaction does.")
        case .assertion:
            return String(localized: "Checked a condition after the fact — if it hadn't held, the whole transaction would have failed.")
        case .utxo:
            return String(localized: "Moved money into or out of the vault as discrete pieces, rather than as a balance.")
        case .unknown:
            return String(localized: "A step this app doesn't have a name for yet.")
        }
    }
}

/// **THREE COUNTERS, AND NONE OF THEM WAITS** (prd §503, moment 04).
///
/// The whole content of a keyed nonce is that the queues advance
/// INDEPENDENTLY — a stuck transaction in one does not hold up another — and
/// three numbers sitting still say none of it. So each counts up on its own
/// clock and they finish at different moments, which is the concept drawn
/// rather than described.
///
/// **The rates are derived from the targets, not random.** A bigger number
/// counts faster so every box lands within the same short window; random
/// timing would read as jitter, and identical timing would say they are
/// synchronised, which is the one thing this figure exists to deny.
///
/// Reduce Motion shows the figure, immediately — it is a number, and the
/// count is decoration on top of it.
struct HegotaCountUp: View {
    let target: Int
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    /// The window every counter lands inside. Long enough that three numbers
    /// finishing apart is legible, short enough that nobody waits.
    private static let window: Double = 0.75

    var body: some View {
        Text(String(reduceMotion ? target : shown))
            .dsText(.stat24).foregroundStyle(tint)
            .monospacedDigit().lineLimit(1)
            .task {
                guard !reduceMotion, target > 0 else { shown = target; return }
                // A per-counter stride: each step is the same fraction of ITS
                // own total, so the three tracks run at genuinely different
                // speeds and stop at genuinely different times.
                let steps = min(target, 14)
                let step = max(1, target / steps)
                let pause = UInt64(Self.window / Double(max(1, steps)) * 1_000_000_000)
                var value = 0
                while value < target {
                    value = min(target, value + step)
                    shown = value
                    try? await Task.sleep(nanoseconds: pause)
                }
                shown = target
            }
    }
}

/// The frame anatomy as one bar — a row's texture, and a sheet's diagram.
///
/// **Gaps, never hairlines** (design law): the divisions are `DS.page` slivers,
/// the same idiom the app uses everywhere it has to separate two fills.
///
/// `weighted` gives each segment a width proportional to the gas it burned,
/// floored so a zero-gas frame is still a visible, labellable segment. That
/// floor is the whole correctness of it: a `Verify` frame legitimately runs no
/// code, and proportional-without-a-floor draws the step that authorises the
/// entire transaction as nothing at all.
struct HegotaFrameStrip: View {
    let frames: [HegotaFrame]
    var height: CGFloat = 5
    var labelled = false
    var weighted = false
    /// **The transaction RUNS on open** (prd §503, moment 01).
    ///
    /// A frame transaction is a SEQUENCE, and this strip already draws it as
    /// one — so on the sheet it fills step by step rather than being suddenly
    /// present, each segment starting when the ones before it have finished.
    /// The delays come off the same gas weights the WIDTHS do, so a step that
    /// burned most of the gas visibly takes most of the time: the drawing and
    /// its timing are the same fact told twice.
    ///
    /// Off in the row strip, which is a texture rather than a document, and
    /// off under Reduce Motion — this is an appear-triggered animation and
    /// `design-motion-audit` requires the honour.
    var runs = false
    var onTap: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ran = false

    private static let minShare: Double = 0.12
    /// How long the whole sequence takes to draw. Short enough that nobody
    /// waits for it, long enough that a four-frame transaction reads as four
    /// things rather than one flash.
    private static let runDuration: Double = 0.62

    private func shares(_ width: CGFloat) -> [CGFloat] {
        let gaps = CGFloat(max(0, frames.count - 1)) * 1.5
        let usable = max(0, width - gaps)
        guard weighted else {
            return Array(repeating: usable / CGFloat(max(1, frames.count)), count: frames.count)
        }
        let gas = frames.map { Double($0.gasUsed ?? 0) }
        let total = gas.reduce(0, +)
        // No gas read anywhere means the receipt window didn't reach this
        // transaction — equal widths then, rather than a shape built on
        // nothing.
        guard total > 0 else {
            return Array(repeating: usable / CGFloat(max(1, frames.count)), count: frames.count)
        }
        let raw = gas.map { max(Self.minShare, $0 / total) }
        let sum = raw.reduce(0, +)
        return raw.map { usable * CGFloat($0 / sum) }
    }

    /// When each segment starts, as a fraction of the run — the share of gas
    /// that came BEFORE it. A strip with no gas read falls back to even
    /// spacing rather than starting every segment at once, which would be the
    /// feature switched off while claiming to be on.
    private func starts() -> [Double] {
        let gas = frames.map { Double($0.gasUsed ?? 0) }
        let total = gas.reduce(0, +)
        guard total > 0 else {
            return frames.indices.map { Double($0) / Double(max(1, frames.count)) }
        }
        var running = 0.0
        return gas.map { g in defer { running += g }; return running / total }
    }

    var body: some View {
        let offsets = starts()
        GeometryReader { geo in
            let widths = shares(geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    segment(frame)
                        .frame(width: widths.indices.contains(index) ? widths[index] : 0)
                        // Grown from the LEADING edge, so the bar fills the way
                        // the transaction ran rather than swelling from its
                        // middle.
                        .scaleEffect(x: drawn(index) ? 1 : 0, anchor: .leading)
                        .opacity(drawn(index) ? 1 : 0)
                        .animation(reduceMotion ? nil
                                   : .easeOut(duration: Self.runDuration * 0.34)
                                        .delay(Self.runDuration * offsets[index]),
                                   value: ran)
                        .contentShape(Rectangle())
                        // Each segment opens that step's own sheet, so it is a
                        // button and must say so. Named individually rather
                        // than combined at the strip, or VoiceOver announces
                        // one control for a sequence of four different steps.
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(frame.mode.label)
                        .onTapGesture { onTap?(index) }
                    if index < frames.count - 1 {
                        Rectangle().fill(DS.page).frame(width: 1.5)
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: min(5, height / 2), style: .continuous))
        .accessibilityLabel(frames.map(\.mode.label).joined(separator: ", "))
        .onAppear { ran = true }
    }

    /// A segment is drawn unless it is waiting its turn in a run that has not
    /// started. Everything that is not the running sheet draws immediately.
    private func drawn(_ index: Int) -> Bool {
        guard runs, !reduceMotion else { return true }
        return ran
    }

    @ViewBuilder private func segment(_ frame: HegotaFrame) -> some View {
        let failed = frame.succeeded == false
        Rectangle()
            .fill(failed ? DS.destructive : HegotaModeStyle.hue(frame.mode).opacity(0.85))
            // **A FAILED STEP PULSES ONCE** (moment 06). Failure is rare by
            // construction here, so it stands out by exception rather than by
            // owning a colour — and once, never repeating: a step that keeps
            // flashing is an alarm, and this one already happened.
            .overlay {
                if failed && runs && !reduceMotion {
                    Rectangle().fill(.white)
                        .opacity(ran ? 0 : 0.55)
                        .animation(.easeOut(duration: 0.5).delay(Self.runDuration),
                                   value: ran)
                }
            }
            .overlay(alignment: .leading) {
                if labelled {
                    Text(frame.mode.label)
                        .dsText(.label12)
                        .foregroundStyle(DS.textPrimary.opacity(0.9))
                        .padding(.leading, 6).lineLimit(1)
                }
            }
            // A frame whose receipt could not be paired is drawn HOLLOW rather
            // than as a success it cannot support.
            .opacity(frame.succeeded == nil ? 0.42 : 1)
    }
}

// MARK: - Is this still the same chain?

/// What the room says when the devnet was relaunched.
///
/// **The one state every other guard in this seat misses.** All of them protect
/// against a read that FAILED; a relaunched devnet answers everything perfectly
/// and with nothing — balance zero, no logs, no coins — so without this the
/// room draws a zeroed balance in its largest type, and both hardcoded worked
/// examples go blank at once, with no error anywhere. Hegotá is an experimental
/// devnet and being relaunched from genesis is a thing it is expected to do.
///
/// It sits ABOVE the figure because it governs everything below it: the
/// readings are all still drawn, and they all describe a history the chain no
/// longer has.
struct HegotaChainNotice: View {
    let verdict: HegotaGenesis.Verdict

    var body: some View {
        // `.same` and `.unknown` both draw NOTHING, and they are different
        // silences: one is proof, the other is a first sweep or a read that did
        // not answer. Neither is worth a line — a banner saying "we checked and
        // it's fine" is chrome, and one saying "we couldn't check" is an alarm
        // about our own plumbing on somebody else's screen.
        if verdict == .restarted || verdict == .differentChain {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(headline)
                    .dsText(.subhead13).foregroundStyle(DS.attention)
                Text(detail)
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if verdict == .restarted {
                    // The person's own act. Re-baselining on our schedule is how
                    // a fact nobody was told disappears — and this one costs
                    // them the readings below, so it is theirs to take.
                    Button {
                        DSHaptic.selection()
                        HegotaLiveState.shared.acceptRestart()
                    } label: {
                        Text(String(localized: "Start again from the new chain"))
                            .dsText(.subhead13).foregroundStyle(DS.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.surfaceWell)
            }
        }
    }

    private var headline: String {
        verdict == .restarted
            ? String(localized: "The devnet restarted")
            : String(localized: "This isn't Hegotá")
    }

    /// **Says what happened to the money, because that is the question.** Not
    /// "spent" and not "moved" — the history did not happen on the chain that
    /// is there now, which is a devnet's normal life and not a loss.
    private var detail: String {
        verdict == .restarted
            ? String(localized: "Everything below is from the old chain — those blocks, balances and UTXOs don't exist on the new one. Nothing was spent; the chain was rebuilt from scratch.")
            : String(localized: "A host answered for a different chain, so these readings can't be trusted. Nothing here was changed.")
    }
}

// MARK: - The lists

struct HegotaRoomList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var balanced = false

    let head: HegotaRoom.Head
    let accounts: [HegotaAccount]
    let scoped: String?
    let section: HegotaSection
    var onOpenMove: ((HegotaMove, String) -> Void)? = nil
    var onOpenAccount: ((HegotaAccount) -> Void)? = nil
    var onOpenCoin: ((HegotaCoin, [HegotaCoin], Set<UInt64>) -> Void)? = nil

    private var shown: [HegotaAccount] {
        guard let scoped else { return accounts }
        return accounts.filter { $0.address.caseInsensitiveCompare(scoped) == .orderedSame }
    }
    /// Every address the person watches — what turns a hex counterparty into
    /// "your …a776". Taken from the composed accounts rather than the watch
    /// list so it can never name an account the room isn't drawing.
    private var watched: [String] { accounts.map(\.address) }

    private var coins: [HegotaCoin] {
        shown.filter(\.hasCoins).flatMap { $0.unspent ?? [] }.sorted { $0.index < $1.index }
    }
    /// Every coin these accounts have EVER owned, spent ones included — what a
    /// spend's full anatomy needs. `coins` above is the unspent set the list
    /// draws; this is the set the sheet reasons over.
    private var everyCoin: [HegotaCoin] {
        shown.flatMap(\.coins).sorted { $0.index < $1.index }
    }
    private var unspentIndices: Set<UInt64> { Set(coins.map(\.index)) }

    /// The whole chain's vault, and this address's proven share of it (§555).
    ///
    /// Taken from the primary reached account for `HegotaRoomFigure`'s own
    /// reason: every account's sweep computes the same whole-chain set, so two
    /// of them can only disagree if one failed, and `census` is nil unless the
    /// set reconciled. The SENTENCE is `HegotaCensus.line`'s, so there is one
    /// of it.
    private var censusLine: String? {
        shown.filter(\.reached).compactMap(\.census).first?.line
    }

    private var lanes: [HegotaNonceLane] {
        shown.flatMap(\.lanes).sorted { $0.lastBlock > $1.lastBlock }
    }
    /// Moves paired with the account they belong to. **The owner has to travel
    /// with the move**: in the All scope nothing else can say which of your
    /// addresses a transaction was, and a sheet that can't answer that is a
    /// sheet about a stranger's money.
    private var moves: [(move: HegotaMove, owner: String)] {
        shown.flatMap { account in account.moves.map { (move: $0, owner: account.address) } }
            .sorted { $0.move.block > $1.move.block }
    }

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            switch section {
            // **HOME IS THE ONE DO; ACTIVITY IS THE STREAM (prd §539,
            // 2026-08-31 — vibenet's §533/§538 ruling, carried over at the
            // user's instruction).**
            //
            // This was `movesList(Array(moves.prefix(4)))` against Activity's
            // `movesList(moves)` directly below: the SAME list, truncated, one
            // chip away from the whole of itself. Real duplication, not a
            // summary — a preview of four rows tells you nothing the four rows
            // in Activity don't, and it spent Home on a worse copy of the
            // scope beside it.
            //
            // The fix is not a better preview, it is a different second half:
            // the one write action this room has, in the one slot with room
            // for it. `HegotaSendCard` gates itself on this phone holding a
            // key, so a room with no key draws no form rather than a dead one.
            case .home:     HegotaSendCard()
            case .activity: movesList(moves)
            case .accounts: accountsList
            case .frames:   framesList
            case .coins:    coinsList
            case .nonces:   noncesList
            case .sponsors: sponsorsList
            }
        }
    }

    // MARK: Moves

    @ViewBuilder private func movesList(_ list: [(move: HegotaMove, owner: String)]) -> some View {
        if list.isEmpty {
            empty(String(localized: "Nothing has moved yet."))
        } else {
            ForEach(list, id: \.move.id) { pair in
                HegotaMoveRow(move: pair.move,
                              watched: watched,
                              madeCoins: coinsMade(by: pair.move)) {
                    onOpenMove?(pair.move, pair.owner)
                }
            }
        }
    }

    /// How many UTXOs a deposit turned into.
    ///
    /// **Free** — the coins already carry the transaction that created them, so
    /// this is a join over data the sweep holds, and it turns "Into the UTXO
    /// vault" from a destination into an outcome.
    private func coinsMade(by move: HegotaMove) -> Int {
        guard !everyCoin.isEmpty else { return 0 }
        return everyCoin.filter {
            guard let tx = $0.createdBy else { return false }
            return tx.caseInsensitiveCompare(move.hash) == .orderedSame
        }.count
    }

    // MARK: Frames

    /// The transactions that ran steps, described by what they DID.
    ///
    /// **Not Activity filtered.** Those rows lead with an amount and a
    /// counterparty, because that is what a transfer is; these lead with the
    /// sequence, because a frame transaction's subject is what it ran. The same
    /// transaction appears in both lists saying two different things about
    /// itself, which is the argument for the scope rather than against it.
    ///
    /// Folded by hash for the figure's own reason: a multi-output spend lands as
    /// several moves and is ONE transaction.
    @ViewBuilder private var framesList: some View {
        let list = framedPairs
        if list.isEmpty {
            // Reachable: `HegotaRoom.sections` gates this scope on frames
            // existing, but the scope is remembered across sweeps and a later
            // one can land before its receipts do.
            empty(String(localized: "No steps have been read yet."))
        } else {
            ForEach(list, id: \.move.id) { pair in
                HegotaMoveRow(move: pair.move,
                              watched: watched,
                              madeCoins: coinsMade(by: pair.move),
                              leadsWithFrames: true) {
                    onOpenMove?(pair.move, pair.owner)
                }
            }
        }
    }

    private var framedPairs: [(move: HegotaMove, owner: String)] {
        var seen = Set<String>()
        return moves.filter { pair in
            guard let f = pair.move.frames, !f.isEmpty else { return false }
            return seen.insert(pair.move.hash.lowercased()).inserted
        }
    }

    // MARK: Accounts

    /// This phone's own key, leading the Accounts scope — same placement
    /// ruling as vibenet's create row (user, 2026-08-29: a verb belongs above
    /// the list it acts on, not buried under it).
    ///
    /// **Raises the key sheet through a closure, not a local `.sheet`** — the
    /// same §468 rule vibenet's sibling row learned the hard way (caught by
    /// `vibenet-selftest.sh`, unguarded here but the identical defect: this
    /// list lives inside `FeedScreen`'s own List rows, and a `.sheet` here
    /// resolves to the same presenting controller as the screen's single
    /// sheet — the half-open-then-close bug, paid for three times before
    /// today and almost a fourth and fifth in the same afternoon).
    var onOpenKeySheet: () -> Void = {}
    /// Raise the send sheet — owned by `FeedScreen`, for the reason
    /// `HegotaSendCard`'s own header gives (prd §553).
    var onOpenSend: () -> Void = {}

    @ViewBuilder private var thisPhoneRow: some View {
        Button {
            DSHaptic.selection()
            onOpenKeySheet()
        } label: {
            HStack(spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(HegotaModeStyle.room.opacity(0.18))
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                    // `plus` while there's nothing yet — the same CREATE
                    // semantic vibenet's own `createAccountRow` icon carries,
                    // rather than `key.fill` implying a credential already
                    // exists to manage.
                    Image(systemName: HegotaKey.presence() == .present ? "key.fill" : "plus")
                        .dsGlyph(12, weight: .semibold)
                        .foregroundStyle(HegotaModeStyle.room)
                }
                VStack(alignment: .leading, spacing: 1) {
                    // The title is a VERB while there's no account yet — the
                    // exact wording vibenet's own `createAccountRow` uses
                    // (user, 2026-08-29: this row needs to say "create an
                    // account", the same way vibenet does). A noun-phrase
                    // label ("This phone's account") over an account that
                    // doesn't exist yet reads as a fact rather than an
                    // invitation, and hides the one thing this row does.
                    Text(HegotaKey.presence() == .present
                         ? String(localized: "This phone's account")
                         : String(localized: "Create an account"))
                        .dsText(.heading17)
                        .foregroundStyle(HegotaModeStyle.room)
                        .lineLimit(1)
                    Text(HegotaKey.presence() == .present
                         ? String(localized: "The one account here you control")
                         : String(localized: "This phone becomes its key"))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(HegotaModeStyle.room.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
    }

    @ViewBuilder private var accountsList: some View {
        thisPhoneRow
        ForEach(shown) { account in
            Button {
                DSHaptic.selection()
                onOpenAccount?(account)
            } label: {
            WalletRow(mark: .face(account.address),
                      title: HegotaWatch.shared.name(for: account.address)
                          ?? WalletStore.shortAddress(account.address),
                      subtitle: subtitle(account)) {
                if let wei = account.balanceWei {
                    // **`crown`, not `eth`.** A devnet hands out prefunded
                    // accounts, and one watched here really holds 999,999,898
                    // ETH — printed in full it was shrinking to a size nobody
                    // could read rather than abbreviating like the crown above
                    // it already does.
                    Text(HegotaFormat.crown(wei))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .monospacedDigit().lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func subtitle(_ account: HegotaAccount) -> String {
        guard account.reached else { return String(localized: "Couldn't be read") }
        let held = account.unspent?.count ?? 0
        if held > 0 {
            return held == 1
                ? String(localized: "1 UTXO · \(String(account.moves.count)) moves")
                : String(localized: "\(String(held)) UTXOs · \(String(account.moves.count)) moves")
        }
        return account.moves.count == 1 ? String(localized: "1 move")
                                        : String(localized: "\(String(account.moves.count)) moves")
    }

    // MARK: Coins

    @ViewBuilder private var coinsList: some View {
        if coins.isEmpty {
            // **Three empty states, not one.** "No unspent UTXOs" was told to
            // somebody who had never held one and to somebody who had held four
            // and spent them all — completely different facts about an account,
            // and the second is a history the room was hiding.
            if everyCoin.isEmpty {
                empty(String(localized: "This address has never held a UTXO."))
            } else {
                empty(everyCoin.count == 1
                      ? String(localized: "Its 1 UTXO has been spent.")
                      : String(localized: "All \(String(everyCoin.count)) of its UTXOs have been spent."))
            }
        } else {
            ForEach(coins, id: \.index) { coin in
                Button {
                    DSHaptic.selection()
                    onOpenCoin?(coin, everyCoin, unspentIndices)
                } label: {
                WalletRow(mark: .symbol(coin.isChange ? "arrow.uturn.backward" : "arrow.down",
                                        tint: DS.tint),
                          title: HegotaFormat.eth(coin.wei),
                          subtitle: coinSubtitle(coin)) {
                    // The vault's own allocation counter — which coin came
                    // first. An ORDINAL, which is why the age beside it in the
                    // subtitle is worth having: #45 says nothing about when.
                    Text(String(localized: "#\(String(coin.index))"))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).monospacedDigit()
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // **THE BOOKS BALANCE** (moment 03). This line is a PROOF the app
            // performed — every unspent coin on the chain, summed, equals what
            // the vault contract actually holds — so it arrives after the rows
            // have settled rather than with them, the way a sum lands after
            // its column. No other room in this app can check its own numbers.
            //
            // **AND THE CENSUS RIDES IT NOW (prd §555).** That fact used to sit
            // under the treemap, where 116pt of map plus a two-line share ran
            // the 168pt figure slot over and clipped the drawing. It was never
            // a fact about YOUR coins — it is what the whole chain's vault
            // holds and how many people hold it — so it belongs beside the
            // reconciliation it is a companion to, in a list with as much room
            // as it needs.
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "These UTXOs account for exactly what the vault holds."))
                if let census = censusLine {
                    Text(census)
                }
            }
            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(balanced || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.45),
                       value: balanced)
            .onAppear { balanced = true }
        }
    }

    private func coinSubtitle(_ coin: HegotaCoin) -> String {
        let origin = coin.isChange
            ? String(localized: "change from your own spend")
            : String(localized: "from \(HegotaName.of(coin.source, watched: watched))")
        guard let when = HegotaFormat.time(coin.timestamp) else { return origin }
        return "\(origin) · \(when)"
    }

    // MARK: Nonces

    @ViewBuilder private var noncesList: some View {
        if lanes.isEmpty {
            empty(String(localized: "Everything sent on the ordinary nonce."))
        } else {
            ForEach(lanes) { lane in
                WalletRow(mark: lane.looksLikeAddress
                              ? .face(lane.key)
                              : .monogram(String(lane.key.dropFirst(2).prefix(2)).uppercased(),
                                          tint: DS.tint),
                          title: lane.looksLikeAddress
                              ? WalletStore.shortAddress(lane.key) : lane.key,
                          // **Per-lane facts, not the same sentence N times.**
                          // Every row used to read "its own queue — never waits
                          // for the others", which is chrome: it says the same
                          // thing about every key and so distinguishes none of
                          // them. The explainer belongs once, in the figure's
                          // caption, and the row says where THIS key is.
                          subtitle: laneSubtitle(lane)) {
                    // **THE CHAIN'S OWN COUNT when we have it (§509).** The
                    // observed count undercounts by construction — a send that
                    // moved no ETH emits no transfer log — which is why this
                    // said "at least" before the counter could be read.
                    Text(lane.sendCount == 1 ? String(localized: "1 send")
                                             : String(localized: "\(String(lane.sendCount)) sends"))
                        .dsText(.subhead13)
                        .foregroundStyle(lane.countIsExact ? DS.textSecondary : DS.textTertiary)
                }
            }
        }
    }

    private func laneSubtitle(_ lane: HegotaNonceLane) -> String {
        var parts: [String] = []
        if let seq = lane.seq {
            let n = WalletIngest.hexToInt(seq)
            parts.append(String(localized: "at #\(String(n))"))
        }
        // The per-key form of §504's valueless sends — the steps this key ran
        // that paid nobody, which no transfer log can show.
        if let quiet = lane.valuelessSends {
            parts.append(quiet == 1 ? String(localized: "1 moved no value")
                                    : String(localized: "\(String(quiet)) moved no value"))
        }
        if let when = HegotaFormat.time(lastSend(on: lane)) { parts.append(when) }
        return parts.isEmpty
            ? String(localized: "block \(String(lane.lastBlock))")
            : parts.joined(separator: " · ")
    }

    private func lastSend(on lane: HegotaNonceLane) -> Date? {
        moves.first { $0.move.block == lane.lastBlock }?.move.timestamp
    }

    // MARK: Sponsors

    /// **Grouped by WHO PAID.** Until this the scope was Activity filtered —
    /// the same rows in the same shape, ordered by when rather than by who. One
    /// person paying for eleven of your transactions and eleven people paying
    /// once each are completely different facts about an account, and a flat
    /// list cannot tell them apart.
    @ViewBuilder private var sponsorsList: some View {
        let sponsors = HegotaSponsor.group(moves.map(\.move))
        if sponsors.isEmpty {
            empty(String(localized: "You've paid for everything yourself."))
        } else {
            ForEach(sponsors) { sponsor in
                VStack(spacing: DS.Space.s2) {
                    WalletRow(mark: .face(sponsor.payer),
                              title: HegotaName.of(sponsor.payer, watched: watched),
                              subtitle: sponsor.moves.count == 1
                                  ? String(localized: "paid for 1 transaction")
                                  : String(localized: "paid for \(String(sponsor.moves.count)) transactions")) {
                        // The gas they actually spent — nil unless EVERY move's
                        // fee was read, because a partial sum understates what
                        // somebody gave you and does it silently.
                        if let fee = sponsor.feeWei {
                            Text(HegotaFormat.eth(fee))
                                .dsText(.subhead13).foregroundStyle(DS.tint)
                                .monospacedDigit().lineLimit(1)
                        }
                    }
                    ForEach(sponsor.moves, id: \.id) { move in
                        HegotaMoveRow(move: move, watched: watched,
                                      madeCoins: coinsMade(by: move), inset: true) {
                            onOpenMove?(move, owner(of: move))
                        }
                    }
                }
            }
        }
    }

    private func owner(of move: HegotaMove) -> String {
        moves.first { $0.move.id == move.id }?.owner ?? ""
    }

    @ViewBuilder private func empty(_ text: String) -> some View {
        Text(text).dsText(.body17).foregroundStyle(DS.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Naming the other side

/// The words for a counterparty.
///
/// The DECISION is `HegotaParty`, in the model where a harness can reach it;
/// this is only the wording, because naming a stranger as yourself is the worst
/// failure this room could have and it renders as a perfectly ordinary row.
enum HegotaName {
    static func of(_ address: String, watched: [String]) -> String {
        switch HegotaParty.of(address, watched: watched) {
        case .vault:
            return String(localized: "the UTXO vault")
        case .nonceManager:
            return String(localized: "the nonce manager")
        case .mine(let match), .stranger(let match):
            return HegotaWatch.shared.name(for: match) ?? WalletStore.shortAddress(match)
        }
    }
}

// MARK: - One movement

/// **The app's own row.** Hand-rolled `HStack`s are what made this room read as
/// a database dump beside Wallet's: no leading mark, a smaller title, and none
/// of the row chrome every other list here wears.
struct HegotaMoveRow: View {
    let move: HegotaMove
    var watched: [String] = []
    var madeCoins: Int = 0
    var inset = false
    /// In the Frames scope the row's subject is the SEQUENCE, so the steps lead
    /// the subtitle and the anatomy is drawn wide enough to read as a diagram
    /// rather than as texture. Everywhere else the outcome leads, because there
    /// the subject is money that moved.
    var leadsWithFrames = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        // **EVERY ROW OPENS ITS SHEET.** Gating the tap on having frames left
        // ordinary type-`0x2` transactions dead — and they are most rows on a
        // real address. They have an amount, a counterparty and a block like
        // any other, and the sheet's "one result, not a step for each part" is
        // itself the reading that distinguishes this chain's two eras. A row
        // that opens nothing teaches nothing.
        Button {
            DSHaptic.selection()
            onTap?()
        } label: {
            row.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, inset ? DS.Space.s6 : 0)
    }

    private var row: some View {
        WalletRow(mark: party == .vault ? .symbol("tray.full", tint: DS.tint)
                                        : .face(move.counterparty),
                  title: title, subtitle: subtitle) {
            VStack(alignment: .trailing, spacing: 3) {
                // **SIGNED.** Direction lived only in colour, which is the one
                // channel a person can't be assumed to read — and green-vs-grey
                // is a far weaker signal than a sign every other money row in
                // this app carries.
                // ONE RUNG FOR A SIGNED AMOUNT IN A ROW (prd §587). This was
                // `subhead13` — 12pt — while the Wallet room's own activity
                // rows draw the same fact at `price16` and Frames drew it at
                // `callout15`. Four activity surfaces, three sizes, for one
                // kind of figure. `price16` is the app's row-money rung and
                // the one the most-drawn surface already uses, so the other
                // two come to it.
                Text(HegotaFormat.signed(move.wei, incoming: move.incoming))
                    .dsText(.price16)
                    .foregroundStyle(move.incoming ? DS.confirm : DS.textSecondary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                // The frame anatomy as texture. A legacy transaction draws
                // nothing here, so the two eras are told apart at a glance
                // rather than by reading a joined string of mode names.
                if let frames = move.frames, !frames.isEmpty {
                    HegotaFrameStrip(frames: frames,
                                     height: leadsWithFrames ? 9 : 5,
                                     weighted: leadsWithFrames)
                        .frame(width: leadsWithFrames ? 78 : 54)
                }
            }
        }
    }

    private var party: HegotaParty { HegotaParty.of(move.counterparty, watched: watched) }

    /// **THE VAULT IS NAMED, AND SO ARE YOU.** Most rows on a UTXO-holding
    /// address are moves in and out of the vault predeploy, and plenty of the
    /// rest are between two addresses the same person watches — so leaving both
    /// as `…8312` and `…a776` made a room of your own housekeeping read as a
    /// room full of strangers.
    private var title: String {
        switch party {
        case .vault:
            return move.incoming ? String(localized: "Out of the UTXO vault")
                                 : String(localized: "Into the UTXO vault")
        case .nonceManager:
            return move.incoming ? String(localized: "Out of the nonce manager")
                                 : String(localized: "Into the nonce manager")
        case .mine(let address):
            let name = HegotaWatch.shared.name(for: address)
                ?? WalletStore.shortAddress(address)
            return move.incoming ? String(localized: "In from your \(name)")
                                 : String(localized: "Out to your \(name)")
        case .stranger(let address):
            let name = HegotaWatch.shared.name(for: address)
                ?? WalletStore.shortAddress(address)
            return move.incoming ? String(localized: "In from \(name)")
                                 : String(localized: "Out to \(name)")
        }
    }

    /// What it became, and when. **The outcome beats the mechanism**: a deposit
    /// that turned into three UTXOs says more than the modes that did it, and
    /// the modes are drawn beside it as the strip anyway.
    private var subtitle: String? {
        var parts: [String] = []
        // In the Frames scope the STEPS lead, named in the order they ran —
        // "Verify → UTXO → Call" is the row's whole subject there, and the
        // outcome ("became 3 UTXOs") is what the Activity row already leads
        // with one chip away.
        if leadsWithFrames, let frames = move.frames, !frames.isEmpty {
            parts.append(frames.map(\.mode.label).joined(separator: " → "))
        } else if madeCoins > 0 {
            parts.append(madeCoins == 1 ? String(localized: "became 1 UTXO")
                                        : String(localized: "became \(String(madeCoins)) UTXOs"))
        } else if let frames = move.frames, !frames.isEmpty {
            parts.append(frames.count == 1 ? String(localized: "1 frame")
                                           : String(localized: "\(String(frames.count)) frames"))
        }
        if let when = HegotaFormat.time(move.timestamp) {
            parts.append(when)
        } else if let about = HegotaFormat.approximate(move.estimatedAt) {
            // **A row past the header window is dated to the DAY, and says so.**
            // Interpolated between two headers we really read, which on this
            // chain is honest to seconds — but an estimate is a different grade
            // of fact from a reading, so it never wears a clock.
            parts.append(about)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - The activity sheet

/// One movement's activity sheet — what the transaction actually did.
///
/// **The reading this chain exists to offer.** Every other activity sheet here
/// can say a transaction succeeded; a type-`0x6` receipt reports per FRAME, so
/// this one says which steps ran, what each carried, where it went, and both
/// gas dimensions — and who paid, when it wasn't you.
///
/// A `DSTray`, because trays are never hand-rolled in this app, and routed
/// through `FeedScreen`'s ONE sheet: a `.sheet` on a card inside the List
/// self-dismisses (the row-presentation rule, paid for three times).
struct HegotaMoveSheet: View {
    let move: HegotaMove
    /// Which watched address this move belongs to. **In the All scope nothing
    /// else can say it**, and a sheet that can't answer "whose?" is a sheet
    /// about a stranger's money.
    var owner: String = ""
    var watched: [String] = []
    /// The UTXOs this transaction created, when it created any. Passed in
    /// rather than derived: the join is `createdBy` against every coin the
    /// shown accounts have owned, and only the room holds that set.
    var minted: [HegotaCoin] = []
    var onOpenFrame: ((Int) -> Void)? = nil

    var body: some View {
        // SCROLLABLE, AND DRAG-PAST (prd §560, 2026-09-01) — `HegotaKeySheet`'s
        // own fix, which that sheet applied to itself and the four trays
        // beside it never took. All four are a bare `VStack` against a
        // hand-summed height, which is the shape whose failure that sheet
        // records: "the tray is clipped at the bottom", because real device
        // text metrics ran a line longer than the arithmetic guessed and the
        // last section sat below the tray's own edge with no way to reach it.
        // A `ScrollView` plus a second `.large` detent makes every reachable
        // state reachable regardless of how the number is guessed — the
        // measurement §542 asks for is the better fix and a bigger one, and
        // this is the half that removes the dead end.
        DSTray(title: title, height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    becomes
                    frames
                    facts
                    watchDoor
                    explorer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// **Watch the address on the other side of this transaction.**
    ///
    /// This room's own measurement is the argument for it: coin owners and
    /// keyed-nonce senders are DISJOINT populations on this chain — not one
    /// address does both — so the half of Hegotá you are not watching shows up
    /// in your Activity rows as a stranger, and watching one meant memorising
    /// forty hex characters, leaving the room and pasting them into a setup
    /// screen. The address is already on screen; the door belongs beside it.
    ///
    /// Offered only for a STRANGER: the vault and the nonce manager are
    /// contracts rather than accounts, and one of your own addresses is already
    /// watched, so a button there would do nothing (§83's dead control).
    @ViewBuilder private var watchDoor: some View {
        if case .stranger(let address) = party {
            Button {
                DSHaptic.selection()
                if HegotaWatch.shared.add(address) {
                    // Sweeping immediately is the point — a watch that shows
                    // nothing until the next foreground pass reads as a button
                    // that did nothing.
                    Task { await HegotaLiveState.shared.refresh() }
                }
            } label: {
                Text(String(localized: "Watch \(WalletStore.shortAddress(address))"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
            .buttonStyle(.plain)
        }
    }

    /// Sized to the frames rather than fixed: a one-frame transfer and a
    /// four-frame sponsored spend are very different documents.
    ///
    /// The watch door adds a row for a stranger, so it is paid for here — a
    /// tray sized for a sheet one line shorter clips its own last control.
    private var trayHeight: CGFloat {
        let extra: CGFloat = { if case .stranger = party { return 34 }; return 0 }()
        // The crossing is a fixed block; the minted pieces are one more.
        let crossing: CGFloat = 72
        let becomes: CGFloat = minted.isEmpty ? 0 : (minted.count > 3 ? 96 : 78)
        // The head block's own chrome — `dsSheetHeadBlock` pads `s4` at the top and
        // `s6` plus a tooth at the bottom. The old arithmetic had no term for
        // it because the head was drawn bare, and a deficit CLIPS.
        // Was `60` for the receipt paper's own `s6` top and `s6`-plus-a-tooth
        // bottom. §583 removed the paper; `dsSheetHeadBlock` pads `s4` top and
        // `s6` bottom, so the head is ~19pt shorter. Kept as a named term
        // rather than folded into the base, because a deficit CLIPS and the
        // next person to change the head's padding needs a line to change.
        let paper: CGFloat = 41
        let sponsored: CGFloat = sponsorship == nil ? 0 : 46
        return min(860, 380 + extra + crossing + becomes + paper + sponsored
                        + CGFloat(move.frames?.count ?? 0) * 54)
    }

    private var party: HegotaParty { HegotaParty.of(move.counterparty, watched: watched) }

    private var title: String {
        if party == .vault {
            return move.incoming ? String(localized: "Out of the UTXO vault")
                                 : String(localized: "Into the UTXO vault")
        }
        return move.incoming ? String(localized: "Money in") : String(localized: "Money out")
    }

    /// **THE HEAD IS AN OBJECT, NOT A RUN OF TEXT** (prd §495).
    ///
    /// This sheet opened with eight bare left-aligned blocks on the tray
    /// surface — the "jumble of text" §495 named in the vibenet room, and the
    /// same answer applies: a raised surface, a pour (ink since 2026-08-29), and
    /// the receipt silhouette that makes a head read as one moment rather than
    /// as a column of facts.
    ///
    /// **`dsSheetHeadBlock` directly rather than `DSSheetHead`, and §498 is the
    /// reason it exists to be composed this way**: that component's title slot
    /// is `heading22`, and a money sheet leads with its FIGURE. What is shared
    /// is the head's METRICS — the inset and the room above and below — so this
    /// room and Wallet's cannot drift into two sets of margins. It was the
    /// paper that was shared until §583 deleted it.
    ///
    /// The dateline moved UP here from the foot of the sheet, which is where a
    /// receipt's dateline belongs and why the old `stamp` block is gone.
    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                Text(HegotaFormat.stamp(move.timestamp, block: move.block,
                                        estimated: move.estimatedAt))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let outcome {
                    DSStamp(word: outcome.word, weight: outcome.weight)
                }
            }
            amount.padding(.top, 2)
            crossing.padding(.top, DS.Space.s4)
            if let sponsorship {
                Text(sponsorship)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            }
        }
        .dsSheetHeadBlock()
    }

    /// **The transaction's standing, summarised from the steps below it.**
    ///
    /// It states nothing this sheet does not already draw — the strip and every
    /// frame row carry their own outcome — so this is that reading said ONCE at
    /// the top rather than a new claim. Nil where any step's receipt could not
    /// be paired: "we cannot see" is not a state worth stamping, and the row it
    /// belongs to says so itself.
    private var outcome: (word: String, weight: DSStamp.Weight)? {
        guard let frames = move.frames, !frames.isEmpty else { return nil }
        if frames.contains(where: { $0.succeeded == false }) {
            return (String(localized: "A step failed"), .urgent)
        }
        guard frames.allSatisfy({ $0.succeeded == true }) else { return nil }
        return (String(localized: "Ran"), .good)
    }

    /// **Sponsorship as the head's closing sentence** — what the old `cost`
    /// block said, in the slot a receipt keeps for what it means now. The
    /// amount itself moved to the facts table, where an unsponsored move's
    /// gas also lives: one place for one fact.
    private var sponsorship: String? {
        guard move.isSponsored, let payer = move.payer else { return nil }
        let who = HegotaName.of(payer, watched: watched)
        return move.feeWei.map {
            String(localized: "It cost you nothing — \(who) paid \(HegotaFormat.eth($0)) in gas.")
        } ?? String(localized: "It cost you nothing — \(who) paid the gas.")
    }

    /// **The facts as a TABLE, not as four sentences** (`DSSpecTable`).
    ///
    /// Gas, who paid it and which queue it was sent on are label/value pairs,
    /// and setting them as prose at `subhead13` is most of what made this sheet
    /// read as a wall. The date is not here — it is the head's dateline.
    @ViewBuilder private var facts: some View {
        if hasFacts {
            DSSpecTable {
                if let fee = move.feeWei {
                    DSSpecRow(label: Text("Gas"),
                              value: Text(verbatim: HegotaFormat.eth(fee)))
                }
                // Named only when it is NOT you: a receipt telling you that you
                // paid your own gas is a row that says nothing.
                if move.isSponsored, let payer = move.payer {
                    DSSpecRow(label: Text("Paid by"),
                              value: Text(verbatim: HegotaName.of(payer, watched: watched)))
                }
                if !move.nonceKeys.isEmpty {
                    DSSpecRow(label: Text(move.nonceKeys.count == 1 ? "Nonce key" : "Nonce keys"),
                              value: Text(move.nonceKeys.count == 1
                                          ? String(localized: "\(move.nonceKeys[0]) — a queue of its own")
                                          : String(localized: "\(String(move.nonceKeys.count)) at once")))
                }
            }
        }
    }

    /// An empty `DSSpecTable` is a zero-height `Grid` that still costs its
    /// enclosing stack a `DS.Space.s6` gap — a hole in the sheet with nothing
    /// in it.
    private var hasFacts: Bool {
        move.feeWei != nil || move.isSponsored || !move.nonceKeys.isEmpty
    }

    @ViewBuilder private var amount: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HegotaFormat.signed(move.wei, incoming: move.incoming))
                // `price40`, the app's own money-receipt hero (§363).
                // It was picked because `price48` was the WALLET CROWN and this
                // is the same object one room over — a devnet receipt must not
                // outsize the wallet's. §551 brought that crown down to this
                // same rung, so the two now MATCH rather than merely not
                // clashing, which is the stronger version of the same rule.
                .dsText(.price40)
                .foregroundStyle(move.incoming ? DS.confirm : DS.textPrimary)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
        }
    }

    /// **WHO, AND WHICH WAY — drawn once instead of said twice.**
    ///
    /// This was two lines of tertiary prose ("in from the UTXO vault" / "on
    /// your 0x8b54…a013") that a reader had to assemble into a direction. Both
    /// facts are the same fact — money crossed this address's edge, from
    /// somebody to somebody — and an arrow between two marks states it in one
    /// pass, which is `WalletFlowBand`'s own reasoning at sheet scale.
    ///
    /// The sides follow the DIRECTION rather than a fixed layout: your address
    /// is on the right for an inbound move and on the left for an outbound one,
    /// so the arrow always reads left-to-right the way the money went.
    @ViewBuilder private var crossing: some View {
        HStack(spacing: DS.Space.s2) {
            if move.incoming {
                endpoint(move.counterparty, mine: false)
                arrow
                endpoint(owner, mine: true)
            } else {
                endpoint(owner, mine: true)
                arrow
                endpoint(move.counterparty, mine: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .dsGlyph(13).foregroundStyle(DS.textTertiary)
    }

    /// One side of the crossing.
    ///
    /// A contract gets its own mark rather than a face: the vault and the nonce
    /// manager are predeploys, and an identicon on either would give a piece of
    /// chain machinery a portrait, which is exactly the `AssetMark` refusal
    /// (never invent an identity for a thing that has none).
    @ViewBuilder private func endpoint(_ address: String, mine: Bool) -> some View {
        let party = HegotaParty.of(address, watched: watched)
        VStack(spacing: 6) {
            Group {
                switch party {
                case .vault, .nonceManager:
                    ZStack {
                        Circle().fill(DS.surfaceWell)
                        Image(systemName: party == .vault ? "tray.full" : "number")
                            .dsGlyph(15).foregroundStyle(DS.tint)
                    }
                default:
                    // An identicon is a function of an ADDRESS, so an empty one
                    // would draw a face for nobody — a portrait of a string we
                    // do not have. `owner` is always supplied by the room, but
                    // the parameter has a default and a mark that lies is worse
                    // than a plain one.
                    if address.isEmpty {
                        Circle().fill(DS.surfaceWell)
                    } else {
                        WalletFace(address: address, size: DS.Face.list, circular: true)
                    }
                }
            }
            .frame(width: DS.Face.list, height: DS.Face.list)
            Text(address.isEmpty
                 ? String(localized: "you")
                 : (mine ? String(localized: "your \(HegotaName.of(address, watched: watched))")
                         : HegotaName.of(address, watched: watched)))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// **What a deposit BECAME.** The vault turns one amount into countable
    /// pieces, and that is the whole UTXO reading — but until now the only
    /// place it appeared was a row subtitle ("became 2 UTXOs"), a number with
    /// no way to see the pieces it counted. Costs nothing: the join already
    /// exists, it simply had no surface.
    @ViewBuilder private var becomes: some View {
        if !minted.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(minted.count == 1
                     ? String(localized: "It became 1 UTXO")
                     : String(localized: "It became \(String(minted.count)) UTXOs"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                HStack(spacing: DS.Space.s2) {
                    ForEach(minted.sorted { $0.wei > $1.wei }.prefix(3), id: \.index) { coin in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(HegotaFormat.eth(coin.wei))
                                .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            Text(coin.isChange ? String(localized: "change")
                                               : String(localized: "sent"))
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, DS.Space.s2)
                        .background {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.surfaceWell)
                        }
                    }
                }
                // NAMED, never dropped — three cells is a width budget, and a
                // spend that made five pieces drawn as three is a lie about how
                // many pieces the money is in (the coins figure's own rule).
                if minted.count > 3 {
                    Text(String(localized: "and \(String(minted.count - 3)) more, in the UTXOs scope"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    @ViewBuilder private var frames: some View {
        if let list = move.frames, !list.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(list.count == 1 ? String(localized: "1 frame")
                                     : String(localized: "\(String(list.count)) frames"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                // **THE SHAPE FIRST, THEN THE DETAIL** — and the shape is
                // WEIGHTED BY GAS, so the bar says where the work happened
                // rather than only what order the steps ran in. A `Verify`
                // frame runs no code and is floored to stay visible: the step
                // that authorises the whole transaction must not draw as
                // nothing.
                HegotaFrameStrip(frames: list, height: 24, labelled: true,
                                 weighted: true, runs: true) { onOpenFrame?($0) }
                ForEach(Array(list.enumerated()), id: \.offset) { index, frame in
                    Button {
                        DSHaptic.selection()
                        onOpenFrame?(index)
                    } label: {
                        frameRow(index: index, frame: frame).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            // An ordinary type-0x2 transaction has no frames and never will —
            // said rather than left as an empty space.
            Text(String(localized: "An ordinary transaction — it reports one result, not a step for each part."))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The chain's own explorer. **The account sheet had a door and this one
    /// dead-ended** — on the sheet most likely to raise a question this app
    /// cannot answer.
    @ViewBuilder private var explorer: some View {
        if let url = URL(string: "\(HegotaIdentity.explorer)/tx/\(move.hash)") {
            Link(destination: url) {
                Text(String(localized: "Open in the explorer"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
        }
    }

    @ViewBuilder private func frameRow(index: Int, frame: HegotaFrame) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            // The mode's own hue, and a hollow pip when the receipt could not
            // be paired — outcome as an exception rather than as the palette.
            Circle()
                .fill(frame.succeeded == false ? DS.destructive
                      : frame.succeeded == true ? HegotaModeStyle.hue(frame.mode) : Color.clear)
                .overlay(Circle().strokeBorder(DS.textTertiary,
                                               lineWidth: frame.succeeded == nil ? 1 : 0))
                .frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "\(String(index + 1)). \(frame.mode.label)"))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                if let target = frame.target {
                    Text(HegotaName.of(target, watched: watched))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                if frame.wei > 0 {
                    Text(HegotaFormat.eth(frame.wei))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary).monospacedDigit()
                }
                // BOTH dimensions: this chain prices execution and state
                // separately, and a frame that only moves value runs no code —
                // so a zero execution figure is a fact, not a missing reading.
                if let gas = frame.gasUsed {
                    Text(String(localized: "\(String(gas)) gas"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary).monospacedDigit()
                }
            }
            WalletRowChevron().padding(.top, 3)
        }
    }
}

// MARK: - One frame

/// A single step of a frame transaction, as its own document.
///
/// **This is what makes frames first-class rather than a detail.** A frame was
/// a row inside another sheet with nowhere to go — the chain's defining object,
/// and the only thing in this room you could not open. It also carried a mode
/// name (`Verify`, `Check`) that means nothing to somebody who has not read
/// EIP-8141, with no room beside it to say what the step actually did.
///
/// It deliberately does NOT get a scope of its own: a frame is a PART of a
/// move, not something you own, and a flat list of every step torn out of the
/// transactions that give them meaning would say the same thing Activity says.
struct HegotaFrameSheet: View {
    let move: HegotaMove
    let index: Int
    var watched: [String] = []
    /// Step-to-step through the ONE sheet — the same route swap the move sheet
    /// already uses to open a frame, so the neighbour rises where this step was
    /// rather than as a second tray over it.
    var onOpenFrame: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var frame: HegotaFrame? {
        guard let frames = move.frames, frames.indices.contains(index) else { return nil }
        return frames[index]
    }
    private var total: Int { move.frames?.count ?? 0 }

    var body: some View {
        DSTray(title: frame?.mode.label ?? String(localized: "Step"),
               // The head block's own chrome (`dsSheetHeadBlock` pads s4 top
               // and s6 bottom) plus the disc it now carries.
               height: total > 1 ? 720 : 640, ink: true,
               // Scrollable and drag-past — see `HegotaMoveSheet.body`.
               detents: [.height(total > 1 ? 720 : 640), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if let frame {
                        head(frame)
                        position
                        gasShare(frame)
                        facts(frame)
                        neighbours
                    } else {
                        Text(String(localized: "This step is no longer available."))
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// **THE HEAD IS AN ARRANGEMENT** — the move sheet's head, one level down
    /// (prd §495, and §583 for why there is no paper under it), composed
    /// through `dsSheetHeadBlock` for that sheet's stated reason: a step that
    /// moved value leads with its FIGURE, and `DSSheetHead`'s title slot is
    /// `heading22`.
    ///
    /// **The old `heading28` is gone and that was a real inversion**: it set
    /// the mode label one rung ABOVE the tray title sitting directly on top of
    /// it, so the sheet's own name read smaller than a line inside it. A
    /// valueless step now leads with what it DID, at `reading20` — running
    /// prose that is the whole point of the surface it sits on, which is that
    /// rung's own definition — and the mode name is not repeated, because the
    /// tray title above already carries it.
    ///
    /// The mode's hue moved from the type to the DISC and the pour. Colour
    /// carries identity here, not emphasis, and a bold coloured headline is
    /// the same fact said louder rather than said better.
    @ViewBuilder private func head(_ frame: HegotaFrame) -> some View {
        let tone = HegotaModeStyle.hue(frame.mode)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(tone.opacity(0.16))
                    Image(systemName: HegotaModeStyle.glyph(frame.mode))
                        .dsGlyph(24).foregroundStyle(tone)
                }
                .frame(width: DS.Face.shelf, height: DS.Face.shelf)
                Spacer(minLength: 0)
                // **Answered in every case, not only the bad ones** — the
                // reading the old dot-and-word carried, in the slot every other
                // sheet in the app keeps for a state. `DSStamp`'s weights are a
                // closed set with no failure rung, so a failed step wears
                // `urgent` (attention) rather than `destructive`.
                DSStamp(word: outcomeWord(frame), weight: outcomeWeight(frame))
            }
            Text(lead(frame))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s3)
            if frame.wei > 0 {
                Text(HegotaFormat.eth(frame.wei))
                    // `price40`, the money-receipt hero — see the move sheet's
                    // `amount`, and §551.
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.top, 2)
                Text(HegotaModeStyle.meaning(frame.mode))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            } else {
                Text(HegotaModeStyle.meaning(frame.mode))
                    .dsText(.reading20).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .dsSheetHeadBlock()
    }

    /// Where the step sat, and whether it carried money — the two facts the
    /// figure below cannot say for itself. One line rather than two, because a
    /// step of one is not a sequence and "moved no value" beside a figure of
    /// zero would be the same fact twice.
    private func lead(_ frame: HegotaFrame) -> String {
        let where_ = total > 1
            ? String(localized: "Step \(String(index + 1)) of \(String(total))")
            : String(localized: "One step")
        guard frame.wei > 0 else {
            return String(localized: "\(where_) · moved no value")
        }
        return String(localized: "\(where_) · moved by this step")
    }

    private func outcomeWord(_ frame: HegotaFrame) -> String {
        switch frame.succeeded {
        case .some(true):  return String(localized: "Ran")
        case .some(false): return String(localized: "Failed")
        // NOT "failed": a receipt we could not pair is a step whose outcome we
        // cannot see, and the strip draws it hollow for the same reason.
        case .none:        return String(localized: "Outcome unknown")
        }
    }

    /// `quiet` for the unknown, deliberately. It used to wear `DS.attention`,
    /// which raises an alarm about a reading we simply do not have —
    /// `DSStamp`'s own doc: quiet is a real answer, not an absence.
    private func outcomeWeight(_ frame: HegotaFrame) -> DSStamp.Weight {
        switch frame.succeeded {
        case .some(true):  return .good
        case .some(false): return .urgent
        case .none:        return .quiet
        }
    }

    /// **What this step cost of the whole transaction.**
    ///
    /// The facts below already name this step's own gas, and a raw 36,334 means
    /// nothing without the total beside it — a share does. Drawn only over a
    /// sequence whose gas was actually read: with one frame the share is
    /// trivially everything, and with no gas read at all the bar would be a
    /// shape built on nothing (the strip's own rule for its widths).
    @ViewBuilder private func gasShare(_ frame: HegotaFrame) -> some View {
        if let frames = move.frames, frames.count > 1, let mine = frame.gasUsed {
            let whole = frames.reduce(UInt64(0)) { $0 + ($1.gasUsed ?? 0) }
            if whole > 0 {
                let share = Double(mine) / Double(whole)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.fillFaint)
                            Capsule().fill(HegotaModeStyle.hue(frame.mode).opacity(0.85))
                                .frame(width: max(0, geo.size.width * CGFloat(share)))
                        }
                    }
                    .frame(height: 10)
                    // Sized from data, so it earns its entrance (design-motion
                    // law): the bar wipes in rather than being suddenly a
                    // measurement, and stands still under Reduce Motion.
                    .chartWipe(reduceMotion: reduceMotion)
                    Text(String(localized: "\(Int((share * 100).rounded()))% of the transaction's gas"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    /// The steps either side, as doors.
    ///
    /// **Reading a four-step transaction meant closing and reopening four
    /// times** — the sheet knew its own position in the sequence and offered no
    /// way along it. Each door names the neighbour's MODE rather than saying
    /// "Previous", because what somebody wants to know is what comes next, not
    /// that something does.
    @ViewBuilder private var neighbours: some View {
        if let frames = move.frames, frames.count > 1 {
            HStack(spacing: DS.Space.s3) {
                if index > 0 { step(frames[index - 1], at: index - 1, back: true) }
                Spacer(minLength: 0)
                if index + 1 < frames.count { step(frames[index + 1], at: index + 1, back: false) }
            }
        }
    }

    @ViewBuilder private func step(_ frame: HegotaFrame, at target: Int,
                                   back: Bool) -> some View {
        Button {
            DSHaptic.selection()
            onOpenFrame?(target)
        } label: {
            HStack(spacing: DS.Space.s2) {
                if back {
                    Image(systemName: "chevron.left").dsGlyph(11)
                        .foregroundStyle(DS.textTertiary)
                }
                VStack(alignment: back ? .leading : .trailing, spacing: 1) {
                    Text(String(localized: "Step \(String(target + 1))"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                    Text(frame.mode.label)
                        .dsText(.callout15)
                        .foregroundStyle(HegotaModeStyle.hue(frame.mode))
                }
                if !back {
                    Image(systemName: "chevron.right").dsGlyph(11)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Where this step sat in the sequence — the whole strip again, with this
    /// segment named. A step out of its order is a step without its meaning.
    @ViewBuilder private var position: some View {
        if let frames = move.frames, frames.count > 1 {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(String(localized: "Step \(String(index + 1)) of \(String(total))"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                HegotaFrameStrip(frames: frames, height: 20, labelled: true)
                    .opacity(0.55)
                    .overlay(alignment: .leading) { EmptyView() }
            }
        }
    }

    /// **Label/value pairs, drawn as label/value pairs** (`DSSpecTable`).
    ///
    /// These were four prose sentences — "21000 execution gas" — which is a
    /// table written out longhand: nothing lines up, and the labels and the
    /// figures wear the same ink at the same size. The component sizes its
    /// column to its own longest label, so the two gas rows align with each
    /// other rather than with some other sheet's table.
    @ViewBuilder private func facts(_ frame: HegotaFrame) -> some View {
        DSSpecTable {
            if let target = frame.target {
                DSSpecRow(label: Text("Ran against"),
                          value: Text(verbatim: HegotaName.of(target, watched: watched)))
            }
            // BOTH gas dimensions, and this chain is the reason the distinction
            // is worth a line: it prices execution and state separately, so a
            // step that only moves value really does burn zero execution gas.
            if let gas = frame.gasUsed {
                DSSpecRow(label: Text("Execution gas"),
                          value: Text(verbatim: String(gas)))
            }
            if let state = frame.stateGasUsed {
                DSSpecRow(label: Text("State gas"),
                          value: Text(verbatim: String(state)))
            }
            DSSpecRow(label: Text("When"),
                      value: Text(verbatim: HegotaFormat.stamp(move.timestamp, block: move.block,
                                                               estimated: move.estimatedAt)))
        }
    }
}

// MARK: - Amounts

/// Amounts, in ETH, never in money. This is test ETH and it is worth nothing,
/// so a figure here is a QUANTITY — there is no price to convert with, and
/// inventing one would be §83's fake status where a reader cannot check us.
enum HegotaFormat {
    /// **A UTXO that exists must never render as zero.** Found by seeding the
    /// demo from the real chain rather than invented numbers: one watched
    /// address genuinely holds UTXOs of 1 and 2 WEI beside coins of 0.005 ETH,
    /// and at six decimal places both printed as "0 ETH" — money on screen,
    /// shown as nothing, in the room whose whole claim is that it shows you
    /// your pieces. Below ETH's display floor the figure is given in wei.
    static func eth(_ wei: Decimal) -> String {
        let value = HegotaCoins.eth(wei)
        if wei > 0, value < Decimal(string: "0.000001")! {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            let text = f.string(from: wei as NSDecimalNumber) ?? "0"
            return wei == 1 ? String(localized: "1 wei") : String(localized: "\(text) wei")
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        // Enough places to keep a fee visible: the real spend measured on this
        // chain paid 0.000059 ETH, which four places would round away to zero.
        f.maximumFractionDigits = value < 1 ? 6 : 4
        let text = f.string(from: value as NSDecimalNumber) ?? "0"
        return String(localized: "\(text) ETH")
    }

    /// The same figure wearing its direction.
    ///
    /// **Direction lived only in colour**, which is the one channel that cannot
    /// be assumed — and green-against-grey is a far weaker signal than the sign
    /// every other money row in this app carries. A true minus (U+2212), not a
    /// hyphen, so the digits stay aligned in a monospaced column.
    static func signed(_ wei: Decimal, incoming: Bool) -> String {
        guard wei > 0 else { return eth(wei) }
        return (incoming ? "+" : "\u{2212}") + eth(wei)
    }

    /// How long ago, in the app's own coarse grain.
    ///
    /// **Nil is a real answer and the room draws nothing for it.** The header
    /// read that dates these rows is bounded, so a move past the window has no
    /// time — which is a different thing from a move at the epoch, and
    /// substituting "now" for a miss is the fake status §83 bans.
    static func time(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Date().timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "just now") }
        if minutes < 60 { return String(localized: "\(String(minutes))m ago") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(String(hours))h ago") }
        let days = hours / 24
        if days < 7 { return String(localized: "\(String(days))d ago") }
        let weeks = days / 7
        if weeks < 52 { return String(localized: "\(String(weeks))w ago") }
        return String(localized: "\(String(weeks / 52))y ago")
    }

    /// An INTERPOLATED time, stated to the day and hedged in words.
    ///
    /// **A different grade of fact from `time(_:)`, and drawn as one (§504).**
    /// Measured on this chain: 310,833 blocks ran 72 seconds ahead of exact
    /// six-second spacing — twelve missed slots in twenty-one days — so a block
    /// bracketed between two headers we really read is accurate to seconds. It
    /// still never wears a clock, because the total drift says how far the
    /// chain slipped overall and nothing about where the gaps SIT: two of them
    /// inside one short history would move that row by however long they were.
    /// The day absorbs that; a minute would not.
    static func approximate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return String(localized: "around \(f.string(from: date))")
    }

    /// A sheet's dateline. The block is the chain's own identity for the
    /// moment — what you would quote to somebody else — and the date is the
    /// only form of it a person can read, so both.
    ///
    /// An estimate is admitted as an estimate rather than promoted: the block
    /// number beside it is exact either way, so the row still carries something
    /// quotable even when the time is derived.
    static func stamp(_ date: Date?, block: UInt64, estimated: Date? = nil) -> String {
        guard let date else {
            guard let about = approximate(estimated) else {
                return String(localized: "Block \(String(block))")
            }
            return String(localized: "\(about) · block \(String(block))")
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return String(localized: "\(f.string(from: date)) · block \(String(block))")
    }

    /// A lane label's figure: the number alone, no unit, four places at most.
    ///
    /// **Not a second opinion about the amount** — it is `eth`'s output with
    /// the unit removed and the tail clipped, for a label that has about a
    /// hundred points to say an amount AND a counterparty in. A value too small
    /// to survive four places falls back to the full form rather than printing
    /// zero, which on a flow lane would read as money that did not move.
    static func compact(_ wei: Decimal) -> String {
        let value = HegotaCoins.eth(wei)
        guard value >= Decimal(string: "0.0001")! else { return eth(wei) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = value < 1 ? 4 : 2
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    /// The CROWN's figure, which has a width the rows do not. A devnet hands
    /// out prefunded accounts — one watched here really holds 999,999,899 ETH
    /// — and printed in full that runs off the card.
    static func crown(_ wei: Decimal) -> String {
        let value = HegotaCoins.eth(wei)
        guard value >= 1000 else { return eth(wei) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        // Thresholds sit just under the round number, or 999,999,899 rounds to
        // one decimal and prints "1,000M" — a bigger unit's worth of digits in
        // the smaller unit.
        let (scaled, suffix): (Decimal, String) =
            value >= 999_950_000 ? (value / 1_000_000_000, "B")
            : value >= 999_950 ? (value / 1_000_000, "M")
            : (value / 1_000, "K")
        let text = f.string(from: scaled as NSDecimalNumber) ?? "0"
        return String(localized: "\(text)\(suffix) ETH")
    }
}

// MARK: - One account

/// A watched address's own sheet.
///
/// **Where the money split is stated in full.** The room's crown sums the
/// account balances and the Accounts figure shows the split per account; this
/// is where one address says all of it — what sits in the account, what sits as
/// coins in the vault, and what it has actually been doing.
///
/// It carries no scoping control: picking an account is what the face rail
/// above the room is for, and a second door to the same state is the
/// duplication §83 warns about.
struct HegotaAccountSheet: View {
    let account: HegotaAccount
    /// Where a fact leads. **The sheet dead-ended before this**: it named three
    /// readings the room can actually show and offered no way to any of them,
    /// which is the dead control §83 bans wearing the shape of a summary.
    var onScope: ((HegotaSection) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    /// The head block's own chrome — `dsSheetHeadBlock` pads `s4` top and `s6`
    /// bottom, which the old height had no term for. Hoisted out
    /// of the call (prd §560) so the detent set below can name the same number
    /// rather than restating the arithmetic — two copies of a height is how
    /// the resting detent and the tray stop agreeing.
    private var trayHeight: CGFloat {
        700 + (showsSplit ? 52 : 0) + (sends == nil ? 0 : 76)
    }

    var body: some View {
        DSTray(title: name, height: trayHeight, ink: true,
               // Scrollable and drag-past — see `HegotaMoveSheet.body`.
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    vaultDoor
                    sendStory
                    doing
                    explorer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The two places this address's money sits, as ONE quantity.
    ///
    /// **Drawn only when both halves are known.** The balance is one read and
    /// the vault total is a reconciled set; with either missing the bar would
    /// state a split we cannot support, and the two figures below it already
    /// say everything the bar would have.
    private var showsSplit: Bool {
        account.balanceWei != nil && account.reconciled
            && !(account.unspent ?? []).isEmpty
    }

    /// **A LINEAR stacked bar, and that is arithmetic rather than taste.** The
    /// room's accounts figure compares addresses whose totals span nine orders
    /// of magnitude and therefore needs `HegotaScale`; here the two segments are
    /// parts of ONE address's holdings, so they genuinely add and a plain
    /// proportional split is exactly true. This is `HegotaScale.linear`'s case,
    /// which is why the §504 nesting rule does not apply.
    @ViewBuilder private var splitBar: some View {
        if showsSplit, let balance = account.balanceWei,
           let coins = account.coinsWei {
            let total = balance + coins
            let vaultShare = total > 0
                ? NSDecimalNumber(decimal: coins / total).doubleValue : 0
            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule().fill(DS.tint.opacity(0.8))
                        .frame(width: max(0, geo.size.width * CGFloat(1 - vaultShare)))
                    // **A FLOOR.** A real address holds ~1% of its money in the
                    // vault, and at 1% of 354pt the segment is three points —
                    // present, and the reason the figures are LABELLED below
                    // rather than read off the bar.
                    Capsule().fill(HegotaModeStyle.hue(.utxo))
                        .frame(width: max(4, geo.size.width * CGFloat(vaultShare)))
                }
            }
            .frame(height: 12)
            .chartWipe(reduceMotion: reduceMotion)
            // Its own top air, rather than a gap in the head's stack: the head
            // is spaced 0 and pads each element, so an `if`-guarded child must
            // carry its own or a missing bar leaves a hole.
            .padding(.top, DS.Space.s3)
        }
    }

    /// What the chain says this address has SENT — the §504 facts, per account.
    ///
    /// The room's Nonces figure draws these across every shown account at once;
    /// this is the one place they are scoped to the address you opened. Nil
    /// unless the ordinary nonce was actually read, because the derived count
    /// undercounts by construction (a transaction that moved no ETH emits no
    /// transfer log) and a figure captioned "sends" that quietly means "sends
    /// we could see" is the wrong number stated confidently.
    private var sends: HegotaNonceTotals? {
        guard account.nonceCount != nil else { return nil }
        return HegotaNonceTotals.of(account.moves, lanes: account.lanes,
                                    nonceCount: account.nonceCount,
                                    valuelessSends: account.valuelessSends)
    }

    @ViewBuilder private var sendStory: some View {
        if let sends {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                sendStat(String(sends.ordinarySends),
                         String(localized: "Sends, key 0"), tint: DS.textPrimary)
                // The one fact no other reading in this room can reach: sends
                // the chain counted that no transfer log can show.
                if let quiet = sends.valuelessSends {
                    sendStat(String(quiet), String(localized: "Moved no value"),
                             tint: DS.textSecondary)
                }
                if sends.keyedSends > 0 {
                    sendStat(String(sends.keyedSends),
                             String(localized: "On named keys"), tint: DS.tint)
                }
            }
        }
    }

    @ViewBuilder private func sendStat(_ value: String, _ caption: String,
                                       tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).dsText(.stat24).foregroundStyle(tint).monospacedDigit()
            Text(caption)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.surfaceWell)
        }
    }

    private var name: String {
        HegotaWatch.shared.name(for: account.address)
            ?? WalletStore.shortAddress(account.address)
    }

    /// **THE HEAD IS AN ARRANGEMENT** — the move sheet's head (prd §495, with
    /// no paper under it since §583), and
    /// `dsSheetHeadBlock` rather than `DSSheetHead` for §498's own stated reason:
    /// this head is partly a CONTROL. The address is a copy button, so the
    /// title cannot be handed over as a `String`.
    ///
    /// The address stands in the head's secondary slot rather than beside the
    /// face, and the balance takes the figure slot — one object saying who this
    /// is and what they hold, instead of two blocks of text that happened to be
    /// stacked.
    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                WalletFace(address: account.address, size: DS.Face.shelf, circular: true)
                Spacer(minLength: 0)
                // Waiting on the CHAIN, not on you — the read simply has not
                // landed, which is why the stamp is `waiting` rather than an
                // alarm. The sentence below says what it means.
                if !account.reached {
                    DSStamp(word: String(localized: "Unread"), weight: .waiting)
                }
            }
            addressLine.padding(.top, DS.Space.s3)
            if !account.reached {
                Text(String(localized: "Couldn't be read — nothing below is current."))
                    .dsText(.callout15).foregroundStyle(DS.attention)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            // **IT PRODUCES THE CHAIN (§509).** Free, off headers the sweep
            // already reads, and it explains the room's most baffling number:
            // the sequencer holds nearly the devnet's whole supply, so an
            // account with 999,999,898 ETH beside one with 1.13 is not an error
            // in the figure, it is what a sequencer looks like. Stated only
            // when every header sampled agreed.
            if account.producesBlocks {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "cube").dsGlyph(13).foregroundStyle(DS.tint)
                    Text(String(localized: "Produces this chain's blocks"))
                        .dsText(.callout15).foregroundStyle(DS.tint)
                }
                .padding(.top, 2)
            }
            Text(account.balanceWei.map { HegotaFormat.crown($0) }
                 ?? String(localized: "Unread"))
                // `price40` — see the move sheet's `amount`, and §551, which
                // brought every room crown to this rung.
                .dsText(.price40).foregroundStyle(DS.textPrimary)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .padding(.top, DS.Space.s4)
            Text(String(localized: "in the account"))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
            splitBar
        }
        .dsSheetHeadBlock()
    }

    /// The WHOLE address, not the short form: this is the one screen where
    /// somebody is checking they watched the right thing — and therefore the
    /// one screen where they need to be able to take it away with them.
    @ViewBuilder private var addressLine: some View {
        Button {
            DSPasteboard.copySensitive(account.address)
            DSHaptic.selection()
            copied = true
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(account.address)
                    .dsText(.mono13).foregroundStyle(DS.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .dsGlyph(12)
                    .foregroundStyle(copied ? DS.confirm : DS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// **THE OTHER HALF OF THE MONEY, and a door to it.** Coins live in the
    /// vault contract, so they are NOT in this address's balance — the two
    /// figures are different money in different places, and adding them
    /// silently would be the room inventing a total nobody publishes.
    ///
    /// It sits OFF the paper on purpose: the head answers what this address
    /// holds, and this is somewhere to go.
    @ViewBuilder private var vaultDoor: some View {
        if let held = account.unspent, !held.isEmpty, account.reconciled {
            Button {
                DSHaptic.selection()
                onScope?(.coins)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(HegotaFormat.eth(HegotaCoins.total(held)))
                            .dsText(.heading22).foregroundStyle(DS.tint)
                            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        Text(held.count == 1
                             ? String(localized: "held as 1 UTXO in the vault")
                             : String(localized: "held as \(String(held.count)) UTXOs in the vault"))
                            .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    }
                    WalletRowChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// **Every fact is a door.** Each of these names a scope the room can
    /// already open, filtered to this account — so the sheet hands you the list
    /// instead of telling you a number and closing.
    @ViewBuilder private var doing: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            door(account.moves.count == 1 ? String(localized: "1 movement")
                                          : String(localized: "\(String(account.moves.count)) movements"),
                 to: .activity, enabled: !account.moves.isEmpty)
            if !account.lanes.isEmpty {
                door(account.lanes.count == 1
                     ? String(localized: "1 nonce key of its own")
                     : String(localized: "\(String(account.lanes.count)) nonce keys, each sending independently"),
                     to: .nonces, enabled: true)
            }
            if !account.sponsored.isEmpty {
                door(String(localized: "\(String(account.sponsored.count)) paid for by somebody else"),
                     to: .sponsors, enabled: true)
            }
        }
    }

    @ViewBuilder private func door(_ text: String, to section: HegotaSection,
                                   enabled: Bool) -> some View {
        if enabled {
            Button {
                DSHaptic.selection()
                onScope?(section)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(text).dsText(.callout15).foregroundStyle(DS.textSecondary)
                    WalletRowChevron()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(text).dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    /// The chain's own explorer, opened in the person's browser. Nothing here
    /// reaches it — it is a permalink, which is why the host sits on the reach
    /// audit's non-reach list rather than in the registry.
    @ViewBuilder private var explorer: some View {
        if let url = URL(string: "\(HegotaIdentity.explorer)/address/\(account.address)") {
            Link(destination: url) {
                Text(String(localized: "Open in the explorer"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
        }
    }
}

// MARK: - One UTXO

/// A single unspent output, and the spend that made it.
///
/// **Why a coin is worth opening at all.** Everything the row shows — amount,
/// change or received, age — is already on the row, and a sheet that repeats
/// its row is the dead control §83 bans. What is NOT on the row is the spend
/// this coin came out of: its siblings. Coins sharing a `createdBy` are the
/// outputs of one transaction, and seeing them together is the UTXO model
/// itself — money went in, and came back out as several pieces, one of them
/// change to you.
///
/// **The inputs are deliberately absent.** A spent coin is known by a BIT in
/// the vault's storage, not by an event, so nothing on the wire says which
/// coins a spend consumed. The fee — inputs minus outputs — is therefore not
/// derivable here, and the sheet says what it knows rather than estimating.
struct HegotaCoinSheet: View {
    let coin: HegotaCoin
    /// Every coin these accounts have owned, SPENT ONES INCLUDED.
    ///
    /// It used to be the unspent set alone, which made a spend's anatomy
    /// silently incomplete: a transaction that made four pieces showed the two
    /// still lying around and said "one spend made 2 of these" — a wrong number
    /// stated confidently, and the reading this sheet exists for.
    let all: [HegotaCoin]
    /// Which of them are still unspent. Passed rather than derived, because the
    /// spent bit lives in the vault's storage and only the sweep can read it.
    var unspent: Set<UInt64> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dealt = false

    private var siblings: [HegotaCoin] {
        guard let tx = coin.createdBy else { return [] }
        return all.filter { $0.createdBy == tx }.sorted { $0.index < $1.index }
    }

    /// Everything this person still holds in the vault — what the share bar
    /// measures against. Derived from the two things already passed in, so it
    /// costs no read: `all` is scoped to the shown accounts and `unspent` is
    /// the set the sweep proved.
    private var held: [HegotaCoin] { all.filter { unspent.contains($0.index) } }

    var body: some View {
        // **THE TITLE IS THE COIN'S IDENTITY, not its origin (2026-08-27).**
        // It was "Change" / "A UTXO you were sent" — the first reads as a VERB
        // before it reads as money coming back from a spend, which on a sheet
        // header is a control that isn't one (§83), and the second is a
        // sentence where a name belongs. The vault's counter IS the coin (this
        // file's own ruling, one property up), the room's chip already teaches
        // the literal term (§500), and the origin is not lost: it is the line
        // under the amount and the sibling row's own caption.
        DSTray(title: String(localized: "UTXO #\(String(coin.index))"),
               height: trayHeight, ink: true,
               // Scrollable and drag-past — see `HegotaMoveSheet.body`. This is
               // the sharpest of the four: the height is `min(820, …)`, so a
               // coin with enough siblings does not merely risk overrunning
               // its guess, it is GUARANTEED to — the cap is a promise to clip.
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    share
                    spend
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
                .onAppear { dealt = true }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// +60 for the head block's own chrome (`dsSheetHeadBlock` pads s4 top and
    /// s6 bottom); a deficit clips. Hoisted out of the call (prd
    /// §560) so the detent set names the same number instead of restating it.
    private var trayHeight: CGFloat {
        min(820, 460 + CGFloat(siblings.count) * 46 + (showsShare ? 64 : 0))
    }

    /// **THE HEAD IS AN OBJECT** — the move sheet's paper (prd §495), on the
    /// room's own hue. A piece IS the object this chain publishes, so it gets
    /// the vault's mark rather than a face: an identicon here would be a
    /// portrait of a counter (`AssetMark`'s refusal).
    ///
    /// **The dateline moved to the top**, where a receipt's dateline goes, and
    /// up from `label12` — it is the coin's AGE, which is a fact rather than a
    /// caption on the figure above it. The origin clause stays under the
    /// amount: the title already carries the identity.
    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(HegotaModeStyle.room.opacity(0.16))
                    Image(systemName: "tray.full")
                        .dsGlyph(24).foregroundStyle(HegotaModeStyle.room)
                }
                .frame(width: DS.Face.shelf, height: DS.Face.shelf)
                Spacer(minLength: 0)
                if let standing {
                    DSStamp(word: standing.word, weight: standing.weight)
                }
            }
            Text(HegotaFormat.stamp(coin.timestamp, block: coin.block,
                                    estimated: coin.estimatedAt))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s3)
            Text(HegotaFormat.eth(coin.wei))
                // `price40` — see the move sheet's `amount`.
                .dsText(.price40).foregroundStyle(DS.textPrimary)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .padding(.top, 2)
            Text(coin.isChange
                 ? String(localized: "change from your own spend")
                 : String(localized: "sent to you by \(WalletStore.shortAddress(coin.source))"))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
        .dsSheetHeadBlock()
    }

    /// **Spent or not — stated only when the sweep has proved a set.**
    ///
    /// `unspent` defaults to empty, and an empty set means "nobody passed one"
    /// exactly as loudly as it means "nothing here is unspent". Stamping a coin
    /// `Spent` off that would be a state invented from an absence (§83), so the
    /// stamp is withheld until there is a proven set to test against —
    /// `showsShare`'s own caution, one property down.
    ///
    /// Both wear `quiet`: a spent piece is not a warning and an unspent one is
    /// not good news, they are the two ordinary states of a UTXO.
    private var standing: (word: String, weight: DSStamp.Weight)? {
        guard !unspent.isEmpty else { return nil }
        return unspent.contains(coin.index)
            ? (String(localized: "Unspent"), .quiet)
            : (String(localized: "Spent"), .quiet)
    }

    /// **This piece among the pieces — the one thing the room's treemap cannot
    /// say.** `UnitTreemap` sizes its cells by RANK rather than area (its own
    /// ruling: true squarified cells arrive as slivers too thin to label), and
    /// on this chain a set spans orders of magnitude — so six roughly equal
    /// cells routinely draw over a set whose first piece is nearly all of it.
    ///
    /// Drawn only when there is a comparison to make: one coin is not a share,
    /// and a coin outside the proven set has no denominator it belongs to.
    private var showsShare: Bool {
        held.count > 1 && held.contains { $0.index == coin.index }
    }

    @ViewBuilder private var share: some View {
        if showsShare {
            let total = HegotaCoins.total(held)
            let ranked = held.sorted { $0.wei > $1.wei }
            let pct = total > 0
                ? NSDecimalNumber(decimal: coin.wei / total).doubleValue : 0
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(ranked, id: \.index) { piece in
                            let isThis = piece.index == coin.index
                            Capsule()
                                .fill(isThis ? DS.tint : DS.tint.opacity(0.22))
                                // **A FLOOR, for `HegotaScale`'s reason one
                                // figure over**: a piece drawn at no width is
                                // indistinguishable from a piece missing from
                                // the set, and dust beside a whole coin is the
                                // ordinary case here rather than the corner.
                                .frame(width: max(3, geo.size.width
                                                  * CGFloat(fraction(piece, of: total))))
                        }
                    }
                }
                .frame(height: 12)
                Text(String(localized: "\(Int((pct * 100).rounded()))% of the \(String(held.count)) pieces you hold"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func fraction(_ piece: HegotaCoin, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: piece.wei / total).doubleValue
    }

    /// The spend's other outputs — the reading this sheet exists for.
    @ViewBuilder private var spend: some View {
        if siblings.count > 1 {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // **What the spend PRODUCED, never what it was worth.** The
                // outputs sum exactly and are on the wire; the spend's own
                // total is outputs plus a fee whose inputs are not published,
                // so "the spend was X" would be a number we cannot support —
                // which the note at the foot of this list already says.
                Text(String(localized: "One spend made these \(String(siblings.count)) — \(HegotaFormat.eth(HegotaCoins.total(siblings))) in all"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // **THE SPEND DEALS ITS PIECES** (prd §503, moment 02). The
                // outputs arrive one after another rather than being present,
                // which is the UTXO model as a gesture: money went in, and came
                // back out as several countable objects. Staggered off the
                // index so they always deal in the vault's own order.
                ForEach(Array(siblings.enumerated()), id: \.element.index) { position, sibling in
                    siblingRow(sibling)
                        .opacity(dealt || reduceMotion ? 1 : 0)
                        .offset(y: dealt || reduceMotion ? 0 : -10)
                        .animation(reduceMotion ? nil
                                   : .spring(response: 0.34, dampingFraction: 0.78)
                                        .delay(Double(position) * 0.07),
                                   value: dealt)
                }
                // STATED, not estimated: the inputs are not on the wire, so the
                // fee cannot be derived from what we can see.
                // The refusal, kept — and cut to its two facts. What it
                // consumed is unknowable, and the reason is that a spent UTXO
                // is a bit rather than an event; everything else the old
                // sentence carried was scaffolding around those.
                Text(String(localized: "What it consumed isn't published — a spent UTXO is a bit in storage, not an event."))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if coin.createdBy != nil {
            Text(String(localized: "The only UTXO its spend made."))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder private func siblingRow(_ sibling: HegotaCoin) -> some View {
        let isThis = sibling.index == coin.index
        let spent = !unspent.contains(sibling.index)
        HStack(spacing: DS.Space.s3) {
            Circle()
                .fill(isThis ? DS.tint : DS.tint.opacity(spent ? 0.18 : 0.3))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(HegotaFormat.eth(sibling.wei))
                    .dsText(.callout15)
                    .foregroundStyle(isThis ? DS.textPrimary
                                     : spent ? DS.textTertiary : DS.textSecondary)
                    .monospacedDigit()
                    // A spent sibling is struck through rather than dimmed
                    // alone: dimming reads as "less important", and this one is
                    // GONE, which is a different fact.
                    .strikethrough(spent && !isThis, color: DS.textTertiary)
                Text(sibling.isChange ? String(localized: "change, back to you")
                                      : String(localized: "out to \(WalletStore.shortAddress(sibling.owner))"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
            if isThis {
                Text(String(localized: "this one"))
                    .dsText(.label12).foregroundStyle(DS.tint)
            } else if spent {
                Text(String(localized: "already spent"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        }
    }
}
