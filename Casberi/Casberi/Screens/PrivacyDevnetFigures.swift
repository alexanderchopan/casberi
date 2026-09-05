import SwiftUI

// The Ethrex Privacy room's drawings (prd §593b).
//
// `PrivacyDevnetFigure` is the Foundation-only half and holds every number;
// nothing here computes a position, a width or a cap. That split is what lets
// `privacy-selftest.sh` prove the arithmetic, since no harness, simulator or
// build on this host can make a proof age out or a frame halt.
//
// **ONE VOCABULARY, FOUR SHAPES, LEARNED ONCE.** A BAR is a frame, a DISC is a
// one-time spend key, a DIAMOND is a snapshot, an OUTLINED PILL is somebody
// else paying. Every scope that draws a transaction draws the same four, which
// is `HegotaModeStyle`'s reasoning carried onto shape instead of hue — and it
// has to be shape here, because this room spends no colour on state.

// MARK: - The chain's memory, as a ring (prd §598)

/// The 8,192-slot window, drawn as the ring it is.
///
/// **THE PREDEPLOY MASKS A SLOT WITH `0x1fff`** — the window is a ring buffer
/// in the chain's own bytecode (`PrivacyDevnetRoots.ringIndex`), and the room
/// drew it as a straight bar with a caption at each end saying which way time
/// ran. Two captions, in fact: one under Home's track and one under every lane
/// in the Roots scope, saying the same eight words. **An arc needs neither.
/// The gap at the bottom IS the exit**, so a snapshot that leaves the window
/// falls into it, and the shape carries what the caption was carrying.
///
/// **NOW at the top, age clockwise** — the direction a clock face already
/// teaches, so nothing has to be learned to read it.
///
/// **The ring is ALIVE.** Marks drift between sweeps
/// (`PrivacyDevnetFigure.drifted`), because the head slot is read once every
/// two minutes and the window drains continuously — a ring that only moves
/// when a sweep lands is a clock that ticks twice an hour. The drift is an
/// ESTIMATE and is clamped so it can never carry a mark to the rim: only a
/// real read may say a snapshot has aged out, which is the one state on this
/// ring that changes what a row says.
///
/// **No colour carries state**, inherited whole. A hollow mark in the gap is a
/// snapshot the chain has forgotten; it is not red, because the proof was
/// valid when it landed and its transaction is settled.
struct PrivacyDevnetRing: View {
    let marks: [PrivacyDevnetFigure.Mark]
    /// How many distinct sets are on this ring. One set wears no ordinals —
    /// a number implies a second (`PrivacyDevnetRoots.setLabel`'s rule).
    var sets: Int = 1
    /// The freshest live reference's remaining slots, for the ring's own
    /// reading. Nil draws no reading rather than a zero.
    var remaining: UInt64?
    /// When the chain was last actually read. The drift runs from here and
    /// freezes at `PrivacyDevnetFigure.driftCap`; nil means no drift at all,
    /// which is what a fixture and a preview get.
    var readAt: Date?
    var diameter: CGFloat = 132
    let reduceMotion: Bool

    /// The rim's own weight — the same 4pt bed every track in this room used,
    /// bent into a circle, so the ring is recognisably the same object.
    // **5, not 4 — measured on a device.** The straight track this replaced
    // was 4pt across the full card width and read clearly; bent into a circle
    // the same weight all but disappeared on a dark ground, so the ring's own
    // shape was the thing hardest to see on the card it leads.
    private static let rim: CGFloat = 5
    private static let markSize: CGFloat = 11

