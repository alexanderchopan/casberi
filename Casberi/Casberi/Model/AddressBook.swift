import Foundation
import Observation

/// The named-address ledger (prd §169, 2026-07-21) — one book for every
/// on-chain address the person has put a name to, whether or not its activity
/// is watched.
///
/// **Why one store.** Names lived in two places that never met: `WalletStore`
/// held the labels of WATCHED wallets, and `CounterpartyLabels` held names for
/// addresses met in your own activity. Name "Mom" on a transfer, later watch
/// that address, and the name didn't carry; unwatch a wallet and its name was
/// destroyed with its cursors. A name the person typed is their data, not
/// bookkeeping, so it now lives in exactly one place and outlives every watch.
///
/// **Membership: the copy test.** An entry is an on-chain address — something
/// you'd copy to send value or look up on a block explorer. Personal wallets,
/// your own accounts, contracts, Safes, exchange deposit addresses; EVM hex and
/// Solana base58 alike. Emails and phone numbers fail that test and belong to
/// the phone's own address book, not this one (ruling: crypto-only, so the list
/// stays scannable at fifty rows and honest at every one).
///
/// **Naming is free; watching is the upgrade.** An entry costs nothing on the
/// wire and lands nothing in the corpus — it just makes every transfer with
/// that address read in the person's own words (`WalletIngest.counterpartyNames`
/// consults the book first). Watching, which starts the ingest pipelines, is a
/// separate deliberate act with its own cap (`WalletStore.watchLimit`).
@Observable
final class AddressBook {
    static let shared = AddressBook()
    private static let key = "wallet.addressBook.v1"
    private static let migratedKey = "wallet.addressBook.migrated.v1"
    private static let kindRecheckKey = "wallet.addressBook.kindRecheck.7702"

    /// What the app learned an address IS — detected, never asked (prd §169).
    /// The person supplies a name; the chain supplies the kind. `unknown` is
    /// the honest resting state: nothing has looked yet, and a row that hasn't
    /// been checked never claims to be a plain wallet.
    enum Kind: String, Codable {
        case unknown, wallet, contract, safe
        /// An ERC-4337 / ERC-7579 smart account (2026-08-03, prd §294).
        ///
        /// It has bytecode, so every read in this app called it a `contract` —
        /// which is true the way "a house is a building" is true, and just as
        /// unhelpful when the house is yours. Someone watching their own
        /// Coinbase Smart Wallet or Biconomy account saw the row labelled
        /// "Contract" wearing the machinery mark.
        ///
        /// This is the EXACT complaint the 7702 fix answered on 2026-07-25,
        /// one mechanism over: a delegated EOA was reading as a contract and
        /// losing its face. That fix is why `hasCode` skips a `0xef0100`
        /// prefix; this is the same ruling applied to accounts whose code is
        /// real.
        case smartAccount

        /// The mark's glyph. Only a WALLET is a "who" — it wears the round
        /// identicon face; everything else gets a square mark, so a book of
        /// fifty rows separates people from machinery without any grouping UI.
        ///
        /// A SMART ACCOUNT is a who. That's the whole point of the kind: it's
        /// somebody's wallet that happens to be made of code, and taking its
        /// face away to file it with routers and token contracts is the
        /// mislabelling this case exists to undo. It keeps the face and says
        /// what it is in the label instead.
        var glyph: String? {
            switch self {
            case .contract: return "curlybraces"
            case .safe:     return "shield.lefthalf.filled"
            case .wallet, .unknown, .smartAccount: return nil
            }
        }

        var label: String? {
            switch self {
            case .contract:     return String(localized: "Contract")
            case .safe:         return String(localized: "Safe")
            case .smartAccount: return String(localized: "Smart account")
            case .wallet, .unknown: return nil
            }
        }
    }

