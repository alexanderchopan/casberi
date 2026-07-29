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
    let previousProbability: Double?
    /// Already in the corpus — the row says so and offers no Follow, rather
    /// than disappearing from the book. A book that silently shrinks as you
    /// use it loses your place and gives you nowhere to go back to.
    let isFollowed: Bool
    /// Everything the preview sheet and the Follow capsule both need.
    let preview: PredictionPreview
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
    // Connecting no longer implies following anything (prd §234), so zero is
    // a real, ordinary state — and "0 markets followed" would read as a
    // failed sync rather than an exchange you've just opened the door to.
    let proof = count == 0
        ? String(localized: "Browse the open markets in the \(source) room")
        : String(localized: "\(count) market\(count == 1 ? "" : "s") followed")
    if let existing = store.bridges.first(where: { $0.name == source }) {
        store.reconnect(existing.id, proof: proof)
    } else {
        store.bridges.append(BridgeApp(
            id: id, name: source, status: .connected, statusLine: proof,
            can: ["Browse every open market in its room.",
                  "Follows only the markets you pick.",
                  "Read-only — public odds, no trading."]))
        DSHaptic.success()
    }
}

struct PredictionBrowseSection: View {
    let scope: PredictionVenueScope
    let onWatchedKalshi: (Thing) -> Void
    let onWatchedPolymarket: (Thing) -> Void
    /// Hands the preview UP to whoever owns a presentation — this view lives
    /// inside `FeedScreen`'s List rows, and a `.sheet` on a row resolves to
    /// the same presenting controller as the screen's own, which is the
    /// half-open-then-close bug (ruling 2026-07-28). So the room routes it
    /// through `FeedSheetRoute` instead of presenting here.
    var onPreview: (PredictionPreview) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    /// Needed by `acceptTwin` — taking the twin offer registers the other
    /// exchange's seat, which may not exist yet.
    @Environment(BridgeStore.self) private var store
    /// The book is browsable, but a specific question still has to be
    /// findable — "Chiefs" shouldn't require scrolling Sports. Search lives
    /// HERE, with the book, rather than on the connect page where it used to
    /// sit (prd §234): it's a way of moving through the room's own content,
    /// not a step in connecting.
    @State private var query = ""
    @State private var category: String? = nil
    @State private var order: PredictionOrder = .busiest
    @State private var kalshiCategories: [String] = []
    @State private var polymarketCategories: [String] = []
    @State private var kalshiRows: [KalshiWatch.Resolved] = []
    @State private var polymarketRows: [PolymarketBridge.Resolved] = []
    @State private var disagreements: [PredictionDisagreement.Pair] = []
    /// sourceRefs already in the corpus, across BOTH venues — read once per
    /// load so each row can mark itself followed without its own fetch.
    @State private var followedRefs: Set<String> = []
    @State private var loaded = false

