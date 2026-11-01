import Foundation

/// **A SOURCE'S ROW LOOKS LIKE ITS APP (prd §1645, user, 2026-11-01: "each
/// source where applicable getting it's own design in the feed if it merits
/// it"; "like in media we show square images, and now w/ telegram and agent
/// we show chat bubbles"; "build all").** The Feed's one-line row keeps the
/// one signature you would know a source by, drawn in Casberi's own type and
/// inks, never the app's chrome or its brand colour:
///
///   • an agent chat is your question, in your own bubble
///   • a post on X or Bluesky is who, why it's here, then their words
///   • a mail is its sender over its subject
///   • a GitHub item names its repository and number in code type, and its
///     state where the bridge stamped one
///   • a workout carries its distance or time as the figure
///   • a file wears its type and size
///   • a Work row says how it went, in the status inks (`WorkStage`)
///   • an event says its hours and place, or that it was cancelled
///   • a Linear, Jira or Sentry issue names its key in code type, as GitHub does
///   • a package release is its version; a review is its stars
///   • a feed item is its publication over its headline
///   • a highlight is the passage, quoted, over its book
///   • Duolingo's XP, Steam's hours, a song's length and an ENS name's days
///     left are the figure at the edge (prd §1648)
///
/// **A look draws only a fact the bridge stored.** GitHub stores no
/// "merged", so no row says Merged; Cloudflare stores no counts, so no row
/// draws a metric; a voice note's waveform is a whole-file decode, so it keeps
/// its length (§83). Where the fact is missing the row stays `.plain`.
///
/// THE ONE TABLE. Every look is decided here and nowhere else, as
/// `SocialRoom.rowKind` decides a social row: a new app is a case in this
/// function, never a new row design. Foundation-only, so
/// `scripts/feed-look-selftest.sh` compiles it as shipped.
enum FeedLook: Equatable {
    case plain
    /// Your opening question to an agent.
    case agentAsk(String)
    /// Who, why it's here (nil for a post you follow), then their words.
    case post(name: String, context: String?, words: String)
    case mail(sender: String, subject: String)
    /// `place` is "repo #212", or the repository alone.
    case code(title: String, place: String, state: Status?)
    case workout(name: String, figure: String, duration: String?)
    /// `type` is the extension, upper-cased ("PDF").
    case file(name: String, type: String, size: String?)
    /// A Work row's verdict (`WorkStage.outcome`), at the row's edge.
    case status(title: String, Status)
    /// A calendar event: its hours and its place under its title, or
    /// Cancelled. `end` is nil for an all-day event.
    case event(title: String, start: Date, end: Date?, allDay: Bool, place: String?, cancelled: Bool)
    /// Who wrote it over what it is: a publication over its headline.
    case byline(who: String, what: String)
    /// A passage you highlighted, and the book it came from.
    case quote(passage: String, from: String)
    /// An App Store review: its title, who wrote it, its stars out of five.
    case review(title: String, by: String?, stars: Int)
    /// One figure at the row's edge: a version, XP, hours, a length, days.
    case figure(title: String, line: String?, figure: String, style: FigureStyle)

    /// How a `.figure` is set: bold for an amount, code for a version, quiet
    /// for a length, amber for a countdown you need to act on.
    enum FigureStyle: Equatable { case bold, code, quiet, attention }

    struct Status: Equatable {
        let word: String
        let tone: Tone
    }

    /// `WorkStage.Tone`'s inks, by name: red, amber, green, plain.
    enum Tone: String { case failed, waiting, landed, neutral }

