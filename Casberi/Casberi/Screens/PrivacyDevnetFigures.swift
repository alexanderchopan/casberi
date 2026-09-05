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
            RingArc(sweep: PrivacyDevnetFigure.ringSweep)
                .stroke(DS.fillFaint, style: StrokeStyle(lineWidth: Self.rim, lineCap: .round))

            // Quarter ticks, so the ring has a scale without an axis — the
            // same faint fill as the rim, never a hairline (the design law's
            // no-lines ban) and never labelled.
            ForEach([0.25, 0.5, 0.75], id: \.self) { q in
                tick(at: PrivacyDevnetFigure.ringSweep * q, length: 7,
                     colour: DS.fillFaint, width: 2)
            }

            // NOW. In ink rather than tint: it is the axis, not a reading, and
            // tinting it would make the present look like another snapshot.
            tick(at: 0, length: 13, colour: DS.textPrimary.opacity(0.55), width: 2.5)

            reading

            ForEach(Array(placed.enumerated()), id: \.element.id) { index, p in
                diamond(p, index: index)
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
            VStack(spacing: 1) {
                Text(PrivacyDevnetRoots.approximate(slots: remaining))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(localized: "\(String(remaining)) slots left"))
                    .dsText(.label12)
                    .monospacedDigit()
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: diameter - 34)
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

    /// One snapshot on the rim.
    ///
    /// **The offset-then-rotate idiom, and the counter-rotation is not
    /// decoration.** `.offset` is a render-time transform that leaves the
    /// layout frame at the ring's centre, so the following `.rotationEffect`
    /// swings the mark around that centre — which is what places it on the
    /// arc. It also spins the mark's own content, so a set ordinal at 200°
    /// would be printed upside down; the inner counter-rotation cancels
    /// exactly that and nothing else.
    @ViewBuilder private func diamond(_ p: PrivacyDevnetFigure.Placement,
                                      index: Int) -> some View {
        let aged = p.mark.position == nil
        ZStack {
            Rectangle()
                .fill(aged ? Color.clear : DS.tint)
                .overlay {
                    if aged {
                        Rectangle().strokeBorder(DS.tint.opacity(0.45), lineWidth: 2)
                    }
                }
                .frame(width: Self.markSize, height: Self.markSize)
                .rotationEffect(.degrees(45))
            // **THE ORDINAL, NOT THE BYTES** (§598). A 32-byte source id names
            // nothing a reader can hold across a figure, a row and a sheet; a
            // small number does, and it is the same number the list below
            // wears. Absent entirely when there is one set, because an ordinal
            // implies a second.
            if sets > 1 {
                Text(String(p.mark.set + 1))
                    .dsText(.label12)
                    .monospacedDigit()
                    .foregroundStyle(aged ? DS.tint.opacity(0.8) : DS.page)
            }
        }
        .rotationEffect(.degrees(-p.angle))
        .offset(y: -(diameter - Self.rim) / 2)
        .rotationEffect(.degrees(p.angle))
        .chartArrival(index: index, reduceMotion: reduceMotion)
        // **THE MOVE IS ANIMATED, so a snapshot visibly leaves.** A mark that
        // ages out between reads travels to the gap and hollows rather than
        // teleporting there — the one place this room has to show a thing
        // ending, and the reason the drift is worth drawing at all.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: p.angle)
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
    /// **SEAL IT, ONCE, THE FIRST TIME THIS DEVICE SEES IT (prd §598).**
    ///
    /// The ring's hole IS its claim — used once, never again — and the room
    /// drew that claim already finished, every time, for keys it had shown a
    /// hundred times and keys that landed a second ago alike. A key this
    /// device has never seen before closes: the stroke sweeps round and the
    /// ring is sealed, which is the one animation in this room that says what
    /// the shape means rather than decorating it.
    ///
    /// Off by default, so a grid of forty known keys is still forty static
    /// rings; `PrivacyDevnetMoments.unseen` is what turns it on, and it
    /// deliberately seeds silently on an install's first read — otherwise
    /// somebody's first open seals forty rings at once, which is a room
    /// celebrating its own contents.
    var seals = false
    var reduceMotion = false

    @State private var closed = false

    private var drawn: Bool { closed || !seals || reduceMotion }

    var body: some View {
        Circle()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(DS.tint, style: StrokeStyle(lineWidth: max(2, size * 0.28),
                                                lineCap: .round))
            // Inset by half the stroke so a trimmed stroke sits exactly where
            // `strokeBorder` used to — otherwise every key in the app grows by
            // its own line width the day this gained an animation.
            .padding(max(1, size * 0.14))
            .frame(width: size, height: size)
            // Starts at 12 o'clock and closes clockwise, which is the ring
            // above's own direction — one room, one sense of rotation.
            .rotationEffect(.degrees(-90))
            // The fact is stated beside it every time — the grid carries
            // "Spend keys used" and its count, the sheet row carries the key's
            // own hex and "used once" — so the shape is decoration to
            // VoiceOver and announcing it would read the same fact twice.
            .accessibilityHidden(true)
            .task {
                guard seals, !reduceMotion, !closed else { return }
                withAnimation(.easeInOut(duration: 0.55)) { closed = true }
            }
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


// MARK: - What an address has done

/// Three counts as pips: frames, spend keys, snapshots.
///
/// **A tally, not a weight.** The pips are countable up to
/// `PrivacyDevnetFigure.pipCap` and then say how many more, which is the whole
/// claim — no bar, no share, no comparison of one address's magnitude against
/// another's, because the only magnitude here is test ETH and it has no price.
struct PrivacyDevnetTally: View {
    let tally: PrivacyDevnetFigure.Tally
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            column(tally.frames, String(localized: "frames"), index: 0) { bar }
            column(tally.keys, String(localized: "keys"), index: 1) { disc }
            column(tally.roots, String(localized: "snapshots"), index: 2) { gem }
        }
    }

    @ViewBuilder
    private func column<M: View>(_ count: Int, _ label: String, index: Int,
                                 @ViewBuilder mark: @escaping () -> M) -> some View {
        let p = PrivacyDevnetFigure.pips(count)
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<p.filled, id: \.self) { _ in mark().opacity(1) }
                ForEach(0..<p.empty, id: \.self) { _ in mark().opacity(0.16) }
                if p.overflow > 0 {
                    Text(String(localized: "+\(String(p.overflow))"))
                        .dsText(.subhead13)
                        .monospacedDigit()
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .frame(height: 8)
            .chartArrival(index: index, reduceMotion: reduceMotion)
            Text(label)
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(String(count)) \(label)"))
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 1).fill(DS.tint).frame(width: 8, height: 6)
    }
    private var disc: some View {
        Circle().fill(DS.tint).frame(width: 6, height: 6)
    }
    private var gem: some View {
        Rectangle().fill(DS.tint).frame(width: 6, height: 6)
            .rotationEffect(.degrees(45))
    }
}

