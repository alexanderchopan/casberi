import SwiftUI
import Charts

/// The token chart family (prd 51, from the approved mock): one anatomy at
/// two doses. `TokenChartView` is the sheet's full read — price, a delta
/// pill that names its window, range chips (24h/7d/30d), a scrubbable line
/// with anchored high/low, a skeleton while loading. `TokenChartPlot` is
/// the bare plot the Home row reuses (gradient fade + live endpoint, no
/// chrome). The feed Sparkline is deliberately untouched — its job is one
/// glance in a scrolling list.
enum TokenChartStyle {

    /// Green up / red down is state (the color law's third permitted job);
    /// light mode pulls the hue 35% toward black — BridgeIcon's own mix —
    /// so the line and pill hold on the white sheet.
    static func accent(up: Bool, scheme: ColorScheme) -> Color {
        let base = up ? DS.confirm : DS.destructive
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    /// A change that rounds away at the one decimal we print has no direction
    /// to report: "-0.0%" in red claims a loss the number itself denies. Flat
    /// is its own state — no sign, quiet ink (2026-07-16).
    static func isFlat(_ c: Double) -> Bool { abs(c * 100) < 0.05 }

    /// The delta's ink, flat included — the up/down reading of a change is
    /// only honest once the change survives rounding.
    static func accent(change: Double, scheme: ColorScheme) -> Color {
        isFlat(change) ? DS.textTertiary : accent(up: change >= 0, scheme: scheme)
    }

    static func priceText(_ p: Double) -> String {
        if p >= 1 { return String(format: "$%.2f", p) }
        if p >= 0.01 { return String(format: "$%.4f", p) }
        return String(format: "$%.8f", p)
    }

    static func changeText(_ c: Double) -> String {
        if isFlat(c) { return "0.0%" }
        return String(format: "%@%.1f%%", c > 0 ? "+" : "", c * 100)
    }

    /// The chosen range persists per symbol (prd 51) — a 7d watcher isn't
    /// reset to 24h on every open. Key-based since the stock chart joined
    /// (2026-07-15): tokens keep their historical "token.range.…" keys.
    static func rememberedRange<R: PriceRange>(key: String) -> R {
        UserDefaults.standard.string(forKey: key)
            .flatMap(R.init(rawValue:)) ?? R.base
    }
    static func remember<R: PriceRange>(_ range: R, key: String) {
        UserDefaults.standard.set(range.rawValue, forKey: key)
    }
}

/// The signed percent in a state-fill capsule, naming its window:
/// "−1.8% · 24h". The fill is the kind-pill grammar (color at low opacity);
/// the number still carries the sign, so color is never the only voice.
/// An empty label drops the window ("+4.2%" alone — the feed row's dose,
/// where every pulse is 24h and saying so per row is noise). `solid` is the
/// full-ink fill (2026-07-17, the fat-row build) — but only when the change
/// has a direction: flat keeps the quiet fill, because a loud pill around
/// "0.0%" would be state-styling with no state to report.
struct TokenDeltaPill: View {
    let change: Double
    let label: String
    /// The Home row's smaller dose.
    var compact: Bool = false
    var solid: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = TokenChartStyle.accent(change: change, scheme: scheme)
        let flat = TokenChartStyle.isFlat(change)
        let loud = solid && !flat
        let text = label.isEmpty
            ? TokenChartStyle.changeText(change)
            : "\(TokenChartStyle.changeText(change)) · \(label)"
        Text(text)
            .dsText(compact ? .label12 : .subhead13)
            .fontWeight(solid ? .bold : .regular)
            .monospacedDigit()
            // A solid pill must hold on ANY backing — the hero sits on the
            // sheet's cover wash, where the quiet 15% fill vanished (review
            // 2026-07-17). Loud = full state ink; solid-but-flat = a neutral
            // strong fill: still no direction color (honesty §83), just
            // enough body to survive the wash.
            .foregroundStyle(loud ? .white : solid ? DS.textPrimary : ink)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 2 : 3)
            .background(loud ? ink
                        : solid ? DS.fillStrong
                        : ink.opacity(scheme == .light ? 0.12 : 0.15),
                        in: Capsule(style: .continuous))
    }
}

/// Something that HAPPENED, drawn against a line that only knows values
/// (2026-07-21, prd §155). The wallet's balance line is sampled; its
/// transactions are landed things — a mark ties one to the other, so a step in
/// the line can be read back to the send that caused it.
///
/// `x` is fractional along the series (2.5 = halfway between the third and
/// fourth sample) because a transaction lands whenever it lands, not on a
/// sample boundary — which is why the plot's x scale is Double, not Int.
struct TokenChartMark: Identifiable, Equatable {
    let id: UUID
    let x: Double
    /// What the mark is, for the accessibility label — never drawn.
    let label: String
}