    /// What the table reads, as plain values so it compiles without SwiftData.
    struct Facts {
        var source: String
        /// `Thing.kind`'s raw value.
        var kind: String
        var title: String
        var content: String = ""
        var tags: [String] = []
        /// `Thing.mark`'s raw value.
        var mark: String = "none"
        var sourceRef: String? = nil
        /// `AgentSheet.assistant(for:)` is non-nil for this source; then
        /// `content` is the opening question, or empty when it is the title.
        var isAgent = false
        /// `Thing.postText`, never the title: a notice's title already
        /// names the person, and the words would say it twice.
        var postText: String? = nil
        /// `SocialRoomSource.author(of:)`.
        var author: String? = nil
        /// `Thing.socialContext`, raw.
        var socialContext: String? = nil
        /// `SocialThread.contextLabel(for:)`.
        var contextLabel: String? = nil
        /// `BandRow.mailSender`.
        var mailSender: String? = nil
        /// The "Duration" fact a workout carries.
        var duration: String? = nil
        /// `WorkStage.outcome`, mapped to this table's tones.
        var workOutcome: Status? = nil
        /// The row carries a stored price: money keeps its column (§900),
        /// and a verdict beside it would push the figure into the title.
        var hasPrice = false
        /// `Thing.capturedAt`: an event's start.
        var start: Date? = nil
        /// `Thing.endAt`, read for Calendar only.
        var end: Date? = nil
        /// The event's `.allDay` fact.
        var allDay = false
        /// The event's Status fact says Cancelled.
        var cancelled = false
        /// `Thing.authorHandle`: a publication, a book, a reviewer, a game, a name.
        var authorHandle: String? = nil
        /// `Thing.summary`: a Kindle locator, Duolingo's lessons, Steam's hours.
        var summary: String? = nil
        /// Apple Music's Length fact.
        var length: String? = nil
        /// `Thing.dueAt`: an ENS name's expiry.
        var dueAt: Date? = nil
        /// What a countdown counts from.
        var now: Date = .now
    }

    static let postSources: Set<String> = ["X", "Bluesky"]
    static let mailSources: Set<String> = ["Gmail", "iCloud Mail"]
    static let workoutSources: Set<String> = ["Apple Health", "Strava", "Garmin"]
    /// Feeds whose `authorHandle` is the publication or channel.
    static let bylineSources: Set<String> = ["RSS", "Substack", "Podcasts", "YouTube"]
    /// Trackers whose title ends in the issue's key ("— ENG-142").
    static let issueSources: Set<String> = ["Linear", "Jira"]
    static let packageSources: Set<String> = ["npm", "PyPI"]
    /// The sources whose looks read `content`, so a row of any other app
    /// never touches it.
    static let contentSources: Set<String> = ["GitHub", "Files", "Calendar", "Readwise", "Duolingo"]
    /// The sources whose looks read `authorHandle` or `summary`.
    static let handleSources: Set<String> = bylineSources.union(
        ["Kindle", "App Store Connect", "Steam", "Duolingo", "Apple Music", "ENS"])
    /// A notice that names no words of anyone's: a like, a follow, a repost.
    static let wordlessContexts: Set<String> = ["liked", "like", "follow", "recast", "repost"]

