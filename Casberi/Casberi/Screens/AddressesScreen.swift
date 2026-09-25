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
/// **The row.** The face, the name on one line, and a line naming every
/// identity the contact carries (`@jesse · jesse.base.eth`). The trailing
/// slot is EMPTY: no money (user, 2026-08-21), no counts (§345).
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
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
        .task { contacts = ContactIndexSources.rebuild(context: modelContext) }
        .sheet(item: $opened) { contact in
            ContactSheet(contact: contact)
                .dsReadSheet()
        }
    }

    // MARK: - Scopes

    /// The dock's categories, in catalog order, that hold at least one
    /// contact — plus All. Fewer than three draws no strip.
    private var scopes: [AddressScope] {
        let held = Set(contacts.flatMap(\.categories))
        return [AddressScope(name: nil)]
            + BridgeCatalog.categories.map(\.name).filter { held.contains($0) }.map { AddressScope(name: $0) }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(contact.line)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
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

    /// The row's line: every identity but the one the name already says,
    /// in precedence order. A contact card's identifier is never drawn (it
    /// is a device-local id, not a fact about the person), and a contact
    /// with nothing else to say names its service — "Contacts", "Wallet".
    var line: String {
        let labels = identities
            .filter { $0.kind != .contact }
            .map(\.label)
            .filter { $0 != name }
        if labels.isEmpty { return ContactSheet.service(lead.kind) }
        return labels.joined(separator: " · ")
    }

    /// An auto-named wallet (`…44b1`) sorts after every real name.
    var isUnnamed: Bool { name.hasPrefix("…") }

    /// The kind's word, drawn under the name on the sheet. A person is the
    /// ordinary case and says nothing.
    var kindWord: String? {
        switch kind {
        case .person:       return nil
        case .organization: return String(localized: "Organization")
        case .contract:     return String(localized: "Contract")
        case .safe:         return String(localized: "Safe")
        case .smartAccount: return String(localized: "Smart account")
        case .key:          return String(localized: "Key")
        case .publication:  return String(localized: "Publication")
        }
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

/// One contact: face, name, the kind's word, then every identity as a row —
/// each a door where the app has one (the address card, the person's room,
/// a profile page, a feed), each line saying HOW the app knows it: verified,
/// you confirmed, from their contact card. "With you" (the things across the
/// corpus) is the next pass.
struct ContactSheet: View {
    let contact: Contact
    @Environment(\.openURL) private var openURL
    @State private var pushed: Door?

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
                        if let word = contact.kindWord {
                            Text(word).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s6)

                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("Identities").dsText(.heading24).foregroundStyle(DS.textPrimary)
                        VStack(spacing: DS.Space.s1) {
                            ForEach(contact.identities, id: \.key) { identity in
                                identityRow(identity)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
            }
            .dsPageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $pushed) { door in
                switch door {
                case .address(let entry): AddressCard(entry: entry)
                case .profile(let profile): SocialProfileCard(profile: profile)
                }
            }
        }
    }

    /// The row states the identity and how it is known; it is a button only
    /// where a door exists (§83), else a fact.
    @ViewBuilder
    private func identityRow(_ identity: Identity) -> some View {
        let label = DSPushRowLabel(title: Text(identity.kind == .contact ? contact.name : identity.label),
                                   subtitle: Text(Self.how(identity)),
                                   opens: door(for: identity) != nil) {
            Image(systemName: Self.glyph(identity.kind))
                .dsGlyph(.subhead)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 38, height: 38)
                .background(DS.fillFaint, in: Circle())
        }
        if let act = door(for: identity) {
            Button(action: act) { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
                .dsListRow()
        } else {
            label.dsListRow()
        }
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

    /// The line under an identity: the service, then how it joined.
    static func how(_ identity: Identity) -> String {
        let service = Self.service(identity.kind)
        switch (identity.tier, identity.source) {
        case (.verified?, "you"): return service + " · " + String(localized: "you confirmed")
        case (.verified?, _):     return service + " · " + String(localized: "verified")
        case (.stated?, _):       return service + " · " + String(localized: "from their contact card")
        default:                  return service
        }
    }

    static func glyph(_ kind: Identity.Kind) -> String {
        switch kind {
        case .contact:  return "person.crop.circle"
        case .email:    return "envelope"
        case .github:   return "chevron.left.forwardslash.chevron.right"
        case .wallet:   return "cube"
        case .feed:     return "dot.radiowaves.up.forward"
        case .ens, .basename, .linea, .lens, .farcaster, .bluesky, .nostr, .worldApp: return "at"
        }
    }
}
