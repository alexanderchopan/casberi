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

extension DSTraySearchField where Idle == EmptyView {
    init(placeholder: String, text: Binding<String>, focus: FocusState<Bool>.Binding,
         searching: Bool = false, keyboard: UIKeyboardType = .default,
         submitLabel: SubmitLabel = .search, onSubmit: @escaping () -> Void = {}) {
        self.init(placeholder: placeholder, text: text, focus: focus, searching: searching,
                  keyboard: keyboard, submitLabel: submitLabel, onSubmit: onSubmit,
                  idle: { EmptyView() })
    }
}

/// A find tray's group name ("Near you", "From your Wallet"): a quiet label
/// over its rows, never a day (§740).
struct DSTrayHead: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s1)
    }
}
