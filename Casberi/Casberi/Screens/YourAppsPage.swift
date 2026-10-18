import SwiftUI

/// **SETTINGS › APPS (prd §1418, user: "and then in settings only the apps
/// you are connected to will be there right?").** A tap on an app in Library
/// goes to it, so the plain door to each one's page is here: every app
/// Library marks yours (the green dot, `SettingsHome.isYours`), A–Z, its
/// state on the line, a broken one in the attention ink. Adding an app stays
/// Library's.
struct YourAppsPage: View {
    @Environment(BridgeStore.self) private var bridges
    @Environment(HomeRoute.self) private var route

    /// The apps Library draws with the green dot: in the catalogue, in
    /// Library (`SettingsHome.inLibrary`), not paused. A–Z.
    static func apps(_ bridges: [BridgeApp]) -> [BridgeApp] {
        let names = Set(BridgeCatalog.offers.filter(SettingsHome.inLibrary).map(\.name))
        return bridges
            .filter { $0.status != .paused && names.contains($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let apps = Self.apps(bridges.bridges)
        ScrollView {
            if apps.isEmpty {
                DSEmptyState(headline: DSProse.text("None yet"),
                             words: Text("The apps you add in Library list here."),
                             scale: .list(rows: 3))
                    .padding(.vertical, DS.Space.s4)
            } else {
                // Spaced as Library's own A–Z rows are (`appsByLetter`).
                LazyVStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(apps, id: \.id) { app in
                        DSPushRow(title: Text(verbatim: app.name),
                                  subtitle: Text(verbatim: app.statusLine),
                                  subtitleTone: app.status == .attention ? DS.attentionInk : DS.textTertiary) {
                            route.pushBridge(BridgeRouter.destination(forID: app.id))
                        } leading: {
                            BridgeIcon(name: app.name, size: DS.Face.row)
                                .frame(width: DS.Mark.row, height: DS.Mark.row)
                        }
                    }
                }
                .padding(.horizontal, DSRoomChassis.rowInset)
                .padding(.top, DS.Space.s2)
                .padding(.bottom, ShellMetrics.bottomInset + DS.Space.s4)
            }
        }
        .scrollContentBackground(.hidden)
        #if DEBUG
        .onAppear { NSLog("[Casberi] yourApps| %d | %@", apps.count, apps.map(\.name).joined(separator: ",")) }
        #endif
    }
}
