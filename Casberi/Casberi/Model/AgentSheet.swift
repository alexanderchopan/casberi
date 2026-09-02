import Foundation

/// WHAT AN AGENT THING SHEET IS — the shape decision, the turn parser and the
/// two readings behind them (prd §367, 2026-08-12).
///
/// The wallet sheets became receipts (§302), Work became a receipt this
/// morning, social became a post (§363). The Agents category is ten catalog
/// seats; four of them land nothing at all (they are keys, not sources) and one
/// — Cursor — was already covered by `WorkStage` hours ago. The five that were
/// left carry more text than anything else in the corpus and drew the least of
/// it. Measured from the shipped code, not guessed:
///
/// - **An imported chat's entire conversation is stored and drawn by nothing.**
///   `ChatGPTImport` writes the opening ask to `content` and the whole
///   speaker-prefixed transcript to `enrichedText` (≤8,000 characters;
///   `ClaudeCodeImport` ≤16,000), and `ThingContent` renders
///   `ChatBubbles(text: thing.content)`. So the sheet you opened to read a
///   conversation showed one line of it — **the same line already clamped into
///   the title above it.** This is the Obsidian defect verbatim, four seats
///   over: "the vault bridge read a person's notes, indexed them for search,
///   and showed nobody the note."
/// - **`ChatBubbles` draws no bubbles.** It splits on newlines and puts every
///   line in the same faint slab at the same alignment, while the speaker is
///   written INSIDE the string (`"You: …"`). Handed the real transcript it
///   would render a conversation's one structural fact — who is talking — as
///   punctuation.
/// - **A 61-turn Claude Code session read exactly like a 3-turn one.**
///   `messageCount` is stamped by all four importers and drawn on one screen
///   in the whole app (a social thread's rest).
/// - **1Claw's expiry was stored and unreachable.** Grants land `kind: .link`
///   with `dueAt = expires_at`, and the spec table's `Due` row is gated on
///   `kind == .reminder`. A grant expiring in six days looked identical to one
///   that never expires, on the surface whose entire job is "what can this
///   agent reach".
///
/// ## Two shapes, and deliberately no third
///
/// §363's rule: a shape exists only where the sheet would otherwise draw the
/// wrong noun. A Claude Code session is NOT a third shape — it is a
/// conversation whose project happens to be stamped, and giving it an anatomy
/// of its own would be two views drawing one fact, which is how a screen starts
/// contradicting itself.
///
/// ## Why this file is Foundation-only
///
/// So `scripts/agent-sheet-selftest.sh` can compile it WHOLE and unmodified —
/// the `SocialSheet` / `WorkStage` / `ASCShape` precedent. Every failure here
/// is a silent wrong answer that renders perfectly and no build, screen sweep
/// or probe can see: a turn attributed to the wrong speaker reads as somebody
/// saying something they did not say, and an 84-turn chat presenting its first
/// 8,000 characters with no clause reads as the whole conversation. Everything
/// touching `Thing`, SwiftData or UserDefaults lives in `AgentSheetSource`.
enum AgentSheet {

    // MARK: - Shape

    enum Shape: String, Equatable {
        /// A chat with an agent: the ask, the turns, and what the record says
        /// about how much of it we hold. ChatGPT, Claude, Gemini, Claude Code.
        case conversation
        /// A permission: what can be reached, by which verbs, until when.
        /// 1Claw's vault grants — a thing that was rendering as a bookmark.
        case grant
    }

    /// The facts the shape decision reads. A value type on purpose: the
    /// decision is the thing worth testing, and it must be testable without a
    /// `Thing`, a store, or a simulator.
    struct Facts: Equatable {
        /// `ThingKind.rawValue`, so this file needs no SwiftData.
        var kind: String
        /// Does `SocialSheet` already claim this row? A Snapchat saved chat and
        /// an imported DM thread are `.chat` too, and they are transcripts of
        /// PEOPLE — social owns them, and asked first.
        var socialShaped: Bool
        /// Is this a 1Claw policy row (`sourceRef` prefix)? The ref is the
        /// record; nothing here reads a display string to decide a noun.
        var grantRef: Bool
        /// Turns recovered from the stored transcript.
        var turns: Int
        /// `Thing.messageCount` — what the importer counted BEFORE its clamp.
        var counted: Int?
    }

