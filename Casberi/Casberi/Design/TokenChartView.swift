import SwiftUI
import Charts
import Accessibility

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

    /// How recently a curve must have been read for the breathing endpoint to
    /// be an honest mark (2026-08-16). Two minutes: long enough that the halo
    /// survives a scrub and a scroll after the fetch that earned it, short
    /// enough that it can never sit over a price from earlier in the day.
    ///
    /// Its ceiling, stated rather than hidden: this is decided when the view
    /// renders, and a sheet nobody touches does not re-render, so a halo can
    /// outlive its window on a screen left open. The line beside it always
    /// carries the real read time, and a foreground return refetches — so the
    /// worst case is a stale halo next to a sentence that contradicts it,
    /// where before there was a stale halo and no sentence at all.
    static let freshWindow: TimeInterval = 120

    static func isFresh(_ fetchedAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) < freshWindow
    }

    /// "read just now" / "read 12 min ago" — the price surface's own version of
    /// the wallet's "as of Xh ago".
    static func readLine(_ fetchedAt: Date, now: Date = .now) -> String {
        let age = now.timeIntervalSince(fetchedAt)
        if age < 60 { return String(localized: "read just now") }
        return String(localized: "read \(fetchedAt.formatted(.relative(presentation: .named)))")
    }

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
    /// Render the delta in POINTS rather than percent (2026-07-28, the
    /// prediction-market rows). A probability moving 34% → 61% has gone up
    /// 27 POINTS; calling that "+79%" is a true statement about a different
    /// quantity, and the one people read off a market is points. Lives here
    /// rather than in a second pill so the capsule grammar stays in one file.
    var points: Bool = false
    /// The pill as it reads ON a saturated card (2026-08-15) — a solid WHITE
    /// capsule carrying the figure in its own direction, which is the grammar
    /// the day card arrived at in b32ce19 and the reason it arrived there: a
    /// green delta drawn straight onto a saturated blue is illegible, so the
    /// figure needs its own ground rather than a lighter ink.
    ///
    /// Distinct from `solid`, which is the opposite trade — a LOUD capsule in
    /// the state colour with white text, for a quiet backing that would
    /// swallow the 15% fill. Here the backing is the loud thing, so the pill
    /// answers with the one value no brand hue in the table can collide with.
    ///
    /// The accent is resolved for the LIGHT scheme regardless of theme,
    /// because the capsule is white in both: taking the dark theme's brighter
    /// green would put the washed-out variant on the one ground that needs the
    /// deeper one.
    var onColor: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = TokenChartStyle.accent(change: change,
                                         scheme: onColor ? .light : scheme)
        // Half a point is the smallest move worth a direction, the same job
        // `isFlat`'s 0.05% does for a price.
        let flat = points ? abs(change * 100) < 0.5 : TokenChartStyle.isFlat(change)
        let loud = solid && !flat
        let value = points ? Self.pointsText(change, flat: flat)
                           : TokenChartStyle.changeText(change)
        let text = label.isEmpty ? value : "\(value) · \(label)"
        Text(text)
            .dsText(compact ? .label12 : .subhead13)
            .fontWeight(solid ? .bold : .regular)
            .monospacedDigit()
            // A delta that updates ROLLS its digits instead of blinking
            // (2026-08-04, the microanimation pass) — the crown's own
            // grammar, one tier down. Inert when a List rebuilds the row's
            // identity (the WalletScreen:1016 caveat), which is the right
            // failure: no animation, never a wrong number.
            .contentTransition(.numericText())
            .animation(DS.Motion.standard, value: text)
            // A solid pill must hold on ANY backing — the hero sits on the
            // sheet's cover wash, where the quiet 15% fill vanished (review
            // 2026-07-17). Loud = full state ink; solid-but-flat = a neutral
            // strong fill: still no direction color (honesty §83), just
            // enough body to survive the wash.
            // A flat move on a white capsule takes a neutral dark ink rather
            // than `DS.textPrimary`, which is WHITE in the dark theme and
            // would render the figure invisible on its own ground (§83's
            // no-direction rule must not cost the number itself).
            .foregroundStyle(onColor ? (flat ? Color.fixed("#3c3c43") : ink)
                             : loud ? .white : solid ? DS.textPrimary : ink)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 2 : 3)
            .background(onColor ? Color.white
                        : loud ? ink
                        : solid ? DS.fillStrong
                        : ink.opacity(scheme == .light ? 0.12 : 0.15),
                        in: Capsule(style: .continuous))
    }

    /// "+27 pts" — a probability delta in its own unit. A move that rounds
    /// away has no direction, exactly as with a price (prd §83 ③).
    private static func pointsText(_ change: Double, flat: Bool) -> String {
        let pts = change * 100
        if flat { return String(localized: "0 pts") }
        return String(format: "%@%.0f pts", pts > 0 ? "+" : "", pts)
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
    /// The line's weight and the area's density (prd §157, 2026-07-21). The
    /// defaults are the chart family's own hairline dose, unchanged
    /// everywhere; the wallet balance line asks for more body, because a thin
    /// line under a 48pt total read as an afterthought rather than the same
    /// fact drawn twice.
    var lineWidth: CGFloat = 2
    var fillOpacity: Double = 0.22
    /// A solid dot on the last point — the pulse's quiet twin (prd §157). The
    /// breathing halo claims live streaming and stays off by default (the
    /// 2026-07-11 ruling); a static dot only claims "this is the latest
    /// reading", which every one of these lines can honestly say.
    var endpointDot = false
    /// Moments to mark on the curve (transactions, prd §155) — empty
    /// everywhere but the wallet balance line.
    var marks: [TokenChartMark] = []
    /// Given, the marks become tap targets: the nearest mark within a finger's
    /// reach of the tap wins. Absent, they're read-only punctuation (no dead
    /// controls either way — an untappable mark simply isn't a control).
    var onTapMark: ((TokenChartMark) -> Void)? = nil
    /// How long the caller's own draw-on takes, so the marks can wait for it
    /// (prd §171). 0 lands them immediately — the default everywhere that
    /// draws no line of its own.
    var markDelay: Double = 0
    /// Scrubbing — the line interrogated. Given a handler, a press-then-drag
    /// (or, on Catalyst, a resting cursor) reports the sample index under it,
    /// nil on release, and `cursorIndex` draws the scrub cursor at the
    /// caller's chosen index. The caller owns the state so it can also roll
    /// its own headline number to that sample (see `WalletBalanceHeadline`).
    ///
    /// Touch AND hover since 2026-08-03 (prd §297). For two days this was
    /// Mac-only, which meant the plumbing sat on every device and answered
    /// only a cursor; `ChartScrubSurface` now carries both, and states which
    /// half of it compiles where.
    var cursorIndex: Int? = nil
    var onScrub: ((Int?) -> Void)? = nil
    @State private var pulsing = false
    @State private var marksLanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // x is Double, not the enumeration's Int: an event mark lands between
        // samples (see TokenChartMark), and a proxy can only place a value in
        // its scale's own type.
        Chart(Array(chart.closes.enumerated()), id: \.offset) { i, close in
            LineMark(x: .value("t", Double(i)), y: .value("price", close))
                .interpolationMethod(chart.coarse ? .linear : .catmullRom)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                       lineJoin: .round))
            AreaMark(x: .value("t", Double(i)), y: .value("price", close))
                .interpolationMethod(chart.coarse ? .linear : .catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(fillOpacity), accent.opacity(0)],
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
                // The static endpoint — drawn only when the pulse isn't, so
                // the two can never stack into a dot with a halo it didn't ask
                // for.
                if endpointDot, !pulses, let plotAnchor = proxy.plotFrame,
                   let last = chart.closes.last,
                   let x = proxy.position(forX: Double(chart.closes.count - 1)),
                   let y = proxy.position(forY: last) {
                    let plot = geo[plotAnchor]
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .position(x: plot.minX + x, y: plot.minY + y)
                }
                // The scrub cursor + hover catcher (Mac, 2026-08-03) — drawn
                // BEFORE the marks so a mark's tap target stays on top and
                // clickable. Same cursor grammar as the sheet's touch scrub
                // (`TokenChartView.overlayContent`): a quiet vertical line,
                // the accent dot riding the curve.
                if let i = cursorIndex, !chart.coarse,
                   i >= 0, i < chart.closes.count,
                   let plotAnchor = proxy.plotFrame,
                   let x = proxy.position(forX: Double(i)),
                   let y = proxy.position(forY: chart.closes[i]) {
                    let plot = geo[plotAnchor]
                    Capsule(style: .continuous)
                        .fill(DS.textTertiary.opacity(0.5))
                        .frame(width: 2, height: max(plot.height - 8, 0))
                        .position(x: plot.minX + x, y: plot.midY)
                    Circle()
                        .fill(accent)
                        .frame(width: 9, height: 9)
                        .position(x: plot.minX + x, y: plot.minY + y)
                }
                if !marks.isEmpty, let plotAnchor = proxy.plotFrame {
                    markLayer(proxy: proxy, plot: geo[plotAnchor])
                        .onAppear {
                            guard !marksLanded else { return }
                            if reduceMotion || markDelay <= 0 {
                                marksLanded = true
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + markDelay) {
                                    marksLanded = true
                                }
                            }
                        }
                }
                if scrubs || onTapMark != nil, let plotAnchor = proxy.plotFrame {
                    interaction(plot: geo[plotAnchor], proxy: proxy)
                }
            }
        }
    }

    /// Whether this plot can be scrubbed at all — a handler, and a real curve
    /// under it. Hoisted so the surface below and its gesture can't disagree:
    /// gating the tap catcher on `onScrub == nil` while gating the surface on
    /// the full condition left a hole (both callbacks + a coarse chart = marks
    /// drawn with nothing catching them, a dead control by the honesty rule).
    private var scrubs: Bool {
        onScrub != nil && !chart.coarse && chart.closes.count > 1
    }

    /// ONE surface for every gesture this plot answers (2026-08-03) — the
    /// scrub, the hover, and the mark taps.
    ///
    /// One rectangle rather than two stacked ones on purpose: a
    /// `.onTapGesture` view directly over a long-press-then-drag view is two
    /// hit-testable rectangles competing for the same touch, which is the sort
    /// of arrangement that works on a simulator and fails on a finger.
    private func interaction(plot: CGRect, proxy: ChartProxy) -> some View {
        ChartScrubSurface(plot: plot, count: chart.closes.count,
                          cursorIndex: cursorIndex,
                          onScrub: scrubs ? { onScrub?($0) } : nil)
            .onTapGesture { point in
                guard let onTapMark, let nearest = nearestMark(to: point, plot: plot,
                                                               proxy: proxy) else { return }
                DSHaptic.selection()
                onTapMark(nearest)
            }
    }

    /// The mark nearest the tap, within a finger's reach — a 5pt circle is far
    /// under the 44pt floor, so the plot catches the tap and picks.
    private func nearestMark(to point: CGPoint, plot: CGRect,
                             proxy: ChartProxy) -> TokenChartMark? {
        let hits = marks.compactMap { mark -> (TokenChartMark, CGFloat)? in
            guard let x = proxy.position(forX: mark.x) else { return nil }
            return (mark, abs(plot.minX + x - point.x))
        }
        guard let nearest = hits.min(by: { $0.1 < $1.1 }), nearest.1 <= 22 else { return nil }
        return nearest.0
    }

    /// The event marks, and (when a handler exists) their tap target. Drawn in
    /// the plot's own ink at low opacity with a small solid core: punctuation
    /// on the line, never a second series competing with it.
    @ViewBuilder
    private func markLayer(proxy: ChartProxy, plot: CGRect) -> some View {
        ForEach(Array(marks.enumerated()), id: \.element.id) { i, mark in
            if let x = proxy.position(forX: mark.x),
               let y = proxy.position(forY: value(at: mark.x)) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .overlay {
                        Circle().stroke(accent.opacity(0.3), lineWidth: 4)
                    }
                    .position(x: plot.minX + x, y: plot.minY + y)
                    // The marks LAND (prd §171, 2026-07-22) — they wait for the
                    // line to finish drawing itself, then spring in left to
                    // right, in the order the money actually moved. Before
                    // this they simply existed inside the draw-on mask, which
                    // wasted the one beat where the line and the events it
                    // explains could be shown as cause and effect.
                    .scaleEffect(marksLanded ? 1 : 0.1)
                    .opacity(marksLanded ? 1 : 0)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.34, dampingFraction: 0.62)
                                   .delay(Double(i) * 0.05),
                               value: marksLanded)
                    .accessibilityLabel(mark.label)
            }
        }
        // The tap catcher lives on `interaction(plot:proxy:)` now — one
        // surface for taps and scrubbing alike, so the two can never be
        // stacked rectangles fighting for the same touch. This layer draws
        // the dots and nothing else.
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
    /// Which anatomy is coming (2026-08-16).
    ///
    /// The type's whole promise is "ghosts of the exact anatomy that's coming…
    /// so the layout never jumps", and under `hero: true` it was false: it drew
    /// a left-aligned 24pt ghost for a CENTRED 40pt price, no ghost at all for
    /// the chips row, the since-line or the plot's 18pt vertical padding. Every
    /// hero token sheet in the app jumped when the data arrived.
    var hero: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if hero {
                VStack(spacing: DS.Space.s2) {
                    ghost(width: 168, height: 44, radius: 8)   // price40's line box
                    ghost(width: 96, height: 24, radius: 12)   // the delta pill
                }
                .frame(maxWidth: .infinity)
                // The plot carries `.padding(.vertical, 18)` in the sheet, for
                // the high/low labels — so the ghost has to reserve it too.
                ghost(width: nil, height: plotHeight, radius: 8)
                    .padding(.vertical, 18)
                ghost(width: 132, height: 24, radius: 12)      // the range chips
                    .frame(maxWidth: .infinity)
                ghost(width: 104, height: 16, radius: 6)       // the read line
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: DS.Space.s2) {
                    ghost(width: 110, height: 24, radius: 6)
                    ghost(width: 72, height: 20, radius: 10)
                }
                ghost(width: nil, height: plotHeight, radius: 8)
                ghost(width: 104, height: 16, radius: 6)
            }
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
            // A loading skeleton stands for a fact that has not arrived, so it
            // has none to state. The chart it is standing in for announces
            // itself when it lands.
            .accessibilityHidden(true)
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
    /// Draw as the price OBJECT (prd §369 amendment, 2026-08-16) — one card
    /// carrying the asset, the figure, a freshness stamp and a sentence, with
    /// the curve underneath as its evidence.
    ///
    /// An option rather than the default: the Home row and the wallet tiles
    /// want the bare plot, and every existing call site is unchanged by this.
    /// nil keeps the classic/hero header stack exactly as it was.
    var object: (name: String?, symbol: String)? = nil
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
    /// The last curve actually drawn. Held so that switching range keeps the
    /// PLOT on screen while the new one loads (2026-08-16) — see `loaded`.
    @State private var lastDrawn: TokenChart?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(memoryKey: String, fetch: @escaping (R) async -> TokenChart?,
         since: (price: Double, date: Date)? = nil, hero: Bool = false,
         object: (name: String?, symbol: String)? = nil,
         @ViewBuilder fallback: @escaping () -> Fallback) {
        self.memoryKey = memoryKey
        self.fetch = fetch
        self.since = since
        self.hero = hero
        self.object = object
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
                TokenChartSkeleton(hero: hero)
            case .dead:
                fallback()
            default:
                loaded
            }
        }
        .task(id: range) { await load() }
        // A price read an hour ago is not the price (2026-08-16). The view
        // has no timer by design — a chart that polls is a chart that spends
        // somebody's battery to look busy — so the refresh rides the one
        // moment the number is about to be looked at again.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, charts[range] != nil else { return }
            charts[range] = nil
            Task { await load() }
        }
    }

    /// The curve on screen. Falls back to the last one drawn so that tapping a
    /// range does not delete the control you just tapped (2026-08-16).
    ///
    /// **The bug this fixes.** `load()` only sets `phase = .loading` when the
    /// cache is completely empty, so a range switch left `phase == .ready` with
    /// `charts[range] == nil` — which fell to the `else` below and rendered the
    /// SKELETON. The hero price, the delta pill and the range chips all
    /// vanished for the length of the fetch, so the person who tapped 7D lost
    /// the chips and could not tap back until the network answered.
    private var shown: TokenChart? { charts[range] ?? lastDrawn }

    /// True while the selected range has not answered yet and we are standing
    /// in with the previous curve.
    private var awaitingRange: Bool { charts[range] == nil && lastDrawn != nil }

    @ViewBuilder private var loaded: some View {
        if let chart = shown, let identity = object {
            PriceObjectCard(object: priceObject(chart, identity: identity)) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    plot(chart)
                        .opacity(awaitingRange ? 0.35 : 1)
                        .allowsHitTesting(!awaitingRange)
                        .animation(reduceMotion ? nil : DS.Motion.standard,
                                   value: awaitingRange)
                    chipsOrCoarseLabel(chart)
                        .frame(maxWidth: .infinity)
                    readLine(chart)
                    if let note {
                        Text(note)
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                }
            }
        } else if let chart = shown {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if hero { heroHeader } else { header(chart) }
                plot(chart)
                    // The stand-in curve belongs to the PREVIOUS range, so it
                    // is dimmed and cannot be scrubbed: its shape is no longer
                    // a claim about the selected window, and reading a value
                    // off it would be reading the wrong window's price.
                    .opacity(awaitingRange ? 0.35 : 1)
                    .allowsHitTesting(!awaitingRange)
                    .animation(reduceMotion ? nil : DS.Motion.standard,
                               value: awaitingRange)
                if hero { heroFooter(chart) }
                sinceWatchedLine(chart)
                readLine(chart)
                if let note {
                    Text(note)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
        } else {
            TokenChartSkeleton(hero: hero)
        }
    }

    /// The object this curve is about. Built here because this view is the one
    /// place that holds the chart, the selected window and the watch anchor
    /// together — so the card and its evidence can never describe different
    /// readings.
    private func priceObject(_ chart: TokenChart,
                             identity: (name: String?, symbol: String)) -> PriceObject {
        PriceObjectSource.object(
            name: identity.name, symbol: identity.symbol,
            closes: chart.closes, price: displayPrice, change: displayChange,
            // The window the FIGURE is about. While a range is still loading
            // the delta is withheld upstream, so this is never a label over
            // somebody else's number.
            window: range.label, fetchedAt: chart.fetchedAt,
            watched: since, coarse: chart.coarse)
    }

    /// When this price was read (2026-08-16, §83). Always drawn, never
    /// conditional on the answer being old: a freshness line that appears only
    /// when something is stale teaches people to read its ABSENCE as
    /// "current", which is the same overclaim one level up.
    @ViewBuilder private func readLine(_ chart: TokenChart) -> some View {
        Text(TokenChartStyle.readLine(chart.fetchedAt))
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity, alignment: hero ? .center : .leading)
            .accessibilityLabel(Text("Price \(TokenChartStyle.readLine(chart.fetchedAt))"))
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
    /// The price and its delta as ONE stop (2026-08-16).
    ///
    /// The figure carried no label at all, so VoiceOver read the raw glyphs and
    /// then the pill's raw text ("+4.2% · 1D") as a second, unrelated stop —
    /// two fragments of one sentence. The window is what makes the delta mean
    /// anything, so it is spoken WITH it rather than beside it.
    private var spokenPrice: String {
        let price = TokenChartStyle.priceText(displayPrice)
        guard !awaitingRange else { return price }
        let move = TokenChartStyle.isFlat(displayChange)
            ? String(localized: "unchanged")
            : String(localized: "\(TokenChartStyle.changeText(displayChange)) over \(range.label)")
        return "\(price), \(move)"
    }

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
            //
            // Hidden while the selected range is still loading: the PRICE is
            // range-independent and stays, but a delta is a claim about a
            // window, and labelling the old window's change with the new
            // window's name is a wrong reading rather than a missing one.
            if !awaitingRange {
                TokenDeltaPill(change: displayChange, label: range.label, solid: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenPrice))
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
            if !awaitingRange {
                TokenDeltaPill(change: displayChange, label: range.label)
            }
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
                    Text(r.label)
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
                .buttonStyle(PressSpring())
            }
        }
    }

    private func plot(_ chart: TokenChart) -> some View {
        // The breathing halo means LIVE and is now earned rather than assumed
        // (2026-08-16). `TokenChartPlot`'s own doc denied the Home row this
        // mark for overclaiming and let the sheet keep it because the sheet
        // "refetches per range" — which is a refetch on a chip tap, not on a
        // clock, so it sat over prices of any age. The quiet endpoint dot (the
        // pulse's twin, already in that file) carries the legibility job when
        // the read is no longer recent, so nothing is lost but the claim.
        let fresh = TokenChartStyle.isFresh(chart.fetchedAt)
        return TokenChartPlot(chart: chart, accent: accent,
                              pulses: fresh, endpointDot: !fresh)
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
            // ONE element that plays as an Audio Graph (2026-08-16), replacing
            // Swift Charts' default fallback of one element PER MARK — a 7d
            // curve read out as up to 168 stops of "t, 42, price, 0.0031",
            // with no summary and no trend. Nothing is lost by collapsing the
            // marks: the only way to interrogate a value here is the scrub,
            // which is a long-press-then-drag and was never reachable by
            // VoiceOver in the first place.
            .accessibilityElement()
            .accessibilityLabel(Text("Price over \(range.label)"))
            .accessibilityChartDescriptor(PriceChartDescriptor(
                closes: chart.closes, window: range.label))
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

            if !chart.coarse {
                ChartScrubSurface(plot: plot, count: closes.count,
                                  cursorIndex: scrubIndex,
                                  onScrub: { scrubIndex = $0 })
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
        if let cached = charts[range] {
            lastDrawn = cached
            phase = .ready
            replayReveal()
            return
        }
        if charts.isEmpty { phase = .loading }
        let fetched = await fetch(range)
        if let fetched {
            charts[range] = fetched
            lastDrawn = fetched
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
        note = "No \(range.label) prices here yet."
        noteRange = range
        // The DISPLAY steps back but the remembered preference stays — a
        // transient network failure at 7d must not permanently downgrade a
        // 7d watcher to 24h (the prd-51 invariant; review 2026-07-11).
        let back: R = charts[R.base] != nil ? R.base : (charts.keys.first ?? R.base)
        range = back   // task(id: range) refires and shows (or fetches) it
    }

    /// The draw-on wipe. Reduce Motion lands it drawn (2026-08-16).
    ///
    /// `GenValueSpark` has guarded this exact 0.7s easeOut mask since it was
    /// written and this copy never did — same duration, same curve, same
    /// effect, one guarded and one not. It slipped `design-motion-audit.py`
    /// because that check reads `onAppear`-triggered animations and carves out
    /// `withAnimation` inside an `async` func, and this is called from `load()`
    /// via `.task(id:)`. A real gap the lint is shaped not to see.
    private func replayReveal() {
        guard !reduceMotion else { revealed = true; return }
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
         object: (name: String?, symbol: String)? = nil,
         @ViewBuilder fallback: @escaping () -> Fallback) where R == TokenRange {
        self.init(memoryKey: "token.range.\(chain).\(address)",
                  fetch: { await TokenChart.fetch(chain: chain, address: address, range: $0) },
                  since: since, hero: hero, object: object, fallback: fallback)
    }
}

/// The scrub surface both charts share (2026-08-03, prd §297) — the sheet's
/// and `TokenChartPlot`'s, which had drifted into two byte-identical copies of
/// the same rectangle, the same index arithmetic and the same haptic policy.
/// Every fact below was measured once and is now stated once.
///
/// **Press, then drag.** Sequenced off a long press so a plain swipe still
/// belongs to whatever is scrolling: the sheet's own scroll view, and on the
/// feed both the vertical list AND the horizontal pager (the
/// DragGesture-vs-ScrollView law — a bare `DragGesture` in scroll content wins
/// outright and the surface stops scrolling).
///
/// **A cursor is not a finger.** Hover needs no press to disambiguate — there
/// is nothing to disambiguate from — so on Catalyst simply RESTING on the line
/// scrubs it (`ChartHoverScrub`, a no-op off Mac). The touch gesture stays
/// there too: a trackpad drag still works, and the two write the same state.
/// Hover takes NO haptic: it is continuous, and a tick per sample would buzz
/// the whole traverse.
///
/// `onScrub: nil` makes the whole thing inert but still hit-testable, so a
/// caller can hang its own tap on it (the plot's mark taps) without a second
/// rectangle competing for the same touch.
struct ChartScrubSurface: View {
    let plot: CGRect
    let count: Int
    /// What the caller currently shows, so a drag that lands on the same
    /// sample doesn't re-report it (and doesn't re-tick the haptic).
    let cursorIndex: Int?
    let onScrub: ((Int?) -> Void)?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(width: plot.width, height: plot.height)
            // BEFORE `.position`, deliberately: the hover's `.local` space is
            // then the rectangle's own bounds (0…width), not the overlay's.
            // The drag attaches AFTER `.position` and subtracts `plot.minX`
            // for exactly this reason.
            .modifier(ChartHoverScrub(count: count, width: plot.width,
                                      onScrub: { onScrub?($0) }))
            .position(x: plot.midX, y: plot.midY)
            .gesture(
                LongPressGesture(minimumDuration: 0.15)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard let onScrub, count > 1,
                              case .second(true, let drag) = value else { return }
                        let x = (drag?.location.x ?? plot.maxX) - plot.minX
                        let i = Int((x / max(plot.width, 1) * CGFloat(count - 1)).rounded())
                        let clamped = min(max(i, 0), count - 1)
                        if clamped != cursorIndex {
                            onScrub(clamped)
                            DSHaptic.selection()
                        }
                    }
                    .onEnded { _ in onScrub?(nil) },
                including: onScrub == nil ? .none : .all
            )
    }
}

