import SwiftUI

/// **THE WAY BACK TO MOVE'S MENU (prd §1781).** The verb in a sentence used
/// to open the verbs; nothing in a sentence takes a touch now, so every
/// sentence's foot leads with this card. Move's own sentence hands it the
/// act; the sentences Move mounts (Lend, a private send, Receive privately,
/// Receive on Aztec) read it from the environment Move sets over them.
struct MoveBackCard: View {
    /// The act, where the caller holds it; else the environment's.
    var act: (() -> Void)?
    var disabled = false
    @Environment(\.moveBack) private var back

    var body: some View {
        if let go = act ?? back {
            Button {
                go()
                DSHaptic.selection()
            } label: {
                Image(systemName: "chevron.left").dsGlyph(.title, weight: .bold)
                    .foregroundStyle(disabled ? DS.textSecondary : DS.textPrimary)
                    .frame(width: MoveSentence.actHeight, height: MoveSentence.actHeight)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous).fill(DS.fillStrong))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .disabled(disabled)
            .accessibilityLabel(Text("Back to the list"))
        }
    }
}

private struct MoveBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens Move's menu, set by Move over the sentences it mounts.
    var moveBack: (() -> Void)? {
        get { self[MoveBackKey.self] }
        set { self[MoveBackKey.self] = newValue }
    }
}

/// **A SENTENCE'S CHOICES, AS ROWS (prd §1781).** The private sentences and
/// Lend write their own words; what each word did is a row here, in the
/// shape of Move's own: the name grey, what is picked in white, a chevron
/// because something opens, "Choose" in the pick's pink where the first
/// thing is still to be picked.
struct MoveChoiceRow: Identifiable {
    let id: String
    let name: String
    let value: String
    var empty = false
    var ink: Color?
    let act: () -> Void
}

/// **A CHOICE'S ROW (prd §1782).** The name small above, what is picked
/// large beneath it, a chevron at the trailing edge: the answer is the
/// thing seen and pressed, where a small figure at the far edge read as a
/// settings form.
struct MoveChoiceRowLabel: View {
    let name: String
    let value: String
    var ink: Color = DS.textPrimary

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                Text(verbatim: value)
                    .dsText(.heading24)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.right").dsGlyph(.subhead, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: MoveChoiceRowLabel.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static let height: CGFloat = 60
}

struct MoveChoiceRows<Menu: View>: View {
    let rows: [MoveChoiceRow]
    var disabled = false
    /// The ink of the first row still to be picked: the pick's, or Aztec's
    /// own on an Aztec sentence (prd §1779).
    var nextInk: Color = DS.pickInk
    /// **A LIST IS A MENU ON ITS ROW (prd §1784).** The id of the row whose
    /// menu is up, and that row's list. The rows stay where they are; a tap
    /// outside the menu sets this nil.
    var open: Binding<String?>
    @ViewBuilder var menu: (String) -> Menu
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        if !rows.isEmpty {
            let next = rows.first { $0.empty }?.id
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { r in
                    Button {
                        r.act()
                        DSHaptic.selection()
                    } label: {
                        MoveChoiceRowLabel(name: r.name, value: r.empty ? String(localized: "Choose") : r.value,
                                           ink: r.id == next ? nextInk : r.ink ?? DS.textPrimary)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Changes it"))
                    .popover(isPresented: Binding(get: { open.wrappedValue == r.id },
                                                  set: { if !$0, open.wrappedValue == r.id { open.wrappedValue = nil } }),
                             attachmentAnchor: .rect(.bounds)) {
                        MoveMenuBox { menu(r.id) }
                            .environment(chrome)
                    }
                }
            }
            .disabled(disabled)
        }
    }
}

/// A row's list as its menu (prd §1784): a menu's width, as tall as its
/// rows up to `MoveSentence.menuRoom`, then they scroll, on the system's own
/// popover ground. A popover on the phone too, never a sheet.
struct MoveMenuBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            box
            ScrollView { box }.scrollIndicators(.hidden)
        }
        .frame(width: MoveSentence.menuWidth)
        .frame(maxHeight: MoveSentence.menuRoom)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThickMaterial)
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
    }
}

/// A list's own name at its head, which closes it without a pick (prd
/// §1781): the sentence's word used to, and takes no touch now.
struct MoveListBack: View {
    let name: String
    var ink: Color = DS.pickInk
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            // The glyph in the head column, as every section name's (prd §1496).
            HStack(spacing: DSRoomChassis.headGap) {
                Image(systemName: "chevron.left").dsGlyph(.body, weight: .semibold)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text(verbatim: name).dsText(.heading24)
            }
            .foregroundStyle(ink)
            .frame(minHeight: MoveSentence.listRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Closes the list"))
    }
}