/// The bare plot — line over a gradient fade, the live end pulsing gently
/// (the chart refreshes; the pulse claims only the endpoint). A coarse
/// fallback curve draws as it is: five dots, straight segments, no pulse
/// (prd 51: it stops pretending). No axes, no grid — the hairline law
/// holds on charts too.
struct TokenChartPlot: View {
    let chart: TokenChart
    let accent: Color
    var height: CGFloat = 140

    /// The Home row's chart is fetched once per visit, not streamed — a
    /// pulsing endpoint there overclaims (the row's own ruling; review
    /// 2026-07-11). The sheet, which refetches per range, keeps the pulse.
    var pulses = true
    /// Moments to mark on the curve (transactions, prd §155) — empty
    /// everywhere but the wallet balance line.
    var marks: [TokenChartMark] = []
    /// Given, the marks become tap targets: the nearest mark within a finger's
    /// reach of the tap wins. Absent, they're read-only punctuation (no dead
    /// controls either way — an untappable mark simply isn't a control).
    var onTapMark: ((TokenChartMark) -> Void)? = nil
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // x is Double, not the enumeration's Int: an event mark lands between
        // samples (see TokenChartMark), and a proxy can only place a value in
        // its scale's own type.
        Chart(Array(chart.closes.enumerated()), id: \.offset) { i, close in
            LineMark(x: .value("t", Double(i)), y: .value("price", close))
                .interpolationMethod(chart.coarse ? .linear : .catmullRom)
                .foregroundStyle(accent)
            AreaMark(x: .value("t", Double(i)), y: .value("price", close))
                .interpolationMethod(chart.coarse ? .linear : .catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(0.22), accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
            if chart.coarse {
                PointMark(x: .value("t", Double(i)), y: .value("price", close))
                    .symbolSize(28)
                    .foregroundStyle(accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: height)
        .chartOverlay { proxy in
            GeometryReader { geo in
                // The live endpoint — solid dot plus a soft breathing halo.
                if pulses, !chart.coarse, let plotAnchor = proxy.plotFrame,
                   let last = chart.closes.last,
                   let x = proxy.position(forX: Double(chart.closes.count - 1)),
                   let y = proxy.position(forY: last) {
                    let plot = geo[plotAnchor]
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.16))
                            .frame(width: pulsing ? 15 : 9, height: pulsing ? 15 : 9)
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                    }
                    .position(x: plot.minX + x, y: plot.minY + y)
                    .onAppear {
                        guard !reduceMotion, !pulsing else { return }
                        withAnimation(.easeInOut(duration: 1.4)
                            .repeatForever(autoreverses: true)) { pulsing = true }
                    }
                }
                if !marks.isEmpty, let plotAnchor = proxy.plotFrame {
                    markLayer(proxy: proxy, plot: geo[plotAnchor])
                }
            }
        }
    }

    /// The event marks, and (when a handler exists) their tap target. Drawn in
    /// the plot's own ink at low opacity with a small solid core: punctuation
    /// on the line, never a second series competing with it.
    @ViewBuilder
    private func markLayer(proxy: ChartProxy, plot: CGRect) -> some View {
        ForEach(marks) { mark in
            if let x = proxy.position(forX: mark.x),
               let y = proxy.position(forY: value(at: mark.x)) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .overlay {
                        Circle().stroke(accent.opacity(0.3), lineWidth: 4)
                    }
                    .position(x: plot.minX + x, y: plot.minY + y)
                    .accessibilityLabel(mark.label)
            }
        }
        if let onTapMark {
            // One tap surface over the plot rather than a target per dot: a
            // 5pt circle is far under the 44pt floor, so the nearest mark
            // within a finger's reach of the tap wins instead.
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: plot.width, height: plot.height)
                .position(x: plot.midX, y: plot.midY)
                .onTapGesture { point in
                    let hits = marks.compactMap { mark -> (TokenChartMark, CGFloat)? in
                        guard let x = proxy.position(forX: mark.x) else { return nil }
                        return (mark, abs(plot.minX + x - point.x))
                    }
                    guard let nearest = hits.min(by: { $0.1 < $1.1 }), nearest.1 <= 22
                    else { return }
                    DSHaptic.selection()
                    onTapMark(nearest.0)
                }
        }
    }

    /// The curve's value at a fractional index — linearly interpolated between
    /// the two samples it falls between, so a mark sits ON the line rather than
    /// floating beside it.
    private func value(at x: Double) -> Double {
        let closes = chart.closes
        guard !closes.isEmpty else { return 0 }
        let clamped = min(max(x, 0), Double(closes.count - 1))
        let low = Int(clamped.rounded(.down)), high = min(low + 1, closes.count - 1)
        let t = clamped - Double(low)
        return closes[low] + (closes[high] - closes[low]) * t
    }
}