    static func of(_ f: Facts) -> FeedLook {
        let title = f.title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Your OPENING QUESTION, never the conversation's name: the
        // importers keep it in `content`, left empty only when it is the
        // title word for word. A name ("Trip plan: Lisbon") is not your
        // words, and your bubble would say they were.
        if f.kind == "chat", f.isAgent {
            let asked = f.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let question = asked.isEmpty ? title : asked
            if !question.isEmpty { return .agentAsk(question) }
        }

        if postSources.contains(f.source),
           !(f.socialContext.map(wordlessContexts.contains) ?? false),
           let words = f.postText?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty,
           let name = f.author, !name.isEmpty {
            return .post(name: name, context: f.contextLabel, words: words)
        }

        if f.kind == "mail", mailSources.contains(f.source),
           let sender = f.mailSender?.trimmingCharacters(in: .whitespaces), !sender.isEmpty,
           !title.isEmpty {
            return .mail(sender: sender, subject: title)
        }

        if f.source == "GitHub", let place = githubPlace(f.content) ?? githubPlace(f.sourceRef ?? ""),
           !title.isEmpty {
            return .code(title: withoutNumber(title), place: place, state: githubState(tags: f.tags, mark: f.mark))
        }

        if workoutSources.contains(f.source), f.sourceRef?.hasPrefix("hkworkout:") == true,
           let split = workout(title) {
            // "Strength · 45 min" already says its time; the duration
            // would say it again.
            let duration = split.figure == f.duration ? nil : f.duration
            return .workout(name: split.name, figure: split.figure, duration: duration)
        }

        if f.source == "Files", f.kind == "file", let type = fileType(title) {
            return .file(name: title, type: type, size: byteCount(f.content))
        }

        // An event says its hours, not "in 4h": the start and the end the
        // calendar stored, and the place its line already carries.
        if f.source == "Calendar", f.sourceRef?.hasPrefix("ekevent:") == true,
           let start = f.start, !title.isEmpty {
            return .event(title: title, start: start, end: f.allDay ? nil : f.end,
                          allDay: f.allDay, place: eventPlace(f.content), cancelled: f.cancelled)
        }

        // An issue is GitHub's look: its key in code type, its state from the
        // mark the tracker set. The tracker's own status name is not stored.
        if issueSources.contains(f.source), let split = issueKey(title) {
            return .code(title: split.name, place: split.key, state: issueState(mark: f.mark))
        }
        if f.source == "Sentry", let split = sentryIssue(title) {
            let regressed = f.tags.contains("Regression")
            return .code(title: split.name, place: split.id,
                         state: regressed ? Status(word: String(localized: "Regression"), tone: .waiting) : nil)
        }

        if packageSources.contains(f.source) {
            if f.tags.contains("Release"), let split = release(title) {
                return .figure(title: split.name, line: nil, figure: split.version, style: .code)
            }
            if f.tags.contains("Deprecated"), let name = deprecatedName(title) {
                return .status(title: name, Status(word: String(localized: "Deprecated"), tone: .failed))
            }
        }

        if f.source == "App Store Connect", f.tags.contains("Review"), let split = review(title) {
            let by = f.authorHandle?.trimmingCharacters(in: .whitespaces)
            return .review(title: split.name, by: by?.isEmpty == false ? by : nil, stars: split.stars)
        }

        if bylineSources.contains(f.source), !title.isEmpty,
           let who = f.authorHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !who.isEmpty, who != f.source, who != title {
            return .byline(who: who, what: title)
        }

        // A highlight is the passage, quoted, and the book under it. Kindle
        // keeps the book in `authorHandle` and the page in `summary`;
        // Readwise keeps the book in `content`.
        if f.kind == "note", !title.isEmpty {
            if f.source == "Kindle", let book = f.authorHandle?.trimmingCharacters(in: .whitespaces), !book.isEmpty {
                let page = f.summary?.trimmingCharacters(in: .whitespaces)
                let from = [book, page].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return .quote(passage: title, from: from)
            }
            if f.source == "Readwise" {
                let book = f.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !book.isEmpty, !book.hasPrefix("http") { return .quote(passage: title, from: book) }
            }
        }

        if f.source == "Duolingo", let split = duolingo(title) {
            let line = [f.summary, f.content]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !$0.hasPrefix("http") }
            return .figure(title: split.course, line: line, figure: split.xp, style: .bold)
        }

        if f.source == "Steam", title.hasPrefix("Played "), let split = steamHours(f.summary ?? "") {
            let handle = f.authorHandle?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = handle.isEmpty ? String(title.dropFirst("Played ".count)) : handle
            return .figure(title: name, line: split.rest, figure: split.hours, style: .bold)
        }

        if f.source == "Apple Music", let length = f.length?.trimmingCharacters(in: .whitespaces),
           !length.isEmpty, !title.isEmpty {
            let seam = TitleSeam.split(title)
            return .figure(title: seam.name, line: seam.line ?? f.authorHandle, figure: length, style: .quiet)
        }

