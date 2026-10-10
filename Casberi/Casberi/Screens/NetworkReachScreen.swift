import SwiftUI

/// "What this app reaches" (prd §205) and "what it actually reached" (prd
/// §277) on ONE screen (prd §967, 2026-09-28). The registry says what the app
/// MAY reach and why; the ledger says what it DID this week. They were two
/// sheets naming the same sixty services in two orders, and neither could
/// say "Zerion — holdings and prices — 214 requests, two minutes ago" in one
/// row. Now every service is one row carrying both halves, and a host the
/// registry never declared is the one section that only draws on a finding.
///
/// A DIRECTORY, so it takes the Accounts and Addresses anatomy: a pushed
/// screen (`HomeRoute.Node.reach`), the dock's category tiles as the filter
/// (`DSScopeDock` on the phone, §960; inline where the rail stands), rows.
/// A row that names a connected seat is a door to that seat's account page —
/// §736's rule, and the reverse of the "What it reaches" rows §702 cut from
/// every account page: the app's hosts are still stated once, here.
///
/// **The screen's ceiling is stated, not implied.** The ledger records where
/// it can see (`NetworkLedger`'s own doc): pictures loading into rows and the
/// two live wallet-app connections are not in it, and a host you named
/// yourself (a feed, a store, a saved site) is filed under the app that asked
/// for it. A receipts page that looks complete while missing whole classes of
/// request is worse than none.
struct NetworkReachScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @State private var entries: [NetworkLedger.Entry] = []
    @State private var confirmForget = false
    /// A category's panel brightened once after a tile's jump (prd §1222).
    @State private var landed: String?

    private var connectedNames: Set<String> {
        Set(store.bridges.filter { $0.status == .connected }.map(\.name))
    }

    // MARK: - The ledger, resolved

    /// One observed host, paired with the service the registry says it
    /// belongs to. A named struct rather than a tuple so `ForEach` has a
    /// plain `Identifiable` element.
    private struct Receipt: Identifiable {
        let entry: NetworkLedger.Entry
        let service: String?
        var id: String { entry.host }
    }

    /// Registry first, then the recorder's own attribution — the ONE rule,
    /// `NetworkLedger.Entry.resolvedService`, shared with the Settings door
    /// so the door and this screen can never disagree about whether a host
    /// is on the list.
    private var receipts: [Receipt] {
        entries.map { Receipt(entry: $0, service: $0.resolvedService) }
    }

    /// Rows whose host the registry declares, and rows it doesn't. The second
    /// group should always be empty; it exists because the day it isn't is
    /// the day this screen earns its keep.
    private var declared: [Receipt] { receipts.filter { $0.service != nil } }
    private var undeclared: [Receipt] { receipts.filter { $0.service == nil } }

    /// The lead card's reading, over the rows exactly as this screen resolved
    /// them — so the map and the list below can never disagree about which
    /// host belongs to whom.
    private var reach: NetworkReceiptsInsight.Reach? {
        NetworkReceiptsInsight.compose(rows: receipts.map {
            .init(host: $0.entry.host, count: $0.entry.count, service: $0.service)
        })
    }

    // MARK: - The registry, with its receipts folded in

    /// A registry service and its week: every declared host's count summed,
    /// the latest of their last-seen stamps.
    private struct ServiceRow: Identifiable {
        let endpoint: NetworkReach.Endpoint
        let requests: Int
        let last: Date?
        var id: String { endpoint.service }
    }

    private var rows: [ServiceRow] {
        var requests: [String: Int] = [:]
        var last: [String: Date] = [:]
        for receipt in declared {
            guard let service = receipt.service else { continue }
            requests[service, default: 0] += receipt.entry.count
            last[service] = max(last[service] ?? .distantPast, receipt.entry.last)
        }
        return NetworkReach.endpoints.map {
            ServiceRow(endpoint: $0, requests: requests[$0.service] ?? 0, last: last[$0.service])
        }
    }

    /// The chip's category, then the four states a service can be in. A
    /// reached row is sorted by recency, so the screen opens on what the app
    /// is talking to right now; the rest keep the registry's own order.
    private var scoped: [ServiceRow] { rows }
    private var reached: [ServiceRow] {
        scoped.filter { $0.requests > 0 }
              .sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
    }
    private var reachingNow: [ServiceRow] {
        let live = Set(NetworkReach.reachingNow(connected: connectedNames).map(\.service))
        return scoped.filter { $0.requests == 0 && live.contains($0.endpoint.service) }
    }
    private var onTap: [ServiceRow] {
        scoped.filter {
            guard $0.requests == 0, case .onTapWithKey = $0.endpoint.reach else { return false }
            return true
        }
    }
    private var available: [ServiceRow] {
        scoped.filter {
            guard $0.requests == 0, case .whenConnected(let bridge) = $0.endpoint.reach else { return false }
            return !connectedNames.contains(bridge)
        }
    }

    // MARK: - Scopes

    /// All, then every dock category with a service behind it, A–Z — the
    /// Accounts and Addresses strips' own order. Fewer than three draws no
    /// strip. A category with nothing behind it never gets a chip: a control
    /// that filters to an empty list is the dead control §83 bans.
    /// What a service does today, said where it stands (prd §1222): its
    /// receipt when it reached this week, else when it would.
    private enum ReachState { case reached, now, onTap, ifConnected }

    private struct Placed: Identifiable {
        let row: ServiceRow
        let state: ReachState
        var id: String { row.id }
    }

    /// The services a category holds, in the order the groups stood: what
    /// reached this week, newest first, then what reaches now, on a tap, and
    /// only if connected.
    private var placed: [Placed] {
        reached.map { Placed(row: $0, state: .reached) }
            + reachingNow.map { Placed(row: $0, state: .now) }
            + onTap.map { Placed(row: $0, state: .onTap) }
            + available.map { Placed(row: $0, state: .ifConnected) }
    }

    /// Every category with a service in it, in the Feed's order; a service
    /// with no category (Maps, the name resolvers) stands under Casberi.
    private var panels: [(name: String, rows: [Placed])] {
        let grouped = Dictionary(grouping: placed) { Self.categories[$0.row.endpoint.service] ?? Self.uncategorised }
        let named = CategoryOrder.sorted(grouped.keys.filter { $0 != Self.uncategorised })
        let order = named + (grouped[Self.uncategorised] == nil ? [] : [Self.uncategorised])
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private static let uncategorised = "Casberi"

    private static func glyph(_ category: String) -> String {
        category == uncategorised ? "app" : CategoryFold.glyph(for: category)
    }

    private static func anchor(_ category: String) -> String { "reach:\(category)" }

    private static func category(of endpoint: NetworkReach.Endpoint) -> String? {
        if let offer = BridgeCatalog.offers.first(where: { $0.name == endpoint.service }) {
            return BridgeCatalog.category(of: offer)
        }
        switch endpoint.reach {
        case .onTapWithKey: return BridgeCatalog.agentsCategory
        case .whenConnected(let bridge):
            return BridgeCatalog.offers.first { $0.name == bridge }.map(BridgeCatalog.category(of:))
        case .always: return nil
        }
    }

    /// Both lookups, built ONCE off the static registry and catalogue — a
    /// row never walks the catalogue per render (§626).
    private static let categories: [String: String] =
        Dictionary(NetworkReach.endpoints.compactMap { e in category(of: e).map { (e.service, $0) } },
                   uniquingKeysWith: { a, _ in a })
    private static let destinations: [String: BridgeRouter.Destination] =
        Dictionary(NetworkReach.endpoints.compactMap { e in
            owner(of: e).flatMap(BridgeRouter.destination(forOffer:)).map { (e.service, $0) }
        }, uniquingKeysWith: { a, _ in a })
    private static let branded: Set<String> = Set(BridgeCatalog.offers.map(\.name))

    /// The seat a row opens: the service's own catalogue page, else the
    /// bridge that owns it. nil for the always-on set, which has no page.
    private static func owner(of endpoint: NetworkReach.Endpoint) -> String? {
        if BridgeCatalog.offers.contains(where: { $0.name == endpoint.service }) { return endpoint.service }
        return NetworkReach.bridge(forService: endpoint.service)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            list(proxy)
        }
    }

    /// A tile's press: its category's panel to the top, brightened once —
    /// the Feed's landing (prd §1208l).
    private func jump(_ category: String, _ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) {
            proxy.scrollTo(Self.anchor(category), anchor: .top)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(DS.Motion.standard) { landed = category }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.6)) { landed = nil }
        }
    }

    /// One category at a glance, in the Feed's glance frame (prd §1222): the
    /// service that asked most this week and its receipt, else the first
    /// service and when it would reach.
    private func glance(_ category: String, _ rows: [Placed], _ proxy: ScrollViewProxy) -> some View {
        let busiest = rows.filter { $0.state == .reached }.max { $0.row.requests < $1.row.requests }
        let lead = busiest ?? rows.first
        let last = rows.compactMap(\.row.last).max()
        let title = lead?.row.endpoint.service ?? ""
        let line: String = {
            guard let lead else { return "" }
            if let busiest, let at = busiest.row.last { return receiptLine(busiest.row.requests, at) }
            return stateLine(lead.state)
        }()
        return GlanceShell(category: category, when: last.map { LiveTimeText.short($0) },
                           accessibility: Text(verbatim: "\(category). \(title)")) {
            DSHaptic.selection()
            jump(category, proxy)
        } top: {
            EmptyView()
        } mark: {
            Image(systemName: Self.glyph(category))
                .dsGlyph(.caption)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Mark.badge, height: DS.Mark.badge)
        } words: {
            Text(verbatim: title)
                .dsText(.body17)
                .fontWeight(.medium)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: line)
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
                .padding(.top, DS.Space.s1)
        }
    }

    /// When a service with nothing this week would reach (the old groups'
    /// names, now said on the row).
    private func stateLine(_ state: ReachState) -> String {
        switch state {
        case .reached, .now: return String(localized: "Reaching now")
        case .onTap: return String(localized: "Only when you tap")
        case .ifConnected: return String(localized: "Only if you connect them")
        }
    }

    private func list(_ proxy: ScrollViewProxy) -> some View {
        List {
            Section {
                // THE CLAIM IS THE HEAD (prd §564, at the screen-head rung
                // since §967). This screen exists to make ONE promise
                // checkable, and a name over the claim would be two heads.
                // Split into two keys: the second sentence is the MECHANISM.
                // The claim stands where every screen's name does, in the
                // title row's pink (prd §1222), never under a second name.
                DSRoomTitleRow(title: String(localized: "There is no server."))
                    .dsRoomTitleListRow(inSheet: true)
                DSProse.text("Every request below goes straight from \(DS.device) to the service named.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                // The other half of "goes straight", said out loud (2026-08-10):
                // Private Relay covers Safari browsing, DNS and insecure
                // connections, and an app's own HTTPS requests are none of
                // those. Leaving that to be assumed on the one screen whose
                // job is making the privacy claim checkable would be the fake
                // status this app refuses everywhere else.
                DSFootnote("Going straight means each service sees your IP, as any app or website does. iCloud Private Relay covers Safari browsing, not an app's own requests.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // The week's reading leads, when there is one (prd §299).
            if let reach {
                Section {
                    // The room's box at its one size (prd §1222, §760).
                    ReachCard(reach: reach)
                        .dsRoomBox()
                        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: 0,
                                                  bottom: DS.Space.s2, trailing: 0))
                        .dsListRow()
                    ReachCard.line(reach)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                                  bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.rowInset))
                        .dsListRow()
                }
            }

            // A BOX PER CATEGORY, EVERY ONE SHOWING (prd §1222, user: "i
            // want it like we have on Feed which is all boxes showing"): the
            // Feed's glance at its one size, the busiest service leading.
            // The glass capsule that filtered the list is gone.
            if !panels.isEmpty {
                Section {
                    GlanceGrid {
                        ForEach(panels, id: \.name) { panel in
                            glance(panel.name, panel.rows, proxy)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                              bottom: 0, trailing: DSRoomChassis.inset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            // The finding first, on its own panel: a host with no service has
            // no category, so no category may hide it.
            if !undeclared.isEmpty {
                SectionPanelGroup(anchor: Self.anchor("unlisted")) {
                    SectionPanelName(name: String(localized: "Not on the list"), glyph: "questionmark.circle")
                } rows: {
                    ForEach(undeclared) { receipt in
                        hostRow(receipt).reachPanelRow()
                    }
                }
            }

            // EACH CATEGORY ON ITS PANEL (prd §1222), the Feed's and the
            // Wallet's card: every service once, its receipt or when it
            // would reach under its name.
            ForEach(panels, id: \.name) { panel in
                SectionPanelGroup(anchor: Self.anchor(panel.name), lit: landed == panel.name) {
                    SectionPanelName(name: panel.name, glyph: Self.glyph(panel.name))
                } rows: {
                    ForEach(panel.rows) { item in
                        serviceRow(item.row, state: item.state).reachPanelRow()
                    }
                }
            }

            // A row, never a section footer: a plain list pins its footers
            // on a plate (§782), measured on this screen.
            if !reached.isEmpty {
                Section {
                    DSFootnote(prose: ceiling, scale: .page)
                        .dsListRow()
                }
            }

            if !entries.isEmpty {
                Section {
                    Button(role: .destructive) {
                        DSHaptic.tap()
                        confirmForget = true
                    } label: {
                        Text("Forget these receipts")
                            .dsText(.body17).foregroundStyle(DS.destructiveInk)
                    }
                    .dsListRow()
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        // The claim is in the content and the way back is the dock's seat, so
        // nothing stands at the top edge (prd §767) — on the Mac, which still
        // pushes it. The phone raises it as a sheet (prd §1132), and a sheet
        // leaves by its Done, so the bar stands there with no title in it.
        .navigationTitle(Text("What this app reaches"))
        #if targetEnvironment(macCatalyst)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        #endif
        // The ledger is read on appear, never in a body (§628): a snapshot
        // flushes and walks the store.
        .onAppear {
            entries = NetworkLedger.shared.snapshot()
            #if DEBUG
            // `-reachScope "<Category>"` — take a category's tile headlessly,
            // the Accounts screen's `-appsShelf` one screen over.
            if let name = UserDefaults.standard.string(forKey: "reachScope") {
                let count = panels.first { $0.name == name }?.rows.count ?? 0
                NSLog("reachScope| \(name) \(count) services")
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    jump(name, proxy)
                }
            }
            #endif
        }
        .confirmationDialog("Forget these receipts?",
                            isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                NetworkLedger.shared.forget()
                entries = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forgetting them changes nothing about what's reached.")
        }
    }

    /// Named plainly, because the alternative is a page that implies it saw
    /// everything. These are the request paths that don't ride an
    /// instrumented transport — see `NetworkLedger`'s own doc.
    private var ceiling: String {
        "Hosts you named yourself — a feed, a store, a saved site — are filed under the app that asked for them. Not recorded: pictures loading as you scroll, and live wallet-app connections."
    }

    // MARK: - Rows

    /// A row that names a seat is a door to it (prd §736); the always-on set
    /// has no page and draws no chevron — never a control that looks
    /// pressable and isn't (§83).
    @ViewBuilder
    private func serviceRow(_ row: ServiceRow, state: ReachState) -> some View {
        if let destination = Self.destinations[row.endpoint.service] {
            Button {
                DSHaptic.tap()
                route.pushBridge(destination)
            } label: {
                serviceLabel(row, state: state, opens: true)
            }
            .buttonStyle(RowPress())
        } else {
            serviceLabel(row, state: state, opens: false)
        }
    }

    private func serviceLabel(_ row: ServiceRow, state: ReachState, opens: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            leadingIcon(row.endpoint)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(row.endpoint.service)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                // The receipt, under the name: how many, how recently. A
                // trailing column lost every width contest to the purpose
                // paragraph and drew nothing (measured on the simulator).
                if row.requests > 0, let last = row.last {
                    Text(receiptLine(row.requests, last))
                        .dsText(.subhead12).monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                } else {
                    Text(stateLine(state))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textPrimary)
                }
                Text(row.endpoint.purpose)
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.endpoint.hosts.joined(separator: " · "))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
            Spacer(minLength: DS.Space.s2)
            if opens {
                DSChevron()
                    .padding(.top, DS.Space.s1)
            }
        }
        .padding(.vertical, DS.Space.s1)
        .contentShape(Rectangle())
    }

    /// A host nobody declared — the finding. It wears the attention mark and
    /// its own host for a name, because there is no service to name it by.
    private func hostRow(_ receipt: Receipt) -> some View {
        HStack(spacing: DS.Space.s3) {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.list), style: .continuous)
                .fill(DS.attention.opacity(0.16))
                .frame(width: DS.Mark.list, height: DS.Mark.list)
                .overlay {
                    Image(systemName: "questionmark")
                        .dsGlyph(.subhead)
                        .foregroundStyle(DS.attention)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.entry.host)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(summary(receipt.entry))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s1)
    }

    /// A real catalog service wears its brand mark; the infra/always/on-tap
    /// entries (no brand) wear a category SF symbol on a quiet badge.
    @ViewBuilder
    private func leadingIcon(_ endpoint: NetworkReach.Endpoint) -> some View {
        if Self.branded.contains(endpoint.service) {
            BridgeIcon(name: endpoint.service, size: DS.Mark.list)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.list), style: .continuous)
                .fill(DS.gray200)
                .frame(width: DS.Mark.list, height: DS.Mark.list)
                .overlay(
                    Image(systemName: infraSymbol(endpoint))
                        .dsGlyph(.subhead)
                        .foregroundStyle(DS.textSecondary)
                )
        }
    }

    private func infraSymbol(_ endpoint: NetworkReach.Endpoint) -> String {
        switch endpoint.reach {
        case .onTapWithKey: return "key.fill"
        case .always: return endpoint.service == "Maps" ? "map" : "link"
        case .whenConnected:
            // The wallet-infra and exchange entries.
            if endpoint.service.contains("names") { return "textformat.abc" }
            if endpoint.service.contains("DeFi") { return "building.columns" }
            if endpoint.service.contains("Exchange") { return "dollarsign.arrow.circlepath" }
            return "globe"
        }
    }

    private func receiptLine(_ count: Int, _ last: Date) -> String {
        let when = last.formatted(.relative(presentation: .named))
        return count == 1 ? String(localized: "1 request · \(when)")
                          : String(localized: "\(count) requests · \(when)")
    }

    private func summary(_ entry: NetworkLedger.Entry) -> String {
        let requests = entry.count == 1 ? "1 request" : "\(entry.count) requests"
        let when = entry.last.formatted(.relative(presentation: .named))
        return "\(requests) · last \(when)"
    }
}

