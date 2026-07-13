import SwiftUI

/// The + tray's tool launcher (user, 2026-07-12) — a finite, fixed set of jumps
/// to the person's OWN tools, for when something in the app sparks "I want to do
/// that." Nothing creates in Casberi: every tile opens an app (the ruling —
/// people create in their own tools). The order is grouped by job — note ·
/// communicate · schedule · look up / think — and STAYS PUT: a launcher's whole
/// value is that the tile never moves, so the thumb learns where it is (never
/// alphabetized, never reordered by use).
///
/// The Apple targets (Notes/Messages/Mail/Calendar/Reminders) and Search web
/// are always offered. The third-party apps (ChatGPT/Claude) open their APP by
/// URL scheme and are `probe`-gated — a tile appears only when the app is
/// installed (opening a website instead of the app is worse than no tile;
/// user, 2026-07-12), so its scheme must be listed in `LSApplicationQueriesSchemes`.
struct QuickTool: Identifiable {
    let id: String
    let label: String
    let symbol: String
    /// One brand color; the tile derives a tinted fill + glyph from it, so both
    /// modes read (mirrors BridgeIcon's fallback).
    let tint: Color
    let url: URL
    /// True = show only when `url`'s app is installed (canOpenURL). The tray
    /// filters these out otherwise, so the tile never falls back to a website.
    let probe: Bool

    static let all: [QuickTool] = [
        t("note",     "Note",       "note.text",       "#E8A400", "mobilenotes://"),
        t("message",  "Message",    "message.fill",    "#1FA855", "sms:"),
        t("email",    "Email",      "envelope.fill",   "#2E6FD6", "mailto:"),
        t("event",    "Event",      "calendar",        "#E5372B", "calshow://"),
        t("reminder", "Reminder",   "checklist",       "#E8890C", "x-apple-reminderkit://"),
        t("web",      "Search web", "magnifyingglass", "#1C6DD0", "https://www.google.com"),
        t("chatgpt",  "ChatGPT",    "bubble.left",     "#0F8A6B", "chatgpt://", probe: true),
        t("claude",   "Claude",     "sparkles",        "#C4633B", "claude://",  probe: true),
    ]

    private static func t(_ id: String, _ label: String, _ symbol: String,
                          _ hex: String, _ url: String, probe: Bool = false) -> QuickTool {
        QuickTool(id: id, label: label, symbol: symbol,
                  tint: Color.fixed(hex), url: URL(string: url)!, probe: probe)
    }
}
