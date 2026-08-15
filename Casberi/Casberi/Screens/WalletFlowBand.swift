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
/// app's one green moment (`SourceMoments` rains for it). Painting outflow red
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

    private let bandHeight: CGFloat = 138
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
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                WalletSectionLabel(title: String(localized: "Where it moved"))
                Text(pickedLine ?? summary)
                    .dsText(.label12)
                    .foregroundStyle(picked == nil ? DS.textTertiary : DS.textPrimary)
                    .lineLimit(1)
                netLine
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 3)
                    .animation(netAnimation, value: entered)
                if let note = coverageNote {
                    // Stated, never swallowed — a band drawn from six of nine
                    // moves is a different claim from one drawn from all nine.
                    Text(note)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, DS.Space.s3)
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
        }
        // A plain set: each element owns its own delayed animation above.
        .onAppear { entered = true }
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    private var summary: String {
        "\(windowLabel) · in \(WalletValue.money(band.inUSD)) · out \(WalletValue.money(band.outUSD))"
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

    private func diagram(width: CGFloat) -> some View {
        let slabWidth = width * 0.36
        let spineX = width / 2 - spineWidth / 2
        let inSegs = segments(band.inLanes, sideTotal: band.inUSD)
        let outSegs = segments(band.outLanes, sideTotal: band.outUSD)

        return ZStack(alignment: .topLeading) {
            // Connectors first — straight tapers, square shoulders.
            ForEach(inSegs.indices, id: \.self) { i in
                connector(fromX: slabWidth, fromTop: inSegs[i].slabTop,
                          toX: spineX, toTop: inSegs[i].spineTop,
                          height: inSegs[i].height)
                    .fill(DS.confirm.opacity(0.22))
            }
            ForEach(outSegs.indices, id: \.self) { i in
                connector(fromX: spineX + spineWidth, fromTop: outSegs[i].spineTop,
                          toX: width - slabWidth, toTop: outSegs[i].slabTop,
                          height: outSegs[i].height)
                    .fill(DS.textPrimary.opacity(0.10))
            }

            // The slabs — SOLID, square, running into the card's edges.
            ForEach(inSegs.indices, id: \.self) { i in
                slab(inSegs[i], width: slabWidth, incoming: true)
                    .offset(y: inSegs[i].slabTop)
            }
            ForEach(outSegs.indices, id: \.self) { i in
                slab(outSegs[i], width: slabWidth, incoming: false)
                    .offset(x: width - slabWidth, y: outSegs[i].slabTop)
            }

            // The spine — you.
            RoundedRectangle(cornerRadius: spineWidth / 2, style: .continuous)
                .fill(spineTint.opacity(0.65))
                .frame(width: spineWidth, height: bandHeight - 4)
                .offset(x: spineX, y: 2)
            if let spineAddress {
                WalletFace(address: spineAddress, size: DS.Face.row, circular: true)
                    .overlay(Circle().stroke(DS.page, lineWidth: 3))
                    .scaleEffect(entered ? 1 : 0.4)
                    .animation(faceAnimation, value: entered)
                    .position(x: width / 2, y: bandHeight * 0.42)
            }
        }
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
