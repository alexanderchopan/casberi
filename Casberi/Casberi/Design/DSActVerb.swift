import SwiftUI

/// **THE HERO VERB — an act at the head rung (prd §559, 2026-09-01).**
///
/// The devnet rooms' Home panel (prd §553, `DevnetSendPanel`) set "Send",
/// "Top up" and "Create account" at `price40` — a VERB wearing the rung the
/// ramp reserves for a head or a leading figure — and that treatment is the
/// house identity now: when a surface exists to do one thing, its verb is set
/// at the size money gets. This is that identity as a component, for the
/// surfaces whose whole reason is one act — the pinned commit of an act sheet
/// (Sign, Create account, Add 3) and the onboarding greeting's one honest
/// first tap. The state above the tile is information; the tile is the point.
///
/// **Anatomy mirrors `DevnetSendPanel`'s tile and deliberately shares no code
/// with it.** The panel's layout is MEASURED against the room's chrome (§553's
/// tileFloor arithmetic, asserted by `devnet-console-audit.py`) while this
/// hugs its content — folding the two would put a sheet's commit under a room
/// measurement. The shared grammar is the disc, the bottom-left verb at
/// `price40`, `PressSpring` and the widget radius; the floors are not shared.
///
/// **NOT for connect/setup screens.** §190 rules those slabs (`DSSlabDoor`),
/// `connect-shape-audit.py` enforces it, and this tile on a connect page would
/// be that audit's finding wearing a bigger font. Nor for any surface with
/// three or more verbs — a hero verb among peers is just shouting.
///
/// Honesty (§83): a hand-rolled button paints its own background and
/// `.disabled` dims a label, not a fill — so the fill swaps itself when the
/// tile cannot act. A BUSY tile keeps its fill (it is acting, not refusing)
/// and shows the spinner in the disc rather than beside the verb, the
/// `DevnetCreatePanel` shape — the verb is the object and does not wobble.
struct DSActVerb: View {
    let title: String
    /// A unit set at `price16` on the verb's own baseline, for a tile whose
    /// verb carries a FIGURE ("Send 1.1" · "test ETH"). Nil everywhere else.
    ///
    /// It is a second parameter rather than part of `title` for the reason
    /// `DSTreemapLeader` splits its two: folded into one string the unit is
    /// set at 40pt, which both wraps the verb onto a second line and states a
    /// denomination in the size reserved for the amount. `DevnetSendSheet`'s
    /// amount screen already sets a figure and its unit at exactly these two
    /// rungs, so this is that lockup, on the tile that commits it.
    var unit: String? = nil
    /// The disc's glyph — the slot that says HOW the act happens: "faceid" on
    /// a commit Face ID confirms, "key" where a key is made, "plus" where
    /// something is added.
    var glyph: String = "arrow.up.right"
    /// The fill. The venue's or subject's own colour where it has one,
    /// `DS.tint` otherwise — the primary is always a filled tile; the ink
    /// (secondary) half of the identity stays `DevnetSendPanel`'s until a
    /// second surface needs a pair.
    var tint: Color = DS.tint
    var busy = false
    var disabled = false
    /// Something to sit beside the disc in the tile's header band — today the
    /// stitched send's own sequence strip, drawn inside the tile that sends
    /// it. Nil for every other caller, so the band stays the air it has always
    /// been and nothing about the existing four changes.
    var accessory: AnyView? = nil
    let act: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            act()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.s3) {
                    disc
                    if let accessory { accessory }
                }
                Spacer().frame(height: DS.Space.s2)
                HStack(alignment: .lastTextBaseline, spacing: DS.Space.s2) {
                    Text(title)
                        .dsText(.price40)
                        .foregroundStyle(disabled ? DS.textTertiary : .white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let unit {
                        Text(unit)
                            .dsText(.price16)
                            .foregroundStyle(disabled ? DS.textTertiary
                                                      : Color.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
            .background(disabled ? AnyShapeStyle(DS.gray100) : AnyShapeStyle(tint),
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(disabled || busy)
        .dsHover()
        .accessibilityLabel(Text(unit.map { "\(title) \($0)" } ?? title))
    }

    private var disc: some View {
        ZStack {
            // 36pt — `DevnetConsole.mark`'s value, spelled here because Design/
            // does not reach into Screens/. Under `DS.Hit.min` deliberately:
            // the disc is not a target, the whole tile is.
            Circle().fill(Color.white.opacity(disabled ? 0.10 : 0.22))
                .frame(width: 36, height: 36)
            if busy {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: glyph)
                    .accessibilityHidden(true)
                    .dsGlyph(20, weight: .semibold)
                    .foregroundStyle(disabled ? DS.textTertiary : .white)
            }
        }
    }
}
