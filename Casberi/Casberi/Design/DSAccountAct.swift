import SwiftUI

/// THE ACT CONTEXT — the setup half of an account page draws rows, not slabs
/// (prd §640, 2026-09-06).
///
/// The report: *"all of the set up pages basically look like shit"*, with a
/// screenshot of App Store Connect's key form — a blue commit slab, three
/// prose steps, two green ticks, a picker slab, three field slabs and a
/// footnote, stacked. §639b had already put every one of the 55 screens on
/// `AccountPage`, so the header, the facts, the readers and the roster were
/// all the row grammar; the ACT slot in the middle was still the slab stack
/// §190 built for the wallet manager, and one page carried both. That is the
/// same complaint §639b answered ("all of these different pages should have
/// the same DNA"), one slot further in.
///
/// **What this changes is where a slab is drawn, never what a slab is.** §190
/// and §613 stand everywhere they were written for — the wallet manager, the
/// devnet rooms' Send/Top up, the trays' compact filters. Inside an account
/// page's act (and inside the "Your key" sheet, which draws the same block)
/// the primitives render their ROW form instead, so all 55 screens change
/// with their call sites untouched: a screen that stacks `DSSlabButton`,
/// `DSSlabField` and `DSSlabNote` is spelling an act, not a shape, and the
/// shape is the chassis's to choose.
///
/// The row form, one line each:
///
/// · `DSSlabButton` → the COMMIT row: tinted disc, tint title, its address
///   trailing. Colour is the only thing separating it from a door, which is
///   `DSSlabDisc`'s own grammar.
/// · `DSSlabDoor`   → the DOOR row: ink disc, primary title, its fact
///   trailing, chevron.
/// · `DSSlabField`  → the ENTRY row: the field itself, left-aligned, keeping
///   its placeholder; the verb becomes its own row underneath.
/// · `DSSlabSwitch` → title, detail, a `Toggle`, no fill.
/// · `BridgeStepLines` / `DSCheckList` / `BridgeSyncStatusRows` keep their
///   shape and drop to the page's quiet rung, so a form's prose stops
///   out-weighing the rows it explains.
///
/// **A row with no glyph is INSET to the title column** rather than given an
/// invented one. Half the act fields in the catalog pass no glyph, and a
/// guessed disc ("plus" over a Key ID) is worse than none — but a ragged left
/// edge is what made the old stack read as a collage, so the text still lines
/// up with every titled row above it.
enum DSActRow {
    /// The row's height — `AccountFactRow`'s, because they stand in one column.
    static let height: CGFloat = 56
    /// The leading disc's box. The title column starts at `inset`.
    ///
    /// Spelled `discSize` rather than overloading `disc` below: a stored
    /// property and a method may share a base name in Swift, and the two
    /// resolve by context — which compiles, and reads as a typo forever.
    static let discSize: CGFloat = 32
    static var inset: CGFloat { discSize + DS.Space.s3 }

    /// The leading disc: a glyph on the well fill, the mark grammar every
    /// settings row in the app already uses. ONE definition — `AccountFactRow`
    /// forwards to it, so a fact row and an act row can never drift apart.
    /// **The ink disc takes the POUR** (2026-09-06). `DS.surfaceWell` is
    /// `#080809` and the page is `#000000` — a 1.03:1 step, so on every row
    /// below the header's wash the disc simply was not there, and a column of
    /// rows with no left edge reads as ragged floating text. This is §545's
    /// finding on the field, one control over, and it takes §545's answer:
    /// the well tone with `DS.pourInk` over it, clipped to the circle.
    static func disc(_ glyph: String, tinted: Bool = false) -> some View {
        Image(systemName: glyph)
            .dsGlyph(14, weight: .medium)
            .foregroundStyle(tinted ? DS.tint : DS.textSecondary)
            .frame(width: discSize, height: discSize)
            .background {
                if tinted {
                    Circle().fill(DS.tint.opacity(0.14))
                } else {
                    Circle().fill(DS.surfaceWell)
                        .overlay { Circle().fill(DS.pourInk) }
                }
            }
    }
}

private struct AccountActKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside an account page's act slot (and its key sheet) — the
    /// primitives read it to pick their row form.
    var accountAct: Bool {
        get { self[AccountActKey.self] }
        set { self[AccountActKey.self] = newValue }
    }
}

private struct AccountDoorOpenedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True once the account page has opened its provider door in-app (prd
    /// §653) — the entry rows read it to offer the paste the person came
    /// back to make. Set by `AccountPage` alone.
    var accountDoorOpened: Bool {
        get { self[AccountDoorOpenedKey.self] }
        set { self[AccountDoorOpenedKey.self] = newValue }
    }
}

extension View {
    /// Marks a subtree as an account page's act. Set in exactly two places
    /// (`AccountPage.actSection` and `AccountKeySheet`); nothing else may set
    /// it, or a slab somewhere else in the app silently becomes a row.
    func dsAccountAct() -> some View { environment(\.accountAct, true) }

    /// The act row's own geometry — one modifier so the door, the commit, the
    /// entry and the verb are the same object at the same height.
    func dsActRowFrame(glyphless: Bool = false) -> some View {
        frame(minHeight: DSActRow.height)
            .padding(.leading, glyphless ? DSActRow.inset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
