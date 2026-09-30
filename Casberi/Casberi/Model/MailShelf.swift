import Foundation

/// The mail rooms' tiles: All · From · Subject, on the template every room
/// scopes with, the music rooms' shape (prd §995). Gmail and iCloud Mail share
/// one face (`.gmail`), so they share these tiles.
///
/// **A tile here is an ORDER, not a filter**, as in the music rooms. All is
/// the room as it was — the newest mail, what is waiting on you, then days.
/// Subject is every mail A–Z by subject under letter headers, a reply filed
/// with the mail it answers. From is an A–Z list of SENDERS, each with how
/// many mails it holds; one opens in place, its mail newest first under it,
/// and its name as a row that leads back.
///
/// Foundation-only, so `scripts/mail-shelf-selftest.sh` compiles it whole
/// (with `MusicShelf.swift`, whose letters and A–Z order it shares); the
/// glyphs are `ScopeTileGlyphs.swift`'s.
enum MailScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    // A–Z with All first (prd §995), so the room opens on All.
    case all, from, subject

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return String(localized: "All")
        case .from:    return String(localized: "From")
        case .subject: return String(localized: "Subject")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .all:     return String(localized: "Your mail, newest first")
        case .from:    return String(localized: "Every sender, A to Z")
        case .subject: return String(localized: "Every mail by subject, A to Z")
        }
    }
}

enum MailShelf {

    /// One sender: the name as first met, the key the room files under, and
    /// how many mails. The key is the ADDRESS when the row holds one, so two
    /// people who share a display name are two senders, and one person whose
    /// mail client spelt their name two ways is one.
    struct Sender: Hashable, Sendable {
        let key: String
        let name: String
        let count: Int
    }

    /// The key one mail files under: its address, else its folded name, else
    /// nil (a mail that names no sender files nowhere).
    static func senderKey(name: String?, address: String?) -> String? {
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !address.isEmpty { return address }
        guard let name = displayName(name) else { return nil }
        return MusicShelf.key(name)
    }

    /// What the sender list draws: "Uma Patel" out of "Uma Patel
    /// <uma@studio.example>" (an older row's "From …" line carries both),
    /// the address when that is all there is.
    static func displayName(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let open = s.firstIndex(of: "<"), s.hasSuffix(">") {
            let name = s[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            s = name.isEmpty ? String(s[s.index(after: open)..<s.index(before: s.endIndex)]) : name
        }
        return s.isEmpty ? nil : s
    }

    /// Every sender, counted; rows arrive newest first, so a sender's name is
    /// the one on their newest mail.
    static func senders(_ rows: [(name: String?, address: String?)]) -> [Sender] {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        var order: [String] = []
        for row in rows {
            guard let key = senderKey(name: row.name, address: row.address),
                  let name = displayName(row.name) ?? row.address else { continue }
            if names[key] == nil { names[key] = name; order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { Sender(key: $0, name: names[$0] ?? $0, count: counts[$0] ?? 0) }
    }

    /// The subject a mail sorts by: the reply and forward prefixes off, so
    /// "Re: Lease" stands beside "Lease", the way Mail sorts by subject.
    static func subjectKey(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while let colon = s.firstIndex(of: ":") {
            let head = s[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard replyPrefixes.contains(head) else { break }
            s = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return s.isEmpty ? subject : s
    }

    /// Reply and forward markers as mail clients write them, English and the
    /// commonest others (Outlook's German "AW"/"WG", Nordic "SV", French "TR").
    private static let replyPrefixes: Set<String> = ["re", "fwd", "fw", "aw", "wg", "sv", "tr"]
}
