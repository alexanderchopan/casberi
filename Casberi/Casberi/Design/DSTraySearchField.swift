import SwiftUI

/// THE FIND TRAY'S FIELD, AT THE BOTTOM ON GLASS (prd §1081, §1085, §1086,
/// §1090) — Markets' Watch, Reading's Follow and Search, Social's Follow and
/// the Wallet's Follow draw this one control. Four hand copies drifted in
/// nothing yet; this is so they cannot.
///
/// The field leads with the magnifier, then the words; the spinner shows
/// while the tray is asking; with words, a clear key, and without, an
/// optional `idle` key (the Wallet's paste).
struct DSTraySearchField<Idle: View>: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var searching: Bool = false
    var keyboard: UIKeyboardType = .default
    /// A field that takes a NAME capitalizes its words; a search does not.
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .search
    var onSubmit: () -> Void = {}
    @ViewBuilder var idle: () -> Idle

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.subhead)
                .foregroundStyle(DS.textSecondary)
            TextField(placeholder, text: $text)
                .dsText(.body17)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .focused(focus)
            if searching { DSSpinner(size: .small) }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Clear"))
            } else {
                idle()
            }
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s1)
        .frame(height: 52)
        .dsGlass(cornerRadius: 26)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
    }
}

extension View {
    /// Pins a find tray's field under its list. On iOS 26 it is a bar, so the
    /// rows passing under the glass dissolve (the soft edge) instead of
    /// reading through it as ghost words (user: "glitches here how the search
    /// bar shows"); below 26, the inset it always was.
    @ViewBuilder
    func dsFindField<Field: View>(@ViewBuilder _ field: () -> Field) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: field)
                .scrollEdgeEffectHidden(false, for: .bottom)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            safeAreaInset(edge: .bottom, content: field)
        }
    }
}

extension DSTraySearchField where Idle == EmptyView {
    init(placeholder: String, text: Binding<String>, focus: FocusState<Bool>.Binding,
         searching: Bool = false, keyboard: UIKeyboardType = .default,
         submitLabel: SubmitLabel = .search, onSubmit: @escaping () -> Void = {}) {
        self.init(placeholder: placeholder, text: text, focus: focus, searching: searching,
                  keyboard: keyboard, submitLabel: submitLabel, onSubmit: onSubmit,
                  idle: { EmptyView() })
    }
}

/// **A FIND TRAY'S GROUP IS THE FEED'S CARD (prd §1266, user: "yes do
/// it").** The panel's fill, a pink glyph and the group's name in the head
/// ink ("From your cards", "Recent"), an optional control trailing, the rows
/// inside — which bring their own column. It was a grey `label12` over loose
/// rows (`DSTrayHead`, deleted with it).
struct DSTrayGroup<Content: View, Trailing: View>: View {
    let title: String
    let glyph: String
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    init(_ title: String, glyph: String, @ViewBuilder content: () -> Content,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.glyph = glyph
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Image(systemName: glyph)
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .dsText(.heading20)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Space.s2)
                trailing
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s1)
            content
        }
        .padding(.bottom, DS.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No fill (prd §1393): a tray's group is a named block, bare, as a
        // sheet's and a section's are.
        .padding(.horizontal, DS.Space.s3)
        .padding(.top, DS.Space.s3)
    }
}

extension DSTrayGroup where Trailing == EmptyView {
    init(_ title: String, glyph: String, @ViewBuilder content: () -> Content) {
        self.init(title, glyph: glyph, content: content) { EmptyView() }
    }
}
