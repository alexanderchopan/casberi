import SwiftUI

/// Dragging a row OUT of the app (2026-08-17) — the half of Mac drag-and-drop
/// this app never had.
///
/// Dropping IN has worked since the shell grew its `dropDestination` pair and
/// `DropGlow`: a URL or a string dragged onto the window lands as a thing. The
/// reverse — pulling a thing out into Finder, Mail, a note, a message — is
/// what a Mac user assumes the moment the first direction works, and it
/// answered nothing.
///
/// ## Not a second gesture
///
/// A row's context menu already answers the secondary click: `.contextMenu` is
/// cross-platform and Catalyst binds it to right-click for free, so the verbs
/// the 2026-07-16 ruling put on a long-press (Open in app, Translate, Pin,
/// Share) have been a right-click away on Mac the whole time. This adds no
/// menu and no click of its own — a drag is a gesture touch already spends on
/// scrolling and a pointer has spare, which is the same argument that let the
/// secondary click exist at all.
///
/// ## What leaves
///
/// A link exports its URL, so a drop into a browser, a note or a message
/// behaves the way every other link on the machine does. Anything else exports
/// the agent rendering (`AgentContext.render`) — the app's own answer to "what
/// IS this thing", and **already redacted on the way out**, which is the point
/// that matters here: a drag out is an export, so the secret-scan boundary
/// applies to it exactly as it applies to a keyed request. Re-deriving the
/// payload inside the closure rather than capturing it is deliberate for the
/// same reason as the liveness check below — the drag may happen an hour after
/// the row was built.
///
/// ## Liveness
///
/// The closure outlives the frame that made it, which is a longer fuse than
/// any view in the corollary chain: a foreground bridge sweep can delete this
/// row while the pointer is resting on it. It re-checks `isLive` before
/// touching a stored property and exports an empty string for a row that has
/// gone, rather than trapping inside a drag session.
///
/// Compiles to `self` off Catalyst. iPad pointer drag is real but a trackpad
/// there is an accessory rather than the assumption, and the phone pays
/// nothing.
extension View {
    func macRowDrag(_ thing: Thing) -> some View {
        #if targetEnvironment(macCatalyst)
        // The `@autoclosure` form, not the trailing-closure one: the closure
        // overload (`draggable(_:containerNamespace:_:)`) is macOS-only and is
        // `unavailable in iOS`, which is what Catalyst compiles against. The
        // autoclosure is still evaluated when the drag BEGINS rather than when
        // the row is built, which is the property this needs.
        draggable(MacRowDragPayload.text(for: thing))
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
enum MacRowDragPayload {
    static func text(for thing: Thing) -> String {
        guard thing.isLive else { return "" }
        for candidate in [thing.externalLink, thing.content] {
            guard let candidate, let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            return url.absoluteString
        }
        return AgentContext.render(thing)
    }
}
#endif