    /// The anatomy, or nil for an agent thing that needs none.
    ///
    /// Order is load-bearing:
    ///
    /// 1. **A grant is a permission before it is anything else** — it is a
    ///    `.link` whose link is the same dashboard URL on every row in the
    ///    corpus, so the kind cannot be allowed to decide.
    /// 2. **Social wins any tie.** A `.chat` that `SocialSheet` shapes is a
    ///    conversation between people and already has an anatomy; claiming it
    ///    here would be two shapes for one row.
    /// 3. **A conversation is a `.chat` that carries a conversation** — turns
    ///    we could read, or a count the importer stamped. This is the data test
    ///    §363 ruled for, and it is what keeps Slack messages and Stocktwits
    ///    posts (both `.chat`, neither a transcript) out: they carry neither.
    static func shape(_ f: Facts) -> Shape? {
        if f.grantRef { return .grant }
        guard !f.socialShaped, f.kind == "chat" else { return nil }
        return (f.turns > 0 || f.counted != nil) ? .conversation : nil
    }

    // MARK: - Turns

    /// One turn of a stored transcript.
    ///
    /// There is deliberately no `.tool` voice. Claude Code's transcript folds
    /// tool traffic into the assistant's turns (`role` is `user` or nothing
    /// else that reaches us), so a tool case would be a distinction the record
    /// does not make — invented structure, which is the one thing a transcript
    /// view must never add.
    struct Turn: Equatable {
        enum Voice: String, Equatable { case you, assistant }
        var voice: Voice
        /// The label exactly as the importer wrote it ("ChatGPT", "You"), so
        /// the view never has to name a speaker the record did not.
        var name: String
        var text: String
    }

    /// The reader's label in every stored transcript.
    ///
    /// **A plain literal, and it must stay one.** All four importers write
    /// `"You"` unlocalized (`ChatGPTImport.speakerName`,
    /// `ClaudeImport.speakerName`, `ClaudeCodeSession.transcript`,
    /// `GeminiImport.turns`), so the transcript on a row is stable English
    /// whatever language the device was in when it landed. A
    /// `String(localized:)` here would stop every transcript in the corpus
    /// from parsing the moment somebody changed their language — prd §340's
    /// ruling in a second place, and the reason `WorkStage` derives its
    /// outcome from tags rather than clauses.
    static let readerLabel = "You"

    /// The assistant's label in a given source's transcripts — the mirror of
    /// the importers' own `speakerName` functions, which write these strings
    /// into `enrichedText` at import, and unlocalized for the same reason
    /// `readerLabel` is.
    ///
    /// **nil is a real answer and it is the safe one.** With no label, only
    /// "You" would split, and a two-party conversation would collapse into one
    /// enormous turn attributed to the reader — a stranger's words under your
    /// own name, the §363 failure in its most expensive form. `turns` returns
    /// nothing rather than that, and the sheet falls back to exactly today's
    /// rendering.
    static func assistant(for source: String) -> String? {
        switch source {
        case "ChatGPT":     return "ChatGPT"
        case "Claude":      return "Claude"
        // `ClaudeCodeSession.transcript` labels the assistant "Claude", not
        // "Claude Code" — the seat's name and its speaker's name differ, and
        // assuming they match is how this whole parse returns nothing.
        case "Claude Code": return "Claude"
        case "Gemini":      return "Gemini"
        default:            return nil
        }
    }

