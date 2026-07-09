import SwiftUI
import SwiftData

/// One connect path, shared by the catalog, the app detail page, and the Apps
/// list. Connect ends in proof — the wired bridges (Photos/Calendar/Reminders)
/// run their real system-framework path and the permission ask arrives in
/// context; everything else isn't wired yet and says so.
@MainActor
enum BridgeConnect {
    static func connect(_ offer: BridgeCatalog.Offer, store: BridgeStore,
                        context: ModelContext,
                        chrome: ShellChrome? = nil,
                        completion: ((Bool) -> Void)? = nil) {
        Task {
            let result: (n: Int, id: String, noun: String, can: String)?
            switch offer.name {
            case "Photos":
                result = await ScreenshotIngest.connectAndIngest(context: context)
                    .map { ($0, "pho", "screenshots", "Reads screenshots you take.") }
            case "Calendar":
                result = await ScheduleIngest.connectCalendar(context: context)
                    .map { ($0, "cal", "events", "Reads your events; adds one when you ask.") }
            case "Reminders":
                result = await ScheduleIngest.connectReminders(context: context)
                    .map { ($0, "rem", "reminders", "Reads your lists; adds one when you ask.") }
            case "Apple Health":
                result = await HealthIngest.connectAndIngest(context: context)
                    .map { ($0, "hlt", "workouts", "Reads your workouts.") }
            case "Apple Music":
                result = await AppleMusicIngest.connectAndIngest(context: context)
                    .map { ($0, "music", "songs", "Reads what you've played.") }
            default:
                result = nil
            }
            // Honesty rule (no dead controls): a connect that reaches nothing —
            // access denied, framework unavailable, no subscription — used to
            // return in silence, which reads as a broken button. Say so.
            guard let result else {
                DSHaptic.error()
                chrome?.flash("Couldn't connect \(offer.name) — access was denied or it's unavailable.")
                completion?(false)
                return
            }
            let proof = result.n > 0 ? "\(result.n) \(result.noun) in" : "Synced just now"
            store.registerConnected(id: result.id, name: offer.name,
                                    proof: proof, can: [result.can])
            DSHaptic.success()
            chrome?.flash(result.n > 0
                ? "\(offer.name) connected — \(result.n) \(fullNoun(result.noun, result.n)) landed"
                : "\(offer.name) connected — nothing new yet")
            completion?(true)
        }
    }

    /// The connected strip shows a terse proof ("3 pho in"); the toast speaks
    /// in full ("3 screenshots landed"), so the outcome reads as a sentence.
    private static func fullNoun(_ noun: String, _ n: Int) -> String {
        let word: String
        switch noun {
        case "pho":   word = "screenshot"
        case "cal":   word = "event"
        case "rem":   word = "reminder"
        case "hlt":   word = "workout"
        case "music": word = "song"
        default:      word = noun
        }
        return n == 1 ? word : word + "s"
    }
}
