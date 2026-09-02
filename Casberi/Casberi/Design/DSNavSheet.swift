import SwiftUI

/// **THE NAV-SHEET CHASSIS — the third sheet family, given a name (prd §560,
/// 2026-09-01).**
///
/// This app presents sheets in three shapes and only two of them had a
/// component. `DSTray` owns the tray — the grabber, the `heading34` title, a
/// stated height, the surface, the detent. The three READING sheets
/// (`ThingSheetView`, `TokenQuickSheet`, `SocialPostSheet`) share
/// `[.medium, .large]` + `dsInk` + `dsSheetCorner` + `dsPageSheet`, and there
/// are few enough of them to keep in step by hand.
///
/// The third family is a `NavigationStack` with a title and a dismiss button.
/// Twelve sheets, no component, and therefore twelve independent answers to
/// three questions that a person crossing between them reads instantly:
///
///   • **the word** — "Done" at seven sites, "Close" at one.
///   • **the placement** — `.cancellationAction` (which is LEADING on iPhone)
///     at four sites and `.topBarTrailing` at four, so the exit control
///     changed sides of the bar between sheets reachable from one another in
///     two taps. This is the one a hand cannot learn.
///   • **the sizing** — `dsPageSheet()` at eight sites and missing at four,
///     among them `AccountDetailSheet`'s privacy pages, whose literal sibling
///     one line up in `AccountScreen` has it. On iPad and Mac a sheet with no
///     sizing is a ~540×620 form-sheet box whatever the window is, which is
///     the failure `ConnectFormSheet`'s own doc records being reported as
///     "these modals are way too small".
///
/// …and one nobody had answered anywhere: **the corner**. `DS.Radius`'s own
/// `presentedSheet` doc argues the concentric corner for a presented sheet and
/// names it "the most-opened surface in the app", and it reached three sheets
/// out of forty-odd.
///
/// # The rulings
///
/// **The word is "Done" and the placement is `.confirmationAction`.** Apple's
/// idiom puts an abandon verb leading and a finish verb trailing, and every
/// sheet in this family is finished rather than abandoned — a report you were
/// reading, a diagnostic, a form you either completed or did not. Naming the
/// placement semantically rather than as `.topBarTrailing` is also what makes
/// it land correctly on Catalyst, where the bar is not a phone's.
///
/// **A nav sheet has NO grabber, and that is the family's own rule.** A tray
/// exits by its grabber and carries no button; a nav sheet exits by its button
/// and carries no grabber. One exit affordance per family, so neither surface
/// offers two ways out of itself directly above one another. Drag-to-dismiss
/// is untouched — the indicator is the AFFORDANCE, never the gesture — so what
/// goes is the doubled chrome over a bar that already holds an exit, and
/// nothing a hand can do.
///
/// **The BACKGROUND is deliberately not folded in.** These sheets paint three
/// different grounds and each is a real answer rather than drift: a reading
/// sheet on `dsPageBackground` carries the person's own theme (a background
/// photo included), a vibenet sheet on `dsInk` is the room's ink, and
/// `BridgeConnectionSheet` states `DS.surfaceSheet` because a form is not a
/// page. Forcing one would flatten a distinction the person set, which is the
/// §558 rule ("do not 'harmonize' a refusal") applied one layer down. What is
/// shared here is the GEOMETRY, which had no reason to differ and did.
extension View {
    /// The presentation half — sizing and corner. Applied to the `.sheet`'s
    /// root (the `NavigationStack` itself), because both modifiers configure
    /// the PRESENTATION rather than the content.
    func dsNavSheet() -> some View {
        dsPageSheet()
            .dsSheetCorner()
    }

    /// The dismiss half — applied INSIDE the `NavigationStack`, to the content,
    /// because a toolbar attached from outside the stack has no bar to attach
    /// to. That split is why this is two modifiers and not one.
    ///
    /// Optional on purpose: `HowItWorksSheet` in the onboarding tail has no
    /// exit but its own CTA (one door, the connect screen's rule), so it
    /// passes nil rather than growing a second shape.
    func dsSheetDismiss(_ dismiss: (() -> Void)?) -> some View {
        toolbar {
            if let dismiss {
                ToolbarItem(placement: .confirmationAction) {
                    // No `dsText` override. A toolbar button is the one place
                    // in this app that should read as the system's, because it
                    // sits in the system's own bar beside the system's own
                    // title — three call sites had three different type
                    // treatments here (`body17`, `callout15`, untouched) and
                    // all three were answering a question nobody had asked.
                    Button(String(localized: "Done"), action: dismiss)
                        .tint(DS.tint)
                }
            }
        }
    }
}
