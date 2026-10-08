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
/// · `DSSlabField`  → the ENTRY row: the field itself, keeping its
///   placeholder, wrapped rather than cut; the commit is a check inside the
///   well (prd §1032).
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
///
/// **The entry well is the one exception (prd §1027).** It is a box, not a
/// line of text, so it starts at the discs' edge and ends at the page's: a
/// well inset to the title column had a left margin a disc wider than its
/// right one, and gave that width to the placeholder's ellipsis.
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

    /// THE ENTRY WELL (prd §729). The one thing on an account page that may
    /// be a box, because it is a box you put something in: an entry row that
    /// was only a placeholder in the title column read as one more title, and
    /// nobody could tell it took a paste. The disc's own recipe — the well
    /// tone under `DS.pourInk` — so a field and the discs beside it are one
    /// material, and on ink it has an edge (§545's finding).
    static let wellHeight: CGFloat = 44
    static var well: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        return shape.fill(DS.surfaceWell).overlay { shape.fill(DS.pourInk) }
    }

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
            .dsGlyph(.subhead, weight: .medium)
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

// MARK: - The act's verbs as tiles (prd §1197)

/// One of an account page's tiles (prd §1197): a verb, drawn by
/// `DSScopeTiles` as a thing sheet's are (`SheetTile`), in the caller's order.
/// `enabled` false draws it in place, dimmed (the tiles never move).
struct AccountTile {
    let id: String
    let label: String
    let glyph: String
    var enabled = true
    let act: () -> Void

    var scope: SheetTile { SheetTile(id: id, label: label, glyph: glyph) }

    /// What a redraw compares: everything but the closure.
    var key: String { "\(id)|\(label)|\(glyph)|\(enabled)" }
}

/// THE WORD AND GLYPH A SLAB TAKES AS A TILE (prd §1197). A slab's title is
/// a sentence ("Get your API key", "Connect Rocket Money"); a tile is a word
/// over a glyph, so the call site names which word, from this one table —
/// the same act wears the same tile on every page.
struct SlabTile: Equatable {
    let label: String
    let glyph: String

    static let signIn  = SlabTile(label: String(localized: "Sign in"), glyph: "person.badge.key")
    static let getKey  = SlabTile(label: String(localized: "Get key"), glyph: "key.horizontal")
    static let getPassword = SlabTile(label: String(localized: "Password"), glyph: "key.horizontal")
    static let keyFile = SlabTile(label: String(localized: "Key file"), glyph: "doc.badge.plus")
    static let allow   = SlabTile(label: String(localized: "Allow"), glyph: "checkmark.shield")
    static let folder  = SlabTile(label: String(localized: "Folder"), glyph: "folder.badge.plus")
    static let photos  = SlabTile(label: String(localized: "Photos"), glyph: "photo.on.rectangle")
    static let importFile = SlabTile(label: String(localized: "Import"), glyph: "square.and.arrow.down")
    static let follow  = SlabTile(label: String(localized: "Follow"), glyph: ScopeTileGlyph.watch)
    static let reconnect = SlabTile(label: String(localized: "Reconnect"), glyph: "arrow.clockwise")
    static let turnOn  = SlabTile(label: String(localized: "Turn on"), glyph: "power")
    static let ask     = SlabTile(label: String(localized: "Ask"), glyph: "sparkles")
    static let approve = SlabTile(label: String(localized: "Approve"), glyph: "checkmark.seal")
    static let getApp  = SlabTile(label: String(localized: "Get app"), glyph: "arrow.down.app")
}

/// The tiles a page's act slot hands up (prd §1197). A slab marked with a
/// `SlabTile` and standing in an account page's act registers here and draws
/// nothing in its row; the chassis draws the tiles under the box. Observable,
/// not a preference: a `List` row's preferences do not reach the rows beside
/// it.
@MainActor @Observable
final class AccountTileBoard {
    private(set) var tiles: [AccountTile] = []

    /// Writes only on a change, so a redraw that re-registers the same verb
    /// invalidates nothing.
    func put(_ tile: AccountTile) {
        if let i = tiles.firstIndex(where: { $0.id == tile.id }) {
            guard tiles[i].key != tile.key else { return }
            tiles[i] = tile
        } else {
            tiles.append(tile)
        }
    }

    func remove(_ id: String) {
        tiles.removeAll { $0.id == id }
    }
}

private struct AccountTileBoardKey: EnvironmentKey {
    static let defaultValue: AccountTileBoard? = nil
}

extension EnvironmentValues {
    /// Set on an account page's act slot only — never on `more()` or the key
    /// sheet, which draw their slabs where they stand.
    var accountTileBoard: AccountTileBoard? {
        get { self[AccountTileBoardKey.self] }
        set { self[AccountTileBoardKey.self] = newValue }
    }
}
