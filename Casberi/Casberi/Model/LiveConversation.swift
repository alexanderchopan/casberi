import Foundation

/// A direct-message conversation read off a LIVE session (prd §1244) — X's
/// `dm/inbox_initial_state.json` and Instagram's `direct_v2/inbox/`, one shape
/// for both. The PURE half: Foundation only, compiled whole by
/// `scripts/live-messages-selftest.sh`; the landing half is
/// `LiveMessagesLanding`.
///
/// **One thing per CONVERSATION, never per message** — the X and Instagram
/// imports' shape (both deleted, prd §1579) and their reason: a message alone is a fragment with no subject, a conversation has
/// people, a span and a subject. The transcript keeps the imports' numbers
/// too, so a live conversation and an imported one hold the same amount.
///
/// **A live read sees the newest few messages, so the transcript GROWS.** The
/// inbox hands over the last handful per conversation; each pass appends the
/// lines newer than the row's own `capturedAt` (the newest line it holds) and
/// re-clamps. Nothing older than the first read is ever claimed.
struct LiveConversation: Equatable {
    struct Line: Equatable {
        /// The network's own message id — the dedupe within one read.
        var id: String
        var at: Date
        /// Labelled and on one line: "You: …", "Ana: …".
        var text: String
    }

    /// The network's conversation id — the ref's tail.
    var id: String
    var title: String
    /// The other person on a one-to-one, nil for a group.
    var handle: String?
    var avatar: String?
    var isGroup: Bool
    /// Oldest first.
    var lines: [Line]
}

enum LiveMessages {
    /// The seats with a live messages read.
    enum Seat: String, CaseIterable {
        case x
        case instagram
        /// Through TDLib signed in as you, not a web session (prd §1575).
        case telegram

        /// Off by default, per seat (prd §1244 over §310): private
        /// correspondence enters the corpus only because the person turned
        /// this on, on that seat's own page.
        var defaultsKey: String { "\(rawValue).live.readMessages" }
    }

    static func reads(_ seat: Seat, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: seat.defaultsKey)
    }

    /// `SnapchatImport`'s numbers, which both imports already share.
    static let transcriptLines = 60
    static let transcriptBytes = 4_000

    struct Merge: Equatable {
        var content: String
        var newest: Date
        var count: Int
        /// How many lines this read added.
        var appended: Int
    }

    /// The lines newer than `newest` onto a stored transcript, clamped. nil
    /// when nothing is newer — the row stays as it is.
    ///
    /// `newest` is the row's `capturedAt`, which is the newest line it holds;
    /// a first landing passes nil for all three. `count` is the stored
    /// `messageCount`, the whole conversation as far as this app has seen it,
    /// never the clamped slice.
    static func merge(content: String?, newest: Date?, count: Int?,
                      lines: [LiveConversation.Line]) -> Merge? {
        let fresh = lines
            .filter { line in newest.map { line.at > $0 } ?? true }
            .sorted { $0.at < $1.at }
        guard let last = fresh.last else { return nil }
        let stored = (content ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return Merge(
            content: clamp(stored + fresh.map(\.text)),
            newest: last.at,
            count: (count ?? stored.count) + fresh.count,
            appended: fresh.count)
    }

    /// The newest `transcriptLines`, inside `transcriptBytes` — the imports'
    /// clamp, character for character.
    static func clamp(_ lines: [String]) -> String {
        var transcript = lines.suffix(transcriptLines).joined(separator: "\n")
        if transcript.count > transcriptBytes {
            transcript = String(transcript.suffix(transcriptBytes))
        }
        return transcript
    }

    /// One message as a transcript line. A message's own line breaks become
    /// spaces: the transcript is one message per line, and the merge splits
    /// it back on them.
    static func line(sender: String?, isMe: Bool, text: String) -> String {
        let flat = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if isMe { return String(localized: "You: \(flat)") }
        guard let sender, !sender.isEmpty else { return flat }
        return "\(sender): \(flat)"
    }

    /// "Messages with Ana", "Messages with Ana, Ben and 2 more".
    static func title(names: [String]) -> String {
        let named = names.filter { !$0.isEmpty }
        guard let first = named.first else { return String(localized: "Messages") }
        switch named.count {
        case 1: return String(localized: "Messages with \(first)")
        case 2: return String(localized: "Messages with \(first) and \(named[1])")
        default:
            return String(localized: "Messages with \(first), \(named[1]) and \(named.count - 2) more")
        }
    }

    /// An epoch in whatever magnitude the network sent — seconds,
    /// milliseconds (X) or microseconds (Instagram) — as a String or a
    /// number. nil for anything else, never a guessed now.
    static func date(epoch any: Any?) -> Date? {
        let raw: Double?
        if let s = any as? String { raw = Double(s) }
        else if let n = any as? NSNumber { raw = n.doubleValue }
        else { raw = nil }
        guard let raw, raw > 0 else { return nil }
        if raw >= 1e14 { return Date(timeIntervalSince1970: raw / 1_000_000) }
        if raw >= 1e11 { return Date(timeIntervalSince1970: raw / 1_000) }
        return Date(timeIntervalSince1970: raw)
    }

    /// A numeric id as a String, whichever way it arrived.
    static func idString(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }
}
