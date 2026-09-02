import SwiftUI

/// "What this app reaches" (prd §205) — every service Casberi talks to,
/// straight from this iPhone, and exactly what each call is for. The privacy
/// promise ("no server, nothing routes through us") made legible: a person
/// can read the whole list and see that connected services reach out, and the
/// rest don't until you connect them.
///
/// Reached from the Privacy sheet — the ONE privacy home (user, 2026-07-24),
/// where the at-rest half (on device / iCloud) and this in-motion half (what
/// leaves the iPhone) sit together rather than as two competing rows. Three
/// groups: what's reaching now (always-on + your connected apps), what would
/// reach only if you connect it, and the agent key that reaches only when you
/// tap "Try with your key".
struct NetworkReachScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var connectedNames: Set<String> {
        Set(store.bridges.filter { $0.status == .connected }.map(\.name))
    }

    /// The rule lives in `NetworkReach.reachingNow(connected:)` (2026-08-18)
    /// so the Privacy tray's door, which now states this count, can never
    /// disagree with the list it opens.
    private var reachingNow: [NetworkReach.Endpoint] {
        NetworkReach.reachingNow(connected: connectedNames)
    }

    private var available: [NetworkReach.Endpoint] {
        NetworkReach.endpoints.filter { endpoint in
            if case .whenConnected(let bridge) = endpoint.reach {
                return !connectedNames.contains(bridge)
            }
            return false
        }
    }

    private var onTap: [NetworkReach.Endpoint] {
        NetworkReach.endpoints.filter {
            if case .onTapWithKey = $0.reach { return true }
            return false
        }
    }

    var body: some View {
        List {
            Section {
                // THE CLAIM TAKES THE HEAD RUNG (prd §564). This screen exists
                // to make ONE promise checkable, and the promise was drawn at
                // `subhead13` — the second-smallest rung on the ramp — above a
                // list of sixty services each of whose NAME was set larger than
                // it. That is §563's inversion, on the screen carrying the
                // app's central claim: the most important thing on it was the
                // quietest thing on it.
                //
                // **Split into two keys rather than set whole.** At the head
                // rung a trailing clause is a paragraph wearing a headline
                // (§559), and the second sentence is the MECHANISM, not the
                // claim. The four translations were carried across rather than
                // orphaned (§561's rule — a re-worded label silently doubles a
                // key and re-bills a translator), split at each language's own
                // sentence terminator; the format specifier sits entirely in
                // the second half of all four, so the crown carries none.
                //
                // No colour and no tile: this screen has no act. The style here
                // is the proportion alone.
                Text("There is no server.")
                    .dsText(.heading34).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                Text("Every request below goes straight from \(DS.device) to the service named.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                // The other half of "goes straight", said out loud (2026-08-10).
                //
                // Nothing on this screen ever claimed otherwise, so this is not
                // a correction — it is the §83 rule applied to a SILENCE. A
                // person with iCloud Private Relay switched on, reading a list
                // of sixty services this app reaches, can reasonably conclude
                // those reaches are relayed and their address hidden. They are
                // not: Private Relay covers Safari browsing, DNS and insecure
                // connections, and an app's own HTTPS requests are none of
                // those. Leaving that to be assumed on the one screen whose
                // entire job is making the privacy claim checkable would be the
                // fake status this app refuses everywhere else — and the more
                // careful the rest of the screen is, the more it would be
                // trusted.
                Text("Going straight means each service sees your IP, as any app or website does. iCloud Private Relay covers Safari browsing, not an app's own requests.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            group(String(localized: "Reaching now"), reachingNow,
                  footer: String(localized: "The always-on essentials, plus the apps you've connected."))

            if !onTap.isEmpty {
                group(String(localized: "Only when you tap"), onTap, footer: nil)
            }

            if !available.isEmpty {
                group(String(localized: "Only if you connect them"), available,
                      footer: String(localized: "These reach nothing until you connect them."))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        // **THIS SHEET HAD NO WAY OUT** (prd §560, 2026-09-01). It is presented
        // only from `AccountDetailSheet` and carried no close control at all,
        // so the only exit was a drag — and on Catalyst a form sheet has no
        // drag to give, which makes it a sheet a Mac cannot dismiss. The
        // cohesion pass found it by asking what every nav sheet's exit is; a
        // screenshot of it looks completely correct.
        .navigationTitle(Text("What this app reaches"))
        .navigationBarTitleDisplayMode(.inline)
        .dsSheetDismiss { dismiss() }
    }

    private func group(_ title: String, _ endpoints: [NetworkReach.Endpoint],
                       footer: String?) -> some View {
        Section {
            ForEach(endpoints) { endpoint in
                row(endpoint).dsListCardRow()
            }
        } header: {
            Text(title).dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            if let footer {
                Text(footer).dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func row(_ endpoint: NetworkReach.Endpoint) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            leadingIcon(endpoint)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(endpoint.service)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(endpoint.purpose)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(endpoint.hosts.joined(separator: " · "))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s1)
    }

    /// A real catalog service wears its brand mark; the infra/always/on-tap
    /// entries (no brand) wear a category SF symbol on a quiet badge.
    @ViewBuilder
    private func leadingIcon(_ endpoint: NetworkReach.Endpoint) -> some View {
        if isCatalogService(endpoint.service) {
            BridgeIcon(name: endpoint.service, size: DS.Mark.list)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.list), style: .continuous)
                .fill(DS.gray200)
                .frame(width: DS.Mark.list, height: DS.Mark.list)
                .overlay(
                    Image(systemName: infraSymbol(endpoint))
                        .dsGlyph(16)
                        .foregroundStyle(DS.textSecondary)
                )
        }
    }

    private func isCatalogService(_ name: String) -> Bool {
        BridgeCatalog.offers.contains { $0.name == name }
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
}
