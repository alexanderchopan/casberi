import WidgetKit
import SwiftUI

/// The wallet line, on the Home Screen (2026-08-14, prd §382).
///
/// It draws `WalletStore.combinedValueSamples()` — the app's OWN series, the
/// forward-only, never-back-filled, alignment-guarded one the balance card
/// draws (§77) — published by `WidgetPublish`. Not a re-derivation: the tile
/// and the card can never disagree about history because there is one series.
///
/// FOUR HONESTY RAILS, none of them optional, all of them things this tile
/// would look perfectly fine without:
///
///  1. **A flat curve draws down the MIDDLE, never along the floor.** The naive
///     normalization divides by a range that is zero for a flat series, and the
///     naive guard against that returns 0 — which draws a wallet that did
///     nothing as a wallet that went to zero. `WidgetWalletLine.normalizedPoints`
///     owns this, with a test (`AgentPanel` has carried the same rule since §334).
///  2. **A change that rounds to zero has no direction** — no sign, no colour
///     (`MoneyFormat.isFlatPercent`, mirroring `TokenChartStyle.isFlat`).
///  3. **A reading old enough to matter says so.** Wallet sampling is throttled
///     to one point per four hours, so a stamp appears only past that — past
///     which "$12,480" and "$12,480, as of yesterday" are different claims.
///  4. **Hide wallet balances (§374) keeps the SHAPE and loses the FIGURES**, and
///     the figures are not merely masked here — they were never published (see
///     `WidgetWalletLine.hidden`). A Home Screen is the most stood-next-to
///     surface the OS has, which is precisely the threat §374 exists for.
struct WalletWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWallet.kind, provider: WalletProvider()) { entry in
            WalletWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Wallet")
        .description("What your followed addresses are worth.")
        // The small tile only (prd §1210): every Casberi widget is one size.
        .supportedFamilies([.systemSmall])
    }
}

struct WalletEntry: TimelineEntry {
    let date: Date
    /// The week's money in against money out (2026-08-14, prd §382b) — the
    /// question the curve raises and cannot settle. nil when the band declined,
    /// which `WalletFlow.band` does on an unpriceable window, on fewer than two
    /// lanes, and on lanes too thin to draw honestly.
    var flow: WidgetFlowBand?
    /// nil when there is no watched wallet, or fewer than two aligned samples
    /// across the ones there are — in which case the tile declines rather than
    /// inventing a flat line out of one point.
    let line: WidgetWalletLine?

    /// A wallet tile is a STATE, not news (§216), so it never asks for
    /// promotion the way something arriving does. It asks for a little more
    /// when the reading is fresh than when it is a day old and stamped.
    var relevance: TimelineEntryRelevance? {
        guard let line else { return TimelineEntryRelevance(score: 0) }
        let stale = date.timeIntervalSince(line.asOf) > WidgetWallet.stampAfter
        return TimelineEntryRelevance(score: stale ? 15 : 40)
    }
}

struct WalletProvider: TimelineProvider {
    func placeholder(in context: Context) -> WalletEntry {
        WalletEntry(date: .now, flow: nil, line: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WalletEntry) -> Void) {
        completion(WalletEntry(date: .now, flow: WidgetWallet.flow(),
                               line: WidgetWallet.published()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalletEntry>) -> Void) {
        let now = Date.now
        // Hourly, and the app reloads this kind itself the moment a new sample
        // lands. The hour is what moves the STAMP forward on a phone whose owner
        // hasn't opened the app: the figure stays put, the "as of" grows, which
        // is the pair being honest together.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: [WalletEntry(date: now, flow: WidgetWallet.flow(now: now),
                                                  line: WidgetWallet.published(now: now))],
                            policy: .after(next)))
    }
}

struct WalletWidgetView: View {
    let entry: WalletEntry

    var body: some View {
        Group {
            if let line = entry.line {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetLabel(text: String(localized: "Wallet"))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(figure)
                            .dsText(.widgetFigure24)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let change = changeText {
                            Text(change)
                                .dsText(.widgetSubline12)
                                .foregroundStyle(changeInk)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    }
                    if let stamp = WidgetStamp.text(for: line.asOf, now: entry.date,
                                                    after: WidgetWallet.stampAfter) {
                        Text(stamp)
                            .dsText(.widgetSubline11)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let flow = entry.flow {
                        WidgetFlowLanes(band: flow)
                        if let note = pricedNote(flow) {
                            Text(note)
                                .dsText(.widgetSubline11)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    WidgetSpark(normalized: line.normalizedPoints)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                           lineJoin: .round))
                        .frame(height: sparkHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                declined
            }
        }
        .widgetURL(URL(string: "casberi://feed/source/Wallet"))
    }

    /// The figure, the mask, or nothing.
    ///
    /// `total` is nil for exactly one reason — §374 withheld it — because a line
    /// with no last point is never published at all. So nil here means hidden,
    /// and the mask is what says so: never "$0" and never blank, both of which
    /// already mean something else in this app's wallet (§374 rule 2).
    private var figure: String {
        guard let line = entry.line else { return "" }
        guard let total = line.total else { return WidgetMask.figure }
        return MoneyFormat.compactUSD(total)
    }

    private var changeText: String? {
        guard let pct = entry.line?.changePct else { return nil }
        return MoneyFormat.percentLabel(pct)
    }

    /// Flat gets no colour, which is the §83 corollary in ink: a change that
    /// rounds to zero has no direction, so it may not be painted as a gain.
    private var changeInk: Color {
        guard let pct = entry.line?.changePct else { return .secondary }
        if MoneyFormat.isFlatPercent(pct) { return .secondary }
        return pct > 0 ? WidgetChrome.gain : WidgetChrome.loss
    }

    /// "6 of 9 priced" — the sentence for `WidgetFlowBand.owesDisclosure`.
    ///
    /// Written HERE rather than in the payload because that file compiles into
    /// the app and the share extension too, and a widget-only sentence declared
    /// there lands in all three string catalogs where two of them can never
    /// show it.
    private func pricedNote(_ band: WidgetFlowBand) -> String? {
        guard band.owesDisclosure else { return nil }
        return String(localized: "\(band.priced) of \(band.total) priced")
    }

    /// The curve gives up height to the lanes, and to the disclosure under
    /// them, so the tile keeps every reading rather than clipping one.
    private var sparkHeight: CGFloat {
        guard let flow = entry.flow else { return 34 }
        return flow.owesDisclosure ? 14 : 20
    }

    /// Two causes, one sentence — and it names the ACTION rather than the
    /// fault, because both causes have the same fix and neither is a bug.
    private var declined: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetLabel(text: String(localized: "Wallet"))
            Text("Follow an address in Casberi")
                .dsText(.widgetSubline12)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
