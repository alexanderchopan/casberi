import SwiftUI

/// Settings, its own pushed screen again (prd §933, 2026-09-26; again since
/// §1111, after §1050g folded it under Apps' list for four days).
///
/// §796 made Settings a section of Accounts so the dock's face could toggle
/// ONE screen in and out; the switcher was doing a menu's job. The rooms tray
/// (§930) is that menu now, with a door per place, so the HIG's own rule for
/// a segmented control applies again — closely related views of one thing,
/// never navigation between different things — and Settings is not a view of
/// the app catalog. `SettingsRows` is untouched: the same rows, under their
/// own name, with the face as the way back like every pushed screen (§767).
struct SettingsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                // Casberi's own settings, and only them (prd §1111): the
                // tray's Settings door opens this page again, and the apps
                // are their own door, Apps.
                DSScreenHead(title: Text("Settings"))
                SettingsRows()
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s4)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        // The name is in the content and the way back is the dock's seat, so
        // nothing stands at the top edge (prd §767).
        .navigationTitle(Text("Settings"))
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Addresses, its own pushed screen (prd §933): a directory of the parties
/// behind the accounts, the way Contacts is its own app. It was Accounts'
/// fourth section since §916's amendment, for §796's reason, and leaves for
/// §933's. The search field is the section's own filter (§916: it filters the
/// list you are on, never resolves into the catalog), so it moves with it.
struct AddressesScreen: View {
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// The list's scope and the scopes it holds, up here because on the phone
    /// the tiles ride the capsule beside the seat (`DSScopeDock`, prd §960).
    @State private var scope = AddressScope(name: nil)
    @State private var scopes: [AddressScope] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                DSScreenHead(title: Text("Addresses"))
                DSSlabField(placeholder: String(localized: "Search"),
                            text: $query, actionLabel: "",
                            focus: $searchFocused,
                            glyph: "magnifyingglass", clearable: true,
                            size: .slab, submitLabel: .search, action: {})
                AddressesSection(query: query, scope: $scope) { scopes = $0 }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s4)
        }
        .dsScopeDock(sections: query.isEmpty ? scopes : [], active: scope) { picked in
            withAnimation(DS.Motion.standard) { scope = picked }
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(Text("Addresses"))
        .toolbar(.hidden, for: .navigationBar)
    }
}