    var body: some View {
        // **A CLOCK, so it is drawn on one.** The schedule is the ring's
        // drain rate rather than a second: at 12s a slot a mark crosses a
        // pixel every few seconds, so a faster tick spends battery to redraw
        // an identical frame.
        TimelineView(.periodic(from: .now, by: reduceMotion ? 600 : 6)) { context in
            ring(now: context.date)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "The chain's memory")))
        .accessibilityValue(Text(Self.spoken(marks)))
    }

    @ViewBuilder private func ring(now: Date) -> some View {
        let placed = PrivacyDevnetFigure.ringPlacements(drifted(now: now))
        ZStack {
            // **THE TRACK IS THICK AND THE WINDOW IS FILLED (prd §606).**
            //
            // Reported, on the first device look: the ring "just looks like a
            // toy". It was a 5pt outline with saturated rotated squares
            // scattered on it, each stamped with a numeral — badge vocabulary
            // on an empty circle. Nothing was FILLED, so it held no quantity:
            // a gauge shows an amount by how much of it is covered, and this
            // showed position alone.
            //
            // Now the arc carries the freshest proof's remaining life as a
            // fill, so the ring reads as the depleting resource it describes,
            // and the marks are TICKS THAT CUT THE TRACK rather than objects
            // floating near it — a measurement on the instrument.
            RingArc(sweep: PrivacyDevnetFigure.ringSweep)
                .stroke(DS.fillFaint, style: StrokeStyle(lineWidth: Self.rim, lineCap: .round))

            if let filled = fillSweep {
                RingArc(sweep: filled)
                    .stroke(DS.tint, style: StrokeStyle(lineWidth: Self.rim, lineCap: .round))
            }

            // NOW. In ink rather than tint: it is the axis, not a reading, and
            // tinting it would make the present look like another snapshot.
            tick(at: 0, length: Self.rim + 8, colour: DS.textPrimary.opacity(0.75), width: 2.5)

            reading

            ForEach(Array(placed.enumerated()), id: \.element.id) { index, p in
                proofTick(p, index: index)
            }
        }
        // The ring fills the way it drains.
        .chartWipe(reduceMotion: reduceMotion)
    }

    /// Every mark moved to where the estimate says it is now.
    ///
    /// The arithmetic is `PrivacyDevnetFigure.drifted`'s, including the clamp
    /// that keeps an estimate off the rim — nothing here decides anything, so
    /// the harness can prove the one rule that matters.
    private func drifted(now: Date) -> [PrivacyDevnetFigure.Mark] {
        guard let readAt else { return marks }
        let elapsed = now.timeIntervalSince(readAt)
        guard elapsed > 0 else { return marks }
        return marks.map { mark in
            guard let position = mark.position else { return mark }
            var moved = mark
            moved.position = PrivacyDevnetFigure.drifted(position: position,
                                                         secondsSinceRead: elapsed)
            return moved
        }
    }

    /// What the ring says in its middle — the freshest snapshot's remaining
    /// life, in words somebody can feel, with the measured slot count under it.
    ///
    /// **The hedge and the measurement travel together** (§598): "about"
    /// carries the assumption, the slot count carries what was observed, so
    /// nothing measured is replaced by anything assumed.
    @ViewBuilder private var reading: some View {
        if let remaining {
            // **ONE LINE, AND IT MUST NOT COMPETE WITH THE HEADLINE.** Seen
            // on a device, "about 14 hours" wrapped to two lines inside a 128pt
            // ring and read as a second headline under the first. It is the
            // ring's caption, not its lede: one line, scaled down before it
            // wraps, over a slot the sentence above already owns.
            VStack(spacing: 2) {
                Text(PrivacyDevnetRoots.approximate(slots: remaining))
                    .dsText(.stat24)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(String(localized: "\(String(remaining)) of \(String(PrivacyDevnetRoots.windowSlots)) slots"))
                    .dsText(.label12)
                    .monospacedDigit()
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: diameter - 40)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func tick(at angle: Double, length: CGFloat,
                                   colour: Color, width: CGFloat) -> some View {
        Capsule()
            .fill(colour)
            .frame(width: width, height: length)
            .offset(y: -(diameter - Self.rim) / 2)
            .rotationEffect(.degrees(angle))
    }

    /// How much of the arc is filled — the freshest live proof's remaining
    /// share of the window.
    ///
    /// **The freshest, because it is the one with time left to care about**
    /// (`PrivacyDevnetRoom.head`'s own ranking, so the fill and the sentence
    /// above can never describe two different snapshots). Nil when nothing is
    /// live: an empty track and a track with nothing to measure are different
    /// claims, and only the second is true then.
    private var fillSweep: Double? {
        guard let remaining else { return nil }
        let share = min(1, Double(remaining) / Double(PrivacyDevnetRoots.windowSlots))
        guard share > 0 else { return nil }
        return PrivacyDevnetFigure.ringSweep * share
    }

    /// One snapshot, as a tick across the track.
    ///
    /// **A tick that CUTS the track is a measurement on it; a gem sitting
    /// beside it is an ornament** (prd §606). It runs the rim's full width
    /// plus a little either side so it reads over both the filled and the
    /// empty part, in ink rather than tint — the fill is the quantity, the
    /// ticks are the readings on it, and tinting both would merge them.
    ///
    /// An aged proof is a DASHED tick in the exit gap: out of the window,
    /// visibly a thing rather than an absence, and dashed rather than red
    /// because a proof whose snapshot has left was valid when it landed.
    ///
    /// **The offset-then-rotate idiom**: `.offset` is a render-time transform
    /// that leaves the layout frame at the ring's centre, so the following
    /// `.rotationEffect` swings the tick around that centre. The inner
    /// counter-rotation exists only to keep a set ordinal upright.
    @ViewBuilder private func proofTick(_ p: PrivacyDevnetFigure.Placement,
                                        index: Int) -> some View {
        let aged = p.mark.position == nil
        ZStack {
            Capsule()
                .fill(aged ? Color.clear : DS.textPrimary.opacity(0.92))
                .overlay {
                    if aged {
                        Capsule().strokeBorder(DS.tint.opacity(0.55), lineWidth: 1.5)
                    }
                }
                .frame(width: 2.5, height: Self.rim + 6)
                .offset(y: -(diameter - Self.rim) / 2)
                .rotationEffect(.degrees(p.angle))

            // **THE ORDINAL SITS INSIDE THE RIM, in the quietest ink.** It was
            // stamped INSIDE the mark in `DS.page`, which is what made the
            // marks read as numbered badges; then it sat OUTSIDE, and at the
            // bottom of the ring it was clipped by the figure's own frame —
            // seen on a device. Inward cannot clip, because the ring's own
            // radius bounds it. Absent entirely when there is one set, since
            // an ordinal implies a second.
            if sets > 1 {
                // **PLACED WITH TRIG, NOT WITH A COUNTER-ROTATION.** Rotating
                // the label into place and then rotating it back needs a pivot
                // expressed in the label's own unit space, which is a ratio of
                // two things neither of which the view knows — and on a device
                // every numeral landed at the wrong angle from its tick. The
                // position is one sine and one cosine; it is upright by
                // construction because nothing rotates it at all.
                let point = Self.labelOffset(p.angle, diameter: diameter)
                Text(String(p.mark.set + 1))
                    .dsText(.label12)
                    .monospacedDigit()
                    .foregroundStyle(DS.textTertiary)
                    .offset(x: point.x, y: point.y)
            }
        }
        .chartArrival(index: index, reduceMotion: reduceMotion)
        // **THE MOVE IS ANIMATED, so a snapshot visibly leaves.** A mark that
        // ages out between reads travels to the gap and hollows rather than
        // teleporting there.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: p.angle)
    }

    /// Where a set's numeral sits: inside the rim, on the same radius as its
    /// tick, at the same angle. **Clockwise from the top**, which is the
    /// ring's own sense — so `x` is a sine and `y` is a NEGATIVE cosine,
    /// because the screen's y grows downward and the top of the ring is where
    /// the angle starts.
    static func labelOffset(_ angle: Double, diameter: CGFloat) -> CGPoint {
        let r = (diameter - rim) / 2 - 15
        let radians = angle * .pi / 180
        return CGPoint(x: CGFloat(sin(radians)) * r,
                       y: -CGFloat(cos(radians)) * r)
    }

    static func spoken(_ marks: [PrivacyDevnetFigure.Mark]) -> String {
        let live = marks.filter { $0.position != nil }.reduce(0) { $0 + $1.count }
        let gone = marks.filter { $0.position == nil }.reduce(0) { $0 + $1.count }
        if gone == 0 {
            return String(localized: "\(String(live)) snapshots still in the chain's memory")
        }
        return String(localized: "\(String(live)) snapshots still in the chain's memory, \(String(gone)) gone")
    }
}

/// The rim: an open arc with its gap at the bottom.
///
/// A `Shape` rather than a rotated `Circle().trim`, so the gap's position is
/// stated once and the ticks and marks can be placed against the same zero.
struct RingArc: Shape {
    /// Degrees of arc drawn, clockwise from the top.
    let sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = (min(rect.width, rect.height)) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + sweep),
                    clockwise: false)
        return path
    }
}