/// nil is All; otherwise a `BridgeCatalog.categories` name — the Accounts
/// screen's `CatalogScope` and Addresses' `AddressScope`, one type over, for
/// the same reasons they give: one stored property, so the strip's `==`
/// against its own elements never drifts.
/// The screen's lead (prd §299) — the reach map. One reading of a list you
/// would otherwise have to add up yourself: how many requests, to how many
/// services, whether any of them is undisclosed, and who dominates.
///
/// Display-only, like `TopicMapHero`: every cell is a fact the ledger states
/// and none is a door. The honesty rule bars a control that looks pressable
/// and isn't, and there is nothing useful to push a service to — its rows are
/// already directly below.
private struct ReachCard: View {
    let reach: NetworkReceiptsInsight.Reach

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                // `stat24`, not `heading40` (2026-08-28). `heading40` is the
                // LEDE rung — a sentence — and a figure borrowing it put this
                // count between the two money rungs either side of it,
                // matching neither. `stat24` is the ramp's own stat-card rung
                // and is what every other card-leading figure in the app uses.
                Text(reach.requests.formatted())
                    .dsText(.stat24).monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
                Text(unit).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                verdict
            }
            // What is left of the room's one box under the count (prd §1222);
            // the sentence that reads it stands under the box (`ReachLine`).
            UnitTreemap(count: reach.cells.count, height: 128, cell: { i in
                face(reach.cells[i], rank: i)
            }, readout: { i in
                // The exact count under the cursor. The card's whole job is
                // "who did this app reach, and how much", and a rank-ordered
                // tile can only ever show the ORDER — a small cell's own
                // number is the fact it cannot fit and the one a person hovers
                // to get. Declared state is named too, because an undeclared
                // host is the finding this screen exists to surface and it must
                // read as such even when its cell is one of the small ones.
                let cell = reach.cells[i]
                let unit = cell.count == 1 ? "request" : "requests"
                return cell.declared
                    ? "\(cell.label) — \(cell.count) \(unit)"
                    : "\(cell.label) — \(cell.count) \(unit), not on the list"
            })
        }
        .padding(.vertical, DS.Space.s1)
    }

    /// The verdict, in the second-largest type on the card. This is what the
    /// screen is FOR — a host reached without being disclosed is the runtime
    /// form of the failure that shipped in build 214 — so it leads rather than
    /// waiting in a section footer.
    private var verdict: some View {
        let clean = reach.clean
        let word = clean
            ? String(localized: "All declared")
            : (reach.undeclaredHosts == 1
               ? String(localized: "1 not on the list")
               : String(localized: "\(reach.undeclaredHosts) not on the list"))
        // A word in ink, no capsule (prd §583) — green for a clean week,
        // attention for a finding the person should look at.
        return DSStamp(word: word,
                       weight: clean ? .good : .urgent,
                       glyph: clean ? "checkmark" : "exclamationmark.circle.fill")
            .accessibilityElement(children: .combine)
    }

    /// Services is the headline unit — it's the one a person can act on. A
    /// ledger holding only undeclared hosts has no services to count, so it
    /// falls back to hosts rather than printing "0 services" over six rows.
    private var unit: String {
        if reach.services > 0 {
            return reach.services == 1
                ? String(localized: "requests · 1 service")
                : String(localized: "requests · \(reach.services) services")
        }
        return reach.hosts == 1
            ? String(localized: "requests · 1 host")
            : String(localized: "requests · \(reach.hosts) hosts")
    }

    /// What the number alone can't say: who dominates, and the ledger's own
    /// ceiling. The second sentence used to be the paragraph above this card;
    /// it moved here rather than being said twice (§208).
    /// The sentence that reads the map, under the box (prd §1222): who asks
    /// most, and the promise that only hosts and counts are kept.
    static func line(_ reach: NetworkReceiptsInsight.Reach) -> Text {
        Text(verbatim: subline(reach))
    }

    private static func subline(_ reach: NetworkReceiptsInsight.Reach) -> String {
        let promise = String(localized: "Hosts and counts only — never what was asked.")
        guard let label = reach.leadLabel, let share = reach.leadShare else { return promise }
        if reach.cells.count == 1 {
            return String(localized: "\(label) is the only one reached. \(promise)")
        }
        let percent = Int((share * 100).rounded())
        return String(localized: "\(label) asks most, at \(percent)% of every request. \(promise)")
    }

    private func face(_ cell: NetworkReceiptsInsight.Cell, rank: Int = -1) -> some View {
        // THE LEADER IS THE LOCKUP (prd §565). Slot 0 states its count at the
        // head rung; every other cell is untouched, so the tail keeps its
        // slots, its ramp and its 12pt names. A count is safe at that size
        // where a balance would not be (§374) — this card counts requests.
        //
        // Never the TAIL, even when the tail is somehow first: its number is a
        // SUM across several services, and at 40pt "one thing made that many
        // requests" is the same misreading this face already refuses in the
        // small tier, said louder.
        //
        // No disc. The only mark available here would be a monogram of the
        // service name printed directly beneath it, which restates its own
        // caption; see `DSTreemapLeader`'s doc.
        VStack(alignment: .leading, spacing: 2) {
            if rank == 0 && !cell.isTail {
                DSTreemapLeader(figure: cell.count.formatted(), name: cell.label)
            } else {
                Text(cell.label)
                    .dsText(.body17)
                    .foregroundStyle(cell.isTail ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                // The tail is a sum, not a service — printing its count beside a
                // name would read as one thing that made that many requests.
                if !cell.isTail {
                    Text("\(cell.count)")
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(rank == 0 && !cell.isTail ? 0 : DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                // The well, not the sheet: this card's own row background IS
                // `surfaceSheet`, so a cell washed over the same tone would
                // vanish at low share.
                DS.surfaceWell
                fill(cell)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cell.isTail ? cell.label
                            : "\(cell.label), \(cell.count) requests\(cell.declared ? "" : ", not on the list")")
    }

    /// Magnitude in the neutral ink ramp, STATE in the hue — the one place
    /// this map departs from the ramp's rule, and it earns it: an undeclared
    /// host is not a smaller version of a declared one, so it keeps a real
    /// color (2026-08-10: `DS.ink(magnitude:)` replaced the tinted wash for
    /// every OTHER treemap in the app, but attention is a state, not a
    /// decoration, and stays orange). The tail takes a flat neutral because
    /// "everything else" has no magnitude of its own.
    private func fill(_ cell: NetworkReceiptsInsight.Cell) -> Color {
        if cell.isTail { return DS.fillLine }
        return cell.declared ? DS.ink(magnitude: cell.share)
                              : DS.wash(DS.attention, magnitude: cell.share)
    }
}

private extension View {
    /// A row on a category's panel (prd §1222): the rows' column, the
    /// panel's fill, no separator.
    func reachPanelRow() -> some View {
        listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DSRoomChassis.rowInset,
                                 bottom: DS.Space.s1, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
            .listRowSeparator(.hidden)
    }
}
