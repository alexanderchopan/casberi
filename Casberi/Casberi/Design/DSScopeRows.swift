import SwiftUI

/// THE SCOPES AS DOOR ROWS — what the room's Home holds instead of a chip
/// strip (prd §747, 2026-09-15).
///
/// **The complaint this answers, in the words it was made in** (user,
/// 2026-09-15): *"the sections like holdings accounts, et cetera, don't really
/// look like sections or buttons to tap, and they look so small, especially if
/// they're supposed to be for a category of the wallet."* Both halves are
/// measurable rather than matters of taste. `DSSectionSwitcher` draws its word
/// at `label12` — 12pt, the rung the app uses for a month beside a date — and
/// embedded in the slab it draws NO rest fill at all (§547 removed it as a
/// pill inside a pill), so at rest a scope is a caption on glass. And a
/// category of the wallet is not a small thing.
///
/// A row is the app's own answer to "this is a door": a word at `body17`, what
/// is behind it on the right, a chevron. `DSPushRow` already is that row, so
/// this draws no anatomy of its own — the template audit's whole point, and
/// the reason a fix to `DSPushRow` reaches these rows for free.
///
/// **Every row states its reading, and that is an obligation rather than a
/// nicety.** §611 made every scope present on every wallet, on the rule that a
/// chip onto nothing is a dead control (§83) but a chip onto a sentence that
/// teaches the scope is the room explaining itself. The strip could only keep
/// that promise AFTER the tap. A row keeps it before: `Permissions · 4 live
/// approvals` and `Risk · Nothing on leverage` both answer the question the
/// tap was going to ask, and an empty scope reads its own `emptyHeadline`
/// here — which is why `reading` returns a plain `String?` and the rooms hand
/// it the same sentence they already wrote.
///
/// **Home is not a row.** The rows ARE Home, so a room passes the scopes
/// minus its own home case. Filtering here would mean this component knowing
/// which of eight enums calls its first case `home`, which is a fact about
/// rooms and not about rows.
struct DSScopeRows<Scope: DSSectionScope>: View {

    let sections: [Scope]
    /// Scopes with something that wants answering — the dot the strip carried,
    /// moved onto the row. A set, for `DSSectionSwitcher`'s own reason: several
    /// can want you at once and each says so for itself.
    var attention: Set<Scope> = []
    /// What the scope holds RIGHT NOW, in the room's words. Nil draws no fact
    /// rather than an empty one; the chevron still promises what is behind it.
    let reading: (Scope) -> String?
    let onPick: (Scope) -> Void

    var body: some View {
        // **A ROOM WITH ONE READING DRAWS NO ROWS (§83).** `DSSectionSwitcher`
        // was gated by each room's own `shows(present:)`, on the rule that a
        // control offering a single choice is not a control. The rule is
        // unchanged and the gate moved HERE, because the chrome around these
        // rows must still draw on Home either way — it carries the crown and
        // the acts now. An empty `VStack` on a widget surface is a plate with
        // nothing in it, which is the same dead control wearing a background.
        if !sections.isEmpty {
            VStack(spacing: 0) {
                ForEach(sections) { section in
                    row(section)
                }
            }
            .dsWidgetSurface()
        }
    }

    @ViewBuilder
    private func row(_ section: Scope) -> some View {
        let wants = attention.contains(section)
        DSPushRow(title: Text(section.label),
                  fact: reading(section).map { Text($0) },
                  action: { onPick(section) }) {
            // The dot LEADS the word rather than trailing it, because a
            // column of dots down the left edge is scannable and a dot after
            // a word of any length is not. It keeps its 6pt and its
            // `DS.attention` from the strip: this is the same mark saying the
            // same thing, moved.
            if wants {
                Circle()
                    .fill(DS.attention)
                    .frame(width: DS.Space.s2 - 4, height: DS.Space.s2 - 4)
            }
        }
        .padding(.horizontal, DSRoomChassis.inset)
        .padding(.vertical, DS.Space.s3)
        // A row is a finger target before it is a layout, and `body17` in
        // `s3` padding lands a point or two under the floor on Mac's tighter
        // spacing ramp.
        .frame(minHeight: DS.Hit.min)
        // The word and its reading are one announcement; the summary says
        // what the scope HOLDS, since these nouns are learnable but not
        // self-explaining ("Permissions" must not read as app settings when
        // what sits behind it is ranked by what somebody can take, §292).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(section, wants: wants))
        .accessibilityAddTraits(.isButton)
        .dsTooltip(section.summary)
    }

    private func accessibilityLabel(_ section: Scope, wants: Bool) -> Text {
        let fact = reading(section)
        let base = fact.map { "\(section.label), \($0)" } ?? "\(section.label), \(section.summary)"
        return Text(wants ? String(localized: "\(base), needs you") : base)
    }
}