/// Mac hover-scrub (delight, 2026-08-03) — the cursor half of
/// `ChartScrubSurface`. A cursor resting on the plot maps to the sample under
/// it; leaving reports nil. Compiles to a no-op off Catalyst, so touch builds
/// carry no hover plumbing.
struct ChartHoverScrub: ViewModifier {
    let count: Int
    let width: CGFloat
    let onScrub: (Int?) -> Void

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.onContinuousHover { phase in
            switch phase {
            case .active(let p):
                guard count > 1 else { return }
                let i = Int((p.x / max(width, 1) * CGFloat(count - 1)).rounded())
                onScrub(min(max(i, 0), count - 1))
            case .ended:
                onScrub(nil)
            }
        }
        #else
        content
        #endif
    }
}


/// The price curve as an Audio Graph (2026-08-16).
///
/// A separate `AXChartDescriptorRepresentable` value rather than a conformance
/// on `TokenChartView`: that view is generic over `R: PriceRange` AND carries a
/// `Fallback` view, so conforming it would drag both parameters into the
/// descriptor for no gain. This needs the closes and the window's name.
struct PriceChartDescriptor: AXChartDescriptorRepresentable {
    let closes: [Double]
    let window: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Time"),
            range: 0...Double(max(closes.count - 1, 1)),
            gridlinePositions: []) { position in
                String(localized: "point \(Int(position) + 1)")
            }
        let low = closes.min() ?? 0
        let high = closes.max() ?? 0
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Price"),
            // Never zero-width: a perfectly flat curve would give the graph
            // nothing to sweep, which plays as silence and reads as broken.
            range: low...max(high, low + .leastNonzeroMagnitude),
            gridlinePositions: []) { TokenChartStyle.priceText($0) }
        let points = closes.enumerated().map { index, close in
            AXDataPoint(x: Double(index), y: close)
        }
        return AXChartDescriptor(
            title: String(localized: "Price over \(window)"),
            summary: nil,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            // Continuous: this is a line, and telling the graph otherwise
            // plays it as unrelated readings rather than one movement.
            series: [AXDataSeriesDescriptor(name: "", isContinuous: true,
                                            dataPoints: points)])
    }
}
