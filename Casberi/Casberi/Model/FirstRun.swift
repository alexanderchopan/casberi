import SwiftUI
import SwiftData

/// **HAS THIS PERSON ADDED ANYTHING YET (prd §1365 item 3).** The answer the
/// Feed's box reads (`StartWaysIn`), so "Start with any of these" gives way
/// the moment anything is added. Library's box read it too until that box was
/// deleted (2026-10-30); the Calendars page reads the phone's calendars here.
///
/// The eight kinds Library counted. A card arrives through its app, so the
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
