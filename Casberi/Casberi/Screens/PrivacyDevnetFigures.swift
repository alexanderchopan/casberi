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

// MARK: - The chain's memory

/// The 8,192-slot ring, with NOW at the right edge.
///
/// **This replaces the meter, and the difference is what it CLAIMS.** A filled
/// bar reads as a percentage of something, which invites the question "of
/// what?" and answers it with a caption; and it could only ever show the
/// freshest root, so a room with three proofs drew one and said nothing about
/// the others. The track is the thing itself: the ring, every referenced
/// snapshot at its own age, and the ones that have left it drawn hollow past
/// the edge — which is the first time an aged root has had a picture rather
/// than a sentence.
///
/// **No colour for aged.** `PrivacyDevnetRoomCard`'s own ruling, and it is
/// sharper here because the hollow mark is the one a reader might expect to be
/// red: a proof whose snapshot has left the ring was valid when it landed and
/// its transaction is settled. Hollow says "no longer in the ring"; red would
/// say "something is wrong", which is not true and cannot be acted on.
struct PrivacyDevnetTrack: View {
    let marks: [PrivacyDevnetFigure.Mark]
    /// Whether to print each labelled mark's own reading. Off in a lane stack
    /// too tall to carry them.
    var labelled = true
    let reduceMotion: Bool

    /// The bed, the mark and the label row. Two label lines are budgeted
    /// because `PrivacyDevnetFigure.labelGap` permits up to three labels and
    /// the view stacks any that would collide horizontally.
    private var height: CGFloat { labelled ? 46 : 22 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(DS.fillFaint)
                    .frame(height: 4)
                    .offset(y: 9)

                // Quarter ticks, so the ring has a scale without an axis: they
                // are the same faint fill as the bed, never a hairline (the
                // design law's no-lines ban) and never labelled, since the only
                // readings that matter are the marks' own.
                ForEach([0.25, 0.5, 0.75], id: \.self) { q in
                    Capsule()
                        .fill(DS.fillFaint)
                        .frame(width: 2, height: 10)
                        .offset(x: geo.size.width * q, y: 6)
                }

                // NOW. The one full-height mark, in ink rather than tint: it is
                // the axis, not a reading, and tinting it would make the
                // present look like another snapshot.
                Capsule()
                    .fill(DS.textPrimary.opacity(0.55))
                    .frame(width: 2, height: 18)
                    .offset(x: geo.size.width - 2, y: 2)

                ForEach(Array(marks.enumerated()), id: \.element.id) { index, mark in
                    diamond(mark, index: index, width: geo.size.width)
                }
            }
            .frame(height: height, alignment: .topLeading)
        }
        .frame(height: height)
        // The ring drains left; the wipe reveals in that direction, which is
        // §297's "a drawing reveals in the direction it means".
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "The chain's memory")))
        .accessibilityValue(Text(Self.spoken(marks)))
    }

    @ViewBuilder
    private func diamond(_ mark: PrivacyDevnetFigure.Mark,
                         index: Int, width: CGFloat) -> some View {
        // An aged mark sits just OUTSIDE the bed's leading edge, which is where
        // it really is: out of the ring. Inside would place it among the live
        // ones at an age it no longer has.
        let x = mark.position.map { width * $0 } ?? -6
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(mark.position == nil ? Color.clear : DS.tint)
                .overlay {
                    if mark.position == nil {
                        Rectangle().strokeBorder(DS.tint.opacity(0.45), lineWidth: 2)
                    }
                }
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
                .offset(y: 5)
                .chartArrival(index: index, reduceMotion: reduceMotion)
            if labelled, mark.labelled {
                Text(Self.reading(mark))
                    .dsText(.subhead13)
                    .monospacedDigit()
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize()
                    // A label on the leading half hangs right of its mark and
                    // one on the trailing half hangs left, so nothing runs off
                    // either end of the card.
                    .offset(x: (mark.position ?? 0) > 0.6 ? -62 : 10,
                            y: 4 + CGFloat(index % 2) * 13)
            }
        }
        .offset(x: x - 5)
    }

    /// What one mark says.
    ///
    /// **SLOTS, never minutes** — `PrivacyDevnetRoom.sentence`'s rule: the slot
    /// count is measured and this devnet's slot time is an assumption.
    static func reading(_ mark: PrivacyDevnetFigure.Mark) -> String {
        if let aged = mark.agedBy {
            return String(localized: "gone \(String(aged)) ago")
        }
        let left = UInt64((mark.position ?? 0) * Double(PrivacyDevnetRoots.windowSlots))
        return String(localized: "\(String(left)) left")
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
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                shape(item, index: index)
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(items)))
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
                .frame(width: max(4, stripWidth * share - 3), height: 8)
                .chartArrival(index: index, reduceMotion: reduceMotion)
        case .key:
            PrivacyDevnetSpentKey(size: 9)
                .padding(.leading, index == 0 ? 0 : 3)
                .chartArrival(index: index, reduceMotion: reduceMotion)
        case .root:
            Rectangle()
                .fill(DS.tint)
                .frame(width: 8, height: 8)
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

    var body: some View {
        Circle()
            .strokeBorder(DS.tint, lineWidth: max(2, size * 0.28))
            .frame(width: size, height: size)
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

// MARK: - One transaction, as a row

/// The row every list scope draws: what it is, what it did, and the words.
///
/// **The hash leads and the words trail**, which reverses what the room drew
/// before. The hash is the row's identity and the only thing a person can carry
/// to a block explorer; the sentence is a reading, and a reading belongs where
/// the eye lands last.
struct PrivacyDevnetMoveRow: View {
    let hash: String
    let block: UInt64?
    let items: [PrivacyDevnetFigure.Item]
    let words: String
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Space.s2) {
                PrivacyDevnetAnatomy(items: items, reduceMotion: reduceMotion)
                Text(words)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(tail)
                .dsText(.mono12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The identity line — which transaction, and where it landed.
    ///
    /// **A hash IDENTIFIES, it does not INFORM** (§571): every list in this
    /// room first shipped with the hash in the crown and a person with a full
    /// room reported seeing "nothing in the lists". So the drawing and its
    /// reading take the crown and the hash is the quiet tail, where somebody
    /// matching one against a block explorer can still find it.
    private var tail: String {
        let short = hash.count > 12
            ? String(hash.prefix(8)) + "…" + String(hash.suffix(4)) : hash
        guard let block else { return short }
        return "\(short) · block \(block)"
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
