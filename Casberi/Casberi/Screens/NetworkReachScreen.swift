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

    private var reachingNow: [NetworkReach.Endpoint] {
        NetworkReach.endpoints.filter { endpoint in
            switch endpoint.reach {
            case .always: true
            case .whenConnected(let bridge): connectedNames.contains(bridge)
            case .onTapWithKey: false
            }
        }
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
                Text("Casberi has no server. Every request below goes straight from \(DS.device) to the service named.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            group(String(localized: "Reaching now"), reachingNow,
                  footer: String(localized: "The always-on essentials, plus the apps you've connected. Each reaches only its own service."))

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
        .dsScreenTitle("What this app reaches")
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
            BridgeIcon(name: endpoint.service, size: 38)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(38), style: .continuous)
                .fill(DS.gray200)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: infraSymbol(endpoint))
                        .font(.system(size: 16, weight: .semibold))
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
