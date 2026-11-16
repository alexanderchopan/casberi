import Foundation
import WebKit

/// One web store per signed-in app (prd §1819).
///
/// The cookie seats (X, Instagram, Threads, TikTok, Duolingo, Privy) signed
/// in inside the app's DEFAULT `WKWebsiteDataStore`, the store the Aztec
/// browser and the agents' pages also use. Every page opened there could be
/// handed another seat's cookies by an embed, and one seat's sign-in page
/// could see that the others were signed in. Each seat now signs in inside a
/// store of its own. Still PERSISTENT, for the reason every sign-in view
/// records: a slow sign-in (2FA, a checkpoint) must outlive the view.
///
/// Not moved, on purpose: the agents' pages and the web-session seats
/// (`AgentPage`, `WebSessionSignInSheet`, Fileverse). Their signed-in PAGE is
/// the session, kept in the default store, and moving it signs the person
/// out. The seats here keep their session in the vault, so nothing is lost.
enum SeatWebStore {
    enum Seat: String, CaseIterable {
        case x, meta, tiktok, duolingo, privy

        /// Fixed per seat, so the store is the same one next launch.
        var id: UUID {
            switch self {
            case .x:        return UUID(uuidString: "6A5C0E1D-7A11-4C2E-9F3B-0A1100000101")!
            case .meta:     return UUID(uuidString: "6A5C0E1D-7A11-4C2E-9F3B-0A1100000102")!
            case .tiktok:   return UUID(uuidString: "6A5C0E1D-7A11-4C2E-9F3B-0A1100000103")!
            case .duolingo: return UUID(uuidString: "6A5C0E1D-7A11-4C2E-9F3B-0A1100000104")!
            case .privy:    return UUID(uuidString: "6A5C0E1D-7A11-4C2E-9F3B-0A1100000105")!
            }
        }

        /// What this seat left in the default store before it had its own.
        /// Instagram and Threads are one store: Threads signs in THROUGH
        /// Instagram, and Meta already knows they are one person.
        var domains: [String] {
            switch self {
            case .x:        return ["x.com", "twitter.com"]
            case .meta:     return ["instagram.com", "threads.com", "threads.net"]
            case .tiktok:   return ["tiktok.com", "tiktokv.com"]
            case .duolingo: return ["duolingo.com"]
            case .privy:    return ["home.privy.io"]   // never privy.io whole: an app's own Privy sign-in lives there
            }
        }
    }

    @MainActor static func store(_ seat: Seat) -> WKWebsiteDataStore {
        retireShared()
        return WKWebsiteDataStore(forIdentifier: seat.id)
    }

    private static let retiredKey = "seatWebStore.sharedRetired.v1"

    /// Whether `record` (a registrable domain, as WebKit names it) is one a
    /// seat here owns. Pure, for the self-test.
    static func owns(record: String) -> Bool {
        let name = record.lowercased()
        return Seat.allCases.contains { seat in
            seat.domains.contains { name == $0 || name.hasSuffix("." + $0) }
        }
    }

    /// Once: the seats' old cookies leave the default store. Asked the first
    /// time a seat's sign-in opens, never at launch (it starts WebKit).
    @MainActor private static func retireShared() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: retiredKey) else { return }
        defaults.set(true, forKey: retiredKey)
        let shared = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        shared.fetchDataRecords(ofTypes: types) { records in
            let ours = records.filter { owns(record: $0.displayName) }
            guard !ours.isEmpty else { return }
            shared.removeData(ofTypes: types, for: ours) {}
        }
    }
}
