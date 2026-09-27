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

    /// **THE WINDOW RULE IS THE CROWN'S, VERBATIM.** Each date becomes a
    /// `ValueSample` carrying no value, purely so `WalletRange.offered` and
    /// `.clip` decide this control's windows and the crown's by one piece of
    /// code. The alternative — a second, date-only window rule — is how two
    /// controls over one record come to disagree about what "30d" covers.
    private var samples: [WalletStore.ValueSample] {
        dates.sorted().map { WalletStore.ValueSample(at: $0, usd: 0) }
    }

    /// **A PRESSED BAR (prd §921).** The bucket under the finger, while it is
    /// held — Health's gesture: the headline becomes that bucket's count and
    /// the line its days. The crown's own `ChartScrubSurface` carries the
    /// press (a long press sequenced before the drag, so scroll content never
    /// loses a swipe to it — the gotcha `WalletBalanceHeadline` already paid).
    @State private var pressed: Int?

    /// The words under the bars (prd §921): the window's first day at the
    /// left, Today at the right — Health's axis, said in words because nothing
    /// here draws a line.
    private static let axisRow: CGFloat = 16

    var body: some View {
        let all = samples
        let offered = WalletRange.offered(for: all)
        let active = offered.contains(range) ? range : WalletRange.remembered(offered: offered)
        let inWindow = active.clip(all).map(\.at)
        let buckets = Self.buckets(dates: inWindow, range: active)
        let held = pressed.flatMap { buckets.indices.contains($0) ? $0 : nil }
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            // **ONE NUMBER, ONE NOUN (prd §942).** At rest the caption is what
            // is counted; the window is said once, on the last line, and the
            // scope by the account menu. A held bar still says its days.
            reading(count: held.map { buckets[$0] } ?? inWindow.count,
                    when: held.map { Self.bucketDays(index: $0, dates: inWindow, range: active) } ?? "")
            if buckets.contains(where: { $0 > 0 }) {
                // At rest the lit bar is the NEWEST BUCKET THAT HOLDS
                // ANYTHING — the last time something happened — because an
                // empty today draws no bar (below), and lighting nothing left
                // every bar quiet: seen on the Wallet room's first build, a
                // whole chart one notch dim with no reason on screen.
                ActivityBars(counts: buckets, lit: held ?? buckets.lastIndex { $0 > 0 })
                    // **TO THE FLOOR (prd §942).** The bars take whatever the
                    // box leaves after the reading, the axis and the window
                    // line — no budgeted constant, so no band of air under them.
                    .frame(maxHeight: .infinity)
                    .overlay {
                        GeometryReader { geo in
                            ChartScrubSurface(plot: CGRect(origin: .zero, size: geo.size),
                                              count: buckets.count,
                                              cursorIndex: pressed,
                                              onScrub: { pressed = $0 })
                        }
                    }
                    .id(active)
            } else {
                Text("Nothing in this window.")
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            HStack {
                Text(Self.firstDay(dates: inWindow, range: active))
                Spacer(minLength: 0)
                Text(String(localized: "Today"))
            }
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
            .frame(height: Self.axisRow)
            DSRangeChips(ranges: offered, range: active, slim: true) { picked in
                range = picked
                picked.remember()
            }
        }
        // The box is the caller's, exactly: the bars flex inside it.
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: box, alignment: .top)
    }

    /// The reading — caption, count, and one line under it — bare or inside a
    /// Button depending on whether there is a door behind it.
    ///
    /// **THE COUNT WEARS THE CROWN'S RUNG (prd §921).** It was `price40` while
    /// the Home crown one tap away draws its number at `stat24` — the
    /// inconsistency §551 ruled out of the crowns, back in the scope beside
    /// them. **And the line under it is never absent:** a calendar window says
    /// the change against the window before, the whole record says its span
    /// ("since Aug 17", the crown's own window word), so this stack stands
    /// exactly as tall as Home's and leaves no air under the chips.
    /// **ONE NUMBER, ONE CAPTION (prd §936).** The count, and under it what
    /// is counted, when, and whose — the change-against-before sentence is
    /// deleted; the bars already show which way it went.
    @ViewBuilder
    private func reading(count: Int, when: String) -> some View {
        let label = countLabel(count)
        let noun = label.hasPrefix(String(count) + " ") ? String(label.dropFirst(String(count).count + 1)) : label
        let block = DSFigureReading(number: String(count),
                                    caption: [noun, when].filter { !$0.isEmpty }.joined(separator: " · "))
        if let onOpen {
            Button(action: { DSHaptic.selection(); onOpen() }) { block }
                .buttonStyle(.plain)
        } else {
            block
        }
    }

    /// The change against the window before, in words; the window's own span
    /// where there is no window before (`.watched` — a comparison against a
    /// period half of which predates the record would be a guess).
    static func changeWords(delta: Int?, window: String) -> String {
        guard let delta else { return window }
        return delta == 0 ? String(localized: "Same as the window before")
             : delta > 0 ? String(localized: "\(String(delta)) more than the window before")
                         : String(localized: "\(String(-delta)) fewer than the window before")
    }

    /// The window's start and one bucket's width, in seconds — the same
    /// arithmetic `buckets` slices by, stated once so the axis words and a
    /// pressed bar's days can never disagree with the bars.
    static func bucketSpan(dates: [Date], range: WalletRange, now: Date = .now)
        -> (start: Date, width: TimeInterval) {
        let oldest = dates.min() ?? now
        let span = range.span ?? max(now.timeIntervalSince(oldest), 1)
        let n = bucketCount(range: range, span: span)
        return (now.addingTimeInterval(-span), span / Double(n))
    }

    /// The left-hand axis word: the window's first day.
    static func firstDay(dates: [Date], range: WalletRange, now: Date = .now) -> String {
        Self.day(bucketSpan(dates: dates, range: range, now: now).start, now: now)
    }

    /// A pressed bar's days — "Sep 22" for a day-wide bucket, "Sep 20 – 22"
    /// for a wider one, the month repeated only when it changes.
    static func bucketDays(index: Int, dates: [Date], range: WalletRange, now: Date = .now) -> String {
        let (start, width) = bucketSpan(dates: dates, range: range, now: now)
        let from = start.addingTimeInterval(width * Double(index))
        let to = min(from.addingTimeInterval(width - 1), now)
        let cal = Calendar.current
        if cal.isDate(from, inSameDayAs: to) || width <= 86_400 { return day(from, now: now) }
        if cal.isDate(from, equalTo: to, toGranularity: .month) {
            return "\(day(from, now: now)) – \(to.formatted(.dateTime.day()))"
        }
        return "\(day(from, now: now)) – \(day(to, now: now))"
    }

    private static func day(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
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
///
/// **ONE BAR IS LIT, THE REST ONE NOTCH QUIETER (prd §921).** At rest it is
/// the newest bucket — the one you are living in, which the word "Today" under
/// its edge names — and under a press it is the bucket held. Fitness and
/// Screen Time draw today this way; the quieter bars are the same tint at
/// less opacity, so nothing about the scale changes.
struct ActivityBars: View {
    let counts: [Int]
    var lit: Int? = nil
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
                         with: .color(DS.tint.opacity(lit == nil || lit == i ? 1 : 0.45)))
            }
        }
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized:
            "\(String(counts.reduce(0, +))) transactions over \(String(counts.count)) periods")))
    }
}

