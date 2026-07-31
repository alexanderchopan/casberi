import SwiftUI
import SwiftData

/// Which venue's book the room is showing — `.all` merges both, and only
/// exists once both exchanges are connected (`PredictionVenueSwitcher`).
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
/// screen's own connect toggle only knows its own venue. Same shape both
/// screens' `PredictionVenueConnect` already uses.
///
/// "Room" stays out of every string here on purpose (prd §234, amended
/// 2026-07-29) — these lines surface as the Apps-catalog subline and the
/// bridge detail screen's capability list, both places a user reads, and
/// the word exists nowhere else they can see it. The chip is what's real to
/// them; the room is the word for what's behind it.
@MainActor
func registerPredictionBridge(source: String, id: String, store: BridgeStore, context: ModelContext) {
    let count = recentBridgeThings(source: source, context: context).count
    // Connecting no longer implies following anything (prd §234), so zero is
    // a real, ordinary state — and "0 markets followed" would read as a
    // failed sync rather than an exchange you've just opened the door to.
    let proof = count == 0
        ? String(localized: "Its chip is in your feed — browse every open \(source) market there")
        : String(localized: "\(count) market\(count == 1 ? "" : "s") followed")
    if let existing = store.bridges.first(where: { $0.name == source }) {
        store.reconnect(existing.id, proof: proof)
    } else {
        store.bridges.append(BridgeApp(
            id: id, name: source, status: .connected, statusLine: proof,
            can: ["Its chip opens every open market to browse.",
                  "Follows only the markets you pick.",
                  "Read-only — public odds, no trading."]))
        DSHaptic.success()
    }
}