/// A skeleton, not a spinner (prd 51) — ghosts of the exact anatomy that's
/// coming (price seat, pill seat, plot) with one slow shimmer, so the
/// layout never jumps when data lands and nothing spins at the person.
struct TokenChartSkeleton: View {
    var plotHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                ghost(width: 110, height: 24, radius: 6)
                ghost(width: 72, height: 20, radius: 10)
            }
            ghost(width: nil, height: plotHeight, radius: 8)
        }
    }

    private func ghost(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        GhostShimmer()
            .frame(maxWidth: width ?? .infinity)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// One shared shimmer — a faint highlight sweeping the fill, honest about
/// "drawing soon" without a spinner. Still under reduce-motion.
private struct GhostShimmer: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(DS.fillFaint)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.05), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: phase * geo.size.width * 1.7)
                }
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// The sheet's full chart — the symbol's "media" (ThingContent rule). Owns
/// its fetches (one per range, cached per visit), the draw-on reveal (a
/// range switch is a data arrival — the one moment animation belongs to),
/// touch scrubbing (press, then drag; the header rolls to the scrubbed
/// value, the finger carries only the when), and per-symbol range memory.
/// The dead case (no price anywhere) renders the caller's fallback — the
/// plain link, honestly. Generic over the range set (2026-07-15) so a
/// watched stock (StockRange/Yahoo) wears the exact anatomy a token does;
/// the token init below keeps every existing call site unchanged.
struct TokenChartView<R: PriceRange, Fallback: View>: View {
    /// The UserDefaults key the chosen range persists under.
    let memoryKey: String
    /// One range's curve — nil means this range can't be answered.
    let fetch: (R) async -> TokenChart?
    /// The since-you-watched anchor (2026-07-14): the price and moment the
    /// symbol joined the watchlist, kept on its thing. When present, a line
    /// under the plot says "+41.2% · since Jul 2" against the live price —
    /// a number known locally that no market site can show. nil (older
    /// watches, non-watchlist charts) renders nothing.
    var since: (price: Double, date: Date)? = nil
    /// The Big money dose (2026-07-17, approved mock): the price leads big,
    /// centered, in the rounded display voice, with the delta pill beneath
    /// it, and the range chips move below the plot. False keeps the classic
    /// left-aligned header row — every existing call site unchanged.
    var hero: Bool = false
    @ViewBuilder let fallback: () -> Fallback

    private enum Phase { case loading, ready, dead }

    @State private var range: R
    @State private var charts: [R: TokenChart] = [:]
    @State private var phase: Phase = .loading
    /// One honest line when a range has no candles ("No 7d prices…") —
    /// the selection reverts rather than faking a curve or blanking.
    @State private var note: String?
    @State private var revealed = false
    @State private var scrubIndex: Int?
    @Environment(\.colorScheme) private var scheme

    init(memoryKey: String, fetch: @escaping (R) async -> TokenChart?,
         since: (price: Double, date: Date)? = nil, hero: Bool = false,
         @ViewBuilder fallback: @escaping () -> Fallback) {
        self.memoryKey = memoryKey
        self.fetch = fetch
        self.since = since
        self.hero = hero
        self.fallback = fallback
        _range = State(initialValue: TokenChartStyle.rememberedRange(key: memoryKey))
    }

