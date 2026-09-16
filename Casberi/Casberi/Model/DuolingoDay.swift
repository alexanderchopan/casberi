import Foundation

/// Duolingo's own record of the days you practised, read with the person's OWN
/// web session (prd §776) — the pure half, Foundation-only so
/// `duolingo-selftest.sh` compiles it WHOLE. Everything that touches `Thing`
/// or the Keychain is `DuolingoLive`.
///
/// This is §703/§726/§731's door, one seat over: the person signs in at
/// duolingo.com inside a `WKWebView` we control, the sign-in leaves a
/// `jwt_token` cookie, and every read afterwards is the same bearer the web
/// app sends. No developer app, no key, no server, and nothing signs a
/// request. Nothing is extracted from Duolingo's page scripts.
///
/// **What lands:** one thing per DAY you practised — "38 XP in Spanish", with
/// the lessons and the minutes under it. Not one per lesson: Duolingo's own
/// record has no per-lesson row to read, and the day is the unit its streak,
/// its widget and its own notifications are all counted in.
///
/// **NOT MEASURED BY THIS PROJECT, and read defensively because of it.** No
/// build host here can reach duolingo.com (the session that wrote this file
/// had the host refused at its egress proxy), so every shape below is the
/// public community record of the web app's endpoints rather than a request
/// this repo has watched. That is a weaker footing than §731's TikTok entry
/// and exactly the footing §741's X entry shipped on. What follows from it:
///
///   · every field is optional and every number is read through `int(_:)`,
///     which accepts a JSON number or a numeric string;
///   · a 200 whose body is not a `summaries` array is `.drifted`, never an
///     empty practice history — an empty history and an unreadable one must
///     not render the same;
///   · `-duolingoProbe` prints the profile's keys, the first summaries and one
///     raw day, so the first real sign-in is a one-launch correction rather
///     than a guess.
enum DuolingoFeed {
    static let source = "Duolingo"

    /// Spelled a second time in `duolingo-selftest.sh`. One namespace, because
    /// this seat has no import half — nothing here is in
    /// `Corpus.liveRefPrefixesBySource`, which exists only to tell a seat's
    /// live rows from its imported ones (prd §733), and Duolingo has no
    /// archive to import.
    static let refPrefix = "duolingo:day:"

    static let host = "www.duolingo.com"
    /// The web app's own sign-in. `?isLoggingIn=true` is what opens the form
    /// rather than the marketing page.
    static let loginURL = "https://www.duolingo.com/?isLoggingIn=true"
    /// The cookie a completed sign-in leaves, and the whole credential: it IS
    /// the bearer the web app sends on every later call.
    static let cookieName = "jwt_token"

    /// A desktop Safari agent for the sign-in sheet AND every read — TikTok's
    /// reason (§731): the desktop site is the one whose sign-in does not steer
    /// toward the app, and one constant means the cookie and the reads always
    /// claim the same browser.
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    // MARK: - The credential

