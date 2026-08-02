import Foundation

/// The living changelog — high-level synthesis of what changed, newest first.
/// The Updates tile wears the latest line; the detail sheet holds the recent
/// history. Maintained with every build batch (facts, Bob's words, no jargon).
enum AppUpdates {
    struct Entry: Identifiable {
        let date: String     // yyyy-mm-dd, display-formatted in the sheet
        let line: String
        var id: String { date + line }
    }

    /// Newest first. ONE entry per day (ruling 2026-07-05) — a day's later
    /// batches fold into that day's line. Plain words: say what you can now
    /// do or see. No metaphors, no app-speak.
    static let entries: [Entry] = [
        Entry(date: "2026-07-05", line: "Answers are now written on-device from your things. Apps shows all 16 apps, in their own colors. Data leads with your numbers; Delete everything now clears recordings and photos too."),
        Entry(date: "2026-07-04", line: "Connect Calendar and Reminders, record voice notes, and approve or deny what your agents ask."),
        Entry(date: "2026-07-03", line: "First launch now walks you through the app."),
    ]

    static var latest: String { entries.first?.line ?? "You're on the latest build." }
}