// MARK: - What a transaction is made of

/// One transaction's anatomy: its frames, then what it proved, then who paid.
///
/// Drawn at row scale in every scope that lists transactions, so the shapes are
/// met once and read everywhere. It carries no words — the row beside it does
/// — because at 14pt a label is longer than the drawing it names.
struct PrivacyDevnetAnatomy: View {
    let items: [PrivacyDevnetFigure.Item]
    /// How wide the frame strip may run. The keys, roots and pill take their
    /// own intrinsic width after it.
    var stripWidth: CGFloat = 92
    /// The bar's height — 8 at row scale, larger where the anatomy IS the
    /// figure (prd §596: the Frames-scope strips were 8pt marks centred in a
    /// 300pt slot, the "tiny and top justified" defect §588 fixed on Frames).
    /// Every other shape derives from it so the strip scales as one drawing.
    var barHeight: CGFloat = 8
    /// How much of the whole budget the transaction actually spent, 0…1
    /// (`PrivacyDevnetFigure.usedShare`). Nil draws NOTHING — this room could
    /// say what every transaction was ALLOWED and never what any of them cost,
    /// and the honest fix is a second reading, not a re-labelled first one
    /// (prd §602).
    var usedShare: Double? = nil
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    shape(item, index: index)
                }
            }
            used
        }
        .frame(minHeight: barHeight + 6, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(items)))
        .accessibilityValue(Text(Self.spokenUsed(usedShare) ?? ""))
    }

    /// **THE SPEND, ON THE BUDGET'S OWN AXIS.** The strip's full width IS the
    /// transaction's whole allowance — that is what `shares` divides — so a
    /// track beneath it filled to `usedShare` is measured against exactly the
    /// thing above it rather than against a scale of its own.
    ///
    /// **Under the bars, never inside them.** A fill drawn behind the frame
    /// segments would read as a per-frame breakdown, which this chain does not
    /// serve (§593a) and which nothing here may imply. Two objects, one axis,
    /// one meaning each.
    ///
    /// Thin and quiet: it is the second reading on the row, not a rival to the
    /// anatomy it sits under.
    @ViewBuilder private var used: some View {
        if let usedShare {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule()
                        .fill(DS.tint.opacity(0.45))
                        .frame(width: max(2, geo.size.width * CGFloat(usedShare)))
                }
            }
            .frame(width: stripWidth, height: 3)
        }
    }

    static func spokenUsed(_ share: Double?) -> String? {
        guard let share else { return nil }
        return String(localized: "\(String(Int((share * 100).rounded())))% of its gas budget spent")
    }

    @ViewBuilder
    private func shape(_ item: PrivacyDevnetFigure.Item, index: Int) -> some View {
        switch item {
        case .frame(let share, let failed):
            // **FAILURE IS AN OUTLINE, NEVER A FILL.** A frame that halted is
            // rare by construction, so drawn as a second fill it is one colour
            // among many and disappears; drawn as the only unfilled bar in the
            // strip it is the exception the eye finds first. Same reasoning as
            // `HegotaFrameStrip`, and the same restraint: `succeeded == nil`
            // is an unread status and is never drawn as a failure.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(failed ? Color.clear : DS.tint)
                .overlay {
                    if failed {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(DS.destructive, lineWidth: 2)
                    }
                }
                .frame(width: max(4, stripWidth * share - 3), height: barHeight)
                .chartArrival(index: index, reduceMotion: reduceMotion)
        case .key:
            PrivacyDevnetSpentKey(size: barHeight + 1)
                .padding(.leading, index == 0 ? 0 : 3)
                .chartArrival(index: index, reduceMotion: reduceMotion)
        case .root:
            Rectangle()
                .fill(DS.tint)
                .frame(width: barHeight, height: barHeight)
                .rotationEffect(.degrees(45))
                .padding(.leading, 3)
                .chartArrival(index: index, reduceMotion: reduceMotion)
        case .sponsor:
            Text(String(localized: "paid for"))
                .dsText(.subhead13)
                .foregroundStyle(DS.tint)
                .padding(.horizontal, 6)
                .overlay(Capsule().strokeBorder(DS.tint, lineWidth: 1.5))
                .padding(.leading, 3)
                .chartArrival(index: index, reduceMotion: reduceMotion)
        }
    }

    static func spoken(_ items: [PrivacyDevnetFigure.Item]) -> String {
        var frames = 0, keys = 0, roots = 0, sponsored = false
        for item in items {
            switch item {
            case .frame: frames += 1
            case .key: keys += 1
            case .root: roots += 1
            case .sponsor: sponsored = true
            }
        }
        var parts = [frames == 1 ? String(localized: "1 frame")
                                 : String(localized: "\(String(frames)) frames")]
        if keys > 0 {
            parts.append(keys == 1 ? String(localized: "1 spend key")
                                   : String(localized: "\(String(keys)) spend keys"))
        }
        if roots > 0 {
            parts.append(roots == 1 ? String(localized: "1 snapshot")
                                    : String(localized: "\(String(roots)) snapshots"))
        }
        if sponsored { parts.append(String(localized: "somebody else paid")) }
        return parts.joined(separator: ", ")
    }
}

