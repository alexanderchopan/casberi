import SwiftUI

/// **THE ACTIVITY SLOT, ONE TEMPLATE FOR EVERY WALLET-FAMILY ROOM (prd §686,
/// user: "for that one i want to implement a standard chart for number of
/// transations over time").**
///
/// §683 and §684 did this for Home. Activity had drifted further: Hegotá drew a
/// step figure, Frames drew signed value bars, the Privacy devnet drew a list
/// of pairs and Vibenet drew its own. Four drawings answering four different
/// questions, none of them the one a person opens Activity to ask, which is
/// *how much has been going on, and when*.
///
/// It reads in the same order as the crown above it, deliberately — a person
/// moving between the two tabs should be moving between two readings of one
/// shape, not two screens:
///
///   caption → count → change → bars → range chips
///
/// **BARS, NOT A SPARKLINE, AND BLUE RATHER THAN GREEN.** A transaction count
/// is a count per bucket; a line drawn between two counts claims a continuous
/// quantity that passes through the values in between, and nothing here
/// measured that. The tint is `DS.tint` because green is the delta's colour one
/// slot up — this drawing has no direction to report, and borrowing the colour
/// that means "up" for a number that means "how many" is the kind of quiet
/// false claim §83 exists to stop.
struct RoomActivityChart: View {
    /// Every transaction's own timestamp, in any order. A move whose date could
    /// not be read is simply not passed — it is not a transaction at time zero.
    var dates: [Date]
    /// The scope: one address's name, or how many you follow. Same line as the
    /// crown's, so the two tabs identify themselves identically.
    let caption: String
    var captionAddress: String? = nil
    /// How much room the room has. The chrome above and below the bars is this
    /// view's business — §684's own ruling, which is why no caller passes a
    /// height.
    var box: CGFloat = DSRoomChassis.visualSlot
    /// **WHAT IS BEING COUNTED**, the one thing this template cannot share.
    /// Every ethrex room counts transactions; vibenet's Activity is the record
    /// of a key being authorised or revoked, which is the same drawing over a
    /// different noun. Parameterised exactly as the crown's `format` is, and
    /// for the same reason — the shape is shared, the unit never is.
    var countLabel: (Int) -> String = {
        $0 == 1 ? String(localized: "1 transaction")
                : String(localized: "\(String($0)) transactions")
    }
    /// The door behind the reading, where a room has one.
    var onOpen: (() -> Void)? = nil

    @State private var range: WalletRange = WalletRange.remembered(offered: [])
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// **THE WINDOW RULE IS THE CROWN'S, VERBATIM.** Each date becomes a
    /// `ValueSample` carrying no value, purely so `WalletRange.offered` and
    /// `.clip` decide this control's windows and the crown's by one piece of
    /// code. The alternative — a second, date-only window rule — is how two
    /// controls over one record come to disagree about what "30d" covers.
    private var samples: [WalletStore.ValueSample] {
        dates.sorted().map { WalletStore.ValueSample(at: $0, usd: 0) }
    }

    private var chartHeight: CGFloat {
        DSRoomChassis.crownLine(box: box, chrome: DSRoomChassis.crownChrome)
    }

