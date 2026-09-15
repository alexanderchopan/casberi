import SwiftUI

/// **THE DOOR ROW — a way out of a sheet, drawn once (prd §560, 2026-09-01).**
///
/// Three wallet sheets each carried a private `doorRow(icon:label:action:)`
/// with the same signature: `ENSRenewCard`, `SafeQueueCard` and
/// `ApprovalPrepareCard`. Two of the three were byte-identical apart from a
/// `.dsHover()`; the third set its glyph two points larger, dropped the icon
/// column and painted the whole row `DS.tint`.
///
/// **The tinted one is the drift, and this settles it toward the other two.**
/// A row painted entirely in the accent colour is web-footer grammar — it
/// reads as a link, and §480 already named "three blue links in a row" as a
/// fault on the sheet next door. A door here is a ROW: a secondary icon in a
/// fixed column so the labels align down the sheet, and the label in primary
/// ink because it is the thing you are reading, not a citation of it.
///
/// **THE VERB ROW TOO (prd §746, 2026-09-15).** A verb that stood alone as a
/// capsule — Catch up now, Listen, Make active, Revoke this key, Ask about
/// this — is this row now. The one colour it may take is DESTRUCTIVE, because
/// that ink is a meaning and not an accent: `role: .destructive`.
///
/// `DSSlabDoor` is the sibling and NOT the same object: it is §190's connect-
/// screen slab, a tall tinted card that `connect-shape-audit.py` enforces on
/// setup pages. This is the small one, for a sheet whose content is a reading
/// and whose doors sit under it.
///
/// Honesty (§83): the row is a `Button` with a `contentShape`, so its whole
/// width is the target — a door that only answers on its 18pt glyph is a
/// control that mostly does nothing — and it is 44pt tall (§717, since §746).
struct DSDoorRow: View {
    /// The SF Symbol naming where this goes — an explorer, a settings page, a
    /// copy. It sits in a fixed-width column so a run of doors aligns.
    let icon: String
    let title: Text
    var role: ButtonRole? = nil
    let act: () -> Void

    init(icon: String, label: LocalizedStringKey, role: ButtonRole? = nil,
         act: @escaping () -> Void) {
        self.icon = icon
        self.title = Text(label)
        self.role = role
        self.act = act
    }

    /// A runtime string (an address, a door's own label) stays verbatim.
    init(icon: String, title: Text, role: ButtonRole? = nil, act: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.role = role
        self.act = act
    }

    var body: some View {
        Button(role: role, action: act) {
            DSDoorRowLabel(icon: icon, title: title, role: role)
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}

/// The door row's face, for a slot that owns its own control — a `ShareLink`,
/// a `Menu`, a `Button` with a custom press.
struct DSDoorRowLabel: View {
    let icon: String
    let title: Text
    var role: ButtonRole? = nil

    private var ink: Color { role == .destructive ? DS.destructive : DS.textPrimary }

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon)
                .dsGlyph(13, weight: .regular)
                .foregroundStyle(role == .destructive ? DS.destructive : DS.textSecondary)
                // The column, not the glyph's own width: SF Symbols are
                // not uniform, so without it a stack of doors staircases.
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)
            title
                .dsText(.callout15)
                .foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s1)
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }
}

/// **Copy, and say it was copied — as a row (prd §746; was `DSCopyCapsule`,
/// §715).** A bare tap-to-copy went unnoticed (user, 2026-07-15), so the word
/// swaps to "Copied" for two seconds. The value is copied SENSITIVE
/// (local-only, expiring) by default because every caller so far copies a
/// sign-in code; pass `sensitive: false` for anything public.
struct DSCopyRow: View {
    let value: String
    var label: LocalizedStringKey = "Copy code"
    var sensitive = true
    @State private var copied = false

    var body: some View {
        DSDoorRow(icon: copied ? "checkmark" : "doc.on.doc",
                  title: copied ? Text("Copied") : Text(label)) {
            if sensitive { DSPasteboard.copySensitive(value) } else { DSPasteboard.copy(value) }
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { copied = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(DS.Motion.standard) { copied = false }
            }
        }
    }
}
