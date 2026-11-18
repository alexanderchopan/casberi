import WidgetKit
import SwiftUI

/// The Wallet tile (prd §1881, amends §1210 item 2): Home's balance, its day,
/// and Public and Private as Home heads them. Small tile only.
///
/// It draws `WidgetWalletHome`, which Home itself publishes from the figures it
/// prints, so the tile and Home can never state two totals (the tile drew the
/// followed addresses' line before, a different sum from Home's).
struct WalletWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWallet.kind, provider: WalletProvider()) { entry in
            WalletWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Wallet")
        .description("Your balance, public and private.")
        .supportedFamilies([.systemSmall])
    }
}

struct WalletEntry: TimelineEntry {
    let date: Date
    let home: WidgetWalletHome?

    /// Smart Stack ranking: a fresh balance is worth surfacing, a stamped
    /// one less so, none not at all.
    var relevance: TimelineEntryRelevance? {
        guard let home else { return TimelineEntryRelevance(score: 0) }
        let stale = date.timeIntervalSince(home.asOf) > WidgetWallet.stampAfter
        return TimelineEntryRelevance(score: stale ? 15 : 40)
    }
}

struct WalletProvider: TimelineProvider {
    func placeholder(in context: Context) -> WalletEntry {
        WalletEntry(date: .now, home: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WalletEntry) -> Void) {
        completion(WalletEntry(date: .now, home: WidgetWallet.published()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalletEntry>) -> Void) {
        // The app reloads this kind whenever Home's figures change; the hourly
        // ask is only so the stamp moves on and a stale reading retires.
        let now = Date.now
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: [WalletEntry(date: now, home: WidgetWallet.published(now: now))],
                            policy: .after(next)))
    }
}

struct WalletWidgetView: View {
    let entry: WalletEntry

    var body: some View {
        Group {
            if let home = entry.home {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetLabel(text: String(localized: "Wallet"))
                    Text(verbatim: home.total.map(MoneyFormat.compactUSD) ?? WidgetMask.figure)
                        .dsText(.widgetFigure24)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .privacySensitive()
                    // A reading past the normal cadence says when it was read,
                    // in the day's place (Home does the same, §825, §1593).
                    if let stamp = WidgetStamp.text(for: home.asOf, now: entry.date,
                                                    after: WidgetWallet.stampAfter) {
                        Text(stamp)
                            .dsText(.widgetSubline12)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let pct = home.dayPct {
                        Text("\(MoneyFormat.percentLabel(pct)) today")
                            .dsText(.widgetSubline12)
                            .foregroundStyle(ink(pct))
                            .monospacedDigit()
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    Spacer(minLength: 4)
                    side(String(localized: "Public"), home.publicUSD, hidden: home.hidden)
                    side(String(localized: "Private"), home.privateUSD, hidden: home.hidden)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                declined
            }
        }
        .widgetURL(URL(string: "casberi://home"))
    }

    /// One of Home's two sections, its name and its head. A side Home draws
    /// none of is left out; a withheld one reads as hidden, never as zero
    /// (§374 rule 2).
    @ViewBuilder
    private func side(_ name: String, _ usd: Double?, hidden: Bool) -> some View {
        if hidden || usd != nil {
            HStack(spacing: 6) {
                Text(name)
                    .dsText(.widgetSubline12)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: usd.map(MoneyFormat.compactUSD) ?? WidgetMask.figure)
                    .dsText(.widgetTitle14)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }

    /// A change that rounds to zero has no colour (§83).
    private func ink(_ pct: Double) -> Color {
        if MoneyFormat.isFlatPercent(pct) { return .secondary }
        return pct > 0 ? WidgetChrome.gain : WidgetChrome.loss
    }

    private var declined: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetLabel(text: String(localized: "Wallet"))
            Text("Open Casberi to see your balance")
                .dsText(.widgetSubline12)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
