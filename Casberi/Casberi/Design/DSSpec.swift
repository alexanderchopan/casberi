import SwiftUI

/// THE SPEC TABLE — a run of label/value facts under a thing (2026-08-28
/// component sweep).
///
/// **It was hand-rolled three times at three label widths.**
/// `ThingSheetView.specRow` sized its column 80, `ThingContent`'s fact row 72
/// and `VibenetKeySheet.factRow` 84 — the same anatomy (`label12` tertiary,
/// `callout15` primary, optional trailing glyph) in three sheets a person
/// moves between in two taps. `ThingSheetView` spelled the layout a further
/// two times INSIDE itself, in `fromRow` and `counterpartyRow`, only to add a
/// trailing mark its own `specRow` had no parameter for.
///
/// **The column is INTRINSIC, not a number.** Picking one of 72/80/84 would
/// have been the tidier-looking fix and the wrong one: `ThingContent`'s labels
/// are not a closed vocabulary — a Contacts fact is
/// `ThingFact(label(phone.label, fallback: "Phone"), …)`, i.e. whatever the
/// person typed on their own phone, in whatever language — and that is the
/// table that had the NARROWEST column and no `lineLimit`, so it is the one
/// that wrapped. A `Grid` sizes each table's column to its own longest label,
/// which costs alignment BETWEEN two different sheets (nobody sees that) and
/// buys alignment WITHIN one (everybody does).
///
/// Measured before it was built, because the load-bearing question had a
/// plausible wrong answer: a `Grid` does see a `GridRow` through a custom
/// `View` wrapper, through a modifier and through an `if`. Rendered intrinsic
/// widths for a short-label/long-value row beside a long-label/short-value
/// row: all three Grid forms **304pt**, independent rows **174pt**. So
/// `DSSpecRow` can be a real type rather than a bare function.
struct DSSpecTable<Rows: View>: View {
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: DS.Space.s3,
             verticalSpacing: DS.Space.s3) {
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One fact. Place these directly inside a `DSSpecTable`.
///
/// **`label` and `value` are `Text`, not `String`, and that is load-bearing.**
/// The app injects `\.locale` so an in-app language change re-resolves every
/// `Text` (see `LanguageStore`), which `String(localized:)` at call time would
/// not follow — and the two callers need opposite things anyway: this sheet's
/// labels are a closed vocabulary that MUST localize ("Landed", "Site", "Who")
/// while a Contacts fact's label is somebody's own words and must NOT be
/// looked up in a catalog. Handing the component a styled-nothing `Text` lets
/// each caller keep its own answer while the styling stays here, which is the
/// only part that was ever duplicated.
struct DSSpecRow: View {
    let label: Text
    let value: Text
    /// The value's ink. Tinted where the row leads somewhere.
    var tint: Color = DS.textPrimary
    var weight: Font.Weight? = nil
    /// nil wraps freely — the vibenet key sheet's answer, where a value is a
    /// sentence rather than a field.
    var lineLimit: Int? = 2
    /// The trailing mark. The app's own grammar: `arrow.up.right` leaves,
    /// `chevron.right` goes deeper, `square.and.pencil` edits in place.
    var glyph: String? = nil
    /// A tap for the whole row. nil leaves it inert — and inert is the
    /// default, so a row cannot become a control by accident (§83).
    var action: (() -> Void)? = nil

    var body: some View {
        GridRow {
            label
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .gridColumnAlignment(.leading)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                value
                    .dsText(.callout15)
                    // Applied only when a caller really wants a DIFFERENT
                    // weight — `weight ?? .regular` would restate `callout15`'s
                    // own rung, which `design-ramp-audit` fails the build on.
                    .fontWeight(weight)
                    .foregroundStyle(tint)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: lineLimit == nil)
                if let glyph {
                    Image(systemName: glyph)
                        .accessibilityHidden(true)
                        .dsGlyph(12, weight: .regular)
                        .foregroundStyle(DS.textTertiary)
                }
                // The value cell takes the rest of the width, so the label
                // column is the only one sized to content — and so a tappable
                // row's target reaches the trailing edge.
                Spacer(minLength: 0)
            }
        }
        .modifier(DSSpecRowTap(action: action))
    }
}

/// The tap, as a modifier so the row itself stays a `GridRow` in both states.
///
/// `contentShape` + `onTapGesture` rather than wrapping the row in a `Button`:
/// a `Button` is one view and would collapse the two cells into a single
/// column, which is the whole thing this table exists to avoid. The traits are
/// added by hand for exactly that reason — without them VoiceOver would never
/// announce the row as activatable, which is the shape `accessibility-audit`
/// check 1 was written for.
private struct DSSpecRowTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, action)
                .dsHover()
        } else {
            content
        }
    }
}
