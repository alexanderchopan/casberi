import SwiftUI

/// "What it actually reached" (prd §277) — the runtime half of §205's
/// registry. `NetworkReachScreen` lists what the app MAY reach; this lists
/// what it DID, read off `NetworkLedger`.
///
/// The screen's job is as much to state its own ceiling as to show the rows.
/// A receipts page that looks complete while missing whole classes of request
/// is worse than none — so the paths that aren't instrumented are named in
/// the footer, in the same plain words the registry uses.
struct NetworkReceiptsScreen: View {
    /// Presented only as a sheet, so it owns its own exit — see the dismiss
    /// note on the title below (prd §560).
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [NetworkLedger.Entry] = []
    @State private var confirmForget = false

    /// One observed host, paired with the service the registry says it
    /// belongs to. A named struct rather than a tuple so `ForEach` has a
    /// plain `Identifiable` element.
    private struct Receipt: Identifiable {
        let entry: NetworkLedger.Entry
        let service: String?
        var id: String { entry.host }
    }

    /// Registry first, then the recorder's own attribution (2026-08-03).
    ///
    /// Some hosts can never be in the registry: a feed you follow, a Shopify
    /// store you named, a link you saved, your own self-hosted PostHog. The
    /// host comes out of YOUR input, so `service(forHost:)` misses it and
    /// every one of them landed under "not on the list — that's a bug, please
    /// report it", which was both wrong and alarming. Those call sites now
    /// name their service when they record (`NetworkLedger.Entry.service`).
    ///
    /// The RULE itself moved to `NetworkLedger.Entry.resolvedService`
    /// (2026-08-18) when the Privacy tray's door began stating this screen's
    /// verdict on its own row: two copies of "is this host declared?" is how
    /// a door and the screen behind it come to answer differently.
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

    var body: some View {
        List {
            // The reading leads; the sentence that used to sit here says the
            // same things the card now says with numbers (§208 — one thing
            // said twice). It survives for the empty case, which has no card.
            if let reach {
                Section {
                    ReachCard(reach: reach)
                        .dsListCardRow()
                }
            } else {
                Section {
                    Text("Nothing yet. Every service reached shows up here — the host, how many requests, and when the last one was.")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !undeclared.isEmpty {
                Section {
                    ForEach(undeclared) { receipt in
                        row(receipt).dsListCardRow()
                    }
                } header: {
                    Text("Not on the list").dsText(.label12).foregroundStyle(DS.textTertiary)
                } footer: {
                    Text("Reached but not declared in \"What this app reaches\" — a bug in the list, not a hidden service. Please report it.")
                        .dsText(.callout15).foregroundStyle(DS.attention)
                }
            }

            if !declared.isEmpty {
                Section {
                    ForEach(declared) { receipt in
                        row(receipt).dsListCardRow()
                    }
                } header: {
                    Text("Reached").dsText(.label12).foregroundStyle(DS.textTertiary)
                } footer: {
                    Text(ceiling).dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
            }

            if !entries.isEmpty {
                Section {
                    Button(role: .destructive) {
                        DSHaptic.tap()
                        confirmForget = true
                    } label: {
                        Text("Forget these receipts")
                            .dsText(.body17).foregroundStyle(DS.destructive)
                    }
                    .dsListCardRow()
                } footer: {
                    Text("Kept on \(DS.device) for seven days, never synced. Forgetting them changes nothing about what's reached.")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        // **NO WAY OUT, the second of the pair** (prd §560) — see
        // `NetworkReachScreen`, its sibling in the same `.sheet(item:)`; both
        // were presented with no close control and no sizing.
        .navigationTitle(Text("What it actually reached"))
        .navigationBarTitleDisplayMode(.inline)
        .dsSheetDismiss { dismiss() }
        .onAppear { entries = NetworkLedger.shared.snapshot() }
        .confirmationDialog("Forget these receipts?",
                            isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                NetworkLedger.shared.forget()
                entries = []
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Named plainly, because the alternative is a page that implies it saw
    /// everything. These are the request paths that don't ride an
    /// instrumented transport — see `NetworkLedger`'s own doc.
    private var ceiling: String {
        "Hosts you named yourself — a feed, a store, a saved site — are filed under the app that asked for them. Not recorded: pictures loading as you scroll, and live wallet-app connections."
    }

    private func row(_ receipt: Receipt) -> some View {
        HStack(spacing: DS.Space.s3) {
            leadingIcon(receipt.service)
            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.service ?? receipt.entry.host)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(receipt.entry.host)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                Text(summary(receipt.entry))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s1)
    }

    @ViewBuilder
    private func leadingIcon(_ service: String?) -> some View {
        if let service, BridgeCatalog.offers.contains(where: { $0.name == service }) {
            BridgeIcon(name: service, size: DS.Mark.list)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.list), style: .continuous)
                .fill(service == nil ? DS.attention.opacity(0.16) : DS.gray200)
                .frame(width: DS.Mark.list, height: DS.Mark.list)
                .overlay {
                    Image(systemName: service == nil ? "questionmark" : "network")
                        .dsGlyph(16)
                        .foregroundStyle(service == nil ? DS.attention : DS.textSecondary)
                }
        }
    }

    private func summary(_ entry: NetworkLedger.Entry) -> String {
        let requests = entry.count == 1 ? "1 request" : "\(entry.count) requests"
        let when = entry.last.formatted(.relative(presentation: .named))
        return "\(requests) · last \(when)"
    }
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
                // `stat24`, not `heading28` (2026-08-28). `heading28` is the
                // LEDE rung — a sentence — and a figure borrowing it put this
                // count between the two money rungs either side of it,
                // matching neither. `stat24` is the ramp's own stat-card rung
                // and is what every other card-leading figure in the app uses.
                Text(reach.requests.formatted())
                    .dsText(.stat24).monospacedDigit()
                    .foregroundStyle(DS.textPrimary)
                Text(unit).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                verdict
            }
            Text(subline)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            UnitTreemap(count: reach.cells.count, height: 180, cell: { i in
                face(reach.cells[i])
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
        let tone = clean ? DS.confirm : DS.attention
        return HStack(spacing: 4) {
            Image(systemName: clean ? "checkmark" : "exclamationmark.triangle.fill")
                .dsSymbolSwap(clean)
                .dsGlyph(10, weight: .bold)
            Text(word).dsText(.label12).fontWeight(.semibold)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, 4)
        .background(tone.opacity(0.16), in: Capsule(style: .continuous))
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

    private func face(_ cell: NetworkReceiptsInsight.Cell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.label)
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(cell.isTail ? DS.textSecondary : DS.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.8)
            // The tail is a sum, not a service — printing its count beside a
            // name would read as one thing that made that many requests.
            if !cell.isTail {
                Text("\(cell.count)")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
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
