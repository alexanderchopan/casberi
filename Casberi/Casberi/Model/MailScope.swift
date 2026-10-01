import Foundation

/// The mail rooms' tiles (prd §1019): All · Attachments · New, under the
/// newest mail's cover, in Gmail and iCloud Mail alike. One scope file for
/// both because they are one room shape over one IMAP ingest (`MailBridge`),
/// and a tile set that reached one and not the other would be two rooms
/// pretending to be one (user: "I only wanna add those to Apple Mail if we
/// could do the same to Gmail").
///
/// Attachments is the one fact about a mail the ingest holds beyond its
/// envelope: `MailMIME` names what came with it, and `MailBridge` writes the
/// names as the row's `Attached` fact. No unread tile, no flagged tile: the
/// client fetches neither flag, and the 2026-07-06 ruling draws no unread
/// badge anywhere.
///
/// New is a VERB, like the Notes, Reminders and Calendar rooms': it never
/// lights, and its tap composes in the mail app `SourceActions` names for the
/// seat — Gmail's own when installed, else the system `mailto:`. It replaces
/// the "New email" compose row, which stood above the lead at the top of the
/// screen (§752, named in §911 as the one control left there).
///
/// Foundation-only, like every scope enum, so a harness can compile it whole;
/// the glyphs are `ScopeTileGlyphs.swift`'s.
enum MailScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, attachments, new

    var id: String { rawValue }

    /// The two seats this room shape serves. Spelled once, here: the feed's
    /// filter, its tiles, its compose-row exclusion and the held-lead gate all
    /// ask this set.
    static let rooms: Set<String> = ["Gmail", "iCloud Mail"]

    /// The label `MailBridge` writes on the attachment fact, read back by the
    /// Attachments tile. One spelling for the write and the read, so the tile
    /// cannot drift from the ingest. Localized at write time like every fact
    /// label, so a mail landed under one language and read under another
    /// stands under All alone — stated, not hidden.
    static var attachedLabel: String { String(localized: "Attached") }

    var label: String {
        switch self {
        case .all:         return String(localized: "All")
        case .attachments: return String(localized: "Attachments")
        case .new:         return String(localized: "New")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .all:         return String(localized: "Your recent mail")
        case .attachments: return String(localized: "Mail that came with a file")
        case .new:         return String(localized: "Write an email in your mail app")
        }
    }

    /// What the held lead says when this scope holds nothing. One clause
    /// (prd §799).
    var emptyHeadline: String {
        switch self {
        case .all, .new:   return String(localized: "Nothing in your inbox.")
        case .attachments: return String(localized: "Nothing attached.")
        }
    }

    /// The tiles that SCOPE the list; New is a verb and never stands.
    var isVerb: Bool { self == .new }

    /// Whether a mail stands under this scope, given its fact labels. A mail
    /// landed before the ingest named attachments (2026-08-14) carries no
    /// such fact and stands under All alone.
    func allows(factLabels: [String]) -> Bool {
        switch self {
        case .all, .new:   return true
        case .attachments: return factLabels.contains(Self.attachedLabel)
        }
    }
}
