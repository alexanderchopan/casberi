import SwiftUI
import SwiftData

/// One connect path, shared by the catalog, the app detail page, and the Apps
/// list. Connect ends in proof — the wired bridges (Photos/Calendar/Reminders)
/// run their real system-framework path and the permission ask arrives in
/// context; everything else isn't wired yet and says so.
@MainActor
enum BridgeConnect {
    /// The one connect-success toast, shared by the Apps store and the product
    /// page so the copy can't drift — the proof itself arrives in the feed;
    /// this names what's now happening.
    static func landingMessage(_ name: String) -> String {
        String(localized: "Connected — your \(name) things are landing.")
    }

    static func connect(_ offer: BridgeCatalog.Offer, store: BridgeStore,
                        context: ModelContext,
                        completion: ((Bool) -> Void)? = nil) {
        Task {
            let result: (n: Int, id: String, noun: String, can: String, proof: String?)?
            switch offer.name {
            case "Photos":
                result = await ScreenshotIngest.connectAndIngest(context: context)
                    .map { ($0, "pho", "screenshots", "Reads screenshots you take.", nil) }
            case "Calendar":
                result = await ScheduleIngest.connectCalendar(context: context)
                    .map { ($0, "cal", "events", "Reads your events; adds one when you ask.", nil) }
            case "Reminders":
                result = await ScheduleIngest.connectReminders(context: context)
                    .map { ($0, "rem", "reminders", "Reads your lists; adds one when you ask.", nil) }
            case "Apple Health":
                let stravaOn = store.bridges.contains { $0.id == "strava" && $0.status == .connected }
                if let r = await HealthIngest.connectAndIngest(context: context, stravaOn: stravaOn) {
                    result = (r.added, "hlt", "things",
                             "Reads your workouts, sleep, and reflections.", healthProof(r))
                } else {
                    result = nil
                }
            case "Strava":
                // Strava's seat is the Health store filtered to workouts
                // Strava wrote — no Strava account, no OAuth (2026-07-14).
                let healthOn = store.bridges.contains { $0.id == "hlt" && $0.status == .connected }
                if let r = await HealthIngest.connectAndIngest(context: context, healthOn: healthOn,
                                                                stravaOn: true, counting: "Strava") {
                    result = (r.added, "strava", "activities",
                             "Reads the workouts Strava saves to Apple Health.", healthProof(r))
                } else {
                    result = nil
                }
            case "Apple Music":
                result = await AppleMusicIngest.connectAndIngest(context: context)
                    .map { ($0, "music", "songs", "Reads what you've played.", nil) }
            case "Contacts":
                result = await ContactsIngest.connectAndIngest(context: context)
                    .map { ($0, "contacts", "contacts", "Reads your contacts — search-only, never in your feed.", nil) }
            case "HomeKit":
                result = await HomeKitIngest.connectAndIngest(context: context)
                    .map { ($0, "homekit", "accessories", "Reads your home's accessories — search-only, never in your feed.", nil) }
            default:
                result = nil
            }
            guard let result else { completion?(false); return }
            let proof = result.proof ?? (result.n > 0
                ? String(localized: "\(result.n) \(result.noun) in")
                : String(localized: "Synced just now"))
            store.registerConnected(id: result.id, name: offer.name,
                                    proof: proof, can: [result.can])
            // No haptic here — the caller's landing toast carries it
            // (`chrome.flash(_, tone: .success)`), so a connect never buzzes
            // twice.
            completion?(true)
        }
    }

    /// Health hides read denials by design — a repeat ask that still comes
    /// back empty likely means access is off, so the proof says so instead
    /// of claiming a sync that may not have happened (honesty rule).
    private static func healthProof(_ r: HealthIngest.HealthConnectResult) -> String? {
        guard r.added == 0, r.likelyBlocked else { return nil }
        return "Connected — nothing found. Check Settings ▸ Privacy & Security ▸ Health ▸ Casberi."
    }
}
