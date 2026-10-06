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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var entries: [NetworkLedger.Entry] = []
    @State private var confirmForget = false
    @State private var scope = ReachScope(name: nil)

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
    private var scoped: [ServiceRow] {
        rows.filter { scope.name == nil || Self.categories[$0.endpoint.service] == scope.name }
    }
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
    private var scopes: [ReachScope] {
        let held = Set(Self.categories.values)
        return [ReachScope(name: nil)]
            // The person's category order (prd §1050j), not A to Z.
            + CategoryOrder.sorted(BridgeCatalog.categories.map(\.name).filter { held.contains($0) })
                .map { ReachScope(name: $0) }
    }

    /// The dock category a registry service stands in: its own catalogue
    /// row, else its owning seat's, else Agents for the key that reaches only
    /// when you tap. nil for the always-on set (a saved link's own page, a
    /// tapped location), which no category holds and only All draws.
    ///
    /// Here and not in `NetworkReach`, because a dozen Foundation-only
    /// harnesses compile that file against stubs and the catalogue is not one.
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

    /// Where a pick lands: the first row under the card. The head and the
    /// week's card fill the first screen, so a pick from the bottom capsule
    /// changed rows below the fold and looked like nothing happened — the
    /// Accounts screen's `scopeAnchor` for the same reason.
    private static let rowsAnchor = "reach-rows"

    var body: some View {
        ScrollViewReader { proxy in
            list(proxy)
        }
    }

    private func pick(_ picked: ReachScope, _ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) {
            scope = picked
            proxy.scrollTo(Self.rowsAnchor, anchor: .top)
        }
    }

    private func list(_ proxy: ScrollViewProxy) -> some View {
        List {
            Section {
                // THE CLAIM IS THE HEAD (prd §564, at the screen-head rung
                // since §967). This screen exists to make ONE promise
                // checkable, and a name over the claim would be two heads.
                // Split into two keys: the second sentence is the MECHANISM.
                DSScreenHead(title: Text("There is no server."))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                    ReachCard(reach: reach)
                        .dsListRow()
                }
            }

            // Where the rail stands the tiles sit inline; on the phone they
            // ride the capsule beside the seat (`dsScopeDock`, prd §960).
            if scopes.count > 2, !DSScopeDock<ReachScope>.atBottom(sizeClass) {
                Section {
                    DSScopeTiles(sections: scopes, active: scope, strip: true) { pick($0, proxy) }
                        .dsListRow()
                }
            }

            Color.clear.frame(height: 0)
                .listRowInsets(EdgeInsets())
                .dsListRow()
                .id(Self.rowsAnchor)

            // The finding, under every scope: a host with no service has no
            // category, so no chip may hide it (`AppsScreen.troubledScopes`'
            // reason, one screen over).
            if !undeclared.isEmpty {
                Section {
                    // A row, not a header (prd §784): a plain list pins headers.
                    Text("Not on the list").dsText(.label12).foregroundStyle(DS.textTertiary)
                        .dsListRow()
                    ForEach(undeclared) { receipt in
                        hostRow(receipt).dsListRow()
                    }
                }
            }

            if !reached.isEmpty {
                Section {
                    Text("Reached this week").dsText(.label12).foregroundStyle(DS.textTertiary)
                        .dsListRow()
                    ForEach(reached) { row in
                        serviceRow(row).dsListRow()
                    }
                    // A row, never a section footer: a plain list pins its
                    // footers on a plate (§782), measured on this screen.
                    DSFootnote(prose: ceiling, scale: .page)
                        .dsListRow()
                }
            }

            // No section footers past the ceiling (prd §748): each group's
            // name says when its services reach out.
            group(String(localized: "Reaching now"), reachingNow)
            group(String(localized: "Only when you tap"), onTap)
            group(String(localized: "Only if you connect them"), available)

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
        .dsScopeDock(sections: scopes, active: scope) { pick($0, proxy) }
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
        .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
        #endif
        // The ledger is read on appear, never in a body (§628): a snapshot
        // flushes and walks the store.
        .onAppear {
            entries = NetworkLedger.shared.snapshot()
            #if DEBUG
            // `-reachScope "<Category>"` — PICK a category headlessly, the
            // Accounts screen's `-appsShelf` one screen over.
            if let name = UserDefaults.standard.string(forKey: "reachScope") {
                scope = ReachScope(name: name)
                NSLog("reachScope| \(name) \(scoped.count) services")
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(Self.rowsAnchor, anchor: .top)
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

    @ViewBuilder
    private func group(_ title: String, _ rows: [ServiceRow]) -> some View {
        if !rows.isEmpty {
            Section {
                Text(title).dsText(.label12).foregroundStyle(DS.textTertiary)
                    .dsListRow()
                ForEach(rows) { row in
                    serviceRow(row).dsListRow()
                }
            }
        }
    }

    // MARK: - Rows

    /// A row that names a seat is a door to it (prd §736); the always-on set
    /// has no page and draws no chevron — never a control that looks
    /// pressable and isn't (§83).
    @ViewBuilder
    private func serviceRow(_ row: ServiceRow) -> some View {
        if let destination = Self.destinations[row.endpoint.service] {
            Button {
                DSHaptic.tap()
                route.pushBridge(destination)
            } label: {
                serviceLabel(row, opens: true)
            }
            .buttonStyle(RowPress())
        } else {
            serviceLabel(row, opens: false)
        }
    }

    private func serviceLabel(_ row: ServiceRow, opens: Bool) -> some View {
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
struct ReachScope: DSTileScope {
    let name: String?
    var id: String { name ?? "\u{1}all" }
    var label: String { name ?? String(localized: "All") }
    var glyph: String { CategoryFold.glyph(for: name ?? "All") }
    var summary: String { name ?? String(localized: "Every service") }
}

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
            Text(subline)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            UnitTreemap(count: reach.cells.count, height: 180, cell: { i in
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
    private var subline: String {
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
