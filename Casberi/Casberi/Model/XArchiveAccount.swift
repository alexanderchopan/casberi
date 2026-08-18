import Foundation

/// THE HALF OF AN X ARCHIVE THAT ISN'T POSTS (2026-08-18, prd §396).
///
/// `XArchiveImport` reads what you wrote and what you liked. This reads the
/// three files beside them that nothing had ever opened, and it is deliberately
/// a SEPARATE type: every function here is pure over Foundation values, so
/// `scripts/x-selftest.sh` compiles this file WHOLE and unmodified — the only
/// proof these readings are right, since no real X archive has ever been opened
/// on the machine any of this was written on. Everything touching `Thing` stays
/// in `XArchiveImport`, exactly the way `XRoom` and `XRoomSource` split.
///
/// ## 1. `connected-application.js` — which apps can act as you
///
/// The strongest thing in the export that isn't your writing, and the one an X
/// account of any age is most likely to be wrong about. An OAuth grant made in
/// 2013 to an app that shut down in 2015 is still a live grant: it sits in a
/// settings page nobody opens, and X's own product surfaces it nowhere else.
/// So this is `FarcasterSigners` (§239) with a different wire — an INVENTORY,
/// read and shown, with a door to the page that revokes. Nothing here revokes
/// anything, and nothing here can: the archive is a file on a disk, and the
/// grant lives on X's servers.
///
/// **The reach ladder is what the row leads with, and it is never guessed.**
/// `Reach.unknown` is a real answer with its own sentence — an export whose
/// permission field we don't recognise says the app is connected and stops
/// there, because "can post as you" printed over a read-only app is exactly
/// the fake status §83 bans, in the one place somebody would act on it.
///
/// ## 2. `account.js` — the day you joined
///
/// One field (`createdAt`) in a file this importer has read for its `username`
/// since the seat shipped. It lands as a single dated row, so the room's oldest
/// entry is the account's own beginning rather than whichever post happened to
/// survive.
///
/// ## 3. `screen-name-change.js` — who you used to be
///
/// A long-lived account has had names. This matters past nostalgia: a reply
/// from 2016 was written by whoever you were called in 2016, and `XRoom`'s
/// years say nothing about it. Each change is a dated event, which is exactly
/// what a thing is — no tally, no aggregate.
///
/// ## What every parse here promises
///
/// A missing file, a renamed key, or a shape this build doesn't recognise
/// yields NOTHING — never a partial guess. Each reader takes the entries the
/// archive's own `parseArray` handed back and returns only the rows it could
/// read whole, so a drifted export costs the feature and never the room.
///
/// **UNMEASURED against a real archive**, like every other line that reads one
/// of these files. Paths and field names are doc-derived, both known wrapper
/// shapes are tried (`{"connectedApplication": {…}}` and the bare object, the
/// same two eras `landTweets` already handles), and both date shapes are tried
/// for every timestamp.
enum XArchiveAccount {

    // MARK: - Dates
    //
    // Both parsers live here rather than in `XArchiveImport` (they moved on
    // 2026-08-18) for one reason: this file is compiled whole by the harness
    // and that one is not, so a date shape proven here is proven for every
    // reader of this export. Two copies of a date parser drift, and a drifted
    // one dates a decade of somebody's posts to 1970 while every row still
    // renders perfectly.

