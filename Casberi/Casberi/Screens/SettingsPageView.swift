import SwiftUI

/// One Settings page drawn in the Accounts pane (prd §876, user: "we should
/// put all settings in the pane too").
///
/// Each case is the SAME view the row raises as a sheet where there is no
/// pane — never a second copy — told it is in a pane by `dsInPane`, which is
/// how a tray drops its Done and scrolls as a page. The two nav-sheet pages
/// (Diagnostics, Dock order) had their title in a navigation bar the pane
/// does not have, so they are named here with `DSScreenHead` (§767's rule for
/// a screen with no bar).
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
            case .diagnostics:
                headed("Diagnostics") { DiagnosticsScreen() }
            case .dockOrder:
                headed("Feed order") { CategoryOrderSheet() }
            }
        }
        .environment(\.dsInPane, true)
        // Pushed beside Sources on the phone (prd §1321): "Sources · Data".
        .environment(\.dsTitleBack, route.sheet == nil && SettingsHome.bandSearches
                     ? DSTitleBack(word: String(localized: "Sources"), action: { route.goBack() }) : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func headed<Content: View>(_ title: String,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Group {
                if route.sheet == nil && SettingsHome.bandSearches {
                    DSRoomTitleRow(title: String(localized: "Sources"),
                                   pick: String(localized: String.LocalizationValue(title)),
                                   onTitle: { route.goBack() })
                } else {
                    DSScreenHead(title: Text(LocalizedStringKey(title)))
                }
            }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s6)
            content()
        }
        .background(DS.surfaceSheet.ignoresSafeArea())
    }
}
