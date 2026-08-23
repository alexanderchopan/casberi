import Foundation
import SwiftData

// MARK: - The pure half

/// Everything about a Claude Code transcript that has a right answer, with no
/// SwiftData, no `ModelContext` and no file system in it — so
/// `scripts/claudecode-selftest.sh` can compile it out of this file and put
/// known inputs through it.
///
/// **MEASURED 2026-08-23 (prd §457)** against 470 real transcripts —
/// 247,085 lines, every file under a real `~/.claude/projects`. This header
/// said UNMEASURED for fifteen days and listed four field-name guesses to
/// re-measure first. Three were right. The fourth was wrong, and it was the
/// one that decided what every row in this room is CALLED:
///
///   1. `type` is the kind key ✓ — and `user` / `assistant` / `system` are
///      real values ✓. **But `summary` is not: it appears ZERO times in
///      247,085 lines.** A session's own name lives on its own line kinds,
///      `custom-title` (key `customTitle`) and `ai-title` (key `aiTitle`),
///      and 469 of the 470 files carry at least one. So `summaryText`'s
///      `kind == "summary"` guard never once passed: every session fell back
///      to its opening ask for a headline, and `Thing.summary` — documented
///      below as "Claude Code's own session summary" — was **always nil**.
///      See `titleText`.
///   2. `message.content` really is a bare string OR an array of typed
///      blocks ✓ (350 string, 11,188 array in the sample). Block types are
///      `text`, `thinking`, `tool_use`, `tool_result`, `image`; a text
///      block's only keys are `type` and `text`. `blockText`'s take-only-
///      `text` rule is therefore right as written, and drops `thinking`
///      correctly — reasoning is not what the person wrote or was told.
///   3. `cwd` is present ✓ on every user/assistant line (13,227 of 13,227).
///   4. The timestamp is `timestamp` ✓, ISO-8601 with three fractional
///      digits and a `Z` — which `isoFractional` parses. Note it is absent
///      from title and `queue-operation` lines, so the "first line that
///      carries one" rule is load-bearing rather than incidental: the FIRST
///      line of a file is a `queue-operation` in 456 of 470 files.
///
/// Line kinds the original parse never knew existed, all correctly ignored
/// by `turn`: `attachment`, `last-prompt`, `queue-operation`, `mode`,
/// `atis-latch`, `frame-link`, `pr-link`, `artifact-comment-monitor`.
/// `isSidechain` was false on all 247,085 lines and `userType` always
/// `external`, so no subagent transcript is inlined in this corpus today.
///
/// Everything else here keeps its schema tolerance — candidate key paths
/// rather than one, and a miss that SKIPS rather than landing a wrong row —
/// because one measurement of one version is not a contract.
enum ClaudeCodeSession {

    // MARK: Shapes

    /// One session, flattened. Everything a `Thing` needs and nothing else.
    struct Parsed {
        var sessionId: String
        /// The project this session ran in — the folder name, not the path.
        var project: String
        /// The headline: the session's own NAME when the transcript carries
        /// one (see `titleText`), else the opening ask. Never empty for a
        /// `Parsed` that exists.
        var headline: String
        /// The session's own name, kept apart from `headline` so a caller can
        /// tell a real name from the fallback — which is what decides whether
        /// the opening ask is worth drawing as a subtitle underneath.
        ///
        /// Nil is rare but real: 1 of 470 measured transcripts carried no
        /// title line of any kind.
        var sessionTitle: String?
        /// The opening ask, kept separately from `headline` so the row can
        /// show both when they differ (a summarised session) and neither
        /// twice when they don't.
        var opener: String
        /// The whole conversation as prose, for retrieval only.
        var transcript: String
        /// Real turns — user and assistant lines, tool traffic included, since
        /// a turn spent entirely on tools is still a turn that happened.
        var messageCount: Int
        /// The FIRST timestamp in the file, so a first import sorts back into
        /// history instead of claiming a day's worth of urgency.
        var startedAt: Date?
    }

    /// One line's worth of what we care about, after the shape-tolerance.
    struct Turn {
        var role: String
        var text: String
    }

