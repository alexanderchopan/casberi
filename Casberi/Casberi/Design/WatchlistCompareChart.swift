import Charts
import SwiftUI

/// **THE WATCHLIST'S BOX: EVERY TOKEN SIDE BY SIDE (2026-11-01, user: "in the
/// header it just says 2 tokens you watch … we could have a visualization";
/// of the mockups, "lets go with E").** The first five watched tokens
/// (`WatchlistRules.charted`), each window drawn as the percent it is from
/// where it began, one line each on one scale, so a line above another did
/// better. Up from the start is a faint green, down a faint red, and no line
/// marks zero (no hairlines). The column on the right names each line and its
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

    /// The windows as a token's own boxed chart draws them (`TokenChartView`'s
    /// `rangeChips`): small words, the pick on a faint capsule, so the
    /// Watchlist's box and a token's read as one.
    private var rangeChips: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(TokenRange.allCases, id: \.self) { r in
                Button {
                    guard r != range else { return }
                    DSHaptic.tap()
                    range = r
                    TokenChartStyle.remember(r, key: Self.memoryKey)
                } label: {
                    Text(r.label)
                        .dsText(.label12)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(r == range ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(r == range ? DS.fillFaint : .clear, in: Capsule(style: .continuous))
                        .animation(DS.Motion.standard, value: r == range)
                }
                .buttonStyle(PressSpring())
                .accessibilityAddTraits(r == range ? .isSelected : [])
            }
        }
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
            RectangleMark(xStart: .value("start", 0.0), xEnd: .value("end", 1.0),
                          yStart: .value("from", 0.0), yEnd: .value("to", domain.upperBound))
                .foregroundStyle(TokenChartStyle.accent(up: true, scheme: scheme).opacity(0.07))
            RectangleMark(xStart: .value("start", 0.0), xEnd: .value("end", 1.0),
                          yStart: .value("from", domain.lowerBound), yEnd: .value("to", 0.0))
                .foregroundStyle(TokenChartStyle.accent(up: false, scheme: scheme).opacity(0.07))
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
        GeometryReader { geo in
            let h = geo.size.height
            let span = domain.upperBound - domain.lowerBound
            let wanted = lines.map { (domain.upperBound - $0.last) / span * h }
            let centers = WatchlistRules.labelCenters(wanted, gap: 18, lo: 9, hi: max(h - 9, 9))
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                let change = WatchlistRules.change(line.last)
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
