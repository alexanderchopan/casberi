import SwiftUI
import SwiftData

/// WHO IS THIS ADDRESS (prd §1775): the tray a transfer's Save raises for an
/// address the book does not hold. Naming it was the only answer, which made
/// a second "Jesse" beside the one Contacts already had; here the people you
/// have are rows, and picking one puts the address on them. "New name" is the
/// old answer, kept as the first row.
struct AddToContactTray: View {
    let address: String
    /// The caller's own naming alert, raised once this tray has gone.
    let onNewName: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var people: [Contact] = []
    @State private var query = ""
    @State private var wantsName = false
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private var shown: [Contact] {
        Array(AddToContact.matching(people, query: trimmed).prefix(40))
    }

    /// A book entry this address imitates: said before anyone is picked, as
    /// Send says it (the poisoning rule, prd §1025).
    private var imitated: String? {
        AddressBook.shared.lookalikes(of: address).first?.name
    }

    var body: some View {
        DSTray(title: String(localized: "Who is \(AddressTail.short(address))"), height: 640,
               detents: [.large], scrollsItself: true) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let imitated {
                        Text("Looks like \(imitated)'s address. It is a different one.")
                            .dsText(.body17)
                            .foregroundStyle(DS.attentionInk)
                            .padding(.bottom, DS.Space.s3)
                    }
                    if trimmed.isEmpty {
                        DSDoorRow(icon: "character.cursor.ibeam", label: "New name") {
                            wantsName = true
                            dismiss()
                        }
                    }
                    ForEach(shown) { person in row(person) }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .dsFindField {
                DSTraySearchField(placeholder: String(localized: "Search your contacts"),
                                  text: $query, focus: $fieldFocused)
            }
        }
        .task {
            let built = ContactIndexSources.contacts.isEmpty
                ? ContactIndexSources.rebuild(context: modelContext) : ContactIndexSources.contacts
            people = AddToContact.candidates(built.filter(ContactIndexSources.isListed), for: address)
        }
        .onDisappear { if wantsName { onNewName() } }
    }

    private func row(_ person: Contact) -> some View {
        Button {
            add(to: person)
        } label: {
            HStack(spacing: DS.Space.s3) {
                ContactFace(contact: person, size: DS.Face.list)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: person.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let line = AddressesSection.line(of: person) {
                        Text(verbatim: line)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: AddressesSection.rowPitch)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    /// The address takes the person's name in the book, so its transfers
    /// read their name, and the two are joined, so Contacts keeps one row.
    private func add(to person: Contact) {
        AddToContact.join(address, to: person, context: modelContext)
        DSHaptic.success()
        chrome.flash(String(localized: "Added to \(person.name)"))
        dismiss()
    }
}

/// The tray's rules, apart from its view.
enum AddToContact {
    /// Someone an address can belong to: named, a person or a company, and
    /// not already holding this address. Whoever dealt with you last leads.
    static func candidates(_ contacts: [Contact], for address: String) -> [Contact] {
        let key = Identity.key(.wallet, address)
        return contacts
            .filter { c in
                !c.isUnnamed && !c.has(key) && c.lead.kind != .biller
                    && (c.kind == .person || c.kind == .organization)
            }
            .sorted { ($0.lastActedAt ?? .distantPast, $1.name) > ($1.lastActedAt ?? .distantPast, $0.name) }
    }

    /// By name or anything they go by; an empty query keeps them all.
    static func matching(_ contacts: [Contact], query: String) -> [Contact] {
        guard !query.isEmpty else { return contacts }
        return contacts.filter { c in
            c.name.lowercased().contains(query)
                || c.identities.contains { $0.body.lowercased().contains(query) }
        }
    }

    @MainActor
    static func join(_ address: String, to person: Contact, context: ModelContext) {
        AddressBook.shared.setName(person.name, for: address)
        ContactLinksStore.shared.confirm(Identity.key(.wallet, address), person.lead.key)
        Task { @MainActor in await AddressKind.detect(address) }
        CounterpartyRetitle.applyCurrentName(for: address, in: context)
        ContactIndexSources.rebuild(context: context)
    }
}
