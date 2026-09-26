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
/// **The row.** The face, the name, and ONE line under it: the newest thing
/// from or about them (`Contact.lastThing`, the corpus's own title), else
/// the addresses they carry — never a company or a role (user, 2026-09-25:
/// "don't add Company line that's meaningless"). The trailing slot is the
/// seat marks: no money (user, 2026-08-21), no counts (§345). A wallet
/// nobody has named carries `Name` there instead, so the group is the
/// nudge and the one nudge row above the list is gone.
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
    /// The wallet the naming alert is naming — a `Not named yet` row's own
    /// `Name`, or the resolver's bare address.
    @State private var namingAddress: String?
    /// What the search RESOLVED (2026-09-25): an address, a name or a handle
    /// typed or pasted that matches nobody here, asked of web3.bio and drawn
    /// as one row with its doors and the corpus's own history under it.
    @State private var resolved: Resolved?
    @State private var resolvedWithYou: [ContactSheet.WithYouRow] = []
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    /// The one "Same person?" the list may draw (section 3): the newest live
    /// suggestion whose two ends are both here, with the model's sentence
    /// under it when the phone can give one.
    @State private var suggestion: ContactLink?
    @State private var verdict: String?
    @State private var naming = false
    @State private var draft = ""
    /// The "Same person?" sheet's pair (the one row's door) — an ITEM, so a
    /// suggestion that clears between the tap and the present raises nothing
    /// rather than an empty sheet (review, 2026-09-25).
    @State private var asked: AskedPair?
    /// What the row body reads per contact, computed ONCE in `refresh()` so a
    /// row carries values and never walks its identities per render (§626).
    @State private var extras: [String: RowExtras] = [:]

    struct AskedPair: Identifiable {
        let link: ContactLink
        let a: Contact
        let b: Contact
        var id: String { link.pairKey }
    }

    struct RowExtras {
        let marks: [String]
        let arrival: TimeInterval?
        /// The row's line — computed once, never per render (§626).
        let line: String?
    }
    /// The wave this list stands on (`LeadCycle`'s rule): a contact whose
    /// saved `addedAt` is later than this AND fresh turns its face once. Set
    /// at the first refresh, so the book you open to is at rest and only a
    /// contact saved while you look cycles.
    @State private var waveAt: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if !query.isEmpty, let resolved {
                resolverBlock(resolved)
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
            } else if shown.isEmpty, resolved == nil {
                // A resolved row IS the answer to the query; "No match"
                // under it would say the opposite in the same frame.
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
        // The resolver, debounced behind the typing: one web3.bio ask per
        // settled query, only for a query SHAPED like an address, a name or
        // a handle, and only when nobody here already carries it.
        .task(id: query) {
            resolved = nil; resolvedWithYou = []
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.resolvable(q) else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard let hit = await Self.resolve(q), !Task.isCancelled,
                  !contacts.contains(where: { c in hit.keys.contains { c.has($0) } }) else { return }
            resolvedWithYou = ContactSheet.things(for: hit.contact, context: modelContext, limit: 3)
            resolved = hit
        }
        .alert("Name this address",
               isPresented: $naming) {
            TextField("Name (e.g. Mom)", text: $draft)
            Button("Save") {
                guard let address = namingAddress else { return }
                AddressBook.shared.setName(draft, for: address)
                Task { @MainActor in await AddressKind.detect(address) }
                CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
                resolved = nil
                Task { await refresh() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It rides every future transfer with this address. Blank clears it.")
        }
        .sheet(item: $opened) { contact in
            ContactSheet(contact: contact) { Task { await refresh() } }
                .dsReadSheet()
        }
        .sheet(item: $asked) { pair in
            SamePersonSheet(a: pair.a, b: pair.b, whereA: Self.where(pair.a, pair.link),
                            whereB: Self.where(pair.b, pair.link), verdict: verdict) {
                ContactLinksStore.shared.confirm(pair.link.a, pair.link.b)
                asked = nil
                Task { await refresh() }
            } no: {
                ContactLinksStore.shared.decline(pair.link.a, pair.link.b)
                asked = nil
                Task { await refresh() }
            }
            .dsReadSheet()
        }
    }

    private func refresh() async {
        if waveAt == nil { waveAt = Date.timeIntervalSinceReferenceDate }
        // You are not an address you deal with (`ContactIndexSources.isYours`):
        // Manage holds your accounts, and a sheet offering to unfollow
        // yourself is a dead verb.
        contacts = ContactIndexSources.rebuild(context: modelContext)
            .filter { !ContactIndexSources.isYours($0) }
        extras = Dictionary(uniqueKeysWithValues: contacts.map {
            ($0.id, RowExtras(marks: Self.marks(of: $0), arrival: Self.arrival(of: $0),
                              line: Self.line(of: $0)))
        })
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

    /// "Same person?" — ONE row in the list's own anatomy (the design pass,
    /// 2026-09-25): the two faces overlapped as the lead, the question as the
    /// title, where each end lives as the line. The tap opens
    /// `SamePersonSheet`, which holds the model's line and the two answers.
    /// It was four rows of doors before anybody appeared; now it is a row.
    private func suggestionRow(_ link: ContactLink, a: Contact, b: Contact) -> some View {
        Button {
            asked = AskedPair(link: link, a: a, b: b)
        } label: {
            HStack(spacing: DS.Space.s3) {
                PairFace(a: a, b: b)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Same person?")
                        .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text("\(Self.where(a, link)) · \(Self.where(b, link))")
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                DSPushRowTrail()
            }
            .frame(minHeight: Self.rowPitch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .dsListRow()
    }

    /// "Nils on Bluesky" — the name and the service of the end the link names.
    private static func `where`(_ c: Contact, _ link: ContactLink) -> String {
        let end = c.identities.first { $0.key == link.a || $0.key == link.b } ?? c.lead
        return String(localized: "\(c.name) on \(ContactSheet.service(end.kind))")
    }

    // MARK: - The resolver (2026-09-25)

    /// What a search resolved to when nobody here matched: the row the
    /// person would get by following or naming it, drawn BEFORE they do.
    struct Resolved: Equatable {
        let query: String
        /// Lowercased hex when the query is or resolves to an address.
        let address: String?
        let name: String
        let identities: [Identity]
        let avatar: String?

        /// Every key this answer stands for, so a contact carrying any of
        /// them suppresses the row.
        var keys: [String] { identities.map(\.key) }

        /// A value `ContactFace` and `ContactSheet.things` can read.
        var contact: Contact {
            Contact(id: identities.first?.key ?? query, name: name, kind: .person,
                    identities: identities, avatar: avatar, lastActedAt: nil,
                    lastThing: nil, keywords: [])
        }
        /// Whether the name is a real one or the address's own tail.
        var isNamed: Bool { !name.hasPrefix("…") }
    }

    /// A query worth asking about: a hex address, a dotted name with no
    /// spaces, or an `@handle`. A person's name is not — that is the
    /// filter's job, and web3.bio would 404 on it every keystroke.
    static func resolvable(_ q: String) -> Bool {
        if ENS.isHexAddress(q) { return true }
        guard !q.contains(" "), q.count >= 3 else { return false }
        if q.hasPrefix("@") { return q.count >= 2 }
        return q.contains(".") && !q.hasPrefix(".") && !q.hasSuffix(".")
    }

    /// One web3.bio ask (`Web3Bio.lookup`, cached per launch, demo-gated
    /// inside). An address answers even when web3.bio holds nothing for it:
    /// a pasted address is still a row to name or follow. A name or handle
    /// that web3.bio does not know answers nil — there is nothing honest
    /// to draw for it (§83).
    @MainActor
    static func resolve(_ q: String) async -> Resolved? {
        if ENS.isHexAddress(q) {
            let address = q.lowercased()
            let records = await Web3Bio.names(for: address)
            var identities = [Identity.make(.wallet, address)]
            identities += records.compactMap(identity(for:))
            let named = identities.first { $0.kind.isNameService }?.body
                ?? records.compactMap(\.displayName).first
            return Resolved(query: q, address: address, name: named ?? WalletStore.shortAddress(address),
                            identities: identities, avatar: records.compactMap(\.avatar).first)
        }
        let handle = q.hasPrefix("@") ? String(q.dropFirst()) : nil
        let asked = handle.map { "farcaster,\($0)" } ?? q
        guard case .records(let records) = await Web3Bio.lookup(asked), !records.isEmpty else { return nil }
        let address: String?
        if let handle {
            address = records.first { $0.platform == .farcaster && $0.identity.lowercased() == handle.lowercased() }?.address
        } else {
            address = Web3Bio.forwardAddress(records, for: q)
        }
        var identities: [Identity] = []
        if let address, ENS.isHexAddress(address) {
            identities.append(Identity.make(.wallet, address))
            identities += Web3Bio.names(records, ownedBy: address).compactMap(identity(for:))
        }
        let own = handle.map { Identity.make(.farcaster, $0) }
            ?? Identity.Kind.classify(primaryName: q).map { Identity.make($0, q) }
        if let own, !identities.contains(where: { $0.key == own.key }) { identities.append(own) }
        guard !identities.isEmpty else { return nil }
        return Resolved(query: q, address: address.flatMap { ENS.isHexAddress($0) ? $0.lowercased() : nil },
                        name: handle ?? q.lowercased(), identities: identities,
                        avatar: records.compactMap(\.avatar).first)
    }

    /// A web3.bio record as an identity, by platform.
    private static func identity(for record: Web3Bio.Record) -> Identity? {
        switch record.platform {
        case .ens:       return Identity.make(.ens, record.identity)
        case .basenames: return Identity.make(.basename, record.identity)
        case .linea:     return Identity.make(.linea, record.identity)
        case .farcaster: return Identity.make(.farcaster, record.identity)
        case .lens:      return Identity.make(.lens, record.identity)
        case .sns, .ethereum, .solana: return nil
        }
    }

    /// The resolved row: the face and the name in the list's own anatomy,
    /// with what web3.bio knows as its line; then its doors as rows (§746);
    /// then the newest things the corpus already holds with it.
    @ViewBuilder
    private func resolverBlock(_ hit: Resolved) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LetterHead(text: Text("Not in your addresses"), tone: DS.textTertiary)
            HStack(spacing: DS.Space.s3) {
                ContactFace(contact: hit.contact, size: DS.Face.list)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.name).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    if let line = Self.line(of: hit.contact) {
                        Text(line).dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                SeatMarks(names: Self.marks(of: hit.contact))
            }
            .frame(minHeight: Self.rowPitch)
            .dsListRow()
            VStack(spacing: 0) {
                if let address = hit.address {
                    DSDoorRow(icon: "eye", title: Text("Follow \(hit.name)")) { follow(hit, address: address) }
                }
                DSDoorRow(icon: "person.crop.circle.badge.plus", label: "Add to Addresses") { add(hit) }
            }
            if !resolvedWithYou.isEmpty {
                Text("With you").dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .padding(.top, DS.Space.s3)
                ForEach(resolvedWithYou) { row in
                    HStack(spacing: DS.Space.s3) {
                        BridgeIcon(name: row.source, size: DS.Face.row, circular: true)
                        Text(row.title).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(row.when.formatted(date: .abbreviated, time: .omitted))
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .dsListRow()
                }
            }
        }
    }

    /// Follow, from the search — the same choke point every door funnels
    /// through (`WalletStore.outcome(ofAdding:)`), worded as the Farcaster
    /// profile's door words it: the cap still NAMES the wallet (§170).
    private func follow(_ hit: Resolved, address: String) {
        let label = hit.isNamed ? hit.name : ""
        switch WalletStore.shared.outcome(ofAdding: address, label: label) {
        case .added:
            bridges.reconcileWalletSeats()
            chrome.flash(String(localized: "Following \(hit.name)."), tone: .success)
        case .limitReached:
            if hit.isNamed { AddressBook.shared.setName(hit.name, for: address, kind: .wallet) }
            chrome.flash(String(localized: "Following \(WalletStore.watchLimit) addresses already — saved \(hit.name) to Addresses instead."))
        case .alreadyWatching, .invalid:
            chrome.flash(String(localized: "Already following \(hit.name)."))
        }
        resolved = nil
        Task { await refresh() }
    }

    /// Add to Addresses (spec section 2.6): a named address lands in the
    /// wallet book under its name; a bare address asks for one; a handle
    /// with no address is saved by hand (`ContactBook`).
    private func add(_ hit: Resolved) {
        if let address = hit.address {
            guard hit.isNamed else {
                namingAddress = address; draft = ""; naming = true
                return
            }
            AddressBook.shared.setName(hit.name, for: address, kind: .wallet)
            Task { @MainActor in await AddressKind.detect(address) }
        } else if let own = hit.identities.first {
            ContactBook.shared.save(own, name: hit.name)
        }
        chrome.flash(String(localized: "Saved \(hit.name) to Addresses."), tone: .success)
        resolved = nil
        Task { await refresh() }
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
            if contact.identities.contains(where: {
                Self.fold($0.label).contains(needle) || Self.fold($0.body).contains(needle)
            }) { return true }
            // What no row draws but a search may hit: a card's company and
            // role, a wallet entry's note (2026-09-25).
            return contact.keywords.contains { Self.fold($0).contains(needle) }
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }

    /// One row's height: a 44pt target with 12pt of air, so 36pt faces stand
    /// 20pt apart (they were 6pt apart on 46pt rows — "overlapping").
    static let rowPitch: CGFloat = 56

    // MARK: - The list (section 1: Recent, then Everyone alphabetical)

    /// Recent, then everyone under LETTER headings (the design pass,
    /// 2026-09-25 — user: "the avatars seem like they are overlapping"): the
    /// rows are 56pt on a 36pt face, so the faces stand 20pt apart, and a
    /// letter says where you are the way Apple's own book does. Recent wears
    /// the day divider's hue because it names a time (§740); a letter does
    /// not, so it stays grey. No index bar (§752).
    ///
    /// The second pass (same day, user: "do all"): the heads PIN while their
    /// group scrolls (`pinnedViews`, no control), and each is a seam you feel
    /// (`LetterHead`). A search draws a FLAT list — no Recent, no letters —
    /// and a row that matched on an address rather than its name says which
    /// one under the name (`matchedLine`), the only time a second line is
    /// drawn at all.
    private var list: some View {
        let needle = Self.fold(query)
        let recent = shown.filter { ($0.lastActedAt ?? .distantPast) > Date.now.addingTimeInterval(-30 * 86400) }
            .sorted { ($0.lastActedAt ?? .distantPast) > ($1.lastActedAt ?? .distantPast) }
        let everyone = shown.sorted { l, r in
            if l.isUnnamed != r.isUnnamed { return !l.isUnnamed }
            return l.name.localizedStandardCompare(r.name) == .orderedAscending
        }
        return LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if !needle.isEmpty {
                ForEach(everyone) { contact in
                    row(contact, matched: Self.matchedLine(contact, needle: needle))
                }
            } else {
                if !recent.isEmpty {
                    Section {
                        ForEach(recent) { contact in row(contact) }
                    } header: {
                        LetterHead(text: Text("Recent"), tone: DS.brandInk)
                    }
                }
                ForEach(Self.lettered(everyone), id: \.letter) { section in
                    Section {
                        ForEach(section.rows) { contact in row(contact) }
                    } header: {
                        LetterHead(text: Self.title(for: section.letter), tone: DS.textTertiary)
                    }
                }
            }
        }
        // The wave the list stands on, for `faceCycle` (§901's rule, a
        // contact's saved date in place of a thing's arrival).
        .environment(\.feedWaveAt, waveAt)
        // The hand, for the letter seam (prd §866's discipline 1). The
        // Accounts screen's ScrollView does not run `minimizesChrome`, so
        // nothing else writes this flag here; cleared on the way out for the
        // reason `minimizesChrome` gives — a flag left true lets the next
        // screen's first seam tick with nothing on the glass.
        .onScrollPhaseChange { _, phase in
            FeedSeam.set(dragging: phase == .tracking || phase == .interacting)
        }
        .onDisappear { FeedSeam.set(dragging: false) }
    }

    /// The word a group wears: its letter, `#` for a digit or a symbol, and
    /// "Not named yet" for the wallets nobody has named (the design pass: a
    /// wall of identicons under a symbol read as junk; under a word it reads
    /// as what it is, a to-do — and "yet" says the row's own `Name` verb is
    /// the way out).
    static func title(for letter: String) -> Text {
        switch letter {
        case "…": Text("Not named yet")
        default:  Text(verbatim: letter)
        }
    }

    /// The letter a name files under: its first letter, folded; `#` for a
    /// digit or a symbol; `…` for an auto-name (`…44b1`), the group drawn as
    /// "Unnamed". Letters first, then `#`, then Unnamed — Apple's own order.
    static func lettered(_ rows: [Contact]) -> [(letter: String, rows: [Contact])] {
        var out: [(letter: String, rows: [Contact])] = []
        for contact in rows {
            let first = fold(contact.name).first
            let letter = contact.isUnnamed ? "…" : (first?.isLetter == true ? String(first!).uppercased() : "#")
            if let i = out.firstIndex(where: { $0.letter == letter }) { out[i].rows.append(contact) }
            else { out.append((letter, [contact])) }
        }
        let rank: (String) -> Int = { $0 == "…" ? 2 : ($0 == "#" ? 1 : 0) }
        return out.enumerated().sorted { l, r in
            let (rl, rr) = (rank(l.element.letter), rank(r.element.letter))
            return rl != rr ? rl < rr : l.offset < r.offset
        }.map(\.element)
    }

    /// While searching: the identity or keyword the query hit when the NAME
    /// did not — "why is this row here". Nil when the name itself matches,
    /// so a row found by name keeps its own line.
    static func matchedLine(_ contact: Contact, needle: String) -> String? {
        guard !needle.isEmpty, !fold(contact.name).contains(needle) else { return nil }
        if let hit = contact.identities.first(where: {
            fold($0.label).contains(needle) || fold($0.body).contains(needle)
        }) {
            return hit.kind == .contact ? nil : hit.label
        }
        return contact.keywords.first { fold($0).contains(needle) }
    }

    /// The row's line: the newest thing from or about them, else the
    /// addresses they carry that the name does not already say (never a
    /// card ref, never the name itself), at most three. Nil draws one line.
    static func line(of contact: Contact) -> String? {
        if let thing = contact.lastThing, !thing.isEmpty { return thing }
        // A Nostr key is 64 hex characters nobody reads; the mark already
        // says Nostr, so the line leaves it out.
        let labels = contact.identities
            .filter { $0.kind != .contact && $0.kind != .nostr
                   && fold($0.label) != fold(contact.name) && fold($0.body) != fold(contact.name) }
            .map(\.label)
        return labels.isEmpty ? nil : labels.prefix(3).joined(separator: " · ")
    }

    /// When this contact was SAVED by hand, in `LeadCycle`'s clock: a
    /// `ContactBook` entry (only the person writes that store), or a wallet
    /// book entry with NO provenance — a seat's own naming carries one
    /// (`setName(provenance:)`), and a seat's sweep is not you adding
    /// somebody. Nil for every seat-fed row, which never cycles.
    static func arrival(of contact: Contact) -> TimeInterval? {
        var latest: Date?
        for identity in contact.identities {
            if let saved = ContactBook.shared.entries[identity.key]?.addedAt {
                latest = max(latest ?? .distantPast, saved)
            } else if identity.kind == .wallet,
                      let entry = AddressBook.shared.entry(for: identity.body),
                      entry.provenance == nil {
                latest = max(latest ?? .distantPast, entry.addedAt)
            }
        }
        return latest?.timeIntervalSinceReferenceDate
    }

    private func row(_ contact: Contact, matched: String? = nil) -> some View {
        Button {
            opened = contact
        } label: {
            HStack(spacing: DS.Space.s3) {
                ContactFace(contact: contact, size: DS.Face.list)
                    // A contact you just saved turns its face to its dock
                    // category's glyph and back, once (§901's cycle, the
                    // Addresses caller — see `LeadCycle`).
                    .faceCycle(category: contact.categories.first,
                               arrival: extras[contact.id]?.arrival,
                               fact: contact.name, size: DS.Face.list)
                // The name, then ONE line: while searching, why the row is
                // here (`matchedLine`); otherwise the newest thing from or
                // about them, else the addresses they carry (`line(of:)`).
                // An auto-name (`…44b1`) is not a name, so it wears the
                // secondary ink — the line under it is the transfer that
                // brought it, which is the one fact worth naming it for.
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.name)
                        .dsText(.body17)
                        .foregroundStyle(contact.isUnnamed ? DS.textSecondary : DS.textPrimary)
                        .lineLimit(1)
                    if let line = matched ?? extras[contact.id]?.line {
                        Text(line)
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                if contact.isUnnamed, let address = contact.identities.first(where: { $0.kind == .wallet })?.body {
                    // The verb IS the row's trailing fact (§746's `init(verb:)`
                    // shape): every unnamed wallet carries its own `Name`, so
                    // the group is the nudge and no row above the list is.
                    Button {
                        namingAddress = address; draft = ""; naming = true
                    } label: {
                        Text("Name")
                            .dsText(.body17)
                            .foregroundStyle(DS.tint)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                } else {
                    // The seats this contact is on, as the dock's own marks —
                    // the sheet's icon tiles at a glance (the design pass). A
                    // fact, never a count or money (§345, user 2026-08-21).
                    SeatMarks(names: extras[contact.id]?.marks ?? [])
                }
            }
            .frame(minHeight: Self.rowPitch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .dsListRow()
    }

    /// The distinct seat marks a contact's identities wear, in identity
    /// precedence, at most three — `SeatMarks` draws them.
    static func marks(of contact: Contact) -> [String] {
        var out: [String] = []
        for identity in contact.identities {
            // An email the CARD stated is not a mail seat this person is on
            // — it is a fact on their card, and a Gmail mark on somebody who
            // never wrote to you would claim a seat they do not hold.
            if identity.kind == .email, identity.tier == .stated, identity.source == "contact.card" { continue }
            let mark = ContactSheet.mark(identity)
            if !out.contains(mark) { out.append(mark) }
            if out.count == SeatMarks.cap { break }
        }
        return out
    }
}

extension AddressesSection {
    /// The ground a pinned head and a mark's ring are cut from: the page's
    /// own colour — or NOTHING over a photo theme, where a flat band would be
    /// a plate on the person's picture (§782; review, 2026-09-25). A head
    /// over a photo pins transparent, and the rows show through it.
    static var ground: Color {
        ThemeStore.shared.backgroundPhoto == nil ? DS.page : .clear
    }
}

/// A group's head in the Addresses list: a word in `label12`, PINNED while
/// its rows scroll under it (Apple's own book), on the page's own ground so
/// the rows slide beneath it — the page, not a plate (§782).
///
/// **It is also felt.** Passing under the finger, a letter ticks once
/// through `FeedSeam` — the feed's day seam, with both of its disciplines
/// (finger down, never inside 300ms). §866 scoped the feel to a seam in
/// TIME because the feed's only axis is time; a directory's only axis is the
/// alphabet, so its letters are the same kind of fact about where you are.
private struct LetterHead: View {
    let text: Text
    let tone: Color
    @State private var tracker = FeedSeam.Tracker()

    var body: some View {
        text
            .dsText(.label12)
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s1)
            .background(AddressesSection.ground)
            .onGeometryChange(for: Int.self) { proxy in
                FeedSeam.side(ofTop: proxy.frame(in: .scrollView).minY)
            } action: { _, now in
                FeedSeam.observe(side: now, in: tracker)
            }
    }
}

/// Up to three seat marks, overlapped, each cut out of the next by the page's
/// own ground — a ring of ground, never a drawn line (no hairlines).
struct SeatMarks: View {
    let names: [String]
    static let cap = 3

    var body: some View {
        // `badge`: a mark beside inline text, not a portrait (the ramp's own tier).
        HStack(spacing: -6) {
            ForEach(names, id: \.self) { name in
                BridgeIcon(name: name, size: DS.Face.badge, circular: true)
                    .padding(2)
                    .background(Circle().fill(AddressesSection.ground))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(names.joined(separator: ", ")))
    }
}

/// Two faces overlapped in one 36pt lead — the "Same person?" row's lead.
private struct PairFace: View {
    let a: Contact
    let b: Contact

    var body: some View {
        // `badge` (20pt) on the 36pt seat: the two faces sit corner to corner
        // with a 4pt overlap, so both read as faces — at `row` the second
        // covered most of the first (measured on the sim, 2026-09-25).
        ZStack(alignment: .topLeading) {
            ContactFace(contact: a, size: DS.Face.badge)
            ContactFace(contact: b, size: DS.Face.badge)
                .padding(2)
                .background(Circle().fill(AddressesSection.ground))
                .offset(x: DS.Face.list - DS.Face.badge - 2, y: DS.Face.list - DS.Face.badge - 2)
        }
        .frame(width: DS.Face.list, height: DS.Face.list, alignment: .topLeading)
    }
}

/// The "Same person?" sheet: the two faces, where each lives, the model's
/// line when the phone gave one, and the two answers as rows (§746). Yes is
/// a verified edge you made; No is remembered forever for the pair.
private struct SamePersonSheet: View {
    let a: Contact
    let b: Contact
    let whereA: String
    let whereB: String
    let verdict: String?
    let yes: () -> Void
    let no: () -> Void

    var body: some View {
        // A ScrollView wearing the page ground, `ContactSheet`'s own shape: a
        // bare stack covered only itself, and the sheet's grey material showed
        // through beneath it (measured on the sim, 2026-09-25).
        ScrollView {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            HStack(spacing: DS.Space.s4) {
                ContactFace(contact: a, size: DS.Face.profile)
                ContactFace(contact: b, size: DS.Face.profile)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s6)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Same person?").dsText(.heading24).foregroundStyle(DS.textPrimary)
                // Each side says WHERE it is ("Nils on Bluesky and Nils on
                // Nostr"): two bare names were the same word twice.
                Text("\(whereA) and \(whereB)")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let verdict {
                    Text(verdict).dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: DS.Space.s1) {
                DSDoorRow(icon: "checkmark.circle", label: "Yes, same person", act: yes)
                DSDoorRow(icon: "xmark.circle", label: "No", act: no)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dsPageBackground()
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
    @Environment(\.modelContext) private var modelContext
    /// The card's own photo (`ContactsIngest.healPhotos` lands the Contacts
    /// thumbnail on the thing) — read for the row on screen, decoded off
    /// main, cached by card (2026-09-25). The book already held the one
    /// picture that tells people apart, and the list drew initials over it.
    @State private var photo: UIImage?

    var body: some View {
        face.background(photoTask)
    }

    @ViewBuilder private var face: some View {
        // A wallet keeps its identicon and a contract, Safe or key its
        // glyph (`AddressMark`'s rules); everybody else with no picture
        // wears their INITIALS in the ring — forty identical grey
        // silhouettes told nobody apart (the design pass, 2026-09-25;
        // §753's rule for a face with no picture).
        if let photo {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .transition(.opacity)
        } else if contact.avatar == nil, contact.lead.kind != .wallet,
           contact.kind == .person || contact.kind == .organization || contact.kind == .publication {
            Circle()
                .fill(DS.fillFaint)
                .frame(width: size, height: size)
                .overlay {
                    Text(Self.initials(contact.name))
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.textSecondary)
                }
        } else {
            AddressMark(entry: entry, size: size)
        }
    }

    /// The photo, for a contact led by a card: cached by card key, else one
    /// fetch by the card's own ref and a decode off the main thread. A row
    /// met by scrolling pays this once; a row with no card pays nothing.
    private var photoTask: some View {
        EmptyView().task(id: contact.id) {
            guard contact.lead.kind == .contact else { return }
            let key = contact.lead.key
            if let hit = Self.photos.object(forKey: key as NSString) { photo = hit; return }
            guard let ref = ContactIndexSources.cardRef(forKey: key) else { return }
            var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref && $0.source == "Contacts" })
            d.fetchLimit = 1
            guard let data = (try? modelContext.fetch(d))?.first?.previewImageData, !data.isEmpty else { return }
            let decoded = await Task.detached(priority: .utility) { UIImage(data: data)?.preparingForDisplay() }.value
            guard let decoded, !Task.isCancelled else { return }
            Self.photos.setObject(decoded, forKey: key as NSString)
            withAnimation(DS.Motion.standard) { photo = decoded }
        }
    }
    private static let photos = NSCache<NSString, UIImage>()

    /// Up to two initials: the first letters of the first two words, or
    /// the first letter alone for a handle or a one-word name.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = words.compactMap { $0.first(where: \.isLetter) }.map { String($0).uppercased() }
        return letters.isEmpty ? "#" : letters.joined()
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
    /// Called after a change this sheet made (a rename, an unfollow) so the
    /// list behind it rebuilds; the sheet dismisses itself on those.
    var onChanged: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var pushed: Door?
    /// "With you" (section 1): the things across the corpus that involve
    /// this contact — VALUE snapshots, never a held `[Thing]` (the liveness
    /// class in CLAUDE.md); a tap refetches by id.
    @State private var withYou: [WithYouRow] = []
    /// How many "With you" rows are asked for; `Show older` raises it.
    @State private var withYouLimit = 20
    @State private var openedThing: Thing?
    /// The card's reachable facts (a phone, a mailbox) for the dial — read
    /// off the Contacts thing in `.task`, never in the body (§628).
    @State private var cardPhone: String?
    @State private var cardEmail: String?
    @State private var composer: Composer?
    @State private var renaming = false
    @State private var draft = ""
    /// The wallets World ID's address book marks verified (prd §785): read
    /// on open, at most three, drawn as the wallet row's fact. Lapsed and
    /// absent draw nothing here — the card says the date.
    @State private var verifiedHumans: Set<String> = []

    private enum Composer: String, Identifiable {
        case messages, mail
        var id: String { rawValue }
    }

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
                        // Enters at the row's size and grows to its own —
                        // `AddressReveal`'s hero, for its stated reason: the
                        // zoom transition is out for sheets (§232), and a
                        // scale is the part of the flight that can be claimed
                        // honestly from here.
                        ContactFace(contact: contact, size: DS.Face.profile)
                            .addressHeroArrival(size: DS.Face.profile)
                        Text(contact.name)
                            .dsText(.heading24)
                            .foregroundStyle(DS.textPrimary)
                            .multilineTextAlignment(.center)
                        // No kind word under the name (user, 2026-09-25: "what
                        // does that even mean … his smart account presumably is
                        // in the list as wallet"): the kind shapes the face and
                        // the wallet row's own card says what the address is.
                        // No company or role either (user, same day: "that's
                        // meaningless") — they are searched, never drawn.
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s6)

                    // The dial (2026-09-25): how to REACH them, as the thing
                    // sheet's own discs — Messages and Mail through the
                    // system composers (the one sanctioned write, the person
                    // taps Send), Copy where they have exactly one address.
                    // Drawn only where a disc can act (§83): no phone, no
                    // Message; the simulator has no Messages at all.
                    if !dial.isEmpty {
                        HStack(alignment: .top, spacing: DS.Space.s4 + 2) {
                            ForEach(dial, id: \.label) { disc in
                                Button(action: disc.act) {
                                    VStack(spacing: DS.Space.s2 - 2) {
                                        Circle()
                                            .fill(DS.fillLine)
                                            .frame(width: 52, height: 52)
                                            .overlay {
                                                Image(systemName: copied == disc.label ? "checkmark" : disc.icon)
                                                    .dsGlyph(.body, weight: .regular)
                                                    .foregroundStyle(DS.textPrimary)
                                                    .dsSymbolSwap(copied == disc.label ? "checkmark" : disc.icon)
                                            }
                                        Text(disc.label)
                                            .dsText(.label12)
                                            .foregroundStyle(DS.textTertiary)
                                    }
                                }
                                .buttonStyle(PressSpring())
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // No section word (user, 2026-09-25: "you can't say
                    // 'identities' … doesn't even need a section descriptor"):
                    // the rows are the addresses, under the name.
                    VStack(spacing: 0) {
                        ForEach(contact.identities, id: \.key) { identity in
                            identityRow(identity)
                        }
                    }
                    if !withYou.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("With you").dsText(.heading17).foregroundStyle(DS.textPrimary)
                            VStack(spacing: 0) {
                                ForEach(withYou) { row in withYouRow(row) }
                                // The door the spec named and the first pass
                                // left out: a full list stops at its cap and
                                // says so, never silently (§83).
                                if withYou.count >= withYouLimit {
                                    DSDoorRow(icon: "clock.arrow.circlepath", label: "Show older") {
                                        withYouLimit += 80
                                        withYou = Self.things(for: contact, context: modelContext, limit: withYouLimit)
                                    }
                                }
                            }
                        }
                    }
                    // RENAME (2026-09-25) — the one verb the sheet lacked. A
                    // wallet's name goes in the wallet book and retitles its
                    // transfers; anything else the person names is a
                    // `ContactBook` save. A card's name is Apple's to change,
                    // so a card-led contact draws no row (§83).
                    if contact.lead.kind != .contact {
                        DSDoorRow(icon: "character.cursor.ibeam", label: "Rename") {
                            draft = contact.isUnnamed ? "" : contact.name
                            renaming = true
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
                                    onChanged?()
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
                            onChanged?()
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
            }
            .dsPageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                withYou = Self.things(for: contact, context: modelContext, limit: withYouLimit)
                if let ref = ContactIndexSources.cardRef(forKey: contact.lead.key) {
                    let facts = Self.cardFacts(ref: ref, context: modelContext)
                    cardPhone = facts.phone; cardEmail = facts.email
                }
                // World ID, read on open for the wallets here (the card's
                // own `fill`), bounded so a Safe with many keys costs three.
                for identity in contact.identities.filter({ $0.kind == .wallet }).prefix(3) {
                    _ = await WorldIDSource.shared.fill(identity.body)
                    if case .verified = WorldIDSource.shared.status(for: identity.body) {
                        verifiedHumans.insert(identity.body)
                    }
                }
            }
            .sheet(item: $openedThing) { thing in ThingSheetView(thing: thing) }
            .sheet(item: $composer) { which in
                switch which {
                case .messages:
                    TextComposer(body: "", attachment: nil, attachmentName: "",
                                 recipients: cardPhone.map { [$0] } ?? [])
                case .mail:
                    MailComposer(subject: "", body: "", attachment: nil, attachmentName: "",
                                 recipients: mailAddress.map { [$0] } ?? [])
                }
            }
            .alert(contact.isUnnamed ? "Name this address" : "Rename", isPresented: $renaming) {
                TextField("Name", text: $draft)
                Button("Save") { rename(draft) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if contact.lead.kind == .wallet {
                    Text("It rides every future transfer with this address. Blank clears it.")
                } else {
                    Text("Blank clears it.")
                }
            }
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
        // The one fact a wallet row may trail: World ID's own book says a
        // verified human holds it (prd §785 — only `verified` draws here;
        // a zero is never "not a person").
        let fact: Text? = identity.kind == .wallet && verifiedHumans.contains(identity.body)
            ? Text("Verified human") : nil
        HStack(spacing: DS.Space.s2) {
            if let act = door(for: identity) {
                Button(action: act) {
                    DSPushRowLabel(title: title, fact: fact, opens: true) { mark }.contentShape(Rectangle())
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
        .frame(minHeight: AddressesSection.rowPitch)
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

    // MARK: - The dial, and Rename

    private struct Disc {
        let icon: String
        let label: String
        let act: () -> Void
    }

    /// The mailbox a Mail disc addresses: the card's, else a mail identity.
    private var mailAddress: String? {
        cardEmail ?? contact.identities.first { $0.kind == .email }?.body
    }

    private var dial: [Disc] {
        var out: [Disc] = []
        if MessageCompose.canText, cardPhone != nil {
            out.append(Disc(icon: "message", label: String(localized: "Message")) { composer = .messages })
        }
        if MessageCompose.canMail, mailAddress != nil {
            out.append(Disc(icon: "envelope", label: String(localized: "Mail")) { composer = .mail })
        }
        let wallets = contact.identities.filter { $0.kind == .wallet }
        if wallets.count == 1, let one = wallets.first {
            out.append(Disc(icon: "doc.on.doc", label: String(localized: "Copy")) {
                copy(one.body, key: String(localized: "Copy"))
            })
        }
        return out
    }

    /// The card's first phone and mailbox, off its facts — one fetch by the
    /// card's own ref, read in `.task`.
    static func cardFacts(ref: String, context: ModelContext) -> (phone: String?, email: String?) {
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref && $0.source == "Contacts" })
        d.fetchLimit = 1
        guard let thing = (try? context.fetch(d))?.first else { return (nil, nil) }
        let facts = thing.facts.compactMap(ThingFact.init(encoded:))
        return (facts.first { $0.action == .call }?.value, facts.first { $0.action == .mail }?.value)
    }

    private func rename(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch contact.lead.kind {
        case .wallet:
            let address = contact.lead.body
            AddressBook.shared.setName(name, for: address)
            Task { @MainActor in await AddressKind.detect(address) }
            CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
        case .contact:
            return
        default:
            ContactBook.shared.save(contact.lead, name: name)
        }
        onChanged?()
        dismiss()
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
            .frame(minHeight: AddressesSection.rowPitch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
        .dsListRow()
    }

    /// Every thing whose `contact(for:)` would be this contact — one string
    /// predicate per identity (a `.contains` predicate traps, CLAUDE.md), the
    /// union sorted newest first and capped at 20.
    static func things(for contact: Contact, context: ModelContext, limit: Int = 20) -> [WithYouRow] {
        var found: [UUID: WithYouRow] = [:]
        func take(_ descriptor: FetchDescriptor<Thing>) {
            var d = descriptor
            d.sortBy = [SortDescriptor(\Thing.capturedAt, order: .reverse)]
            d.fetchLimit = limit * 2
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
        return found.values.sorted { $0.when > $1.when }.prefix(limit).map { $0 }
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
