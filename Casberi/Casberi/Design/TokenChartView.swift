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

    static func priceText(_ p: Double) -> String {
        if p >= 1 { return String(format: "$%.2f", p) }
        if p >= 0.01 { return String(format: "$%.4f", p) }
        return String(format: "$%.8f", p)
    }

    static func changeText(_ c: Double) -> String {
        String(format: "%@%.1f%%", c >= 0 ? "+" : "", c * 100)
    }

    /// The chosen range persists per token (prd 51) — a 7d watcher isn't
    /// reset to 24h on every open.
    static func rememberedRange(chain: String, address: String) -> TokenRange {
        UserDefaults.standard.string(forKey: "token.range.\(chain).\(address)")
            .flatMap(TokenRange.init(rawValue:)) ?? .day
    }
    static func remember(_ range: TokenRange, chain: String, address: String) {
        UserDefaults.standard.set(range.rawValue, forKey: "token.range.\(chain).\(address)")
    }
}

/// The signed percent in a state-fill capsule, naming its window:
/// "−1.8% · 24h". The fill is the kind-pill grammar (color at low opacity);
/// the number still carries the sign, so color is never the only voice.
struct TokenDeltaPill: View {
    let change: Double
    let label: String
    /// The Home row's smaller dose.
    var compact: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = TokenChartStyle.accent(up: change >= 0, scheme: scheme)
        Text("\(TokenChartStyle.changeText(change)) · \(label)")
            .dsText(compact ? .label12 : .subhead13)
            .monospacedDigit()
            .foregroundStyle(ink)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 2 : 3)
            .background(ink.opacity(scheme == .light ? 0.12 : 0.15),
                        in: Capsule(style: .continuous))
    }
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
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart(Array(chart.closes.enumerated()), id: \.offset) { i, close in
            LineMark(x: .value("t", i), y: .value("price", close))
                .interpolationMethod(chart.coarse ? .linear : .catmullRom)
                .foregroundStyle(accent)
            AreaMark(x: .value("t", i), y: .value("price", close))
                .interpolationMethod(chart.coarse ? .linear : .catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(0.22), accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
            if chart.coarse {
                PointMark(x: .value("t", i), y: .value("price", close))
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
                   let x = proxy.position(forX: chart.closes.count - 1),
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
            }
        }
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

/// The sheet's full chart — the token's "media" (ThingContent rule). Owns
/// its fetches (one per range, cached per visit), the draw-on reveal (a
/// range switch is a data arrival — the one moment animation belongs to),
/// touch scrubbing (press, then drag; the header rolls to the scrubbed
/// value, the finger carries only the when), and per-token range memory.
/// The dead-token case (no price anywhere) renders the caller's fallback —
/// the plain link, honestly.
struct TokenChartView<Fallback: View>: View {
    let chain: String
    let address: String
    @ViewBuilder let fallback: () -> Fallback

    private enum Phase { case loading, ready, dead }

    @State private var range: TokenRange
    @State private var charts: [TokenRange: TokenChart] = [:]
    @State private var phase: Phase = .loading
    /// One honest line when a range has no candles ("No 7d prices…") —
    /// the selection reverts rather than faking a curve or blanking.
    @State private var note: String?
    @State private var revealed = false
    @State private var scrubIndex: Int?
    @Environment(\.colorScheme) private var scheme

    init(chain: String, address: String,
         @ViewBuilder fallback: @escaping () -> Fallback) {
        self.chain = chain
        self.address = address
        self.fallback = fallback
        _range = State(initialValue: TokenChartStyle.rememberedRange(chain: chain,
                                                                     address: address))
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
        TokenChartStyle.accent(up: displayChange >= 0, scheme: scheme)
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
                header(chart)
                plot(chart)
                if let note {
                    Text(note)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
        } else {
            TokenChartSkeleton()
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
            if chart.coarse {
                // The fallback says what it is — and offers no ranges
                // (7d on five points would be a fake control).
                Text("24h · 5 price points")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            } else {
                rangeChips
            }
        }
    }

    private var rangeChips: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(TokenRange.allCases, id: \.self) { r in
                Button {
                    guard r != range else { return }
                    DSHaptic.tap()
                    scrubIndex = nil
                    range = r
                    TokenChartStyle.remember(r, chain: chain, address: address)
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
               let xH = proxy.position(forX: iH), let yH = proxy.position(forY: hi),
               let xL = proxy.position(forX: iL), let yL = proxy.position(forY: lo) {
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
               let x = proxy.position(forX: i),
               let y = proxy.position(forY: closes[i]) {
                Capsule(style: .continuous)
                    .fill(DS.textTertiary.opacity(0.5))
                    .frame(width: 2, height: plot.height - 8)
                    .position(x: plot.minX + x, y: plot.midY)
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .position(x: plot.minX + x, y: plot.minY + y)
                Text(agoText(index: i, of: closes.count))
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
                    .position(x: min(max(plot.minX + x, plot.minX + 28), plot.maxX - 28),
                              y: plot.minY - 9)
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

    /// "9h ago" / "3d ago" / "now" — the scrubbed candle's distance.
    private func agoText(index: Int, of count: Int) -> String {
        let ago = Double(count - 1 - index) * range.step
        if ago < 1 { return "now" }
        if ago < 86_400 { return "\(Int(ago / 3600))h ago" }
        return "\(Int(ago / 86_400))d ago"
    }

    /// The range whose failure produced the current note — lets the note
    /// survive exactly one revert fetch (see load()'s success path).
    @State private var noteRange: TokenRange?

    private func load() async {
        if charts[range] != nil {
            phase = .ready
            replayReveal()
            return
        }
        if charts.isEmpty { phase = .loading }
        let fetched = await TokenChart.fetch(chain: chain, address: address, range: range)
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
        if range == .day {
            // 24h has the Dexscreener fallback behind it — nothing at all
            // means the token is dead/illiquid: the plain link, honestly.
            phase = .dead
            return
        }
        // The token charts 24h but GeckoTerminal has no candles at this
        // window — say so and step back rather than fake a curve or
        // strand the card on an empty selection.
        note = "No \(range.rawValue) prices for this token yet."
        noteRange = range
        // The DISPLAY steps back but the remembered preference stays — a
        // transient network failure at 7d must not permanently downgrade a
        // 7d watcher to 24h (the prd-51 invariant; review 2026-07-11).
        let back: TokenRange = charts[.day] != nil ? .day : (charts.keys.first ?? .day)
        range = back   // task(id: range) refires and shows (or fetches) it
    }

    private func replayReveal() {
        revealed = false
        withAnimation(.easeOut(duration: 0.7)) { revealed = true }
    }
}
