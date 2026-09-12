import Foundation

/// Who may READ an account (prd §639, 2026-09-06) — the per-account allow-list
/// behind the row of reader marks on every account page.
///
/// **A reader is anything that takes a thing out of the corpus to think with
/// it**: the on-device model, each agent key the person has added (Claude,
/// Venice, OpenRouter, Grok, Bankr), and a paired MCP client. A person is not a
/// reader — Find and the feed are theirs, and nothing here ever hides a row
/// from the person who captured it.
///
/// **Stored as a DENY list, keyed by SEAT ID.** The default is that every
/// reader may read every account ("Default — every agent you've added may read
/// it"), and the honest representation of a default is an absent entry, not a
/// list that has to be kept in step with the readers that exist. Turning a
/// reader off writes its id into the seat's denied set; turning it back on
/// removes it; a seat with nothing denied has no entry at all. An agent added
/// LATER is therefore allowed by default too, which is what the caption says
/// happens, and the only reading of "default" that stays true as keys come and
/// go.
///
/// **The SOURCE rides beside the seat.** Enforcement filters `Thing.source`,
/// and the seat→source join lives in `BridgeStore`, which the MCP server (off
/// the main actor, its own `ModelContext`) cannot reach. So a write records
/// the source name with the denial, and `deniedSources(for:)` answers without
/// any store — the same reason `NetworkLedger.Entry` carries its own service.
///
/// App-group `UserDefaults`, never CloudKit: which agent may read what on THIS
/// phone is a fact about this phone's keys.
///
/// Foundation-only by design, so `scripts/account-page-selftest.sh` compiles
/// it whole and unmodified.
enum AccountReaders {
    static let key = "account.readers.v1"

    /// One reader's identity — stable strings, never a display name, so a
    /// renamed agent keeps its setting.
    enum ID {
        static let device = "device"
        static let mcp = "mcp"
        static func agent(_ providerRaw: String) -> String { "agent:\(providerRaw)" }
    }

    /// A reader as the page draws it. `mark` is the catalog name `BridgeIcon`
    /// keys on, nil for the on-device model (a glyph tile, not a brand).
    struct Reader: Identifiable, Hashable {
        let id: String
        let name: String
        let mark: String?
    }

    struct Entry: Codable, Equatable {
        var source: String
        var denied: [String]
    }

    static var defaults: UserDefaults { SharedStore.groupDefaults ?? .standard }

    // MARK: - Reading

    static func denied(seat: String, defaults: UserDefaults? = nil) -> Set<String> {
        Set(load(defaults ?? Self.defaults)[seat]?.denied ?? [])
    }

    static func mayRead(_ reader: String, seat: String, defaults: UserDefaults? = nil) -> Bool {
        !denied(seat: seat, defaults: defaults).contains(reader)
    }

    /// Every `Thing.source` this reader is shut out of — what the answer path
    /// and the MCP door subtract before a thing reaches a model.
    static func deniedSources(for reader: String, defaults: UserDefaults? = nil) -> Set<String> {
        Set(load(defaults ?? Self.defaults).values
            .filter { $0.denied.contains(reader) }
            .map(\.source))
    }

    // MARK: - Writing

    static func setMayRead(_ reader: String, _ allowed: Bool, seat: String, source: String,
                           defaults: UserDefaults? = nil) {
        let suite = defaults ?? Self.defaults
        var book = load(suite)
        var entry = book[seat] ?? Entry(source: source, denied: [])
        // The source is re-stamped on every write: a §629 rename moves the
        // seat's rows under a new name, and the next tap on this page is the
        // moment the record learns it.
        entry.source = source
        if allowed {
            entry.denied.removeAll { $0 == reader }
        } else if !entry.denied.contains(reader) {
            entry.denied.append(reader)
        }
        if entry.denied.isEmpty { book.removeValue(forKey: seat) } else { book[seat] = entry }
        save(book, suite)
    }

    static func forget(seat: String, defaults: UserDefaults? = nil) {
        let suite = defaults ?? Self.defaults
        var book = load(suite)
        book.removeValue(forKey: seat)
        save(book, suite)
    }

    static func forgetAll(defaults: UserDefaults? = nil) {
        (defaults ?? Self.defaults).removeObject(forKey: key)
    }

    // THE CAPTION IS DELETED (prd §708, user: "get rid of the who may read
    // it section, it is really confusing and no one cares, we already in
    // settings give receipts"). `caption(available:denied:connected:)` and
    // its `list(_:)` sentence builder wrote the three-state line under the
    // reader marks on every account page; the block, the marks and the line
    // all went together. Everything ABOVE this comment stands — the deny
    // book, the per-source lookups and `AccountReadersEnforce` still filter
    // every hand-off to a model, defaulting to every reader, which is what
    // the receipts screen then reports. Restoring a per-account control
    // means writing new copy, not reviving this.

    // MARK: - Persistence

    private static func load(_ suite: UserDefaults) -> [String: Entry] {
        guard let data = suite.data(forKey: key),
              let book = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return book
    }

    private static func save(_ book: [String: Entry], _ suite: UserDefaults) {
        if book.isEmpty {
            suite.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(book) {
            suite.set(data, forKey: key)
        }
    }
}
