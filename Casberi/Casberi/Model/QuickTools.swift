import SwiftUI

/// The composer's "Send to" chips (user rulings 2026-07-16). Three moves got
/// here: the 2026-07-12 tool-tile grid (blank jumps, read as "what are these
/// for?"), then "Open in" chips (unclear that the TEXT travels), then this —
/// "Send to" + app names, because what you typed is either a question (the
/// Ask button's job) or a FACT that belongs in another app (a reminder, an
/// event, a message).
///
/// Ruling: we NEVER write into another app — every chip jumps (user,
/// 2026-07-16: "no matter what we should jump, we don't write"). The text
/// rides the jump where a URL can carry it (Messages/Mail compose body,
/// Google query, Calendar opens AT a detected date via calshow's timestamp);
/// where it can't (Reminders, Notes, Calendar's text itself), the chip
/// copies first and the flash says so — never a silent blank jump. The row
/// STAYS PUT (never reordered) — a detected date adds a receipt line under
/// the field, not a shuffle.
struct TakeTool: Identifiable {
    let id: String
    let label: String
    let glyph: String
    /// True = the app can't take the text by URL; the chip puts it on the
    /// clipboard before jumping and the flash says so.
    let copiesFirst: Bool
    /// Builds the destination URL around the typed text and the date
    /// NSDataDetector found in it (nil when none).
    let makeURL: (String, Date?) -> URL?

    static let all: [TakeTool] = [
        TakeTool(id: "reminder", label: "Reminders", glyph: "checklist",
                 copiesFirst: true) { _, _ in
            URL(string: "x-apple-reminderkit://")
        },
        TakeTool(id: "event", label: "Calendar", glyph: "calendar",
                 copiesFirst: true) { _, date in
            // calshow: takes seconds since the reference date — with a
            // detected time the jump lands ON that day, not on today.
            if let date {
                return URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))")
            }
            return URL(string: "calshow://")
        },
        TakeTool(id: "note", label: "Notes", glyph: "note.text",
                 copiesFirst: true) { _, _ in
            URL(string: "mobilenotes://")
        },
        TakeTool(id: "message", label: "Messages", glyph: "message",
                 copiesFirst: false) { text, _ in
            var parts = URLComponents()
            parts.scheme = "sms"
            parts.queryItems = [URLQueryItem(name: "body", value: text)]
            return parts.url
        },
        TakeTool(id: "email", label: "Mail", glyph: "envelope",
                 copiesFirst: false) { text, _ in
            var parts = URLComponents()
            parts.scheme = "mailto"
            parts.queryItems = [URLQueryItem(name: "body", value: text)]
            return parts.url
        },
        TakeTool(id: "web", label: "Google", glyph: "magnifyingglass",
                 copiesFirst: false) { text, _ in
            var parts = URLComponents(string: "https://www.google.com/search")
            parts?.queryItems = [URLQueryItem(name: "q", value: text)]
            return parts?.url
        },
    ]
}
