import Foundation

/// **THE AUTHORIZATIONS YOU HAVE GIVEN ON AZTEC (prd §1762).** An app asks
/// for one (§1760), you approve it, and until now nothing listed it: no way
/// to see what an app may still do in your name, and no way to take it back.
/// Each one approved in Casberi is kept on this phone with the hash that
/// names it in Aztec's public registry; Wallet › Permissions lists the ones
/// the registry still holds and takes one back with one transaction.
///
/// This file is the part with no screen, no store and no chain: the record,
/// how the list is kept, and which records a reading of the registry leaves.
enum AztecGrantsShape {
    struct Grant: Codable, Equatable, Identifiable {
        /// The hash Aztec's registry holds: what a take-back names.
        let hash: String
        /// The site that asked, as the browser read it.
        let host: String
        let caller: String
        let contract: String
        let method: String
        /// The call's arguments in short words, as the sheet drew them.
        let args: [String]
        let transaction: String
        let at: Date
        var id: String { hash }
    }

    /// At most this many are kept; the oldest goes first.
    static let cap = 40
    /// A record this young is kept whatever the registry says: its own
    /// transaction may not be in a block the node has read yet.
    static let settling: TimeInterval = 10 * 60

    /// The list after an approval: that one first, once.
    static func added(_ grants: [Grant], _ grant: Grant) -> [Grant] {
        Array(([grant] + grants.filter { $0.hash.lowercased() != grant.hash.lowercased() }).prefix(cap))
    }

    static func removed(_ grants: [Grant], hash: String) -> [Grant] {
        grants.filter { $0.hash.lowercased() != hash.lowercased() }
    }

    /// The list after the registry was read: one that still stands, one that
    /// could not be read, and one too young to have landed stay. The rest
    /// were used by their app or taken back, and are dropped: an
    /// authorization is for one call (§1760).
    static func kept(_ grants: [Grant], standing: [String], unread: [String], now: Date) -> [Grant] {
        let stands = Set(standing.map { $0.lowercased() }), unknown = Set(unread.map { $0.lowercased() })
        return grants.filter {
            stands.contains($0.hash.lowercased()) || unknown.contains($0.hash.lowercased())
                || now.timeIntervalSince($0.at) < settling
        }
    }

    /// The row's line: the call and who may make it. "set authorized · ...63f2".
    static func line(_ grant: Grant) -> String {
        grant.method.replacingOccurrences(of: "_", with: " ") + " · " + tail(grant.caller)
    }

    /// An address by its last four, as every address in the app is drawn.
    static func tail(_ address: String) -> String { AddressTail.short(address) }
}
