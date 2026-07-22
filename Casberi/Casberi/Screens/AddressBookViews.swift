import SwiftUI
import SwiftData
import UIKit

/// The address book's shared pieces (prd §169, 2026-07-21): the kind mark, the
/// copy button every row carries, the name-an-address sheet, and the address
/// card behind a tap.

extension AddressBook.Entry {
    /// "0x9a2E…44b1 · Contract" — the address, plus what it turned out to be
    /// and where it came from, when either is known. A `.wallet` says nothing
    /// extra: a wallet is the unmarked case, and labelling it would put a word
    /// on every row that differentiates none of them.
    var subline: String {
        var parts = [short]
        if let label = kind.label { parts.append(label) }
        if let provenance { parts.append(provenance) }
        return parts.joined(separator: " · ")
    }
}

/// What an address IS, as a mark. A wallet is a WHO — it wears the same
/// identicon face the watched wallets and transfer stages use, so the same
/// address looks the same everywhere. Everything else is machinery and wears a
/// square glyph, which is what lets a fifty-row book separate people from
/// contracts with no grouping UI at all.
struct AddressMark: View {
    let entry: AddressBook.Entry
    var size: CGFloat = 32

    var body: some View {
        if let glyph = entry.kind.glyph {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(DS.fillFaint)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: glyph)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)
                }
        } else {
            WalletFace(address: entry.address, size: size)
        }
    }
}