    struct Entry: Codable, Identifiable, Equatable {
        /// The address itself — as it was added, except that a NAME is stored
        /// as the address it resolves to (`AddressBook.resolvedForm`), because
        /// a name is a label, not an identity, and two spellings of one wallet
        /// are one entry. Solana's case is preserved; it IS identity. The
        /// person's own spelling lives on in `name`.
        var address: String
        var name: String
        var addedAt: Date
        var kind: Kind = .unknown
        /// Where this entry came from, when we knew at the moment of adding —
        /// "Farcaster · @jesse" for the verified-address door (prd §169). A
        /// pointer captured from a link the app already verified, never an
        /// identity GUESSED across sources: a wrong link silently retitles
        /// history with the wrong name, which the person can't see or correct.
        var provenance: String? = nil
        /// The groups this address is in (2026-08-01) — a portfolio, a family,
        /// a set of work wallets. Stored ON the entry rather than in a store of
        /// its own precisely because `reconcileAliases` RE-KEYS entries when a
        /// name resolves: membership keyed separately would be orphaned by the
        /// same merge that fixes the duplicate.
        ///
        /// Optional, and every new field here must be: Swift's synthesized
        /// `Codable` does NOT fall back to a property's default for a missing
        /// key, so a non-optional addition would throw on decode and take the
        /// WHOLE book with it (the decode is one `try?` over the entire
        /// dictionary). `provenance` set that precedent.
        var groups: [String]? = nil
        /// When this entry last CHANGED — the merge stamp iCloud sync compares
        /// (`AddressBookSync`). Distinct from `addedAt`, which records when the
        /// address was first named and deliberately never moves.
        var updatedAt: Date? = nil
        /// When the chain was last ASKED what this address is (2026-08-13,
        /// prd §372) — distinct from `updatedAt` in both directions: this
        /// moves when a detection merely RAN, and never when the person edits
        /// anything.
        ///
        /// It exists because a kind was detected once and then believed
        /// forever. The transition that makes that wrong is ordinary: an
        /// ERC-4337 smart account has a counterfactual address that holds
        /// funds BEFORE it is deployed, so it reads as an EOA, gets filed
        /// `.wallet`, and stays a `.wallet` for life once its first
        /// UserOperation puts code there. `.contract` has the milder version
        /// (a `detectSmartAccount` that was transiently unreachable). Both
        /// were unreachable by the two existing one-shots, which fire once per
        /// install and can only fix what was already wrong on the day they
        /// shipped.
        ///
        /// nil means never checked, which sorts oldest — the honest reading
        /// for a book written before this field existed. Optional like every
        /// other addition here, for the decode reason `groups` documents.
        var kindCheckedAt: Date? = nil
        var id: String { AddressBook.key(for: address) }

        var short: String { WalletStore.shortAddress(address) }

        /// The stamp a merge sorts on — `addedAt` for entries written before
        /// the field existed, which is the honest floor: whatever the other
        /// device has that carries a real stamp is newer.
        var stamp: Date { updatedAt ?? addedAt }

        var groupNames: [String] { groups ?? [] }

        /// Group membership, case-folded — the ONE place that test is spelled.
        /// It was written out at thirteen sites across three files before this,
        /// which is how a fold rule quietly stops being one.
        func isIn(_ group: String) -> Bool {
            groupNames.contains { AddressBook.sameGroup($0, group) }
        }
    }

    /// key (normalised address) → entry.
    private var entries: [String: Entry] {
        didSet {
            cachedColliding = nil
            persist()
        }
    }

    /// `collidingKeys`' memo, dropped whenever the book changes. Not
    /// `@ObservationIgnored`-worthy: it's derived from `entries`, which is
    /// already the observed thing, and every reader reads it through a body
    /// that `entries` invalidates anyway.
    private var cachedColliding: Set<String>?

    /// True while a multi-address operation is in flight, so `persist()` (a
    /// full JSON encode of the whole book, plus an iCloud push) runs ONCE at
    /// the end instead of once per address. A forty-address paste did eighty
    /// encodes and eighty `NSUbiquitousKeyValueStore.synchronize()` calls
    /// before this — on the main thread, for what is logically one write.
    private var batching = false

    private func batched(_ body: () -> Void) {
        guard !batching else { return body() }   // already inside one
        batching = true
        body()
        batching = false
        persist()
    }

    /// The comparison form. A NAME resolves to the address it stands for
    /// first (below); then hex lowercases (EIP-55 case is a checksum, not
    /// identity), and everything else is left exactly as it came, because
    /// base58 case IS identity and folding it merges two different wallets —
    /// the same asymmetry `WalletStore.dedupeKey` keeps.
    static func key(for address: String) -> String {
        let canonical = resolvedForm(of: address)
        return ENS.isHexAddress(canonical) ? canonical.lowercased() : canonical
    }

    // MARK: - Names are not identities (2026-07-25, prd §212)

