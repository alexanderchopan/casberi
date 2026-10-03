import Foundation

/// The Social room's tiles (prd §1086): All, To you — only what is addressed
/// to you, across every network — and Follow, the verb, last. "To you", never
/// "You": the faces under the tiles already hold a You, your own posts. Foundation-only,
/// its conformance beside every other in `ScopeTileGlyphs.swift`.
enum SocialScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, toYou, follow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    return String(localized: "All")
        case .toYou:  return String(localized: "To you")
        case .follow: return String(localized: "Follow")
        }
    }

    var summary: String {
        switch self {
        case .all:    return String(localized: "Everyone you follow")
        case .toYou:  return String(localized: "Replies, mentions and new followers")
        case .follow: return String(localized: "Follow someone on any network")
        }
    }

    var isVerb: Bool { self == .follow }
}

/// What is TO you in the Social room (prd §1086), compiled whole by
/// `social-room-selftest.sh` — so a starter pack's forty people never bury
/// the reply someone sent you.
enum SocialToYou {
    /// A row, as the rule reads it.
    struct Row: Sendable {
        let source: String
        let socialContext: String?
        let sourceRef: String?
        let title: String
        /// The post's words (`postText`), where the title is a clamp of them.
        let text: String?
    }

    /// How long a row leads All as "To you", and how many lead it.
    static let leadWindow: TimeInterval = 7 * 86_400
    static let leadCap = 3

    /// Notices that are about someone you follow, not about you: X's "New
    /// post from mia" and its digest of them. X stores the sentence only.
    private static let followFeedNotices = ["New post from", "New post notifications"]

    /// Whether a row is addressed to you: a reply to you, a new follower, a
    /// mention naming one of your own handles, or a live notice from X,
    /// Instagram or TikTok that is about your post or your account.
    ///
    /// `myHandles` are your accounts' handles, lower-cased, no `@`. A mention
    /// is landed for any watched account with mentions on, so it is yours
    /// only when it names you.
    static func isToYou(_ row: Row, myHandles: Set<String>) -> Bool {
        switch row.socialContext {
        case "reply", "follow": return true
        case "mention":
            let words = (row.text ?? row.title).lowercased()
            return myHandles.contains { !$0.isEmpty && words.contains("@" + $0) }
        default: break
        }
        guard let ref = row.sourceRef else { return false }
        if ref.hasPrefix("ig-live:notif:") || ref.hasPrefix("tiktok:live:notif:") { return true }
        if ref.hasPrefix("x-live:notif:") {
            return !followFeedNotices.contains { row.title.hasPrefix($0) }
        }
        return false
    }

    /// The rows that lead All: to you, within the week, newest first, three.
    static func leading(_ rows: [(row: Row, at: Date)], myHandles: Set<String>, now: Date) -> [Int] {
        rows.indices
            .filter { i in
                let at = rows[i].at
                return at <= now && now.timeIntervalSince(at) <= leadWindow
                    && isToYou(rows[i].row, myHandles: myHandles)
            }
            .sorted { rows[$0].at > rows[$1].at }
            .prefix(leadCap).map { $0 }
    }

    // MARK: - Follow suggestions

    /// The networks a Follow can land on: the ones whose stores watch a
    /// handle (`SocialBridge.watch`).
    static let followable: Set<String> = ["Farcaster", "Bluesky"]

    /// Someone near you: who they are, on which network, and why.
    struct Person: Equatable, Sendable {
        enum Why: Equatable, Sendable { case talksToYou, mentioned(Int) }
        let source: String
        let handle: String
        let why: Why
    }

    static let suggestionCap = 6

    /// People who already talk to you and people your feed keeps naming,
    /// that you follow nowhere on that network. Who talks to you leads, newest
    /// first; then the most-named, twice or more in the week.
    ///
    /// `talkers` are the authors of your replies and new-follower rows;
    /// `posts` the week's posts on a followable network, each with its source.
    static func suggestions(talkers: [(source: String, handle: String, at: Date)],
                            posts: [(source: String, text: String, at: Date)],
                            watched: [String: Set<String>], mine: Set<String>,
                            now: Date) -> [Person] {
        func known(_ source: String, _ handle: String) -> Bool {
            let h = normalized(handle)
            return h.isEmpty || mine.contains(h) || (watched[source] ?? []).contains(h)
        }
        var out: [Person] = []
        var seen = Set<String>()
        for t in talkers.sorted(by: { $0.at > $1.at })
        where followable.contains(t.source) && !known(t.source, t.handle) {
            let key = t.source + ":" + normalized(t.handle)
            if seen.insert(key).inserted {
                out.append(Person(source: t.source, handle: normalized(t.handle), why: .talksToYou))
            }
        }
        var counts: [String: (source: String, handle: String, n: Int)] = [:]
        for post in posts where followable.contains(post.source)
            && post.at <= now && now.timeIntervalSince(post.at) <= leadWindow {
            var once = Set<String>()
            for handle in mentions(in: post.text) where !known(post.source, handle) {
                let key = post.source + ":" + handle
                guard once.insert(key).inserted, !seen.contains(key) else { continue }
                counts[key, default: (post.source, handle, 0)].n += 1
            }
        }
        out += counts.values.filter { $0.n >= 2 }
            .sorted { $0.n != $1.n ? $0.n > $1.n : $0.handle < $1.handle }
            .map { Person(source: $0.source, handle: $0.handle, why: .mentioned($0.n)) }
        return Array(out.prefix(suggestionCap))
    }

    /// The `@handles` in a post, lower-cased: a Farcaster name or a Bluesky
    /// domain handle. A trailing full stop is the sentence's, not the handle's.
    static func mentions(in text: String) -> [String] {
        text.matches(of: #/(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_][A-Za-z0-9_.\-]{0,62})/#).map {
            var h = String($0.1).lowercased()
            while h.hasSuffix(".") || h.hasSuffix("-") { h.removeLast() }
            return h
        }.filter { !$0.isEmpty }
    }

    static func normalized(_ handle: String) -> String {
        var h = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.hasPrefix("@") { h.removeFirst() }
        return h
    }
}
