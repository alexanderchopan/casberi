import Foundation
import SwiftData

extension ModelContext {
    /// Saves and reports the outcome instead of swallowing it (RULE,
    /// 2026-07-15). A bare `try? context.save()` was the ingestion layer's
    /// default everywhere — a failed save (disk pressure, a CloudKit
    /// merge/validation rejection) silently dropped whatever was just
    /// inserted or changed, with nothing downstream ever finding out. This
    /// at minimum logs the failure so it's observable, and returns whether
    /// it actually saved so a user-facing write (a screen reacting to a tap,
    /// not a background ingest) can correct an optimistic UI update instead
    /// of leaving a lie on screen — the same honesty rule that bans dead
    /// controls and fake status.
    @discardableResult
    func saveHonestly(file: StaticString = #fileID, line: UInt = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            NSLog("[Casberi] save failed at \(file):\(line): \(error)")
            return false
        }
    }
}
