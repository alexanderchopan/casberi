import Foundation

/// Reading a stored chat transcript back as TURNS (2026-08-20).
///
/// The three chat importers flatten a conversation into one speaker-prefixed
/// string (`ChatTranscript.make` — "You: …\nChatGPT: …", oldest first, clamped
/// at 8,000 characters) and park it on `enrichedText`, which is retrieval-only
/// by the 2026-07-15 ruling. That was the right shape for the job it was built
/// for: the words become findable, and nothing renders them.
///
/// It is the wrong shape for the two things that room actually wants. A
/// conversation is a SEQUENCE of exchanges, and both of these need it back:
/// drawing an imported chat as the chat it was rather than as an excerpt, and
/// picking a conversation up where it stopped by handing its prior turns to the
/// keyed agent as history. Neither can work from one flat string.
///
/// **The vocabulary is closed, and that is what makes the parse safe.** A line
/// begins a new turn ONLY when it opens with a speaker this app itself writes
/// — nothing is inferred from the shape of a line. That matters because a
/// message's own text is full of lines that look like speaker prefixes:
/// "Note: the following", "Error: unexpected token", "TODO: fix this",
/// "Step 3: run it". A loose `^\w+:` rule would shatter a single answer into a
/// dozen turns attributed to speakers who do not exist — and it would do it
/// silently, rendering a plausible conversation nobody had.
///
/// **A transcript we did not write parses to NOTHING, deliberately.** The clamp
/// keeps the oldest end, so a transcript this app wrote always opens with a
/// speaker; one that doesn't is somebody else's text on `enrichedText` (a
/// vault note's body, an article's lede, a keyed digest). Returning an empty
/// list lets every caller fall back to the plain rendering it already had,
/// which is the behaviour that was correct before this file existed.
enum ChatTurns {

    /// Every speaker the importers write, in one place. `ChatGPTImport`,
    /// `ClaudeImport` and `GeminiImport` each map their export's own role
    /// vocabulary down to these before `ChatTranscript.make` joins them, and
    /// `chat-turns-selftest.sh` asserts each of those mappings still lands
    /// inside this set — the parse and the writers cannot drift apart without
    /// the build going red.
    ///
    /// "You" is the person on every one of them, which is what makes the
    /// speaker-to-side question answerable at all.
    static let speakers: Set<String> = ["You", "ChatGPT", "Claude"]

    /// The person's own side. One name rather than "not an assistant", because
    /// an unknown speaker must never be silently promoted to the person: an
    /// answer misattributed to you, in a room of your own conversations, is
    /// the kind of wrong that reads as true.
    static let mine = "You"

    struct Turn: Equatable, Sendable {
        let speaker: String
        let text: String
        var isMine: Bool { speaker == ChatTurns.mine }
    }

    /// The transcript as turns, oldest first. Empty when this is not a
    /// transcript this app wrote (see the type doc).
    ///
    /// A continuation line — anything that does not open a new turn — is
    /// appended to the turn in progress WITH its newline, because a code block
    /// or a list inside one answer is part of that answer and re-joining it
    /// with spaces would destroy the only structure it has.
    static func parse(_ transcript: String?) -> [Turn] {
        guard let transcript, !transcript.isEmpty else { return [] }
        var turns: [Turn] = []
        var speaker: String?
        var body: [String] = []

        func close() {
            guard let speaker else { return }
            let text = body.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // A speaker line with nothing under it is dropped rather than
            // landed empty: the importers never write one, so an empty body
            // means the clamp cut immediately after a prefix.
            if !text.isEmpty { turns.append(Turn(speaker: speaker, text: text)) }
            body = []
        }

        for line in transcript.components(separatedBy: "\n") {
            if let opened = speakerPrefix(line) {
                close()
                speaker = opened.speaker
                body = opened.rest.isEmpty ? [] : [opened.rest]
            } else if speaker != nil {
                body.append(line)
            }
            // A line before ANY speaker is dropped on purpose — it is the
            // signature of a body this app did not write, and `parse` answers
            // that case with an empty list below.
        }
        close()
        // The whole-or-nothing rule: if the FIRST line never opened a turn,
        // this is not our transcript and the caller should render it the way
        // it always did.
        guard let first = transcript.components(separatedBy: "\n").first,
              speakerPrefix(first) != nil else { return [] }
        return turns
    }