    /// The stored transcript, as turns.
    ///
    /// The format is the importers' own: turns joined with newlines, each
    /// written `"<Speaker>: <text>"`. A message's own text may contain
    /// newlines, so **a new turn begins only at a line that starts with a known
    /// speaker's label** — splitting on every newline is what today's
    /// `ChatBubbles` does, and it is why a paragraph break inside an answer
    /// reads as a new message.
    ///
    /// Returns [] when nothing matched: a transcript we cannot read is not a
    /// transcript we may guess at.
    static func turns(_ transcript: String?, assistant: String?) -> [Turn] {
        guard let transcript, !transcript.isEmpty, let assistant else { return [] }
        var out: [Turn] = []
        for line in transcript.components(separatedBy: "\n") {
            if let rest = strip(prefix: readerLabel, from: line) {
                out.append(Turn(voice: .you, name: readerLabel, text: rest))
            } else if let rest = strip(prefix: assistant, from: line) {
                out.append(Turn(voice: .assistant, name: assistant, text: rest))
            } else if !out.isEmpty {
                out[out.count - 1].text += "\n" + line
            }
            // A line before any speaker is prose we cannot attribute. Dropped,
            // never folded into the first turn.
        }
        return out.compactMap { turn in
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Turn(voice: turn.voice, name: turn.name, text: text)
        }
    }

    /// `"You: hello"` → `"hello"`, and nil for every line that is not this
    /// speaker's. The space after the colon is required: `ClaudeCodeSession`
    /// and `ChatTranscript` both write one, and without it a line reading
    /// "You:me" would open a turn.
    private static func strip(prefix speaker: String, from line: String) -> String? {
        let head = speaker + ": "
        guard line.hasPrefix(head) else { return nil }
        return String(line.dropFirst(head.count))
    }

    // MARK: - The conversation reading

    /// Everything a conversation sheet says. `nil` fields are "we have nothing
    /// true to say", never a placeholder.
    struct Conversation: Equatable {
        /// The headline — the conversation's own name, or the ask itself where
        /// the name is only a clamp of it.
        var hero: String
        /// The project this ran in, and ONLY from a stored field (Claude Code's
        /// own tag). Never sliced out of a title.
        var project: String?
        /// The turns to DRAW — the parse, minus a leading turn that is already
        /// the hero.
        var turns: [Turn]
        /// What the importer counted before its clamp.
        var counted: Int?
        /// How many turns are missing from the stored transcript, or nil when
        /// nothing was cut or we cannot tell.
        var cut: Int?
        /// The export carries the asks and no replies. True by construction,
        /// never by source name.
        var oneSided: Bool
        var opened: Date?
        /// One sentence saying how this got here.
        var provenance: String?
    }

    struct ConversationInput {
        var source: String
        var title: String
        /// `Thing.content` — the opening ask on every one of the four
        /// importers.
        var ask: String?
        var transcript: String?
        /// The project, off a stored tag.
        var project: String?
        var counted: Int?
        var opened: Date?
        /// Does a re-import GROW this row rather than replace it? True for
        /// Claude Code, whose sessions are appended to; false for a finished
        /// export.
        var growing: Bool = false
    }

    static func conversation(_ i: ConversationInput) -> Conversation {
        let parsed = turns(i.transcript, assistant: assistant(for: i.source))
        let ask = i.ask?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hero = hero(title: i.title, ask: ask, project: i.project)
        // The first turn is DROPPED only when it IS the hero — proven, never
        // sliced blind (`SocialSheet.threadRest`'s rule). Without the proof, a
        // chat whose title is its own ask prints the ask twice: once at display
        // size and once as the opening bubble.
        var drawn = parsed
        if let first = drawn.first, first.voice == .you,
           first.text.trimmingCharacters(in: .whitespacesAndNewlines) == hero {
            drawn.removeFirst()
        }
        return Conversation(
            hero: hero,
            project: i.project,
            turns: drawn,
            counted: i.counted,
            // Against the FULL parse, never the drawn list — dropping a
            // duplicate for display must not make the sheet claim a turn was
            // lost to the clamp.
            cut: cut(counted: i.counted, shown: parsed.count),
            oneSided: !parsed.isEmpty && !parsed.contains { $0.voice == .assistant },
            opened: i.opened,
            provenance: provenance(source: i.source, growing: i.growing))
    }

    // MARK: - Carrying a conversation on (2026-08-20)

