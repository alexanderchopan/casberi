import SwiftUI

/// The address book, on its own page (prd §189, 2026-07-23).
///
/// It used to be a headed section on the Wallet manager, with its own
/// paragraph, its own blue "Name an address" text link, and a row list that
/// grew without limit — the largest block of furniture below the shelf, on a
/// screen whose job is the shelf and the one field. The Wallet screen now
/// carries a single door wearing this book's own count, and everything the
/// section said lives here, where the naming actually happens.
///
/// The search field came with it. On the manager, the watch field doubled as
/// the book's filter (prd §184) — clever, and the reason that field needed the
/// words "or search your book" in its placeholder. One field per job is the
/// simpler trade: up there it only watches, and the book searches itself.
struct AddressBookScreen: View {
    @Bindable private var book = AddressBook.shared
    @Bindable private var wallet = WalletStore.shared
    @State private var query = ""
    @State private var showNameSheet = false
    @State private var openEntry: AddressBook.Entry?
    @FocusState private var searchFocused: Bool

    /// Named addresses that AREN'T watched — the light tier. Watched wallets
    /// have the roster on the manager, and listing them twice would make one
    /// book read as two (the rule this screen inherited).
    private var entries: [AddressBook.Entry] {
        let watched = Set(wallet.addresses.map { AddressBook.key(for: $0.address) })
        return book.search(query).filter { !watched.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                WalletSlabField(placeholder: String(localized: "Search names or addresses"),
                                text: $query,
                                actionLabel: String(localized: "NAME"),
                                focus: $searchFocused) {
                    DSHaptic.tap()
                    showNameSheet = true
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                      bottom: DS.Space.s2, trailing: DS.Space.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(entries) { entry in
                    Button {
                        DSHaptic.selection()
                        openEntry = entry
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            book.remove(entry.address)
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            } footer: {
                Text(entries.isEmpty && query.isEmpty
                     ? "Name any address — a person, a contract, your own account elsewhere. Names cost nothing, land nothing, and title every transaction with that address in your own words."
                     : "Names only — nothing lands from these. Tap one to see it, copy it, or start watching it.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
            .listRowSeparator(.hidden)

            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("Address book")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showNameSheet) { NameAddressSheet() }
        .sheet(item: $openEntry) { entry in AddressCard(entry: entry) }
        // Ask the chain what the unnamed-kind entries are, a few at a time —
        // keyless, and only for entries that haven't been checked (prd §169).
        .task { await AddressKind.detectPending() }
    }

    /// One row: the kind's mark, the name, the address, and Copy — the book's
    /// most-used verb, on every row rather than one level down.
    private func row(_ entry: AddressBook.Entry) -> some View {
        HStack(spacing: DS.Space.s3) {
            AddressMark(entry: entry, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(entry.subline).dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            CopyAddressButton(address: entry.address)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
