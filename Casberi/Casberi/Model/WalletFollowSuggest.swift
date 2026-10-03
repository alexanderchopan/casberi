import Foundation

/// Who the Wallet's Follow tray offers before you type (prd §1090), Social's
/// "Near you" carried over (§1086): the addresses your own money already
/// moves with, then the names in your book you don't follow.
///
/// Foundation-only by design: `scripts/wallet-makeover-selftest.sh` compiles
/// it whole. A wrong suggestion renders as a calm list — a router offered as
/// a person, a poisoning address offered as a friend, the address you follow
/// offered again — so only a case-by-case statement says it is right.
enum WalletFollowSuggest {
    /// One transfer in the room, reduced to what the rule reads.
    struct Move {
        let counterparty: String
        let at: Date
        /// The row is flagged as poisoning or spam (`Thing.securityFlag`), or
        /// the move went through a venue (a swap, a bridge) — the other side
        /// is a contract, never a person. So is an address the app's
        /// directory knows as a protocol's, or one named for an app in the
        /// catalogue ("Coinbase", "Stripe") — a service, not someone.
        let excluded: Bool
    }

    /// One address-book entry, reduced to what the rule reads.
    struct BookEntry {
        let address: String
        let name: String
        /// `AddressBook.Kind.rawValue`.
        let kind: String
        let provenance: String?
        let addedAt: Date
        /// Named for an app in the catalogue, or a known contract — a service.
        var isService: Bool = false
    }

    enum Why: Equatable {
        /// Moved money with you this many times in the window.
        case movedWith(Int)
        /// A name in your book, with where it came from when known.
        case inBook(String?)
    }

    struct Suggestion: Equatable {
        let address: String
        let name: String?
        let why: Why
    }

    /// How far back a move counts, and how many make a habit.
    static let window: TimeInterval = 60 * 86_400
    static let habit = 2
    static let limit = 6

    /// Kinds that never hold your money with you: a contract is machinery,
    /// a key signs for an account and holds nothing (prd §294).
    static let neverOffered: Set<String> = ["contract", "key"]

    /// The comparison key: hex case-folds, everything else (Solana, Bitcoin)
    /// keeps its case, because there the case IS the address.
    static func key(_ address: String) -> String {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.hasPrefix("0x") ? a.lowercased() : a
    }

    static func suggestions(moves: [Move], book: [BookEntry], following: Set<String>,
                            now: Date) -> [Suggestion] {
        let followed = Set(following.map(key))
        var kinds: [String: BookEntry] = [:]
        for entry in book { kinds[key(entry.address)] = entry }
        var count: [String: Int] = [:]
        var latest: [String: Date] = [:]
        var spelling: [String: String] = [:]
        for move in moves where !move.excluded && now.timeIntervalSince(move.at) <= window
            && move.at <= now {
            let k = key(move.counterparty)
            guard !k.isEmpty, !followed.contains(k) else { continue }
            if let entry = kinds[k], neverOffered.contains(entry.kind) || entry.isService { continue }
            count[k, default: 0] += 1
            latest[k] = max(latest[k] ?? .distantPast, move.at)
            if spelling[k] == nil { spelling[k] = move.counterparty }
        }
        let habits = count.filter { $0.value >= habit }.keys.sorted {
            let (a, b) = (count[$0]!, count[$1]!)
            return a != b ? a > b : latest[$0]! > latest[$1]!
        }
        var out: [Suggestion] = habits.map { k in
            Suggestion(address: spelling[k]!, name: kinds[k].map(\.name), why: .movedWith(count[k]!))
        }
        var seen = Set(habits)
        for entry in book.sorted(by: { $0.addedAt > $1.addedAt }) {
            let k = key(entry.address)
            guard !followed.contains(k), !seen.contains(k),
                  !neverOffered.contains(entry.kind), !entry.isService else { continue }
            seen.insert(k)
            out.append(Suggestion(address: entry.address, name: entry.name, why: .inBook(entry.provenance)))
        }
        return Array(out.prefix(limit))
    }
}