    // MARK: Budgets

    /// How much of one conversation is kept for retrieval. Generous, because
    /// this is the only body a session will ever have and nothing displays it,
    /// but not unbounded: a long agentic session can run to megabytes of tool
    /// output, and `Thing.enrichedText` rides the CloudKit-mirrored store.
    static let transcriptLimit = 16_000

    /// A single turn's share of that budget. Without it one enormous pasted
    /// file in message three eats the whole conversation and the rest of the
    /// session is invisible to search — which reads exactly like a session
    /// that was never imported.
    static let turnLimit = 2_000

    /// The most sessions one tap will land. A person who has used Claude Code
    /// daily for a year has hundreds; this covers that outright. What it
    /// bounds is how much of a very long history belongs in one tap — and any
    /// history past it SAYS SO (`Summary.dropped`) rather than truncating in
    /// silence, which is §307's lesson and the reason this number is not just
    /// a `prefix`.
    static let sessionCap = 2_000

    // MARK: Field readers (schema-tolerant by design)

    /// The first non-empty string among `keys`, tried in order.
    ///
    /// Every read below goes through this rather than naming one key, for the
    /// TikTok reason: field case has been observed to vary WITHIN one export
    /// file, so a reader that knows one spelling is a reader that works on
    /// half a file. A key that is present but not a string is treated as
    /// absent, never coerced.
    static func string(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            guard let raw = object[key] as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// The first dictionary among `keys`.
    static func object(_ object: [String: Any], _ keys: [String]) -> [String: Any]? {
        for key in keys {
            if let nested = object[key] as? [String: Any] { return nested }
        }
        return nil
    }

    /// A line's kind — `user`, `assistant`, `summary`, `system`, or whatever
    /// else a future version writes. Lowercased so a capitalised variant can't
    /// slip past the switches that read it.
    static func kind(_ line: [String: Any]) -> String? {
        string(line, ["type", "Type", "kind"])?.lowercased()
    }

    /// The session id. `sessionId` is the documented spelling; the snake case
    /// is carried because half of everything that writes JSONL uses it, and
    /// the FILENAME is the last resort — the file is named for the session, so
    /// a transcript that names itself nowhere inside is still identifiable.
    static func sessionID(_ line: [String: Any]) -> String? {
        string(line, ["sessionId", "session_id", "sessionID"])
    }

    /// The working directory a line ran in. The only unambiguous project name
    /// available — see `projectName`.
    static func workingDirectory(_ line: [String: Any]) -> String? {
        string(line, ["cwd", "workingDirectory", "working_directory", "projectPath", "project_path"])
    }

    /// Which kind of name a title line carries. Ranked: a name the person set
    /// beats one that was generated, and both beat the legacy `summary` line.
    enum TitleKind: Int, Comparable {
        /// A `summary` line — the shape this parser was written against and
        /// which no measured transcript has. Kept because an older history on
        /// disk is exactly what this importer exists to reach.
        case legacy = 0
        /// `ai-title`.aiTitle — generated from the conversation.
        case generated = 1
        /// `custom-title`.customTitle.
        case custom = 2

        static func < (a: TitleKind, b: TitleKind) -> Bool { a.rawValue < b.rawValue }
    }

    /// A title line's own text and which kind it is, or nil for any other line.
    ///
    /// Claude Code writes these as their own records rather than as a field on
    /// a message, so this reads the line and not `message`.
    ///
    /// **MEASURED (see the type header): there are no `summary` lines.** The
    /// name lives on `custom-title` / `ai-title`, and 469 of 470 files carry
    /// one — so the guard this replaces meant a session was named after its
    /// opening ask ("ok do all", "why is it 404ing") instead of after itself.
    ///
    /// The two kinds usually DISAGREE — the last `customTitle` differed from
    /// the last `aiTitle` in 437 of the 460 files carrying both — so which one
    /// wins is a real decision and not a formality. `custom` leads on the rule
    /// this codebase already applies to a fetched handle beating an archived
    /// one (§375): the more specific claim about what this session is wins,
    /// and a title somebody set for themselves is the most specific there is.
    static func titleText(_ line: [String: Any]) -> (kind: TitleKind, text: String)? {
        switch kind(line) {
        case "custom-title":
            return string(line, ["customTitle", "custom_title", "title"])
                .map { (.custom, $0) }
        case "ai-title":
            return string(line, ["aiTitle", "ai_title", "title"])
                .map { (.generated, $0) }
        case "summary":
            let text = string(line, ["summary", "text", "title"])
                ?? object(line, ["message"]).flatMap { string($0, ["summary", "text", "content"]) }
            return text.map { (.legacy, $0) }
        default:
            return nil
        }
    }

    /// The role of a message line — from `message.role` where it lives, or the
    /// line's own `type`, which carries the same word for the two kinds that
    /// matter. Anything that isn't a real conversational turn returns nil.
    static func role(_ line: [String: Any]) -> String? {
        let nested = object(line, ["message", "Message"])
        let raw = nested.flatMap { string($0, ["role", "Role", "sender"]) }
            ?? string(line, ["role", "sender"])
            ?? kind(line)
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "user", "human":     return "user"
        case "assistant", "ai":   return "assistant"
        default:                  return nil
        }
    }

