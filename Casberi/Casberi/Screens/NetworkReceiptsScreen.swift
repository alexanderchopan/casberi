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

    private var receipts: [Receipt] {
        entries.map { Receipt(entry: $0, service: NetworkReach.service(forHost: $0.host)) }
    }

    /// Rows whose host the registry declares, and rows it doesn't. The second
    /// group should always be empty; it exists because the day it isn't is
    /// the day this screen earns its keep.
    private var declared: [Receipt] { receipts.filter { $0.service != nil } }
    private var undeclared: [Receipt] { receipts.filter { $0.service == nil } }

    var body: some View {
        List {
            Section {
                Text(entries.isEmpty
                     ? "Nothing yet. As Casberi talks to a service, it shows up here — the host, how many requests, and when the last one was."
                     : "Every service Casberi actually reached in the last seven days, recorded on \(DS.device) as it happened. Hosts and counts only — never what was asked.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !undeclared.isEmpty {
                Section {
                    ForEach(undeclared) { receipt in
                        row(receipt).dsListCardRow()
                    }
                } header: {
                    Text("Not on the list").dsText(.label12).foregroundStyle(DS.textTertiary)
                } footer: {
                    Text("These were reached but aren't declared in \"What this app reaches\". That's a bug in the list, not a hidden service — please report it.")
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
                    Text("Receipts are kept on \(DS.device) for seven days and never sync. Forgetting them changes nothing about what Casberi reaches.")
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("What it actually reached")
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
        "Recorded from the shared connection every app connection uses, plus your agent key and saved-link lookups. Not recorded: pictures loaded into rows as you scroll, and live wallet-app connections, which use their own connections."
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
            BridgeIcon(name: service, size: 38)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(38), style: .continuous)
                .fill(service == nil ? DS.attention.opacity(0.16) : DS.gray200)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: service == nil ? "questionmark" : "network")
                        .font(.system(size: 16, weight: .semibold))
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
