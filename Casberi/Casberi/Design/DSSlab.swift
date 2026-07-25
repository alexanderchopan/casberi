import SwiftUI

/// The slab — the app's one shape for a manage page's controls (prd §190,
/// 2026-07-23; born on the Wallet manager as §189's `WalletSlab*`).
///
/// The complaint that started it, about the Wallet screen below its roster:
/// *"we have different fonts, different shapes, and I think to myself, how
/// would Cash App do this screen."* It was a fair census — a recessed field
/// with a side pill, a full-width capsule with a caption, three paragraph
/// footers, a headed section with a blue text link, and a gear row: six shapes
/// and four type rungs stacked on each other. The answer wasn't new art, it
/// was one rule, and the rule generalizes to every manage page in the catalog:
///
/// **Below a screen's identity area, every control is a slab** — one height,
/// one radius (`DS.Radius.widget`, the tile radius §8 already sanctions). The
/// only round things on a manage page are people and assets (§185's mark
/// grammar). The eye then reads a rhythm instead of a collage.
///
/// **One font, and it is SF Pro Text.** The mock that won this set the slabs
/// in SF Rounded, Cash App style. That would break a standing rule
/// (`Typography.swift`, 2026-07-09): SF Rounded is the DISPLAY tier only —
/// "functional text (body, rows, labels) stays SF Pro Text, which scans
/// crisper at UI sizes and keeps the app feeling native." The complaint was
/// *inconsistency*, and consistency is the fix, so every slab is the text face
/// at one weight; the rounded face stays where it lived, on display headings.
///
/// **What is NOT a slab**, deliberately: a page's own content rows (a topic, a
/// feed, a store — those wear §184/§185's marks and are the person's data, not
/// a control); the shelves and rosters above, which the ruling explicitly kept
/// ("I do not want to change any of the top shelf rows of avatars"); the
/// numbered steps of a pre-connect form (kept whole by §186); and Disconnect,
/// which stays the quiet centered red row it already is on every screen —
/// destructive sits outside the rhythm on purpose.
///
/// **One gray sentence per screen** is the companion rule. Most of the "form
/// feel" on these pages was never the controls; it was two or three footer
/// paragraphs stacked under them. Everything a footer said moves to the door,
/// dialog, or screen that owns it.
enum DSSlab {
    static let height: CGFloat = 56
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
    }
}

/// The field slab — one shape holding both the input and its verb. Replaces
/// field-plus-side-pill, which read as two controls for one act.
///
/// The verb is text, not a filled capsule: a filled control inside a filled
/// well is the "button in a button" that made these areas busy. It dims until
/// there's something to act on, so it still says when it's live (the §83 rule
/// that a control states its own disabled state, not just grays its label).
struct DSSlabField: View {
    let placeholder: String
    @Binding var text: String
    /// The verb, in caps — the one place caps are right, because it's a
    /// control label inside a field, not an eyebrow over content (§8 bans
    /// ALL-CAPS eyebrows, which this isn't).
    let actionLabel: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    var focus: FocusState<Bool>.Binding? = nil
    /// Fires even when the field is empty, for callers whose verb doesn't need
    /// input (the address book's NAME opens a sheet).
    var alwaysEnabled = false
    /// A caller-supplied arm condition — overrides the default "text isn't
    /// empty" when the verb should only light up in a specific state (the
    /// address book's ADD, live only when the typed text is an addable
    /// address, not any old search term).
    var isArmed: Bool? = nil
    /// A SECOND verb inside the same slab (prd §212, 2026-07-25) — the quieter
    /// one, shown only while `secondaryArmed`. It exists because the Wallet
    /// manager has two real things to do with a typed address (watch it, which
    /// is capped and starts syncing; or just name it, which is neither), and
    /// the second one was a floating text button on its own line under the
    /// field — a fifth block on a page whose whole problem was block count.
    /// Two verbs in one slab is still one control for one act; a second line
    /// was two.
    var secondaryLabel: String? = nil
    var secondaryArmed = false
    var secondaryAction: () -> Void = { }
    let action: () -> Void

