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

extension EnvironmentValues {
    /// True inside a sheet that hosts a `NavigationStack` (the app sheet, the
    /// route sheet, the connect form): a presentation made there pushes
    /// instead of rising (prd §1238).
    @Entry var dsInSheetStack: Bool = false
}

extension View {
    /// `.sheet(isPresented:)`, or a push where `pushes` (prd §1238).
    func dsOneSheet<Content: View>(isPresented: Binding<Bool>, pushes: Bool,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        self
            .sheet(isPresented: Binding(get: { isPresented.wrappedValue && !pushes },
                                        set: { isPresented.wrappedValue = $0 }), content: content)
            .navigationDestination(isPresented: Binding(get: { isPresented.wrappedValue && pushes },
                                                        set: { isPresented.wrappedValue = $0 })) {
                content().environment(\.dsInPane, true)
            }
    }

    /// `.sheet(item:)`, or a push where `pushes` says so for that item.
    func dsOneSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, pushes: @escaping (Item) -> Bool,
                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(DSOneSheet(route: item, pushes: pushes,
                            raised: { content($0) },
                            pushed: { content($0).environment(\.dsInPane, true) }))
    }
}
