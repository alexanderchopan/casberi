import SwiftUI

/// Where the money actually went — the flow band, in its ruled form
/// (2026-08-01, `design/wallet-viz/sankey-cashapp-mocks.html`, option B:
/// "the bleed band").
///
/// The balance line says the total moved. This says through whom: inflows
/// left, the wallet as a spine, outflows right, every lane sized by what it
/// was worth when it moved. Money moving is the module doctrine's standing
/// exception to "never a tally", and every slab here is a real landed
/// transfer rather than a count of them.
///
/// ## The drawing grammar, and why it looks like nothing else in the room
///
/// Solid slabs of colour mass run EDGE TO EDGE through the card's own
/// padding; the connectors are straight tapers with square shoulders (no
/// bezier softness); the money type sits dark-on-green the way a Cash App
/// balance pill does. That's deliberate rule-breaking with a precedent — the
/// treemap's own Cash App exercise ruled that when every element on a screen
/// is a rounded capsule, the standout move is BREAKING the shape grammar
/// rather than adding one more capsule. This card is the one non-capsule
/// object in the room, and the card's own clip supplies the only curve.
///
/// The v1 form (rounded slabs, gradient ribbons, a bright full-height spine)
/// was rejected on sight: the bars were the heroes, the ribbons were leftovers
/// nobody could see, and the spine was the loudest object on the card while
/// meaning the least.
///
/// ## Rules kept
///
/// **In is green, out is neutral slab — never red.** Arriving money is this
/// app's one green note. Painting outflow red
/// would make every deliberate payment an alarm, which is the ruling
/// `WalletCompositionStrip` already keeps for "Owed": a debt you opened on
/// purpose isn't an emergency, and neither is rent.
///
/// **One scale across both sides** — see `WalletFlow.Band.scaleUSD` for why
/// per-side normalising would break the band's only real claim.
///
/// **The spine is you.** Your wallet's face on its own identity tint when the
/// room is scoped (or a single wallet is watched); the combined view draws the
/// app tint and NO face, because a face that isn't anyone's would be fake
/// identity — the honesty rule applied to a portrait.
///
/// **Nothing is tappable.** A lane is usually several transfers folded
/// together, so a tap would have to pick one to open, and picking is the sort
/// of quiet lie the honesty rule exists to stop. The band is a read; the rows
/// below it are the door.
///
/// **It draws itself** (user, 2026-08-03: "every visualization we have should
/// draw itself in some way"), amending 2026-08-01's "we don't need the motion".
/// What that first ruling killed was a drift-dot loop — money crawling along
/// the tapers forever, which claims live streaming the way the endpoint pulse
/// does and is decoration by the §129 test. What it takes instead is ONE
/// left-to-right wipe (`ChartEntrance`), which is not decoration: this diagram's
/// whole claim is that money entered on the left, passed through you, and left
/// on the right, so a reveal along that axis is the claim being made in time.
/// The out slabs land last because they happened last. Nothing loops; nothing
/// moves again after the beat.
///
/// No `Thing` is stored — `WalletFlowSource` reduced them to values at the
/// boundary — so the liveness rules have nothing to bite on here.
struct WalletFlowBand: View {
    let band: WalletFlow.Band
    /// "This week" / "This month" / "Since you started watching" — the window
    /// the band was built from, named so the card can never be read against
    /// the wrong period.
    let windowLabel: String
    /// The wallet whose face rides the spine — the scoped wallet, or the sole
    /// watched one. nil (several wallets, unscoped) draws the app tint alone.
    var spineAddress: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One flag for the whole entrance; each element hangs its OWN delayed
    /// animation off it (`WalletRiskStrip`'s shape). The face pops as the wipe
    /// reaches the spine, the outcome sentence lands after the money has
    /// finished moving — two beats off one wipe, not three animations arguing
    /// for attention.
    @State private var entered = false
    /// The pressed lane (2026-08-14, prd §386d) — named IN PLACE, in the
    /// summary's own slot, so the answer appears where the eye already is and
    /// the card never changes height. The §384 press-reveals-a-fact grammar
    /// reaching the one figure it had skipped: a slab already carries its
    /// name and value when it is TALL, and carries neither when it is thin,
    /// which is exactly when a reader most wants to know what it is.
    /// Auto-reverts; a fresh press restarts the clock.
    @State private var picked: WalletFlow.Lane?
    @State private var pickedClear: Task<Void, Never>?