    /// A message's prose.
    ///
    /// `content` is EITHER a plain string OR an array of typed blocks, and the
    /// array form is the one that matters: a Claude Code turn is mostly
    /// `tool_use` and `tool_result` blocks, which are machine traffic and must
    /// NOT land as writing. A room searchable by "the file I edited" would be
    /// a room where every session matches every query — the `t.co` failure
    /// (§313) in a different corpus.
    ///
    /// Only `text` blocks contribute. A block whose type is missing is read as
    /// text ONLY if it carries a `text` field and nothing tool-shaped, since a
    /// future block kind we don't know about is more likely to be prose than
    /// to be a tool call — and if we're wrong, the cost is one stray line in a
    /// retrieval body rather than a wrong row.
    static func blockText(_ content: Any?) -> String {
        if let plain = content as? String { return plain }
        guard let blocks = content as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for block in blocks {
            let type = string(block, ["type", "Type"])?.lowercased()
            if let type, type != "text" { continue }
            // A tool block that omits its type is still recognisable by what
            // it carries. Checked even when `type == "text"`, because a
            // mislabelled block is exactly the case a type check can't see.
            if block["tool_use_id"] != nil || block["toolUseId"] != nil
                || block["input"] != nil || block["tool_use"] != nil { continue }
            guard let text = string(block, ["text", "Text", "content"]) else { continue }
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }

    /// One line as a conversational turn, or nil if it isn't one.
    static func turn(_ line: [String: Any]) -> Turn? {
        guard let role = role(line) else { return nil }
        let message = object(line, ["message", "Message"])
        let text = blockText(message?["content"] ?? line["content"])
        return Turn(role: role, text: clamp(text, to: turnLimit))
    }

    // MARK: Project identity

    /// The project name.
    ///
    /// `cwd` is preferred and the directory name is the fallback, and the
    /// order is the whole point: Claude Code's directory name is the project
    /// path with every `/` replaced by `-`, which is NOT reversible — a real
    /// path `/Users/x/Developer/my-project` and `/Users/x/Developer/my/project`
    /// encode to the same string. So a decode is a guess, and `cwd` is the
    /// path itself. Getting this wrong doesn't fail loudly: the room simply
    /// files a person's sessions under a project name they never used.
    static func projectName(cwd: String?, directory: String?) -> String {
        if let cwd, let last = lastComponent(ofPath: cwd) { return last }
        guard let directory else { return "" }
        return lastComponent(ofPath: decodeProjectDirectory(directory)) ?? ""
    }

    /// `-Users-x-Developer-foo` → `/Users/x/Developer/foo`.
    ///
    /// Lossy by construction (see `projectName`) and used only when `cwd` is
    /// absent. A name with no leading separator is returned as-is rather than
    /// mangled — that shape is somebody's plain folder, not an encoding.
    static func decodeProjectDirectory(_ name: String) -> String {
        guard name.hasPrefix("-") else { return name }
        return name.replacingOccurrences(of: "-", with: "/")
    }

    /// The last non-empty path component, trailing separators tolerated.
    static func lastComponent(ofPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = parts.last else { return nil }
        let name = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: Composition

    /// The title.
    ///
    /// **The project LEADS.** A session's own headline is a fragment written
    /// against a context you had at the time ("fix the flaky one", "why is it
    /// 404ing") and is close to meaningless a month later in a list of four
    /// hundred siblings — the same reason a repo leads a Cursor run and a
    /// board leads a Trello card (§303). It also survives `titleLine`'s
    /// 80-char clamp, which a trailing project name would not.
    static func title(project: String, headline: String) -> String {
        let head = headline.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = project.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return head }
        if head.isEmpty { return name }
        return name + " · " + head
    }

    /// The transcript, as prose.
    ///
    /// Speakers are named because the retrieval body is read as one text: an
    /// unlabelled flatten makes what you asked and what Claude answered
    /// indistinguishable, and "did I ask about X" is the question this room
    /// exists to answer.
    static func transcript(_ turns: [Turn]) -> String {
        var out = ""
        for turn in turns where !turn.text.isEmpty {
            let label = turn.role == "user" ? "You: " : "Claude: "
            if !out.isEmpty { out += "\n\n" }
            out += label + turn.text
            if out.count >= transcriptLimit { break }
        }
        return clamp(out, to: transcriptLimit)
    }

    /// A character clamp that never splits a scalar and never returns a
    /// misleadingly whole-looking string — the ellipsis is the marker that
    /// something was cut.
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// The opening ask, clamped for a title.
    static func opener(_ turns: [Turn]) -> String {
        for turn in turns where turn.role == "user" {
            let line = turn.text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // A `/command` or a bare mechanical line names nothing.
            guard !line.isEmpty else { continue }
            return clamp(line, to: 200)
        }
        return ""
    }

    // MARK: The whole parse

    /// One `.jsonl` transcript.
    ///
    /// `fileName` is the session uuid Claude Code names the file for, and
    /// `directory` the encoded project folder — both are fallbacks for facts
    /// the file is supposed to carry itself, and both are supplied by the
    /// caller so this stays free of the file system.
    ///
    /// Returns nil for a file with nothing conversational in it. That is a
    /// SKIP and not a failure: a transcript that is all system lines, or a
    /// file some other tool left in the folder, must not land a row whose
    /// title is a guess.
    static func parse(jsonl: String, fileName: String?, directory: String?) -> Parsed? {
        var turns: [Turn] = []
        var named: (kind: TitleKind, text: String)?
        var identifier: String?
        var cwd: String?
        var startedAt: Date?

        for raw in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if identifier == nil { identifier = sessionID(object) }
            if cwd == nil { cwd = workingDirectory(object) }
            // **THE LAST NAME WINS, not the first** — the opposite of every
            // other read in this loop, and measured: a transcript carries a
            // title line every few turns (median 23 per file, up to 1,615),
            // rewritten as the session finds out what it is about. The last
            // `customTitle` differed from that file's first in 75 of the 378
            // files carrying more than one, so first-wins names a long session
            // after the thing it started out as.
            //
            // `>=` rather than `>` is what makes it last-wins WITHIN a kind
            // while still refusing to let a later generated title overwrite a
            // custom one.
            if let found = titleText(object), found.kind >= (named?.kind ?? .legacy) {
                named = found
            }
            // The FIRST date wins, and a title line's own stamp counts as much
            // as a message's — a session is dated by when it started, and
            // every line carrying one agrees about that. Note the title and
            // `queue-operation` lines carry NO timestamp at all, and the first
            // line of a file is a `queue-operation` in 456 of 470 measured
            // files, so this really does have to look past the opening lines.
            if startedAt == nil, let when = parseDate(string(object, dateKeys)) {
                startedAt = when
            }
            if let turn = turn(object) { turns.append(turn) }
        }

        let body = transcript(turns)
        let first = opener(turns)
        let sessionTitle = named?.text
        let headline = sessionTitle ?? first
        // Nothing to name it by AND nothing in it — not a session.
        guard !headline.isEmpty || !body.isEmpty else { return nil }
        guard let id = identifier ?? fileName.map(stem), !id.isEmpty else { return nil }

        let project = projectName(cwd: cwd, directory: directory)
        return Parsed(
            sessionId: id,
            project: project,
            headline: headline.isEmpty ? String(localized: "Session") : headline,
            sessionTitle: sessionTitle,
            opener: first,
            transcript: body,
            messageCount: turns.count,
            startedAt: startedAt)
    }

