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
    /// Home's account row is a DOOR (2026-09-02). It was the only identity on
    /// the screen and it opened nothing — and it is where the balance, the
    /// nonce and the curve all already meet, so it is the obvious place to ask
    /// what this address has been doing. Declared here rather than adding a
    /// second account row to the list below, which would be one fact drawn
    /// twice six points apart.
    var onOpenAccount: ((FramesAccount) -> Void)? = nil

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
                Button {
                    DSHaptic.selection()
                    onOpenAccount?(account)
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: account.address, size: DS.Face.list, circular: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FramesWatch.shared.name(for: account.address)
                                 ?? WalletStore.shortAddress(account.address))
                                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                            // The nonce IS the count — it is incremented per
                            // transaction the account signs — so this is a fact off
                            // the chain rather than a tally of what was read back.
                            Text(sendLine(nonce: account.nonce))
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                        WalletRowChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // **The name stays IN the label.** The first cut replaced the
                // button's whole label with "Open this account", which is the
                // one thing a sighted reader already knows from the chevron
                // and drops the one thing they get from the row — which
                // account it is. `children: .combine` keeps the address and
                // the send line and adds the verb.
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text(String(localized: "Opens this account")))
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
    /// **THE NEWEST TRANSACTION IS THE DRAWING'S IDENTITY** (2026-09-01).
    ///
    /// A chart entrance is a one-shot on appear, which is right for opening a
    /// room and wrong for the moment this room exists for: a transaction you
    /// just sent LANDS, and the chart it lands in redrew silently between two
    /// frames. Keyed on the newest hash, a new transaction is a new drawing
    /// and it draws itself — so the settle is watchable rather than inferred
    /// from a row that is suddenly there.
    ///
    /// It changes only when a transaction becomes the newest, so nothing else
    /// in the room can replay it: not a scope switch, not a balance read, not
    /// an older run rolling off the end.
    private var newestHash: String { moves.first?.hash ?? "" }

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
            // **FILLS THE SLOT** (user, 2026-09-02: *"why it so tiny and top
            // justified"*). It was pinned to 64pt inside a 210pt box whose
            // remaining height went to the `Spacer` below, so the room's
            // busiest reading drew in a third of the space it had been given
            // and every scope beside it looked fuller. `maxHeight: .infinity`
            // hands it what the slot actually reserved.
            FramesMovementBars(bars: bars)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(newestHash)
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
                    .id(newestHash)
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
        // **SOMEBODY ELSE JUST PAID FOR ONE.** The reading this chain has that
        // no other room in this app can make, and until now it only ever
        // arrived as a slightly different bar. A glance, not a badge: it
        // answers a thing that just happened and gets out of the way
        // (`ArrivalWash`'s ruling), and `arrived` empties on the next read so
        // it cannot become a mark the bar wears.
        let sponsoredArrival = moves.contains {
            $0.sponsored && FramesLiveState.shared.hasJustArrived($0.hash)
        }
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if theirs + mine > 0 {
                // Centred in what is left rather than pinned to the top, for
                // the Activity chart's reason: a 16pt bar hung under a
                // headline in a 210pt box reads as a drawing that failed to
                // load.
                Spacer(minLength: 0)
                FramesSponsorBar(mine: mine, theirs: theirs, glance: sponsoredArrival)
                Spacer(minLength: 0)
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
    /// **THE OWNING ADDRESS TRAVELS WITH THE MOVE** — Hegotá's signature, and
    /// for its reason: in an unscoped room nothing else can say which of the
    /// shown addresses a transaction belonged to, and a sheet that cannot
    /// answer "whose?" is a sheet about a stranger's money.
    let onOpenMove: (FramesMove, String) -> Void
    var onOpenPayer: ((FramesPayer) -> Void)? = nil

    @Environment(ShellChrome.self) private var chrome

    private var moves: [FramesMove] {
        pairs.map(\.move)
    }

    /// Every shown move with the address whose read produced it.
    ///
    /// The flat `moves` list above is derived FROM this rather than beside it,
    /// so the two orderings can never differ — a row opening the sheet for the
    /// transaction above it is the kind of defect that renders perfectly.
    private var pairs: [(move: FramesMove, owner: String)] {
        accounts.filter(\.reached)
            .flatMap { account in account.moves.map { (move: $0, owner: account.address) } }
            .sorted { $0.move.blockNumber > $1.move.blockNumber }
    }

    var body: some View {
        scoped
            // **THE FIRST ONE, ONCE EVER** (2026-09-01).
            //
            // Not the first broadcast — the send sheet already rains when the
            // node accepts the bytes, and accepting bytes is not the chain
            // agreeing. This fires when a transaction this phone signed turns
            // out to be REAL, which is the thing the seat is for and happens
            // exactly once per person.
            //
            // **A sentence, not a second shower.** The send that produced it
            // rained seconds ago, and dealing another over it is the stutter
            // `BerryRain`'s "one gesture, one shower" ruling forbids in a
            // different costume. The toast carries the seat's own mark and a
            // success haptic, which is the register this app already uses for
            // "your first X".
            //
            // Spent HERE rather than at the settle, because a celebration
            // nobody was present for is not a celebration — this seat is one
            // chip away from three others and the room may not have been open.
            .task(id: FramesLiveState.shared.firstSettle) {
                guard FramesLiveState.shared.firstSettle != nil else { return }
                FramesLiveState.shared.spendFirstSettle()
                chrome.flash(String(localized: "Your first transaction landed"),
                             tone: .success,
                             mark: FramesIdentity.source,
                             seconds: 3)
            }
    }

    @ViewBuilder private var scoped: some View {
        switch section {
        case .home:
            // **HOME HOLDS THE TILES, NOT A FORM** (§553's ruling, mirrored).
            FramesSendCard(onSend: onSend)
        case .activity:
            rows(pairs)
        case .frames:
            rows(pairs.filter { $0.move.rows.count > 1 })
        case .sponsors:
            // **TWO KINDS OF ROW, SAID TO BE TWO** (user, 2026-09-02: *"sponsors
            // list also is messy"*). A person and a transaction have different
            // anatomies, and stacked under one caption at one spacing they read
            // as a single list that keeps changing shape. Each block names
            // itself; `s6` between them is the gap the app already uses for
            // "these are different things".
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                payers
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(String(localized: "What they paid for"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                    // **THE SPONSORSHIP CLAUSE IS DROPPED HERE.** Every row in
                    // this scope is sponsored by definition, so the word
                    // separates nothing and costs the line its remaining
                    // width — §548's own ruling against the frame-count
                    // sentence on Activity, one chip over.
                    rows(pairs.filter { $0.move.sponsored }, showsSponsorship: false)
                }
            }
        }
    }

    /// **WHO PAID — the scope's other subject, and it had no surface at all.**
    ///
    /// The figure draws one split bar: how much of the gas here somebody else
    /// covered. It could not say WHO, and on this chain that is the whole
    /// interesting half — the `payer` field is the reading no ordinary chain
    /// publishes, and a sponsor is the one stranger on a network of eighteen
    /// addresses genuinely worth following.
    ///
    /// Above the transactions rather than below, because the people are what
    /// the scope is ABOUT and the transactions are the evidence.
    @ViewBuilder private var payers: some View {
        let roster = FramesPayers.roster(moves)
        if !roster.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(roster.count == 1 ? String(localized: "1 sponsor")
                                       : String(localized: "\(String(roster.count)) sponsors"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                ForEach(roster) { payer in
                    Button {
                        DSHaptic.selection()
                        onOpenPayer?(payer)
                    } label: {
                        FramesPayerRow(payer: payer).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// **A ROW FOR SOMETHING THAT HAS NOT LANDED YET.**
    ///
    /// Deliberately NOT a `FramesMoveRow` with invented fields: it has no
    /// outcome, no gas and no fee, because none of those exist until a block
    /// carries it, and filling them with zeros would be the §83 fake status on
    /// the row somebody is watching hardest. It says the two things that ARE
    /// true — that this phone sent it, and how many frames went — and nothing
    /// else.
    private func pendingRow(_ item: FramesPending) -> some View {
        // **THE CLAIM DECAYS RATHER THAN POPPING** (2026-09-01).
        //
        // `reconcilePending` drops a hash the chain has not carried inside its
        // window, and its own doc says why: we cannot tell "still queued" from
        // "dropped" from here, so we stop narrating rather than call it
        // failed. That is right and it was drawn wrong — the row stood at full
        // strength saying "Sending…" and then was simply gone, which from
        // outside reads as the transaction being lost rather than as us losing
        // our grip on a claim.
        //
        // A 1Hz tick, bounded by construction: it exists only while something
        // is pending, in a stack that is already redrawing a spinner, and
        // blocks here land in seconds so the common life of this view is two
        // or three ticks.
        TimelineView(.periodic(from: item.at, by: 1)) { tick in
            let age = tick.date.timeIntervalSince(item.at)
            let doubt = FramesLiveState.pendingDoubtAfter
            let span = max(1, FramesLiveState.pendingWindow - doubt)
            // Never below a floor: a row you can barely see is a row that has
            // already made the claim this dim exists to withdraw.
            let strength = age <= doubt ? 1
                : max(0.4, 1 - (age - doubt) / span * 0.6)
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.legs == 1
                         ? String(localized: "1 frame")
                         : String(localized: "\(String(item.legs)) frames"))
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    Text(String(localized: "Sending\u{2026}"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
                ProgressView().controlSize(.mini)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(strength)
            .animation(DS.Motion.standard, value: strength)
        }
        .transition(.opacity)
    }

    @ViewBuilder private func rows(_ list: [(move: FramesMove, owner: String)],
                                   showsSponsorship: Bool = true) -> some View {
        // **PENDING FIRST, and only in the scopes where it belongs.** Activity
        // is every transaction and Home is where the send lives, so a
        // just-broadcast batch belongs in both. Frames and Sponsors select rows
        // by properties nothing can know yet — how many frames RAN, and who
        // PAID — so a pending row there would be filed under a claim that has
        // not been made.
        let inFlight = section == .activity ? FramesLiveState.shared.pending : []
        if !inFlight.isEmpty {
            VStack(spacing: DS.Space.s2) {
                ForEach(inFlight) { pendingRow($0) }
            }
            .padding(.bottom, DS.Space.s2)
            // The row already declared `.transition(.opacity)` and nothing
            // ever animated the container, so every removal was a cut. Keyed
            // on the IDs rather than the array: a `FramesPending` carries a
            // date, so `value: inFlight` would re-run on nothing changing.
            .animation(DS.Motion.standard, value: inFlight.map(\.id))
        }
        if list.isEmpty, inFlight.isEmpty {
            Text(String(localized: "Nothing here yet."))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
                .padding(.vertical, DS.Space.s3)
        } else {
            VStack(spacing: DS.Space.s2) {
                ForEach(list, id: \.move.id) { pair in
                    let move = pair.move
                    Button {
                        DSHaptic.selection()
                        onOpenMove(move, pair.owner)
                    } label: {
                        FramesMoveRow(move: move, showsSponsorship: showsSponsorship)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        // **THE SETTLE, ON THE ROW SOMEBODY IS WATCHING.**
                        // The pending row above it fades out and the real one
                        // arrives in the same beat, so a send becoming real is
                        // a thing you SEE rather than a row that is suddenly
                        // there. `arrivalWash` is the app's existing one-shot —
                        // latched per view, dropped under Reduce Motion, and
                        // gone by the next read, so it can never become a badge.
                        .arrivalWash(FramesLiveState.shared.hasJustArrived(move.hash))
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
    /// False in the Sponsors scope, where every row is sponsored and the word
    /// is a tally of everything.
    var showsSponsorship = true

    /// **THE VERDICT COMES FROM THE MODEL** (2026-09-02). It was spelled out
    /// here, where nothing else could reach it — so the sheet this row now
    /// opens would have had to derive the same rule a second time, and two
    /// readings of THIS rule drifting means a row and its own sheet disagreeing
    /// about whether somebody's money moved. `FramesMove.verdict` is the one
    /// door, and the harness mutates it.
    private var verdict: FramesMove.Verdict { move.verdict }

    /// **THE ROW SAYS FOUR THINGS, AND IT USED TO SAY SEVEN** (user,
    /// 2026-09-02: *"thats a lot of detail for the list. it should be cleaned
    /// up not all of that needs to show at this level"*).
    ///
    /// It carried the frame count, the verdict, "Somebody else paid", the
    /// recipients, the time, the amount, the fee AND the gas — and on a
    /// sponsored row that overflowed so badly the words broke one per line
    /// (`Someb / ody / else / paid`, seen on a device).
    ///
    /// **Every one of those was right when it was added and the reason has
    /// since expired.** §548's seventh follow-up put the recipient and the fee
    /// here explicitly because the row was the ONLY surface — there was no
    /// sheet, so a fact not on the row was a fact nowhere. There is a sheet
    /// now, and it carries all seven with room to explain them. What stays is
    /// what a LIST is for: what it was, whether anything is wrong, when, and
    /// how much.
    ///
    /// **The clauses are ONE `Text`, not several in an `HStack`** — that is
    /// the whole of the wrap fix. SwiftUI squeezes an over-committed row by
    /// picking a child and shrinking it to its minimum width, so a long middle
    /// clause wraps into a one-word column while its siblings sit at full
    /// width. Concatenated runs cannot do that; they wrap as a sentence, and
    /// this one is capped at a line.
    private var meta: Text? {
        var out: Text?
        func add(_ piece: Text) {
            out = out.map { $0 + Text(verbatim: " · ").foregroundColor(DS.textTertiary) + piece }
                ?? piece
        }
        // **ONLY WHEN SOMETHING IS WRONG.** "Ran" is the answer on nearly every
        // row, so printing it is a word that separates nothing — while its
        // absence makes the rows that DO say something impossible to miss.
        if verdict.isTrouble {
            add(Text(verdict.word).foregroundColor(DS.destructive))
        }
        // One word, not a sentence: the scope is called Sponsors and the sheet
        // says who and how much.
        if move.sponsored, showsSponsorship {
            add(Text(String(localized: "Sponsored")).foregroundColor(DS.textTertiary))
        }
        // Nil draws nothing rather than "now" — the header read is bounded, so
        // a move outside the window legitimately has no time (§515a).
        if let when = FramesFormat.time(move.timestamp) {
            add(Text(when).foregroundColor(DS.textTertiary))
        }
        return out
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                // **AN ORDINARY TRANSACTION IS NOT "0 FRAMES".** This chain
                // carries both — the faucet pays out as a plain type-0x2
                // transfer — and a row reading "0 frames" over one of them is
                // a count where a noun belongs.
                Text(move.rows.isEmpty
                     ? String(localized: "Transfer")
                     : move.rows.count == 1
                       ? String(localized: "1 frame")
                       : String(localized: "\(String(move.rows.count)) frames"))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                if let meta {
                    meta.dsText(.label12).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            // **WHAT IT MOVED, AND NOTHING ELSE IN THIS COLUMN.** The fee and
            // the gas were here and are now the sheet's — three stacked
            // figures made the money column wider than the words beside it,
            // which is what left the metadata line no room at all. It is exact
            // (§548): every ETH movement is a log and the receipt names both
            // the fee and who paid it. Nil draws nothing rather than a zero.
            if let delta = move.deltaWei {
                Text(FramesMoney.signedETH(wei: delta, compact: true))
                    .dsText(.callout15)
                    .foregroundStyle(delta > 0 ? DS.confirm : DS.textPrimary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .contentShape(Rectangle())
    }
}

/// ONE SPONSOR, as a row.
///
/// **The figure's split bar says how much and this says who** — the two halves
/// of the one reading this chain publishes that ordinary chains hide.
struct FramesPayerRow: View {
    let payer: FramesPayer

    /// **NO FACE, so the scope's two lists share a left edge** (user,
    /// 2026-09-02: *"terrible indentation"*).
    ///
    /// A `DS.Face.list` mark pushed this row's words 76pt right of the
    /// transaction rows directly beneath it, under captions that both sit at
    /// the margin — so the block read as a list that could not decide where it
    /// started. A list's rows share a left content edge, and here there are
    /// two lists stacked.
    ///
    /// The identity is not lost, it MOVED: the payer sheet this row opens
    /// leads with the same face at `DS.Face.shelf`, which is where a portrait
    /// belongs (§435's own rule — a face is the subject of the sheet, and one
    /// of several in a roster). The chevron and the two captions are what keep
    /// the kinds apart here.
    var body: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(FramesWatch.shared.name(for: payer.address)
                     ?? WalletStore.shortAddress(payer.address))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(payer.count == 1
                     ? String(localized: "1 transaction")
                     : String(localized: "\(String(payer.count)) transactions"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: DS.Space.s2)
            // **NOT A ZERO WHEN IT COULD NOT BE TOTALLED.** `FramesPayer
            // .gasWei` is all-or-nothing on purpose, and printing "0.000000"
            // for an incomplete sum understates a specific person's generosity
            // (§515a, wearing a name).
            if let fee = FramesMoney.feeLine(wei: payer.gasWei) {
                Text(fee).dsText(.label12).foregroundStyle(DS.textSecondary)
                    .monospacedDigit().lineLimit(1)
            }
            WalletRowChevron()
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

    /// **THE DRAWING DRAWS ITSELF** (prd §297), and left to right is the
    /// direction it means: oldest bar first, newest on the right, so the wipe
    /// is the account's own history accruing. Invisible to
    /// `design-motion-audit` because it is a `Canvas` rather than a
    /// proportional shape — which is how a room where every other sized-from-
    /// data drawing arrives kept two that simply were.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // **THE FLOOR SCALES WITH THE DRAWING.** It was a flat 4pt,
                // chosen when this chart was 64pt tall; at the slot's real
                // height 4pt is 3% of the box, so on this chain's own spread —
                // a 1 ETH faucet claim beside 0.001 sends, a 1000:1 ratio —
                // five of six real transactions drew as hairlines and the
                // chart read as empty. Still NOT a log scale, for the reason
                // below: this raises the minimum, it does not restate any
                // bar's magnitude relative to another above it.
                let floor = max(4, (mid - 3) * 0.08)
                let height = max(floor, CGFloat(abs(value) / peak) * (mid - 3))
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
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "\(String(bars.count)) movements")))
    }
}

/// **THE ROOM'S SIGNATURE DRAWING: a transaction as its parts.**
///
/// One run per transaction, one cell per frame, each cell's width the VALUE
/// that frame moved (the gas share it used to be was measured meaningless —
/// see the note at the widths). Nothing else in this app draws a transaction
/// as a sequence, because no other chain this app reads publishes one.
///
/// **Three states, and the third is the whole point.** A frame that ran is
/// filled; one that reverted is filled in the destructive tone; one that was
/// ROLLED BACK is outlined — because it reports `status: 0x1` and did nothing,
/// so filling it like a success would be the lie §548 was written about.
struct FramesSequenceStrip: View {
    let runs: [[FramesFrameRow]]

    /// **THE TIE, AS A DIAL RATHER THAN A FACT** (2026-09-01).
    ///
    /// The room passes 1 and the drawing is the data's. The send preview
    /// passes the toggle, so flipping all-or-nothing GROWS the ties instead of
    /// swapping one static picture for another — which is what it did, despite
    /// the `.animation(_:value: atomic)` already sitting on it: a `Canvas`
    /// redraws whole, so nothing about that modifier could reach inside it.
    /// `FramesSequenceCanvas` is `Animatable` for exactly this one value.
    ///
    /// It is a dial and not a second source of truth: a tie is drawn only
    /// where the RUN says the frames are joined, so this can hide a join that
    /// exists and can never invent one that does not.
    var joinProgress: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // **THE DRAWING DRAWS ITSELF** (prd §297). It is a `Canvas`, so
        // `design-motion-audit` — which looks for proportional shapes and
        // `GeometryReader` — could not see that it had no entrance, and it
        // did not: every other sized-from-data drawing in this room arrives
        // and this one simply was.
        //
        // Left to right is the direction it MEANS: these cells are frames in
        // execution order, so the wipe is the transaction running.
        FramesSequenceCanvas(runs: runs, joinProgress: joinProgress)
            .chartWipe(reduceMotion: reduceMotion)
            .accessibilityElement()
            .accessibilityLabel(Text(String(localized: "\(String(runs.count)) transactions, drawn frame by frame")))
    }
}

private struct FramesSequenceCanvas: View, Animatable {
    let runs: [[FramesFrameRow]]
    var joinProgress: Double

    /// One value, so a plain `Double`. This is what lets a `Canvas`
    /// interpolate at all — SwiftUI animates a view's `animatableData` and
    /// re-evaluates its body per frame; without it the parent's `.animation`
    /// modifier has nothing inside the drawing to move.
    var animatableData: Double {
        get { joinProgress }
        set { joinProgress = newValue }
    }

    private static let rowHeight: CGFloat = 14
    private static let gap: CGFloat = 6
    /// The space between two cells that are NOT joined. Joined cells touch, so
    /// this gap is the whole of how a person sees an atomic group.
    private static let cellGap: CGFloat = 3

    var body: some View {
        Canvas { ctx, size in
            guard !runs.isEmpty else { return }
            let rowGap = Self.gap
            let height = min(Self.rowHeight,
                             (size.height - rowGap * CGFloat(runs.count - 1)) / CGFloat(runs.count))
            for (row, run) in runs.enumerated() {
                let y = (height + rowGap) * CGFloat(row)

                // **WIDTH IS VALUE MOVED, NOT GAS** (2026-09-01). The first cut
                // used each frame's `gasUsed` share, and that number was
                // measured to be nearly meaningless here: on a transaction this
                // app sent, the frames reported 100 and 3,000 against a receipt
                // of 210,790 — over 98% of the real cost is attributed to no
                // frame at all. So gas shares claimed a cost breakdown this
                // chain does not publish.
                //
                // Value is a fact each frame carries in its own right, it is
                // what a batch is actually FOR, and a three-leg send now reads
                // as ascending cells instead of three identical ones.
                //
                // The VERIFY frame moves nothing by design, so it is given a
                // FIXED narrow cell rather than a zero-width one or a share of
                // nothing: it is the frame that authorises, it is present in
                // every transaction here, and a drawing that omits it is
                // drawing a different transaction.
                let verifyWidth: CGFloat = 12
                let values: [Double] = run.map { cell in
                    guard cell.frame.mode != 1 else { return 0 }
                    return Self.weiMagnitude(cell.valueWeiHex)
                }
                let verifyCount = run.filter { $0.frame.mode == 1 }.count
                let payloadCount = run.count - verifyCount
                let total = values.reduce(0, +)
                let gaps = CGFloat(max(0, run.count - 1)) * Self.cellGap
                let payloadSpace = max(0, size.width - gaps - verifyWidth * CGFloat(verifyCount))

                var x: CGFloat = 0
                for (i, cell) in run.enumerated() {
                    let w: CGFloat
                    if cell.frame.mode == 1 {
                        w = verifyWidth
                    } else if total > 0 {
                        w = max(4, CGFloat(values[i] / total) * payloadSpace)
                    } else {
                        // Every payload frame moved nothing — a batch of pure
                        // calls. Equal widths say "these ran" without claiming
                        // a size none of them has.
                        w = max(4, payloadSpace / CGFloat(max(1, payloadCount)))
                    }
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

                    // **THE JOIN, which is the thing this room could not show
                    // until the send could make one.** `flags` bit 2 means
                    // "joined to the frame after me" — proven by the node
                    // refusing it on a last frame — so a run of joined frames
                    // plus the first unjoined one after them is ONE atomic
                    // group, and the two transactions this app sent that
                    // differ ONLY in that bit drew identically here.
                    //
                    // Drawn as a TIE between the cells rather than as a colour
                    // or a badge: atomicity is a relationship between two
                    // frames, and every other encoding would make it a property
                    // of one of them.
                    let last = i == run.count - 1
                    // `joinProgress` scales it and can only ever HIDE a join
                    // the run declares — never draw one it does not.
                    if cell.joinedToNext, !last, joinProgress > 0.01 {
                        let tieH = max(2, height * 0.34) * joinProgress
                        let tie = CGRect(x: x + w, y: y + (height - tieH) / 2,
                                         width: Self.cellGap, height: tieH)
                        ctx.fill(Path(tie), with: .color(DS.tint.opacity(0.55)))
                    }
                    x += w + Self.cellGap
                }
            }
        }
        // The wrapper carries the one label. Two accessibility elements over
        // one drawing reads the same fact twice.
        .accessibilityHidden(true)
    }

    /// A wei hex string as a magnitude for RELATIVE widths only.
    ///
    /// `Double` is fine here and nowhere else in this seat: this is the ratio
    /// between two bars on a 350pt strip, never a figure anybody reads, and
    /// the alternative — `Decimal` arithmetic per cell inside a `Canvas` draw
    /// — buys precision that cannot be seen. Anything a person READS goes
    /// through `FramesMoney`, which carries wei as `Decimal` precisely because
    /// this chain holds balances past `UInt64`.
    static func weiMagnitude(_ hex: String?) -> Double {
        guard let hex else { return 0 }
        let body = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
        guard !body.isEmpty else { return 0 }
        var out = 0.0
        for ch in body {
            guard let d = ch.hexDigitValue else { return 0 }
            out = out * 16 + Double(d)
        }
        return out
    }
}

/// WHO PAID THE GAS — one bar, split.
///
/// Exact: `gasUsed` and `effectiveGasPrice` are on every receipt and the
/// `payer` says whose it was. The reading no ordinary chain can give.
struct FramesSponsorBar: View {
    let mine: Double
    let theirs: Double
    /// A sponsored transaction landed while somebody was in this scope.
    var glance = false

    /// **A DRAWING SIZED FROM DATA GETS AN ENTRANCE** (prd §299) — caught by
    /// `design-motion-audit`, not by looking. It grows from the leading edge,
    /// which is the direction the split is read in, and Reduce Motion lands it
    /// at full width on the first frame rather than animating faster.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    /// The glance's own clock, latched so a re-compose cannot replay it —
    /// this scope re-composes on every read, and a segment that keeps
    /// flickering is the badge `ArrivalWash` exists to refuse.
    @State private var glanced = false
    @State private var lit = false

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
                        // A GLOW, not a size change and not a hue change: the
                        // segment's width is a measurement and its colour is
                        // the room's, so the only thing left to lend it is
                        // light. Nothing when idle.
                        .shadow(color: DS.tint.opacity(lit ? 0.7 : 0),
                                radius: lit ? 7 : 0)
                }
            }
            .scaleEffect(x: grown ? 1 : 0.001, anchor: .leading)
            .onAppear {
                guard !reduceMotion else { grown = true; return }
                withAnimation(DS.Motion.standard) { grown = true }
            }
            .task {
                // Reduce Motion draws nothing at all rather than a slower
                // glow — the fact is already in the bar's own proportions,
                // and this is the flourish that preference exists to drop.
                guard glance, !glanced, !reduceMotion else { return }
                glanced = true
                // A beat, so the bar's own growth lands first and the glance
                // reads as a mark ON a settled drawing rather than as part of
                // its arrival (`ArrivalWash`'s reasoning, same number).
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeOut(duration: 0.22)) { lit = true }
                try? await Task.sleep(nanoseconds: 620_000_000)
                withAnimation(.easeInOut(duration: 0.5)) { lit = false }
            }
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "Gas paid by others, against gas you paid")))
    }
}
