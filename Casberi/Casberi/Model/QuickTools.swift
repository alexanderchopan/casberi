import SwiftUI

/// The + tray's tool launcher (user, 2026-07-12) — a finite, fixed set of jumps
/// to the person's OWN tools, for when something in the app sparks "I want to do
/// that." Nothing creates in Casberi: every tile opens an app (the ruling —
/// people create in their own tools). The order is grouped by job — note ·
/// communicate · schedule · look up / think — and STAYS PUT: a launcher's whole
/// value is that the tile never moves, so the thumb learns where it is (never
/// alphabetized, never reordered by use).
///
/// None is a dead control: the Apple targets (Notes/Messages/Mail/Calendar/
/// Reminders) are always present, and ChatGPT/Claude/Search use https so they
/// open the app when installed and the website otherwise — always something.
struct QuickTool: Identifiable {
    let id: String
    let label: String
    let symbol: String
    /// One brand color; the tile derives a tinted fill + glyph from it, so both
    /// modes read (mirrors BridgeIcon's fallback).
    let tint: Color
    let url: URL

    static let all: [QuickTool] = [
        t("note",     "Note",       "note.text",       "#E8A400", "mobilenotes://"),
        t("message",  "Message",    "message",         "#1FA855", "sms:"),
        t("email",    "Email",      "envelope",        "#2E6FD6", "mailto:"),
        t("event",    "Event",      "calendar",        "#E5372B", "calshow://"),
        t("reminder", "Reminder",   "checklist",       "#E8890C", "x-apple-reminderkit://"),
        t("web",      "Search web", "magnifyingglass", "#1C6DD0", "https://www.google.com"),
        t("chatgpt",  "ChatGPT",    "bubble.left",     "#0F8A6B", "https://chatgpt.com"),
        t("claude",   "Claude",     "sparkles",        "#C4633B", "https://claude.ai"),
    ]

    private static func t(_ id: String, _ label: String, _ symbol: String,
                          _ hex: String, _ url: String) -> QuickTool {
        QuickTool(id: id, label: label, symbol: symbol,
                  tint: Color.fixed(hex), url: URL(string: url)!)
    }
}
