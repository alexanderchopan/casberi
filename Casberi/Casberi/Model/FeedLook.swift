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
    }

    static let postSources: Set<String> = ["X", "Bluesky"]
    static let mailSources: Set<String> = ["Gmail", "iCloud Mail"]
    static let workoutSources: Set<String> = ["Apple Health", "Strava", "Garmin"]
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