    /// The speaker a line opens, and whatever followed the colon on that same
    /// line. nil for every other line.
    ///
    /// The separator is `": "` — colon AND space — which is exactly what
    /// `ChatTranscript.make` writes. Matching a bare colon would make
    /// "Claude:3" a turn, and matching case-insensitively would make a
    /// sentence beginning "You: " inside an answer one too.
    private static func speakerPrefix(_ line: String) -> (speaker: String, rest: String)? {
        for speaker in speakers {
            let marker = speaker + ": "
            if line.hasPrefix(marker) {
                return (speaker, String(line.dropFirst(marker.count)))
            }
            // A turn whose text is empty is written as "You:" with nothing
            // after it by no importer here — but a clamp landing exactly on
            // the colon produces it, and reading that as prose would attribute
            // a speaker's name to the previous turn.
            if line == speaker + ":" { return (speaker, "") }
        }
        return nil
    }

    /// Whether the stored transcript is missing turns the conversation really
    /// had. `Thing.messageCount` is counted BEFORE the clamp and is the only
    /// place the true number survives (`ChatTranscript`'s own note), so this is
    /// the one comparison that can detect it.
    ///
    /// Conservative in the direction that matters: an unknown or zero count
    /// answers false, because claiming a conversation is cut when we cannot
    /// tell is a worse error than staying quiet — it puts a caveat on a
    /// complete chat.
    static func isPartial(parsed: [Turn], messageCount: Int?) -> Bool {
        guard let messageCount, messageCount > 0 else { return false }
        return parsed.count < messageCount
    }

    /// The conversation as question/answer PAIRS, for handing to the keyed
    /// agent as prior history.
    ///
    /// Pairing is the point and it is not a formality: `AgentTurn` is a
    /// (question, answer) pair on every wire this app speaks, so a flat list of
    /// turns cannot be sent. Each of the person's turns takes the NEXT
    /// assistant turn as its answer.
    ///
    /// **Three shapes are dropped rather than guessed at.** An assistant turn
    /// with no question before it (the clamp cut the opening ask) has no pair
    /// and is not invented one. Consecutive turns from the same speaker — two
    /// asks in a row, which every one of these products allows — pair the
    /// LATEST ask with the answer, since that is the one the answer replies
    /// to. And a trailing question with no answer yet is not a pair at all; it
    /// is returned separately as `pending`, because that is the thing somebody
    /// continuing this conversation most likely wants asked.
    static func exchanges(_ turns: [Turn]) -> (history: [(question: String, answer: String)],
                                               pending: String?) {
        var history: [(question: String, answer: String)] = []
        var question: String?
        for turn in turns {
            if turn.isMine {
                question = turn.text
            } else if let asked = question {
                history.append((question: asked, answer: turn.text))
                question = nil
            }
        }
        return (history, question)
    }

    /// What to tell a model that is picking this conversation up.
    ///
    /// **It says the transcript is partial when it is, and that is the whole
    /// reason this is a function rather than a literal.** Handing a model the
    /// last 8,000 characters of a long conversation without saying so invites
    /// it to answer as though it had read the beginning — and the beginning is
    /// where a chat's subject is set. The clamp keeps the OLDEST end
    /// (`ChatTranscript`'s ruling: a chat is a document that opens with the ask
    /// it exists to answer), so what is missing is the RECENT end, which is
    /// exactly what a continuation would otherwise assume it has.
    static func continuationInstructions(source: String, partial: Bool) -> String {
        var text = """
        You are picking up a conversation this person had with \(source) \
        somewhere else, and they have brought it here to carry on. The earlier \
        turns are given to you as they happened. Answer their next message in \
        that conversation's own terms — do not summarize what was already said, \
        do not reintroduce yourself, and do not pretend to remember anything \
        beyond the turns you were given.
        """
        if partial {
            text += """
             Some of the conversation is missing: only the earlier part was \
            kept, so the most recent turns are not here. If the missing part \
            matters to the answer, say so plainly rather than guessing what it \
            contained.
            """
        }
        return text
    }
}
