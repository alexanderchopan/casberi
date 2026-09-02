import SwiftUI

/// The language tray — one row per shipped localization plus "System", each a
/// full-width card that states its own name in its own script. Tapping one
/// switches the whole app on the spot (the root's locale environment repaints
/// live); the checkmark slides to the choice. Same tray shape as every other
/// picker in the app (DSTray, widget-radius cards, no hairlines).
struct LanguagePickerSheet: View {
    @Bindable private var store = LanguageStore.shared

    var body: some View {
        DSTray(title: "Language", height: 580) {
            // No intro sentence: the first row is "System · Match your device",
            // which teaches the scope by being the choice, where a sentence
            // above it could only say the same thing again in prose.
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(spacing: DS.Space.s2) {
                    row(endonym: "System", gloss: "Match your device",
                        selected: store.code == nil) { store.code = nil }
                    ForEach(LanguageStore.supported) { lang in
                        row(endonym: lang.endonym, gloss: lang.gloss,
                            selected: store.code == lang.code) { store.code = lang.code }
                    }
                }
            }
        }
    }

    private func row(endonym: String, gloss: String, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { action() }
        } label: {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 1) {
                    // The endonym leads — it IS the visual, no flag needed. Real
                    // endonyms/glosses aren't catalog keys so they fall through
                    // verbatim; only "System" / "Match your device" localize.
                    Text(LocalizedStringKey(endonym)).dsText(.heading17).foregroundStyle(DS.textPrimary)
                    Text(LocalizedStringKey(gloss)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .dsGlyph(16, weight: .bold)
                    .foregroundStyle(DS.tint)
                    .opacity(selected ? 1 : 0)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Color is the only signal: the chosen row wears the accent wash,
            // the rest the faint fill. No border, no line.
            .background(selected ? DS.tintDim : DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(DSTileButtonStyle())
        .accessibilityLabel(endonym)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
