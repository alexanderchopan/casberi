import SwiftUI

/// Every Privy app, with a switch to hide it (prd §803e, user: "Hide an app").
/// Hiding only takes the row out of the feed and the room here; nothing is
/// sent to Privy. A `List` inside a sheet draws a bounded number of rows
/// (`RowWindow`, §657) — ninety apps is well inside it.
struct PrivyAppsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let store = PrivyHomeStore.shared
        let apps = store.apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        NavigationStack {
            List {
                ForEach(apps) { app in
                    let ref = PrivyHomeFeed.ref(app)
                    HStack(spacing: DS.Space.s3) {
                        PrivyAppMark(logoURL: app.logoURL)
                        DSToggleRow(title: Text(verbatim: app.name),
                                    detail: PrivyHomeFeed.lastUsed(app.lastActiveAt, now: .now).map { Text(verbatim: $0) },
                                    isOn: Binding(get: { !store.hidden.contains(ref) },
                                                  set: { store.setHidden(ref, !$0) }))
                    }
                    .dsListRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .dsScreenTitle(String(localized: "Apps in your feed"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}