/// A key that has been used once and can never be used again.
///
/// A ring with a hole, not a filled disc: the hole IS the reading — the key is
/// spent. Every nullifier this chain has ever shown us carries `nonceSeq` 0 and
/// is spent exactly once (§593), so there is no unspent state to draw and the
/// shape can afford to mean one thing.
struct PrivacyDevnetSpentKey: View {
    var size: CGFloat = 14

    // **THE SEAL IS GONE WITH THE GRID IT LIVED ON (prd §606).**
    //
    // §598 gave this ring a first-sight animation: a key this device had never
    // seen closed itself once, because the hole IS the claim. It fired in the
    // Spend keys scope's grid — and that grid was eight identical rings
    // standing in for the number eight, which §606 deleted. An animation
    // attached to a figure that should not exist does not survive the figure;
    // moving it onto the sheet's key rows would put a 0.55s draw on a list
    // item, which is the fidget the motion law bans.
    //
    // `PrivacyDevnetMoments`' seen-ledger goes with it. What remains here is
    // the shape, in the anatomy strip and the legend, where it means what it
    // always meant: used once, never again.
    var body: some View {
        Circle()
            .strokeBorder(DS.tint, lineWidth: max(2, size * 0.28))
            .frame(width: size, height: size)
            // The fact is stated beside it every time — the sheet row carries
            // the key's own hex and "used once" — so the shape is decoration
            // to VoiceOver and announcing it would read the same fact twice.
            .accessibilityHidden(true)
    }
}

