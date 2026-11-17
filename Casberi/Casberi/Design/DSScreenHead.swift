import SwiftUI

/// A screen's name, in its content (prd §767).
///
/// The system's large title stood at the top edge at 34pt, beside a back
/// chevron. The name sits in the rows' column and scrolls away with them
/// (§767) — and since prd §915 it takes its OWN rung, `heading34`: at
/// `heading24` the screen's name, its sections, its switcher and "Since you
/// left" were four jobs on one rung, so nothing on the Accounts screen
/// outranked anything else. One scale now: the screen at 34, a section at
/// 24, a switcher's words at 17.
///
/// **A room wears one too, since prd §930.** Until then no room had a title:
/// the dock's lit tile named the category under your thumb. With the strip
/// folded into the rooms tray, nothing on the screen said which room you were
/// in, so every room names itself here, first in its list, the way a pushed
/// screen does.
struct DSScreenHead: View {
    let title: Text
    /// A category's name is pink (prd §1129, user: "i meant for ONLY the
    /// category to be in pink"); a pushed screen's stays primary.
    var ink: Color = DS.textPrimary

    var body: some View {
        title
            .dsText(DSRoomTitleRow.rung)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **A CATEGORY'S TITLE ROW (prd §1129, §1133, §1320).** Its name in the head
/// ink; once something in it is picked, the name greys and the pick after a
/// dot takes the primary ink:
/// "Wallet · Coinbase", "You · Settings". A label that presses nothing (§1133:
/// the face says where, the tiles say what), on one line at one height
/// picked or not, so nothing under it moves; a long pair shrinks to fit.
/// Every room draws it first in its list, and You's three screens (Apps,
/// Addresses, Settings) draw it in place of their own heads.
struct DSRoomTitleRow: View {
    /// **EVERY TITLE IS ONE SIZE (prd §1812, user: "keep name and one size
    /// for every title").** The longest path the app draws, "Activity · Work
    /// · App Store Connect" beside its settings disc, fits at this rung on
    /// the phone, so Home, Activity, a category and an app all wear it and
    /// no title steps down or loses a name. It was `heading34`, stepping to
    /// 28 and 24 by the length of the name (§1389), which drew three sizes
    /// across three pages.
    static let rung: DSTextStyle = .heading20

    let title: String
    var pick: String? = nil
    /// The category's word pressed while a pick follows it: back to the
    /// whole category (prd §1262, user: "otherwise you have to go into the
    /// tray, which is fine but shouldn't be the only way"). Nil keeps the
    /// row a label.
    var onTitle: (() -> Void)? = nil
    /// The app the row names, pressed: its settings, its account page (prd
    /// §1444, user: "the sliders is the absolute clearest hands down"). Draws
    /// the sliders disc after the pick, or after the title on an app's own
    /// page, the glyph the long press's Settings wears, so what an app's page
    /// manages is found on the page. Nil keeps the words labels.
    var onSettings: (() -> Void)? = nil
    /// **THE WHOLE PATH (prd §1811).** The place this page is two steps under,
    /// named first and pressable: "Home · Activity · Social". A category's
    /// page read "Activity · Social", so Home was two taps away. **The path is
    /// always whole** (prd §1812, user: "we should have a rule and stick to
    /// it"): three names at one size; a path too long for the row cuts its
    /// last name at the tail, never the names before it (prd §1828).
    var root: DSTitleBack? = nil
    @Environment(\.sizeCategory) private var sizeCategory
    /// In a thing sheet the title is the thing's, and wraps (prd §1258).
    @Environment(\.dsTitleWraps) private var wraps

    var body: some View {
        // ONE LEFT EDGE (prd §1471): the title stands in the rows' column,
        // where the lead's words, the section names and the row marks stand.
        // It kept the box's outer line while the box drew a fill; since the
        // box draws none (§1381) that line is invisible and the name read
        // 14pt off everything under it.
        titleContent
            .padding(.leading, DSRoomChassis.titleIndent)
    }

    @ViewBuilder
    private var titleContent: some View {
        if wraps {
            // A THING'S TITLE WRAPS (prd §1258, user, of the sheets' one cut
            // line: "ya do it"): a sheet is one thing, so its name reads
            // whole, over as many lines as it needs, at the card-title rung.
            label
                .dsText(.heading24)
                .foregroundStyle(DS.headInk)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        } else {
            roomTitle
        }
    }

    @ViewBuilder
    private var roomTitle: some View {
        if let pick, onTitle != nil || onSettings != nil {
            // The category's word presses (prd §1262); the pick after the
            // dot stays a label. Same rung, ink and height as the label row.
            // **ONE SIZE, AND THE LAST NAME IS CUT (prd §1828, user: "we
            // can't be having that middle word short", "for long apps like
            // 'app store connect' we will just have to truncate it").** The
            // fallback that let a row too narrow shrink (§1389, §1812) scaled
            // each word on its own, so "Activity" drew smaller than the
            // names either side of it.
            pickedTitle(title, pick: pick, rung: Self.rung)
                .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
        } else if pick == nil, let onSettings {
            // An app's own page ("GitHub", Library's tap): the name is the
            // door, its disc after it (prd §1444).
            Button(action: onSettings) {
                HStack(alignment: .center, spacing: DS.Space.s2) {
                    Text(verbatim: title)
                        .dsText(Self.rung)
                        .foregroundStyle(DS.headInk)
                        .lineLimit(1)
                        // One size; a name too long is cut (prd §1828).
                        .truncationMode(.tail)
                    settingsDisc
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height, alignment: .leading)
            .accessibilityLabel(Text("\(title) settings"))
            .accessibilityAddTraits(.isHeader)
        } else {
            DSScreenHead(title: label, ink: DS.headInk)
                .lineLimit(1)
                // One size; a name too long is cut (prd §1828).
                .truncationMode(.tail)
                // ONE HEIGHT, whatever the name (prd §1136f, user: "the box should
                // never move down!"): a long pair shrinks to fit, and the row used
                // to shrink with it, so the box and the tiles under it moved with
                // the length of your name. The row is the rung's full line, always.
                .frame(height: Self.height, alignment: .leading)
                .accessibilityLabel(Text(verbatim: pick.map { "\(title), \($0)" } ?? title))
        }
    }

    /// The picked title at one rung: the category's word a grey button, the
    /// pick after the dot in the head ink, and with `onSettings` the pick a
    /// button too, its sliders disc after it. The names before the pick are
    /// never cut (they are the way back); the pick takes what is left and
    /// is cut at its tail (prd §1828).
    private func pickedTitle(_ title: String, pick: String,
                             rung: DSTextStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let root {
                Button(action: root.action) {
                    Text(verbatim: root.word)
                        .foregroundStyle(DS.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .fixedSize()
                .accessibilityHint(Text("Opens \(root.word)"))
                Text(verbatim: " · ").foregroundStyle(DS.textTertiary).fixedSize()
            }
            // The word that goes back is grey, where you stand is the
            // head ink (user, 2026-10-15: "is sources supposed to be
            // gray, eg only one is white"), as the walk's title greys
            // its neighbours (§1207).
            if let onTitle {
                Button(action: onTitle) {
                    Text(verbatim: title)
                        .foregroundStyle(DS.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .fixedSize()
                .accessibilityHint(Text("Shows everything in \(title)"))
            } else {
                Text(verbatim: title).foregroundStyle(DS.textTertiary).fixedSize()
            }
            Text(verbatim: " · ").foregroundStyle(DS.textTertiary).fixedSize()
            if let onSettings {
                Button(action: onSettings) {
                    // The pick's own text is the label, so its baseline is the
                    // row's: an HStack centring the disc beside it dropped the
                    // pick below "Wallet ·" (user, 2026-11-02: "axis is messed
                    // up here"). The disc rides an overlay in the space kept.
                    Text(verbatim: pick).foregroundStyle(DS.textPrimary)
                        .truncationMode(.tail)
                        .padding(.trailing, DS.Face.row + DS.Space.s2)
                        .overlay(alignment: .trailing) { settingsDisc }
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("\(pick) settings"))
            } else {
                Text(verbatim: pick).foregroundStyle(DS.textPrimary)
                    .truncationMode(.tail)
            }
        }
        .dsText(rung)
        .lineLimit(1)
    }

    /// The pick's settings door (prd §1444): grey, never the pick's pink
    /// (§1385, a door is grey), on the faint disc a lead's glyph stands on.
    private var settingsDisc: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
                .frame(width: DS.Face.row, height: DS.Face.row)
            Image(systemName: "slider.horizontal.3")
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
        }
        .accessibilityHidden(true)
    }

    /// The rung's line at its full size, scaled for Dynamic Type as the
    /// words are.
    static var height: CGFloat {
        let style = rung
        // Never under a finger's height: the names in it are the way back.
        return max(DS.Hit.min, UIFontMetrics(forTextStyle: style.relative)
            .scaledValue(for: style.lineHeight * style.platformSize / style.size))
    }

    private var label: Text {
        guard let pick else { return Text(verbatim: title) }
        return Text(verbatim: title).foregroundStyle(DS.textTertiary)
            + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
            + Text(verbatim: pick).foregroundStyle(DS.textPrimary)
    }
}

private struct DSTitleWrapsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A title row inside a thing sheet wraps instead of shrinking to one
    /// line (prd §1258). Set by `ThingSheetView` only.
    var dsTitleWraps: Bool {
        get { self[DSTitleWrapsKey.self] }
        set { self[DSTitleWrapsKey.self] = newValue }
    }
}
