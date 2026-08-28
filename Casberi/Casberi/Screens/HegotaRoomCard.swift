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

    /// How many address bars the accounts figure draws. Five is the watch cap,
    /// so in practice it never truncates — a bound on the drawing, not a limit
    /// on what is watched.
    /// How many address bars the accounts figure draws.
    ///
    /// **Three, and it is a HEIGHT budget, not a taste.** The slot gives a
    /// figure 180pt under its reserved headline row and clips the rest; an
    /// account bar is a name row, the bar and its coin note — about 50pt — so
    /// five bars is 250pt of content in a 180pt box, and what falls off the
    /// bottom does so silently. The remainder is NAMED rather than dropped
    /// (the no-silent-caps rule); five is still the watch cap.
    private static let laneCap = 3

    /// The pressed lane, and the task that lets it go. `@State`, so it dies
    /// with the room the way `x402Lane` does — a press is a question about
    /// right now, not a scope worth keeping.
    @State private var pickedLane: HegotaFlow.Lane?
    @State private var laneRevert: Task<Void, Never>?
    /// How many transactions the frame anatomy draws. Six 18pt rows plus their
    /// gaps is what the 210pt slot holds under its reserved headline row; a
    /// seventh would be clipped by `DSRoomSlot`, which is worse than absent.
    private static let frameRows = 6

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
        case .accounts:
            let total = accounts.filter(\.reached).compactMap(\.balanceWei).reduce(Decimal(0), +)
            return HegotaFormat.crown(total)
        case .coins:
            return coins.isEmpty ? nil : HegotaFormat.crown(HegotaCoins.total(coins))
        case .nonces:
            return lanes.count == 1 ? String(localized: "1 nonce key")
                                    : String(localized: "\(String(lanes.count)) nonce keys")
        }
    }

    @ViewBuilder private var slotFigure: some View {
        switch section {
        case .home, .sponsors: crownFigure
        case .activity:        activityFigure
        case .accounts:        accountsFigure
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
                               height: 120, pulses: false,
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
    @ViewBuilder private var activityFigure: some View {
        if let band = HegotaFlow.band(moves) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // **PRESS A LANE TO SEE ITS STEPS** (moment 05) — §386d's
                // press-reveals-a-fact, answered IN the caption's own slot so
                // the eye is already there and the card never changes height.
                figureCaption(pickedLane.map(laneSteps) ?? bandCaption(band))
                // **ONE scale decision across BOTH sides**, for the reason
                // `HegotaScale` exists: this address's biggest inflow is thirty
                // times everything else it has ever done put together, so drawn
                // proportionally every other lane is a four-point sliver — the
                // exact failure the accounts bar hit, in a second figure.
                let amounts = (band.inLanes + band.outLanes).map(\.wei)
                let scale = HegotaScale.of(amounts)
                HStack(alignment: .top, spacing: 0) {
                    laneStack(band.inLanes, band: band, incoming: true,
                              amounts: amounts, scale: scale)
                    // The spine: the address itself, which both sides cross.
                    // Top-aligned with the lane stacks: centred, it hung below
                    // the rows it is supposed to join and read as a stray mark.
                    Capsule().fill(DS.tint.opacity(0.55))
                        .frame(width: 5, height: spineHeight(band))
                        .padding(.horizontal, DS.Space.s2)
                        .padding(.top, 4)
                    laneStack(band.outLanes, band: band, incoming: false,
                              amounts: amounts, scale: scale)
                }
                // **No reserved height.** Forcing 112pt here left ~60pt of air
                // between the band and the note under it, which pushed that
                // note onto the slot's bottom edge where it collided with the
                // face rail — the "overflow" was a fixed frame the content
                // never filled, not content that was too big.
                if scale == .logarithmic {
                    figureCaption(String(localized: "Bar lengths are a log scale — the figures are exact"))
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

    /// In and out as one sentence, so the band can never be read against the
    /// wrong side. Net is deliberately absent: it is not a balance, the crown
    /// above already carries that, and two figures that look like totals on one
    /// card is how a reader ends up believing the wrong one.
    private func bandCaption(_ band: HegotaFlow.Band) -> String {
        String(localized: "In \(HegotaFormat.eth(band.inWei)) · out \(HegotaFormat.eth(band.outWei))")
    }

    /// A figure's caption line.
    ///
    /// **The trailing inset is the settings gear.** `DSRoomSlot` gives a figure
    /// the full width, and the chassis floats its gear over the slot's
    /// top-right — so a caption long enough to reach it renders UNDER it, which
    /// is what put "bar lengths are a log scale" behind a cog. Every scope's
    /// caption goes through here so the clearance is stated once rather than
    /// remembered four times.
    @ViewBuilder private func figureCaption(_ text: String) -> some View {
        Text(text)
            .dsText(.label12).foregroundStyle(DS.textTertiary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The spine's height is the TALLER side's rows, so it spans exactly what
    /// crosses it rather than a constant that is too long for a one-lane side
    /// and too short for a four-lane one.
    private func spineHeight(_ band: HegotaFlow.Band) -> CGFloat {
        let rows = max(1, max(band.inLanes.count, band.outLanes.count))
        return min(CGFloat(112), CGFloat(rows) * 24)
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
        .frame(height: 20)
        .contentShape(Rectangle())
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
    private func laneSteps(_ lane: HegotaFlow.Lane) -> String {
        let who = lane.isOther
            ? String(localized: "these")
            : HegotaName.of(lane.address, watched: accounts.map(\.address))
        guard !lane.modes.isEmpty else {
            return String(localized: "\(who) — an ordinary transfer, no steps")
        }
        return String(localized: "\(who) — \(lane.modes.map(\.label).joined(separator: ", "))")
    }

    /// The bar itself. A floor, because a bar of no width is indistinguishable
    /// from a lane that is not there — and the small lanes are the ones a
    /// person is least able to account for.
    @ViewBuilder private func laneBar(_ lane: HegotaFlow.Lane,
                                      share: Double, incoming: Bool) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(laneTint(lane).opacity(0.85))
                .frame(width: max(4, geo.size.width * CGFloat(share)), height: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: incoming ? .trailing : .leading)
        }
        .frame(width: 52)
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
                .foregroundStyle(DS.tint).frame(width: 15, height: 15)
        } else {
            WalletFace(address: lane.address, size: 15, circular: true)
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





    /// **ACCOUNTS — where each address's money actually sits.**
    ///
    /// iPhone's storage bar, and the same question: one bar per address, split
    /// by where the money is. **It counts no moves**, deliberately — how much
    /// an address DOES is the Activity scope's subject, and a figure that
    /// borrows it is two scopes saying one thing.
    ///
    /// What is left is genuinely an account fact and one this chain makes
    /// interesting: money here sits in two different places at once. The
    /// balance is in the account; the UTXOs are in the vault CONTRACT, so they
    /// are not in that balance at all. The bar is the only place the two are
    /// drawn as one quantity, which is what a person actually holds.
    ///
    /// **Bars are shares of the largest address, not of a total.** A total
    /// across a devnet's prefunded accounts is a number nobody has, and
    /// dividing by it draws every real account as nothing.
    @ViewBuilder private var accountsFigure: some View {
        let lanes = Array(accounts.prefix(Self.laneCap))
        let totals = lanes.map { held($0) }
        let scale = HegotaScale.of(totals)
        let peak = totals.max() ?? 0
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            figureCaption(scale == .logarithmic
                          ? String(localized: "Where the money sits · log scale, figures exact")
                          : String(localized: "Where each address's money sits"))
            VStack(spacing: DS.Space.s3) {
                ForEach(lanes) { account in
                    accountBar(account, peak: peak, totals: totals, scale: scale)
                }
            }
            if accounts.count > lanes.count {
                let rest = accounts.count - lanes.count
                Text(rest == 1 ? String(localized: "1 more address, in the list below")
                               : String(localized: "\(String(rest)) more addresses, in the list below"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
        }
        // Centred in the slot for `activityFigure`'s reason: the surplus is
        // split rather than pooled under the bars.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Everything an address holds — its balance PLUS its unspent coins.
    ///
    /// Coins are only added once the set has RECONCILED against the vault's own
    /// balance; an unreconciled set is a total nobody should read, so it is
    /// left out rather than guessed at.
    private func held(_ account: HegotaAccount) -> Decimal {
        (account.balanceWei ?? 0) + (account.coinsWei ?? 0)
    }

    /// One address's bar, split into the account and the vault.
    @ViewBuilder private func accountBar(_ account: HegotaAccount,
                                         peak: Decimal,
                                         totals: [Decimal],
                                         scale: HegotaScale) -> some View {
        let total = held(account)
        let share = HegotaScale.share(total, in: totals, scale: scale)
        let coins = account.coinsWei ?? 0
        let coinShare: Double = total > 0
            ? NSDecimalNumber(decimal: coins / total).doubleValue : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Space.s2) {
                WalletFace(address: account.address, size: 18, circular: true)
                Text(HegotaWatch.shared.name(for: account.address)
                     ?? WalletStore.shortAddress(account.address))
                    .dsText(.label12).foregroundStyle(DS.textSecondary).lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                Text(account.reached ? HegotaFormat.crown(total)
                                     : String(localized: "Unread"))
                    .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().lineLimit(1)
            }
            GeometryReader { geo in
                let width = geo.size.width * CGFloat(share)
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule().fill(DS.tint.opacity(0.8)).frame(width: max(0, width))
                    // The vault's slice, drawn INSIDE the bar in the room's coin
                    // blue — it is part of the same money, not a second holding,
                    // and a bar of its own would read as a second account.
                    if coinShare > 0 {
                        Capsule()
                            .fill(Color(red: 0.30, green: 0.78, blue: 0.92))
                            .frame(width: max(3, width * CGFloat(coinShare)))
                    }
                }
            }
            .frame(height: 12)
            if let unspent = account.unspent, !unspent.isEmpty, account.reconciled {
                // Named, because at a real split (1.1288 in the account against
                // 0.0131 in coins) the vault's slice is about one percent of the
                // bar — visible, but far too small to read a figure off.
                Text(String(localized: "\(HegotaFormat.eth(coins)) of it in \(String(unspent.count)) UTXOs"))
                    .dsText(.label12)
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.92))
                    .lineLimit(1)
            }
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
            Text(coinsLine)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            if !drawn.isEmpty {
                // **SIZED TO WHAT IS LEFT OF THE SLOT.** `DSRoomSlot` is a fixed
                // 210pt and reserves 30 for the headline; with the caption and
                // the stack's gaps above it, 116 is what remains.
                UnitTreemap(count: drawn.count, height: 116, cell: { i in
                    tile(drawn[i])
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
    private var tiledCoins: [CoinTile] {
        let cap = 6
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
    @ViewBuilder private func tile(_ tile: CoinTile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch tile {
            case .coin(let coin):
                Text(HegotaFormat.eth(coin.wei))
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(coin.isChange ? String(localized: "change")
                                   : String(localized: "received"))
                    .dsText(.label12).foregroundStyle(DS.textSecondary).lineLimit(1)
            case .rest(let count, let wei):
                Text(HegotaFormat.eth(wei))
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(String(localized: "\(String(count)) more"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                DS.surfaceWell
                fill(tile)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
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

    /// One UTXO's tile.
    ///
    /// **The cell paints its own ground** — `UnitTreemap` lays out the frames
    /// and nothing else, so a cell that is only text has no shape to see. The
    /// well rather than the sheet, for the receipts map's own reason: a cell
    /// washed in the surrounding tone vanishes at low share.
    ///
    /// The fill says where the UTXO came from, which is the one thing worth
    /// encoding in hue here: on a real address most of the set is change from
    /// your own spends, and the pieces somebody actually sent you are the
    /// minority worth picking out.
    private func utxoCell(_ coin: HegotaCoin) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HegotaFormat.eth(coin.wei))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(coin.isChange ? String(localized: "change") : String(localized: "received"))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                DS.surfaceWell
                (coin.isChange ? DS.tint.opacity(0.16) : DS.tint.opacity(0.42))
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
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
        let totals = HegotaNonceTotals.of(moves, lanes: lanes)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            figureCaption(String(localized: "Each counter sends without waiting on the others"))
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
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
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
    static func hue(_ mode: HegotaFrame.Mode) -> Color {
        switch mode {
        case .verify:    return Color(red: 0.55, green: 0.47, blue: 0.93)   // the signature check
        case .sender:    return DS.confirm                                   // value actually moving
        case .general:   return DS.tint                                      // a call
        case .assertion: return DS.attention                                 // a condition
        case .utxo:      return Color(red: 0.30, green: 0.78, blue: 0.92)   // the vault
        case .unknown:   return DS.textTertiary
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
            case .home:     movesList(Array(moves.prefix(4)))
            case .activity: movesList(moves)
            case .accounts: accountsList
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

    // MARK: Accounts

    @ViewBuilder private var accountsList: some View {
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
            Text(String(localized: "These UTXOs account for exactly what the vault holds."))
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
                    Text(lane.sends == 1 ? String(localized: "1 send")
                                         : String(localized: "\(String(lane.sends)) sends"))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
                Text(HegotaFormat.signed(move.wei, incoming: move.incoming))
                    .dsText(.subhead13)
                    .foregroundStyle(move.incoming ? DS.confirm : DS.textSecondary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                // The frame anatomy as texture. A legacy transaction draws
                // nothing here, so the two eras are told apart at a glance
                // rather than by reading a joined string of mode names.
                if let frames = move.frames, !frames.isEmpty {
                    HegotaFrameStrip(frames: frames).frame(width: 54)
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
        if madeCoins > 0 {
            parts.append(madeCoins == 1 ? String(localized: "became 1 UTXO")
                                        : String(localized: "became \(String(madeCoins)) UTXOs"))
        } else if let frames = move.frames, !frames.isEmpty {
            parts.append(frames.count == 1 ? String(localized: "1 frame")
                                           : String(localized: "\(String(frames.count)) frames"))
        }
        if let when = HegotaFormat.time(move.timestamp) { parts.append(when) }
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
    var onOpenFrame: ((Int) -> Void)? = nil

    var body: some View {
        DSTray(title: title, height: trayHeight) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                amount
                frames
                cost
                if !move.nonceKeys.isEmpty {
                    Text(move.nonceKeys.count == 1
                         ? String(localized: "Sent on nonce key \(move.nonceKeys[0]) — a queue of its own.")
                         : String(localized: "Sent on \(String(move.nonceKeys.count)) nonce keys at once."))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                stamp
                explorer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
        }
    }

    /// Sized to the frames rather than fixed: a one-frame transfer and a
    /// four-frame sponsored spend are very different documents.
    private var trayHeight: CGFloat {
        min(760, 380 + CGFloat(move.frames?.count ?? 0) * 54)
    }

    private var party: HegotaParty { HegotaParty.of(move.counterparty, watched: watched) }

    private var title: String {
        if party == .vault {
            return move.incoming ? String(localized: "Out of the UTXO vault")
                                 : String(localized: "Into the UTXO vault")
        }
        return move.incoming ? String(localized: "Money in") : String(localized: "Money out")
    }

    @ViewBuilder private var amount: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HegotaFormat.signed(move.wei, incoming: move.incoming))
                .dsText(.price48)
                .foregroundStyle(move.incoming ? DS.confirm : DS.textPrimary)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(move.incoming
                 ? String(localized: "in from \(HegotaName.of(move.counterparty, watched: watched))")
                 : String(localized: "out to \(HegotaName.of(move.counterparty, watched: watched))"))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            // WHOSE. The room can be scoped to All, and then no other line on
            // this sheet says which of your addresses this was.
            if !owner.isEmpty {
                Text(String(localized: "on your \(HegotaWatch.shared.name(for: owner) ?? WalletStore.shortAddress(owner))"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    /// What it cost, and who paid.
    ///
    /// **Sponsorship stops being a sentence and becomes an amount.** "Somebody
    /// else paid the gas" is a claim; "they paid 0.00006 ETH and you paid
    /// nothing" is the fact underneath it, and it costs no read — both halves
    /// are on the receipt the sweep already fetched.
    @ViewBuilder private var cost: some View {
        if move.isSponsored, let payer = move.payer {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Cost you nothing"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
                Text(move.feeWei.map {
                    String(localized: "\(HegotaName.of(payer, watched: watched)) paid \(HegotaFormat.eth($0)) in gas")
                } ?? String(localized: "\(HegotaName.of(payer, watched: watched)) paid the gas"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        } else if let fee = move.feeWei {
            Text(String(localized: "Cost \(HegotaFormat.eth(fee)) in gas"))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    @ViewBuilder private var stamp: some View {
        // The block is the chain's own identity for this moment; the date is
        // the only form of it anybody can read. Both, because the block is what
        // you would quote to somebody else.
        Text(HegotaFormat.stamp(move.timestamp, block: move.block))
            .dsText(.label12).foregroundStyle(DS.textTertiary)
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

    private var frame: HegotaFrame? {
        guard let frames = move.frames, frames.indices.contains(index) else { return nil }
        return frames[index]
    }
    private var total: Int { move.frames?.count ?? 0 }

    var body: some View {
        DSTray(title: frame?.mode.label ?? String(localized: "Step"), height: 560) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if let frame {
                    headline(frame)
                    meaning(frame)
                    position
                    facts(frame)
                } else {
                    Text(String(localized: "This step is no longer available."))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
        }
    }

    @ViewBuilder private func headline(_ frame: HegotaFrame) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // The VALUE leads when there is one, because that is what a person
            // came to find out; the mode leads when there isn't, because then
            // the step's whole content is what it did.
            if frame.wei > 0 {
                Text(HegotaFormat.eth(frame.wei))
                    .dsText(.price48).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(String(localized: "moved by this step"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            } else {
                Text(frame.mode.label)
                    .dsText(.heading28).foregroundStyle(HegotaModeStyle.hue(frame.mode))
                Text(String(localized: "moved no value"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            if frame.succeeded == false {
                Text(String(localized: "This step failed."))
                    .dsText(.callout15).foregroundStyle(DS.destructive)
            } else if frame.succeeded == nil {
                Text(String(localized: "Its receipt couldn't be paired — we can't say whether it ran."))
                    .dsText(.subhead13).foregroundStyle(DS.attention)
            }
        }
    }

    /// The mode in words. **The reason this sheet exists**: `Verify` is a noun
    /// somebody has to already know, and this is the reading.
    @ViewBuilder private func meaning(_ frame: HegotaFrame) -> some View {
        Text(HegotaModeStyle.meaning(frame.mode))
            .dsText(.callout15).foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder private func facts(_ frame: HegotaFrame) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let target = frame.target {
                fact(String(localized: "Ran against \(HegotaName.of(target, watched: watched))"))
            }
            // BOTH gas dimensions, and this chain is the reason the distinction
            // is worth a line: it prices execution and state separately, so a
            // step that only moves value really does burn zero execution gas.
            if let gas = frame.gasUsed {
                fact(String(localized: "\(String(gas)) execution gas"))
            }
            if let state = frame.stateGasUsed {
                fact(String(localized: "\(String(state)) state gas"))
            }
            fact(HegotaFormat.stamp(move.timestamp, block: move.block))
        }
    }

    private func fact(_ text: String) -> some View {
        Text(text).dsText(.callout15).foregroundStyle(DS.textSecondary)
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

    /// A sheet's dateline. The block is the chain's own identity for the
    /// moment — what you would quote to somebody else — and the date is the
    /// only form of it a person can read, so both.
    static func stamp(_ date: Date?, block: UInt64) -> String {
        guard let date else { return String(localized: "Block \(String(block))") }
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

    @State private var copied = false

    var body: some View {
        DSTray(title: name, height: 640) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                identity
                money
                doing
                explorer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
        }
    }

    private var name: String {
        HegotaWatch.shared.name(for: account.address)
            ?? WalletStore.shortAddress(account.address)
    }

    @ViewBuilder private var identity: some View {
        HStack(spacing: DS.Space.s3) {
            WalletFace(address: account.address, size: DS.Face.shelf, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                // The WHOLE address, not the short form: this is the one screen
                // where somebody is checking they watched the right thing —
                // and therefore the one screen where they need to be able to
                // take it away with them.
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
                if !account.reached {
                    Text(String(localized: "Couldn't be read — nothing below is current."))
                        .dsText(.subhead13).foregroundStyle(DS.attention)
                }
            }
        }
    }

    /// **THE SPLIT, stated rather than implied.** Coins live in the vault
    /// contract, so they are NOT in this address's balance — the two figures
    /// are different money in different places, and adding them silently would
    /// be the room inventing a total nobody publishes.
    @ViewBuilder private var money: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(account.balanceWei.map { HegotaFormat.crown($0) }
                     ?? String(localized: "Unread"))
                    .dsText(.price48).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(String(localized: "in the account"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
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
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        }
                        WalletRowChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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

    var body: some View {
        DSTray(title: coin.isChange ? String(localized: "Change")
                                    : String(localized: "A UTXO you were sent"),
               height: min(720, 360 + CGFloat(siblings.count) * 46)) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                headline
                origin
                spend
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
            .onAppear { dealt = true }
        }
    }

    @ViewBuilder private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HegotaFormat.eth(coin.wei))
                .dsText(.price48).foregroundStyle(DS.textPrimary)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            // The vault's own counter is the coin's IDENTITY; the date beside
            // it is its age. #45 says which coin came first and nothing at all
            // about when, which is why both are here.
            Text(HegotaFormat.stamp(coin.timestamp, block: coin.block))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            Text(String(localized: "UTXO #\(String(coin.index))"))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    @ViewBuilder private var origin: some View {
        Text(coin.isChange
             ? String(localized: "This came back to you as change from your own spend.")
             : String(localized: "Sent to you by \(WalletStore.shortAddress(coin.source))."))
            .dsText(.callout15).foregroundStyle(DS.textSecondary)
    }

    /// The spend's other outputs — the reading this sheet exists for.
    @ViewBuilder private var spend: some View {
        if siblings.count > 1 {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(String(localized: "One spend made \(String(siblings.count)) of these"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
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
                Text(String(localized: "What the spend consumed isn't published — a spent UTXO is a bit in the vault's storage, not an event."))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
        } else if coin.createdBy != nil {
            Text(String(localized: "It was the only UTXO its spend created."))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
