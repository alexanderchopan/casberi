import Foundation

/// The words and the order on an account page (prd §639, 2026-09-06) — every
/// fact the chassis draws that is a RULE rather than a view. Kept
/// Foundation-only so `scripts/account-page-selftest.sh` compiles the shipped
/// judgement whole rather than a copy of it.
///
/// What lives here and why: the state line (three states, one dot); the meta
/// line (two facts joined, or none); the Activity fact ("14 today · 96 this
/// week" — and "—" when the seat is not connected, never "0 today"); the
/// reach fact (host, or host · N hosts — hosts only, no slogan); the key fact
/// (where the key lives, never a character of it); and the roster split —
/// active this week first, then Quiet — with the labels that head each half.
enum AccountPageShape {

    // MARK: - The state line

    enum State: Equatable {
        case notConnected
        case reading(lastRead: Date?)
        case paused
        case needsReconnecting(reason: String)

        /// Whether the page treats the seat as live: the act field adds, the
        /// rows are sorted, the readers row is meaningful.
        var connected: Bool {
            switch self {
            case .notConnected: false
            case .reading, .paused, .needsReconnecting: true
            }
        }

        var needsReconnecting: Bool {
            if case .needsReconnecting = self { return true }
            return false
        }
    }

    /// The line under the name, dot excluded (the view draws the dot in the
    /// line's own tone). `now` is injectable so the harness can pin "8m ago".
    static func stateLine(_ state: State, now: Date = .now) -> String {
        switch state {
        case .notConnected:
            return String(localized: "Not connected")
        case .reading(let lastRead):
            guard let lastRead else { return String(localized: "Reading") }
            return String(localized: "Reading · \(ago(lastRead, now: now))")
        case .paused:
            return String(localized: "Paused")
        case .needsReconnecting(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return String(localized: "Needs reconnecting") }
            return String(localized: "Needs reconnecting · \(trimmed)")
        }
    }

