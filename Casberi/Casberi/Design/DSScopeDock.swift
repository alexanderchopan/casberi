import SwiftUI

/// A directory's category tiles on the PHONE'S BOTTOM LINE, in a glass capsule
/// beside the seat (prd §960, a tester via the user: "the category chips
/// should be at the bottom b/c you can't reach them at the top").
///
/// The room faces' arrangement (§935): the capsule starts where the seat
/// ends and shares its centre line, so the bottom of the screen is one row —
/// the face, then the tiles, scrolling sideways. It costs no height: a pushed
/// screen's `dsSeatClearance` already keeps its last row off that line, and
/// the list scrolls under the glass as it does under the seat.
///
/// **Phone only.** Where the rail stands there is no seat and the pointer
/// reaches the top as easily as the bottom, so `DSScopeDock.atBottom` is
/// false there and the caller keeps its strip inline. Both callers ask that
/// ONE question, so the inline strip and the capsule can never both draw.
///
/// **It stands down while the keyboard is up (prd §865)**: the keyboard
/// covers the seat, and the capsule is the seat's row. Not by
/// `dsStaysUnderKeyboard` — that belongs to the dock's two files, because on
/// a scroll view it pins the content under the keyboard (`dock-selftest.sh`).
struct DSScopeDock<Scope: DSTileScope>: ViewModifier {
    let sections: [Scope]
    let active: Scope
    var attention: Set<Scope> = []
    /// How far the content's bottom stands above the safe area's: a pushed
    /// screen stops at its seat clearance, a room's page (the Tokens packs)
    /// reaches the safe area itself, so it passes 0.
    var clearance: CGFloat = DSDock.seatClearance
    let onPick: (Scope) -> Void

    @Environment(ShellChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The capsule's height: a 52pt tile with 2pt of glass above and below —
    /// the dock chip's own frame, so the capsule reads as the seat's row.
    private static var height: CGFloat { DSDock.chipFrame(minimized: false) }

    /// Off the bottom edge so the capsule's CENTRE lands on the seat's,
    /// following the seat through the fold (`DSDock.SeatInset`).
    private var bottomInset: CGFloat {
        DSDock.agentBottomInset(fold: chrome.fold)
            + DSDock.agentSize(fold: chrome.fold) / 2 - Self.height / 2
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomLeading) {
            if sizeClass == .compact, sections.count > 2, !chrome.keyboardUp {
                DSScopeTiles(sections: sections, active: active,
                             attention: attention, strip: true, onPick: onPick)
                    .padding(.horizontal, DS.Space.s1)
                    .frame(height: Self.height)
                    .clipShape(Capsule())
                    .dsGlass(cornerRadius: Self.height / 2)
                    .padding(.leading, DSDock.agentSeat(minimized: false))
                    .padding(.trailing, DS.Space.s4)
                    // The overlay rides the screen, whose bottom is the TOP
                    // of the pushed screen's seat clearance; the seat is
                    // measured from the safe area's bottom, under it.
                    .offset(y: clearance - bottomInset)
                    .transition(.opacity)
            }
        }
    }
}

extension DSScopeDock {
    /// Whether this size class carries the tiles in the capsule. The one
    /// question both callers ask before drawing their inline strip.
    static func atBottom(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .compact
    }
}

extension View {
    /// Mounts `DSScopeDock` — pass an empty `sections` to take it down (a
    /// search in progress, a list with nothing to scope).
    func dsScopeDock<Scope: DSTileScope>(sections: [Scope], active: Scope,
                                         attention: Set<Scope> = [],
                                         clearance: CGFloat = DSDock.seatClearance,
                                         onPick: @escaping (Scope) -> Void) -> some View {
        modifier(DSScopeDock(sections: sections, active: active,
                             attention: attention, clearance: clearance,
                             onPick: onPick))
    }
}
