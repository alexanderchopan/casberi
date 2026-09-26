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
                .dsText(.subhead12)
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
                .dsText(.subhead12)
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
// transactions ARE, and the shared frames strip what their steps DID
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
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
        }
    }
}

// MARK: - What this room's transactions are (prd §606)

// **`PrivacyDevnetMoveSpine` IS DELETED (prd §687).** It drew this room's
// Activity as a dot strip on a block axis — the right figure while the
// moves carried a block and no date, and displaced the day those moves
// got one and the scope moved to the shared `RoomActivityChart`. Its
// only caller went with it; a figure kept for no scope is the dead code
// `HegotaRoom.valueSeries` was two rulings ago.


/// **DORMANT SINCE §610, and kept rather than deleted.**
///
/// It was the Activity scope's figure and is now that scope's one-line caption
/// (`PrivacyDevnetRoomCard.activityFigure` draws `words` alone), because on
/// this chain the mix is a single kind and the figure restated the chassis
/// headline. The drawing itself is right for a room holding more than one kind
/// of transaction, and this chain will hold one the day a pool spend lands —
/// `PredictionVenueSwitcher`'s precedent: dormant with a stated reason beats
/// deleted and re-derived. `words` is live and is what the caption reads.
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
                            .dsText(.body17)
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

// **`PrivacyDevnetBudgetBar` IS DELETED (prd §698)** — it drew what a
// transaction's steps were allowed to spend, under the Frames scope, which asks
// what they DID. The room draws the family's shared frames figure there now,
// and the per-step budgets are still on the frame sheet.


// **`PrivacyDevnetFigures.grouped` IS DELETED (PERF, prd §628).** It was the
// second of the two copies §602 warned about and §605 folded into
// `DSCount.grouped` — left standing only because a sibling session held this
// file mid-work. That landed; every sheet in this room reads `DSCount` now, and
// this had no callers at all while still building a `NumberFormatter` per call.

/// **THE PROOFS AS BARS (prd §936).** The ring (§596, §929) drew each proof's
/// snapshot as a mark on an arc that drains; the tile draws the same fact in
/// the grammar every other tile uses — one bar per snapshot, as long as the
/// share of the chain's 8192-slot memory it still has, ticking as the chain
/// advances. A snapshot inside its last tenth, or already out, is the one red
/// bar: that is the proof that needs a fresh snapshot. The drift is the
/// model's (`PrivacyDevnetFigure.drifted`), never recomputed here.
struct PrivacyDevnetProofBars: View {
    let marks: [PrivacyDevnetFigure.Mark]
    var remaining: UInt64?
    var readAt: Date?
    var caption: String?
    let reduceMotion: Bool
    @State private var lit: String?

    /// The share of the window under which a snapshot is about to leave it.
    static let leavingShare: Double = 0.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 600 : 6)) { context in
            let drifted = drifted(now: context.date)
            DSBarFigure(reading: { reading(drifted) },
                        bars: DSBarList(bars: Self.bars(drifted), lit: lit) { picked in
                            lit = lit == picked ? nil : picked
                        })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized: "The chain's memory")))
    }

    private func drifted(now: Date) -> [PrivacyDevnetFigure.Mark] {
        guard let readAt else { return marks }
        let elapsed = now.timeIntervalSince(readAt)
        guard elapsed > 0 else { return marks }
        return marks.map { mark in
            guard let position = mark.position else { return mark }
            var moved = mark
            moved.position = PrivacyDevnetFigure.drifted(position: position, secondsSinceRead: elapsed)
            return moved
        }
    }

    static func id(_ mark: PrivacyDevnetFigure.Mark) -> String { "\(mark.set):\(mark.slot)" }

    static func bars(_ marks: [PrivacyDevnetFigure.Mark]) -> [DSBarList.Bar] {
        marks.sorted { ($0.position ?? -1) > ($1.position ?? -1) }.map { mark in
            let share = max(0, min(1, mark.position ?? 0))
            let proofs = mark.count == 1 ? String(localized: "1 proof")
                                         : String(localized: "\(String(mark.count)) proofs")
            let left = mark.position.map {
                PrivacyDevnetRoots.approximate(slots: UInt64(max(0, $0) * Double(PrivacyDevnetRoots.windowSlots)))
            } ?? String(localized: "gone")
            return DSBarList.Bar(id: id(mark), label: proofs, value: left, share: share,
                                 alarm: (mark.position ?? 0) < leavingShare)
        }
    }

    @ViewBuilder
    private func reading(_ drifted: [PrivacyDevnetFigure.Mark]) -> some View {
        let proofs = drifted.reduce(0) { $0 + $1.count }
        let leaving = drifted.filter { ($0.position ?? 0) < Self.leavingShare }.reduce(0) { $0 + $1.count }
        if let lit, let mark = drifted.first(where: { Self.id($0) == lit }) {
            DSFigureReading(number: mark.position.map {
                                PrivacyDevnetRoots.approximate(slots: UInt64(max(0, $0) * Double(PrivacyDevnetRoots.windowSlots)))
                            } ?? String(localized: "Gone"),
                            caption: String(localized: "left in the chain's memory"))
        } else {
            DSFigureReading(number: remaining.map { PrivacyDevnetRoots.approximate(slots: $0) } ?? String(proofs),
                            caption: [remaining == nil ? (proofs == 1 ? String(localized: "proof") : String(localized: "proofs"))
                                                       : String(localized: "left on the freshest proof"),
                                      caption].compactMap { $0 }.joined(separator: " · "),
                            alarm: leaving > 0 ? String(localized: "\(String(leaving)) leaving") : nil)
        }
    }
}
