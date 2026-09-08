import SwiftUI

/// THE DOOR, HOSTED INSIDE A PRESENTED SHEET (prd §653). `AccountPage` routes
/// a door through its ONE presentation; a sheet it presents cannot do that —
/// it is already the presented one — so the key sheet's content gets this
/// host, which catches the same http(s) doors, marks the return leg, and
/// presents the in-app Safari sheet OVER the key sheet. Bankr's whole errand
/// (§529) lives in the key sheet once a key exists; without this it went to
/// real Safari and lost the paste it came back for.
struct AccountDoorHost<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var web: AccountDoorTarget?
    @State private var opened = false

    var body: some View {
        content()
            .environment(\.openURL, action)
            .environment(\.accountDoorOpened, opened)
            .sheet(item: $web) { DSWebSheet(url: $0.url) }
    }

    private var action: OpenURLAction {
        OpenURLAction { url in
            #if targetEnvironment(macCatalyst)
            return .systemAction
            #else
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return .systemAction }
            opened = true
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
