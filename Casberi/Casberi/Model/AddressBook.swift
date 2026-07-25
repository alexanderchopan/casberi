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

        /// The mark's glyph. Only a WALLET is a "who" — it wears the round
        /// identicon face; everything else gets a square mark, so a book of
        /// fifty rows separates people from machinery without any grouping UI.
        var glyph: String? {
            switch self {
            case .contract: return "curlybraces"
            case .safe:     return "shield.lefthalf.filled"
            case .wallet, .unknown: return nil
            }
        }

        var label: String? {
            switch self {
            case .contract: return String(localized: "Contract")
            case .safe:     return String(localized: "Safe")
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
        var id: String { AddressBook.key(for: address) }

        var short: String { WalletStore.shortAddress(address) }
    }

    /// key (normalised address) → entry.
    private var entries: [String: Entry] { didSet { persist() } }

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
        if standing.name.isEmpty || standing.name == WalletStore.shortAddress(address) {
            out.name = alias.name
        }
        out.addedAt = min(standing.addedAt, alias.addedAt)
        if out.kind == .unknown { out.kind = alias.kind }
        if out.provenance == nil { out.provenance = alias.provenance }
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

    /// Filtered for the book's search field — matches the name or any part of
    /// the address, so "mom" and "9a2E" both find the same row.
    func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q)
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
            entries.removeValue(forKey: key)
            return nil
        }
        if var existing = entries[key] {
            existing.name = trimmed
            // Provenance and kind only ever FILL IN — a later plain rename
            // must not erase the verified source an entry arrived with.
            if let provenance { existing.provenance = provenance }
            if let kind { existing.kind = kind }
            entries[key] = existing
            return existing
        }
        // Stored in its RESOLVED form when the name has resolved before, so a
        // row named by ENS and a row met on-chain are one row from the start
        // (§212). An unresolved name still stores as typed — `reconcileAliases`
        // folds it in the moment resolution lands.
        let entry = Entry(address: Self.resolvedForm(of: address),
                          name: trimmed, addedAt: .now,
                          kind: kind ?? .unknown, provenance: provenance)
        entries[key] = entry
        return entry
    }

    /// Records what an address turned out to BE. Separate from naming because
    /// detection is the chain's answer, arriving whenever the lookup lands.
    func setKind(_ kind: Kind, for address: String) {
        let key = Self.key(for: address)
        guard var entry = entries[key], entry.kind != kind else { return }
        entry.kind = kind
        entries[key] = entry
    }

    func remove(_ address: String) {
        entries.removeValue(forKey: Self.key(for: address))
    }

    // MARK: - Bulk

    /// Adds several addresses at once from pasted text — one per line, or
    /// comma-separated, each optionally "name, 0x…" or bare. Returns how many
    /// landed. The Tokens screen's bulk-watch precedent, applied to naming.
    ///
    /// A bare address lands unnamed ONLY if it can't be helped: an entry needs
    /// a name to be a book entry, so a bare paste takes its short form as the
    /// name, which the person can rename in one tap.
    @discardableResult
    func addBulk(_ raw: String) -> Int {
        let lines = raw.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var landed = 0
        var pendingName: String?
        for token in lines {
            if looksLikeAddress(token) {
                let name = pendingName ?? WalletStore.shortAddress(token)
                if setName(name, for: token) != nil { landed += 1 }
                pendingName = nil
            } else {
                // A non-address token is a name for the address that follows
                // ("Mom, 0x9a2E…") — the shape a pasted list actually takes.
                pendingName = token
            }
        }
        return landed
    }

    /// Loose on purpose, exactly like `WalletStore.add`'s own validation: an
    /// address is public data and a bad one simply never resolves to anything.
    func looksLikeAddress(_ token: String) -> Bool {
        ENS.isHexAddress(token) || ENS.looksLikeName(token)
            || SNS.looksLikeName(token) || SNS.isAddress(token)
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
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