        // A name you watch counts down to its expiry; the stored title never
        // says "in N days", which would be wrong by morning. A lapsed name
        // keeps its title, which already says so.
        if f.source == "ENS", let due = f.dueAt, due > f.now,
           let name = f.authorHandle?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            let figure = daysUntil(due, from: f.now)
            return .figure(title: name, line: nil, figure: figure,
                           style: f.tags.contains("Expiring") ? .attention : .quiet)
        }

        if !f.hasPrice, let outcome = f.workOutcome, outcome.tone != .neutral, !title.isEmpty {
            return .status(title: title, outcome)
        }

        return .plain
    }

    // MARK: - The parsers, each over a stored string

    /// "repo #212" from a github.com pull or issue URL; the repository alone
    /// from any other github.com path under an owner.
    static func githubPlace(_ text: String) -> String? {
        guard let range = text.range(of: "https://github.com/") else { return nil }
        let tail = text[range.upperBound...].prefix { !$0.isWhitespace }
        let parts = tail.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let repo = parts[1]
        if parts.count >= 4, ["pull", "issues"].contains(parts[2]),
           let number = Int(parts[3].prefix { $0.isNumber }) {
            return "\(repo) #\(number)"
        }
        return repo
    }

    /// A pull request's title ends in its number, "(#414)", which the place
    /// line already says.
    static func withoutNumber(_ title: String) -> String {
        guard let r = title.range(of: #"\s*\(#[0-9]+\)$"#, options: .regularExpression) else { return title }
        let rest = String(title[..<r.lowerBound])
        return rest.isEmpty ? title : rest
    }

    /// The state the GitHub bridge stamps: a failing check, a review or an
    /// assignment asked of you, or closed. Never "Merged": not stored.
    static func githubState(tags: [String], mark: String) -> Status? {
        let set = Set(tags)
        if set.contains("Checks failing") { return Status(word: String(localized: "Failing"), tone: .failed) }
        if set.contains("Review") { return Status(word: String(localized: "Review"), tone: .waiting) }
        if set.contains("Assigned") { return Status(word: String(localized: "Assigned"), tone: .waiting) }
        if mark == "done" { return Status(word: String(localized: "Closed"), tone: .neutral) }
        return nil
    }

    /// "Run · 5.2 km" → ("Run", "5.2 km"); a title with no figure is nil.
    static func workout(_ title: String) -> (name: String, figure: String)? {
        guard let seam = title.range(of: " · ") else { return nil }
        let name = String(title[..<seam.lowerBound]).trimmingCharacters(in: .whitespaces)
        let figure = String(title[seam.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, figure.first?.isNumber == true else { return nil }
        return (name, figure)
    }

    /// The extension a file name ends in, up to five letters or digits.
    static func fileType(_ name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...]
        guard (1...5).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return ext.uppercased()
    }

    /// The place in an event's line, "14:00 · Studio 3" → "Studio 3".
    static func eventPlace(_ line: String) -> String? {
        guard let seam = line.range(of: " · ") else { return nil }
        let place = line[seam.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? nil : place
    }

    /// "Paste freezes — ENG-142" → ("Paste freezes", "ENG-142").
    static func issueKey(_ title: String) -> (name: String, key: String)? {
        let seam = TitleSeam.split(title)
        guard let line = seam.line else { return nil }
        let name = seam.name.trimmingCharacters(in: .whitespaces)
        let key = line.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, key.range(of: #"^[A-Z][A-Z0-9_]*-[0-9]+$"#, options: .regularExpression) != nil
        else { return nil }
        return (name, key)
    }

    /// The mark a tracker set: started is In progress, finished or
    /// cancelled is Closed (Linear's `completed` and `canceled` both land
    /// done, so Done would be a guess).
    static func issueState(mark: String) -> Status? {
        switch mark {
        case "doing": Status(word: String(localized: "In progress"), tone: .neutral)
        case "done":  Status(word: String(localized: "Closed"), tone: .neutral)
        default:      nil
        }
    }

    /// "Regressed · web · QUILL-3F · TypeError: x" → ("TypeError: x", "QUILL-3F").
    static func sentryIssue(_ title: String) -> (name: String, id: String)? {
        let parts = title.components(separatedBy: " · ")
        guard let at = parts.firstIndex(where: {
            $0.range(of: #"^[A-Z0-9][A-Z0-9_-]*-[A-Z0-9]+$"#, options: .regularExpression) != nil
        }), at + 1 < parts.count else { return nil }
        let name = parts[(at + 1)...].joined(separator: " · ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, parts[at])
    }

    /// "quill-parser 2.4.1" → ("quill-parser", "2.4.1").
    static func release(_ title: String) -> (name: String, version: String)? {
        guard let space = title.lastIndex(of: " ") else { return nil }
        let name = title[..<space].trimmingCharacters(in: .whitespaces)
        let version = String(title[title.index(after: space)...])
        guard !name.isEmpty, version.first?.isNumber == true else { return nil }
        return (name, version)
    }

    /// "Deprecated · fold-tools" → "fold-tools".
    static func deprecatedName(_ title: String) -> String? {
        guard let seam = title.range(of: " · ") else { return nil }
        let name = title[seam.upperBound...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// "Finally — ★★★★☆ · Quillmark" → ("Finally", 4). The stars are the
    /// only rating stored; a review with none stays plain.
    static func review(_ title: String) -> (name: String, stars: Int)? {
        let seam = TitleSeam.split(title)
        guard let line = seam.line else { return nil }
        let name = seam.name.trimmingCharacters(in: .whitespaces)
        let run = line.trimmingCharacters(in: .whitespaces).prefix { $0 == "★" || $0 == "☆" }
        let stars = run.filter { $0 == "★" }.count
        guard !name.isEmpty, run.count == 5 else { return nil }
        return (name, stars)
    }

    /// "40 XP in Spanish" → ("40 XP", "Spanish").
    static func duolingo(_ title: String) -> (xp: String, course: String)? {
        guard let seam = title.range(of: " XP in ") else { return nil }
        let count = title[..<seam.lowerBound]
        let course = title[seam.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !count.isEmpty, count.allSatisfy(\.isNumber), !course.isEmpty else { return nil }
        return ("\(count) XP", course)
    }

    /// "1.5h past two weeks · 40.2h all time" → ("1.5h", "past two weeks · 40.2h all time").
    static func steamHours(_ summary: String) -> (hours: String, rest: String?)? {
        let s = summary.trimmingCharacters(in: .whitespaces)
        guard let space = s.firstIndex(of: " ") else { return nil }
        let hours = String(s[..<space])
        guard hours.hasSuffix("h"), hours.first?.isNumber == true else { return nil }
        let rest = s[s.index(after: space)...].trimmingCharacters(in: .whitespaces)
        return (hours, rest.isEmpty ? nil : rest)
    }

    /// Whole days to a date: "Today", "1 day", "23 days".
    static func daysUntil(_ date: Date, from now: Date) -> String {
        let days = Int((date.timeIntervalSince(now) / 86_400).rounded(.down))
        switch days {
        case ..<1: return String(localized: "Today")
        case 1:    return String(localized: "1 day")
        default:   return String(localized: "\(days) days")
        }
    }

    /// The size `FilesBridge` writes for a file it holds no text of
    /// ("2.3 MB"), else nil: a text file's content is its words.
    static func byteCount(_ content: String) -> String? {
        let s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count <= 12,
              s.range(of: #"^[0-9][0-9.,]*\s?(bytes|KB|MB|GB|TB)$"#, options: .regularExpression) != nil
        else { return nil }
        return s
    }
}