// MARK: - When, and how big (prd §596)

/// One column per transaction on the spaced block axis — the Activity scope's
/// chart, replacing a row of 9pt dots on a 3pt line.
///
/// **The column's height is its FRAME COUNT, this chain's own size measure** —
/// a two-frame pool spend and a five-frame batch are different objects and the
/// dots said only "two things happened". The ornaments above are the room's
/// standing vocabulary at chart scale: a ring when the transaction spent
/// one-time keys, a diamond when it named a snapshot — so the figure reads
/// with no legend beyond the one the scopes already teach.
///
/// **Positions come from `PrivacyDevnetFigure.spaced`** — order and span
/// exact, crowding relieved (the pool's pairs sit five blocks apart across
/// ~10,500, prd §593d) — and the block range is stated at the ends, which is
/// where the precision the nudge costs actually lives.
///
/// No colour carries state; height is the only magnitude and it is a COUNT,
/// never money.
struct PrivacyDevnetActivityChart: View {
    struct Column: Equatable {
        let block: UInt64
        let frames: Int
        let keys: Int
        let roots: Int
    }
    /// Oldest first — the axis runs left to right the way every time axis in
    /// this app does.
    let columns: [Column]
    let reduceMotion: Bool

    private static let markWidth: CGFloat = 14

    var body: some View {
        let lo = columns.map(\.block).min() ?? 0
        let hi = columns.map(\.block).max() ?? 0
        GeometryReader { geo in
            let labelRow: CGFloat = 22
            let ornaments: CGFloat = 24
            let plot = max(24, geo.size.height - labelRow - ornaments)
            let maxFrames = max(1, columns.map(\.frames).max() ?? 1)
            let xs = PrivacyDevnetFigure.spaced(columns.map(\.block),
                                                width: Double(geo.size.width),
                                                mark: Double(Self.markWidth + 4))
            ZStack(alignment: .bottomLeading) {
                // The floor the columns stand on — the same faint bed every
                // track here uses, never a hairline.
                Capsule()
                    .fill(DS.fillFaint)
                    .frame(height: 4)
                    .offset(y: -labelRow + 8)

                ForEach(Array(zip(columns.indices, xs)), id: \.0) { index, x in
                    let col = columns[index]
                    // **A TRANSFER IS A STUB, NOT A ZERO** — a plain transfer
                    // has no frames and still happened, so it draws the
                    // minimum bar rather than vanishing from its own chart.
                    let height = max(10, plot * CGFloat(col.frames) / CGFloat(maxFrames))
                    VStack(spacing: 5) {
                        HStack(spacing: 3) {
                            if col.keys > 0 { PrivacyDevnetSpentKey(size: 11) }
                            if col.roots > 0 {
                                Rectangle()
                                    .fill(DS.tint)
                                    .frame(width: 9, height: 9)
                                    .rotationEffect(.degrees(45))
                            }
                        }
                        .frame(height: 14)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(col.frames > 0 ? DS.tint : DS.textTertiary.opacity(0.45))
                            .frame(width: Self.markWidth, height: height)
                    }
                    .chartArrival(index: index, reduceMotion: reduceMotion)
                    .offset(x: CGFloat(x), y: -labelRow + 2)
                }

                // The axis's own words, at the ends. One block collapses to
                // one label — "block 69 to block 69" is a range pretending.
                HStack {
                    Text(String(localized: "block \(String(lo))"))
                    Spacer(minLength: DS.Space.s3)
                    if hi > lo {
                        Text(String(localized: "block \(String(hi))"))
                    }
                }
                .dsText(.subhead13)
                .monospacedDigit()
                .foregroundStyle(DS.textTertiary)
                .frame(maxWidth: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height,
                   alignment: .bottomLeading)
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "When these landed, and how many steps each ran"))
        .accessibilityValue(hi == lo
            ? String(localized: "All in block \(String(hi))")
            : String(localized: "Blocks \(String(lo)) to \(String(hi))"))
    }
}

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