    /// A filename without its extension — the session uuid.
    static func stem(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: ".") else { return fileName }
        return String(fileName[fileName.startIndex..<dot])
    }

    /// Every spelling of the timestamp worth trying, in order of likelihood.
    static let dateKeys = ["timestamp", "Timestamp", "createdAt", "created_at", "time", "ts"]

    // MARK: Dates

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// An ISO-8601 stamp, tolerant of a fraction of any length.
    ///
    /// **TWO formatters, and the pair is the point — measured 2026-08-08, so
    /// don't collapse it.** A formatter carrying `.withFractionalSeconds`
    /// accepts a fraction of ANY length (1, 2, 3, 6 and 9 digits all parse,
    /// with a `Z` or a numeric offset) and REFUSES a stamp with no fraction at
    /// all; a formatter without it does the exact opposite. Claude Code writes
    /// JSONL from a JavaScript runtime, whose `toISOString` emits three digits
    /// — but the version that writes a whole-second stamp, or a future one on
    /// another runtime, must not read as an undated session.
    ///
    /// The trailing fraction STRIP is `ClaudeImport.parseDate`'s belt-and-
    /// braces, kept for a writer neither formatter above recognises, and it is
    /// honestly dead against every shape measured so far — it is deliberately
    /// NOT claimed as load-bearing in the harness, because a mutation nothing
    /// can catch is a check that proves nothing.
    ///
    /// A wrong answer here is not a wrong DATE, it is `nil`, which is why this
    /// can be strict: the caller falls back to another line rather than to
    /// `.now`.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = isoFractional.date(from: raw) { return d }
        if let d = isoPlain.date(from: raw) { return d }
        let stripped = raw.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return stripped == raw ? nil : isoPlain.date(from: stripped)
    }
}

