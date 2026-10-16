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
                // are their own door, Apps. A place in You (prd §1129).
                YouHead(place: .settings)
                SettingsRows()
            }
            .padding(.horizontal, DS.Space.s4)
            // The You row stands where a feed's title stands (prd §1129):
            // the feed's `s2` above it, so a switch moves nothing.
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s4)
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
