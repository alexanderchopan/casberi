#if !targetEnvironment(macCatalyst)
import WidgetKit
import SwiftUI
import ActivityKit

/// One followed price on the Lock Screen and in the Dynamic Island (prd
/// §1247): the symbol, the price this app last read, the day's move and the
/// day's line. See `PriceActivityAttributes` and `PriceLive` for why it says
/// its age: there is no push server, so past `PriceLive.stampAfter` — the
/// activity's stale date, which iOS flips while the app sleeps — it reads
/// "as of 3:42 PM" rather than passing an old price off as now's (§83).
struct PriceActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PriceActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: context.attributes.symbol)
                        .dsText(.widgetChrome15)
                        .lineLimit(1)
                    Text(verbatim: context.attributes.name)
                        .dsText(.widgetSubline12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let spark = spark(context.state) {
                    WidgetSpark(normalized: spark)
                        .stroke(tone(context.state),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                                   dash: direction(context.state) < 0 ? [3, 2] : []))
                        .frame(width: 64, height: 20)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: WidgetWatch.priceText(context.state.price))
                        .dsText(.widgetChrome15)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let stamp = PriceLive.stampText(at: context.state.at, now: .now,
                                                       stale: context.isStale) {
                        Text(stamp)
                            .dsText(.widgetTimer13)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let change = context.state.change {
                        Text(verbatim: MoneyFormat.percentLabel(change * 100))
                            .dsText(.widgetTimer13)
                            .foregroundStyle(tone(context.state))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .fixedSize()
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spoken(context)))
            .widgetURL(URL(string: "casberi://thing/\(context.attributes.thingID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(verbatim: context.attributes.symbol)
                        .dsText(.widgetChrome15)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: WidgetWatch.priceText(context.state.price))
                        .dsText(.widgetChrome15)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        if let spark = spark(context.state) {
                            WidgetSpark(normalized: spark)
                                .stroke(tone(context.state),
                                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                           lineJoin: .round,
                                                           dash: direction(context.state) < 0 ? [3, 2] : []))
                                .frame(height: 18)
                        }
                        Text(PriceLive.stampText(at: context.state.at, now: .now, stale: context.isStale)
                             ?? context.state.change.map { MoneyFormat.percentLabel($0 * 100) } ?? "")
                            .dsText(.widgetTimer13)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            } compactLeading: {
                Text(verbatim: context.attributes.symbol)
                    .dsText(.widgetTimer13)
                    .lineLimit(1)
            } compactTrailing: {
                // The price, not its age: a compact slot fits one thing. The
                // age is on the Lock Screen and in the expanded island.
                Text(verbatim: WidgetWatch.priceText(context.state.price))
                    .dsText(.widgetTimer13)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(context.isStale ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : tone(context.state))
            } minimal: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(tone(context.state))
            }
            .widgetURL(URL(string: "casberi://thing/\(context.attributes.thingID)"))
        }
    }

    /// The day's line as 0…1, or nil for none.
    private func spark(_ state: PriceActivityAttributes.ContentState) -> [Double]? {
        guard let closes = state.closes, closes.count >= 2 else { return nil }
        return WidgetCurve.normalized(closes)
    }

    /// The move's direction; zero when it rounds to flat (§83).
    private func direction(_ state: PriceActivityAttributes.ContentState) -> Int {
        guard let change = state.change else { return 0 }
        let pct = change * 100
        return MoneyFormat.isFlatPercent(pct) ? 0 : (pct > 0 ? 1 : -1)
    }

    private func tone(_ state: PriceActivityAttributes.ContentState) -> AnyShapeStyle {
        switch direction(state) {
        case 1: AnyShapeStyle(WidgetChrome.gain)
        case -1: AnyShapeStyle(WidgetChrome.loss)
        default: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    private func spoken(_ context: ActivityViewContext<PriceActivityAttributes>) -> String {
        var parts = [context.attributes.name, WidgetWatch.priceText(context.state.price)]
        if let change = context.state.change { parts.append(MoneyFormat.percentLabel(change * 100)) }
        if let stamp = PriceLive.stampText(at: context.state.at, now: .now, stale: context.isStale) {
            parts.append(stamp)
        }
        return parts.joined(separator: ", ")
    }
}
#endif
