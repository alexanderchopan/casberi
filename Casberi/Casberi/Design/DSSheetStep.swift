import SwiftUI

/// **IN A SHEET, THE WAY BACK IS THE SEAT'S (prd §1304, user, 2026-10-14:
/// "this arrow is touching to top", then of the Back at the foot, "it's
/// quicker for user to reach", "and keeps controls in the dock").**
///
/// A step pushed inside a sheet (§1238) showed the system bar's glass Back
/// 16pt under the sheet's corner, and the system bar cannot be lowered
/// (`safeAreaPadding` on the stack does not move it, measured). Everywhere
/// else the way back is the dock's leading seat (§767), so a sheet's step
/// draws that seat: the same glass disc, the same chevron, the same place,
/// and the system Back goes. The edge swipe stays (`DSSwipeBack`), the
/// keyboard covers the disc as it covers the dock (§865), and nothing comes
/// to rest under it (`dsSeatClearance`, §829).
///
/// **Every push carries it** (`way-back-audit.py` check E): a destination
/// either wears `dsSheetStep()` or hides the back itself, as the shell's
/// own stack does where the dock's seat is the way back. Outside a sheet it
/// changes nothing, so one line serves a destination that pushes in a sheet
/// on the phone and in the window on the Mac.
private struct DSSheetStep: ViewModifier {
    @Environment(\.dsInSheet) private var inSheet
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        if inSheet {
            content
                .navigationBarBackButtonHidden(true)
                .background(DSSwipeBack())
                .dsSeatClearance()
                .overlay(alignment: .bottomLeading) {
                    SheetBackDoor { dismiss() }
                        .padding(.leading, DSDock.clusterInset)
                        .padding(.bottom, DSDock.agentBottomInset(minimized: false))
                        .dsStaysUnderKeyboard()
                }
        } else {
            content
        }
    }
}

/// The seat's back door (`AvatarChip(onBack:)`), unfolded: a sheet has no
/// strip to fold it, and no `ShellChrome` to read the fold from.
private struct SheetBackDoor: View {
    let action: () -> Void

    var body: some View {
        let size = DSDock.agentSize(minimized: false)
        Button {
            DSHaptic.tap()
            action()
        } label: {
            BackDoorGlyph()
                .frame(width: size, height: size)
                .dsGlassDoor(nil)
                .dsTapTarget(Circle())
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Back"))
    }
}

extension EnvironmentValues {
    /// True inside a presented sheet (set by `dsSheetCorner`, the one
    /// modifier every sheet family pins its corner through): a step pushed
    /// there draws the seat's back door (prd §1304).
    @Entry var dsInSheet: Bool = false
}

extension View {
    /// A pushed step's way back: the seat's disc inside a sheet (prd §1304),
    /// nothing elsewhere.
    func dsSheetStep() -> some View {
        modifier(DSSheetStep())
    }
}
