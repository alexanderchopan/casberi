import SwiftUI

/// The Wallet manager's one geometry (prd §189, 2026-07-23).
///
/// The user's read of the screen below the shelf: *"we have different fonts,
/// different shapes, and I think to myself, how would Cash App do this
/// screen."* It was a fair census — a recessed field with a side pill, a
/// full-width capsule, three paragraph footers, a headed section with a blue
/// text link, and a gear row: six shapes and four type rungs stacked on top of
/// each other.
///
/// The answer isn't new art, it's one rule: **below the shelf, every block is
/// the same slab** — one height, one radius (`DS.Radius.widget`, the tile
/// radius §8 already sanctions) — and the only round things on the screen are
/// people. The eye then reads a rhythm instead of a collage.
///
/// **One font, and it is SF Pro Text.** The mock that won this ruling set the
/// tappable slabs in SF Rounded, Cash App style. That would have broken a
/// standing rule (Typography.swift, 2026-07-09): SF Rounded is the DISPLAY
/// tier only — "functional text (body, rows, labels) stays SF Pro Text, which
/// scans crisper at UI sizes and keeps the app feeling native." The complaint
/// was inconsistency, and consistency is what fixes it, so every slab here is
/// the text face at one weight. The large nav title stays rounded, as every
/// display-tier heading in the app does.
private enum Slab {
    static let height: CGFloat = 56
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
    }
}

/// The field slab — one shape holding both the input and its verb. Replaces
/// field-plus-side-pill, which read as two controls for one act.
///
/// The verb is text, not a filled capsule: a filled control inside a filled
/// well is the "button in a button" that made this area busy. It dims until
/// there's something to act on, so it still says when it's live (the §83 rule
/// that a control must state its own disabled state, not just gray its label).
struct WalletSlabField: View {
    let placeholder: String
    @Binding var text: String
    /// The verb, in caps — the one place caps are right, because it's a
    /// control label inside a field, not an eyebrow over content (§8 bans
    /// ALL-CAPS eyebrows, which this isn't).
    let actionLabel: String
    var keyboard: UIKeyboardType = .default
    var focus: FocusState<Bool>.Binding? = nil
    /// Fires even when the field is empty for callers whose verb doesn't need
    /// input (the book's NAME opens a sheet); callers that need text guard.
    var alwaysEnabled = false
    let action: () -> Void

    private var armed: Bool {
        alwaysEnabled || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Group {
                if let focus {
                    field.focused(focus)
                } else {
                    field
                }
            }
            Button(action: action) {
                Text(actionLabel)
                    .dsText(.subhead13).fontWeight(.bold)
                    .foregroundStyle(armed ? DS.tint : DS.textTertiary)
                    .animation(DS.Motion.standard, value: armed)
            }
            .buttonStyle(.plain)
            .disabled(!armed)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: Slab.height)
        .background(DS.surfaceWell, in: Slab.shape)
    }

    private var field: some View {
        TextField(placeholder, text: $text)
            .dsText(.body17)
            .foregroundStyle(DS.textPrimary)
            .tint(DS.tint)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(action)
    }
}

/// The primary slab — the screen's one filled block, so it reads as THE verb.
struct WalletSlabButton: View {
    let title: String
    var systemImage: String? = nil
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(LocalizedStringKey(title))
                    .dsText(.body17).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Slab.height)
            .background(busy ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                        in: Slab.shape)
            .contentShape(Slab.shape)
            .animation(DS.Motion.standard, value: busy)
        }
        .buttonStyle(.plain)
    }
}

/// A door slab — a title and the fact it stands in front of. The fact is the
/// point: a door that says "Address book · 4 names" hides nothing, where a
/// headed section with the same four rows was just furniture.
struct WalletSlabDoor: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                Text(LocalizedStringKey(title))
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
                Text(detail)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(height: Slab.height)
            .background(DS.gray100, in: Slab.shape)
            .contentShape(Slab.shape)
        }
        .buttonStyle(.plain)
    }
}
