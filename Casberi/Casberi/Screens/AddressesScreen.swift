import SwiftUI
import SwiftData

/// The Addresses list — the fourth segment under the face (prd §916 and its
/// amendment; `docs/addresses-spec.md` section 1).
///
/// A DIRECTORY, not a feed: it has no time, so it takes the Accounts screen's
/// own anatomy — the shared search field above, the dock's category chips as
/// filters, rows — and never the room chassis. One row per `Contact`, built at
/// read time by `ContactIndexSources.rebuild` from the stores that already
/// hold the identities; nothing here is stored.
///
/// **The row.** The face and the name on one line, nothing under it (user,
/// 2026-09-25); the sheet names every address the contact carries. The
/// trailing slot is EMPTY: no money (user, 2026-08-21), no counts (§345).
///
/// **The chips.** A contact stands in every dock category one of its
/// identities belongs to — a wallet with a Farcaster handle is under Wallet
/// AND Social — and a chip is drawn only for a category that holds somebody,
/// so a selected chip never stands over an empty list (the Accounts rule).
struct AddressesSection: View {
    /// The Accounts screen's search field, shared; the query filters the rows
    /// live over every identity a row carries. It is a filter, not a
    /// resolver (§690: a new address is asked for on the seat pages).
    let query: String

    @Environment(\.modelContext) private var modelContext
    @State private var contacts: [Contact] = []
    @State private var scope = AddressScope(name: nil)
    @State private var opened: Contact?
    /// The newest transfer whose counterparty nobody has named — the list's
    /// one nudge (section 1, section 9: "any time", one row at a time).
    @State private var nudge: (address: String, title: String)?
    /// The one "Same person?" the list may draw (section 3): the newest live
    /// suggestion whose two ends are both here, with the model's sentence
    /// under it when the phone can give one.
    @State private var suggestion: ContactLink?
    @State private var verdict: String?
    @State private var naming = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if query.isEmpty, scope.name == nil, let nudge {
                nudgeRow(nudge)
            }
            if query.isEmpty, scope.name == nil, let suggestion,
               let a = ContactIndexSources.contact(forKey: suggestion.a),
               let b = ContactIndexSources.contact(forKey: suggestion.b) {
                suggestionRow(suggestion, a: a, b: b)
            }
            if query.isEmpty, scopes.count > 2 {
                DSScopeTiles(sections: scopes, active: scope, strip: true) { picked in
                    withAnimation(DS.Motion.standard) { scope = picked }
                }
            }
            if contacts.isEmpty {
                DSEmptyState(headline: DSProse.text("Nobody here yet"),
                             words: Text("Nobody here yet. Follow an address, watch an account, or connect Contacts, and they land here."),
                             scale: .list(rows: 4))
                    .padding(.vertical, DS.Space.s4)
            } else if shown.isEmpty {
                DSEmptyState(headline: DSProse.text("No match"),
                             words: Text("Nobody matches that."),
                             scale: .list(rows: 2))
                    .padding(.vertical, DS.Space.s4)
            } else {
                list
            }
        }
        // The index is rebuilt on appear, never in a body (§628). It reads
        // the stores and the ledger only — no network.
        .task { await refresh() }
        .alert("Name this address",
               isPresented: $naming) {
            TextField("Name (e.g. Mom)", text: $draft)
            Button("Save") {
                guard let nudge else { return }
                AddressBook.shared.setName(draft, for: nudge.address)
                Task { @MainActor in await AddressKind.detect(nudge.address) }
                CounterpartyRetitle.applyCurrentName(for: nudge.address, in: modelContext)
                Task { await refresh() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It rides every future transfer with this address. Blank clears it.")
        }
        .sheet(item: $opened) { contact in
            ContactSheet(contact: contact)
                .dsReadSheet()
        }
    }

    private func refresh() async {
        contacts = ContactIndexSources.rebuild(context: modelContext)
        nudge = Self.newestUnnamed(context: modelContext)
        let next = ContactSuggest.next(in: ContactLinksStore.shared.ledger,
                                       known: { ContactIndexSources.contact(forKey: $0) != nil })
        if next?.pairKey != suggestion?.pairKey { verdict = nil }
        suggestion = next
        guard let next, verdict == nil,
              let a = ContactIndexSources.contact(forKey: next.a),
              let b = ContactIndexSources.contact(forKey: next.b) else { return }
        // The model's sentence, on the phone, from public words only (§916
        // section 3): the names and the handles, never a number or a mailbox.
        // Names and human handles only — a Nostr key or a hex address is
        // noise to a language model (measured: it called one "a random
        // string"), and a mailbox is not public. Only a YES is drawn: a
        // model's doubt is not a fact the row can stand on (§632).
        let describe = { (c: Contact) in
            ([c.name] + c.identities
                .filter { [.farcaster, .bluesky, .github, .ens, .basename, .linea, .lens, .worldApp].contains($0.kind) }
                .map { ContactSheet.service($0.kind) + " " + $0.label })
                .joined(separator: ", ")
        }
        if let answer = await ContactVerdictModel.judge(describe(a), describe(b)), answer.samePerson {
            verdict = answer.because
        }
    }

    // MARK: - The suggestion

    /// "Same person?" — the two names, the model's line when it has one, and
    /// the two answers as rows (§746). Yes is a verified edge you made; No is
    /// remembered forever for the pair.
    private func suggestionRow(_ link: ContactLink, a: Contact, b: Contact) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            // Each side says WHERE it is ("Nils on Bluesky and Nils on
            // Nostr"): two bare names were the same word twice.
            Text("Same person? \(Self.where(a, link)) and \(Self.where(b, link))")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, DS.Space.s4)
            if let verdict {
                Text(verdict).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DS.Space.s4)
            }
            DSDoorRow(icon: "checkmark.circle", label: "Yes, same person") {
                ContactLinksStore.shared.confirm(link.a, link.b)
                Task { await refresh() }
            }
            DSDoorRow(icon: "xmark.circle", label: "No") {
                ContactLinksStore.shared.decline(link.a, link.b)
                Task { await refresh() }
            }
        }
    }

    /// "Nils on Bluesky" — the name and the service of the end the link names.
    private static func `where`(_ c: Contact, _ link: ContactLink) -> String {
        let end = c.identities.first { $0.key == link.a || $0.key == link.b } ?? c.lead
        return String(localized: "\(c.name) on \(ContactSheet.service(end.kind))")
    }

    // MARK: - The nudge

    /// "0xab…12 sent you 0.2 ETH. Name them?" — a door to the naming alert,
    /// and a No that moves on to the next (`AddressNudge.decline`). Never a
    /// counterparty the app can already name, never a flagged address
    /// (`AddressNudge.prompt`'s own guards, reused).
    private func nudgeRow(_ nudge: (address: String, title: String)) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            DSDoorRow(icon: "character.cursor.ibeam",
                      title: Text("Name \(WalletStore.shortAddress(nudge.address))?")) {
                draft = ""
                naming = true
            }
            Text(nudge.title)
                .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
                .padding(.leading, DS.Space.s4)
            DSDoorRow(icon: "xmark.circle", label: "Not now") {
                AddressNudge.decline(nudge.address)
                Task { await refresh() }
            }
        }
    }

    /// The newest landed transfer whose counterparty has no name and was not
    /// declined — the same guards the sheet's nudge keeps, walked newest-first
    /// over a bounded window.
    static func newestUnnamed(context: ModelContext) -> (address: String, title: String)? {
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" },
            sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 60
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard let hit = AddressNudge.prompt(for: thing, context: context) else { continue }
            return (hit.address, thing.title)
        }
        return nil
    }

    // MARK: - Scopes

    /// The dock's categories that hold at least one contact — plus All —
    /// A–Z, as the Accounts screen's strip orders them (user, 2026-09-25:
    /// "alphabetized like they are in the rest of the pages"). Fewer than
    /// three draws no strip.
    private var scopes: [AddressScope] {
        let held = Set(contacts.flatMap(\.categories))
        return [AddressScope(name: nil)]
            + BridgeCatalog.categories.map(\.name).filter { held.contains($0) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { AddressScope(name: $0) }
    }

    /// The rows on screen: the chip's category, then the query, folded over
    /// case and diacritics and matched against the name and every identity.
    private var shown: [Contact] {
        let needle = Self.fold(query)
        return contacts.filter { contact in
            if let name = scope.name, !contact.categories.contains(name) { return false }
            guard !needle.isEmpty else { return true }
            if Self.fold(contact.name).contains(needle) { return true }
            return contact.identities.contains {
                Self.fold($0.label).contains(needle) || Self.fold($0.body).contains(needle)
            }
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }

    // MARK: - The list (section 1: Recent, then Everyone alphabetical)

    private var list: some View {
        let recent = shown.filter { ($0.lastActedAt ?? .distantPast) > Date.now.addingTimeInterval(-30 * 86400) }
            .sorted { ($0.lastActedAt ?? .distantPast) > ($1.lastActedAt ?? .distantPast) }
        let everyone = shown.sorted { l, r in
            if l.isUnnamed != r.isUnnamed { return !l.isUnnamed }
            return l.name.localizedStandardCompare(r.name) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: DS.Space.s6) {
            if !recent.isEmpty {
                group(Text("Recent"), rows: recent)
            }
            group(recent.isEmpty ? nil : Text("Everyone"), rows: everyone)
        }
    }

    private func group(_ name: Text?, rows: [Contact]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let name {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    name.dsText(.heading17).foregroundStyle(DS.textPrimary)
                    Text(rows.count.formatted())
                        .dsText(.subhead12).monospacedDigit().foregroundStyle(DS.textTertiary)
                    Spacer(minLength: 0)
                }
            }
            LazyVStack(spacing: DS.Space.s1) {
                ForEach(rows) { contact in row(contact) }
            }
        }
    }

    private func row(_ contact: Contact) -> some View {
        Button {
            opened = contact
        } label: {
            HStack(spacing: DS.Space.s3) {
                ContactFace(contact: contact, size: DS.Mark.tile)
                // The face and the name, nothing under it (user, 2026-09-25:
                // "why is a second line necessary under each name") — the
                // sheet says every address the contact carries.
                Text(contact.name)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                DSPushRowTrail()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .dsListRow()
    }
}

/// nil is All; otherwise a `BridgeCatalog.categories` name. The Accounts
/// screen's `CatalogScope`, one type over, for the same reasons it gives.
struct AddressScope: DSTileScope {
    let name: String?
    var id: String { name ?? "\u{1}all" }
    var label: String { name ?? String(localized: "All") }
    var glyph: String { CategoryFold.glyph(for: name ?? "All") }
    var summary: String { name ?? String(localized: "Everyone") }
}

extension Contact {
    /// The dock categories this contact stands in — one per identity kind.
    var categories: [String] {
        var out: [String] = []
        for identity in identities {
            let category: String
            switch identity.kind {
            case .wallet, .ens, .basename, .linea, .lens, .worldApp: category = "Wallet"
            case .farcaster, .bluesky, .nostr:                      category = "Social"
            case .github:                                            category = "Work"
            case .contact, .email:                                   category = "Life"
            case .feed:                                              category = "Reading"
            }
            if !out.contains(category) { out.append(category) }
        }
        return out
    }
}

/// The contact's face: the avatar a seat holds, the wallet's identicon, or
/// the monogram — `AddressMark`'s own rules, through a synthesized book entry
/// so every face in the app is drawn by one view.
struct ContactFace: View {
    let contact: Contact
    var size: CGFloat = DS.Face.list

    var body: some View {
        AddressMark(entry: entry, size: size)
    }

    private var entry: AddressBook.Entry {
        var kind: AddressBook.Kind
        switch contact.lead.kind {
        case .wallet, .ens, .basename, .linea, .lens, .worldApp:
            switch contact.kind {
            case .contract:     kind = .contract
            case .safe:         kind = .safe
            case .smartAccount: kind = .smartAccount
            case .key:          kind = .key
            default:            kind = .wallet
            }
        case .contact: kind = .contact
        default:       kind = .social
        }
        let wallet = contact.identities.first { $0.kind == .wallet }?.body ?? contact.lead.body
        var entry = AddressBook.Entry(address: wallet, name: contact.name, addedAt: .now, kind: kind)
        entry.avatarURL = contact.avatar
        return entry
    }
}

// MARK: - The sheet (section 1: identities as doors)

/// One contact: face, name, then every address as a row
/// with no section word above them (user, 2026-09-25) — each a door where the
/// app has one (the address card, the person's room, a profile page, a feed),
/// each line saying HOW the app knows it: verified, you confirmed, from their
/// contact card. "With you" (the things across the corpus) is the next pass.
struct ContactSheet: View {
    let contact: Contact
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var pushed: Door?
    /// "With you" (section 1): the things across the corpus that involve
    /// this contact — VALUE snapshots, never a held `[Thing]` (the liveness
    /// class in CLAUDE.md); a tap refetches by id.
    @State private var withYou: [WithYouRow] = []
    @State private var openedThing: Thing?

    struct WithYouRow: Identifiable, Equatable {
        let id: UUID
        let title: String
        let source: String
        let when: Date
    }

    /// The social accounts this contact stands for that the app WATCHES —
    /// the pairs their own stores know them by (`SocialUnfollow`'s shape).
    private var watchedSocial: [(source: String, handle: String)] {
        // Compared against each store's own spelling, folded — not through
        // `SocialPeople.isWatched`, whose Bluesky arm normalizes a bare
        // handle to its full domain and so missed "nils" (measured).
        contact.identities.compactMap { identity in
            let body = identity.body
            switch identity.kind {
            case .farcaster:
                guard let a = FarcasterStore.shared.accounts.first(where: { $0.username.lowercased() == body }) else { return nil }
                return ("Farcaster", a.username)
            case .bluesky:
                guard let a = BlueskyStore.shared.accounts.first(where: { $0.handle.lowercased() == body }) else { return nil }
                return ("Bluesky", a.handle)
            case .nostr:
                guard let a = NostrStore.shared.accounts.first(where: { $0.pubkeyHex.lowercased() == body }) else { return nil }
                return ("Nostr", a.input)
            default:
                return nil
            }
        }
    }

    /// The key this contact was saved under, when the person saved it.
    private var savedKey: String? {
        contact.identities.map(\.key).first { ContactBook.shared.has($0) }
    }

    private enum Door: Identifiable, Hashable {
        case address(AddressBook.Entry)
        case profile(SocialProfile)
        var id: String {
            switch self {
            case .address(let e): return "address:\(e.address)"
            case .profile(let p): return "profile:\(p.id)"
            }
        }
        // A book entry is Equatable, not Hashable; the id is the identity.
        static func == (l: Door, r: Door) -> Bool { l.id == r.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    VStack(spacing: DS.Space.s3) {
                        ContactFace(contact: contact, size: DS.Face.profile)
                        Text(contact.name)
                            .dsText(.heading24)
                            .foregroundStyle(DS.textPrimary)
                            .multilineTextAlignment(.center)
                        // No kind word under the name (user, 2026-09-25: "what
                        // does that even mean … his smart account presumably is
                        // in the list as wallet"): the kind shapes the face and
                        // the wallet row's own card says what the address is.
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s6)

                    // No section word (user, 2026-09-25: "you can't say
                    // 'identities' … doesn't even need a section descriptor"):
                    // the rows are the addresses, under the name.
                    VStack(spacing: DS.Space.s1) {
                        ForEach(contact.identities, id: \.key) { identity in
                            identityRow(identity)
                        }
                    }
                    if !withYou.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("With you").dsText(.heading17).foregroundStyle(DS.textPrimary)
                            VStack(spacing: DS.Space.s1) {
                                ForEach(withYou) { row in withYouRow(row) }
                            }
                        }
                    }
                    // UNFOLLOW, from the sheet (user, 2026-09-25: "we need the
                    // unfollow doors"). A starter pack's people are rows here
                    // like anyone you watch, and §511's rule holds: the row IS
                    // the watch, so it must carry the verb that ends it. One
                    // door per watched social account; nothing for a card, a
                    // wallet (its own page unwatches) or a name.
                    let followed = watchedSocial
                    if !followed.isEmpty {
                        VStack(spacing: DS.Space.s1) {
                            ForEach(followed, id: \.handle) { pair in
                                DSDoorRow(icon: "person.badge.minus",
                                          title: Text("Unfollow @\(pair.handle) on \(pair.source)"),
                                          role: .destructive) {
                                    SocialUnfollow.perform([pair], name: contact.name,
                                                           context: modelContext, chrome: chrome)
                                    dismiss()
                                }
                            }
                        }
                    }
                    // A contact YOU saved can be un-saved here; a seat-fed one
                    // is removed on its seat's page (§690), so no row is drawn.
                    if let saved = savedKey {
                        DSDoorRow(icon: "minus.circle", label: "Remove from Addresses", role: .destructive) {
                            ContactBook.shared.remove(saved)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
            }
            .dsPageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { withYou = Self.things(for: contact, context: modelContext) }
            .sheet(item: $openedThing) { thing in ThingSheetView(thing: thing) }
            .navigationDestination(item: $pushed) { door in
                switch door {
                case .address(let entry): AddressCard(entry: entry)
                case .profile(let profile): SocialProfileCard(profile: profile)
                }
            }
        }
    }

    /// The row states the address and the service it is on; it is a button
    /// only where a door exists (§83), else a fact. It LEADS with the seat's
    /// mark, the dock's own chip (user, 2026-09-25: "icon tiles … like the
    /// source chips we have in our dock"), and carries no line at all: not
    /// "verified" (user: "that just becomes questionable what it really
    /// means" — the tier stays in the model, where it decides merging) and
    /// not the service's name ("redundant if we are using the icon").
    @ViewBuilder
    private func identityRow(_ identity: Identity) -> some View {
        // Every row COPIES its full value from a trailing glyph (user,
        // 2026-09-25: "we need to have a way for user to see full address or
        // copy it"), the address card's own shape — the copy is felt (§867)
        // and marks its glyph for a beat. A row with a door opens on tap; one
        // without copies on tap too, so nothing on it is dead (§83). No
        // subtitle (user: "even the name of the service is redundant if we
        // are using the icon"); the mark, at the DOCK's size
        // (`DockFolderRow.markSize`, `DS.Face.list`), says the service.
        let value = identity.kind == .contact ? contact.name : identity.body
        let title = Text(identity.kind == .contact ? contact.name : identity.label)
        let mark = BridgeIcon(name: Self.mark(identity), size: DS.Face.list, circular: true)
        HStack(spacing: DS.Space.s2) {
            if let act = door(for: identity) {
                Button(action: act) {
                    DSPushRowLabel(title: title, opens: true) { mark }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsHover()
            } else {
                Button { copy(value, key: identity.key) } label: {
                    DSPushRowLabel(title: title, opens: false) { mark }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsHover()
            }
            Button {
                copy(value, key: identity.key)
            } label: {
                Image(systemName: copied == identity.key ? "checkmark" : "doc.on.doc")
                    .dsGlyph(.subhead)
                    .foregroundStyle(copied == identity.key ? DS.confirm : DS.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsTapTarget()
            .accessibilityLabel(Text("Copy"))
        }
        .dsListRow()
    }

    @State private var copied: String?

    private func copy(_ value: String, key: String) {
        DSPasteboard.copy(value)
        DSHaptic.success()
        withAnimation(DS.Motion.standard) { copied = key }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copied == key { withAnimation(DS.Motion.standard) { copied = nil } }
        }
    }

    // MARK: - With you

    private func withYouRow(_ row: WithYouRow) -> some View {
        Button {
            let id = row.id
            let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })
            openedThing = (try? modelContext.fetch(descriptor))?.first
        } label: {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: row.source, size: DS.Face.list, circular: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(row.when.formatted(date: .abbreviated, time: .omitted))
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: DS.Space.s2)
                DSPushRowTrail()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .dsListRow()
    }

    /// Every thing whose `contact(for:)` would be this contact — one string
    /// predicate per identity (a `.contains` predicate traps, CLAUDE.md), the
    /// union sorted newest first and capped at 20.
    static func things(for contact: Contact, context: ModelContext) -> [WithYouRow] {
        var found: [UUID: WithYouRow] = [:]
        func take(_ descriptor: FetchDescriptor<Thing>) {
            var d = descriptor
            d.sortBy = [SortDescriptor(\Thing.capturedAt, order: .reverse)]
            d.fetchLimit = 40
            for thing in (try? context.fetch(d)) ?? [] {
                if thing.sourceRef?.hasPrefix("gh:notif:") == true { continue }
                found[thing.id] = WithYouRow(id: thing.id, title: thing.title,
                                             source: thing.source, when: thing.capturedAt)
            }
        }
        for identity in contact.identities {
            let body = identity.body
            switch identity.kind {
            case .wallet:
                take(FetchDescriptor(predicate: #Predicate { $0.counterpartyAddress == body }))
            case .email:
                take(FetchDescriptor(predicate: #Predicate { $0.authorEmail == body }))
            case .farcaster:
                take(FetchDescriptor(predicate: #Predicate { $0.authorHandle == body && $0.source == "Farcaster" }))
            case .bluesky:
                take(FetchDescriptor(predicate: #Predicate { $0.authorHandle == body && $0.source == "Bluesky" }))
            case .nostr:
                take(FetchDescriptor(predicate: #Predicate { $0.authorHandle == body && $0.source == "Nostr" }))
            case .github:
                take(FetchDescriptor(predicate: #Predicate { $0.authorHandle == body && $0.source == "GitHub" }))
            case .contact, .ens, .basename, .linea, .lens, .worldApp, .feed:
                continue
            }
        }
        return found.values.sorted { $0.when > $1.when }.prefix(20).map { $0 }
    }

    private func door(for identity: Identity) -> (() -> Void)? {
        switch identity.kind {
        case .wallet:
            let entry = AddressBook.shared.entry(for: identity.body)
                ?? AddressBook.Entry(address: identity.body, name: contact.name, addedAt: .now)
            return { pushed = .address(entry) }
        case .farcaster, .bluesky, .nostr:
            let source: String
            switch identity.kind {
            case .farcaster: source = "Farcaster"
            case .bluesky:   source = "Bluesky"
            default:         source = "Nostr"
            }
            let profile = SocialProfile(source: source, handle: identity.body,
                                        displayName: nil, bio: nil, avatarURL: contact.avatar)
            return { pushed = .profile(profile) }
        case .github:
            guard let url = URL(string: "https://github.com/\(identity.body)") else { return nil }
            return { openURL(url) }
        case .feed:
            guard let url = URL(string: identity.body) else { return nil }
            return { openURL(url) }
        case .email:
            guard let url = URL(string: "mailto:\(identity.body)") else { return nil }
            return { openURL(url) }
        case .contact, .ens, .basename, .linea, .lens, .worldApp:
            return nil
        }
    }

    /// The service an identity kind belongs to, as a word.
    static func service(_ kind: Identity.Kind) -> String {
        switch kind {
        case .contact:   return String(localized: "Contacts")
        case .email:     return String(localized: "Email")
        case .github:    return String(localized: "GitHub")
        case .wallet:    return String(localized: "Wallet")
        case .ens:       return String(localized: "ENS")
        case .basename:  return String(localized: "Base")
        case .linea:     return String(localized: "Linea")
        case .farcaster: return String(localized: "Farcaster")
        case .lens:      return String(localized: "Lens")
        case .bluesky:   return String(localized: "Bluesky")
        case .nostr:     return String(localized: "Nostr")
        case .worldApp:  return String(localized: "World App")
        case .feed:      return String(localized: "Feed")
        }
    }

    /// The seat whose mark the row wears — the name `BridgeIcon` resolves,
    /// exactly as a dock chip does. A kind with no seat of its own borrows the
    /// nearest mark: a Basename wears Base's, an email its provider's.
    static func mark(_ identity: Identity) -> String {
        switch identity.kind {
        case .contact:   return "Contacts"
        case .email:     return identity.body.hasSuffix("@gmail.com") ? "Gmail" : "iCloud Mail"
        case .github:    return "GitHub"
        case .wallet:    return "Wallet"
        case .ens:       return "ENS"
        case .basename:  return "Base Vibenet"
        case .linea:     return "Linea"
        case .farcaster: return "Farcaster"
        case .lens:      return "Lens"
        case .bluesky:   return "Bluesky"
        case .nostr:     return "Nostr"
        case .worldApp:  return "World App"
        case .feed:      return "RSS"
        }
    }
}