    /// "8m ago", "3h ago", "2d ago", "just now" — the compact relative form
    /// a state line has room for. Past a week it says the date, because
    /// "41d ago" is a number nobody converts.
    static func ago(_ date: Date, now: Date = .now) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return String(localized: "just now") }
        if s < 3600 { return String(localized: "\(Int(s / 60))m ago") }
        if s < 86_400 { return String(localized: "\(Int(s / 3600))h ago") }
        if s < 7 * 86_400 { return String(localized: "\(Int(s / 86_400))d ago") }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - The meta line

    /// The small tertiary line under the state — only the facts that are
    /// KNOWN, joined with a middle dot, nil when none is. "Connected Aug 12 ·
    /// key expires in 30 days" / "Last read Sep 4 · 2 days of activity missing".
    static func metaLine(connectedAt: Date?, keyExpires: Date?, lastRead: Date?,
                         missingSince: Date?, now: Date = .now) -> String? {
        var parts: [String] = []
        if let connectedAt {
            parts.append(String(localized: "Connected \(day(connectedAt))"))
        } else if let lastRead {
            parts.append(String(localized: "Last read \(day(lastRead))"))
        }
        if let keyExpires {
            let days = max(0, Int((keyExpires.timeIntervalSince(now) / 86_400).rounded(.up)))
            parts.append(days == 0
                         ? String(localized: "key expires today")
                         : String(localized: "key expires in \(days) days"))
        }
        if let missingSince {
            let days = max(1, Int((now.timeIntervalSince(missingSince) / 86_400).rounded(.down)))
            parts.append(days == 1
                         ? String(localized: "1 day of activity missing")
                         : String(localized: "\(days) days of activity missing"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - The facts on the plain rows

    /// "14 today · 96 this week". Not connected reads "—": a seat that reads
    /// nothing has no count, and "0 today" would be a number about nothing.
    static func activityFact(today: Int, week: Int, connected: Bool) -> String {
        guard connected else { return "—" }
        return String(localized: "\(today) today · \(week) this week")
    }

    /// The hosts and only the hosts. One host reads bare; more read as the
    /// first plus the count, because a row has room for one address.
    static func reachFact(hosts: [String]) -> String {
        let clean = hosts.filter { $0.contains(".") }
        guard let first = clean.first else { return "—" }
        guard clean.count > 1 else { return first }
        return String(localized: "\(first) · \(clean.count) hosts")
    }

    /// Where the key lives and the verb that changes it — NEVER a character
    /// of the key. The expiry replaces the place when a provider reports one,
    /// because the date is then the fact that matters.
    static func keyFact(device: String, expires: Date?) -> String {
        if let expires {
            return String(localized: "Expires \(day(expires)) · Replace")
        }
        return String(localized: "Keychain, \(device) · Replace")
    }

    // MARK: - The roster

    /// One watched account, repo, feed or channel as the chassis needs it.
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        /// "casts, channels · 27 this week" — composed by the caller from
        /// what its bridge knows; `weekCount` is what SORTS it.
        let subline: String
        let weekCount: Int
        /// Produced something since the page was last looked at — the ring.
        let hasNew: Bool
        /// The person's own account — the "You" pill.
        let isYou: Bool
        let avatarURL: String?
        /// **A wallet row wears its own face (prd §690).** The roster row's
        /// fallback is the SEAT's icon, which is right for a Hugging Face model
        /// or a Radicle repo and wrong for an address — every row on the
        /// Wallet's page wore the Wallet app icon seventeen times over. Set,
        /// it draws `WalletFace` for the address; nil keeps the seat's icon.
        var faceAddress: String? = nil
        /// **Followed, or only named (prd §690, §169's two tiers).** The Wallet's
        /// directory lists both, and the page's "Watching · N" counted all
        /// seventeen when four were watched. Default true so the other 23
        /// rosters, which list only what they follow, change nothing.
        var watched: Bool = true
    }

    /// Active this week first, then the quiet rest; each half keeps the
    /// caller's order (its store's own), so two rows with the same count
    /// never swap between body passes.
    static func split(_ rows: [Row]) -> (active: [Row], quiet: [Row]) {
        (rows.filter { $0.weekCount > 0 }, rows.filter { $0.weekCount <= 0 })
    }

    /// **ONE bar, and the bar says which job it is doing** (user ruling
    /// 2026-09-06). The field is first because adding is first, but a person
    /// with forty repos or a hundred and forty accounts also wants to FIND one
    /// they already watch — and a second search field under the roster was
    /// tried and withdrawn as two controls for one line of thinking. So the
    /// placeholder names both jobs in the order they happen, and the RESULTS
    /// are what tell them apart: matches from the roster under "Yours", new
    /// ones under the account's own name.
    ///
    /// `what` is the bridge's own noun with its article ("a repo", "someone",
    /// "a feed") — never a bare plural, which reads as a category header
    /// rather than as the thing you are about to type.
    static func findPlaceholder(_ what: String) -> String {
        String(localized: "Find \(what), or search yours")
    }

    /// The label over roster rows matching what is typed. It replaces
    /// "Watching · N" while a query stands, because the count under it is the
    /// match count and a label saying 140 over three rows is a lie.
    static func yoursLabel(_ count: Int) -> String {
        String(localized: "Yours · \(count)")
    }

    /// The label over the network's own hits — "On GitHub", "On Farcaster".
    /// Named for the service rather than "New", which a first read takes as a
    /// state (unread) rather than as a place.
    static func onLabel(_ name: String) -> String {
        String(localized: "On \(name)")
    }

    /// Roster rows whose title matches a typed query, case- and
    /// diacritic-insensitively. Empty query returns every row — the caller
    /// draws the whole list, unfiltered, which is the page at rest.
    static func matches(_ rows: [Row], query: String) -> [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func watchingLabel(_ count: Int) -> String {
        String(localized: "Watching · \(count)")
    }

    /// The named-only tier's header, beside "Watching · N".
    static func namedLabel(_ count: Int) -> String {
        String(localized: "Named · \(count)")
    }

    static func quietLabel(_ count: Int) -> String {
        String(localized: "Quiet · \(count)")
    }

    /// The subline while the seat needs reconnecting: every row reads
    /// "paused", because nothing is being read for any of them.
    static let pausedSubline = String(localized: "paused")

    /// "casts, channels · 27 this week" / "posts · quiet this week".
    static func subline(nouns: String, weekCount: Int) -> String {
        weekCount > 0
            ? String(localized: "\(nouns) · \(weekCount) this week")
            : String(localized: "\(nouns) · quiet this week")
    }
}
