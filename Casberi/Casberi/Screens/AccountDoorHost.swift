import SwiftUI

/// THE DOOR, HOSTED INSIDE A PRESENTED SHEET (prd §653). `AccountPage` routes
/// a door through its ONE presentation; a sheet it presents cannot do that —
/// it is already the presented one — so the key sheet gets this host, which
/// catches the same http(s) doors, marks the return leg, and presents the
/// in-app Safari sheet OVER it. Bankr's whole errand (§529) lives in the key
/// sheet once a key exists; without this it went to real Safari and lost the
/// paste it came back for.
///
/// **Wrap the SHEET, never its content.** `AccountKeySheet` renders whatever
/// it is handed as a `List` row, so a host placed inside it hangs its `.sheet`
/// off a row — the shape CLAUDE.md records as paid for three times: a
/// presentation attached inside a `List` row resolves to the row's own
/// hosting controller, and the row's teardown can take the transition with it
/// ("the sheet rises PART WAY and closes again"). Used from the outside, the
/// modifier lands on the key sheet's `NavigationStack` instead, which is
/// exactly where `AccountPage` puts its own. The environment still reaches the
/// entry rows either way — it flows down through the List.
struct AccountDoorHost<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var web: AccountDoorTarget?
    @State private var opened = false

    var body: some View {
        content()
            .environment(\.openURL, action)
            .environment(\.accountDoorOpened, opened)
            .sheet(item: $web) { target in
                DSWebSheet(url: target.url) { web = nil }
            }
    }

    private var action: OpenURLAction {
        OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return .systemAction }
            // Stamped on BOTH sides — see `AccountPage.doorAction`: Mac opens
            // the door in a real browser beside the app, so it is the platform
            // that most needs the row holding out its hand on return.
            opened = true
            #if targetEnvironment(macCatalyst)
            return .systemAction
            #else
            web = AccountDoorTarget(url: url)
            return .handled
            #endif
        }
    }
}

private struct AccountDoorTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