/// Copy — the book's most-used verb, so it rides every row instead of hiding
/// one level down. States the outcome in place (the app's own "a control says
/// what happens, then says it happened" grammar) rather than firing a toast
/// from a list row.
struct CopyAddressButton: View {
    let address: String
    var expanded = false
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = address
            DSHaptic.success()
            withAnimation(DS.Motion.standard) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(DS.Motion.standard) { copied = false }
            }
        } label: {
            Group {
                if expanded {
                    Text(copied ? "Copied" : "Copy")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(copied ? DS.confirm : DS.tint)
                } else {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(copied ? DS.confirm : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 9,
                                                                       style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Address copied" : "Copy address")
    }
}

/// Name an address — the book's front door. Accepts one address or a pasted
/// list ("Mom, 0x9a2E…" per line), because a person arriving with a set of
/// addresses shouldn't have to add them one at a time (the Tokens screen's
/// bulk-watch precedent, prd §169).
struct NameAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var bulk = ""
    @State private var showBulk = false
    @State private var outcome: String?
    private var book = AddressBook.shared

    var body: some View {
        NavigationStack {
            List {
                if showBulk {
                    Section {
                        TextEditor(text: $bulk)
                            .frame(minHeight: 140)
                            .dsText(.callout15)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Paste a list").dsText(.label12).foregroundStyle(DS.textSecondary)
                    } footer: {
                        Text("One per line, or comma-separated. A name before an address takes it — \"Mom, 0x9a2E…\". A bare address lands under its short form, ready to rename.")
                            .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    }
                } else {
                    Section {
                        TextField("Name", text: $name)
                            .dsText(.callout15)
                        TextField("Address (0x…, ENS, or .sol)", text: $address)
                            .dsText(.callout15)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Name an address").dsText(.label12).foregroundStyle(DS.textSecondary)
                    } footer: {
                        Text("Nothing lands from a named address — naming is free. Watching its activity is a separate choice, on the address itself.")
                            .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    }
                }
                Section {
                    Button(showBulk ? "Name one at a time" : "Paste a list instead") {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { showBulk.toggle() }
                    }
                    .dsText(.callout15)
                    .foregroundStyle(DS.tint)
                }
                if let outcome {
                    Section {
                        Text(outcome).dsText(.callout15).foregroundStyle(DS.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .navigationTitle("Address book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(DS.tint)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .tint(DS.tint)
                        .disabled(showBulk ? bulk.isEmpty : !canSaveOne)
                }
            }
        }
    }

    private var canSaveOne: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && book.looksLikeAddress(address.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func save() {
        if showBulk {
            let landed = book.addBulk(bulk)
            guard landed > 0 else {
                // Honest refusal: say what was wrong, don't just fail to close.
                outcome = String(localized: "No addresses found in that — each line needs an address (0x…, ENS, or .sol).")
                return
            }
            DSHaptic.success()
            detect(book.all.prefix(landed).map(\.address))
            dismiss()
            return
        }
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        book.setName(name, for: addr)
        DSHaptic.success()
        detect([addr])
        dismiss()
    }

    /// Ask the chain what these are, once they're in the book. Keyless, and
    /// detached so the sheet closes immediately.
    private func detect(_ addresses: [String]) {
        Task { @MainActor in
            for address in addresses { await AddressKind.detect(address) }
        }
    }
}

/// The address card (prd §169) — one address, everything the app honestly
/// knows about it: its name, what it is, the address itself with Copy, the
/// watch toggle as an UPGRADE on the entry, and your own history together,
/// pulled from the corpus.
///
/// The history section is what makes this Casberi's rather than a contacts
/// app: landed transfers already carry `counterpartyAddress`, so the card can
/// show the relationship the corpus already recorded — without one extra
/// request.
struct AddressCard: View {
    let entry: AddressBook.Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Bindable private var wallet = WalletStore.shared
    private var book = AddressBook.shared
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var refusal: String?

    init(entry: AddressBook.Entry) { self.entry = entry }

    /// Live, so a rename or a kind landing repaints the card.
    private var current: AddressBook.Entry { book.entry(for: entry.address) ?? entry }

    private var isWatched: Bool {
        wallet.addresses.contains { WalletWatch.sameAddress($0.address, entry.address) }
    }

    /// The corpus's own record of this address — every transaction where it
    /// was the counterparty, newest first.
    private var history: [Thing] {
        let key = AddressBook.key(for: entry.address)
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        return all.filter { thing in
            guard let cp = thing.counterpartyAddress else { return false }
            return AddressBook.key(for: cp) == key
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.s3) {
                    AddressMark(entry: current, size: 64)
                        .padding(.top, DS.Space.s4)
                    Text(current.name)
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(kindLine)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)

                    addressRow
                    watchRow
                    if let refusal {
                        Text(refusal)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.s1)
                    }
                    historySection
                    explorerRow
                }
                .padding(DS.Space.s4)
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .navigationTitle("Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rename") {
                        nameDraft = current.name
                        renaming = true
                    }.tint(DS.tint)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(DS.tint)
                }
            }
            .alert("Name this address", isPresented: $renaming) {
                TextField("Name", text: $nameDraft)
                Button("Save") {
                    book.setName(nameDraft, for: entry.address)
                    DSHaptic.success()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A blank name removes it from your book.")
            }
            .task { await AddressKind.detect(entry.address) }
        }
    }

    private var kindLine: String {
        var parts: [String] = [current.kind.label ?? String(localized: "Wallet")]
        if let provenance = current.provenance { parts.append(provenance) }
        parts.append(String(localized: "named \(current.addedAt.formatted(.dateTime.month(.abbreviated).day()))"))
        return parts.joined(separator: " · ")
    }

    private var addressRow: some View {
        HStack(spacing: DS.Space.s3) {
            Text(current.address)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .monospaced()
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            CopyAddressButton(address: current.address, expanded: true)
        }
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    /// Watching as an UPGRADE on the book entry — with its cost stated, and
    /// the cap honoured in words rather than a control that refuses (prd §170).
    private var watchRow: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Land its activity")
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Text(isWatched
                     ? String(localized: "Transfers, approvals, and holdings are landing in your feed.")
                     : String(localized: "Transfers, approvals, and holdings — the full feed."))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isWatched }, set: { toggleWatch($0) }))
                .labelsHidden()
                .tint(DS.confirm)
        }
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    private func toggleWatch(_ on: Bool) {
        refusal = nil
        if on {
            switch wallet.outcome(ofAdding: entry.address, label: current.name) {
            case .added:
                DSHaptic.success()
            case .limitReached:
                refusal = String(localized: "You're watching \(WalletStore.watchLimit) wallets — the limit for now. Stop watching one to watch this. Its name stays either way.")
            case .alreadyWatching, .invalid:
                break
            }
        } else if let i = wallet.addresses.firstIndex(where: {
            WalletWatch.sameAddress($0.address, entry.address)
        }) {
            // Unwatching DEMOTES to the book (prd §169): the landed history and
            // cursors go, honestly, but the name is the person's own data and
            // stays.
            wallet.addresses.remove(at: i)
            DSHaptic.tap()
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let things = history
        if !things.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Your history together · \(things.count)")
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(things.prefix(6)) { thing in
                    HStack(spacing: DS.Space.s3) {
                        KindGlyph(kind: thing.kind, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(thing.title).dsText(.subhead13)
                                .foregroundStyle(DS.textPrimary).lineLimit(1)
                            Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(DS.Space.s3)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    /// The one door out — and only for an address an explorer can actually
    /// serve (a Solana address on Etherscan would be a dead link).
    @ViewBuilder
    private var explorerRow: some View {
        if ENS.isHexAddress(current.address),
           let url = URL(string: "https://etherscan.io/address/\(current.address)") {
            Button {
                DSHaptic.tap()
                openURL(url)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text("View on Etherscan").dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }
}
