import SwiftUI

/// The four destinations that are NOT a feed (prd §591, 2026-09-03).
///
/// **It replaces the sources tray, and the reason is the dock.** Until §591 the
/// agent bar's tap raised a panel holding every source, grouped by category —
/// a map of the same set the chip strip ran along the top of the screen. Two
/// surfaces for one set was defensible while the strip was at the top and out
/// of thumb reach, since the panel was the reachable one. §591 moved the strip
/// to the bottom edge and put the bar in its leading seat, at which point the
/// map sat one thumb-width from the road it maps, and the user's own reading
/// (2026-09-03) was that it had become redundant: *"maybe the your feeds tray
/// opens up settings app catalog address book and agent only"*.
///
/// So the panel keeps its position, its glass, its drag and its All capsule,
/// and changes what is inside it: the agent, the catalogue, the address book
/// and settings — every door in this app that does not lead to a feed, and
/// nothing that does.
///
/// **THE AGENT IS A ROW HERE, and that is the cost this panel was chosen
/// with.** It used to be a 0.45s hold on the bar, so asking a question was one
/// gesture; it is now a tap and a tap. That is a real price for the app's
/// headline verb, paid deliberately (user: *"and no long press for it"*,
/// *"that simplifies it!"*) to end a three-round argument about which of two
/// destinations a hidden gesture should hide — §384 gave the hold to the tray,
/// §390 gave it to the agent, and §550 then had to ship a one-time capsule
/// whose whole job was to teach that the gesture existed. One control, one
/// gesture, one panel, everything labelled.
///
/// It is also not the only road: a typed ask, a kept-ask pill, the day strip,
/// the Daily Brief quick action, `casberi://ask?q=`, the widgets' ask tiles and
/// ⌘K on a Mac all still open the agent directly, and every one of them arrives
/// with the question already in hand, which this row cannot.
///
/// **Ordered by what the tap was for, not alphabetically.** The agent leads
/// because it is what the bar drew before this panel existed and what the berry
/// on the bar depicts; the catalogue is second because adding a feed is the
/// only other thing that changes what the dock holds; the address book and
/// settings follow as the two references. No counts, no state, no badges — a
/// door says where it goes.
struct DoorsPanel: View {
    let onAgent: () -> Void
    let onOpenCatalog: () -> Void
    let onOpenAddressBook: () -> Void
    let onSettings: () -> Void

    /// One row's full height — `DSDoorRow` draws its own vertical padding, and
    /// this is the measured result rather than a target: the panel has to state
    /// a height before the rows exist (see `SourcesOverlay`, which sizes its
    /// frame from `panelHeight`), so a row that grows without this constant
    /// moving would be clipped or would leave a hole.
    private static let rowHeight: CGFloat = 52

    /// What the panel asks for, and all it ever asks for.
    ///
    /// The tray it replaced had two heights — a resting one and a taller one
    /// you could drag up to — because a grid of forty sources genuinely has
    /// more to show than fits. Four rows do not, so both answers are the same
    /// number and the panel's own `canGrow` correctly resolves to false: the
    /// drag still dismisses and no longer offers to expand onto nothing.
    var panelHeight: CGFloat {
        Self.rowHeight * 4 + DS.Space.s4 * 2
    }
    var naturalPanelHeight: CGFloat { panelHeight }

    var body: some View {
        VStack(spacing: 0) {
            DSDoorRow(icon: "sparkles", label: "Ask your things", act: onAgent)
            DSDoorRow(icon: "square.grid.2x2", label: "Apps", act: onOpenCatalog)
            DSDoorRow(icon: "person.text.rectangle", label: "Address book",
                      act: onOpenAddressBook)
            DSDoorRow(icon: "gearshape", label: "Settings", act: onSettings)
        }
        .padding(.vertical, DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
