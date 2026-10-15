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
                if let current = route { pushed(current).dsSheetStep() }
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
                content().environment(\.dsInPane, true).dsSheetStep()
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

extension View {
    /// A page that RISES ON ITS OWN hosts a stack, so what it opens pushes
    /// inside it instead of rising over it (prd §1315, user: "i hate that …
    /// i'd rather get rid of that behavior"). The system bar is hidden and
    /// a pushed step's way back is the seat at the foot (`dsInSheet`, §1304).
    /// Inside another sheet's stack it adds nothing; the Mac keeps its own
    /// presentations.
    @ViewBuilder func dsRaisedStack() -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        DSSheetStack { self.toolbar(.hidden, for: .navigationBar) }
            .environment(\.dsInSheet, true)
        #endif
    }
}

/// **A STACK ONLY WHEN STANDING ALONE (prd §1247).** A view that wraps
/// itself in a `NavigationStack` for its own pushes would nest a stack when
/// it is itself pushed inside a sheet's; this adds the stack only when the
/// view stands alone, and marks it as a sheet's stack so what it raises
/// pushes too.
struct DSSheetStack<Content: View>: View {
    @Environment(\.dsInSheetStack) private var inSheetStack
    @ViewBuilder let content: () -> Content

    var body: some View {
        if inSheetStack {
            content()
        } else {
            NavigationStack { content().environment(\.dsInSheetStack, true) }
        }
    }
}

/// `DSSheetStack` for a stack that walks a typed path: alone it owns the
/// path; inside a sheet's stack the caller pushes through an item instead.
struct DSPathStack<Element: Hashable, Content: View>: View {
    @Binding var path: [Element]
    let alone: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if alone {
            NavigationStack(path: $path) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// Applies `transform` only when `condition` holds.
    @ViewBuilder
    func dsIf<T: View>(_ condition: Bool, _ transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
