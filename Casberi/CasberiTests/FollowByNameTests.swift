import Foundation
import Testing
@testable import Casberi

/// **A Feed section's + is its category's follow-by-name apps** (prd §1300).
///
/// The list is derived, so what can go wrong is a row that never draws or
/// draws and opens nothing: an app renamed in the catalogue, an app filed in
/// a category the Feed does not stack, or a row with nowhere to land.
@MainActor
struct FollowByNameTests {

    @Test func everyRowIsACatalogueApp() {
        let names = Set(BridgeCatalog.allOffers.map(\.name))
        for app in FollowByName.whats.keys {
            #expect(names.contains(app), "\(app) is not in the catalogue")
        }
    }

    @Test func everyRowStandsInAFeedSection() {
        let sections = Set(HomeScope.feedCategories(chips: CategoryOrder.defaultOrder))
        for offer in BridgeCatalog.allOffers where FollowByName.whats[offer.name] != nil {
            let category = BridgeCatalog.category(of: offer)
            #expect(sections.contains(category), "\(offer.name) files under \(category), which has no +")
        }
    }

    @Test func everyRowHasSomewhereToLand() {
        for app in FollowByName.whats.keys {
            // A page, and an account to connect first, need the app's page.
            let lands: Bool = switch FollowByName.landing(for: app) {
            case .page, .github, .mail: BridgeRouter.destination(forOffer: app) != nil
            default: true
            }
            #expect(lands, "\(app) opens a page it does not have")
        }
    }

    @Test func socialListsBlueskyAndTelegram() {
        #expect(FollowByName.doors(in: "Social").map(\.app) == ["Bluesky", "Telegram"])
    }

    @Test func doorsReadAToZ() {
        for category in ["Social", "Work", "Media", "Life"] {
            let apps = FollowByName.doors(in: category).map(\.app)
            #expect(apps == apps.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
            #expect(!apps.isEmpty, "\(category) lists nothing")
        }
    }

    @Test func aContactIsReachedByEmailAddressOrName() {
        #expect(NewContact.reach("Ana@Example.com") == .email("ana@example.com"))
        #expect(NewContact.reach("0xAbCdEf0123456789aBcDeF0123456789AbCdEf01")
                == .wallet("0xabcdef0123456789abcdef0123456789abcdef01"))
        #expect(NewContact.reach("vitalik.eth") == .name(.ens, "vitalik.eth"))
    }

    @Test func anythingElseIsNoContact() {
        for raw in ["", "Ana", "@ana", "ana@", "ana@example", "+1 415 555 0100", "two words.com"] {
            #expect(NewContact.reach(raw) == nil, "\(raw) read as a contact")
        }
    }
}
