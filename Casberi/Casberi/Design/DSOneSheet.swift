import SwiftUI

/// **ONE SHEET AT A TIME (prd §1238, user: "a sheet opens on top of a sheet
/// … isn't that weird?").** One route either rises as a sheet or, where the
/// screen already stands in a sheet, PUSHES inside that sheet's stack, with
/// the system's Back. `pushes` decides per route: the system's own pickers
/// and a tray that keeps its own stack still rise.
struct DSOneSheet<Route: Identifiable, Raised: View, Pushed: View>: ViewModifier {
    @Binding var route: Route?
    let pushes: (Route) -> Bool
    @ViewBuilder let raised: (Route) -> Raised
    @ViewBuilder let pushed: (Route) -> Pushed

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { route.flatMap { pushes($0) ? nil : $0 } },
                                 set: { route = $0 })) { raised($0) }
            .navigationDestination(isPresented: Binding(get: { route.map(pushes) ?? false },
                                                        set: { if !$0 { route = nil } })) {
                if let current = route { pushed(current) }
            }
    }
}
