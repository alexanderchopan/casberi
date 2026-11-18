import Charts
import SwiftUI

/// **THE WATCHLIST'S BOX: EVERY TOKEN SIDE BY SIDE (2026-11-01, user: "in the
/// header it just says 2 tokens you watch … we could have a visualization";
/// of the mockups, "lets go with E").** The first five watched tokens
/// (`WatchlistRules.charted`), each window drawn as the percent it is from
/// where it began, one line each on one scale, so a line above another did
/// better. No line marks zero (no hairlines) and no tint marks up or down
/// (prd §1863). The column on the right names each line and its
/// change; a tap opens that token. The windows sit under it as a token's own
/// boxed chart has them.
///
/// Nothing it cannot read: a token with no window is left out, and with none
/// at all the box keeps its count.
struct WatchlistCompareChart: View {
    /// The tokens the box draws, in the list's order: their places pick the hues.
    let tokens: [WatchedToken]
    /// The count and caption the box falls back to with no line to draw.
    let count: Int
    let caption: String
    let onOpen: (WatchedToken) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range: TokenRange = TokenChartStyle.rememberedRange(key: Self.memoryKey)
    /// Each id's window as percents, and which ids and range they were read for.
    @State private var series: [String: [Double]] = [:]
    @State private var readFor: String?

    private static let memoryKey = "watch.range.compare"
    private static let labelColumn: CGFloat = 92

    private var readKey: String { range.rawValue + "|" + tokens.map(\.id).joined(separator: ",") }

    private struct Line: Identifiable {
        let token: WatchedToken
        let values: [Double]
        let hue: Color
        var id: String { token.id }
        var last: Double { values.last ?? 0 }
    }

    private var lines: [Line] {
        tokens.enumerated().compactMap { i, t in
            guard let values = series[t.id], !values.isEmpty else { return nil }
            let base = Color(hex: WatchlistRules.lineHues[i % WatchlistRules.lineHues.count])
            return Line(token: t, values: values, hue: scheme == .light ? base.mix(with: .black, by: 0.35) : base)
        }
    }

    var body: some View {
        let lines = lines
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if lines.isEmpty {
                if readFor == nil {
                    DSSpinner().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DSFigureReading(number: "\(count)", caption: caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                let domain = Self.domain(lines)
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    plot(lines, domain: domain)
                    labels(lines, domain: domain)
                        .frame(width: Self.labelColumn)
                }
                .frame(maxHeight: .infinity)
            }
            rangeChips
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: readKey) { await read() }
    }

    /// The windows through the one template (prd §1863): words at the
    /// reading size, the pick in the primary ink, as the Wallet's Week ·
    /// Month and Yours · Following · All read. It was a hand-rolled copy of a
    /// token chart's small capsules.
    private var rangeChips: some View {
        DSRangeChips(ranges: TokenRange.allCases, range: range, label: { $0.label },
                     slim: true, reads: true) { r in
            range = r
            TokenChartStyle.remember(r, key: Self.memoryKey)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The scale every line shares: zero always in it, a little air past the
    /// highest and the lowest.
    private static func domain(_ lines: [Line]) -> ClosedRange<Double> {
        let all = lines.flatMap(\.values)
        let hi = max(all.max() ?? 0, 0), lo = min(all.min() ?? 0, 0)
        let pad = max((hi - lo) * 0.08, 0.05)
        return (lo - pad)...(hi + pad)
    }

    private func plot(_ lines: [Line], domain: ClosedRange<Double>) -> some View {
        Chart {
            // No green and red halves (prd §1863): the lines and their
            // labels say up and down; a box under them read as two panels.
            ForEach(lines) { line in
                ForEach(Array(line.values.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", Double(i) / Double(max(line.values.count - 1, 1))),
                             y: .value("percent", v),
                             series: .value("token", line.id))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(line.hue)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
                PointMark(x: .value("t", 1.0), y: .value("percent", line.last))
                    .foregroundStyle(line.hue)
                    .symbolSize(30)
            }
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .animation(reduceMotion ? nil : DS.Motion.glide, value: readFor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lines.map { "\($0.token.symbol) \(WatchlistRules.change($0.last).words)" }
            .joined(separator: ", ")))
    }

    /// Each line's name and change beside where it ends, pushed apart where
    /// two would touch (`WatchlistRules.labelCenters`).
    private func labels(_ lines: [Line], domain: ClosedRange<Double>) -> some View {
        let quotes = WatchlistPrices.shared.quotes
        return GeometryReader { geo in
            let h = geo.size.height
            let span = domain.upperBound - domain.lowerBound
            let wanted = lines.map { (domain.upperBound - $0.last) / span * h }
            let centers = WatchlistRules.labelCenters(wanted, gap: 18, lo: 9, hi: max(h - 9, 9))
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                let change = WatchlistRules.change(Self.dayFigure(line, range: range, quotes: quotes))
                Button {
                    DSHaptic.selection()
                    onOpen(line.token)
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: line.token.symbol).foregroundStyle(line.hue)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(verbatim: change.words)
                            .foregroundStyle(change.tone == .up ? DS.confirmInk
                                             : change.tone == .down ? DS.destructiveInk : DS.textSecondary)
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .dsText(.label12)
                    .frame(width: geo.size.width, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .position(x: geo.size.width / 2, y: centers[i])
            }
        }
    }

    /// **ONE DAY, ONE FIGURE (prd §1863).** On 1D the label says the
    /// quote's day, the figure the token's row and Home's watchlist row say;
    /// the window's own start drew "+1.5%" over a row's "+2.1%". Every other
    /// window is the line's own change.
    private static func dayFigure(_ line: Line, range: TokenRange, quotes: [String: WatchlistRules.Quote]) -> Double {
        guard range == .day, let day = quotes[line.token.id]?.change else { return line.last }
        return day
    }

    private func read() async {
        let key = readKey
        let ids = tokens.map(\.id)
        var closes: [String: [Double]] = [:]
        if DemoMode.isActive {
            // The demo reaches nothing (§217): its own invented curves.
            for id in ids { closes[id] = WatchlistPrices.demoChart(id: id, range: range)?.closes }
        } else {
            closes = await WatchlistPrices.charts(ids: ids, range: range)
        }
        guard !Task.isCancelled, key == readKey else { return }
        series = closes.mapValues(WatchlistRules.percentSeries).filter { !$0.value.isEmpty }
        readFor = key
    }
}
