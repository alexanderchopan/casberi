import Foundation
import Testing
@testable import Casberi

/// **Remove from Contacts** (prd §1610). A removed contact stays off the
/// list whatever still feeds it, and naming any one of its identities again
/// brings every one back. A wrong answer leaves a removed person on the list,
/// or keeps someone you named again hidden behind a key you did not touch.
@MainActor
@Suite(.serialized)
struct ContactsRemovedTests {
    private func contact(_ name: String, _ identities: [Identity]) -> Contact {
        Contact(id: identities[0].key, name: name, kind: .person, identities: identities, avatar: nil,
                lastActedAt: nil, lastThing: nil, keywords: [])
    }

    @Test func aRemovedContactLeavesTheListAndNamingItBringsItBack() {
        let wallet = Identity.make(.wallet, "0x00000000000000000000000000000000000c0de1")
        let ens = Identity.make(.ens, "removed-test.eth")
        let mia = contact("Mia", [wallet, ens])
        defer { ContactsRemoved.shared.restore(wallet.key) }

        #expect(ContactIndexSources.isListed(mia))
        ContactsRemoved.shared.remove(mia)
        #expect(ContactsRemoved.shared.removed(mia))
        #expect(!ContactIndexSources.isListed(mia))
        // Any one of its keys keeps the contact off, however it is rebuilt.
        #expect(ContactsRemoved.shared.removed(contact("Mia", [ens])))

        // Naming the ENS name again brings the wallet back with it.
        ContactsRemoved.shared.restore(ens.key)
        #expect(!ContactsRemoved.shared.removed(mia))
        #expect(ContactIndexSources.isListed(mia))
    }

    @Test func anotherContactIsUntouched() {
        let a = contact("A", [Identity.make(.email, "a@removed-test.example")])
        let b = contact("B", [Identity.make(.email, "b@removed-test.example")])
        defer { ContactsRemoved.shared.restore(a.lead.key) }
        ContactsRemoved.shared.remove(a)
        #expect(!ContactsRemoved.shared.removed(b))
    }
}