// MARK: - The landing half

/// Claude Code, connected — by import, the ChatGPT grade, and for a reason
/// stronger than any of the three chat seats beside it: Claude Code writes its
/// history to your own disk as JSONL and offers no read of any kind, live or
/// exported. There is nothing to sign into. The files are simply there.
///
/// **ONE THING PER SESSION.** A session is the unit somebody remembers ("the
/// afternoon I got the migration working"), a message is not, and a
/// message-per-row import of a year of agentic work would bury the corpus
/// under tool traffic. So the whole conversation rides `enrichedText`
/// (retrieval-only by the 2026-07-15 ruling — nothing draws it; it feeds the
/// embedding index and the content scan), `messageCount` carries the real turn
/// count, and `summary` carries Claude Code's own session summary when the
/// transcript has one, which is the only text here that is display copy.
///
/// **SESSIONS GROW.** Unlike a finished ChatGPT export, a transcript is
/// appended to — so a re-import HEALS a row in place (transcript, turn count,
/// summary, title) rather than skipping it. That is the only way a re-import
/// can be worth running twice.
///
/// **UNMEASURED** — see `ClaudeCodeSession`'s note. Every read here fails safe:
/// an unreadable file is skipped, a folder with no transcripts under it is
/// reported as "this isn't a Claude Code folder", and no row is ever landed on
/// a guessed field.
enum ClaudeCodeImport {

    static let source = "Claude Code"
    static let seatID = "claudecode"

