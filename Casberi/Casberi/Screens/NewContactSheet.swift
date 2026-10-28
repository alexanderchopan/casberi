import SwiftUI

/// People's New contact (prd §1300): a name, and an email or a wallet
/// address, kept in Casberi's own list without importing Contacts
/// (`NewContact`). Nothing is written to the phone's address book.
///
/// Optional environment only (prd §872).
struct NewContactSheet: View {
    /// After the person is kept and the sheet has closed.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome: ShellChrome?

    @State private var name = ""
    @State private var reach = ""
    @State private var failure: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        DSTray(title: String(localized: "New contact"), height: 420) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSlabField(placeholder: String(localized: "Name"), text: $name, actionLabel: "",
                            focus: $nameFocused, autocapitalization: .words, action: {})
                DSSlabField(placeholder: String(localized: "Email or account address"), text: $reach,
                            actionLabel: String(localized: "Save"), keyboard: .emailAddress,
                            isArmed: !name.trimmingCharacters(in: .whitespaces).isEmpty
                                && NewContact.reach(reach) != nil,
                            submitLabel: .done,
                            // Usually copied, never typed (prd §1588).
                            paste: { reach = $0 }, action: save)
                if let failure {
                    DSFootnote(Text(verbatim: failure))
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
        .onAppear { nameFocused = true }
    }

    private func save() {
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Adding works once you leave the demo."))
            return
        }
        guard NewContact.save(name: name, reach: reach) else {
            failure = String(localized: "An email, an account address or a name like vitalik.eth.")
            return
        }
        // The success flash carries the one buzz (prd §1587).
        chrome?.flash(String(localized: "Added \(name.trimmingCharacters(in: .whitespaces))."), tone: .success)
        dismiss()
        onSaved()
    }
}
