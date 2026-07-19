import SwiftUI
import SwiftData

/// The wallet things already in the corpus — newest first. A @Query so the
/// list updates live and the fetch runs once per store change, not twice per
/// body pass.
private let walletRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Wallet" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Wallet, connected — the wallet's home in Casberi. The person manages WHICH
/// addresses are watched (paste to add, swipe to remove, drag to reorder — the
/// first address leads), sees a live holdings treemap (top 5 by USD value), and
/// sees what's landed (recent onchain things from the corpus). Read-only,
/// stated plainly: watching an address can never trade or move funds. Both the
/// holdings and the activity are live from Alchemy, read on this iPhone — no
/// server.
struct WalletScreen: View {
    @Bindable private var wallet = WalletStore.shared
    /// Which chains are read (2026-07-15) — the person can narrow the five to
    /// the ones they care about; toggling re-syncs.
    @Bindable private var chainStore = WalletChainStore.shared
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    /// The combined "bundle" treemap across every watched wallet (2026-07-15) —
    /// shown alongside the per-wallet charts when more than one is watched.
    @State private var portfolioHoldings = GenStream()
    @State private var portfolioTotal: Double = 0
    @State private var portfolioSamples: [WalletStore.ValueSample] = []
    /// The combined "Across your wallets" sheet — the full decomposed read
    /// (the combined line, then each wallet's own line in its face's color).
    @State private var showCombinedSheet = false
    @State private var result: String?
    @State private var resultIsError = false
    /// The in-flight WalletConnect handshake — proposed, wallet opened, waiting
    /// on a human to approve over there (2026-07-16). Held as the Task rather
    /// than a Bool so a second tap can CANCEL it: the wait runs to the
    /// proposal's 5-minute expiry, and a person who opened their wallet, chose
    /// not to approve, and came back must not find a stuck button and no way
    /// out. Separate from `syncing` — that one means "reading chains", this one
    /// means "waiting on your wallet", and collapsing them puts the wrong line
    /// on screen.
    @State private var connectTask: Task<Void, Never>?
    /// Bumped on every start and every cancel, so an in-flight handshake can
    /// tell whether it's still the CURRENT one. Cancellation only lands at the
    /// next suspension point — a cancelled handshake sitting in the relay
    /// round-trip can take a second to unwind — so without this, "cancel, then
    /// tap Connect again" lets the dying task's cleanup clear the new task's
    /// handle and write the new task's outcome.
    @State private var connectGeneration = 0
    private var connecting: Bool { connectTask != nil }
    /// A tapped holdings cell: the token's thing sheet when watched, the
    /// quick chart sheet when not.
    @State private var openTokenThing: Thing?
    @State private var quickToken: TokenQuickRoute?
    /// Renaming a watched wallet (2026-07-15) — the missing half of the label
    /// story: an ENS add sets the label automatically, but a raw-hex watch
    /// had no way to ever become "Cold" or "Trading". Tap the row's name.
    @State private var renameTarget: WalletStore.WatchedAddress.ID?
    @State private var renameDraft = ""
    /// Each watched wallet's own USD total, watch order (2026-07-15) — the
    /// one holdings fetch behind every surface here: the per-wallet treemap
    /// cards, the identity legend, the allocation bar, and the row sublines
    /// (2026-07-17; the treemaps used to ride a separate `holdingsChart()`
    /// doc that ran the same per-wallet fetch a second time).
    @State private var walletTotals: [WalletIngest.HoldingsGroup] = []
    /// Whether the Chains row is expanded (2026-07-15) — collapsed by
    /// default to a one-line summary ("Ethereum, Base +3"); a set-once
    /// setting doesn't deserve six full-height rows every visit.
    @State private var chainsExpanded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    /// The one swipe lesson, shared across every screen that pins by swipe
    /// (2026-07-11) — whichever screen a person meets the gesture on first
    /// retires it everywhere.
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    @Query(walletRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            // Empty state: the add field and the vitalik chip ARE the
            // screen — nothing to lead with yet. Connected state: the
            // watched wallets and their approvals lead (prd §104), value
            // views and activity follow, admin (add / chains) at the bottom.
            if wallet.addresses.isEmpty {
                addSection.listRowSeparator(.hidden)
                // The empty state reports too (2026-07-16). This section used
                // to exist only in the connected branch below, so with nothing
                // watched yet every outcome was set and then silently dropped
                // — a mistyped ENS name answered with nothing at all, in the
                // exact state where a first-time typo is likeliest. Found while
                // wiring Connect, whose "no wallet app" line vanished the same
                // way.
                statusSection
            } else {
                // Watching leads (user, 2026-07-17, prd §104): the rows carry
                // the pin control, and burying them under the treemaps and
                // transactions made "what do I pin" a scroll hunt. Approvals
                // rides directly under it — the security read belongs beside
                // the wallets it reads, not below the activity log. The
                // 2026-07-15 "value first" ruling is served by the rows
                // themselves now (value subline + sparkline per wallet).
                watchingSection.listRowSeparator(.hidden)
                if wallet.addresses.contains(where: { WalletApprovals.canServe($0.address) }) {
                    approvalsSection.listRowSeparator(.hidden)
                }
                // The combined "bundle" — total value, the allocation
                // bar, and one merged treemap. Only when more than one
                // wallet is watched (one wallet's own view IS its
                // portfolio); ruling 2026-07-15, alongside the per-wallet views.
                if wallet.addresses.count > 1, !portfolioHoldings.els.isEmpty {
                    portfolioSection.listRowSeparator(.hidden)
                }
                if !walletTotals.isEmpty {
                    Section {
                        // A face+name legend above the stack (2026-07-15) —
                        // scan the per-wallet treemaps by identity, the same
                        // mark the rows and combined sheet already wear,
                        // rather than reading each card's text label.
                        if walletTotals.count > 1 { walletIdentityLegend }
                        ForEach(walletTotals, id: \.address) { group in
                            holdingsMap(group)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                if !recent.isEmpty { recentSection.listRowSeparator(.hidden) }
                // Admin cluster: add another wallet, narrow the chains —
                // the settings, not the point.
                addSection.listRowSeparator(.hidden)
                chainsSection.listRowSeparator(.hidden)
                statusSection
                BridgeDisconnectSection(
                    bridgeID: "wallet", name: "Wallet",
                    teardown: { WalletStore.shared.addresses = [] }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Reorder/remove live behind Edit — drag to sort, red-minus to drop.
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
        }
        .onAppear {
            loadValueLines()
            if !wallet.addresses.isEmpty {
                sync()
                Task { await wallet.loadAvatars() }
            }
        }
        .onChange(of: wallet.addresses) {
            loadValueLines()
        }
        // A tapped holdings cell (2026-07-14): the token's own chart — its
        // thing sheet when watched, the quick sheet when it's just held.
        // ("@wallet" — the native-coin fallback — is a no-op here: this IS
        // the Wallet screen.)
        .environment(\.genProjectTap) { name in
            guard let route = TokenQuickRoute.from(sentinel: name) else { return }
            if let thing = route.watchedThing(in: modelContext) {
                openTokenThing = thing
            } else {
                quickToken = route
            }
        }
        .sheet(item: $openTokenThing) { thing in
            ThingSheetView(thing: thing)
        }
        .sheet(item: $quickToken) { route in
            TokenQuickSheet(route: route)
        }
        .sheet(isPresented: $showCombinedSheet) {
            CombinedWalletsSheet(total: portfolioTotal,
                                 combined: portfolioSamples,
                                 wallets: wallet.addresses)
        }
        // Name a watched wallet — the name rides every surface that already
        // leans on it (feed tags, treemap eyebrows, self-transfer titles).
        .alert("Name this wallet",
               isPresented: Binding(get: { renameTarget != nil },
                                    set: { if !$0 { renameTarget = nil } })) {
            TextField("Name (e.g. Main, Cold)", text: $renameDraft)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("A blank name shows the address instead.")
        }
    }

    private func saveRename() {
        guard let id = renameTarget else { return }
        renameTarget = nil
        wallet.rename(id, to: renameDraft)
        loadValueLines()
        DSHaptic.success()
    }

    // MARK: - Portfolio (combined bundle, 2026-07-15)

    /// The combined view across every watched wallet: net-worth headline,
    /// combined net-worth line (when history exists), and one merged treemap.
    /// Additive — the per-wallet charts still follow below, so which wallet
    /// holds what is never lost (ruling 2026-07-15, revising 2026-07-09's
    /// separate-only holdings).
    private var portfolioSection: some View {
        Section {
            Button {
                DSHaptic.tap()
                showCombinedSheet = true
            } label: {
                // One card, one tap target (2026-07-15) — the headline and
                // the allocation bar are the same fact (what you have,
                // where it sits), not two separate rows.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    HStack(alignment: .center, spacing: DS.Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            // "Combined value", not "Net worth" (ruling 2026-07-15,
                            // softening §71): the frame is your history with what you
                            // watch, not a terminal — and it's only these watched
                            // wallets' onchain value, never a claim about your whole
                            // net worth.
                            Text("Combined value")
                                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            Text(TokenStats.compact(portfolioTotal))
                                .dsText(.heading22).foregroundStyle(DS.textPrimary)
                                .monospacedDigit()
                        }
                        Spacer()
                        if portfolioSamples.count >= 2 {
                            let closes = portfolioSamples.map(\.usd)
                            let first = closes.first ?? 0
                            let last = closes.last ?? 0
                            let change = first > 0 ? (last - first) / first : 0
                            VStack(alignment: .trailing, spacing: 4) {
                                TokenChartPlot(chart: TokenChart(closes: closes, price: last,
                                                                 change: change),
                                               accent: TokenChartStyle.accent(change: change,
                                                                              scheme: scheme),
                                               height: 30, pulses: false)
                                    .frame(width: 84)
                                TokenDeltaPill(
                                    change: change,
                                    label: "since \(portfolioSamples.first!.at.formatted(.dateTime.month(.abbreviated).day()))",
                                    compact: true)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                    if walletTotals.count > 1 { allocationBarContent }
                }
            }
            .buttonStyle(.plain)
            .dsListCardRow()
            if !portfolioHoldings.els.isEmpty {
                GenRender(id: "root", els: portfolioHoldings.els)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        } header: {
            Text("Across your wallets").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("Everything you watch, together — read on this iPhone, no account, watch-only.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    /// Where your stuff actually sits (2026-07-15) — a single stacked band,
    /// one segment per wallet sized by its share of the combined total, each
    /// tinted in that wallet's face color. A portfolio total answers "how am
    /// I doing"; this answers the multi-wallet question no total can: where.
    /// Hidden below $1 total (nothing to allocate). Nested inside the
    /// combined card's own button (not a separate row) — headline and
    /// allocation are one fact, not two.
    /// A wallet's whole-percent share of the combined total, guarded so a
    /// non-finite operand can never trap `Int(_:)` (a hard crash). Clamped to
    /// 0…100 for display.
    private func pct(_ value: Double, of total: Double) -> Int {
        let p = (value / total * 100).rounded()
        guard p.isFinite else { return 0 }
        return min(100, max(0, Int(p)))
    }

    private var allocationBarContent: some View {
        let total = walletTotals.reduce(0) { $0 + $1.totalUSD }
        return Group {
            if total >= 1 {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(walletTotals.enumerated()), id: \.offset) { _, g in
                                let share = g.totalUSD / total
                                // `total` is >= 1 above, but guard non-finite so a
                                // stray garbage totalUSD can never hand SwiftUI a
                                // NaN/Inf frame width (a hard crash).
                                if share.isFinite, share > 0 {
                                    Capsule(style: .continuous)
                                        .fill(g.address.map(WalletFace.tint) ?? DS.fillFaint)
                                        .frame(width: max(4, geo.size.width * min(share, 1)))
                                }
                            }
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: DS.Space.s3) {
                        ForEach(Array(walletTotals.enumerated()), id: \.offset) { _, g in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(g.address.map(WalletFace.tint) ?? DS.fillFaint)
                                    .frame(width: 6, height: 6)
                                Text("\(g.label) \(pct(g.totalUSD, of: total))%")
                                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A face+name chip per wallet, above the per-wallet treemap stack
    /// (2026-07-15) — the same identity mark the rows and combined sheet
    /// wear, so a multi-wallet stack scans by face instead of by reading
    /// each card's text label.
    private var walletIdentityLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s4) {
                ForEach(Array(walletTotals.enumerated()), id: \.offset) { _, g in
                    if let addr = g.address {
                        HStack(spacing: 5) {
                            WalletFace(address: addr, size: 16)
                            Text(g.label).dsText(.label12).foregroundStyle(DS.textSecondary)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                  bottom: 0, trailing: DS.Space.s4))
    }

    // MARK: - Holdings treemaps (per wallet)

    /// One wallet's treemap card — holdings render through the gen-UI engine
    /// (allocation is magnitude, so the treemap is its native shape; holdings
    /// are SYNTHESIS, not things), one card per wallet so each can wear its
    /// own Home control (2026-07-17). The pin sits in the header's free
    /// trailing corner — ON the very thing pinning places on Home — because
    /// the Watching section's pin lives in the admin cluster at the bottom,
    /// and a fresh connect buries it under exactly this card plus the
    /// activity it just landed; nothing at the moment of intent said Home
    /// exists. Same per-address verb as the row pin and the swipe.
    private func holdingsMap(_ group: WalletIngest.HoldingsGroup) -> some View {
        let doc = WalletIngest.groupDocument(group).joined(separator: "\n")
        return GenRender(id: "root", els: GenParser.parse(prefix: doc[...], isComplete: true))
            .overlay(alignment: .topTrailing) {
                if let addr = group.address,
                   let entry = wallet.addresses.first(where: {
                       $0.address.lowercased() == addr.lowercased()
                   }) {
                    mapPinControl(entry)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    /// The card's Home verb, labeled — a bare corner glyph would be one more
    /// thing to decode, and discoverability is this control's whole job.
    /// Same grammar as the NFT strip's "On Home · remove" line below it.
    private func mapPinControl(_ entry: WalletStore.WatchedAddress) -> some View {
        Button {
            DSHaptic.tap()
            wallet.togglePin(entry.id)
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: entry.pinnedToHome ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                Text(entry.pinnedToHome ? "On Home" : "Pin to Home")
                    .dsText(.subhead13)
            }
            .foregroundStyle(entry.pinnedToHome ? DS.tint : DS.textSecondary)
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Matches GenTagMap's own header inset (top s4, horizontal s4), so
        // the control sits on the title line, across from the wallet's name.
        .padding(.top, DS.Space.s4)
        .padding(.trailing, DS.Space.s4)
    }

    // MARK: - Value history (2026-07-14)

    /// A row's sampled history — nil until the wallet has ≥2 sampled points
    /// (a single dot isn't a line).
    private func rowSamples(_ addr: WalletStore.WatchedAddress) -> [WalletStore.ValueSample]? {
        let s = wallet.valueSamples(forAddress: addr.address)
        guard s.count >= 2 else { return nil }
        return s
    }

    /// A watched wallet's live USD total, from the same fetch that feeds the
    /// allocation bar — the row's subline (2026-07-15). Nil until the first
    /// sync lands (no stale "$0" flash).
    private func walletValue(for address: String) -> Double? {
        walletTotals.first { $0.address?.lowercased() == address.lowercased() }?.totalUSD
    }

    /// The row's subline: the wallet's live value once known — more useful
    /// than repeating the address a second time. Falls back to the address
    /// (only when a label already occupies the name line above it) until
    /// the first sync lands, and to nothing when there's neither.
    private func rowSubline(_ addr: WalletStore.WatchedAddress) -> String? {
        if let usd = walletValue(for: addr.address) { return TokenStats.compact(usd) }
        return addr.label.isEmpty ? nil : addr.short
    }

    private func loadValueLines() {
        // The combined net-worth line only exists with more than one wallet;
        // with one, the Watching row's own sparkline already IS the portfolio.
        portfolioSamples = wallet.addresses.count > 1 ? wallet.combinedValueSamples() : []
    }

    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            // Two independent reads — overlapped, so the screen pays the
            // slowest one, not the sum (transfers + holdings each chain their
            // own round-trips).
            async let refreshed = WalletIngest.refresh(context: modelContext)
            async let portfolioDoc = WalletIngest.combinedHoldings()
            // One fetch feeds every holdings surface now — the treemap cards,
            // the legend, the allocation bar, the row sublines (2026-07-17;
            // holdingsChart() ran the same per-wallet fetch a second time
            // just to build the doc string this screen no longer renders).
            async let totals = WalletIngest.topHoldingsByWallet()
            let added = await refreshed
            walletTotals = await totals
            // The combined bundle — total + one merged treemap (nil unless
            // more than one wallet is watched).
            if let group = await portfolioDoc {
                portfolioTotal = group.totalUSD
                portfolioHoldings.paint(WalletIngest.groupDocument(group))
            } else {
                portfolioTotal = 0
                portfolioHoldings.paint([])
            }
            loadValueLines()   // the holdings fetch may have landed a sample
            syncing = false
            // A bridge only registers "connected" once it actually reached
            // Alchemy — a bad key or offline device must never claim success
            // (review 2026-07-08: this fired unconditionally, so a dead key
            // showed "connected" in Apps with nothing ever landing in Feed).
            guard let added else {
                result = String(localized: "Couldn't reach the chain — check your connection.")
                resultIsError = true
                return
            }
            resultIsError = false
            // A wallet that reached the chain but found nothing at all — no
            // priced holdings, no activity, across every selected chain —
            // gets an honest, specific nudge rather than the generic "watching
            // for activity" line, which reads as broken after the first sync
            // finds truly nothing (2026-07-15: a typo'd address "watches"
            // forever with no other signal that something might be wrong).
            let nothingFound = added == 0 && walletTotals.allSatisfy { $0.totalUSD < 1 }
            if added > 0 {
                result = String(localized: "\(added) new")
            } else if nothingFound && wallet.addresses.count == 1 {
                result = String(localized: "No activity found on your chains yet — double-check the address, or give it a moment.")
            } else {
                result = String(localized: "Connected — watching for activity.")
            }
            // Solana's carve-outs are gone as of prd §86: every chain in the
            // picker now reads activity as well as holdings, so the generic
            // lines are true again for everyone.
            let proof = added > 0 ? "\(added) new" : "Synced just now"
            if store.registerConnected(id: "wallet", name: "Wallet", proof: proof,
                                       can: ["Reads your wallet's activity.",
                                             "Read-only — never trades or moves funds."]) {
                DSHaptic.success()
            }
        }
    }

    // MARK: - Watching (add / remove / sort / pin)

    /// Each watched address carries its own pin now (ruling 2026-07-09): a
    /// wallet's holdings show on Home and Feed only when THAT wallet is
    /// pinned — watching more than one is usually two different purposes
    /// (main vs. cold), and a shared switch couldn't say which one it meant.
    /// Pin lives on the swipe alone now (2026-07-11) — the row briefly also
    /// carried an inline toggle, but a second control for the exact same
    /// verb read as two different actions rather than one (user: "confusing
    /// which is which"); the row shows its pin state passively instead
    /// (Feed's grammar), and the swipe hint nudge covers discoverability.
    private var watchingSection: some View {
        Section {
            ForEach(wallet.addresses) { addr in
                HStack(spacing: DS.Space.s3) {
                    // The wallet's face (2026-07-15): its ENS avatar when it
                    // published one, else a deterministic identicon — so
                    // watching three wallets no longer means three identical
                    // blue icons.
                    WalletFace(address: addr.address, size: 36)
                    Button {
                        DSHaptic.tap()
                        renameDraft = addr.label
                        renameTarget = addr.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addr.label.isEmpty ? addr.short : addr.label)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            // The value once known (2026-07-15) — more useful
                            // than repeating the address a second time; the
                            // Value section used to carry this separately.
                            if let subline = rowSubline(addr) {
                                Text(subline).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    // The value heartbeat, merged from the old standalone
                    // Value section (2026-07-15) — sparkline + delta pill,
                    // right on the row. Only once the wallet has ≥2 sampled
                    // points.
                    if let samples = rowSamples(addr) {
                        let closes = samples.map(\.usd)
                        let first = closes.first ?? 0
                        let last = closes.last ?? 0
                        let change = first > 0 ? (last - first) / first : 0
                        VStack(alignment: .trailing, spacing: 4) {
                            TokenChartPlot(chart: TokenChart(closes: closes, price: last,
                                                             change: change),
                                           accent: TokenChartStyle.accent(change: change, scheme: scheme),
                                           height: 22, pulses: false)
                                .frame(width: 40)
                                .accessibilityHidden(true)
                            TokenDeltaPill(change: change,
                                           label: samples.first!.at.formatted(.dateTime.month(.abbreviated).day()),
                                           compact: true)
                        }
                    }
                    // A visible pin control on every row (user, 2026-07-14):
                    // wallets pin per-ADDRESS (you might watch three and pin
                    // one), so the toggle lives on the row rather than as the
                    // source-level PinToHomeButton every other app screen
                    // carries above its list. Tap to pin/unpin; the trailing
                    // swipe still does the same — one verb, two ways.
                    Button {
                        DSHaptic.tap()
                        wallet.togglePin(addr.id)
                    } label: {
                        Image(systemName: addr.pinnedToHome ? "pin.fill" : "pin")
                            .font(.system(size: 14))
                            .foregroundStyle(addr.pinnedToHome ? DS.tint : DS.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .dsListCardRow()
                .modifier(SwipeHintNudge(active: addr.id == hintAddressID) { swipeCoachDone = true })
                // The pin swipe is the SAME GESTURE everywhere (2026-07-10,
                // user: it was leading here, trailing in Feed — one verb,
                // two directions): trailing edge, Feed's edge.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Full swipe = pin (Feed's grammar). An explicit trailing
                    // group replaces the system delete, so Remove rides here
                    // too — Edit mode's red minus still works.
                    Button {
                        DSHaptic.tap()
                        wallet.togglePin(addr.id)
                    } label: {
                        Label(addr.pinnedToHome ? "Unpin" : "Pin",
                              systemImage: addr.pinnedToHome ? "pin.slash" : "pin")
                    }
                    .tint(DS.tint)
                    Button(role: .destructive) {
                        if let i = wallet.addresses.firstIndex(where: { $0.id == addr.id }) {
                            wallet.remove(at: IndexSet(integer: i))
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .onDelete { wallet.remove(at: $0) }
            .onMove { wallet.move(from: $0, to: $1) }
        } header: {
            Text("Watching").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("Swipe a wallet to pin its holdings to Home and Feed.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Approvals (2026-07-16, prd §84)

    /// Each wallet's door to its Revoke.cash approvals dashboard — the read
    /// lives here (and new approvals land as things); the WRITE (revoking is
    /// an on-chain transaction) lives on Revoke.cash, the tool built for it,
    /// stated plainly in the footer. EVM wallets only: Revoke.cash has no
    /// Solana page, and a door to a 404 would be a dead control.
    private var approvalsSection: some View {
        Section {
            // `canServe`, not a bare hex check — a wallet watched by ENS name
            // stores the name, and Revoke.cash resolves names (verified live);
            // only Solana forms have no page there.
            ForEach(wallet.addresses.filter { WalletApprovals.canServe($0.address) }) { addr in
                Button {
                    DSHaptic.selection()
                    if let url = URL(string: WalletApprovals.revokeURL(address: addr.address)) {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: addr.address, size: 28)
                        Text(addr.label.isEmpty ? addr.short : addr.label)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("Revoke.cash")
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsListCardRow()
            }
        } header: {
            Text("Approvals").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("What each wallet has allowed contracts to spend. New approvals land in your feed; review and revoke on Revoke.cash — revoking is a transaction you sign there, never in Casberi.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Chains (2026-07-15)

    /// Which chains to read across every watched wallet — collapsed to a
    /// one-line summary by default (2026-07-15: six full-height checkmark
    /// rows was a lot of ceremony for a set-once setting); tap to expand
    /// into the GeckoTerminal/OpenSea checklist idiom. Default all-on;
    /// toggling narrows the reads and re-syncs. Never lets the last chain
    /// off (the store guards it).
    private var chainsSection: some View {
        Section {
            Button {
                DSHaptic.tap()
                withAnimation(.easeInOut(duration: 0.2)) { chainsExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    Text("Chains")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text(chainsSummary)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    Image(systemName: chainsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsListCardRow()
            if chainsExpanded {
                ForEach(WalletChainStore.selectable, id: \.id) { chain in
                    Button {
                        toggleChain(chain.id)
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            Text(chain.name)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer()
                            if chainStore.isSelected(chain.id) {
                                Image(systemName: "checkmark")
                                    .dsText(.body17).foregroundStyle(DS.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsListCardRow()
                }
            }
        } header: {
            Text("Chains").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            if chainsExpanded {
                Text("Read each watched wallet across these chains only — turn off the ones you don't use.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
        }
    }

    /// "All 5" when nothing's narrowed, else the selected names ("Ethereum,
    /// Base +3" past two) — the collapsed row's one-line fact.
    private var chainsSummary: String {
        let selected = WalletChainStore.selectable.filter { chainStore.isSelected($0.id) }
        if selected.count == WalletChainStore.selectable.count { return "All \(selected.count)" }
        let names = selected.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }

    private func toggleChain(_ id: String) {
        DSHaptic.tap()
        chainStore.toggle(id)
        // Re-read holdings and activity over the new chain set, and rebuild the
        // value lines the dropped chain may have fed.
        sync()
    }

    /// The row that plays the swipe demo — the first watched address, once
    /// ever, retiring the moment any screen's demo (or a real swipe) does.
    private var hintAddressID: WalletStore.WatchedAddress.ID? {
        guard !swipeCoachDone else { return nil }
        return wallet.addresses.first?.id
    }

    /// What just happened — the spinner while chains are read, then the outcome
    /// line. Rendered in BOTH the empty and connected states; see the note at
    /// the call site.
    @ViewBuilder
    private var statusSection: some View {
        if syncing || result != nil {
            Section {
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading onchain activity…"),
                                     result: result, resultIsError: resultIsError)
            }
            .listRowSeparator(.hidden)
        }
    }

    private var addSection: some View {
        Section {
            // The fast path leads: let the wallet hand its address over rather
            // than making someone copy 42 hex characters between two apps
            // (2026-07-16). The paste field below stays regardless — this is
            // the fast path, never the only one (ruling 2026-07-16), and a
            // hardware wallet or a wallet on another device has no other way
            // in. Absent entirely when no project id is configured: a control
            // that can't work doesn't appear.
            if WalletConnectBridge.isAvailable { connectRow }
            BridgeFieldRow(placeholder: "Address (0x…, ENS, or .sol)", text: $newAddress,
                           buttonLabel: "Watch", keyboard: .default,
                           focus: $addressFieldFocused, action: watch)
            // Nothing watched yet, nothing on the clipboard — one tap watches
            // a famous public wallet so the whole feature (holdings, activity,
            // faces, charts) demos in three seconds. Watch-only makes peeking
            // at vitalik.eth entirely legitimate; the chip retires the moment
            // any address is watched.
            if wallet.addresses.isEmpty {
                Button {
                    DSHaptic.tap()
                    newAddress = "vitalik.eth"
                    watch()
                } label: {
                    HStack(spacing: DS.Space.s1) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Peek at vitalik.eth")
                            .dsText(.subhead13).fontWeight(.medium)
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .background(DS.tint.opacity(0.12), in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        } header: {
            // "Add a wallet", not "Watch an address": with Connect leading the
            // section, the header has to name both ways in — connecting hands
            // an address over, it doesn't type one.
            Text("Add a wallet").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            if wallet.addresses.isEmpty {
                Text(WalletConnectBridge.isAvailable
                     ? "Connect your wallet to hand its address over, or paste any address, ENS, or .sol name — holdings and activity land in your feed. Connecting asks for nothing but the address."
                     : "Paste a wallet address, an ENS name, or a .sol name — its holdings and activity land in your feed.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
        }
    }

    /// "Connect wallet" — one tap, then approve in the wallet that opens; while
    /// waiting, the same button cancels.
    ///
    /// Never disabled, so there's no disabled background to get wrong (prd
    /// §83): waiting is a state you can leave, not a state that locks the
    /// screen. The label says so rather than leaving "tap again to cancel" as
    /// folklore — a control whose only exit is invisible is a dead control
    /// wearing a spinner.
    private var connectRow: some View {
        Button {
            DSHaptic.tap()
            if connecting { cancelConnect() } else { connectWallet() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                if connecting {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(connecting ? "Waiting for your wallet — cancel" : "Connect wallet")
                    .dsText(.callout15).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(DS.tint, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .animation(DS.Motion.standard, value: connecting)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DS.Space.s4,
                                  bottom: DS.Space.s2, trailing: DS.Space.s4))
    }

    private func cancelConnect() {
        connectGeneration &+= 1   // orphans the in-flight task before it unwinds
        connectTask?.cancel()
        connectTask = nil
        result = nil
    }

    private func connectWallet() {
        result = nil
        connectGeneration &+= 1
        let generation = connectGeneration
        connectTask = Task { @MainActor in
            // Only clear the handle if it's still OURS — a task orphaned by a
            // cancel or by a newer tap must not clear the current one's.
            defer { if connectGeneration == generation { connectTask = nil } }

            let outcome: Result<WalletConnectBridge.ConnectOutcome, Error>
            do {
                outcome = .success(try await WalletConnectBridge.connect(open: openWalletApp))
            } catch {
                outcome = .failure(error)
            }

            // One staleness gate over BOTH arms. A cancelled or superseded
            // handshake says nothing at all: the person cancelled it, they
            // know, and every line below would be a lie about a handshake
            // they already abandoned — cancellation surfaces as `.timedOut`
            // ("nothing came back from your wallet"), and a cancel landing
            // mid-teardown surfaces as `.tearDownFailed`, which would accuse
            // their wallet of holding a session open.
            guard connectGeneration == generation, !Task.isCancelled else { return }

            switch outcome {
            case .success(.connected(let found)):
                watchConnected(found)
            case .success(.noWalletApp):
                resultIsError = true
                result = String(localized: "No wallet app on this iPhone — paste the address instead.")
            case .success(.timedOut):
                resultIsError = true
                result = String(localized: "Nothing came back from your wallet — approve the request there, or paste the address instead.")
            case .failure(WalletConnectBridge.ConnectError.tearDownFailed):
                // The one failure this whole design exists to catch, so it says
                // so out loud instead of quietly watching the address: a
                // session survived the read, and until it's gone the screen's
                // read-only promise is false.
                resultIsError = true
                result = String(localized: "Connected, but the session wouldn't close — open your wallet and disconnect Casberi. Nothing was watched.")
            case .failure(WalletConnectBridge.ConnectError.keychainUnavailable(let status)):
                // The keychain preflight failed — the handshake never started
                // (the SDK would have crashed on this exact write). The code
                // rides along because it's the one fact that diagnoses this
                // from a screenshot.
                resultIsError = true
                result = String(localized: "This device's keychain refused the handshake (code \(status)) — paste the address instead.")
            case .failure:
                resultIsError = true
                result = String(localized: "Couldn't reach your wallet — paste the address instead.")
            }
        }
    }

    /// Hand the `wc:` URI to whichever wallet claims the scheme, and report
    /// whether one actually did.
    ///
    /// `canOpenURL` FIRST, and it — not the open's own result — is what the
    /// answer rests on. Measured 2026-07-16, both ways of asking afterwards
    /// lie: `UIApplication.open`'s completion and SwiftUI's `openURL` each
    /// reported success for a `wc:` URI that no installed app claimed, while
    /// LaunchServices failed it a beat later in its own daemon
    /// (`LSApplicationWorkspaceErrorDomain Code=115`, visible only in the
    /// device log). Believing that Bool left the screen waiting five minutes
    /// on a wallet that never opened. `canOpenURL` is synchronous, asks the
    /// installed-app registry directly, and needs exactly one
    /// `LSApplicationQueriesSchemes` entry — `wc`, which every WalletConnect
    /// wallet registers — so it does not rot as wallets come and go.
    ///
    /// The open still happens and its result is still ANDed in: a false there
    /// is rare but real (a wallet mid-uninstall), and this is a path where
    /// claiming more than we know is the whole thing we're avoiding.
    @MainActor
    private func openWalletApp(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }

    /// Watch whatever the settled session handed over. A wallet may share
    /// several accounts at once; all of them are addresses the person chose to
    /// give us, so all of them are watched rather than silently taking the
    /// first. Labels stay empty — the wallet sends a raw account, and the row
    /// is renameable.
    private func watchConnected(_ found: [WalletConnectBridge.ConnectedAccount]) {
        var addedAny = false
        for account in found {
            // A Solana wallet can only be read on Solana; adding one with that
            // chain switched off would watch an address that can never show
            // anything. Same rule the paste path applies to a `.sol` name —
            // except the family is read off the session here rather than
            // sniffed from the address, and the account names the chain it
            // needs rather than this screen restating the id.
            if let network = account.requiredNetworkID {
                WalletChainStore.shared.ensureEnabled(network)
            }
            // `add` returns false on a duplicate — kept in the body rather
            // than a `where` clause, which would hide the mutation.
            if wallet.add(account.address, label: "") { addedAny = true }
        }
        guard addedAny else {
            resultIsError = true
            result = found.isEmpty
                ? String(localized: "Your wallet approved but shared no address — paste it instead.")
                : String(localized: "Already watching that address.")
            return
        }
        resultIsError = false
        DSHaptic.success()
        sync()
    }

    private func watch() {
        let input = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        // A name (vitalik.eth, toly.sol) resolves to an address — the address is
        // what the APIs read; the name rides along as the row's label. `.sol` is
        // tried FIRST: `ENS.looksLikeName` takes any dotted string, so it would
        // otherwise send toly.sol to the ENS resolver, which answers with a null
        // address rather than an error.
        if SNS.looksLikeName(input) {
            Task {
                guard let address = await SNS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name, or paste the address.")
                    return
                }
                // A Solana wallet can only be read on Solana; adding one with
                // that chain switched off would watch an address that can never
                // show anything.
                WalletChainStore.shared.ensureEnabled("solana-mainnet")
                addWatched(address: address, label: input)
            }
        } else if ENS.looksLikeName(input) {
            Task {
                guard let hex = await ENS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name or paste a 0x address.")
                    return
                }
                addWatched(address: hex, label: input)
            }
        } else {
            if SNS.isAddress(input) { WalletChainStore.shared.ensureEnabled("solana-mainnet") }
            addWatched(address: input, label: "")
        }
    }

    private func addWatched(address: String, label: String) {
        guard wallet.add(address, label: label) else {
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        }
        newAddress = ""
        addressFieldFocused = false
        resultIsError = false
        DSHaptic.success()
        sync()
    }

    // MARK: - What's landed

    private var recentSection: some View {
        Section {
            ForEach(recent) { thing in
                HStack(spacing: DS.Space.s3) {
                    KindGlyph(kind: thing.kind, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thing.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // The wallet label when more than one is watched, or
                        // nothing — the block-explorer URL as a subline was
                        // receipt noise in a screen full of stories
                        // (2026-07-15); the link still lives behind the tap.
                        if let label = walletLabel(thing) {
                            Text(label).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(shortTime(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .dsListCardRow()
            }
        } header: {
            Text("Recent").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var footerSection: some View {
        Section {
        } footer: {
            Text("Read-only — watching can never trade or move funds. Activity is public, read across chains directly on this iPhone.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
    }

    /// Which watched wallet a landed transaction came from, when more than
    /// one is watched — falls back to nil (the explorer link shows instead)
    /// rather than guessing.
    private func walletLabel(_ thing: Thing) -> String? {
        wallet.label(forAddress: thing.walletAddress)
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