    struct Summary {
        /// New sessions landed.
        var imported = 0
        /// Sessions already here that GREW since the last import and were
        /// updated in place. Counted apart from `imported` because they are a
        /// different fact: one is history arriving, the other is history
        /// catching up.
        var healed = 0
        /// Already here and unchanged.
        var skipped = 0
        /// What the cap refused. Reported rather than swallowed — a truncated
        /// import renders exactly like a complete one, and the person is the
        /// only one who can tell whether the missing sessions matter (§307).
        var dropped = 0
        /// How many distinct projects the pick covered — the one number that
        /// tells "I picked a single project folder" from "I picked the whole
        /// `projects` directory", which is otherwise invisible.
        var projects = 0
        var failed = false

        var landed: Int { imported + healed }
    }

    // MARK: - Run

    /// Imports a Claude Code transcript folder.
    ///
    /// The pick is EITHER `~/.claude/projects` (project folders, each holding
    /// `<uuid>.jsonl`) OR a single project folder. Both work rather than the
    /// screen having to explain the difference — the same coin flip
    /// `XArchiveImport.read` handles for an unzipped archive.
    ///
    /// `failed` is reserved for "there are no transcripts under this at all".
    @MainActor
    static func run(folder: URL, context: ModelContext,
                    progress: ((Int) -> Void)? = nil) async -> Summary {
        var summary = Summary()

        let files = transcriptFiles(under: folder)
        guard !files.isEmpty else { return Summary(failed: true) }

        // Newest first by the FILE's own modification date, then capped —
        // rather than parsing everything and sorting by the session's real
        // start. Parsing thousands of transcripts to decide which thousand to
        // keep is work thrown away, and an mtime tracks a session's last
        // activity closely enough to rank by. The rows themselves are still
        // dated from inside the file, which is what actually matters.
        let ordered = files.sorted { $0.modified > $1.modified }
        summary.dropped = max(0, ordered.count - ClaudeCodeSession.sessionCap)
        let chosen = ordered.prefix(ClaudeCodeSession.sessionCap)

        // As THINGS and not just refs: a session that grew has to be reached
        // and updated, and the folder is a temporary scoped pick, so no later
        // foreground sweep can do it instead.
        let existing = IngestSupport.thingsByRef(context, source: source)
        var landed: [Thing] = []
        var seen = Set<String>()
        var projects = Set<String>()

        for file in chosen {
            guard let text = try? String(contentsOf: file.url, encoding: .utf8) else {
                continue
            }
            guard let parsed = ClaudeCodeSession.parse(
                jsonl: text,
                fileName: file.url.lastPathComponent,
                directory: file.directory) else { continue }

            if !parsed.project.isEmpty { projects.insert(parsed.project) }
            let ref = "claudecode:\(parsed.sessionId)"
            guard seen.insert(ref).inserted else { continue }

            if let already = existing[ref] {
                // Grown? The turn count is the honest test — a transcript's
                // byte length also moves when nothing conversational happened.
                if heal(already, with: parsed) { summary.healed += 1 }
                else { summary.skipped += 1 }
                continue
            }
            landed.append(thing(from: parsed, ref: ref))
            summary.imported += 1
        }

        summary.projects = projects.count
        // The heals are already on live models in this context; the new rows
        // go down in chunks that each save and yield (`ImportCommit`), so a
        // large first import doesn't hold the main thread (§310).
        guard await ImportCommit.commit(landed, context: context,
                                        source: "Claude Code", progress: progress) else {
            return Summary(failed: true)
        }
        if summary.healed > 0, (try? context.save()) == nil {
            return Summary(failed: true)
        }
        return summary
    }

    // MARK: - Rows

    @MainActor
    private static func thing(from parsed: ClaudeCodeSession.Parsed, ref: String) -> Thing {
        let thing = Thing(
            kind: .chat,
            title: IngestSupport.titleLine(
                ClaudeCodeSession.title(project: parsed.project, headline: parsed.headline)),
            // The subtitle is the opening ask, and only when it isn't already
            // the headline — echoing the title back under itself is the §220
            // finding, which `ClaudeImport` pays for one seat over.
            content: parsed.opener == parsed.headline ? "" : parsed.opener,
            source: source,
            capturedAt: parsed.startedAt ?? .now,
            // The project is a TAG so the room narrows by it — the one filter
            // a corpus of sessions actually wants. "Session" names the kind of
            // thing this is, the way `Conversation`/`Memory` do one room over.
            tags: parsed.project.isEmpty ? ["Session"] : ["Session", parsed.project],
            sourceRef: ref)
        thing.enrichedText = parsed.transcript
        thing.messageCount = parsed.messageCount
        // `Thing.summary` is deliberately NOT set (2026-08-23, prd §457). It
        // used to carry `Parsed.summary`, which the measurement showed was
        // always nil — and now that the session's own name is the HEADLINE,
        // putting it here too would print the title a second line below
        // itself, which is the redundancy §451/§452 swept out of every other
        // room. The opening ask is the subtitle, on `content` above.
        return thing
    }