    private var armed: Bool {
        if let isArmed { return isArmed }
        return alwaysEnabled || !text.trimmingCharacters(in: .whitespaces).isEmpty
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
            if let secondaryLabel, secondaryArmed {
                Button(action: secondaryAction) {
                    Text(secondaryLabel)
                        .dsText(.subhead13).fontWeight(.bold)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
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
        .animation(DS.Motion.standard, value: secondaryArmed)
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DSSlab.height)
        .background(DS.surfaceWell, in: DSSlab.shape)
    }

    @ViewBuilder private var field: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .dsText(.body17)
        .foregroundStyle(DS.textPrimary)
        .tint(DS.tint)
        .keyboardType(keyboard)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(action)
    }
}

/// The primary slab — a screen's one filled block, so it reads as THE verb.
struct DSSlabButton: View {
    let title: String
    var systemImage: String? = nil
    var busy = false
    var enabled = true
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
            // A hand-rolled fill must swap the FILL when inert, not just dim
            // the label (§83, paid for by a button that read live while dead).
            .foregroundStyle(enabled && !busy ? AnyShapeStyle(.white)
                                              : AnyShapeStyle(DS.textTertiary))
            .frame(maxWidth: .infinity)
            .frame(height: DSSlab.height)
            .background(enabled && !busy ? AnyShapeStyle(DS.tint)
                                         : AnyShapeStyle(DS.gray200),
                        in: DSSlab.shape)
            .contentShape(DSSlab.shape)
            .animation(DS.Motion.standard, value: busy)
            .animation(DS.Motion.standard, value: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

/// A door slab — a title and the fact it stands in front of. The fact is the
/// point: a door reading "Address book · 4 names" hides nothing, where a
/// headed section holding the same four rows was just furniture.
struct DSSlabDoor: View {
    let title: String
    var detail: String = ""
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
                Text(LocalizedStringKey(title))
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
                if !detail.isEmpty {
                    Text(detail)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(height: DSSlab.height)
            .background(DS.gray100, in: DSSlab.shape)
            .contentShape(DSSlab.shape)
        }
        .buttonStyle(.plain)
    }
}

/// A switch slab — the shape for a control that STARTS something, on the
/// pages where flipping it is the whole act (a chain on OpenSea or
/// GeckoTerminal, a seat on Peer or Privacy Pools). Those rows aren't settings
/// hiding in a card; each one is that screen's connect verb for one lane, so
/// it gets a full block rather than a line in a stacked toggle list.
///
/// The detail line stays ONE line and carries the lane's own fact, never an
/// explanation — explanations belong to the screen's single sentence.
struct DSSlabSwitch: View {
    let title: String
    var detail: String = ""
    @Binding var isOn: Bool

    var body: some View {
        // `Toggle` rather than a hand-rolled knob: it keeps the switch trait
        // for VoiceOver and the whole label as the target. (Sim gotcha, not a
        // bug: switches ignore a synthetic tap — drive them with a drag
        // across the knob.)
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .tint(DS.tint)
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DSSlab.height)
        .background(DS.gray100, in: DSSlab.shape)
    }
}

/// The screen's one sentence — the promise, centered under its controls.
/// Every manage page gets exactly one; everything else a footer used to say
/// moves behind the door or dialog that owns it.
struct DSSlabNote: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s1)
    }
}

/// A scannable checkmark list — capabilities or features, one per line (prd
/// §192, 2026-07-23). Born on `BridgeConnectedState` ("capabilities are
/// sentences") for the CONNECTED state; promoted here so the product page can
/// render the same visual grammar PRE-connect, when a bridge's differentiated
/// features don't fit the one-sentence hook the summary rule caps at (Wallet's
/// approval/DeFi/Safe monitoring is the case that forced this: six real,
/// distinct capabilities were being crammed into one 60-word run-on clause
/// rather than deleted or restructured). Same lines, same look, whichever side
/// of Connect you're standing on.
struct DSCheckList: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.confirm)
                    Text(LocalizedStringKey(line))
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension View {
    /// The list-row dress every slab stack wears: full-bleed to the screen's
    /// own margins, no list chrome, no separator. One modifier so a slab
    /// section can never drift from the wallet's spacing.
    func dsSlabSection(topPadding: CGFloat = DS.Space.s2) -> some View {
        self
            .listRowInsets(EdgeInsets(top: topPadding, leading: DS.Space.s4,
                                      bottom: 0, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