    private var chart: TokenChart? { charts[range] }
    private var displayIndex: Int? {
        guard let chart else { return nil }
        return scrubIndex.map { min($0, chart.closes.count - 1) }
    }
    private var displayPrice: Double {
        guard let chart else { return 0 }
        if let i = displayIndex { return chart.closes[i] }
        return chart.price
    }
    private var displayChange: Double {
        guard let chart, let first = chart.closes.first, first > 0 else { return 0 }
        if let i = displayIndex { return (chart.closes[i] - first) / first }
        return chart.change
    }
    private var accent: Color {
        TokenChartStyle.accent(change: displayChange, scheme: scheme)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading where chart == nil:
                TokenChartSkeleton()
            case .dead:
                fallback()
            default:
                loaded
            }
        }
        .task(id: range) { await load() }
    }

    @ViewBuilder private var loaded: some View {
        if let chart {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if hero { heroHeader } else { header(chart) }
                plot(chart)
                if hero { heroFooter(chart) }
                sinceWatchedLine(chart)
                if let note {
                    Text(note)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
        } else {
            TokenChartSkeleton()
        }
    }

    /// "+41.2% · since Jul 2 — you watched at $0.0031". The change is the
    /// LIVE price against the watch-time price; both numbers were really
    /// true, so the line claims nothing the record doesn't hold.
    @ViewBuilder private func sinceWatchedLine(_ chart: TokenChart) -> some View {
        if let since, since.price > 0, chart.price > 0 {
            let change = (chart.price - since.price) / since.price
            HStack(spacing: DS.Space.s2) {
                TokenDeltaPill(change: change,
                               label: "since \(since.date.formatted(.dateTime.month(.abbreviated).day()))")
                Text("you watched at \(TokenChartStyle.priceText(since.price))")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            // Hero centers everything — a left-hung line under a centered
            // plot read as a stray (user checkpoint 2026-07-17).
            .frame(maxWidth: .infinity, alignment: hero ? .center : .leading)
        }
    }

    /// The Big money header (prd §102, from the approved mock): price
    /// centered on the ramp's hero rung, the window-naming delta pill
    /// beneath. Scrubbing still rolls this number; the pill still re-labels
    /// to the scrubbed window's change.
    private var heroHeader: some View {
        VStack(spacing: DS.Space.s2) {
            Text(TokenChartStyle.priceText(displayPrice))
                .dsText(.price40)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(DS.Motion.standard, value: displayPrice)
            // Solid: the hero speaks at full Cash-App weight — the quiet
            // fill under a 40pt price read as an afterthought.
            TokenDeltaPill(change: displayChange, label: range.rawValue, solid: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Hero's under-plot seat for what the classic header carried on its
    /// right: the range chips, or the coarse fallback's honest label.
    private func heroFooter(_ chart: TokenChart) -> some View {
        HStack {
            Spacer(minLength: 0)
            chipsOrCoarseLabel(chart)
            Spacer(minLength: 0)
        }
    }

    /// The range chips, or — coarse — the fallback saying what it is (and
    /// offering no ranges: 7d on five points would be a fake control). ONE
    /// builder for both the classic header's trailing seat and heroFooter,
    /// so the two layouts can't drift on the same honesty copy.
    @ViewBuilder private func chipsOrCoarseLabel(_ chart: TokenChart) -> some View {
        if chart.coarse {
            Text("24h · 5 price points")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        } else {
            rangeChips
        }
    }

    private func header(_ chart: TokenChart) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(TokenChartStyle.priceText(displayPrice))
                .dsText(.heading22).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(DS.Motion.standard, value: displayPrice)
            TokenDeltaPill(change: displayChange, label: range.rawValue)
            Spacer(minLength: DS.Space.s2)
            chipsOrCoarseLabel(chart)
        }
    }

    private var rangeChips: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(R.allCases, id: \.self) { r in
                Button {
                    guard r != range else { return }
                    DSHaptic.tap()
                    scrubIndex = nil
                    range = r
                    TokenChartStyle.remember(r, key: memoryKey)
                } label: {
                    Text(r.rawValue)
                        .dsText(.label12)
                        // Never wraps — squeezed, the row gives, not the
                        // label ("24h" once folded into a circled "24/h").
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(r == range ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(r == range ? DS.fillFaint : .clear,
                                    in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func plot(_ chart: TokenChart) -> some View {
        TokenChartPlot(chart: chart, accent: accent)
            // Draw-on reveal, replayed per range — a range switch is a
            // data arrival (the GenTokenRow entrance, shared).
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: revealed ? geo.size.width : 0)
                }
            }
            // Room for the high/low labels above and below the plot.
            .padding(.vertical, 18)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    overlayContent(chart, proxy: proxy, geo: geo)
                }
            }
    }

    /// The sheet-only plot chrome: anchored high/low (the only numbers on
    /// the plot, in tertiary ink) and the scrub cursor. Drawn in overlay
    /// space so the plot component stays bare for the Home row.
    @ViewBuilder
    private func overlayContent(_ chart: TokenChart, proxy: ChartProxy,
                                geo: GeometryProxy) -> some View {
        if let plotAnchor = proxy.plotFrame {
            let plot = geo[plotAnchor]
            let closes = chart.closes

            // High and low, each tied to its point by a 2.5pt anchor dot.
            if !chart.coarse, closes.count > 2,
               let hi = closes.max(), let lo = closes.min(),
               let iH = closes.firstIndex(of: hi), let iL = closes.firstIndex(of: lo),
               let xH = proxy.position(forX: Double(iH)), let yH = proxy.position(forY: hi),
               let xL = proxy.position(forX: Double(iL)), let yL = proxy.position(forY: lo) {
                extremeMark(text: TokenChartStyle.priceText(hi),
                            x: plot.minX + xH, dotY: plot.minY + yH,
                            labelY: plot.minY - 9, plot: plot)
                extremeMark(text: TokenChartStyle.priceText(lo),
                            x: plot.minX + xL, dotY: plot.minY + yL,
                            labelY: plot.maxY + 9, plot: plot)
            }

            // The scrub cursor — a 2pt tertiary line, the accent dot on the
            // curve, and the WHEN above it (the header carries the value:
            // one number, one place).
            if !chart.coarse, let i = displayIndex,
               let x = proxy.position(forX: Double(i)),
               let y = proxy.position(forY: closes[i]) {
                Capsule(style: .continuous)
                    .fill(DS.textTertiary.opacity(0.5))
                    .frame(width: 2, height: plot.height - 8)
                    .position(x: plot.minX + x, y: plot.midY)
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .position(x: plot.minX + x, y: plot.minY + y)
                if let ago = range.agoLabel(indexFromEnd: closes.count - 1 - i) {
                    Text(ago)
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .position(x: min(max(plot.minX + x, plot.minX + 28), plot.maxX - 28),
                                  y: plot.minY - 9)
                }
            }

            // Press, then drag — sequenced so the sheet's scroll still wins
            // a plain vertical swipe (the DragGesture-vs-ScrollView law).
            if !chart.coarse {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.15)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                guard case .second(true, let drag) = value else { return }
                                let x = (drag?.location.x ?? plot.maxX) - plot.minX
                                let i = Int((x / max(plot.width, 1)
                                             * CGFloat(closes.count - 1)).rounded())
                                let clamped = min(max(i, 0), closes.count - 1)
                                if clamped != scrubIndex {
                                    scrubIndex = clamped
                                    DSHaptic.selection()
                                }
                            }
                            .onEnded { _ in scrubIndex = nil }
                    )
            }
        }
    }

    private func extremeMark(text: String, x: CGFloat, dotY: CGFloat,
                             labelY: CGFloat, plot: CGRect) -> some View {
        ZStack {
            Circle().fill(DS.textTertiary)
                .frame(width: 2.5, height: 2.5)
                .position(x: x, y: dotY)
            Text(text)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .monospacedDigit()
                .position(x: min(max(x, plot.minX + 28), plot.maxX - 28), y: labelY)
        }
    }

    /// The range whose failure produced the current note — lets the note
    /// survive exactly one revert fetch (see load()'s success path).
    @State private var noteRange: R?

    private func load() async {
        if charts[range] != nil {
            phase = .ready
            replayReveal()
            return
        }
        if charts.isEmpty { phase = .loading }
        let fetched = await fetch(range)
        if let fetched {
            charts[range] = fetched
            phase = .ready
            // A note set by the range we just stepped BACK from survives one
            // success — clearing it here wiped the "No 7d prices yet"
            // explanation on the same beat it would first render, so the
            // revert read as a silent malfunction (review 2026-07-11).
            if noteRange == range { note = nil } else { noteRange = range }
            replayReveal()
            return
        }
        if range == R.base {
            // The base range is the one every live symbol answers —
            // nothing at all means dead/unreachable: the caller's
            // fallback (the plain link), honestly.
            phase = .dead
            return
        }
        // The symbol charts at base but this window has no candles — say
        // so and step back rather than fake a curve or strand the card on
        // an empty selection.
        note = "No \(range.rawValue) prices here yet."
        noteRange = range
        // The DISPLAY steps back but the remembered preference stays — a
        // transient network failure at 7d must not permanently downgrade a
        // 7d watcher to 24h (the prd-51 invariant; review 2026-07-11).
        let back: R = charts[R.base] != nil ? R.base : (charts.keys.first ?? R.base)
        range = back   // task(id: range) refires and shows (or fetches) it
    }

    private func replayReveal() {
        revealed = false
        withAnimation(.easeOut(duration: 0.7)) { revealed = true }
    }
}

extension TokenChartView {
    /// The token call — the original signature, so a watched token's call
    /// sites read exactly as before the view went generic. The memory key
    /// keeps its historical spelling: remembered ranges survive the change.
    init(chain: String, address: String,
         since: (price: Double, date: Date)? = nil, hero: Bool = false,
         @ViewBuilder fallback: @escaping () -> Fallback) where R == TokenRange {
        self.init(memoryKey: "token.range.\(chain).\(address)",
                  fetch: { await TokenChart.fetch(chain: chain, address: address, range: $0) },
                  since: since, hero: hero, fallback: fallback)
    }
}
