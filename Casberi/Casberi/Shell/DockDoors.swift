import SwiftUI

/// The dock's leading seat: your face, then the catalogue (prd §697,
/// 2026-09-11).
///
/// **This replaces the octopus, and the reason is the agent, not the dock.**
/// The berry stood here as the agent's own bar and opened a folder holding
/// Settings, Accounts and Ask (`DoorsStrip`, §591). The ask is deprecated
/// (user, 2026-09-11: *"the chat feature sucks. no one will use it"* —
/// *"honestly we are forcing this ... for now, deprecate"*), which left that
/// folder holding two doors and a dud, and a folder holding two doors is a
/// tap nobody needs: it is cheaper to draw the two doors.
///
/// **Order is Face · Grid · All** (user, same session). Both doors lead, so
/// the categories keep the trailing edge and the half-cell peek that says
/// there is more — the arrangement the strip already wears, with a two-mark
/// cluster in the seat a one-mark cluster used to have.
///
/// **Hosted on `RootShell`'s own layer, not inside the strip** — the seat the
/// octopus held. That is what makes Settings and Accounts reachable from a
/// pushed room, a bridge form and Settings itself, none of which the strip's
/// `safeAreaInset` survives (§357's rule, from the other direction).
///
/// **Two marks, ONE piece of glass.** `dsGlassDoor` merges them at a shared
/// radius (2026-08-06's union, which this is the second call site of), so the
/// cluster reads as one object standing beside the run of chips rather than as
/// the first two chips of it — the distinction `DSDock.seam` exists to state.
struct DockDoors: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    /// Settings — the avatar door.
    var onSettings: () -> Void
    /// The catalogue — the grid door.
    var onApps: () -> Void
    /// The zoom anchors both doors grow out of, shared with the iPad rail's
    /// own pair under the same two ids.
    var zoomNS: Namespace.ID? = nil
    /// The two doors' glass union. Owned here: this pair exists nowhere else.
    @Namespace private var glassNS

    private var markSize: CGFloat { DSDock.agentSize(fold: chrome.fold) }
    private var union: DSGlassUnion { DSGlassUnion(id: "dockDoors", namespace: glassNS) }

    var body: some View {
        DSGlassContainer(spacing: 0) {
            HStack(spacing: DSDock.doorGap) {
                AvatarChip(onSettings: onSettings,
                           refreshSpin: chrome.refreshPulse,
                           pullTension: chrome.pullTension,
                           zoomNS: zoomNS,
                           doorUnion: union,
                           size: markSize)
                catalogueDoor
            }
        }
    }

    /// The catalogue door. `AppsDoor` carries the breakage fill, the attention
    /// hue, the pulse and the healed bounce, so the one alarm the shell has
    /// keeps the seat it has always had.
    private var catalogueDoor: some View {
        Button {
            DSHaptic.tap()
            onApps()
        } label: {
            ZStack {
                if let zoomNS {
                    AppsDoor().matchedTransitionSource(id: "appsDoor", in: zoomNS)
                } else {
                    AppsDoor()
                }
            }
            .frame(width: markSize, height: markSize)
            .dsGlassDoor(union)
            // THE DOOR IS THE CIRCLE, not the glyph inside it — the 2026-07-26
            // lesson, three user reports deep: a `.frame()` does not make its
            // empty space hit-testable, so without this the press has to land
            // on a 21pt symbol inside a 46pt circle that looks tappable
            // everywhere, and near-miss taps fall through to the feed.
            .contentShape(Circle())
            .dsHover()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bridges.attentionCount > 0
                            ? Text("Accounts, needs attention")
                            : Text("Accounts"))
        .dsTooltip(String(localized: "Accounts"))
    }
}
