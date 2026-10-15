import Foundation

/// **A CONTACT TYPED BY HAND (prd §1300, user: "people's i guess should add
/// contacts and a contact entry if they don't want to import").** People is
/// the one list of everyone (`ContactIndex`): your contacts, the people
/// behind your accounts, your wallet book. Someone who will not import their
/// address book still adds a person: a name, and the one thing that ties it
/// to what Casberi reads — an email (their mail), a wallet address (their
/// transfers) or a name like `vitalik.eth`.
///
/// It is kept where hand-saved names already live, so the list needs nothing
/// new: an address in the wallet book (`AddressBook`, which never watches
/// it), anything else in `ContactBook`. A phone number has nothing here to
/// match, so the field does not take one.
enum NewContact {
    /// What the second field holds.
    enum Reach: Equatable {
        case email(String)
        case wallet(String)
        case name(Identity.Kind, String)
    }

    /// Nil for anything that is not an email, a hex address or a dotted name.
    static func reach(_ raw: String) -> Reach? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if ENS.isHexAddress(s) { return .wallet(s.lowercased()) }
        if let at = s.firstIndex(of: "@"), at != s.startIndex {
            let domain = s[s.index(after: at)...]
            guard domain.contains("."), !domain.contains("@"),
                  !domain.hasPrefix("."), !domain.hasSuffix(".") else { return nil }
            return .email(s.lowercased())
        }
        guard s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."),
              let kind = Identity.Kind.classify(primaryName: s), kind != .worldApp else { return nil }
        return .name(kind, s.lowercased())
    }

    /// Keep it, under the name typed. False when there is no name or no reach.
    @MainActor
    static func save(name raw: String, reach input: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let reach = reach(input) else { return false }
        switch reach {
        case .wallet(let address):
            AddressBook.shared.setName(name, for: address, kind: .wallet)
            Task { @MainActor in await AddressKind.detect(address) }
        case .email(let email):
            ContactBook.shared.save(Identity.make(.email, email), name: name)
        case .name(let kind, let body):
            ContactBook.shared.save(Identity.make(kind, body), name: name)
        }
        return true
    }
}