/// The live market book (prd §233, moved into the ROOM by §234, refined by
/// §235) — every open market on an exchange, browsable without following
/// anything.
///
/// Reads off data each bridge was already fetching and discarding: Kalshi's
/// per-event `category` (parsed, then used only as a search haystack) and
/// `previousProbability`; Polymarket's event `tags`, free once browse reads
/// `/events` instead of the bare `/markets` list. Races group into one card
/// rather than exploding into a row per candidate, which is what used to
/// make the list look thin.
///
/// **The gesture contract (§235), the thing most likely to get broken by a
/// later edit:** a row TAP reads — it raises the preview through
/// `onPreview` — and the trailing capsule WRITES. They are two targets on
/// purpose. Making the whole row follow-on-tap was the first build's
/// mistake: it turned the app's read gesture into a silent write (a row is
/// a read with one gesture, ruling 2026-07-16) and left no way to inspect a
/// market without committing to it.
///
/// Mounted by `PredictionRoomBook` at the head of a Kalshi or Polymarket
/// room, never by a setup screen — connecting an exchange is not browsing
/// it (§234).
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
    /// Bumped by the empty state's Retry — `.task(id:)` only re-fires when
    /// its id string actually CHANGES, so a genuine one-off failure (the
    /// first-ever load hitting a real network blip, not the cancellation
    /// race the id already covers) had no way to try again short of leaving
    /// and re-entering the room. Folded into that same id string below.
    @State private var retryToken = 0

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

    /// Closing inside 48 hours — the window where "when" starts changing
    /// what the odds mean. A market already past its close reads imminent
    /// too rather than flipping quiet, since a book about to settle is
    /// exactly when you'd want to look.
    private func isImminent(_ closeTime: Date) -> Bool {
        closeTime.timeIntervalSinceNow < 48 * 3600
    }

    /// Worth a footer line at all (2026-07-29, the density pass). "Closes
    /// Aug 2028" told a reader nothing but still cost a line on most of the
    /// cards in the book — the presidential race and every other multi-year
    /// market. Thirty days out is where a close date starts being something
    /// you'd actually plan around; past that it's noise dressed as fact. A
    /// market already past its own close stays worth showing (same as
    /// `isImminent`) — that's the one closing NOW.
    private func isNearTerm(_ closeTime: Date) -> Bool {
        closeTime.timeIntervalSinceNow < 30 * 24 * 3600
    }

    private func moveSize(_ card: BrowseCard) -> Double {
        guard let previous = card.previousProbability, let lead = card.outcomes.first?.probability else { return 0 }
        return abs(lead - previous)
    }

    var body: some View {
        // Computed ONCE per body evaluation and threaded into both the lede
        // and the list — `cards` groups and sorts the whole book, and this
        // view renders inside a List row where that would otherwise run
        // twice on every update.
        let visible = cards
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            // No verb — searching here narrows the book in place as you type
            // (the `.task(id:)` below re-reads), it doesn't commit anything.
            // An empty `actionLabel` is DSSlabField's own supported no-verb
            // case, so this stays the shared control rather than a hand-rolled
            // field.
            // The lede (prd §235). This room used to open with three stacked
            // controls and no orientation at all — search field, chip row,
            // segmented picker — filling most of a phone before any content.
            // Now: one LINE saying what actually moved, and the ordering
            // control folded into the chip row below, so what precedes the
            // first market is a line plus two rows rather than three rows
            // and a card.
            if let lede = lede(in: visible) { ledeLine(lede.card, lede.outcome) }

            DSSlabField(placeholder: String(localized: "Find a team, player, or question"),
                        text: $query, actionLabel: "", action: {})
            // Order + categories share ONE scrolling row: the order menu is a
            // chip like the rest, since "Busiest" and "Politics" are both
            // just ways of narrowing what you're looking at.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    Menu {
                        Picker("", selection: $order) {
                            ForEach(PredictionOrder.allCases) { o in Text(o.rawValue).tag(o) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(order.rawValue).dsText(.subhead13).fontWeight(.semibold)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s3).padding(.vertical, 7)
                        .background(Capsule().fill(DS.fillStrong))
                    }
                    if !categoryOptions.isEmpty {
                        categoryChip(nil, label: "All")
                        ForEach(categoryOptions, id: \.self) { cat in
                            categoryChip(cat, label: cat)
                        }
                    }
                }
            }

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
            if !loaded && visible.isEmpty {
                ForEach(0..<3, id: \.self) { _ in bookSkeleton }
            } else if loaded && visible.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(emptyLine)
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                    // Only when there's actually something to retry — a
                    // query or category that's simply too narrow has no
                    // retry that would change the answer.
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category == nil {
                        Button {
                            DSHaptic.tap()
                            retryToken += 1
                        } label: {
                            Text("Try again").dsText(.subhead13).fontWeight(.semibold)
                                .foregroundStyle(DS.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DS.Space.s3)
            } else {
                ForEach(visible) { card in
                    browseCard(card)
                }
            }
        }
        // Re-runs on scope, category AND query — each is a different read of
        // the book, and both bridges' `search` already takes all three
        // (`query`'s own debounce lives in `debouncedSearch`).
        .task(id: "\(scope.rawValue)|\(category ?? "")|\(query)|\(retryToken)") { await loadIfNeeded() }
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
        // Gathered into LOCALS, not committed yet — see the cancellation
        // guard below for why (2026-07-30, the "couldn't pull the market
        // book" report).
        let kRows = await k
        let pRows = await p
        let kCats = await kc
        let pCats = await pc
        let pairs = scope == .all ? await PredictionDisagreement.find(among: kRows) : []

        // The bug this fixes: `.task(id:)` cancels the PREVIOUS
        // `loadIfNeeded` the instant scope/category/query changes, but
        // Swift does not abort a running function on cancellation — it
        // only makes `await`s on cancellable work (like `URLSession
        // .data(for:)`, inside `IngestSupport.run`) return nil/throw. So a
        // STALE call, cancelled mid-flight, finishes with an empty or
        // partial result and — without this guard — would go on to
        // overwrite `kalshiRows`/`polymarketRows` with that emptiness
        // regardless of whether a NEWER call (for whatever the user
        // actually tapped) already landed the real book. Whichever
        // `loadIfNeeded` finishes LAST wins, and the stale, cancelled one
        // usually finishes fastest (its own network calls returned nil
        // almost immediately), so it routinely stomped a live category's
        // correct data with "nothing" a moment later — reading as a dead
        // Kalshi connection on a perfectly healthy one. ONE check, after
        // every await in this function and before the first write, makes a
        // superseded call a true no-op instead of a silent regression.
        guard !Task.isCancelled else { return }

        // A followed market STAYS in the book, marked (2026-07-29) — it used
        // to be filtered out, which quietly shrank the list under you and
        // left nowhere to go back to the thing you'd just followed.
        followedRefs = IngestSupport.existingSourceRefs(modelContext, source: "Kalshi")
            .union(IngestSupport.existingSourceRefs(modelContext, source: "Polymarket"))
        kalshiRows = kRows
        polymarketRows = pRows
        kalshiCategories = kCats
        polymarketCategories = pCats
        disagreements = pairs
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

            if card.others > 0 || card.isThin || (card.closeTime.map(isNearTerm) ?? false) {
                HStack(spacing: DS.Space.s2) {
                    if card.others > 0 {
                        Text("\(card.others) more").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    // Time is WEIGHTED (prd §235) and now GATED (density
                    // pass, 2026-07-29): "Closes Aug 2028" cost a line on
                    // most of the book and told a reader nothing. Under 30
                    // days it's worth a line; inside 48h that line reads as
                    // state, since 62% closing tonight is a different claim
                    // than 62% closing next month.
                    if let closeTime = card.closeTime, isNearTerm(closeTime) {
                        if card.others > 0 { Text("·").foregroundStyle(DS.textTertiary) }
                        Text("Closes \(closeTime.formatted(.relative(presentation: .named)))")
                            .dsText(.subhead13)
                            .fontWeight(isImminent(closeTime) ? .semibold : .regular)
                            .foregroundStyle(isImminent(closeTime) ? DS.attention : DS.textTertiary)
                    }
                    if card.isThin {
                        if card.others > 0 || card.closeTime != nil { Text("·").foregroundStyle(DS.textTertiary) }
                        Text("Thin book").dsText(.subhead13).foregroundStyle(DS.attention)
                    }
                }
            }
        }
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.top, DS.Space.s2)
    }

    /// One outcome in a race — a READ target only (2026-07-29, the density
    /// pass). A race's several candidates used to each carry their own
    /// follow capsule, which meant a four-way race stacked four identical
    /// blue circles down the trailing edge — the single busiest thing in the
    /// view, and ambiguous besides (which one does "follow" mean here?). The
    /// rule adopted: a capsule exists where there's exactly ONE thing to
    /// follow. A race has several, so the whole row taps through to the
    /// preview, and following happens there, on the specific outcome you
    /// opened. Already-followed still says so — a quiet checkmark, not a
    /// button — so the row keeps reporting state without adding a target.
    private func outcomeRow(_ outcome: BrowseOutcome, isLead: Bool, thin: Bool) -> some View {
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
                if outcome.isFollowed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.confirm)
                        .frame(width: 16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: - The lede

    /// The single biggest move in the book right now (prd §235).
    ///
    /// A THING, deliberately, not a tally — the module doctrine bans a count
    /// as a module, and "14 markets moved 10+ points" is exactly that. One
    /// market that moved nine points is an EVENT, and it's also the most
    /// useful thing to know on opening: it's where the crowd changed its
    /// mind since yesterday. Silent when nothing moved meaningfully, rather
    /// than promoting the largest of several rounding errors.
    ///
    /// Takes the ALREADY-COMPUTED cards rather than reading `cards` itself —
    /// that property groups and sorts the whole book, and reaching for it
    /// twice per body evaluation would double that work inside a List row.
    /// Suppressed under `.biggestMove` ordering, where the lede would be
    /// the first card restated an inch above itself.
    private func lede(in cards: [BrowseCard]) -> (card: BrowseCard, outcome: BrowseOutcome)? {
        guard order != .biggestMove else { return nil }
        let moved = cards.flatMap { card in
            card.outcomes.compactMap { o -> (BrowseCard, BrowseOutcome, Double)? in
                guard let prev = o.previousProbability else { return nil }
                let delta = o.probability - prev
                // Five points is a real change of mind; below it this would
                // be dressing up noise as news.
                return abs(delta) >= 0.05 ? (card, o, delta) : nil
            }
        }
        guard let best = moved.max(by: { abs($0.2) < abs($1.2) }) else { return nil }
        return (best.0, best.1)
    }

    /// A LINE, not a card (2026-07-29, second pass). The first build made
    /// this the biggest object on screen — a full card with its own headline,
    /// number and bar — which bought orientation at the price of a fourth
    /// stacked block before the first market, and restated a market the list
    /// below almost always shows again. A line orients just as well: it
    /// names what moved and by how much, and taps through to the same
    /// preview. The odds and the bar belong to the card, which is right
    /// underneath.
    ///
    /// The QUESTION carries it — "Newsom" alone says nothing without the
    /// race, and a binary market's title already IS the question — with the
    /// outcome appended only where a race needs it to make sense.
    private func ledeLine(_ card: BrowseCard, _ outcome: BrowseOutcome) -> some View {
        Button { preview(outcome) } label: {
            HStack(spacing: DS.Space.s2) {
                Text("Biggest move")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .layoutPriority(1)
                Text(card.outcomes.count > 1 && !outcome.name.isEmpty
                     ? "\(card.title) · \(outcome.name)" : card.title)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: DS.Space.s1)
                if let prev = outcome.previousProbability {
                    TokenDeltaPill(change: outcome.probability - prev,
                                   label: "", compact: true, points: true)
                        .layoutPriority(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.s1)
        .padding(.bottom, DS.Space.s1)
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
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.top, DS.Space.s2)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.top, DS.Space.s2)
    }

    /// The disagreement card is a DIFFERENT SHAPE, not the browse card in a
    /// different colour (prd §235). It used to render identically to every
    /// other card, which buried the one comparison neither exchange's own
    /// app can ever show. So the GAP is the headline — the fact that only
    /// exists because both books are being read at once — and the two venue
    /// bars sit beneath it wearing their own brand hues, so which crowd is
    /// which is readable without parsing a label.
    ///
    /// The gap is stated, never judged: no spread computed, neither side
    /// called right, nothing suggesting an action (`PredictionTwin`'s own
    /// restraint, held here too).
    ///
    /// Both venue bars are READ targets now (2026-07-29, the density pass) —
    /// two capsules stacked on one card was the same clutter the race rows
    /// carried, and just as ambiguous (follow WHICH one, at a glance). Tap
    /// either bar to preview that venue's market; follow from there, same as
    /// a race outcome.
    @ViewBuilder
    private func disagreementCard(_ pair: PredictionDisagreement.Pair) -> some View {
        let gap = Int((abs(pair.kalshi.probability - pair.polymarket.probability) * 100).rounded())
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(gap) point\(gap == 1 ? "" : "s") apart")
                    .dsText(.heading22).fontWeight(.bold)
                    .foregroundStyle(DS.textPrimary)
                Text(pair.kalshi.title)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }
            venueBar(name: "Kalshi", probability: pair.kalshi.probability) {
                onPreview(PredictionPreview(kalshi: pair.kalshi))
            }
            venueBar(name: "Polymarket", probability: pair.polymarket.probability) {
                onPreview(PredictionPreview(polymarket: pair.polymarket))
            }
        }
        .padding(DS.Space.s4)
        .dsWidgetSurface()
        .padding(.top, DS.Space.s2)
    }

    /// One venue's price inside a disagreement card — tinted to the
    /// exchange's own hue, tapping through to that market's preview.
    private func venueBar(name: String, probability: Double, preview: @escaping () -> Void) -> some View {
        Button { DSHaptic.selection(); preview() } label: {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: name, size: 18, circular: true)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.fillFaint)
                        Capsule().fill(DS.washHue(for: name) ?? DS.tint)
                            .frame(width: max(0, min(1, probability)) * geo.size.width)
                    }
                }
                .frame(height: 10)
                Text("\(Int((probability * 100).rounded()))%")
                    .dsText(.body17).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
                    .frame(width: 42, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
