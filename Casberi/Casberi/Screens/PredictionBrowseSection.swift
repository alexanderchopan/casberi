import SwiftUI
import SwiftData

/// The prediction-markets browse room (prd §233, 2026-07-29) — replaces the
/// search-only addSection both `KalshiScreen` and `PolymarketScreen` shipped
/// with. An empty query already listed the busiest open markets on both
/// bridges; nobody discovered it because the field's placeholder said to
/// type. This leads with what's actually open instead: category chips (read
/// off data each bridge was already fetching — Kalshi's `category` was
/// parsed per event and used only as a search haystack; Polymarket's event
/// tags cost nothing extra once browse reads `/events` instead of the bare
/// `/markets` list), three orderings, and races grouped into one card
/// instead of exploding into one row per candidate.
///
/// Shared by both screens rather than duplicated — the venue switcher this
/// section renders is what makes "own chip, but a toggle inside" (the
/// user's wallet-switcher analogy) buildable without a third destination:
/// `KalshiScreen` embeds it defaulting to `.kalshi`, `PolymarketScreen`
/// defaulting to `.polymarket`, and picking the OTHER venue's segment shows
/// that venue's browse content inline, reusing this exact view.
enum PredictionVenueScope: String, Identifiable {
    case all = "All"
    case kalshi = "Kalshi"
    case polymarket = "Polymarket"
    var id: String { rawValue }
}