    /// X's own post stamp: `"Wed Mar 21 20:50:14 +0000 2006"`.
    ///
    /// Pinned to POSIX and UTC: the month and weekday names in this field are
    /// always English regardless of the person's locale, and a device formatter
    /// would fail to parse them for anyone whose phone isn't in English.
    static let tweetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return f
    }()

    /// ISO 8601 (`2019-04-16T12:34:56.000Z`) — the shape X stamps a DM, a
    /// connected app's approval and a rename with, and NOT the shape it stamps
    /// a tweet with.
    static func isoStamp(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    /// Either shape, whichever the field turns out to hold.
    ///
    /// Both are tried for EVERY timestamp outside the tweet files, because the
    /// one measured fact about this export's date handling is that it is not
    /// consistent: `tweets.js` uses the Twitter format, `direct-messages.js`
    /// uses ISO, and nothing documents which of the two the smaller files use.
    /// Trying both costs one failed parse and removes an entire class of
    /// silently-undated row.
    static func stamp(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return isoStamp(raw) ?? tweetDateFormatter.date(from: raw)
    }

    // MARK: - Connected applications

    /// What a grant lets an app DO, in the only four grades this file is
    /// willing to state.
    ///
    /// Ordered by how much it can cost you, which is also the order the room
    /// ranks them in. `unknown` is LAST rather than first, deliberately: it is
    /// the least alarming honest answer, not the most.
    enum Reach: Int, Comparable, Equatable {
        case unknown = 0
        case read = 1
        case write = 2
        case messages = 3

        static func < (a: Reach, b: Reach) -> Bool { a.rawValue < b.rawValue }
    }

    /// One app that can act as your account.
    struct App: Equatable {
        let id: String
        let name: String
        /// The organisation behind it, when the export named one. Often the
        /// same word as `name`, which is why the caller drops it when it is.
        let organization: String?
        let detail: String?
        let reach: Reach
        /// When you approved it. Optional and it matters that it is: an app
        /// with no date lands stamped with the archive's own oldest fact
        /// rather than with today, so a grant from 2013 can never arrive
        /// wearing this morning's timestamp.
        let approvedAt: Date?
    }

    /// Every app in the file, newest grant first, deduplicated by id.
    ///
    /// Order is TOTAL — approval date descending, then name, then id — so the
    /// room cannot reshuffle between two opens over identical data.
    static func apps(_ entries: [[String: Any]]) -> [App] {
        var seen = Set<String>()
        var out: [App] = []
        for entry in entries {
            let raw = (entry["connectedApplication"] as? [String: Any]) ?? entry
            let name = string(raw["name"]) ?? string(raw["applicationName"])
            guard let name, !name.isEmpty else { continue }
            // The id is what dedupes and what keys the row. An export that
            // states none falls back to the name, which is stable enough for
            // this purpose and is the only alternative to dropping the row.
            let id = string(raw["id"]) ?? string(raw["applicationId"]) ?? name
            guard seen.insert(id).inserted else { continue }
            let org = (raw["organization"] as? [String: Any]).flatMap { string($0["name"]) }
            out.append(App(id: id,
                           name: name,
                           organization: org == name ? nil : org,
                           detail: string(raw["description"]),
                           reach: reach(raw),
                           approvedAt: stamp(string(raw["approvedAt"])
                                             ?? string(raw["createdAt"]))))
        }
        return out.sorted {
            let a = $0.approvedAt ?? .distantPast, b = $1.approvedAt ?? .distantPast
            if a != b { return a > b }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }

    /// What the grant's own words add up to.
    ///
    /// Read as SUBSTRINGS of a lowercased join rather than matched against a
    /// fixed vocabulary, because the field is not one shape: some exports carry
    /// `permissions: ["read", "write"]`, some a single `accessType: "Read and
    /// Write"`, and some spell the message scope "dm" and some "direct
    /// messages". A substring scan reads all of them; an enum match reads one
    /// and silently answers `unknown` for the rest — which on this row would
    /// under-state a write grant, the one direction that must never happen.
    ///
    /// It never UPGRADES on a guess: a field naming nothing recognisable stays
    /// `unknown`, and "read" alone stays `read`.
    static func reach(_ raw: [String: Any]) -> Reach {
        var parts: [String] = []
        if let list = raw["permissions"] as? [String] { parts += list }
        if let one = string(raw["permissions"]) { parts.append(one) }
        for key in ["accessType", "access", "permissionLevel", "scope"] {
            if let one = string(raw[key]) { parts.append(one) }
        }
        let joined = parts.joined(separator: " ").lowercased()
        guard !joined.isEmpty else { return .unknown }
        if joined.contains("dm") || joined.contains("direct message")
            || joined.contains("message") { return .messages }
        if joined.contains("write") || joined.contains("post") { return .write }
        if joined.contains("read") { return .read }
        return .unknown
    }

    /// The row's own line. The REACH LEADS, on §303's clamp ruling: a title is
    /// cut at 80 characters, so an app whose name is long would otherwise lose
    /// the only word that says what it can do — and "can post as you" arriving
    /// after the cut reads exactly like "can read your posts".
    ///
    /// Every grade gets its own sentence, `unknown` included, because a row
    /// that says nothing about reach is indistinguishable from one that says
    /// "read" and is the reason to open the settings page rather than not to.
    static func appTitle(_ app: App) -> String {
        switch app.reach {
        case .messages: return String(localized: "Can post as you and read your messages · \(app.name)")
        case .write:    return String(localized: "Can post as you · \(app.name)")
        case .read:     return String(localized: "Can read your account · \(app.name)")
        case .unknown:  return String(localized: "Connected to your account · \(app.name)")
        }
    }

    /// The second line, or nothing. The organisation first when it differs from
    /// the app's own name (that is the party the grant is really with), then
    /// whatever the app said about itself.
    static func appDetail(_ app: App) -> String? {
        let parts = [app.organization, app.detail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Where you go to take a grant back. X's own page, opened in the person's
    /// own browser — this app has no way to revoke anything and does not claim
    /// one (the `WalletApprovals` ruling, prd §112: read and preview here,
    /// act there).
    static let settingsURL = "https://x.com/settings/connected_apps"

    // MARK: - The account's own beginning

    struct Origin: Equatable {
        let accountID: String?
        let handle: String?
        let createdAt: Date
    }

    /// The day the account was made, from the file this importer already opens
    /// for its handle. nil when the field is absent or unparseable — never a
    /// fallback to today, which would put "you joined X" at the top of the
    /// room on the afternoon somebody imported fifteen years of it.
    static func origin(_ entries: [[String: Any]]) -> Origin? {
        for entry in entries {
            let account = (entry["account"] as? [String: Any]) ?? entry
            guard let made = stamp(string(account["createdAt"])) else { continue }
            let handle = string(account["username"])?
                .trimmingCharacters(in: CharacterSet(charactersIn: " @"))
            return Origin(accountID: string(account["accountId"]),
                          handle: (handle?.isEmpty ?? true) ? nil : handle,
                          createdAt: made)
        }
        return nil
    }

    // MARK: - Who you used to be

    struct Rename: Equatable {
        let from: String?
        let to: String
        let at: Date
    }

    /// Every handle change the export recorded, oldest first.
    ///
    /// The nesting here is genuinely doubled in X's own file — the wrapper key
    /// and the inner key are both `screenNameChange` — so both levels are
    /// unwrapped, and the bare object is accepted as well in case an export
    /// vintage flattens it.
    static func renames(_ entries: [[String: Any]]) -> [Rename] {
        var out: [Rename] = []
        for entry in entries {
            var raw = (entry["screenNameChange"] as? [String: Any]) ?? entry
            if let inner = raw["screenNameChange"] as? [String: Any] { raw = inner }
            guard let to = string(raw["changedTo"])?
                    .trimmingCharacters(in: CharacterSet(charactersIn: " @")),
                  !to.isEmpty,
                  let at = stamp(string(raw["changedAt"])) else { continue }
            let from = string(raw["changedFrom"])?
                .trimmingCharacters(in: CharacterSet(charactersIn: " @"))
            out.append(Rename(from: (from?.isEmpty ?? true) ? nil : from, to: to, at: at))
        }
        return out.sorted { $0.at < $1.at }
    }

    /// A rename's own line. Both handles when the export named both, because
    /// the old one is the half you'd search for.
    static func renameTitle(_ rename: Rename) -> String {
        guard let from = rename.from else {
            return String(localized: "You became @\(rename.to) on X")
        }
        return String(localized: "@\(from) became @\(rename.to)")
    }

    // MARK: - Reading a field

    /// A string field, however the export typed it. Numbers appear where
    /// strings are documented (an app id, an account id), and a `nil` here
    /// costs a row.
    private static func string(_ value: Any?) -> String? {
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let n = value as? UInt64 { return String(n) }
        if let n = value as? Int { return String(n) }
        return nil
    }
}
