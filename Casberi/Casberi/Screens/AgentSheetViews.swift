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

/// The hero of a chat sheet: what it was called, where it ran, and how big it
/// is — which is the fact a sheet that showed one line of a 61-turn session
/// could never state.
struct AgentConversationHead: View {
    let reading: AgentSheet.Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: reading.hero)
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let project = reading.project {
                // The project as a rung of its own rather than a prefix inside
                // the headline — `WorkStageView`'s line, and drawn only because
                // a stored tag carries it.
                Text("in \(project)")
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1 + 2)
            }
            if let meta {
                Text(verbatim: meta)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "12 turns · 4 Aug at 09:41". Absent halves are simply not printed — a
    /// chat with no counted turns says when it happened and nothing about its
    /// size, rather than a zero standing in for an unknown.
    private var meta: String? {
        var parts: [String] = []
        if let turns = reading.counted {
            parts.append(turns == 1
                ? String(localized: "1 turn")
                : String(localized: "\(turns) turns"))
        }
        if let opened = reading.opened {
            parts.append(opened.formatted(
                .dateTime.day().month(.abbreviated).hour().minute()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Turns

/// The conversation itself — the thing that was in the record all along.
///
/// Two voices, drawn as two voices: yours tinted and trailing, the agent's
/// faint and leading. Today's `ChatBubbles` gives both the same fill and the
/// same alignment, so the only thing distinguishing a question from an answer
/// is the label the importer typed into the string.
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

    var body: some View {
        let shown = expanded ? turns : Array(turns.prefix(Self.collapsed))
        let hidden = turns.count - shown.count
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, turn in
                bubble(turn)
            }
            if hidden > 0 {
                Button {
                    withAnimation(DS.Motion.standard) { expanded = true }
                } label: {
                    Text("Show all \(turns.count) turns")
                        .dsText(.subhead13)
                        .foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
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
            Text(ProseLinks.rendered(turn.text))
                .dsText(.callout15)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s2 + 1)
                .background(mine ? DS.tintDim : DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                                .dsText(.heading22)
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
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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

// MARK: - Grant

/// A vault grant, drawn as the permission it is (prd §367).
///
/// It was a `.link` whose link is the same dashboard URL on every grant in the
/// corpus, so the sheet drew a preview card that told you nothing and a `Site`
/// row that told you less — while the expiry sat on the row, unreachable.
struct AgentGrantView: View {
    let grant: AgentSheet.Grant

    /// §299: a drawing SIZED FROM DATA gets an entrance, and the entrance
    /// honours Reduce Motion. The runway is exactly that — its length is the
    /// share of the grant's life already spent.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let status = grant.status {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2 - 3) {
                    Circle()
                        .fill(grant.urgent ? DS.attention : DS.textSecondary)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(verbatim: status)
                        .dsText(.callout15)
                        .fontWeight(.semibold)
                        .foregroundStyle(grant.urgent ? DS.attention : DS.textSecondary)
                }
                .padding(.bottom, DS.Space.s2)
            }
            // The path IS the grant. Monospaced because it is a pattern, not a
            // sentence — the `WorkStage.Face.code` reasoning: setting it in the
            // prose face makes it read as something somebody wrote.
            Text(verbatim: grant.path)
                .dsText(.heading22)
                .monospaced()
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let vault = grant.vault {
                Text("in \(vault)")
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1 + 2)
            }
            if !grant.permissions.isEmpty {
                permissionStrip.padding(.top, DS.Space.s4)
            }
            // The runway only when BOTH ends are known. A bar with one end
            // guessed draws something we do not know.
            if let fraction = grant.fraction {
                runway(fraction).padding(.top, DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the key may do — and ONLY what it may do. There is deliberately no
    /// struck-through "write" beside it: the API reports the permissions it
    /// granted and never the closed set they were drawn from, so a greyed
    /// `delete` would be this app inventing the shape of somebody's security
    /// model (§83, on the screen where believing it is most expensive).
    private var permissionStrip: some View {
        FlowLayout(spacing: DS.Space.s2) {
            ForEach(grant.permissions, id: \.self) { permission in
                Text(verbatim: permission)
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s1 + 2)
                    .background(DS.fillFaint, in: Capsule())
            }
        }
    }

    private func runway(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2 - 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule()
                        .fill(grant.urgent ? DS.attention : DS.tint)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
            // The shared wipe rather than `ShareBar`: this bar's HUE is
            // information (amber inside the fortnight it can still be acted
            // on), and `ShareBar` is deliberately one colour.
            .chartWipe(reduceMotion: reduceMotion)
            HStack {
                if let granted = grant.granted {
                    Text("Granted \(granted.formatted(.dateTime.day().month(.abbreviated)))")
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: DS.Space.s3)
                if let expires = grant.expires {
                    Text("Expires \(expires.formatted(.dateTime.day().month(.abbreviated)))")
                        .dsText(.label12)
                        .foregroundStyle(grant.urgent ? DS.attention : DS.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
