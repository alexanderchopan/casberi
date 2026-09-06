import Foundation

/// A private note on an account (prd §639, 2026-09-06) — the one line on an
/// account page the person writes themselves: "work token, rotate quarterly",
/// "Sam's repo", "the old address".
///
/// Keyed by the BridgeStore SEAT ID, not the catalog name, so a §629 rename
/// keeps the note. Stored in the app-group `UserDefaults` and NOWHERE ELSE:
/// a note is the kind of thing that names a key's purpose or a person, and it
/// never rides CloudKit in this pass — the whole account page is a device
/// screen about what this device holds. Empty text REMOVES the entry rather
/// than storing "", so a cleared note leaves no row behind to count.
///
/// Foundation-only by design, so `scripts/account-page-selftest.sh` compiles
/// it whole and unmodified.
enum AccountNotes {
    static let key = "account.notes.v1"

    /// The suite. `SharedStore.groupDefaults` is the once-made instance
    /// (prd §626); `.standard` is the degrade when the entitlement is missing.
    static var defaults: UserDefaults { SharedStore.groupDefaults ?? .standard }

    static func note(for seat: String, defaults: UserDefaults? = nil) -> String? {
        let book = load(defaults ?? Self.defaults)
        guard let text = book[seat], !text.isEmpty else { return nil }
        return text
    }

    static func set(_ text: String, for seat: String, defaults: UserDefaults? = nil) {
        let suite = defaults ?? Self.defaults
        var book = load(suite)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { book.removeValue(forKey: seat) } else { book[seat] = trimmed }
        save(book, suite)
    }

    /// Every seat that carries a note — the Delete-access sweep reads this to
    /// know what a wipe removes, and the probe reads it to prove a write.
    static func all(defaults: UserDefaults? = nil) -> [String: String] {
        load(defaults ?? Self.defaults)
    }

    static func forgetAll(defaults: UserDefaults? = nil) {
        (defaults ?? Self.defaults).removeObject(forKey: key)
    }

    private static func load(_ suite: UserDefaults) -> [String: String] {
        suite.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func save(_ book: [String: String], _ suite: UserDefaults) {
        if book.isEmpty { suite.removeObject(forKey: key) } else { suite.set(book, forKey: key) }
    }
}

/// When an account page was last LOOKED AT, per seat (prd §639) — the clock
/// behind the ring on a watched row: "this account produced things since you
/// last opened this page". Stamped on the page's disappearance, never on its
/// arrival, so the visit that shows the ring is the one that clears it. A
/// seat never visited reads nil, and nil is "nothing is new" — a fresh
/// install must not ring its whole roster the way `BandRow` guards the widget
/// stamp for the same reason.
enum AccountVisits {
    static let key = "account.lastLooked.v1"

    static var defaults: UserDefaults { SharedStore.groupDefaults ?? .standard }

    static func lastLooked(_ seat: String, defaults: UserDefaults? = nil) -> Date? {
        let book = (defaults ?? Self.defaults).dictionary(forKey: key) as? [String: Double] ?? [:]
        guard let stamp = book[seat], stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    static func stamp(_ seat: String, at date: Date = .now, defaults: UserDefaults? = nil) {
        let suite = defaults ?? Self.defaults
        var book = suite.dictionary(forKey: key) as? [String: Double] ?? [:]
        book[seat] = date.timeIntervalSince1970
        suite.set(book, forKey: key)
    }
}