    /// 148. It went 138 → 170 when the coverage note was deleted, on the
    /// reasoning that the reclaimed height should go into the gaps between
    /// labels — which was right while each end was two stacked lines. Once
    /// `endpoint` put name and amount on ONE baseline (~37pt of type per end
    /// down to ~21pt) the gaps came back for free, and 170 was then spending
    /// the slot on air: the room's slot is fixed, so height this drawing does
    /// not need is height the list below never gets. 164 rather than 148 on
    /// the device: at 148 the drawing cleared the slot by about 45pt, which is
    /// the dead band this pass was fixing wearing the opposite sign.
    ///
    /// **DERIVED, not 164 (2026-09-03, prd §589; the slot growth is prd 588).** Wallet's scopes pass
    /// `reservesHeadline: false`, so the band is offered the WHOLE
    /// `visualSlot`, and a literal here is a second copy of that number that
    /// cannot know when the box moves — prd 588 grew it, and the literal left
    /// ~97pt of dead air under a top-aligned, clipped drawing. 39 is this
    /// view's own chrome above the band: the `label12` caption (15), the `s3`
    /// top inset (14), the `s2` below it (10). At the old 210 box this is 171,
    /// which the 164 measured above was already within 7pt of.
    private var bandHeight: CGFloat { DSRoomChassis.visualSlot - 39 }
    private let laneGap: CGFloat = 2
    private let spineWidth: CGFloat = 12
    /// One line of `label12` fits a 14pt slab; the floor keeps every lane
    /// nameable (the v1 lesson, measured: at a 6pt floor a real $340 outflow
    /// drew 17pt and fell under every label threshold, so the card showed one
    /// named bar and two anonymous ones).
    private static let minSlabHeight: CGFloat = 14
    /// Above this a slab carries name AND value on two lines; below, one
    /// joined line, because the bar's own height is already stating the size.
    private static let twoLineHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **ONE LINE ABOVE THE BAND** (user ruling, prd §483: *"i want to
            // get rid of as much words as possible that are above the sankey"*,
            // and *"really lean into this clean restrained apple like
            // version"*). This carried FOUR: a heading, the window and totals,
            // the net, and the coverage note.
            //
            // **The heading and the window went because the drawing already
            // said them.** The band labels its left column with names AND
            // amounts and its right the same way, so "in $7K · out $3K" was the
            // sum of one column and the sum of the other, both on screen — §208
            // ("never say one thing twice") committed by a header. "Since you
            // started watching" is the same window for every reading in this
            // room and never changes.
            //
            // **And the real cost was legibility, not tidiness.** Inside §483's
            // fixed 200pt slot those four lines left the band 96pt, where four
            // ribbons are ~12pt tall and cross into a smear. At one line the
            // band gets 150 and you can follow Coinbase to Bitrefill with your
            // eye — which is the only thing this drawing exists to let you do.
            //
            // The NET survives (`netLine`) because it is the one figure here
            // that is nowhere else in the scope: in−out, and the reader would
            // have to do the subtraction themselves.
            HStack(spacing: DS.Space.s2) {
                Text(pickedLine ?? summary)
                    .dsText(.label12)
                    .foregroundStyle(picked == nil ? DS.textTertiary : DS.textPrimary)
                    .lineLimit(1)
                netLine
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 3)
                    .animation(netAnimation, value: entered)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WalletCardStyle.pad)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s2)

            // The band itself takes no horizontal padding: the bleed IS the
            // design, and the card's clip below supplies the only rounding.
            GeometryReader { geo in
                diagram(width: geo.size.width)
            }
            .frame(height: bandHeight)
            // The money moves through the band once, in the direction it
            // actually moved. See the type doc's amended ruling.
            .chartWipe(reduceMotion: reduceMotion)

            // A `Path` and a stack of rectangles read as NOTHING to VoiceOver,
            // and this diagram is the only place the app states where the money
            // came from and where it went (2026-08-04, prd §299). One figure,
            // one sentence — the treatment `AddressConnectionsCard` already
            // gives its spine, rather than a dozen stray slab labels.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(spokenDiagram))

            // **THE COVERAGE NOTE IS GONE** (user ruling, prd §483: *"get rid
            // of '1 move couldn't be priced' — this is a summary, we don't need
            // all"*). It said the band was drawn from six of nine moves rather
            // than all nine.
            //
            // That is a real §83 fact and it is worth saying WHY dropping it is
            // not the overclaim it looks like: this scope's own list sits
            // directly below the toggle and holds every move, priced or not. The
            // drawing was never the complete record and does not have to be —
            // it is the summary, the list is the record, and a caveat about
            // completeness belongs to whichever one CLAIMS to be complete.
            //
            // `coverageNote` survives, unused by this view, because it is also
            // read by `spokenDiagram`: a sighted reader has the list two rows
            // down, and a VoiceOver reader stepping through the figure does not.
        }
        // A plain set: each element owns its own delayed animation above.
        .onAppear { entered = true }
        // **NO CARD, NO CLIP** (user ruling, prd §483: *"it is still on a card
        // and shouldn't be"*). The 2026-08-22 recipe above — clip first, surface
        // second — existed because the band BLED to the card's edges and the
        // clip had to reach them. There is no card now, and nothing to bleed
        // against: the drawing is hairlines with their own margins, so a clip
        // would only cut the strokes' round caps at the extremes.
        //
        // Every drawing in this room sits bare on the page now — the sparkline,
        // the treemap, and this.
    }

    private var summary: String {
        // No `windowLabel`: it is the same window for every reading in this
        // room, so it never distinguished anything (prd §483).
        "in \(WalletValue.money(band.inUSD)) · out \(WalletValue.money(band.outUSD))"
    }

    /// "Kept +$1.0K" — the one-sentence outcome, the move Cash App would make
    /// before any drawing. A net that rounds to nothing draws no line at all
    /// (the `isFlat` rule: no direction, no sentence), and a down week stays
    /// in plain ink rather than red, for the same reason the out slabs do.
    @ViewBuilder
    private var netLine: some View {
        let net = band.netUSD
        if abs(net) >= 1 {
            if net > 0 {
                Text("Kept +\(WalletValue.money(net))")
                    .dsText(.label12).fontWeight(.bold)
                    .foregroundStyle(DS.confirm)
            } else {
                Text("Down −\(WalletValue.money(-net))")
                    .dsText(.label12).fontWeight(.bold)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    /// The outcome sentence arrives AFTER the band has finished drawing — the
    /// same ordering `GenMoneyHero` keeps between its rolling total and its
    /// delta pill (2026-07-22): a summary that lands with the thing it
    /// summarizes makes the eye choose, and it always chooses wrong.
    private var netAnimation: Animation? {
        reduceMotion ? nil
            : DS.Motion.standard.delay(ChartEntrance.lead + ChartEntrance.wipe * 0.9)
    }

    /// You arrive as the money reaches you — the wipe uncovers the face at the
    /// same instant it pops, so the spine reads as what the inflows were
    /// travelling towards.
    private var faceAnimation: Animation? {
        reduceMotion ? nil
            : ChartEntrance.land(after: ChartEntrance.lead + ChartEntrance.wipe * 0.5)
    }

    /// What this band does NOT cover, in one line — nil when it covers
    /// everything.
    ///
    /// Two causes, kept as separate clauses rather than summed into one number
    /// (2026-08-03): a move that COULDN'T be priced says the read fell short,
    /// while a move OLDER than price data says nothing about the read at all
    /// and will never change. Adding them would produce a number that reads as
    /// an accusation against the price read on any corpus with history.
    private var coverageNote: String? {
        var parts: [String] = []
        if band.unpricedCount > 0 {
            parts.append(band.unpricedCount == 1
                ? String(localized: "1 move couldn't be priced")
                : String(localized: "\(band.unpricedCount) moves couldn't be priced"))
        }
        if band.predatingCount > 0 {
            parts.append(band.predatingCount == 1
                ? String(localized: "1 is older than price data")
                : String(localized: "\(band.predatingCount) are older than price data"))
        }
        guard !parts.isEmpty else { return nil }
        return String(localized: "\(parts.joined(separator: " · ")) — not drawn")
    }

    // MARK: - Geometry

    private struct Seg {
        let lane: WalletFlow.Lane
        let rank: Int
        let slabTop: CGFloat
        let spineTop: CGFloat
        let height: CGFloat
    }

    /// **LINES, NOT BANDS** (prd §483, 2026-08-26, user: *"we need a diagram,
    /// not a table … i think what we had could be fine if they were lines and
    /// not bands"*, then *"do q4"*).
    ///
    /// **Why the bands had to go, and it is one sentence.** A band has to be
    /// thick enough to MEAN its amount and thick enough to HOLD its label, and
    /// those two demands fight — which is every problem this drawing had: a
    /// $300 lane could not carry its own name, so labels were crammed inside
    /// shapes, reversed out in two different treatments, and clipped.
    ///
    /// A stroke has no such duty. It carries STRUCTURE — how many arrived, how
    /// many left, that everything passed through one place — which is the thing
    /// the list twelve points below structurally cannot show, and the whole
    /// reason this scope leads with a figure rather than more rows. The amounts
    /// live in labels, in their own columns, where nothing can crowd them.
    ///
    /// **A GATE, NOT A POINT, and that is geometry rather than taste.** The
    /// strokes are weighted (1…3.6pt), and weighted lines converging on a
    /// single coordinate all collapse to zero width at the same spot — four of
    /// them pile into a smudge just before it, destroying the widths exactly
    /// where the eye lands. A gate gives every line its own slot to arrive at,
    /// so the weights survive the middle.
    ///
    /// **And the gate draws the net for free.** Each slot is proportional to
    /// its lane, so the in-lines fill the whole gate while the out-lines fill
    /// only `outUSD/inUSD` of it: lit full height on the left, part height on
    /// the right, and the difference is what stayed. That is the one reading a
    /// sentence had to assert before — now it is a shape.
    ///
    /// **It also ends a quiet dishonesty.** The old ribbons ran lane→spine→lane
    /// and looked like a sankey, but `inLanes` and `outLanes` are separate
    /// arrays and nothing in the data pairs a source with a destination. Those
    /// ribbons implied that Peer's money went to Uniswap. Converging on the
    /// wallet's own FACE claims only what is true: money reached you, and some
    /// of it left.
    private func diagram(width: CGFloat) -> some View {
        let inSegs = segments(band.inLanes, sideTotal: band.inUSD)
        let outSegs = segments(band.outLanes, sideTotal: band.outUSD)
        let cx = width * 0.50
        let cy = bandHeight / 2
        // 78 was chosen against a 164 band (0.475 of it); the ratio is kept
        // rather than the literal so the gate grows with the box (prd 588) and
        // the lines still fan across it rather than piling at a short gate.
        let gate = min(bandHeight - 24, (bandHeight * 0.475).rounded())
        let gateTop = cy - gate / 2
        // The gate's lit share — what left, against what arrived. Clamped
        // because a wallet can spend more than it took in over a window, and a
        // segment taller than its own track reads as a drawing error.
        let leftShare = band.inUSD > 0
            ? min(1, band.outUSD / band.inUSD) : 0
        let heaviest = max(band.inLanes.first?.usd ?? 0, 1)

        return ZStack(alignment: .topLeading) {
            // The gate: a hairline track, and a brighter segment for the part
            // of it that leaves again.
            Capsule(style: .continuous)
                .fill(DS.textPrimary.opacity(0.16))
                .frame(width: 1.2, height: gate)
                .offset(x: cx - 0.6, y: gateTop)
            Capsule(style: .continuous)
                .fill(DS.textPrimary.opacity(0.42))
                .frame(width: 2.2, height: gate * CGFloat(leftShare))
                .offset(x: cx - 1.1, y: gateTop)

            // **THE OUTER END OF EVERY STRAND IS EVENLY SPACED, NOT
            // PROPORTIONAL** (prd §483). The labels sat at their lane's own
            // proportional position, which is where the AMOUNT puts them — so
            // the small lanes bunched, and once the label became two lines they
            // drew on top of each other on both sides ("Sam" over "Uniswap",
            // "Other" over "Bitrefill").
            //
            // Proportion belongs at the GATE, where it is the reading; at the
            // rim it was only ever deciding where a word goes. Even spacing
            // there also fills the band's full height instead of clustering
            // everything into its middle third.
            ForEach(inSegs.indices, id: \.self) { i in
                let seg = inSegs[i]
                strand(from: CGPoint(x: labelColumn, y: rimY(i, of: inSegs.count)),
                       to: CGPoint(x: cx, y: gateTop + gateOffset(inSegs, i, gate: gate,
                                                                  total: band.inUSD, share: 1)))
                    .stroke(DS.confirm.opacity(0.74 - 0.09 * Double(seg.rank)),
                            style: StrokeStyle(lineWidth: strandWidth(seg.lane.usd, of: heaviest),
                                               lineCap: .round))
            }
            ForEach(outSegs.indices, id: \.self) { i in
                let seg = outSegs[i]
                strand(from: CGPoint(x: cx, y: gateTop + gateOffset(outSegs, i, gate: gate,
                                                                    total: band.outUSD,
                                                                    share: leftShare)),
                       to: CGPoint(x: width - labelColumn, y: rimY(i, of: outSegs.count)))
                    .stroke(DS.textPrimary.opacity(0.44 - 0.055 * Double(seg.rank)),
                            style: StrokeStyle(lineWidth: strandWidth(seg.lane.usd, of: heaviest),
                                               lineCap: .round))
            }

            ForEach(inSegs.indices, id: \.self) { i in
                endpoint(inSegs[i], y: rimY(i, of: inSegs.count), incoming: true, width: width)
            }
            ForEach(outSegs.indices, id: \.self) { i in
                endpoint(outSegs[i], y: rimY(i, of: outSegs.count), incoming: false, width: width)
            }

            // The gate is YOURS — the one ornament in the room, and the only
            // thing here that says what the convergence means.
            if let spineAddress {
                // `DS.Face.row` (26), not a raw number — and `row` rather than
                    // `rowCircle` because this is an ALL-CIRCLE drawing with no
                    // squircle marks beside it to optically match (the tier's
                    // own rule).
                    WalletFace(address: spineAddress, size: DS.Face.row, circular: true)
                    .overlay(Circle().stroke(DS.page, lineWidth: 3))
                    .scaleEffect(entered ? 1 : 0.4)
                    .animation(faceAnimation, value: entered)
                    .position(x: cx, y: cy)
            }
        }
    }

    /// The label gutter on each side. Text NEVER shares space with a stroke —
    /// the rule the band version could not keep.
    /// 100, not 128. With the name on its own line a gutter no longer has to
    /// hold "Coinbase $2K" side by side — and 128 each side left the strokes
    /// only 98pt of a 354pt band to cross in, which is what made the drawing
    /// read as cramped in its own middle. The field is 154 now.
    private var labelColumn: CGFloat { 100 }

    /// 1…3.6pt by amount. Enough that the heaviest lane reads heavier at a
    /// glance; never so much that a stroke has to contain anything.
    private func strandWidth(_ usd: Double, of heaviest: Double) -> CGFloat {
        1.0 + 2.6 * CGFloat(min(1, usd / heaviest))
    }

    /// Where a lane meets the gate — the CENTRE of a slot sized by its share,
    /// so the arrivals stack rather than crushing together.
    private func gateOffset(_ segs: [Seg], _ i: Int, gate: CGFloat,
                            total: Double, share: Double) -> CGFloat {
        guard total > 0 else { return gate / 2 }
        let span = gate * CGFloat(share)
        let before = segs.prefix(i).reduce(0.0) { $0 + $1.lane.usd }
        let mine = segs[i].lane.usd
        return span * CGFloat((before + mine / 2) / total)
    }

    private func strand(from a: CGPoint, to b: CGPoint) -> Path {
        Path { p in
            p.move(to: a)
            p.addCurve(to: b,
                       control1: CGPoint(x: a.x + (b.x - a.x) * 0.55, y: a.y),
                       control2: CGPoint(x: a.x + (b.x - a.x) * 0.45, y: b.y))
        }
    }

    /// Where a strand meets the rim — EVENLY spaced, never proportional.
    ///
    /// Proportion is the gate's job; here it only decides where a word sits, and
    /// putting words at their amount's position bunches the small lanes until
    /// they overlap. Even spacing also uses the band's whole height rather than
    /// crowding everything into its middle.
    private func rimY(_ i: Int, of count: Int) -> CGFloat {
        guard count > 1 else { return bandHeight / 2 }
        let inset: CGFloat = 16
        return inset + (bandHeight - inset * 2) * CGFloat(i) / CGFloat(count - 1)
    }

    /// A lane's name and amount at the rim.
    ///
    /// **NO TERMINAL DOT** (user: *"do the lines even need dots at the end?"* —
    /// they do not). A dot marked where a stroke ended, which the stroke's own
    /// round cap already does, sitting against a label that names the same
    /// thing. Three marks for one lane; the two that carry meaning stay.
    ///
    /// **NAME AND AMOUNT SHARE ONE BASELINE, the amount pushed hard against the
    /// screen edge** (2026-08-26, prd §483 — reported as *"perhaps this is a
    /// little too tall it feels jammed in… seems like we could use the space
    /// better"*, and it was, measurably).
    ///
    /// Stacked, each end cost ~37pt of type inside a ~42pt rim step, so four
    /// lanes filled the band with about 5pt of air and the strokes had nowhere
    /// to curve. On one baseline an end costs ~21pt, which buys back roughly
    /// 16pt PER LANE — and it is bought from the axis that was scarce (height)
    /// rather than from the gutters, which is why `labelColumn` does not move:
    /// the earlier fix already took those from 128 to 100 and the collisions
    /// were never horizontal.
    ///
    /// A `Spacer(minLength:)` between them, not a fixed gutter: the name may
    /// shrink to 0.8 and the amount never may, because a truncated figure is a
    /// WRONG figure while a tightened name is still the same word.
    @ViewBuilder
    private func endpoint(_ seg: Seg, y: CGFloat, incoming: Bool, width: CGFloat) -> some View {
        // The SAME order on both sides — name first, figure at the outer edge
        // — rather than mirrored. Mirroring reads as tidier in a sketch and
        // costs the reader the one thing this drawing is for: with the figures
        // in a single column down each edge they compare at a glance, and
        // mirrored they zig-zag.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(seg.lane.name)
                .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Space.s2)
            Text(WalletValue.money(seg.lane.usd))
                .dsText(.label12).foregroundStyle(DS.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
        .frame(width: labelColumn - 10, alignment: incoming ? .trailing : .leading)
        .position(x: incoming ? (labelColumn - 10) / 2
                              : width - (labelColumn - 10) / 2,
                  y: y)
        .contentShape(Rectangle())
        .onTapGesture { pick(seg.lane) }
        .accessibilityHidden(true)
    }

    /// The diagram as a sentence — the same facts the drawing carries, in the
    /// order it draws them: in, through you, out.
    private var spokenDiagram: String {
        var parts: [String] = []
        if band.inLanes.isEmpty {
            parts.append(String(localized: "Nothing came in."))
        } else {
            parts.append(String(localized: "In from \(spokenLanes(band.inLanes))."))
        }
        if band.outLanes.isEmpty {
            parts.append(String(localized: "Nothing went out."))
        } else {
            parts.append(String(localized: "Out to \(spokenLanes(band.outLanes))."))
        }
        return parts.joined(separator: " ")
    }

    private func spokenLanes(_ lanes: [WalletFlow.Lane]) -> String {
        // VoiceOver needs a subject even where the drawing shows only a
        // number: an empty name would speak as ", $240". It says the one true
        // thing instead — that we never learned who this was.
        lanes.map { lane in
            lane.name.isEmpty
                ? String(localized: "an unnamed wallet, \(WalletValue.money(lane.usd))")
                : "\(lane.name), \(WalletValue.money(lane.usd))"
        }
        .joined(separator: "; ")
    }

    private var spineTint: Color {
        // No single address to key on (a combined, all-wallets band) has no
        // one identity to wear, so the spine goes neutral rather than blue
        // (2026-08-10) — each real wallet still gets its own `WalletFace`.
        spineAddress.map(WalletFace.tint(for:)) ?? DS.neutralBadge
    }

    /// One side's segments. Slabs stack with the model's own budgeted gap;
    /// spine ends stack CONTIGUOUSLY, which is what makes the connectors
    /// converge into the wallet. Heights come from `WalletFlow.laneHeights`
    /// rather than being computed here — that arithmetic is the one part of
    /// this card that fails invisibly (it clips off the bottom and reads as a
    /// missing counterparty), so it lives where the self-test can reach it.
    private func segments(_ lanes: [WalletFlow.Lane], sideTotal: Double) -> [Seg] {
        guard !lanes.isEmpty else { return [] }
        let inner = Double(bandHeight - 4)
        let layout = WalletFlow.laneHeights(
            lanes: lanes, sideTotal: sideTotal, scaleUSD: band.scaleUSD,
            bandHeight: inner, laneGap: Double(laneGap),
            minHeight: Double(Self.minSlabHeight))
        guard layout.heights.count == lanes.count else { return [] }

        var out: [Seg] = []
        var slabY: CGFloat = 2 + CGFloat(inner - layout.used) / 2
        var spineY: CGFloat = 2 + CGFloat(inner - layout.heights.reduce(0, +)) / 2
        for (rank, pair) in zip(lanes, layout.heights).enumerated() {
            let (lane, rawHeight) = pair
            let height = CGFloat(rawHeight)
            out.append(Seg(lane: lane, rank: rank, slabTop: slabY,
                           spineTop: spineY, height: height))
            slabY += height + CGFloat(layout.gap)
            spineY += height
        }
        return out
    }

    private func connector(fromX: CGFloat, fromTop: CGFloat,
                           toX: CGFloat, toTop: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: fromX, y: fromTop))
        path.addLine(to: CGPoint(x: toX, y: toTop))
        path.addLine(to: CGPoint(x: toX, y: toTop + height))
        path.addLine(to: CGPoint(x: fromX, y: fromTop + height))
        path.closeSubpath()
        return path
    }

    /// Rank-stepped opacity on a solid fill. The height already carries
    /// magnitude; this carries HIERARCHY, and it's what makes the band read as
    /// colour mass rather than a stack of identical tints. Deliberate, and
    /// noted in the mock's own law check.
    /// The top step is 0.82, not 1.0, and that is a COLOUR decision rather
    /// than a transparency one: `DS.confirm` at full strength is a neon block
    /// at this size, while at 0.82 over the card it composites to roughly
    /// `#2BAF4C` — the deeper money green the approved mock drew, and the one
    /// that dark label type actually sits on. Routing it through the token at
    /// reduced strength keeps the design law's "zero raw hex in components".
    private func slabOpacity(rank: Int, incoming: Bool) -> Double {
        let steps: [Double] = incoming ? [0.82, 0.66, 0.52, 0.42]
                                       : [1.00, 0.85, 0.70, 0.55]
        return steps[min(rank, steps.count - 1)]
    }

    private func slab(_ seg: Seg, width: CGFloat, incoming: Bool) -> some View {
        Rectangle()
            .fill(incoming
                  ? DS.confirm.opacity(slabOpacity(rank: seg.rank, incoming: true))
                  : DS.gray100.opacity(slabOpacity(rank: seg.rank, incoming: false)))
            .frame(width: width, height: seg.height)
            .overlay(
                label(seg.lane, incoming: incoming,
                      twoLine: seg.height >= Self.twoLineHeight)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(width: width, height: seg.height,
                           alignment: incoming ? .leading : .trailing)
            )
            // A pressed slab names itself in the summary slot above (prd
            // §386d). The whole slab is the target — a thin lane is exactly
            // the one worth pressing, and its own height is far under the
            // 44pt floor, so forgiveness has to come from the shape rather
            // than from the size. No visual affordance is drawn: nothing
            // navigates, and a figure that looks pressable is a figure
            // claiming to be a control.
            .contentShape(Rectangle())
            .onTapGesture { pick(seg.lane) }
            // NOT its own VoiceOver element, deliberately — the diagram above
            // is `.accessibilityElement(children: .combine)` carrying
            // `spokenDiagram`, which §299 ruled is the right treatment for
            // this figure ("one figure, one sentence … rather than a dozen
            // stray slab labels"). A slab that announced itself would undo
            // that ruling, and the press reveals nothing the spoken sentence
            // does not already name — it is a sighted-user shortcut to a fact
            // VoiceOver is given in full, up front. Recorded in the
            // accessibility audit's `KNOWN_EXEMPT` with this reason.
            .accessibilityHidden(true)
    }

    /// The pressed lane as one line — the name it may not have had room for,
    /// its value, and how many legs folded into it. Nil when nothing is
    /// pressed, so the summary reads exactly as it always did.
    private var pickedLine: String? {
        guard let lane = picked else { return nil }
        let money = WalletValue.money(lane.usd)
        let name = lane.name.isEmpty
            ? String(localized: "an address we can't name") : lane.name
        if lane.count > 1 {
            return String(localized: "\(name) · \(money) over \(lane.count) moves")
        }
        return "\(name) · \(money)"
    }

    private func pick(_ lane: WalletFlow.Lane) {
        DSHaptic.selection()
        withAnimation(DS.Motion.standard) { picked = lane }
        pickedClear?.cancel()
        pickedClear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.standard) { picked = nil }
        }
    }

    @ViewBuilder
    private func label(_ lane: WalletFlow.Lane, incoming: Bool, twoLine: Bool) -> some View {
        // Dark-on-green is a fixed pairing — the confirm green is the same in
        // both themes, so these two are this file's one deliberate step
        // outside the adaptive ink ramp (the Cash App balance-pill treatment
        // the mock ruled in). The out slabs ride `gray100`, which DOES theme,
        // so they stay on the ramp.
        let primary: Color = incoming ? .black.opacity(0.82) : DS.textPrimary
        let secondary: Color = incoming ? .black.opacity(0.60) : DS.textSecondary
        // An unnamed counterparty draws its VALUE alone (2026-08-11). The name
        // is empty exactly when all we ever had was an address, and the value
        // is the part we actually know — so the lane keeps its full label
        // width for the number rather than spending it on a hex string.
        if lane.name.isEmpty {
            Text(valueText(lane))
                .dsText(.label12).fontWeight(.bold)
                .foregroundStyle(primary)
                .lineLimit(1).minimumScaleFactor(0.8)
        } else if twoLine {
            VStack(alignment: incoming ? .leading : .trailing, spacing: 1) {
                Text(lane.name)
                    .dsText(.label12).fontWeight(.bold)
                    .foregroundStyle(primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(valueText(lane))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        } else {
            Text("\(lane.name) · \(WalletValue.money(lane.usd))")
                .dsText(.label12).fontWeight(.bold)
                .foregroundStyle(primary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    /// "$2.1K · 2 moves" — the count appears only where it explains why one
    /// slab stands for more than one thing.
    private func valueText(_ lane: WalletFlow.Lane) -> String {
        let money = WalletValue.money(lane.usd)
        guard lane.count > 1 else { return money }
        return "\(money) · \(lane.count) moves"
    }
}

// MARK: - The band that is not there

/// The Activity slot when the band declines (2026-09-03, prd §589) — the
/// vibenet room's grammar for a declining figure, in the shape THIS scope would
/// have drawn: the face the ribbons would converge on, the gate's outline with
/// nothing running through it, and ONE sentence naming which of the four
/// causes.
///
/// It exists because the reported symptom — *"the activity chart isn't
/// showing. for me or vitalik"* — was a fixed slot of air over a stream full of
/// moves, and from the screen a quiet window, an unpriced one and a broken
/// price read are the same nothing. `WalletFlow.Decline` is the one ladder;
/// this only words it (§83: an honest answer is drawn, never left as air).
struct WalletFlowEmptyFigure: View {
    let decline: WalletFlow.Decline
    let windowLabel: String
    let spineAddress: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The same first line the band wears, at the same rung, so the
            // slot's first pixel lands where it does when the band draws.
            Text(windowLabel)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                .padding(.top, DS.Space.s3)
            HStack(spacing: DS.Space.s3) {
                if let spineAddress {
                    WalletFace(address: spineAddress, size: DS.Face.rowCircle, circular: true)
                }
                // Dashed and EMPTY rather than absent, and in no side's colour:
                // a green ribbon here would draw money that never arrived.
                Capsule(style: .continuous)
                    .strokeBorder(DS.fillLine,
                                  style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    .frame(height: 22)
                    .opacity(0.6)
            }
            Text(line)
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, WalletCardStyle.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// One sentence per cause. Counts go through `String(_:)` — a `\(n)` in a
    /// localized string groups the integer ("2,019"), the §375 lesson.
    private var line: String {
        switch decline {
        case .noLegs(let predating):
            return predating == 0
                ? String(localized: "Nothing has moved in or out yet.")
                : String(localized: "Nothing has moved since prices were kept — \(String(predating)) older moves can't be drawn.")
        case .nothingPriced(let total):
            return total == 1
                ? String(localized: "1 move arrived without a price, so there's no scale to draw.")
                : String(localized: "\(String(total)) moves arrived without a price, so there's no scale to draw.")
        case .belowFloor(let priced, let total):
            return String(localized: "Only \(String(priced)) of \(String(total)) moves carry a price — too few to draw the window honestly.")
        case .oneLane:
            return String(localized: "Everything moved with one address so far — the band needs two to compare.")
        }
    }
}