    /// The other exchange's price for the market just followed (prd §234) —
    /// the ON-RAMP to the comparison, and the only path to it for someone
    /// who has connected ONE venue. `disagreements` above needs `.all`
    /// scope, which needs both venues connected; this needs neither, because
    /// the other exchange's book is public whether or not it's a seat here.
    /// So a Kalshi-only user follows a market and finds out, right there,
    /// that Polymarket prices the same question differently — which is the
    /// most honest possible argument for the second venue, made exactly
    /// where the value lands.
    @State private var twin: PredictionTwin.Offer?

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
        // Rows arrive already category-filtered (`loadIfNeeded` passes it to
        // each bridge's own search) — nothing to re-filter here.
        var out: [BrowseCard] = []
        if scope == .kalshi || scope == .all {
            out += KalshiWatch.grouped(order.sorted(kalshiRows)).map(kalshiCard)
        }
        if scope == .polymarket || scope == .all {
            out += PolymarketBridge.grouped(order.sorted(polymarketRows)).map(polymarketCard)
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
            // No verb — searching here narrows the book in place as you type
            // (the `.task(id:)` below re-reads), it doesn't commit anything.
            // An empty `actionLabel` is DSSlabField's own supported no-verb
            // case, so this stays the shared control rather than a hand-rolled
            // field.
            DSSlabField(placeholder: String(localized: "Find a team, player, or question"),
                        text: $query, actionLabel: "", action: {})
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

            // The just-followed market's counterpart on the other exchange.
            // Sits ABOVE the book because it's about what you just did, and
            // it's transient — the next load clears it.
            if let twin { twinOfferCard(twin) }

            if scope == .all, !disagreements.isEmpty {
                Text("They disagree").dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
                ForEach(disagreements) { pair in
                    disagreementCard(pair)
                }
            }

            // The book takes real time to arrive — Kalshi hydrates one small
            // fetch PER matching event (see `KalshiWatch.search`'s two-phase
            // note), so a blank room that suddenly pops full is the normal
            // case, not the edge one. `loaded` was tracked and never read
            // until 2026-07-29; this is what it's for.
            if !loaded && cards.isEmpty {
                ForEach(0..<3, id: \.self) { _ in bookSkeleton }
            } else if loaded && cards.isEmpty {
                Text(emptyLine)
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    .padding(.vertical, DS.Space.s3)
            } else {
                ForEach(cards) { card in
                    browseCard(card)
                }
            }
        }
        // Re-runs on scope, category AND query — each is a different read of
        // the book, and both bridges' `search` already takes all three
        // (`query`'s own debounce lives in `debouncedSearch`).
        .task(id: "\(scope.rawValue)|\(category ?? "")|\(query)") { await loadIfNeeded() }
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
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Typing debounces; a scope or category tap doesn't (it's one
        // deliberate tap, and waiting 300ms after it just feels broken).
        if !q.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        // Category rides the API call, not a post-filter — Kalshi matches an
        // event's own `category` inside its cached listing, Polymarket
        // matches event tags; both narrow BEFORE the per-event hydration,
        // which is what keeps a category browse the same cost as a plain one.
        async let k: [KalshiWatch.Resolved] = (scope == .kalshi || scope == .all)
            ? KalshiWatch.search(q, limit: 24, category: category) : []
        async let p: [PolymarketBridge.Resolved] = (scope == .polymarket || scope == .all)
            ? PolymarketBridge.search(q, limit: 24, category: category) : []
        async let kc: [String] = (scope == .kalshi || scope == .all) ? KalshiWatch.categories() : []
        async let pc: [String] = (scope == .polymarket || scope == .all) ? PolymarketBridge.categories() : []
        // A followed market STAYS in the book, marked (2026-07-29) — it used
        // to be filtered out, which quietly shrank the list under you and
        // left nowhere to go back to the thing you'd just followed.
        followedRefs = IngestSupport.existingSourceRefs(modelContext, source: "Kalshi")
            .union(IngestSupport.existingSourceRefs(modelContext, source: "Polymarket"))
        kalshiRows = await k
        polymarketRows = await p
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
                          probability: m.probability,
                          previousProbability: m.previousProbability,
                          isFollowed: followedRefs.contains("kalshi:\(m.ticker)"),
                          preview: PredictionPreview(kalshi: m))
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
                          probability: m.probability,
                          previousProbability: m.previousProbability,
                          isFollowed: followedRefs.contains("\(PolymarketBridge.refPrefix)\(m.conditionId)"),
                          preview: PredictionPreview(polymarket: m))
        }
        return BrowseCard(id: "polymarket:\(race.slug)",
                          venueBadge: scope == .all ? "Polymarket" : nil,
                          title: race.title, outcomes: outcomes, others: race.others,
                          closeTime: race.closeTime,
                          previousProbability: race.outcomes.first?.previousProbability,
                          deltaLabel: "vs last week",
                          isThin: race.outcomes.first?.isThin ?? false)
    }

    /// The one write in this whole view. Reached from a row's explicit
    /// Follow capsule and from the preview sheet's own button — never from a
    /// plain row tap, which reads (opens the preview) like every other row
    /// in the app.
    private func follow(_ preview: PredictionPreview) {
        DSHaptic.tap()
        guard let thing = PredictionFollow.follow(preview, store: store, context: modelContext)
        else { return }
        followedRefs.insert("\(preview.source.refPrefix):\(preview.marketID)")
        switch preview.source {
        case .kalshi:
            onWatchedKalshi(thing)
            askTwin(for: PredictionMarket(
                source: .kalshi, id: preview.marketID, title: preview.title,
                subtitle: preview.outcome, url: thing.content,
                probability: preview.probability, volume: preview.kalshi?.volume ?? 0,
                resolved: false, yesWon: nil, closeTime: preview.closeTime))
        case .polymarket:
            onWatchedPolymarket(thing)
            if let m = preview.polymarket { askTwin(for: m.prediction) }
        }
    }

    private func watchKalshi(_ market: KalshiWatch.Resolved) {
        follow(PredictionPreview(kalshi: market))
    }

    private func watchPolymarket(_ market: PolymarketBridge.Resolved) {
        follow(PredictionPreview(polymarket: market))
    }

    /// Fire-and-forget: no twin is the common case and says nothing, so a
    /// nil result is silent rather than an empty state.
    private func askTwin(for market: PredictionMarket) {
        twin = nil
        Task { twin = await PredictionTwin.find(for: market, context: modelContext) }
    }

    /// Accepting lands the twin AND registers its exchange — following a
    /// Polymarket market is exactly as good a reason for Polymarket to hold
    /// a seat as tapping Connect was, and without this the thing would land
    /// with no catalog seat and no source chip to sit under.
    private func acceptTwin(_ offer: PredictionTwin.Offer) {
        DSHaptic.tap()
        PredictionTwin.accept(offer, context: modelContext)
        switch offer.source {
        case .kalshi:
            registerPredictionBridge(source: "Kalshi", id: "kalshi", store: store, context: modelContext)
        case .polymarket:
            registerPredictionBridge(source: "Polymarket", id: "polymarket", store: store, context: modelContext)
        }
        twin = nil
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
                ForEach(Array(card.outcomes.enumerated()), id: \.element.id) { index, outcome in
                    outcomeRow(outcome, isLead: index == 0, thin: card.isThin)
                }
            } else if let only = card.outcomes.first {
                binaryRow(only, card: card)
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

    /// One outcome in a race. TWO tap targets, deliberately separated: the
    /// row reads (opens the preview), the trailing capsule writes (follows).
    /// A single whole-row Button that followed on tap was the first build's
    /// mistake — it made the app's read gesture perform a silent write, and
    /// left no way to inspect a market without committing to it.
    private func outcomeRow(_ outcome: BrowseOutcome, isLead: Bool, thin: Bool) -> some View {
        HStack(spacing: DS.Space.s3) {
            Button { preview(outcome) } label: {
                HStack(spacing: DS.Space.s3) {
                    Text(outcome.name).dsText(.callout15)
                        .foregroundStyle(isLead ? DS.textPrimary : DS.textSecondary)
                        .fontWeight(isLead ? .semibold : .regular)
                        .lineLimit(1).frame(width: 96, alignment: .leading)
                    PredictionOddsBar(probability: outcome.probability,
                                      previous: outcome.previousProbability,
                                      isLead: isLead)
                        .frame(height: 8)
                    Text("\(Int((outcome.probability * 100).rounded()))%")
                        .dsText(.body17).fontWeight(.semibold).monospacedDigit()
                        // A thin book's number is treated gently wherever it
                        // renders (§83 ②).
                        .foregroundStyle(thin ? DS.textSecondary : DS.textPrimary)
                        .frame(width: 42, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            followCapsule(outcome)
        }
    }

    private func binaryRow(_ only: BrowseOutcome, card: BrowseCard) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Button { preview(only) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text("\(Int((only.probability * 100).rounded()))%")
                            .dsText(.heading22).fontWeight(.bold).monospacedDigit()
                            .foregroundStyle(card.isThin ? DS.textSecondary : DS.textPrimary)
                        if let previous = card.previousProbability {
                            TokenDeltaPill(change: only.probability - previous,
                                           label: card.deltaLabel, points: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: DS.Space.s2)
                followCapsule(only)
            }
            PredictionOddsBar(probability: only.probability,
                              previous: only.previousProbability)
                .frame(height: 8)
        }
    }

    /// The write target. Reads as a state once followed rather than
    /// disappearing — the book keeps its shape as you use it.
    @ViewBuilder
    private func followCapsule(_ outcome: BrowseOutcome) -> some View {
        if outcome.isFollowed {
            Label("Following", systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .dsText(.subhead13)
                .foregroundStyle(DS.confirm)
                .frame(width: 30, height: 30)
                .background(Circle().fill(DS.fillFaint))
                .accessibilityLabel("Following")
        } else {
            Button { follow(outcome.preview) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.fillFaint))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Follow \(outcome.name)")
        }
    }

    private func preview(_ outcome: BrowseOutcome) {
        DSHaptic.selection()
        onPreview(outcome.preview)
    }

    /// Says WHICH read came back empty, so a too-narrow filter doesn't read
    /// as a dead exchange.
    private var emptyLine: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty, let category {
            return String(localized: "No open \(category) market matches “\(q)”.")
        }
        if !q.isEmpty { return String(localized: "No open market matches “\(q)”.") }
        if let category { return String(localized: "Nothing open in \(category) right now.") }
        return String(localized: "Couldn't reach the market book just now.")
    }

    private var bookSkeleton: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Capsule().fill(DS.fillFaint).frame(width: 220, height: 14)
            Capsule().fill(DS.fillFaint).frame(height: 8)
            Capsule().fill(DS.fillFaint).frame(width: 120, height: 8)
        }
        .dsListCardRow()
        .redacted(reason: .placeholder)
    }

    /// "Polymarket prices this at 71% — 9 points apart." The line comes from
    /// `PredictionTwin.Offer.line`, which states the gap and never judges it
    /// (no spread computed, neither side called right, nothing suggesting an
    /// action) — the same restraint every other surface in this pair holds.
    @ViewBuilder
    private func twinOfferCard(_ offer: PredictionTwin.Offer) -> some View {
        Button { acceptTwin(offer) } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: offer.source.rawValue, size: 18, circular: true)
                    Text(offer.line).dsText(.callout15).foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Text("Follow it on \(offer.source.rawValue) too")
                    .dsText(.subhead13).foregroundStyle(DS.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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