    /// watched/typed spelling → the address it stands for ("vitalik.eth" →
    /// "0xd8dA…6045"), mirrored from `WalletStore`'s own resolution cache and
    /// keyed by the LOWERCASED name (a name is case-insensitive; the address
    /// it answers with is not, so only the key folds).
    ///
    /// Why the book needs it: keying on the literal string made one wallet two
    /// entries. Watching by ENS named a row under "vitalik.eth" while every
    /// chain read — counterparty naming, reverse ENS — named another under the
    /// hex, and the two never met: two rows, same wallet, one of them wearing
    /// the star (found 2026-07-25, when prd §212 made the book the Wallet
    /// manager's main content and the duplicate became the first thing you
    /// see). Only names ever alias (a spelling with a dot); a hex or base58
    /// address is already the identity.
    ///
    /// Static, and read from the same defaults key `WalletStore` persists to,
    /// so `key(for:)` stays a pure static function — callable from `shared`'s
    /// own initializer without re-entering it.
    private static var aliases: [String: String] = loadAliases()

    private static func loadAliases() -> [String: String] {
        let raw = UserDefaults.standard.dictionary(forKey: "wallet.resolutions")
            as? [String: String] ?? [:]
        var out: [String: String] = [:]
        for (spelling, resolved) in raw where isName(spelling) && !resolved.isEmpty {
            out[spelling.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = resolved
        }
        return out
    }

    /// A spelling that stands for an address rather than being one. The dot is
    /// the whole test: every ENS/SNS name has one and no hex or base58 address
    /// can (base58 excludes it, hex is `0x` + 40 hex digits).
    private static func isName(_ s: String) -> Bool {
        s.contains(".") && !ENS.isHexAddress(s)
    }

    /// The address a spelling stands for — the resolved hex/base58 when the
    /// name has resolved at least once, else the spelling itself. Display
    /// keeps the person's own words (`Entry.name`); identity uses this.
    static func resolvedForm(of address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isName(trimmed) else { return trimmed }
        return aliases[trimmed.lowercased()] ?? trimmed
    }

    /// Records a name's resolution and folds the row standing under the name
    /// into the row standing under the address. Called by
    /// `WalletStore.noteResolution` — the one place both spellings meet.
    func noteResolution(_ watched: String, resolved: String) {
        let name = watched.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isName(name), !resolved.isEmpty else { return }
        let key = name.lowercased()
        guard Self.aliases[key] != resolved else { return }
        Self.aliases[key] = resolved
        reconcileAliases()
    }

    /// Re-keys every entry whose spelling now resolves, merging into whatever
    /// already stands under the resolved address. Idempotent and cheap (the
    /// book is tens of rows): run once at init — so a launch that already
    /// knows the resolution heals before anything reads the list, no sync
    /// required — and again whenever a new resolution lands.
    private func reconcileAliases() {
        var merged = entries
        var changed = false
        for (oldKey, entry) in entries {
            let newKey = Self.key(for: entry.address)
            guard newKey != oldKey else { continue }
            let address = Self.resolvedForm(of: entry.address)
            var moved = entry
            moved.address = address
            if let standing = merged[newKey] {
                moved = Self.merging(moved, into: standing, at: address)
            }
            merged.removeValue(forKey: oldKey)
            merged[newKey] = moved
            changed = true
        }
        if changed { entries = merged }
    }

    /// Folds two rows for one wallet into one. The row keyed by the ADDRESS
    /// stands — it's the one every chain read writes and consults — and keeps
    /// its name, unless that name is only the address's own short form (the
    /// fallback a bare watch lands), in which case the name given to the ENS
    /// spelling is the real one and wins. The earliest `addedAt` survives (the
    /// book remembers when you first named it), and kind/provenance fill in
    /// from either side rather than leaving with the row that goes.
    private static func merging(_ alias: Entry, into standing: Entry, at address: String) -> Entry {
        var out = standing
        out.address = address
        if standing.name.isEmpty || WalletStore.isAutoName(standing.name, for: address) {
            out.name = alias.name
        }
        out.addedAt = min(standing.addedAt, alias.addedAt)
        if out.kind == .unknown { out.kind = alias.kind }
        if out.provenance == nil { out.provenance = alias.provenance }
        // Groups UNION rather than pick a side: both rows were the person's
        // own filing of the same wallet, and dropping either half would lose a
        // group they put it in. Ordered, not a Set, so the list stays stable.
        let combined = standing.groupNames + alias.groupNames.filter {
            !standing.groupNames.contains($0)
        }
        out.groups = combined.isEmpty ? nil : combined
        out.updatedAt = [standing.updatedAt, alias.updatedAt].compactMap { $0 }.max()
        return out
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        } else {
            entries = [:]
        }
        migrateIfNeeded()
        recheckContractKinds()
        // Heals books written before names were resolved (2026-07-25) — the
        // duplicate pair collapses on the next launch with no sync and no
        // migration flag, because the reconcile is the same pass that keeps
        // the book correct from here on.
        reconcileAliases()
        // The iCloud mirror, one runloop turn later — `attach` reads
        // `AddressBook.shared`, which does not exist until this initializer
        // returns.
        DispatchQueue.main.async { AddressBookSync.shared.attach() }
    }

