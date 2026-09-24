import Foundation
import SwiftData

/// Duolingo's live door (prd §776) — the half that touches the Keychain and
/// the corpus. The pure parse, every URL and everything stated about what is
/// and is not measured are in `DuolingoFeed`.
///
/// The credential is the `jwt_token` cookie a sign-in at duolingo.com leaves,
/// stored device-only by `TokenVault` and sent as the bearer the web app
/// itself sends. Read-only: nothing here writes an answer, starts a lesson,
/// spends a gem, or marks anything read.
enum DuolingoLiveAuth {
    private static let tokenKey = "duolingo.live.jwt"
    /// Not a secret — the signed-in handle and the course, learnt from the
    /// profile read and shown on the account page.
    private static let whoKey = "duolingo.live.who"
    private static let courseKey = "duolingo.live.course"
    /// The HANDLE alone, apart from `who` (which falls back to the display
    /// name): a profile page is reached by username and by nothing else
    /// (prd §912).
    private static let usernameKey = "duolingo.live.username"

    static var token: String? {
        TokenVault.get(tokenKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var connected: Bool { token != nil }

    /// The account the stored token names, decoded out of the token itself.
    static var userID: String? { token.flatMap(DuolingoFeed.userID(fromJWT:)) }

    static func store(token: String) {
        // A new sign-in may be a different account: its name and its course
        // are learnt again rather than inherited (TikTok's rule, §731).
        UserDefaults.standard.removeObject(forKey: whoKey)
        UserDefaults.standard.removeObject(forKey: courseKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        TokenVault.set(token, for: tokenKey)
    }

    /// Clears the live session only — every day already landed is untouched,
    /// because those are the person's practice history and not the session's.
    static func clear() {
        TokenVault.delete(tokenKey)
        UserDefaults.standard.removeObject(forKey: whoKey)
        UserDefaults.standard.removeObject(forKey: courseKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    static var who: String? {
        UserDefaults.standard.string(forKey: whoKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var course: String? {
        UserDefaults.standard.string(forKey: courseKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var username: String? {
        UserDefaults.standard.string(forKey: usernameKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Where a practice row opens (prd §912): the account's own profile page,
    /// which exists only under a username. nil until one is learnt.
    static var profileURL: String? {
        username.map { "https://www.duolingo.com/profile/\($0)" }
    }

    static func remember(_ profile: DuolingoFeed.Profile) {
        if let who = profile.who { UserDefaults.standard.set(who, forKey: whoKey) }
        if let course = profile.course { UserDefaults.standard.set(course, forKey: courseKey) }
        if let username = profile.username, !username.isEmpty {
            UserDefaults.standard.set(username, forKey: usernameKey)
        }
    }
}

enum DuolingoLive {
    @MainActor private static var running = false
    /// Why the last pass landed nothing, when it failed. `refresh` keeps its
    /// `Int?` because the sweep only needs "did it work"; the SCREEN needs to
    /// tell a throttle (signed in, days delayed) from a dead session.
    @MainActor private(set) static var lastFailure: DuolingoFeed.Failure?

    /// Lands the days you practised. nil = couldn't run (not signed in, or the
    /// read failed); 0 or more = a real read, however many rows are new. A
    /// refusal — and only a refusal — clears the session, so the page falls
    /// back to Connect instead of saying "signed in" over a dead token (§711).
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext, now: Date = .now) async -> Int? {
        guard let token = DuolingoLiveAuth.token,
              let id = DuolingoFeed.userID(fromJWT: token) else {
            lastFailure = .noSession
            return nil
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        lastFailure = nil

        await learnProfileIfNeeded(id: id, token: token)

        let (json, status) = await get(
            DuolingoFeed.summariesURL(id: id, startDate: DuolingoFeed.startDate(daysBefore: now)),
            token: token)
        if let failure = DuolingoFeed.classify(status: status, json: json) {
            if case .refused = failure { DuolingoLiveAuth.clear() }
            lastFailure = failure
            return nil
        }
        guard let days = DuolingoFeed.days(json) else {
            lastFailure = .drifted
            return nil
        }
        return land(days, context: context, now: now)
    }

    @MainActor
    private static func land(_ days: [DuolingoFeed.Day], context: ModelContext,
                             now: Date) -> Int {
        let course = DuolingoLiveAuth.course
        let door = DuolingoLiveAuth.profileURL
        let landed = landedDays(context: context)
        var added = 0
        var rewritten = 0

        for day in days where day.practised {
            let title = DuolingoFeed.title(day, course: course)
            let line = DuolingoFeed.line(day)
            // The DOOR takes `content` once the profile is known (prd §912),
            // and the "3 lessons · 14 min" line moves under it with the
            // streak words; until then the line stays where it was, so a row
            // never loses it.
            let content = door ?? line ?? ""
            let summary = words(for: day, line: door == nil ? nil : line)
            if let existing = landed[day.ref] {
                // TODAY grows while you are still in it (§776), and a day
                // whose row already says what this read says is left alone —
                // a rewrite that changes nothing still dirties the context and
                // still re-indexes the row.
                guard DuolingoFeed.rewrites(landedTitle: existing.title,
                                            landedLine: existing.content,
                                            title: title, line: content)
                        || (existing.summary ?? "") != (summary ?? "") else { continue }
                existing.title = title
                existing.content = content
                existing.summary = summary
                SpotlightIndex.index([existing])
                rewritten += 1
                continue
            }
            let thing = Thing(
                kind: .event,
                title: title,
                content: content,
                source: DuolingoFeed.source,
                capturedAt: DuolingoFeed.stamp(day, now: now),
                // The facet the retriever narrows "what did I practise?" to,
                // and simply true: this endpoint is the practice record and
                // nothing else. No "Duolingo" tag beside it — the source chip
                // already says that (ShapedRows' reason for dropping bridge
                // tags).
                tags: ["Practice"],
                sourceRef: day.ref)
            thing.summary = summary
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || rewritten > 0 { context.saveHonestly() }
        return added
    }

    /// What the row says under its title (prd §912): the lessons-and-minutes
    /// line when the door displaced it from `content`, then the streak facts
    /// the payload flags — only the ones set, never "streak not extended".
    /// nil when there is nothing, never an empty line.
    private static func words(for day: DuolingoFeed.Day, line: String?) -> String? {
        var parts: [String] = []
        if let line { parts.append(line) }
        if day.streakExtended { parts.append(String(localized: "Streak extended")) }
        if day.frozen { parts.append(String(localized: "Streak frozen")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The days already here, scoped by PREFIX — a fortnight's read against a
    /// corpus that may hold years of them.
    @MainActor
    private static func landedDays(context: ModelContext) -> [String: Thing] {
        let prefix = DuolingoFeed.refPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Duolingo" && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { map[ref] = thing }
        }
        return map
    }

    // MARK: - The requests

    /// The account's own facts, asked once per sign-in. The COURSE is why this
    /// runs at all: without it every row would read "38 XP on Duolingo" and
    /// say nothing about what was practised.
    private static func learnProfileIfNeeded(id: String, token: String) async {
        guard DuolingoLiveAuth.who == nil || DuolingoLiveAuth.course == nil else { return }
        let (json, _) = await get(DuolingoFeed.profileURL(id: id), token: token)
        if let profile = DuolingoFeed.profile(json) { DuolingoLiveAuth.remember(profile) }
    }

    /// The session's own profile, always freshly read — what the connect
    /// screen proves a sign-in with.
    static func profile() async -> (DuolingoFeed.Profile?, DuolingoFeed.Failure?) {
        guard let token = DuolingoLiveAuth.token,
              let id = DuolingoFeed.userID(fromJWT: token) else { return (nil, .noSession) }
        let (json, status) = await get(DuolingoFeed.profileURL(id: id), token: token)
        switch status {
        case 401, 403: return (nil, .refused(status))
        case 429: return (nil, .throttled)
        case 0, 500...: return (nil, .unreachable)
        default: break
        }
        guard let profile = DuolingoFeed.profile(json) else { return (nil, .drifted) }
        DuolingoLiveAuth.remember(profile)
        return (profile, nil)
    }

    private static func get(_ url: String, token: String) async -> (json: Any?, status: Int) {
        await IngestSupport.getJSONStatus(url, auth: "Bearer \(token)",
                                          headers: headers, service: "Duolingo")
    }

    /// What the web app sends and nothing it doesn't. The bearer rides
    /// `auth:`; these are the two headers that make the request look like the
    /// page it is copying.
    static let headers: [String: String] = [
        "User-Agent": DuolingoFeed.desktopUserAgent,
        "Accept": "application/json",
    ]

    // MARK: - Diagnose

    /// The chain, link by link: stored / whose account / the profile's answer
    /// / the summaries status / how many days parsed / the newest three / one
    /// raw day. Never prints the token.
    ///
    /// This exists because NOTHING about this seat is measured on a build host
    /// (`DuolingoFeed`'s header) — the first real sign-in is the measurement,
    /// and it has to be readable in one launch.
    @MainActor
    static func diagnose(context: ModelContext, now: Date = .now) async {
        guard let token = DuolingoLiveAuth.token else {
            NSLog("[Casberi] duolingo| not signed in — connect from the Duolingo account page first")
            return
        }
        guard let id = DuolingoFeed.userID(fromJWT: token) else {
            NSLog("[Casberi] duolingo| stored token carries no `sub` claim — it is not a Duolingo session")
            return
        }
        NSLog("[Casberi] duolingo| session stored (%d chars), account %@", token.count, id)

        let (profileJSON, profileStatus) = await get(DuolingoFeed.profileURL(id: id), token: token)
        let keys = (profileJSON as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "—"
        NSLog("[Casberi] duolingo| profile HTTP %d keys: %@", profileStatus, keys)
        if let profile = DuolingoFeed.profile(profileJSON) {
            NSLog("[Casberi] duolingo| signed in as %@ — %d day streak, %d XP, course %@",
                  profile.who ?? "(no name)", profile.streak, profile.totalXP,
                  profile.course ?? "(none named)")
        } else {
            NSLog("[Casberi] duolingo| profile: no readable account in that body")
        }

        let start = DuolingoFeed.startDate(daysBefore: now)
        let (json, status) = await get(DuolingoFeed.summariesURL(id: id, startDate: start),
                                       token: token)
        NSLog("[Casberi] duolingo| xp_summaries from %@ HTTP %d%@", start, status,
              DuolingoFeed.classify(status: status, json: json)
                .map { " — \(DuolingoFeed.describe($0))" } ?? "")
        let days = DuolingoFeed.days(json) ?? []
        NSLog("[Casberi] duolingo| %d day(s) parsed, %d practised",
              days.count, days.filter(\.practised).count)
        for day in days.filter(\.practised).prefix(3) {
            NSLog("[Casberi] duolingo| %@ | %@ | %@", day.key,
                  DuolingoFeed.title(day, course: DuolingoLiveAuth.course),
                  DuolingoFeed.line(day) ?? "(no lessons or time reported)")
        }
        if let raw = ((json as? [String: Any])?["summaries"] as? [[String: Any]])?.first,
           let data = try? JSONSerialization.data(withJSONObject: raw),
           let text = String(data: data, encoding: .utf8) {
            NSLog("[Casberi] duolingo| one raw day: %@", text)
        }

        let added = await refresh(context: context, now: now)
        NSLog("[Casberi] duolingo| landed: %@ new", added.map(String.init) ?? "FAILED")
    }
}
