import SwiftUI

/// Settings, its own pushed screen again (prd §933, 2026-09-26).
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                DSScreenHead(title: Text("Addresses"))
                DSSlabField(placeholder: String(localized: "Search"),
                            text: $query, actionLabel: "",
                            focus: $searchFocused,
                            glyph: "magnifyingglass", clearable: true,
                            size: .slab, submitLabel: .search, action: {})
                AddressesSection(query: query)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s4)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth(.reading)
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(Text("Addresses"))
        .toolbar(.hidden, for: .navigationBar)
    }
}
