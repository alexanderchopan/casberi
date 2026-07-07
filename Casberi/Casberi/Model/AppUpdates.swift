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
        Entry(date: "2026-07-05", line: "The Apps tile now shows all 16 apps, and picking your look is simpler — one Background row, with your own photo as an option. Answers stay free on your iPhone, so the Balance screen is gone. On iPhones with Apple Intelligence, answers are now written on-device from your things — a lookup like ‘find my work notes’ lists them, while an open question like ‘what’s my week’ gets a short written summary that types itself in; every other iPhone keeps the built-in search, and the model warms up when you open the app so the first answer comes a little sooner. The Support tile is gone — the version lives on Updates. Account › Data now leads with your numbers and shows each privacy promise in its own color — not a settings list; Delete everything also clears your recordings and photo, and Export carries everything, provenance included. Your connected apps now light up in their own colors on the Apps tile. Connection and Privacy got the same colorful, honest treatment, and the Subscription tile is gone until there's something to charge for."),
        Entry(date: "2026-07-04", line: "You can now connect Calendar and Reminders, record voice notes, and approve or deny what your agents ask."),
        Entry(date: "2026-07-03", line: "First launch now walks you through the app."),
    ]

    static var latest: String { entries.first?.line ?? "You're on the latest build." }
}
