import SwiftUI

/// The three views behind an agent thing sheet (prd §367, 2026-08-12): a
/// conversation's head, its turns, and a vault grant.
///
/// `AgentSheet` decides every word and every number; these files only set them,
/// so the reasoning lives in one Foundation-only place a harness can compile.
///
/// **None of them stores a `Thing`.** Each takes the value type out of
/// `AgentSheet`, which is `SocialReceptionCard`'s shape and not an accident:
/// build 188's corollary 5 (a leaf view's body is re-evaluated on the model's
/// OWN observation, independent of the parent that built it) has nothing to
/// guard when there is no model here to read.
///
/// FLAT BY LAW like their siblings — plain stacks, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).

// MARK: - Conversation head

// MARK: - Turns

/// The conversation itself — the thing that was in the record all along.
///
/// Two voices, drawn as two voices: yours trailing, the agent's leading, each
/// under its speaker's label and on no plate — air separates the turns (prd
/// §782). `ChatBubbles` gives both the same alignment, so the only thing
/// distinguishing a question from an answer there is the label the importer
/// typed into the string.
struct AgentTurnsView: View {
    let turns: [AgentSheet.Turn]
    /// How many turns the importer's clamp cut, when that is knowable.
    var cut: Int?
    /// The export carries asks and no replies (Gemini). Said out loud, because
    /// a conversation with one side missing otherwise reads as a failed load.
    var oneSided: Bool = false
    /// The source, for the one-sided sentence — the only place these views
    /// name a seat.
    var source: String = ""

    @State private var expanded = false

    /// Six, matching what `ChatBubbles` showed before it. A sheet opens on a
    /// document, not on a scroll to its end.
    private static let collapsed = 6

    /// How wide one voice may get — under the widest phone column, so this
    /// binds only where the record is wider than a phone (the Mac/iPad detail
    /// pane, a Mac window's sheet). See `bubble`.
    private static let bubbleMaxWidth: CGFloat = 460

    var body: some View {
        let shown = expanded ? turns : Array(turns.prefix(Self.collapsed))
        let hidden = turns.count - shown.count
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, turn in
                bubble(turn)
            }
            if hidden > 0 {
                Button {
                    withAnimation(DS.Motion.standard) { expanded = true }
                } label: {
                    Text("Show all \(turns.count) turns")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.tint)
                }
                .buttonStyle(RowPress())
                .dsHover()
                .frame(maxWidth: .infinity, alignment: .center)
            }
            // The two honesty clauses. Both are derived, never declared: `cut`
            // is the importer's own pre-clamp count against what survived, and
            // `oneSided` is "no turn in this transcript is the assistant's".
            if let cut, expanded || hidden == 0 {
                clause(String(localized:
                    "Stored to here. \(cut) more turns were in the export."))
            }
            if oneSided {
                clause(String(localized:
                    "Your \(source) export carries the prompt. It has no field for the reply, so there is none to show."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func bubble(_ turn: AgentSheet.Turn) -> some View {
        let mine = turn.voice == .you
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            // The speaker is a LABEL, not a prefix inside the sentence — which
            // is the whole difference between a transcript and a wall of text,
            // and it reads correctly at any Dynamic Type size where an
            // alignment cue alone would not.
            Text(verbatim: turn.name)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            // THE AGENT'S SIDE IS MARKDOWN, YOURS IS NOT (2026-08-20).
            //
            // Not a preference — the same per-source FACT §399 established for
            // note bodies, one room over. ChatGPT, Claude and Claude Code emit
            // markdown by construction: fenced code, headings, numbered steps.
            // Drawn as prose it rendered its own punctuation — a fence as three
            // backticks, `**this**` with the asterisks in — and, far worse, an
            // answer's code block was split by the very markers it contains, so
            // a Python `# TODO` became a heading.
            //
            // The person's side stays plain deliberately, which is also how
            // these products render it: what somebody typed is what they typed,
            // and parsing it would eat a literal asterisk they meant. A pasted
            // fence in a question therefore stays unstyled — under-styling is
            // the safe direction, and it stays readable either way.
            //
            // `foldable: false` because this view already folds, by TURN
            // ("Show all N turns"). Two folds over one transcript would let a
            // reader open the conversation and still be looking at a cut answer.
            NoteProse(text: turn.text,
                      foldable: false,
                      markdown: turn.voice == .assistant,
                      tier: .body17)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                // A turn is capped, or the two voices stop being two
                // (Mac parity, 2026-08-12). Alignment is the whole cue here —
                // "yours trailing, the agent's leading" —
                // and a turn long enough to fill the column is aligned to
                // both edges at once, so the transcript collapses back into
                // the wall of same-width blocks this view was written to
                // replace. It never showed on a phone, where 358pt of column
                // caps every bubble for us; the detail pane is 400–560pt and
                // the record sheet wider still. `maxWidth` only ever cuts, so
                // a short turn keeps hugging its own text and no iPhone
                // layout moves.
                .frame(maxWidth: Self.bubbleMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        // Read apart, a name and a paragraph are two unrelated announcements.
        .accessibilityElement(children: .combine)
    }

    private func clause(_ text: String) -> some View {
        Text(verbatim: text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The conversation receipt

/// What the record knows about this chat, stated once, in words.
///
/// Replaces the spec table on a conversation sheet, whose whole contribution
/// was `From — from your session` behind an 80pt label column.
struct AgentReceiptCard: View {
    let reading: AgentSheet.Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !readings.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s6) {
                    ForEach(readings, id: \.noun) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: r.text)
                                .dsText(.heading24)
                                .foregroundStyle(DS.textPrimary)
                                .monospacedDigit()
                            Text(verbatim: r.noun)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let provenance = reading.provenance {
                Text(verbatim: provenance)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // On no plate (prd §782): air separates it from the blocks around it.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An absent number has no cell — `SocialReceptionCard`'s rule, and the
    /// only reason the numbers that ARE here can be trusted.
    private var readings: [(text: String, noun: String)] {
        var out: [(String, String)] = []
        if let turns = reading.counted {
            out.append(("\(turns)", String(localized: "turns")))
        }
        if let cut = reading.cut {
            out.append(("\(cut)", String(localized: "not stored")))
        }
        return out
    }
}