    /// The conversation as question/answer PAIRS, for handing to the keyed
    /// agent as prior history so somebody can pick an imported chat back up.
    ///
    /// Pairing is the point rather than a formality: `AgentTurn` is a
    /// (question, answer) pair on every wire this app speaks, so a flat list of
    /// turns cannot be sent at all.
    ///
    /// **Three shapes are dropped rather than guessed at, and each one would
    /// put words in somebody's mouth.** An assistant turn with no question
    /// before it — the importer's clamp keeps the oldest end, so this is a
    /// transcript whose opening ask was cut — is not given an invented one.
    /// Consecutive turns from the same voice (two asks in a row, which all four
    /// of these products allow) pair the LATEST ask with the answer, since that
    /// is the one the answer replies to. And a trailing ask with no answer yet
    /// is not half a pair; it is returned as `pending`, because it is the thing
    /// somebody continuing this conversation most likely wants asked.
    static func exchanges(_ turns: [Turn]) -> (history: [(question: String, answer: String)],
                                               pending: String?) {
        var history: [(question: String, answer: String)] = []
        var question: String?
        for turn in turns {
            if turn.voice == .you {
                question = turn.text
            } else if let asked = question {
                history.append((question: asked, answer: turn.text))
                question = nil
            }
        }
        return (history, question)
    }

    /// What to tell a model picking this conversation up.
    ///
    /// **It says the transcript is partial when it is, and that is why this is
    /// a function rather than a literal.** Handing a model what survived an
    /// 8,000-character clamp without saying so invites it to answer as though
    /// it had read the rest — and `cut` is the only place that fact exists
    /// (`messageCount` counts turns BEFORE the clamp; the stored text carries
    /// what survived it). The clamp keeps the OLDEST end by
    /// `ChatTranscript`'s own ruling, so what is missing is the RECENT end,
    /// which is exactly the part a continuation would otherwise assume it has.
    static func continuationInstructions(source: String, cut: Int?) -> String {
        var text = """
        You are picking up a conversation this person had with \(source) \
        somewhere else, and they have brought it here to carry on. The earlier \
        turns are given to you as they happened, and they are all you know of \
        it. Answer their next message as the next turn of that conversation, \
        in its own terms; anything beyond those turns is unknown to you, and \
        saying so beats guessing at it.
        """
        if let cut, cut > 0 {
            text += """
             \(cut) later turns of that conversation are NOT here — only the \
            earlier part was kept. If what is missing bears on the answer, say \
            so plainly rather than guessing what it contained.
            """
        }
        return text
    }

    /// How many turns the stored transcript is missing.
    ///
    /// Both numbers already exist on the row: `messageCount` counts turns
    /// BEFORE the importer's clamp, and the stored text carries what survived
    /// it. **So "stored to here" needs no new `Thing` property** — and
    /// therefore no CloudKit Production deploy.
    ///
    /// nil when nothing was cut AND when the transcript did not parse at all: a
    /// count with no readable transcript tells us nothing about what is
    /// missing, and saying "84 turns not shown" over a row that simply has no
    /// stored body would be a claim about a clamp that never ran.
    static func cut(counted: Int?, shown: Int) -> Int? {
        guard let counted, shown > 0, counted > shown else { return nil }
        return counted - shown
    }

    /// The headline.
    ///
    /// The conversation's own name leads, because that is what the export named
    /// it and what the row shows. The ONE exception is proven rather than
    /// assumed: where the title is a CLAMP of the ask — Gemini's rows are
    /// `titleLine(ask)`, cut at 80 characters — the ask replaces it, because
    /// the two are the same string and one of them is whole.
    static func hero(title: String, ask: String?, project: String?) -> String {
        let named = stripProject(title, project: project)
        guard let ask, !ask.isEmpty else { return named }
        return isClamp(named, of: ask) ? ask : named
    }