    var body: some View {
        let all = samples
        let offered = WalletRange.offered(for: all)
        let active = offered.contains(range) ? range : WalletRange.remembered(offered: offered)
        let inWindow = active.clip(all).map(\.at)
        let buckets = Self.buckets(dates: inWindow, range: active)

        VStack(alignment: .leading, spacing: DS.Space.s1) {
            reading(count: inWindow.count, priorChange: Self.change(all: all.map(\.at), range: active))
            if buckets.contains(where: { $0 > 0 }) {
                ActivityBars(counts: buckets)
                    .frame(height: chartHeight)
                    .id(active)
            } else {
                // An empty window states the fact and draws no bars, rather
                // than a row of nothing that reads as a rendering fault.
                Text("Nothing in this window.")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .frame(height: chartHeight, alignment: .top)
            }
            DSRangeChips(ranges: offered, range: active) { picked in
                range = picked
                picked.remember()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - the reading

    @ViewBuilder
    private func reading(count: Int, priorChange: Int?) -> some View {
        let block = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Space.s1) {
                if let captionAddress {
                    WalletFace(address: captionAddress, size: DS.Face.badge, circular: true)
                }
                Text(caption)
                    .dsText(.label12)
                    .fontWeight(captionAddress == nil ? .medium : .semibold)
                    .foregroundStyle(captionAddress == nil ? DS.textTertiary : DS.textSecondary)
                if onOpen != nil { WalletRowChevron() }
            }
            Text(countLabel(count))
                .dsText(.price40)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // **THE CHANGE IS AGAINST THE WINDOW BEFORE THIS ONE**, which is
            // the only comparison a count supports. It is nil on `.watched`,
            // where there IS no window before — and that is stated by drawing
            // nothing rather than by comparing against a period half of which
            // predates the record.
            if let priorChange {
                changeLine(priorChange)
            }
        }
        if let onOpen {
            Button(action: { DSHaptic.selection(); onOpen() }) { block }
                .buttonStyle(.plain)
        } else {
            block
        }
    }

    @ViewBuilder
    private func changeLine(_ delta: Int) -> some View {
        let flat = delta == 0
        let ink = flat ? DS.textSecondary
                       : TokenChartStyle.accent(change: delta > 0 ? 1 : -1, scheme: scheme)
        HStack(spacing: 5) {
            if !flat {
                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .dsGlyph(9)
                    .foregroundStyle(ink)
            }
            Text(flat ? String(localized: "Same as the window before")
                      : String(localized: "\(String(abs(delta))) vs the window before"))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(flat ? DS.textSecondary : ink)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    // MARK: - the arithmetic, kept apart so a harness can drive it

    /// How many buckets a window is drawn in. A day each for 7d and 30d — the
    /// unit a person actually thinks in — and for `.watched`, whose span is
    /// whatever the record happens to cover, the span divided into at most 30,
    /// because a bar thinner than a finger is a texture rather than a reading.
    /// **BUCKETS AGGREGATE; THEY DO NOT TALLY.** The first cut gave 30d thirty
    /// daily buckets and `.watched` up to thirty — and over a record of six
    /// transactions in five weeks, every bucket that held anything held exactly
    /// one, so the chart was a row of identical ticks with no shape at all. A
    /// bucket exists to COLLECT: seven days keeps a day each, because a week is
    /// read day by day, and the longer windows go coarser so that a busy
    /// stretch stacks into a tall bar instead of spreading into a picket fence.
    static func bucketCount(range: WalletRange, span: TimeInterval) -> Int {
        switch range {
        case .week:  return 7                      // a day each
        case .month: return 15                     // two days each
        case .watched:
            let days = Int((span / 86_400).rounded(.up))
            return max(1, min(16, days))
        }
    }

    /// The count per bucket, oldest bucket first. Buckets are equal slices of
    /// the window, and the NEWEST bucket ends now — so the right-hand bar is
    /// always the one you are living in, whatever the span.
    static func buckets(dates: [Date], range: WalletRange, now: Date = .now) -> [Int] {
        guard !dates.isEmpty else { return [] }
        let oldest = dates.min() ?? now
        let span = range.span ?? max(now.timeIntervalSince(oldest), 1)
        let n = bucketCount(range: range, span: span)
        let width = span / Double(n)
        var out = [Int](repeating: 0, count: n)
        for d in dates {
            let back = now.timeIntervalSince(d)
            guard back >= 0 else { out[n - 1] += 1; continue }
            // `back / width` counts backwards from the newest bucket.
            let idx = n - 1 - Int(back / width)
            if idx >= 0 && idx < n { out[idx] += 1 }
        }
        return out
    }

    /// This window's count minus the count of the window immediately before it.
    /// nil for `.watched`, which has no window before it.
    static func change(all: [Date], range: WalletRange, now: Date = .now) -> Int? {
        guard let span = range.span else { return nil }
        let thisStart = now.addingTimeInterval(-span)
        let priorStart = now.addingTimeInterval(-span * 2)
        let here = all.filter { $0 >= thisStart }.count
        let before = all.filter { $0 >= priorStart && $0 < thisStart }.count
        return here - before
    }
}

/// The bars themselves — a `Canvas`, the house idiom for a drawing sized from
/// data (`FramesMovementBars` is the other one), so the wipe rides
/// CoreAnimation rather than a per-frame SwiftUI interpolation on the main
/// actor.
struct ActivityBars: View {
    let counts: [Int]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            guard let busiest = counts.max(), busiest > 0 else { return }
            // **THE SCALE HAS A FLOOR OF FOUR, AND IT IS A CONVENTION RATHER
            // THAN A MEASUREMENT.** Scaled purely against the busiest bucket, a
            // record whose busiest day holds ONE transaction draws every bar at
            // full height — six lone transactions rendered as six full-height
            // columns, which reads as a burst of activity and is the loudest
            // possible way to say "not much happened". The axis therefore runs
            // 0…4 until something busier stretches it. It can only ever
            // UNDERSTATE a quiet record, never overstate a busy one, and the
            // count above the chart is the exact figure either way.
            let peak = max(busiest, 4)
            let slot = size.width / CGFloat(counts.count)
            let width = max(2, min(slot * 0.7, 14))
            for (i, count) in counts.enumerated() {
                // **A BUCKET WITH NOTHING IN IT DRAWS NOTHING.** Not a hairline
                // and not a floor: a day with no transactions is a gap in the
                // record, and the whole point of this drawing is that the gaps
                // are as legible as the bursts. This is the opposite call from
                // `FramesMovementBars`' minimum height, and for the opposite
                // reason — there, every bar IS a transaction that happened.
                guard count > 0 else { continue }
                let height = max(3, CGFloat(count) / CGFloat(peak) * (size.height - 2))
                let x = slot * CGFloat(i) + (slot - width) / 2
                let rect = CGRect(x: x, y: size.height - height, width: width, height: height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(3, width / 2)),
                         with: .color(DS.tint))
            }
        }
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized:
            "\(String(counts.reduce(0, +))) transactions over \(String(counts.count)) periods")))
    }
}
