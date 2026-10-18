import SwiftUI
import SwiftData

/// **HAS THIS PERSON ADDED ANYTHING YET (prd §1365 item 3, user: "so please
/// make them match").** The one answer Library's box and the Feed's box both
/// read (`StartWaysIn`), so "Start with any of these" gives way in both
/// places at the same moment. Each screen used to ask its own list: a contact
/// kept by hand cleared Library's box and left the Feed's.
///
/// The eight kinds Library counts. A card arrives through its app, so the
/// apps term holds it.
@MainActor @Observable
final class FirstRun {
    static let shared = FirstRun()

    /// The phone's calendars Casberi reads, and the people in Addresses
    /// other than you: neither can be read in a body (§628), so a screen's
    /// task reads them here.
    private(set) var phoneCalendars: [PhoneCalendar] = []
    private(set) var people = 0

    /// Reads what a body cannot, and the readings the other kinds keep. On a
    /// screen's task, never in a body.
    func refresh(_ context: ModelContext) async {
        phoneCalendars = PhoneCalendar.readable(context)
        await SubscriptionsReading.shared.refresh(context)
        MailSubscriptionsReading.shared.refresh(context)
        for room in Following.Room.allCases { FollowingReading.shared.refresh(room, context: context) }
        people = ContactIndexSources.rebuild(context: context)
            .filter(ContactIndexSources.isListed).count
    }

    /// Nothing added: no app (Markets is a place, not an app, prd §1123), no
    /// calendar, nothing followed, no mail list, nobody, no subscription, no
    /// address.
    func isEmpty(bridges: BridgeStore) -> Bool {
        bridges.bridges.allSatisfy {
            $0.status == .paused || BridgeCatalog.category(forSource: $0.name) == HomeScope.markets
        }
            && phoneCalendars.isEmpty && CalendarSubscriptionStore.shared.calendars.isEmpty
            && [Following.Room.reading, .media].allSatisfy { FollowingReading.shared.items(for: $0).isEmpty }
            && MailSubscriptionsReading.shared.items.isEmpty
            && people == 0
            && SubscriptionsReading.shared.items.isEmpty
            && WalletStore.shared.addresses.isEmpty
    }
}
