import SwiftUI

/// One Settings page drawn in the Accounts pane (prd §876, user: "we should
/// put all settings in the pane too").
///
/// Each case is the SAME view the row raises as a sheet where there is no
/// pane — never a second copy — told it is in a pane by `dsInPane`, which is
/// how a tray drops its Done and scrolls as a page.
struct SettingsPageView: View {
    let page: SettingsPage
    @Environment(HomeRoute.self) private var route
    @Environment(\.dsTitleBack) private var titleBack

    var body: some View {
        Group {
            switch page {
            case .data:
                AccountDetailSheet(detail: .data)
            case .notifications:
                AccountDetailSheet(detail: .notifications)
            case .language:
                LanguagePickerSheet()
            case .licenses:
                AccountDetailSheet(detail: .licenses)
            }
        }
        .environment(\.dsInPane, true)
        // Pushed beside Sources on the phone (prd §1321): "Sources · Data".
        .environment(\.dsTitleBack, route.sheet == nil && SettingsHome.bandSearches
                     ? DSTitleBack(word: String(localized: "Library"), action: { route.goBack() }) : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