    /// Updates a session that grew. Returns whether anything actually changed —
    /// a re-import of an untouched history must report "nothing new", not a
    /// pile of phantom updates.
    ///
    /// Deliberately does NOT re-date the row. `capturedAt` is when the session
    /// STARTED, and a session you added two messages to yesterday did not
    /// start yesterday; re-dating it would march every long-lived project's
    /// sessions to the top of the feed on every import.
    /// **It also repairs a row landed by a build that read no title** (2026-08-23,
    /// prd §457). Every session imported before that measurement is named after
    /// its opening ask; a re-import is the only thing that can reach it, since
    /// the transcript lives nowhere but on disk behind a scoped pick. So the
    /// title comparison is part of the changed test rather than a write made
    /// only when something else already changed.
    @MainActor
    private static func heal(_ thing: Thing, with parsed: ClaudeCodeSession.Parsed) -> Bool {
        guard thing.isLive else { return false }
        let grew = parsed.messageCount > (thing.messageCount ?? 0)
        let bodyChanged = thing.enrichedText != parsed.transcript
        let wantedTitle = IngestSupport.titleLine(
            ClaudeCodeSession.title(project: parsed.project, headline: parsed.headline))
        let wantedSubtitle = parsed.opener == parsed.headline ? "" : parsed.opener
        let renamed = thing.title != wantedTitle || thing.content != wantedSubtitle
        guard grew || bodyChanged || renamed else { return false }
        thing.title = wantedTitle
        thing.content = wantedSubtitle
        // The transcript is rewritten only when it really moved. A rename on
        // its own must not drop the vector: re-embedding several hundred
        // sessions because they were renamed is work with no answer at the end
        // of it, and the words the vector was computed from have not changed.
        if grew || bodyChanged {
            thing.enrichedText = parsed.transcript
            thing.messageCount = parsed.messageCount
            // The words changed, so the vector computed from the old ones is
            // stale — dropped so the next semantic sweep re-embeds on what the
            // session actually says now.
            thing.embedding = nil
            thing.topicsAt = nil
        }
        return true
    }

    // MARK: - The folder walk

    struct TranscriptFile {
        let url: URL
        /// The name of the folder the file sits in — the encoded project path,
        /// and the fallback project name when a transcript carries no `cwd`.
        let directory: String?
        let modified: Date
    }

    /// Every `.jsonl` under the pick, at the pick itself and one level down.
    ///
    /// TWO levels and no more, on purpose: `~/.claude/projects/<project>/<uuid>.jsonl`
    /// is the deep case and a single project folder is the shallow one, so a
    /// deeper walk could only ever find somebody's unrelated JSONL — a
    /// recursive enumerate over a home directory is a way to import things
    /// nobody meant to pick.
    static func transcriptFiles(under root: URL) -> [TranscriptFile] {
        var out: [TranscriptFile] = []
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]

        func collect(in folder: URL, directory: String?) {
            let children = (try? manager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys)) ?? []
            for child in children {
                let values = try? child.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory != true else { continue }
                guard child.pathExtension.lowercased() == "jsonl" else { continue }
                out.append(TranscriptFile(
                    url: child,
                    directory: directory,
                    modified: values?.contentModificationDate ?? .distantPast))
            }
        }

        collect(in: root, directory: root.lastPathComponent)
        let children = (try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            collect(in: child, directory: child.lastPathComponent)
        }
        return out
    }
}