    // MARK: - Reading

    /// Every entry, newest name first — the book's own order. Watched or not:
    /// the caller decides how to split them (the Wallet screen shows watched
    /// ones under their own heading).
    var all: [Entry] { entries.values.sorted { $0.addedAt > $1.addedAt } }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    func entry(for address: String) -> Entry? { entries[Self.key(for: address)] }

    /// The person's own name for an address, or nil. The one read every
    /// resolver consults first — their word beats ENS, a known-contract table,
    /// and every other source, because it's their record.
    func name(for address: String) -> String? {
        let name = entries[Self.key(for: address)]?.name
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// Filtered for the book's search field — matches the name, any part of
    /// the address, any GROUP it's filed under, or its provenance, so "mom",
    /// "9a2E", "Family" and "Peer" all find rows.
    ///
    /// Groups and provenance joined on 2026-08-13, and the group half is the
    /// one that was actually broken. §267's whole ruling is that the omnibox
    /// is where a group becomes findable — it is the field the person types
    /// "Family" into — and it searched two fields, neither of which was the
    /// group, so it answered "no matches" for a group the chips right above
    /// it were displaying. The chip filter is a different gesture (narrow to
    /// a group you can see) and does not stand in for typing its name.
    ///
    /// Provenance rides along because it's already printed on the row by
    /// `subline`: a field the person can read and cannot search reads as a
    /// broken search, whichever field it is.
    ///
    /// Group matching goes through `sameGroup`'s folding rather than a raw
    /// `contains`, so a search agrees with the book about what one group IS —
    /// but only for a WHOLE-name match; a partial query still falls back to
    /// substring, since someone typing "fam" hasn't named a group yet.
    func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { entry in
            if entry.name.lowercased().contains(q) { return true }
            if entry.address.lowercased().contains(q) { return true }
            if let provenance = entry.provenance, provenance.lowercased().contains(q) { return true }
            return entry.groupNames.contains {
                Self.sameGroup($0, q) || $0.lowercased().contains(q)
            }
        }
    }

    // MARK: - Writing