    /// The user id, decoded out of the JWT's own `sub` claim — no request at
    /// all. Duolingo's read paths are keyed by id, and asking an endpoint for
    /// the id of the session you are holding is a round trip for a fact the
    /// credential already states.
    ///
    /// Signature-unchecked ON PURPOSE: this token was handed to us by the
    /// sign-in we ran ourselves, we never accept one from anywhere else, and
    /// the only thing read out of it is which account to ask about. A wrong id
    /// gets a refusal from Duolingo, not a wrong answer.
    static func userID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let data = base64URL(String(parts[1])),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return int(root["sub"]).map(String.init)
    }

    /// Base64URL, which is not base64: `-`/`_` for `+`/`/`, and the `=`
    /// padding dropped. `Data(base64Encoded:)` rejects both, so a JWT payload
    /// decoded straight would simply be nil — a silent "not signed in" over a
    /// perfectly good session.
    static func base64URL(_ raw: String) -> Data? {
        var s = raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    /// The jar a sign-in left, as the bearer it carries. Nil until
    /// `jwt_token` is in it: duolingo.com writes cookies for a signed-OUT
    /// visitor too, and only a completed sign-in writes this one.
    static func bearer(_ cookies: [(name: String, value: String)]) -> String? {
        guard let hit = cookies.first(where: { $0.name == cookieName && !$0.value.isEmpty })
        else { return nil }
        // A token that carries no id is not a session we can read anything
        // with — treating it as one would store a credential that can only
        // ever fail, and the page would say "signed in" over it forever.
        guard userID(fromJWT: hit.value) != nil else { return nil }
        return hit.value
    }

    // MARK: - The requests

    /// The profile — the account's own facts, for the signed-in line and for
    /// which course a day's XP belongs to. `fields` is named on purpose: the
    /// bare user object is large, and nothing here reads the rest of it.
    static func profileURL(id: String) -> String {
        "https://\(host)/2017-06-30/users/\(id)"
            + "?fields=id,username,name,streak,streakData,totalXp,courses,currentCourseId,picture"
    }

    /// The practice record, from `startDate` forward. Duolingo's own day
    /// boundary is the account's, so the date is a plain `yyyy-MM-dd`.
    static func summariesURL(id: String, startDate: String) -> String {
        "https://\(host)/2017-06-30/users/\(id)/xp_summaries?startDate=\(startDate)"
    }

    /// How far back a sweep asks. A fortnight: enough that a week away still
    /// lands every day of it, small enough that the read stays one page.
    static let lookbackDays = 14

    /// `yyyy-MM-dd` in UTC — the spelling `startDate` takes, and the key half
    /// of every ref. Hand-formatted rather than through a `DateFormatter`
    /// because this file is compiled standalone by the harness.
    static func dayKey(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let p = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    static func startDate(daysBefore now: Date) -> String {
        dayKey(now.addingTimeInterval(-Double(lookbackDays) * 86_400))
    }

    // MARK: - Failure

    enum Failure: Equatable {
        case noSession
        /// 401/403. The ONLY case that may clear the stored token (§711) — a
        /// flat network moment costs the person the whole web sign-in again.
        case refused(Int)
        /// 429 — asked too often. Not a verdict on the session (§711b).
        case throttled
        /// No HTTP response at all, or Duolingo having a bad minute.
        case unreachable
        /// A 200 whose body this file does not know.
        case drifted
    }

    /// The summaries read's verdict. Status-led: unlike TikTok's inbox, no
    /// body shape is known here that says "your session is gone" inside a
    /// 200, so a 200 that is not a summaries array is drift and is NEVER
    /// taken as a refusal — the expensive mistake in both directions is
    /// throwing away a live sign-in.
    static func classify(status: Int, json: Any?) -> Failure? {
        switch status {
        case 0: return .unreachable
        case 401, 403: return .refused(status)
        case 429: return .throttled
        case 500...: return .unreachable
        case 200:
            guard let root = json as? [String: Any], root["summaries"] is [[String: Any]]
            else { return .drifted }
            return nil
        default: return .drifted
        }
    }

    static func describe(_ failure: Failure) -> String {
        switch failure {
        case .noSession: return "not signed in"
        case .refused(let s): return "refused (\(s)) — the session is gone, sign in again"
        case .throttled: return "throttled — asked too often, try later"
        case .unreachable: return "unreachable — check the connection"
        case .drifted: return "unexpected shape — the web app's response changed"
        }
    }

    // MARK: - The profile

    struct Profile: Equatable {
        var username: String?
        var name: String?
        var streak: Int
        var totalXP: Int
        /// The course being learnt, by the language's own display title
        /// ("Spanish"), never its code.
        var course: String?
        var picture: String?

        /// What the connected line says. The handle, then the display name,
        /// then nothing — never a fabricated "Signed in as 1234".
        var who: String? { username ?? name }
    }

    /// Reads BOTH shapes the 2017-06-30 user endpoint answers in: the object
    /// itself (`users/<id>`) and a one-element roster (`users?username=`).
    /// Which one a given build of the web app uses is exactly the sort of
    /// thing that changes without notice, and handling one of them is a seat
    /// that signs in and then says nothing.
    static func profile(_ json: Any?) -> Profile? {
        var root = json as? [String: Any]
        if let roster = root?["users"] as? [[String: Any]] { root = roster.first }
        guard let root else { return nil }
        // THE LARGER OF THE TWO THE ACCOUNT REPORTS. Duolingo answers a flat
        // `streak` and a `streakData.currentStreak.length`, neither
        // documented, and an account with a live streak can come back with
        // the flat one at 0 — so preferring it would print "0 day streak"
        // beside a person's two-hundredth day. Taking the larger needs no
        // claim about which field is authoritative, and both being absent
        // still reads as no streak rather than as a wrong one.
        let lengths = [int(root["streak"]),
                       int(((root["streakData"] as? [String: Any])?["currentStreak"]
                            as? [String: Any])?["length"])]
        let streak = lengths.compactMap { $0 }.max()
        let profile = Profile(
            username: string(root["username"]),
            name: string(root["name"]),
            streak: streak ?? 0,
            totalXP: int(root["totalXp"]) ?? 0,
            course: course(in: root),
            picture: picture(root["picture"]))
        // An object with none of these is not a profile — it is whatever
        // Duolingo answered instead, and reading it as an empty account would
        // put "Signed in" over a body nobody understood.
        guard profile.who != nil || profile.totalXP > 0 || profile.streak > 0
        else { return nil }
        return profile
    }

    /// The course a day's XP belongs to: the current one where the account
    /// names it, otherwise the one with the most XP in it. Never the first in
    /// the array — that order is Duolingo's and means nothing here.
    static func course(in root: [String: Any]) -> String? {
        let courses = (root["courses"] as? [[String: Any]]) ?? []
        guard !courses.isEmpty else { return nil }
        if let current = string(root["currentCourseId"]),
           let hit = courses.first(where: { string($0["id"]) == current }),
           let title = string(hit["title"]) {
            return title
        }
        let best = courses.max { (int($0["xp"]) ?? 0) < (int($1["xp"]) ?? 0) }
        return best.flatMap { string($0["title"]) }
    }

    /// Duolingo serves avatars as a protocol-relative path with no extension
    /// (`//simple-avatars…/xyz`), and the size is a suffix. `/large` rather
    /// than the bare path: the bare one answers a placeholder on some
    /// accounts, which lands as a grey square nobody can explain.
    static func picture(_ any: Any?) -> String? {
        guard var s = string(any) else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        guard s.hasPrefix("https://") else { return nil }
        if !s.hasSuffix("/large") { s += "/large" }
        return s
    }

    // MARK: - The days

    struct Day: Equatable {
        /// Midnight UTC of the practice day, as `xp_summaries` stamps it.
        var dayStartUTC: Date
        var xp: Int
        var sessions: Int
        var seconds: Int
        var streakExtended: Bool
        /// The day was covered by a streak freeze rather than practised.
        var frozen: Bool

        var key: String { DuolingoFeed.dayKey(dayStartUTC) }
        var ref: String { DuolingoFeed.refPrefix + key }

        /// A day worth a row. A frozen day with no XP is a day you did NOT
        /// practise — landing it would put "0 XP" in the feed and call it an
        /// event, which is the fake status §83 bans.
        var practised: Bool { xp > 0 || sessions > 0 }
    }

    static func days(_ json: Any?) -> [Day]? {
        guard let root = json as? [String: Any],
              let raw = root["summaries"] as? [[String: Any]] else { return nil }
        return raw.compactMap(day(from:))
    }

    static func day(from item: [String: Any]) -> Day? {
        guard let stamp = int(item["date"]) else { return nil }
        return Day(
            dayStartUTC: Date(timeIntervalSince1970: Double(stamp)),
            xp: int(item["gainedXp"]) ?? 0,
            sessions: int(item["numSessions"]) ?? 0,
            seconds: int(item["totalSessionTime"]) ?? 0,
            streakExtended: bool(item["streakExtended"]),
            frozen: bool(item["frozen"]))
    }

    /// "38 XP in Spanish" — the course where the account names one, because
    /// "38 XP" alone says nothing about what was practised. Never pluralised
    /// around the number: XP is XP.
    static func title(_ day: Day, course: String?) -> String {
        guard let course, !course.isEmpty else { return "\(day.xp) XP on Duolingo" }
        return "\(day.xp) XP in \(course)"
    }

    /// "3 lessons · 14 min". Only the facts the payload carried: a day whose
    /// sessions or time came back zero simply doesn't claim them, and a day
    /// that carried neither gets no line at all rather than an empty one.
    static func line(_ day: Day) -> String? {
        var parts: [String] = []
        if day.sessions > 0 {
            parts.append(day.sessions == 1 ? "1 lesson" : "\(day.sessions) lessons")
        }
        // Rounded to the nearest minute, floored at one: a two-minute session
        // reported as "0 min" reads as a failure to record it.
        if day.seconds > 0 {
            let minutes = max(1, Int((Double(day.seconds) / 60).rounded()))
            parts.append("\(minutes) min")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// WHEN THE ROW SITS. A practice day arrives as midnight UTC, and a feed
    /// groups by the reader's own day — so a person in UTC+13 practising on
    /// the 9th would have their row filed under the 8th, every day, forever.
    /// The day's UTC calendar components name the day; the stamp is local
    /// midday of it, so it lands under the right header whatever the offset.
    ///
    /// Clamped to `now`, because today's row is landed while today is still
    /// running: an un-clamped midday is a feed row stamped in the future every
    /// morning.
    static func stamp(_ day: Day, now: Date = .now,
                      calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let p = utc.dateComponents([.year, .month, .day], from: day.dayStartUTC)
        var local = DateComponents()
        local.year = p.year; local.month = p.month; local.day = p.day; local.hour = 12
        guard let noon = calendar.date(from: local) else { return min(day.dayStartUTC, now) }
        return min(noon, now)
    }

    /// TODAY IS NOT FINISHED, so its row is rewritten rather than left at the
    /// first read of it (§741's rule for a growing X aggregate, arriving from
    /// the other side): a day landed at 20 XP at breakfast reads 20 XP forever
    /// otherwise, and nothing on screen says the number is a morning's.
    ///
    /// The test is what the row SAYS, not the numbers behind it, because the
    /// row is all that is stored — and it catches the second case as well,
    /// which is a day whose course was renamed or switched. A row saying what
    /// today's read says is never touched, so a sweep that learnt nothing
    /// moves nothing in the feed.
    static func rewrites(landedTitle: String, landedLine: String,
                         title: String, line: String?) -> Bool {
        landedTitle != title || landedLine != (line ?? "")
    }

    // MARK: - Reading a value

    /// A JSON number, or a number spelled as a string. Duolingo's ids come
    /// back both ways across its endpoints, and `as? Int` on the other one is
    /// a silent nil.
    static func int(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = int(any) { return n != 0 }
        return false
    }

    static func string(_ any: Any?) -> String? {
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }
}