    /// `"casberi · Fix the room-head gaps"` → `"Fix the room-head gaps"`, and
    /// only when the stored project really is the prefix.
    ///
    /// `ClaudeCodeSession.title` joins them with `" · "`, so the strip is of a
    /// separator we wrote ourselves — but it still fails safe: a mismatch
    /// leaves the title whole rather than cutting at the first separator it
    /// finds, which on a headline containing a `·` would eat the subject.
    static func stripProject(_ title: String, project: String?) -> String {
        guard let project, !project.isEmpty else { return title }
        let prefix = project + " · "
        guard title.hasPrefix(prefix) else { return title }
        let rest = String(title.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? title : rest
    }

    /// Is `short` the clamped form of `full`?
    ///
    /// `IngestSupport.titleLine` cuts at 80 and appends an ellipsis, so the
    /// test is a prefix match against the title minus its ellipsis. The length
    /// floor matters: a two-word title that happens to open the ask is a
    /// coincidence, and treating it as a clamp would silently replace a real
    /// conversation name with its first sentence.
    static func isClamp(_ short: String, of full: String) -> Bool {
        let core = short
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard core.count >= 24, full.count > core.count else { return false }
        return full.hasPrefix(core)
    }

    /// One sentence saying how this got here.
    ///
    /// Deliberately dateless. Unlike the four bulk-import rooms, none of the
    /// chat importers lands an `ImportReceipt`, so there is no stored date for
    /// when the export was read — and the sheet states when the CONVERSATION
    /// happened (`opened`) rather than inventing a second, unknown one.
    static func provenance(source: String, growing: Bool) -> String {
        growing
            ? String(localized: "From your \(source) history. Sessions grow — re-importing updates this one in place.")
            : String(localized: "From your \(source) export.")
    }

    // MARK: - The grant reading

    /// One vault grant: what can be reached, by which verbs, until when.
    struct Grant: Equatable {
        /// The secret path pattern — the grant's whole payload.
        var path: String
        var vault: String?
        /// The verbs this key was given, in the words the API used.
        var permissions: [String]
        var granted: Date?
        var expires: Date?
        /// "Expires in 6 days" / "Expired" — nil when there is no clock, which
        /// is most grants. A bar drawn against a guessed end date is the
        /// invented fact this codebase bans.
        var status: String?
        /// Is the clock worth colouring? A grant with weeks left is a fact, not
        /// an alarm.
        var urgent: Bool
        /// How much of the grant's life has elapsed, 0…1 — nil unless BOTH
        /// ends are known, since a runway with one end guessed is a drawing of
        /// something we do not know.
        var fraction: Double?
    }

    struct GrantInput {
        /// `Thing.title` — the fallback path only, for a row landed before the
        /// bridge stamped its parts. Never parsed apart.
        var title: String
        /// `Thing.summary`, stamped by `OneClawBridge.policyThing`.
        var path: String?
        /// `Thing.authorHandle`.
        var vault: String?
        var permissions: [String]
        var granted: Date?
        var expires: Date?
        var now: Date
    }

    static func grant(_ i: GrantInput) -> Grant {
        let clock = expiry(i.expires, now: i.now)
        let path = (i.path?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        }
        return Grant(
            // The title is the fallback, WHOLE — a row that predates the
            // stamped fields shows the string it has always shown rather than
            // a string this file guessed at by splitting on a separator.
            path: path ?? i.title,
            vault: i.vault,
            permissions: i.permissions,
            granted: i.granted,
            expires: i.expires,
            status: clock?.text,
            urgent: clock?.urgent ?? false,
            fraction: fraction(granted: i.granted, expires: i.expires, now: i.now))
    }

    /// The clock, in words. Day-boundary arithmetic rather than raw seconds: a
    /// grant expiring at 09:00 tomorrow is "tomorrow" all of today, and
    /// reporting it as "in 0 days" at 10:00 is the kind of true-but-useless
    /// number a receipt exists to replace.
    static func expiry(_ expires: Date?, now: Date) -> (text: String, urgent: Bool)? {
        guard let expires else { return nil }
        if expires <= now { return (String(localized: "Expired"), true) }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: expires)).day ?? 0
        switch days {
        case ...0: return (String(localized: "Expires today"), true)
        case 1:    return (String(localized: "Expires tomorrow"), true)
        default:   return (String(localized: "Expires in \(days) days"), days <= urgentDays)
        }
    }

    /// Two weeks. The same window `AppStoreConnectBridge` treats a TestFlight
    /// build's death as news in — a deadline you can still act on.
    static let urgentDays = 14

    static func fraction(granted: Date?, expires: Date?, now: Date) -> Double? {
        guard let granted, let expires else { return nil }
        let total = expires.timeIntervalSince(granted)
        guard total > 0 else { return nil }
        let done = now.timeIntervalSince(granted) / total
        return min(max(done, 0), 1)
    }
}