    /// Names an address (or renames it). An empty name REMOVES the entry —
    /// clearing a name is how you leave the book, matching the rename field's
    /// own "a blank name shows the address instead" grammar.
    ///
    /// Returns the entry that now stands, or nil when the name was cleared.
    @discardableResult
    func setName(_ name: String, for address: String,
                 provenance: String? = nil, kind: Kind? = nil) -> Entry? {
        let key = Self.key(for: address)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(address)
            return nil
        }
        if var existing = entries[key] {
            existing.name = trimmed
            // Provenance and kind only ever FILL IN — a later plain rename
            // must not erase the verified source an entry arrived with.
            if let provenance { existing.provenance = provenance }
            if let kind { existing.kind = kind }
            existing.updatedAt = .now
            entries[key] = existing
            return existing
        }
        // Stored in its RESOLVED form when the name has resolved before, so a
        // row named by ENS and a row met on-chain are one row from the start
        // (§212). An unresolved name still stores as typed — `reconcileAliases`
        // folds it in the moment resolution lands.
        let entry = Entry(address: Self.resolvedForm(of: address),
                          name: trimmed, addedAt: .now,
                          kind: kind ?? .unknown, provenance: provenance,
                          updatedAt: .now)
        entries[key] = entry
        return entry
    }

    /// Records what an address turned out to BE. Separate from naming because
    /// detection is the chain's answer, arriving whenever the lookup lands.
    ///
    /// Deliberately does NOT stamp `updatedAt`: a kind is the chain's answer,
    /// not the person's edit, and every device detects it independently.
    /// Stamping would make a passive detection outrank a real rename made on
    /// another device.
    /// Stamps `kindCheckedAt` even when the kind is UNCHANGED (2026-08-13),
    /// which is the whole reason the re-check sweep terminates: it picks the
    /// staleset entries, and confirming an address is still what it was has to
    /// count as having asked, or the same eight rows are re-read on every
    /// foreground for the life of the install.
    func setKind(_ kind: Kind, for address: String) {
        let key = Self.key(for: address)
        guard var entry = entries[key] else { return }
        guard entry.kind != kind else { markKindChecked(address); return }
        entry.kind = kind
        entry.kindCheckedAt = .now
        entries[key] = entry
    }

    /// Records that the chain was asked and told us nothing new — a read that
    /// no host answered, or one that confirmed what we already had.
    ///
    /// Separate from `setKind` because `AddressKind.detect` has exits that
    /// resolve no kind at all (every RPC down), and those must still count as
    /// an attempt for the STALE half of the sweep or an unreachable address
    /// burns the budget every pass forever. It deliberately does NOT do this
    /// for an `.unknown` entry: that one has never been resolved, `detectPending`
    /// re-asks it every pass by design, and stamping it would fold the "never
    /// answered" case into the "answered, still true" case.
    func markKindChecked(_ address: String) {
        let key = Self.key(for: address)
        guard var entry = entries[key], entry.kind != .unknown else { return }
        entry.kindCheckedAt = .now
        entries[key] = entry
    }

    func remove(_ address: String) {
        let key = Self.key(for: address)
        guard entries[key] != nil else { return }
        // The tombstone is recorded BEFORE the entry goes, so the push that
        // the removal itself triggers already carries it — otherwise the
        // deletion would leave here without the fact that explains it, and
        // whichever device still holds the entry would send it straight back
        // (`AddressBookSync`).
        AddressBookSync.shared.noteRemoval(key)
        entries.removeValue(forKey: key)
    }

    // MARK: - Sync (AddressBookSync's own two doors)

    /// Which of two versions of one entry stands, or nil when the standing one
    /// does. The single statement of the rule both the iCloud merge and the
    /// Data tray's import follow: a STRICTLY newer stamp wins, and the winner
    /// keeps the earliest `addedAt` either side knows — that field records
    /// when the address was first named, so the true value is the older one
    /// whichever side's edit is newer.
    static func newer(_ incoming: Entry, than standing: Entry?) -> Entry? {
        guard let standing else { return incoming }
        guard incoming.stamp > standing.stamp else { return nil }
        var winner = incoming
        winner.addedAt = min(standing.addedAt, incoming.addedAt)
        return winner
    }

    /// This device's whole book, for the mirror to push.
    var syncSnapshot: [String: Entry] { entries }

    /// Replaces the book with a merged one. Only `AddressBookSync` calls this,
    /// and only with the result of its own newest-fact-wins merge.
    func applyMerged(_ merged: [String: Entry]) {
        entries = merged
        reconcileAliases()
    }

    // MARK: - Groups (2026-08-01)

    /// **A group is a label on entries, not a container of them.** There is no
    /// group store, no group ids, no empty groups to manage: a group exists
    /// exactly as long as some address carries its name. That is what keeps
    /// this a flat list with a filter rather than a tree — and it means rename
    /// is a relabel, delete is an unlabel, and a group can never end up holding
    /// an address the book no longer has.
    ///
    /// The one rule worth stating: **deleting a group never deletes an
    /// address.** Every door that offers it says so.
    /// Two group names are the same group when they differ only in case.
    static func sameGroup(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Every group in use, alphabetical — for display. Sorted, so callers that
    /// only need a lookup use `canonicalGroupName` instead.
    var groupNames: [String] {
        var seen: [String: String] = [:]   // folded → the spelling in use
        for entry in entries.values {
            for name in entry.groupNames where seen[name.lowercased()] == nil {
                seen[name.lowercased()] = name
            }
        }
        return seen.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The spelling already in use for a group matching this one case-folded,
    /// so "family" typed twice doesn't become two groups wearing one word.
    /// Scans `entries` directly rather than going through `groupNames`, whose
    /// localized SORT is pure waste for a first-match lookup — this is called
    /// once per address in a bulk paste.
    private func canonicalGroupName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in entries.values {
            if let match = entry.groupNames.first(where: { Self.sameGroup($0, trimmed) }) {
                return match
            }
        }
        return trimmed
    }

    func entries(inGroup name: String) -> [Entry] {
        all.filter { $0.isIn(name) }
    }

    /// The one read-modify-write behind every group edit: transform the group
    /// list of each named key, stamp what changed, and write the dictionary
    /// back ONCE — which matters because `entries`' own `didSet` persists and
    /// pushes to iCloud, so a per-key write would encode the whole book once
    /// per key.
    private func editGroups(of keys: some Sequence<String>,
                            _ transform: ([String]) -> [String]) {
        var out = entries
        var changed = false
        for key in keys {
            guard let names = out[key]?.groupNames else { continue }
            let next = transform(names)
            guard next != names else { continue }
            out[key]?.groups = next.isEmpty ? nil : next
            out[key]?.updatedAt = .now
            changed = true
        }
        if changed { entries = out }
    }

    /// Files an address under a group. An address with no entry yet is named
    /// with its own short form first — filing something implies keeping it,
    /// and a group naming an address the book doesn't hold would be the
    /// orphan this design exists to make impossible.
    func addToGroup(_ name: String, address: String) {
        let group = canonicalGroupName(name)
        guard !group.isEmpty else { return }
        let key = Self.key(for: address)
        if entries[key] == nil {
            setName(WalletStore.shortAddress(Self.resolvedForm(of: address)), for: address)
        }
        editGroups(of: [key]) { $0.contains(where: { Self.sameGroup($0, group) }) ? $0 : $0 + [group] }
    }

    /// Files SEVERAL addresses under one group in a single write (2026-08-01) —
    /// the book-level door, where a group is named and its members picked in
    /// one pass. Calling the single-address form in a loop would be correct and
    /// slow in the way `editGroups` exists to prevent: `entries`' own `didSet`
    /// encodes the whole book and pushes it to iCloud, so a forty-address pick
    /// would be forty encodes of a growing dictionary.
    ///
    /// Returns the spelling actually filed under, which is NOT always the one
    /// typed: a book already holding "Family" answers "family" with its own
    /// spelling. The caller needs that back to select the chip it just made —
    /// selecting the typed form would filter on a group that matches nothing.
    /// Nil when the name is blank, so a caller can't select a group that was
    /// never created.
    @discardableResult
    func addToGroup(_ name: String, addresses: some Sequence<String>) -> String? {
        let group = canonicalGroupName(name)
        guard !group.isEmpty else { return nil }
        // Name anything not yet in the book first, for the reason the
        // single-address door does it: a group naming an address the book
        // doesn't hold is the orphan this design makes impossible. A write
        // apiece, but only for addresses the picker could not have offered.
        var keys: [String] = []
        for address in addresses {
            let key = Self.key(for: address)
            guard !key.isEmpty else { continue }
            if entries[key] == nil {
                setName(WalletStore.shortAddress(Self.resolvedForm(of: address)), for: address)
            }
            keys.append(key)
        }
        guard !keys.isEmpty else { return nil }
        editGroups(of: keys) { $0.contains(where: { Self.sameGroup($0, group) }) ? $0 : $0 + [group] }
        return group
    }

    func removeFromGroup(_ name: String, address: String) {
        editGroups(of: [Self.key(for: address)]) {
            $0.filter { !Self.sameGroup($0, name) }
        }
    }

    func renameGroup(_ old: String, to new: String) {
        let target = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !Self.sameGroup(target, old) else { return }
        editGroups(of: entries.keys) { names in
            // Renaming ONTO an existing group merges rather than duplicating.
            var seen: Set<String> = []
            return names.map { Self.sameGroup($0, old) ? target : $0 }
                .filter { seen.insert($0.lowercased()).inserted }
        }
    }

    /// Unfiles every address in a group. The addresses and their names stay —
    /// only the label goes.
    func deleteGroup(_ name: String) {
        editGroups(of: entries.keys) { $0.filter { !Self.sameGroup($0, name) } }
    }

    // MARK: - Lookalikes (address poisoning, 2026-08-01)

    /// Entries that would print identically to this address but aren't it —
    /// see `AddressSafety.isLookalike` for what that means and why it's the
    /// one attack a named-address ledger is uniquely placed to catch.
    /// Reached on every keystroke while an address is being typed, so it
    /// early-outs on input that can't collide with anything (a partial
    /// address, a name) before touching the book at all — and walks
    /// `entries.values` rather than `all`, whose sort would be discarded.
    func lookalikes(of address: String) -> [Entry] {
        guard let target = AddressSafety.displayForm(address) else { return [] }
        let identity = AddressSafety.identity(address)
        return entries.values.filter {
            AddressSafety.displayForm($0.address) == target
                && AddressSafety.identity($0.address) != identity
        }
    }

    /// Every entry that collides with another entry already in the book — the
    /// rows that wear a warning.
    ///
    /// Cached, because its input only changes when `entries` does while its
    /// reader is a SwiftUI list body that re-evaluates on every keystroke:
    /// uncached, each one re-parsed the address shape of every row.
    var collidingKeys: Set<String> {
        if let cachedColliding { return cachedColliding }
        var byDisplay: [String: [String]] = [:]
        for entry in entries.values {
            guard let display = AddressSafety.displayForm(entry.address) else { continue }
            byDisplay[display, default: []].append(entry.id)
        }
        var out: Set<String> = []
        for (_, ids) in byDisplay where ids.count > 1 { out.formUnion(ids) }
        cachedColliding = out
        return out
    }

    // MARK: - Export

    /// The whole book as text, in the exact shape `addBulk` reads back —
    /// `Name, address[, group…]`, one entry per line.
    ///
    /// It exists because names are the person's own record and, until this,
    /// were the one thing in the app they could put in but never take out.
    /// Round-tripping is the whole point, so this and `addBulk` are a pair:
    /// change one and change the other.
    func exportText() -> String {
        all.map { entry in
            ([entry.name, entry.address] + entry.groupNames).joined(separator: ", ")
        }.joined(separator: "\n")
    }

    /// The book as JSON-ready dictionaries, for the Data tray's export
    /// (2026-08-01). That export calls itself "everything as one JSON file"
    /// and walked `Thing`s only — but a name the person typed lives in
    /// UserDefaults, not the corpus, so the address book was the one piece of
    /// their own data "everything" quietly left behind. Losslessly here (kind,
    /// provenance, groups and both dates), unlike `exportText`, whose job is
    /// pasting names into another app rather than restoring them into this one.
    func exportPayload() -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        return all.map { entry in
            var dict: [String: Any] = [
                "address": entry.address,
                "name": entry.name,
                "addedAt": iso.string(from: entry.addedAt),
                "kind": entry.kind.rawValue,
            ]
            if let provenance = entry.provenance { dict["provenance"] = provenance }
            if !entry.groupNames.isEmpty { dict["groups"] = entry.groupNames }
            if let updatedAt = entry.updatedAt { dict["updatedAt"] = iso.string(from: updatedAt) }
            return dict
        }
    }

    /// Reads exported entries back. An entry the book doesn't hold lands; one
    /// it does is overwritten only by a STRICTLY newer stamp, so importing an
    /// older backup can restore what was lost without undoing a rename made
    /// since. Returns how many rows changed.
    @discardableResult
    func importPayload(_ items: [[String: Any]]) -> Int {
        let iso = ISO8601DateFormatter()
        var out = entries
        var changed = 0
        for item in items {
            guard let address = item["address"] as? String, !address.isEmpty,
                  let name = item["name"] as? String, !name.isEmpty
            else { continue }
            let key = Self.key(for: address)
            let added = (item["addedAt"] as? String).flatMap { iso.date(from: $0) } ?? .now
            let updated = (item["updatedAt"] as? String).flatMap { iso.date(from: $0) }
            let incoming = Entry(address: Self.resolvedForm(of: address),
                                 name: name, addedAt: added,
                                 kind: (item["kind"] as? String).flatMap(Kind.init(rawValue:))
                                     ?? .unknown,
                                 provenance: item["provenance"] as? String,
                                 groups: item["groups"] as? [String],
                                 updatedAt: updated)
            guard let winner = Self.newer(incoming, than: out[key]) else { continue }
            out[key] = winner
            changed += 1
        }
        if changed > 0 { entries = out }
        return changed
    }

    // MARK: - Bulk

    /// Adds several addresses at once from pasted text — one per line, or
    /// comma-separated, each optionally "name, 0x…" or bare. Returns how many
    /// landed. The Tokens screen's bulk-watch precedent, applied to naming.
    ///
    /// A bare address lands unnamed ONLY if it can't be helped: an entry needs
    /// a name to be a book entry, so a bare paste takes its short form as the
    /// name, which the person can rename in one tap.
    /// Parsed LINE BY LINE, then comma by comma within a line — which is what
    /// lets one parser read every shape a pasted list actually takes without
    /// any of them being ambiguous:
    ///
    ///     0x9a2E…                     a bare address
    ///     Mom, 0x9a2E…                a name for it
    ///     0xaaa…, 0xbbb…              several bare addresses on one line
    ///     Mom, 0x9a2E…, Family        …and the groups it belongs to
    ///     Mom                         a name for the address on the NEXT line
    ///
    /// The rule that disambiguates the last two: within a line, a non-address
    /// token BEFORE the first address is a name; non-address tokens AFTER an
    /// address are that address's groups. Across lines, a line that named
    /// nothing carries its name forward — the old multi-line behaviour, kept.
    ///
    /// Pairs with `exportText`, whose output this reads back exactly.
    @discardableResult
    func addBulk(_ raw: String) -> Int {
        var landed = 0
        // ONE write for the whole paste — see `batched`.
        batched {
            var pendingName: String?
            for line in raw.split(separator: "\n") {
                let tokens = Self.tokens(in: line)
                guard !tokens.isEmpty else { continue }
                var lastAddress: String?
                for token in tokens {
                    if looksLikeAddress(token) {
                        let name = pendingName ?? WalletStore.shortAddress(token)
                        if setName(name, for: token) != nil { landed += 1 }
                        pendingName = nil
                        lastAddress = token
                    } else if let address = lastAddress {
                        // Trailing tokens belong to the address they follow.
                        addToGroup(token, address: address)
                    } else {
                        // Leading token — a name for the address still to
                        // come, on this line or the next.
                        pendingName = token
                    }
                }
            }
        }
        return landed
    }

    private static func tokens(in line: some StringProtocol) -> [String] {
        line.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// True when pasted text holds MORE than one thing worth landing — the
    /// test the omnibox uses to decide between watching one address and
    /// importing a list. Deliberately counts addresses, not lines: "Mom,
    /// 0x9a2E…" is one address wearing a name, and treating it as a list
    /// would drop the person into a bulk import for a single paste.
    ///
    /// Shares `addBulk`'s tokenizer — two parsers for one format is exactly
    /// the drift `exportText`'s "change one and change the other" note warns
    /// about. Stops at the second address rather than tokenizing a whole
    /// forty-line paste: this runs on every keystroke.
    func looksLikeBulk(_ raw: String) -> Bool {
        var found = 0
        for line in raw.split(separator: "\n") {
            for token in Self.tokens(in: line) where looksLikeAddress(token) {
                found += 1
                if found > 1 { return true }
            }
        }
        return false
    }

    /// Loose on purpose, exactly like `WalletStore.add`'s own validation: an
    /// address is public data and a bad one simply never resolves to anything.
    func looksLikeAddress(_ token: String) -> Bool {
        ENS.isHexAddress(token) || ENS.looksLikeName(token)
            || SNS.looksLikeName(token) || SNS.isAddress(token)
            || BitcoinAddress.isAddress(token)
    }

    // MARK: - Migration

    /// Folds the two pre-book name stores into this one, once (prd §169):
    /// `CounterpartyLabels` (names given on transaction sheets) and every
    /// watched wallet's own label. Neither source is deleted — the old
    /// defaults key stays put, so a downgrade doesn't lose anything.
    private func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        if let data = UserDefaults.standard.data(forKey: "wallet.counterpartyLabels.v1"),
           let old = try? JSONDecoder().decode([String: String].self, from: data) {
            for (address, name) in old where !name.isEmpty {
                if entries[Self.key(for: address)] == nil {
                    entries[Self.key(for: address)] = Entry(address: address, name: name,
                                                            addedAt: .now)
                }
            }
        }
        // Watched labels — read straight from the defaults rather than through
        // WalletStore, so the book can migrate during ITS init without the two
        // singletons waiting on each other.
        if let data = UserDefaults.standard.data(forKey: "wallet.addresses"),
           let watched = try? JSONDecoder().decode([WalletStore.WatchedAddress].self, from: data) {
            for entry in watched where !entry.label.isEmpty {
                if entries[Self.key(for: entry.address)] == nil {
                    entries[Self.key(for: entry.address)] =
                        Entry(address: entry.address, name: entry.label,
                              addedAt: .now, kind: .wallet)
                }
            }
        }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)
    }

    /// Forgets every cached `.contract` verdict, once (2026-07-25). Detection
    /// used to read an EIP-7702 delegation as bytecode and call a delegated
    /// wallet a contract; the rule is fixed in `AddressKind`, but a verdict
    /// already cached is never revisited (`detectPending` only asks about
    /// `.unknown`), so the wrong label would outlive the bug. Dropping back to
    /// `.unknown` costs nothing visible — an unchecked row and a wallet row
    /// look identical — and the next Wallet-screen visit re-detects under the
    /// corrected rule. Genuine contracts simply come back as contracts.
    private func recheckContractKinds() {
        guard !UserDefaults.standard.bool(forKey: Self.kindRecheckKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.kindRecheckKey)
        var out = entries
        var changed = false
        for (key, entry) in entries where entry.kind == .contract {
            out[key]?.kind = .unknown
            changed = true
        }
        if changed { entries = out }
    }

    private func persist() {
        guard !batching else { return }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        // …and up, when the person has iCloud sync on. A no-op otherwise, and
        // a no-op while a remote merge is being applied, so a pull can't bounce
        // back out as a push.
        AddressBookSync.shared.push()
    }
}
