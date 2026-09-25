import Foundation

/// What is left of the address book's PEOPLE half (prd §498 → §690 → §916).
///
/// §498 (2026-08-27) made the book "the app's one people surface": Apple
/// contacts and social accounts joined it as EPHEMERAL rows, folded by display
/// name. §690 deleted the book screen, and every function that built those
/// rows lost its last caller — `contacts(in:)`, `social()`, `twitch(in:)`,
/// `splits()`, `rows(in:excluding:)`, `fold(book:people:)` and `merged(_:)` sat
/// here dead for two weeks. §916 deletes them: the unified list is the
/// Addresses index now (`ContactIndex`), where a display name is NEVER a merge
/// key (§632) — the one rule the deleted `merged` broke on purpose and
/// bounded like a heuristic. Its reasoning is kept in the ledger, not here.
///
/// Two things survive because two screens still call them.
enum AddressBookPeople {

    /// What separates a source from a handle inside an `accounts` line.
    ///
    /// Spelled ONCE because since §511 it is parsed as well as built: the
    /// verb that unfollows a row reads the pair back out of `accounts`, which
    /// holds them exactly as the store spells them. Two literals would mean a
    /// row that displays correctly and cannot be acted on.
    static let accountSeparator = " · "

    /// The social accounts a row STANDS FOR, as the pairs their own stores
    /// know them by (2026-08-29, prd §511). A folded person can carry several,
    /// so this returns all of them and the verb acts on all of them.
    ///
    /// **Gated on `hasRoster`, which does the work of an allowlist for free.**
    /// A source read off the corpus rather than a local roster has nothing to
    /// remove a row from, and falls out here rather than being listed as an
    /// exception somewhere that could go stale.
    static func unfollowable(_ entry: AddressBook.Entry) -> [(source: String, handle: String)] {
        (entry.accounts ?? []).compactMap { line in
            guard let split = line.range(of: accountSeparator) else { return nil }
            let source = String(line[line.startIndex..<split.lowerBound])
            let handle = String(line[split.upperBound...])
            guard !handle.isEmpty, SocialRoom.hasRoster(source) else { return nil }
            return (source, handle)
        }
    }

    /// The label the card's address row wears: the network's own badge where
    /// the entry carries one, else the plain word.
    static func addressLabel(for entry: AddressBook.Entry) -> String {
        entry.networkBadge ?? String(localized: "Address")
    }
}
