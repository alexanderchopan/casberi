import SwiftUI
import SwiftData

/// One connect path, shared by the catalog, the app detail page, and the Apps
/// list. Connect ends in proof — the wired bridges (Photos/Calendar/Reminders)
/// run their real system-framework path and the permission ask arrives in
/// context; everything else isn't wired yet and says so.
@MainActor
enum BridgeConnect {
    static func connect(_ offer: BridgeCatalog.Offer, store: BridgeStore, context: ModelContext) {
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
            default:
                result = nil
            }
            guard let result else { return }
            let proof = result.n > 0 ? "\(result.n) \(result.noun) in" : "Synced just now"
            if let existing = store.bridges.first(where: { $0.name == offer.name }) {
                store.reconnect(existing.id, proof: proof)
            } else {
                store.bridges.append(BridgeApp(
                    id: result.id, name: offer.name, status: .connected,
                    statusLine: proof, can: [result.can]
                ))
            }
            DSHaptic.success()
        }
    }
}
