import Foundation

/// THE PEOPLE YOU FOLLOW, ACROSS NETWORKS, FOR THE SOCIAL ROOM'S FACE ROW
/// (prd §1079, the gap §1068 left).
///
/// The face row (§959) belonged to Farcaster's and Bluesky's own
/// rooms, and when the networks folded into one Social room it went with
/// them: nothing could pick a person any more. Brought back as one row over
/// all three, and a person you follow on two networks is ONE face, because
/// the Addresses index already knows they are one contact (`ContactIndex`:
/// identities joined by verified or confirmed links, never by a display
/// name, §632). A pick narrows the room to that person on every network
/// they post from.
///
/// A handle is only a person within its own network (one "alice" on two
/// networks is two strangers until a link says otherwise), so a
/// member is always a (network, handle) pair, and an account with no contact
/// is a person of its own.
///
/// Foundation-only: `scripts/followed-people-selftest.sh` compiles it whole.
enum FollowedPeople {

    /// One account's posts: the network they land under and the handle on
    /// each row (`Thing.authorHandle`, the account's own `key`).
    struct Member: Hashable {
        let source: String
        let handle: String
    }

    /// A followed account, as the stores give it.
    struct Account {
        let source: String
        let key: String
        let title: String
        let subtitle: String
        let avatarURL: String?
        /// Its `Identity` key in the Addresses index (`fc:…`, `bsky:…`).
        let identity: String
        /// Marked as the person's own (`mine`). Their own accounts are one
        /// face on every network: they said so, which is the one link no
        /// index is needed for.
        var mine = false
    }

    /// One face on the row.
    struct Person: Equatable {
        /// What the room's person scope holds.
        let id: String
        let title: String
        /// The account's own line, or the networks a joined person is on.
        let subtitle: String
        let avatarURL: String?
        /// The network whose mark stands in for a missing picture.
        let source: String
        let members: [Member]
    }

    static let contactPrefix = "contact:"
    /// The person's own face.
    static let yours = "you"

    /// The accounts, one face per person, in the order their first account
    /// came. `contact` names an identity's contact in the Addresses index, or
    /// nil when it has none.
    static func group(_ accounts: [Account], contact: (String) -> String?) -> [Person] {
        var order: [String] = []
        var byID: [String: [Account]] = [:]
        for account in accounts {
            let id = account.mine ? yours
                : contact(account.identity).map { contactPrefix + $0 }
                    ?? "\(account.source):\(account.key)"
            if byID[id] == nil { order.append(id) }
            // The same account listed twice is one member.
            if byID[id]?.contains(where: { $0.source == account.source && $0.key == account.key }) == true {
                continue
            }
            byID[id, default: []].append(account)
        }
        return order.compactMap { id in
            guard let members = byID[id], let first = members.first else { return nil }
            let pictured = members.first { $0.avatarURL?.isEmpty == false } ?? first
            let networks = members.map(\.source).reduce(into: [String]()) {
                if !$0.contains($1) { $0.append($1) }
            }
            return Person(
                id: id,
                title: first.title,
                subtitle: members.count == 1 ? first.subtitle : networks.joined(separator: " · "),
                avatarURL: pictured.avatarURL,
                source: pictured.source,
                members: members.map { Member(source: $0.source, handle: $0.key) })
        }
    }

    /// Which person a row's author is, by (network, handle).
    static func index(_ people: [Person]) -> [Member: String] {
        var out: [Member: String] = [:]
        for person in people {
            for member in person.members where out[member] == nil { out[member] = person.id }
        }
        return out
    }

    /// The accounts a scope keeps, or nil when the scope names nobody here.
    static func members(of scope: String, in people: [Person]) -> Set<Member>? {
        people.first { $0.id == scope }.map { Set($0.members) }
    }
}
