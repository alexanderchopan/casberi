import SwiftUI

/// The composer's "take it with you" chips (user, 2026-07-16 — replacing the
/// 2026-07-12 tool-tile grid). The grid's logic was "oh, I need to…" jumps to
/// your own tools, but the jumps carried nothing — a blank Notes list or an
/// empty Google page duplicates the home screen — and the tiles read as
/// "what are these for?". The chips keep the ruling (nothing creates in
/// Casberi; people create in their own tools) and fix the mechanics: they
/// appear once you've TYPED, and the text goes WITH you.
///
/// Only destinations that can actually carry the text earn a chip (honesty
/// rule): Mail and Messages take it in the compose body, Search takes it as
/// the query. Notes has no compose URL — its chip copies first and the flash
/// says exactly that, so the jump is never silently blank. The old grid's
/// blank jumps (Calendar, Reminders, ChatGPT, Claude) died with it.
struct TakeTool: Identifiable {
    let id: String
    let label: String
    let glyph: String
    /// True = the app has no text-carrying URL; the chip puts the text on the
    /// clipboard before jumping and the flash says so.
    let copiesFirst: Bool
    /// Builds the destination URL around the typed text.
    let makeURL: (String) -> URL?

    /// Grouped by job — note · message · mail · look up — and STAYS PUT
    /// (never reordered), same law the tile grid lived by.
    static let all: [TakeTool] = [
        TakeTool(id: "note", label: "Notes", glyph: "note.text",
                 copiesFirst: true) { _ in
            URL(string: "mobilenotes://")
        },
        TakeTool(id: "message", label: "Messages", glyph: "message",
                 copiesFirst: false) { text in
            var parts = URLComponents()
            parts.scheme = "sms"
            parts.queryItems = [URLQueryItem(name: "body", value: text)]
            return parts.url
        },
        TakeTool(id: "email", label: "Mail", glyph: "envelope",
                 copiesFirst: false) { text in
            var parts = URLComponents()
            parts.scheme = "mailto"
            parts.queryItems = [URLQueryItem(name: "body", value: text)]
            return parts.url
        },
        TakeTool(id: "web", label: "Google", glyph: "magnifyingglass",
                 copiesFirst: false) { text in
            var parts = URLComponents(string: "https://www.google.com/search")
            parts?.queryItems = [URLQueryItem(name: "q", value: text)]
            return parts?.url
        },
    ]
}
