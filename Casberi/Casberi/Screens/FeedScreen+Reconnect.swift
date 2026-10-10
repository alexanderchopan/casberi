import SwiftUI

// Home names every app that stopped working (prd §1162).
extension FeedScreen {
    /// The apps that need reconnecting, at the head of Home, each a door to
    /// its own page — where the fix is.
    ///
    /// **Why Home.** A refused key or a lapsed session was visible only on that
    /// app's own page, as an unnamed ring on the face ("Apps, needs
    /// attention"), and in red in Settings › Apps. Nothing on Home, the screen
    /// people actually open, said WHICH app had stopped, so a dead connection
    /// went quiet for weeks while its rows simply stopped arriving — the
    /// silence reads as "nothing happened", which is §299's failure one screen
    /// further out.
    ///
    /// Settings' row anatomy, one per app (`SettingsHome.appRow`): the icon,
    /// the name, the state at the trailing edge in the attention ink. Drawn
    /// only while something is broken; a healthy Home is unchanged.
    @ViewBuilder
    var reconnectSection: some View {
        let broken = bridges.bridges.filter { $0.status == .attention }
        if !broken.isEmpty {
            Section {
                ForEach(broken) { app in
                    DSPushRow(title: Text(verbatim: app.name),
                              // "attention", not "reconnecting": a seat also
                              // breaks for local reasons — Photos' access
                              // narrowed, a folder no longer reachable — where
                              // there is nothing to reconnect. Its page says which.
                              fact: Text("Needs attention"),
                              factTone: DS.attentionInk) {
                        route.openAccount(BridgeRouter.destination(forID: app.id))
                    } leading: {
                        BridgeIcon(name: app.name, size: DS.Face.row)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: 0, trailing: DSRoomChassis.rowInset))
                    .feedRowBackground()
                    .listRowSeparator(.hidden)
                }
            }
        }
    }
}