/// The segmented control itself — the wallet switcher's own shape
/// (`FeedScreen.walletSwitcherBar`/`walletSwitcherChip`) applied to venues:
/// glass, a selection fill that travels on matched geometry, gated by the
/// caller on the OTHER venue actually being connected (never shown to
/// someone who's only ever used one exchange — the control earns its place
/// by existing, not by being disabled).
struct PredictionVenueSwitcher: View {
    @Binding var scope: PredictionVenueScope
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            chip(.all, icon: nil)
            chip(.kalshi, icon: "Kalshi")
            chip(.polymarket, icon: "Polymarket")
        }
        .padding(4)
        .dsGlass(cornerRadius: 999)
    }

    private func chip(_ value: PredictionVenueScope, icon: String?) -> some View {
        let isOn = scope == value
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { scope = value }
        } label: {
            HStack(spacing: 5) {
                if let icon { BridgeIcon(name: icon, size: 14, circular: true) }
                Text(value.rawValue)
                    .dsText(.subhead13)
                    .fontWeight(isOn ? .semibold : .regular)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(DS.fillFaint)
                    if isOn {
                        Capsule(style: .continuous).fill(DS.tint.opacity(0.18))
                            .matchedGeometryEffect(id: "predictionVenueSelection", in: ns)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// One outcome row, venue-neutral — a race's candidate or a binary market's
/// single side. `watch` is bound at construction time, so the section that
/// builds these doesn't need to know which bridge a tap should land on.
private struct BrowseOutcome: Identifiable {
    let id: String
    let name: String
    let probability: Double
    let watch: () -> Void
}

/// One browse card, venue-neutral. A race has several `outcomes`
/// (`others` counts what got left off, never silently); a binary market has
/// exactly one, and renders as the big-headline style instead of a bar list.
private struct BrowseCard: Identifiable {
    let id: String
    /// Shown only in `.all` scope, where a mixed list needs to say whose
    /// number this is.
    let venueBadge: String?
    let title: String
    let outcomes: [BrowseOutcome]
    let others: Int
    let closeTime: Date?
    let previousProbability: Double?
    let deltaLabel: String
    let isThin: Bool
}

/// Registers (or reconnects) a prediction-market bridge's catalog entry —
/// shared because the venue switcher makes it possible to watch a
/// Polymarket market from inside `KalshiScreen` (or vice versa), where the
/// screen's own `register()` only knows its own venue. Same shape both
/// screens' own `register()` already used before this existed.
@MainActor
func registerPredictionBridge(source: String, id: String, store: BridgeStore, context: ModelContext) {
    let count = recentBridgeThings(source: source, context: context).count
    let proof = "\(count) market\(count == 1 ? "" : "s") watched"
    if let existing = store.bridges.first(where: { $0.name == source }) {
        store.reconnect(existing.id, proof: proof)
    } else {
        store.bridges.append(BridgeApp(
            id: id, name: source, status: .connected, statusLine: proof,
            can: ["Watches the markets you add.", "Read-only — public odds, no trading."]))
        DSHaptic.success()
    }
}

struct PredictionBrowseSection: View {
    let scope: PredictionVenueScope
    let onWatchedKalshi: (Thing) -> Void
    let onWatchedPolymarket: (Thing) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var category: String? = nil
    @State private var order: PredictionOrder = .busiest
    @State private var kalshiCategories: [String] = []
    @State private var polymarketCategories: [String] = []
    @State private var kalshiRows: [KalshiWatch.Resolved] = []
    @State private var polymarketRows: [PolymarketBridge.Resolved] = []
    @State private var disagreements: [PredictionDisagreement.Pair] = []
    @State private var loaded = false

    /// The categories on offer for the CURRENT scope — each venue keeps its
    /// own real vocabulary (Kalshi's 13 API categories, Polymarket's curated
    /// tag set) rather than forcing a unified list neither venue actually
    /// has; `.all` shows the union, deduped, so a chip that exists on both
    /// isn't offered twice.
    private var categoryOptions: [String] {
        switch scope {
        case .kalshi: return kalshiCategories
        case .polymarket: return polymarketCategories
        case .all:
            var seen: Set<String> = []
            return (kalshiCategories + polymarketCategories).filter { seen.insert($0.lowercased()).inserted }
        }
    }

    private var cards: [BrowseCard] {
        var out: [BrowseCard] = []
        if scope == .kalshi || scope == .all {
            let filtered = category.map { cat in kalshiRows.filter { $0.category.caseInsensitiveCompare(cat) == .orderedSame } } ?? kalshiRows
            out += KalshiWatch.grouped(order.sorted(filtered)).map(kalshiCard)
        }
        if scope == .polymarket || scope == .all {
            let filtered = category.map { cat in polymarketRows.filter { $0.tags.contains(cat.lowercased()) } } ?? polymarketRows
            out += PolymarketBridge.grouped(order.sorted(filtered)).map(polymarketCard)
        }
        // Busiest deliberately does NOT cross-merge — Kalshi counts
        // contracts, Polymarket counts dollars, and ranking one against the
        // other would be exactly the decimals bug `PredictionMarket.isThin`
        // already refuses to commit (comparing incomparable units). Closing
        // soon and biggest move ARE comparable across venues (a date, a
        // probability-point delta), so only those two re-sort the merged list.
        if scope == .all {
            switch order {
            case .closingSoon:
                out.sort { ($0.closeTime ?? .distantFuture) < ($1.closeTime ?? .distantFuture) }
            case .biggestMove:
                out.sort { moveSize($0) > moveSize($1) }
            case .busiest:
                break
            }
        }
        return out
    }

    private func moveSize(_ card: BrowseCard) -> Double {
        guard let previous = card.previousProbability, let lead = card.outcomes.first?.probability else { return 0 }
        return abs(lead - previous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !categoryOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        categoryChip(nil, label: "All")
                        ForEach(categoryOptions, id: \.self) { cat in
                            categoryChip(cat, label: cat)
                        }
                    }
                }
            }
            Picker("", selection: $order) {
                ForEach(PredictionOrder.allCases) { o in Text(o.rawValue).tag(o) }
            }
            .pickerStyle(.segmented)

            if scope == .all, !disagreements.isEmpty {
                Text("They disagree").dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
                ForEach(disagreements) { pair in
                    disagreementCard(pair)
                }
            }

            ForEach(cards) { card in
                browseCard(card)
            }
        }
        .task(id: "\(scope.rawValue)") { await loadIfNeeded() }
    }

    private func categoryChip(_ value: String?, label: String) -> some View {
        let isOn = category == value || (value == nil && category == nil)
        return Button {
            DSHaptic.selection()
            category = value
        } label: {
            Text(label)
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(isOn ? .white : DS.textSecondary)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, 7)
                .background(Capsule().fill(isOn ? DS.tint : DS.fillFaint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        loaded = false
        async let k: [KalshiWatch.Resolved] = (scope == .kalshi || scope == .all) ? KalshiWatch.search("", limit: 24) : []
        async let p: [PolymarketBridge.Resolved] = (scope == .polymarket || scope == .all) ? PolymarketBridge.search("", limit: 24) : []
        async let kc: [String] = (scope == .kalshi || scope == .all) ? KalshiWatch.categories() : []
        async let pc: [String] = (scope == .polymarket || scope == .all) ? PolymarketBridge.categories() : []
        // Already-watched markets drop out of browse the same way a search
        // hit does (`displayHits`' own rule, both screens) — otherwise a
        // watched market sits in the list forever, tappable, doing nothing
        // (`add`'s own dedupe guard just returns nil on a repeat tap).
        let watchedKalshi = IngestSupport.existingSourceRefs(modelContext, source: "Kalshi")
        let watchedPolymarket = IngestSupport.existingSourceRefs(modelContext, source: "Polymarket")
        kalshiRows = await k.filter { !watchedKalshi.contains("kalshi:\($0.ticker)") }
        polymarketRows = await p.filter { !watchedPolymarket.contains("\(PolymarketBridge.refPrefix)\($0.conditionId)") }
        kalshiCategories = await kc
        polymarketCategories = await pc
        if scope == .all {
            disagreements = await PredictionDisagreement.find(among: kalshiRows)
        } else {
            disagreements = []
        }
        loaded = true
    }

    // MARK: - Card construction

    private func kalshiCard(_ race: KalshiWatch.Race) -> BrowseCard {
        let outcomes = race.outcomes.map { m in
            BrowseOutcome(id: m.ticker, name: m.subtitle.isEmpty ? m.title : m.subtitle,
                         probability: m.probability) { watchKalshi(m) }
        }
        return BrowseCard(id: "kalshi:\(race.eventTicker)",
                          venueBadge: scope == .all ? "Kalshi" : nil,
                          title: race.title, outcomes: outcomes, others: race.others,
                          closeTime: race.closeTime,
                          previousProbability: race.outcomes.first?.previousProbability,
                          deltaLabel: "vs yesterday",
                          isThin: race.outcomes.first?.isThin ?? false)
    }

    private func polymarketCard(_ race: PolymarketBridge.Race) -> BrowseCard {
        let outcomes = race.outcomes.map { m in
            BrowseOutcome(id: m.conditionId, name: m.subtitle.isEmpty ? m.title : m.subtitle,
                         probability: m.probability) { watchPolymarket(m) }
        }
        return BrowseCard(id: "polymarket:\(race.slug)",
                          venueBadge: scope == .all ? "Polymarket" : nil,
                          title: race.title, outcomes: outcomes, others: race.others,
                          closeTime: race.closeTime,
                          previousProbability: race.outcomes.first?.previousProbability,
                          deltaLabel: "vs last week",
                          isThin: race.outcomes.first?.isThin ?? false)
    }

    private func watchKalshi(_ market: KalshiWatch.Resolved) {
        DSHaptic.tap()
        if let thing = KalshiWatch.add(market, context: modelContext) {
            kalshiRows.removeAll { $0.ticker == market.ticker }
            onWatchedKalshi(thing)
        }
    }

    private func watchPolymarket(_ market: PolymarketBridge.Resolved) {
        DSHaptic.tap()
        if let thing = PolymarketBridge.add(market, context: modelContext) {
            polymarketRows.removeAll { $0.conditionId == market.conditionId }
            onWatchedPolymarket(thing)
        }
    }

    // MARK: - Rendering

    @ViewBuilder
    private func browseCard(_ card: BrowseCard) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                if let venueBadge = card.venueBadge {
                    BridgeIcon(name: venueBadge, size: 18, circular: false)
                }
                Text(card.title).dsText(.body17).fontWeight(.semibold).lineLimit(2)
            }

            if card.outcomes.count > 1 {
                ForEach(card.outcomes) { outcome in
                    Button(action: outcome.watch) {
                        HStack(spacing: DS.Space.s3) {
                            Text(outcome.name).dsText(.callout15).foregroundStyle(DS.textSecondary)
                                .lineLimit(1).frame(width: 104, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(DS.fillFaint)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(DS.tint)
                                            .frame(width: geo.size.width * outcome.probability)
                                    }
                            }
                            .frame(height: 8)
                            Text("\(Int((outcome.probability * 100).rounded()))%")
                                .dsText(.body17).fontWeight(.semibold).monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if let only = card.outcomes.first {
                Button(action: only.watch) {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            Text("\(Int((only.probability * 100).rounded()))%")
                                .dsText(.heading22).fontWeight(.bold).monospacedDigit()
                            if let previous = card.previousProbability {
                                TokenDeltaPill(change: only.probability - previous, label: card.deltaLabel, points: true)
                            }
                        }
                        GeometryReader { geo in
                            Capsule().fill(DS.fillFaint)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(DS.tint)
                                        .frame(width: geo.size.width * only.probability)
                                }
                        }
                        .frame(height: 8)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: DS.Space.s2) {
                if card.others > 0 {
                    Text("\(card.others) more").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                if let closeTime = card.closeTime {
                    if card.others > 0 { Text("·").foregroundStyle(DS.textTertiary) }
                    Text("Closes \(closeTime.formatted(.relative(presentation: .named)))")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                if card.isThin {
                    if card.others > 0 || card.closeTime != nil { Text("·").foregroundStyle(DS.textTertiary) }
                    Text("Thin book").dsText(.subhead13).foregroundStyle(DS.attention)
                }
            }
        }
        .dsListCardRow()
    }

    @ViewBuilder
    private func disagreementCard(_ pair: PredictionDisagreement.Pair) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(pair.kalshi.title).dsText(.body17).fontWeight(.semibold).lineLimit(2)
            disagreementRow(name: "Kalshi", icon: "Kalshi", probability: pair.kalshi.probability) {
                watchKalshi(pair.kalshi)
            }
            disagreementRow(name: "Polymarket", icon: "Polymarket", probability: pair.polymarket.probability) {
                watchPolymarket(pair.polymarket)
            }
            let gap = Int((abs(pair.kalshi.probability - pair.polymarket.probability) * 100).rounded())
            Text("\(gap) point\(gap == 1 ? "" : "s") apart")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .dsListCardRow()
    }

    private func disagreementRow(name: String, icon: String, probability: Double, watch: @escaping () -> Void) -> some View {
        Button(action: watch) {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: icon, size: 16, circular: true)
                Text(name).dsText(.callout15).foregroundStyle(DS.textSecondary).frame(width: 88, alignment: .leading)
                GeometryReader { geo in
                    Capsule().fill(DS.fillFaint)
                        .overlay(alignment: .leading) {
                            Capsule().fill(DS.tint).frame(width: geo.size.width * probability)
                        }
                }
                .frame(height: 8)
                Text("\(Int((probability * 100).rounded()))%")
                    .dsText(.body17).fontWeight(.semibold).monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .buttonStyle(.plain)
    }
}
