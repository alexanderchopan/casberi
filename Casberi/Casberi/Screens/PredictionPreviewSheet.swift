import SwiftUI
import SwiftData

/// A market from the live book, read BEFORE it's followed (prd §234).
///
/// The gesture split this exists to serve: in the room, tapping an outcome
/// row used to FOLLOW it — a silent write on the one gesture that means
/// "look at this" everywhere else in the app (a row is a read with one
/// gesture, ruling 2026-07-16). Worse, it left no way to inspect a market
/// at all: the only affordance available committed you. Now the row's tap
/// opens this, and an explicit Follow capsule does the writing.
///
/// Venue-neutral by construction — it carries what both exchanges can
/// answer, plus the one thing only Polymarket can (a real price curve,
/// which `PolymarketMarketView` draws and `KalshiMarketView` deliberately
/// refuses to fake, prd §51).
struct PredictionPreview: Identifiable, Equatable {
    let source: PredictionSource
    /// The bridge-local id — a Kalshi ticker or a Polymarket condition id.
    let marketID: String
    let title: String
    /// The outcome's own name within its event ("Kansas City", "Newsom") —
    /// empty for a plain binary market, where the title carries the question.
    let outcome: String
    let probability: Double
    let previousProbability: Double?
    /// Which window `previousProbability` reaches back to — the two
    /// exchanges genuinely differ (Kalshi's previous CLOSE, Polymarket's
    /// one-week change), so the pill says which rather than implying both
    /// are the same measurement.
    let deltaLabel: String
    let closeTime: Date?
    let isThin: Bool
    /// Polymarket only — the CLOB token id its price history is keyed on.
    let yesTokenId: String?

    /// What it takes to actually follow this — a bridge-specific payload,
    /// since the two `add` paths take different shapes. Exactly the shape
    /// `PredictionTwin.Offer` already uses for the same reason.
    let kalshi: KalshiWatch.Resolved?
    let polymarket: PolymarketBridge.Resolved?

    var id: String { "\(source.refPrefix):\(marketID)" }

    static func == (a: PredictionPreview, b: PredictionPreview) -> Bool { a.id == b.id }

    init(kalshi m: KalshiWatch.Resolved) {
        source = .kalshi
        marketID = m.ticker
        title = m.title
        outcome = m.subtitle
        probability = m.probability
        previousProbability = m.previousProbability
        deltaLabel = String(localized: "vs last close")
        closeTime = m.closeTime
        isThin = m.isThin
        yesTokenId = nil
        kalshi = m
        polymarket = nil
    }

    init(polymarket m: PolymarketBridge.Resolved) {
        source = .polymarket
        marketID = m.conditionId
        title = m.eventTitle.isEmpty ? m.title : m.title
        outcome = m.subtitle
        probability = m.probability
        previousProbability = m.previousProbability
        deltaLabel = String(localized: "vs last week")
        closeTime = m.closeTime
        isThin = m.isThin
        yesTokenId = m.yesTokenId
        kalshi = nil
        polymarket = m
    }
}

/// Following, from either venue's payload — the one place the preview
/// sheet, the row capsule and any future caller share, so "what happens
/// when you follow" has exactly one answer.
@MainActor
enum PredictionFollow {
    @discardableResult
    static func follow(_ preview: PredictionPreview, store: BridgeStore,
                       context: ModelContext) -> Thing? {
        if let m = preview.kalshi, let thing = KalshiWatch.add(m, context: context) {
            registerPredictionBridge(source: "Kalshi", id: "kalshi", store: store, context: context)
            return thing
        }
        if let m = preview.polymarket, let thing = PolymarketBridge.add(m, context: context) {
            registerPredictionBridge(source: "Polymarket", id: "polymarket", store: store, context: context)
            return thing
        }
        return nil
    }
}

struct PredictionPreviewSheet: View {
    let preview: PredictionPreview

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var curve: [Double] = []
    @State private var followed = false

    private var delta: Double? {
        preview.previousProbability.map { preview.probability - $0 }
    }

    /// Already in the corpus? Then the sheet offers the read, not the verb —
    /// a market can be reached here from the book while its row is still on
    /// screen from a previous load.
    private var alreadyFollowed: Bool {
        followed || IngestSupport.hasSourceRef(modelContext, source: preview.source.rawValue,
                                               ref: "\(preview.source.refPrefix):\(preview.marketID)")
    }

    var body: some View {
        DSTray(title: preview.source.rawValue, height: 560) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(preview.title)
                    .dsText(.heading22).foregroundStyle(DS.textPrimary)

                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text("\(Int((preview.probability * 100).rounded()))%")
                        .dsText(.heading34).monospacedDigit()
                        // A thin book's number is treated gently everywhere it
                        // appears (§83 ②) — same rule as the room's cards.
                        .foregroundStyle(preview.isThin ? DS.textSecondary : DS.textPrimary)
                    if let delta {
                        TokenDeltaPill(change: delta, label: preview.deltaLabel, points: true)
                    }
                }

                if !preview.outcome.isEmpty {
                    Text("Odds \(preview.outcome) wins")
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                }

                PredictionOddsBar(probability: preview.probability,
                                  previous: preview.previousProbability)
                    .frame(height: 10)

                // The curve only Polymarket can serve. Absent for Kalshi by
                // ruling, not by omission — its candlestick data is too thin
                // to draw honestly, and a fallback stops pretending (§51).
                //
                // The one-line SHAPE summary that sat under this went with
                // §298's trim: a sentence describing a picture, directly
                // beneath the picture, is the reader doing the same work
                // twice. The curve says "steady" or "one jump" on its own.
                if curve.count >= 2 {
                    Sparkline(closes: curve, up: (delta ?? 0) >= 0)
                        .frame(height: 56)
                }

                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if let closeTime = preview.closeTime {
                        Text("Closes \(closeTime.formatted(.relative(presentation: .named)))")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    if preview.isThin {
                        Text("Thin book — few orders either side, so treat this number gently.")
                            .dsText(.subhead13).foregroundStyle(DS.attention)
                    }
                }

                Spacer(minLength: 0)

                if alreadyFollowed {
                    DSSlabNote(text: "You're following this market.")
                } else {
                    DSSlabButton(title: "Follow this market", systemImage: "plus") { follow() }
                }
                DSSlabNote(text: "Public odds only — nothing here places a trade.")
            }
        }
        .task { await loadCurve() }
    }

    private func loadCurve() async {
        guard preview.source == .polymarket, let token = preview.yesTokenId else { return }
        curve = await PolymarketBridge.priceHistory(yesTokenId: token)
    }

    /// Follows, then LEAVES — the sheet was opened to decide, and the decision
    /// is made. `followed` flips first so the button can't be double-fired
    /// during the dismiss animation.
    private func follow() {
        guard !alreadyFollowed else { return }
        followed = true
        DSHaptic.tap()
        PredictionFollow.follow(preview, store: store, context: modelContext)
        dismiss()
    }
}
