import SwiftUI

/// The feed's half of the Mac keyboard walk (2026-07-31) — the list in
/// list+detail, arrow-walkable.
///
/// The two-pane shape landed on 2026-07-25 (`PadLayout`) and the Mac chrome
/// pass on 2026-07-28, but the app still answered only to a pointer: ↑/↓ moved
/// nothing, Return opened nothing, and the pane could only ever be filled by
/// clicking. A list+detail app you cannot arrow through reads as a port
/// however good the rest of its chrome is — this is the gap that was left.
///
/// The keys themselves are menu items (`MacMenuBar` / `CasberiApp.commands`),
/// not an `onKeyPress` on a focusable view, and that is deliberate: a menu
/// item's key equivalent is delivered through the responder chain with no
/// focus to win first, it can be DISABLED to hand the key straight back to a
/// text field (see `ShellChrome.canWalk`), and it puts the commands somewhere
/// a person can find them — which is most of what "feels like a Mac app"
/// actually means. This modifier is the other end: it publishes what there is
/// to walk, scrolls to whatever the menu selected, and opens it.
///
/// Everything here is inert off Mac. `walkIDs` composes an empty array on
/// iPhone and iPad, `canWalk` is false, and every branch below returns early —
/// the phone pays one `Bool` per feed page.
struct KeyboardWalk: ViewModifier {
    let isActive: Bool
    let chrome: ShellChrome
    let proxy: ScrollViewProxy
    /// The room's RENDERED rows in render order — see `FeedScreen.walkRowIDs`,
    /// which is where the reasoning lives (a bundled All-room day drops its
    /// members from the tree, so the corpus order is not the row order). Ids,
    /// never models: a `[Thing]` parked on the shell's long-lived `chrome` is
    /// the 2026-07-24 crash class by construction.
    let ids: [String]
    /// Resolve and open — the feed page owns `openThing`, so the pane-or-sheet
    /// split stays in the one place that already decides it.
    let open: (String) -> Void
    /// This window's pane selection (per-window since `SceneState`), read to
    /// tell "the pane is already open" from "the ring is only moving".
    @Environment(PadDetailSelection.self) private var detail

    func body(content: Content) -> some View {
        content
            // What there is to walk. Only the page in force publishes: three
            // pages are mounted at once (the pager keeps neighbours alive),
            // and a background page writing its own rows here would hand the
            // menu bar a list for a room nobody is looking at.
            .onChange(of: ids, initial: true) { _, ids in
                guard isActive else { return }
                chrome.walkOrder = ids
                // A row that just left the feed can't stay selected.
                if let selected = chrome.walkSelected, !ids.contains(selected) {
                    chrome.walkSelected = nil
                }
            }
            // Changing rooms drops the selection. The highlight belongs to the
            // room it was set in — carried across a chip switch it would sit on
            // a row the new room doesn't contain, with the menu counting along
            // the old room's order.
            //
            // Only the LEAVING half is here: `walkRowIDs` returns [] when
            // inactive, so becoming active changes `ids` from empty to the real
            // list and the handler above already republishes. (It can't be
            // folded INTO that handler either — the two inactive neighbour
            // pages also publish [], and a contains-check there would clear the
            // active page's selection.)
            .onChange(of: isActive) { _, now in
                guard !now, chrome.walkSelected != nil else { return }
                chrome.walkSelected = nil
            }
            // Follow the selection. `KeyedThing.id` is the row's own
            // `uuidString`, which is exactly what every `ForEach` in this feed
            // is keyed on, so the scroll target and the list identity are the
            // same value rather than two things kept in step by hand.
            .onChange(of: chrome.walkSelected) { _, selected in
                guard isActive, let selected else { return }
                withAnimation(DS.Motion.standard) {
                    proxy.scrollTo(selected, anchor: .center)
                }
                // Once a thing is OPEN in the pane, arrowing moves what the
                // pane is showing — the list+detail idiom (Mail, Finder), and
                // the reason to walk with the keyboard at all. Before that,
                // arrowing only moves the ring: pre-filling a pane the person
                // hasn't opened would turn a glance down the list into a
                // dozen documents rendering behind it.
                if detail.thing != nil {
                    open(selected)
                }
            }
            // Return.
            .onChange(of: chrome.walkOpenPulse) { _, _ in
                guard isActive, let selected = chrome.walkSelected else { return }
                open(selected)
            }
    }
}