/// The four shapes, named once at the bottom of a scope that draws them.
///
/// **Present whenever more than one shape can appear**, which is the dataviz
/// rule that identity must never be carried by appearance alone — here shape
/// rather than colour, but the obligation is the same.
struct PrivacyDevnetLegend: View {
    var showsSponsor = false

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            item { RoundedRectangle(cornerRadius: 2).fill(DS.tint)
                    .frame(width: 14, height: 6) } label: {
                String(localized: "frame")
            }
            item { PrivacyDevnetSpentKey(size: 9) } label: {
                String(localized: "spend key")
            }
            item { Rectangle().fill(DS.tint).frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45)) } label: {
                String(localized: "snapshot")
            }
            if showsSponsor {
                item { Capsule().strokeBorder(DS.tint, lineWidth: 1.5)
                        .frame(width: 14, height: 8) } label: {
                    String(localized: "somebody else paid")
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func item<M: View>(@ViewBuilder mark: () -> M,
                               label: () -> String) -> some View {
        HStack(spacing: 5) {
            mark()
            Text(label())
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
        }
    }
}


// **TWO FIGURES DELETED HERE (prd §606).**
//
// `PrivacyDevnetTally` drew three pip columns per address and
// `PrivacyDevnetActivityChart` a column per transaction whose height was the
// frame count. Both drew a COUNT as N identical shapes over data with nothing
// to compare — every transaction on this chain runs two frames, so the
// Activity chart's one axis was constant, and an address's pips are the number
// the chassis headline already states. Reported as "wtf does it even mean" and
// "we can count, what does that do".
//
// What replaced them is above: `PrivacyDevnetKindMix` answers what these
// transactions ARE, and `PrivacyDevnetBudgetBar` what their steps were allowed
// and what they cost. The Accounts and Spend keys scopes draw NO figure at
// all — their headline is the number and their rows are the detail, which is
// strictly more than the shapes were saying.

// MARK: - The overflow line

/// What a capped list left out.
///
/// **Never silent.** A list cut at the slot's edge and a complete one look
/// identical, which is this repo's oldest recurring defect (§307's truncated
/// imports, §309's four import rooms); a room whose counts are already a FLOOR
/// by construction — the walk cannot see a transaction that emitted no log —
/// can least afford a second, invisible cut on top of it.
struct PrivacyDevnetMore: View {
    let count: Int
    var noun: String = String(localized: "more")

    var body: some View {
        if count > 0 {
            Text(String(localized: "and \(String(count)) \(noun)"))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
        }
    }
}

// MARK: - What this room's transactions are (prd §606)

/// The kind mix, as one labelled bar.
///
/// **THIS REPLACES A COLUMN PER TRANSACTION whose height was the frame count**
/// — and nearly every transaction on this chain runs exactly two frames, so
/// that height axis was constant and the figure was a row of identical bars at
/// nudged positions. Reported as "wtf does it even mean".
///
/// What varies is what a transaction is FOR, and the answer to "what does this
/// address do on this chain" is a proportion, not a scatter. One bar, segments
/// in the room's own words, counts stated rather than inferred from width.
///
/// **ONE KIND DRAWS NO BAR.** A single full-width segment is a sentence with a
/// rectangle behind it saying 100%, and on a young room every transaction is
/// the same kind — so the words stand alone and the figure declines. That is
/// the rule the whole §606 pass turns on: a scope with nothing to compare
/// states its number instead of drawing one.
struct PrivacyDevnetKindMix: View {
    let mix: [(kind: PrivacyDevnetFigure.Kind, count: Int)]
    let reduceMotion: Bool

    private var total: Int { mix.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if mix.count > 1, total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(mix.enumerated()), id: \.offset) { index, part in
                            Capsule()
                                .fill(DS.tint.opacity(Self.weight(index)))
                                .frame(width: max(6, (geo.size.width - CGFloat(mix.count - 1) * 2)
                                                  * CGFloat(part.count) / CGFloat(total)))
                                .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                }
                .frame(height: 22)
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(mix.enumerated()), id: \.offset) { index, part in
                    HStack(spacing: DS.Space.s2) {
                        Capsule()
                            .fill(DS.tint.opacity(Self.weight(index)))
                            .frame(width: 14, height: 8)
                        Text(Self.words(part.kind, count: part.count))
                            .dsText(.callout15)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        // **CENTRED, not pinned to the top.** A short figure with a trailing
        // `Spacer` leaves every leftover point in one block underneath it,
        // which is the dead-air shape §602 fixed for the ring and this
        // repeated the day it was written.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "What these transactions were")))
    }

    /// **ONE HUE, THREE WEIGHTS — never three colours.** This room spends no
    /// colour on state (§593b), and three saturated fills would read as three
    /// unrelated things rather than three parts of one total. The order is the
    /// mix's own, so the biggest share is always the strongest.
    static func weight(_ index: Int) -> Double {
        switch index {
        case 0:  return 1
        case 1:  return 0.55
        default: return 0.3
        }
    }

    static func words(_ kind: PrivacyDevnetFigure.Kind, count: Int) -> String {
        switch kind {
        case .poolSpend:
            return count == 1 ? String(localized: "1 pool spend")
                              : String(localized: "\(String(count)) pool spends")
        case .framed:
            return count == 1 ? String(localized: "1 framed call")
                              : String(localized: "\(String(count)) framed calls")
        case .transfer:
            return count == 1 ? String(localized: "1 plain transfer")
                              : String(localized: "\(String(count)) plain transfers")
        }
    }
}

// MARK: - What the room asked the chain for (prd §606)

/// The two budgets a frame transaction carries, summed across the room.
///
/// **THIS REPLACES SIX IDENTICAL STRIPS.** The Frames scope drew one anatomy
/// per transaction weighted by execution budget, and most frames here carry the
/// same 320,000 — so it was six identical bar-pairs under a headline reading
/// "12 steps", which is the "who cares, what does that even tell anyone" the
/// pass was reported for.
///
/// The reading that is NOT already in the headline is the split. EIP-8141 gives
/// a frame two allowances: what it may compute, and what it may GROW. On this
/// chain state is the one that varies — most frames ask for none, a pool
/// spend's second frame asks for 550,000 — so the proportion between them is
/// what these transactions actually are.
///
/// **The spend rides on top where every receipt was read**, as a fill inside
/// the execution segment on that segment's own axis, so the figure says both
/// what was asked for and what it cost.
struct PrivacyDevnetBudgetBar: View {
    let budgets: PrivacyDevnetFigure.Budgets
    let reduceMotion: Bool

    private var execution: Double { Double(budgets.execution ?? 0) }
    private var state: Double { Double(budgets.state ?? 0) }
    private var total: Double { execution + state }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    if execution > 0 {
                        ZStack(alignment: .leading) {
                            // **THE TRACK IS ONLY DIM WHEN SOMETHING FILLS
                            // IT.** Drawn at 0.35 unconditionally, the LARGER
                            // share read weaker than the smaller one beside
                            // it — seen on a device, 4.9M of compute looking
                            // fainter than 1.5M of state. Dim means "awaiting
                            // a fill"; with no receipt read there is no fill
                            // coming, so it carries its own weight.
                            Capsule().fill(DS.tint.opacity(budgets.used == nil ? 0.9 : 0.3))
                            if let used = budgets.used, execution > 0 {
                                // What the chain actually charged, on the
                                // execution segment's own axis. Clamped: the
                                // receipt covers the whole transaction while
                                // this sums the frames, so an intrinsic cost
                                // outside any frame can exceed it.
                                Capsule()
                                    .fill(DS.tint)
                                    .frame(width: segment(geo, execution)
                                           * CGFloat(min(1, Double(used) / execution)))
                            }
                        }
                        .frame(width: segment(geo, execution))
                        .chartArrival(index: 0, reduceMotion: reduceMotion)
                    }
                    if state > 0 {
                        Capsule()
                            .fill(DS.tint.opacity(0.5))
                            .frame(width: segment(geo, state))
                            .chartArrival(index: 1, reduceMotion: reduceMotion)
                    }
                }
            }
            .frame(height: 26)

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let gas = budgets.execution, gas > 0 {
                    row(fill: budgets.used == nil ? 0.9 : 0.3,
                        text: usedLine ?? String(localized: "\(PrivacyDevnetFigures.grouped(gas)) to compute"))
                }
                if let growth = budgets.state, growth > 0 {
                    row(fill: 0.5, text: String(localized: "\(PrivacyDevnetFigures.grouped(growth)) to grow state"))
                } else if budgets.state == 0 {
                    // **A ZERO IS A READING** — these steps asked to grow no
                    // state, which is a fact about them, not a gap in the read.
                    Text(String(localized: "None of these steps asked to grow state"))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "What these steps were allowed")))
    }

    private var usedLine: String? {
        guard let gas = budgets.execution, gas > 0, let used = budgets.used else { return nil }
        return String(localized: "\(PrivacyDevnetFigures.grouped(used)) of \(PrivacyDevnetFigures.grouped(gas)) computed")
    }

    private func segment(_ geo: GeometryProxy, _ value: Double) -> CGFloat {
        guard total > 0 else { return 0 }
        let gaps: CGFloat = (execution > 0 && state > 0) ? 3 : 0
        return max(8, (geo.size.width - gaps) * CGFloat(value / total))
    }

    @ViewBuilder private func row(fill: Double, text: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            Capsule().fill(DS.tint.opacity(fill)).frame(width: 14, height: 8)
            Text(text)
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }
}

/// One spelling of a count somebody reads, shared by this room's figures.
enum PrivacyDevnetFigures {
    static func grouped(_ value: UInt64) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
