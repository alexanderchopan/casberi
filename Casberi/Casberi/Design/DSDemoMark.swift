import SwiftUI

/// **THE DEMO'S STANDING MARK IS A PILL THAT FLOATS, AND NOTHING ON THE PAGE
/// MOVES FOR IT (prd §919, 2026-09-25).**
///
/// The marking was a `safeAreaInset` on the top of `MainSurface` (§591, §864):
/// every demo screen's lead began a band lower than the same room outside the
/// demo, it was the one piece of chrome left on the top edge after §752 and
/// §767, and a pushed screen — resolved past that inset — carried no marking
/// at all. The user asked whether content sitting somewhere else than in the
/// real app takes away from the demo. Mocked on the real rooms, an overlay has
/// nowhere to float: every room opens on the box (§906) and the lead's
/// statement starts at the well's top, so every overlay landed on the one
/// sentence a room exists to say. So the well ABSORBS it. The pill draws over
/// the lead; the lead's words step down inside their fixed height
/// (`leadClearance`, taken out of `DSRoomChassis.leadBox` and given back as
/// top air by `dsRoomHeadBlock`); the page below is untouched. A pushed
/// screen has no well, so it RESERVES the same band (`screenClearance`, one
/// line at `MainSurface`'s resolver beside `dsSeatClearance`).
///
/// **Blue, not glass (user, with four fills mocked on the real rooms).** Glass
/// read as status and a real person walked past it (§864's own diagnosis).
/// Blue is the app's word for "tap me", and it holds on both themes, where a white pill vanishes on
/// light. §746's two pills (`Chip`, `DSStamp`) gain a third, and it belongs
/// to the floating layer: a marking that carries its own way out.
@MainActor
enum DSDemoMark {
    /// A control gets a control's hit size — not the 34pt recording-indicator
    /// height the glass capsule had, which is what made it read as status.
    static let pillHeight: CGFloat = DS.Hit.min
    /// One step of air off the top edge (§752; the room gear it stood level
    /// with is gone, §937).
    static let pillTop: CGFloat = DS.Space.s2
    /// The air between the pill's foot and the first line under it.
    static let gap: CGFloat = DS.Space.s2

    /// Whether the mark is on screen at all: the demo is active and this is
    /// not a marketing capture (`DemoCapture`, the one door, §864).
    static var marking: Bool { DemoMode.isActive && !DemoCapture.hidesMarking }

    /// What a room's lead gives up INSIDE its well. The well stands at the
    /// screen's top (`dsRoomHeadPlacement` puts 0 or `s2` above it) and pads
    /// its words `s4`; the pill's foot is `pillTop + pillHeight` below the
    /// same edge. Spelled from the 0 case so a scoped head clears too.
    static var leadClearance: CGFloat {
        marking ? pillTop + pillHeight + gap - DS.Space.s4 : 0
    }

    /// What a pushed screen reserves at its top edge, having no well.
    static var screenClearance: CGFloat {
        marking ? pillTop + pillHeight + gap : 0
    }
}

/// The pill itself: whatever words it is handed, on `DS.tint`, with one lift.
/// Drawn HERE because a capsule behind content outside `Design/` is §746's
/// failure (`ds-template-audit.py` check C), and this one is a template with
/// one caller, `DemoBanner`.
struct DSDemoPill<Label: View>: View {
    @ViewBuilder let label: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, DS.Space.s4)
                .frame(minHeight: DSDemoMark.pillHeight)
                .background(DS.tint, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
                // The floating layer casts; content does not (§759). Without
                // it a flat blue pill reads as painted onto the well.
                .shadow(color: DS.cardShadow, radius: 12, x: 0, y: 8)
        }
        .buttonStyle(PressSpring())
        .dsHover()
    }
}

extension View {
    /// A pushed screen's top edge, left clear for the demo's pill — one line
    /// at `MainSurface`'s resolver beside `dsSeatClearance()`, and on the two
    /// destinations `FeedScreen` resolves itself.
    func dsDemoMarkClearance() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: DSDemoMark.screenClearance)
        }
    }
}
