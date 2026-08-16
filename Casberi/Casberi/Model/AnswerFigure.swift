import Foundation

/// The deterministic figure above a free-text answer's prose (2026-08-15).
///
/// WHY IT EXISTS. Every OTHER answer shape in this app leads with a picture the
/// app computed itself — a source recap opens on `dailyBars`, a room opens on
/// its head, the brief opens on whichever module the day earned. The free-text
/// tail, which is the shape a typed question actually lands on most of the
/// time, opened on a paragraph and closed on four grounding rows: the one
/// answer with no arithmetic of its own anywhere on it. So the fact a person
/// could read at a glance — that eleven of the fourteen matches came from one
/// room, that they all landed on Tuesday — was present in the retrieved set,
/// free to compute, and shown nowhere.
///
/// THE MODEL NEVER TOUCHES THE DSL, and the ordering is what keeps that true
/// rather than a promise. The figure is chosen and built from `capturedAt` and
/// `source` alone, BEFORE any model call is made, out of the same rows the
/// answer is grounded on. `RootShell.proseDoc` has already collapsed the
/// model's text into a single `Insight` argument by the time this splices, so
/// the prose cannot name a component, pick a figure, reach a ref, or change one
/// digit of what the figure says. A wrong answer above a right chart is a
/// visible disagreement; a model-authored chart is a wrong number nobody can
/// see is wrong.
///
/// THE RANKING — six rungs, and the order is the point (2026-08-16, user: "i
/// want the composer to respond mostly in visuals since we can't rely on the
/// text to be that specific or accurate"). It shipped as two, which meant a
/// typed question — the shape a person actually lands on most — could reach two
/// of the roughly eighteen figures this app knows how to draw, while the two
/// most legible of them sat fully built with no caller at all.
///
///   • PICTURES (`contactSheetLine`) leads because when the matches are
///     photographs the matches ARE the answer: a grid of the things themselves
///     outranks any abstraction over them. `WidgetDayLead.kind` already ranks
///     its own ladder this way for the Home Screen tile.
///   • TIME (`runwayAxis`) is next, and only the rows carrying a real `dueAt`
///     reach it. The rows can show four dates; only the rail shows the SPREAD,
///     which is what "what's coming up" is actually asking.
///   • PEOPLE (`faces`) — a set dominated by humans is about who. Its own gate
///     is `SocialThread.hasContext`, so a masthead can never be drawn as a
///     person.
///   • WHERE, twice, at two scales. `sourceMapLine` is the full 4×3 board and
///     carries the span of years as its subline; `sourceMixLine` is the 1-big-
///     2-stacked miniature. They answer the same question, so the richer one
///     goes first and the compact one catches the sets too small for it — a
///     figure sized to its evidence rather than two different claims.
///   • WHEN last, which §247 already ruled the weakest lead when it moved the
///     heatmap to the end of `shapedSections` for this exact reason — and, like
///     WHERE, at two scales. `dialLine` puts the week on a 24-hour clock and is
///     the only thing in this app that answers which HOURS; `dailyBars` catches
///     the weeks too thin to have a rhythm at all.
///
/// NO FLOOR HERE IS THIS FILE'S. Every emitter declines on its own terms
/// (`contactSheetLine`: ≥4 distinct pictures; `runwayAxis`: ≥2 dots;
/// `faces`: ≥3 people; `sourceMapLine`: ≥6 hits and ≥2 sources;
/// `sourceMixLine`: ≥2 sources and ≥4 rows; `dailyBars`: ≥4 rows), and a set
/// that declines all six means no figure — never a smaller or a faked one.
///
/// THREE RUNGS ARE DELIBERATELY ABSENT, each for a stated reason rather than an
/// oversight. MONEY: `valueSparkLine` draws the wallet's own recorded balance
/// samples and takes no rows at all, so it would answer about the wallet rather
/// than about the matches — a figure whose subject isn't the set beneath it is
/// the §83 fake status. MEANING: `TodayBrief.clusterMap` is `async` and needs a
/// `ModelContext` for the vectors plus a PCA projection, and this function is
/// synchronous by design so the figure beats the model to the screen. SUBJECTS:
/// there is no emitter that maps `ocrTopics`/`tags` over an arbitrary hit set —
/// `FeedInsight.topicMap` is per-room and takes a source. Each is a build, not
/// a wiring.
///
/// THE ONE THING THIS FILE ADDS, and it is a correction rather than a floor:
/// `dailyBars` charts the last seven days but floors on the TOTAL count of what
/// it is handed. That is right for its existing caller, whose pool is already
/// window-scoped, and wrong here — a retrieval over an imported archive hands
/// it forty rows dated 2015 and clears the floor with every one of the seven
/// columns at zero. `KeptAskComposers.archiveRecap` documents that exact
/// rendering ("seven empty columns, which reads as a broken card rather than as
/// an honest zero") as its reason for carrying no bars at all. So the window
/// filter happens HERE, before the hand-off, which turns the emitter's own
/// `>= 4` into "at least four of these landed in the last week" — the floor it
/// was always meant to be, applied to the rows it was always meant to see.
enum AnswerFigure {

    /// The days `KeptAskComposers.dailyBars` charts. Spelled here because this
    /// file has to filter to that window before handing rows over, and a
    /// mismatch is silent in the worst direction: too wide and the chart draws
    /// empty columns it cleared the floor on, too narrow and it declines over a
    /// week it could have drawn.
    static let barsWindowDays = 7

    /// The figure line for a retrieved set, or nil when both emitters decline.
    ///
    /// `hits` is the set the answer is GROUNDED on, not the corpus — which is
    /// why both eyebrows say "these" and neither says "today". A figure whose
    /// eyebrow claims a wider subject than its data is the §83 fake status in
    /// the one place a number is believed on sight.
    ///
    /// Rows are filtered once, at this boundary (corollary 4): dead models
    /// dropped, import receipts dropped — the app talking about itself is
    /// excluded from every aggregate in this codebase and this is one.
    ///
    /// `@MainActor` because it reads live `Thing`s and both emitters are; the
    /// splice below deliberately is NOT, so the streaming painter can apply a
    /// finished line from whatever context it is handed.
    @MainActor
    static func line(for hits: [Thing], now: Date = .now) -> String? {
        let rows = hits.live.filter { !Corpus.isImportReceipt($0) }
        guard !rows.isEmpty else { return nil }
        // 1 — the matches themselves, when they are pictures.
        if let sheet = KeptAskComposers.contactSheetLine(rows) { return sheet }
        // 2 — the spread of what's due. Only rows carrying a REAL deadline are
        // handed over: `runwayAxis` falls back to `now` for a nil `dueAt`, so an
        // unfiltered set would pile every undated match onto the marker and draw
        // a rail claiming they are all due this second.
        let dated = rows.filter { $0.dueAt != nil }
                        .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
        if let axis = KeptAskComposers.runwayAxis(dated) { return axis }
        // 3 — who these are from.
        if let roster = TodayBrief.faces(rows) { return roster }
        // 4/5 — where they live, the full board first and the miniature for the
        // sets too small to fill one. See the type comment: one question, two
        // scales, never two claims.
        if let board = KeptAskComposers.sourceMapLine(rows) { return board }
        if let mix = TodayBrief.sourceMixLine(
            rows, eyebrow: String(localized: "Where these came from")) {
            return mix
        }
        // 6/7 — WHEN, at two scales, the same way WHERE is. The clock says
        // which HOURS, which nothing else in this app answers and which the
        // bars structurally cannot: a week that all happened after ten at night
        // and a week spread across every waking hour draw the identical strip.
        // It needs a real rhythm to be one (12 marks), so the bars catch every
        // week too thin for it.
        //
        // The dial windows itself — same `barsWindowDays`, passed in — so it is
        // handed the unfiltered rows on purpose.
        if let dial = KeptAskComposers.dialLine(
            rows, eyebrow: String(localized: "When these landed"), now: now) {
            return dial
        }
        // Only the rows inside the chart's own window — see the type comment.
        let cutoff = Calendar.current.date(byAdding: .day, value: -(barsWindowDays - 1),
                                           to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(-Double(barsWindowDays) * 86_400)
        let recent = rows.filter { $0.capturedAt >= cutoff }
        return KeptAskComposers.dailyBars(recent,
                                          eyebrow: String(localized: "When these landed"))
    }

    // MARK: - The prose, once a figure leads it

    /// The longest a caption may run, in characters.
    ///
    /// Not a line count: a line is a rendering fact that changes with the type
    /// size, the language and the width, and this is a budget on how much
    /// UNVERIFIED text sits above the verified picture.
    static let captionBudget = 200

    /// A first sentence shorter than this takes ONE more with it.
    ///
    /// It does NOT claim to detect a preamble. That was the first cut of this
    /// rule and it was wrong on its own evidence: "Here's what I found." is 20
    /// characters and "Mostly policy this month." is 25, so no threshold
    /// separates a worthless opener from a complete answer, and a rule tuned to
    /// that five-character gap would be decided by the model's punctuation.
    ///
    /// What it actually says is weaker and true: a caption this short has room
    /// for another sentence and may need one, so take it. A real first sentence
    /// gains a second and stays well inside the budget; a bare "Sure." gains the
    /// substance behind it. Two is the ceiling either way.
    static let preambleFloor = 40

    /// The model's prose cut to a caption (2026-08-16, user: "we can't rely on
    /// the text to be that specific or accurate").
    ///
    /// WHY CUTTING IS THE FIX. The figure above this is the app's own
    /// arithmetic and cannot be wrong; the prose is the one part of the answer
    /// that can. Leaving four paragraphs of it above the rows spends the most
    /// space and the most reading time on the least reliable thing on screen,
    /// and a wrong sentence at that length reads as the answer. At a sentence
    /// it reads as a remark beside a picture that disagrees with it — which is
    /// the failure mode we can live with, because it is the one a person can
    /// SEE. Nothing is hidden that the answer needed: the figure states the
    /// shape and the grounding rows are the evidence, both already on screen.
    ///
    /// ONLY WHEN A FIGURE LED. With no figure the prose IS the answer and this
    /// is never called — cutting there would leave a question answered by a
    /// fragment and nothing else, which is strictly worse than a long answer.
    /// The call sites make that choice; this function assumes it was made.
    ///
    /// A TERMINATOR IS NOT A FULL STOP. `.` inside a decimal is the failure
    /// this has to survive — "the wallet moved 1.4% today" cut at the first dot
    /// is a caption that says "the wallet moved 1", a wrong NUMBER produced by
    /// a text rule, which is the one class of error this whole feature exists
    /// to keep off the screen. So a terminator only ends a sentence when what
    /// follows is whitespace-then-a-capital, or nothing at all: "1.4%" fails on
    /// the digit, "Aug. 3" fails on the digit, and "…this month. The rebate…"
    /// passes.
    static func caption(_ prose: String) -> String {
        let text = prose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        let parts = sentences(text)
        // Always at least one, however long — a caption that declines to say
        // anything is not a shorter answer, it is a missing one; the clamp
        // below is what bounds that case.
        guard var out = parts.first else { return text }
        if out.count < preambleFloor, parts.count > 1 { out += " " + parts[1] }
        // TWO IS THE CEILING, by construction rather than by a budget check.
        // Filling to `captionBudget` was this function's first cut and it read
        // as working — every caption came out shorter than the prose — while
        // actually keeping four sentences whenever they fit, which is the
        // paragraph this exists to stop wearing a smaller number.
        return out.count <= captionBudget ? out : clamped(out)
    }

    /// The text split after each real sentence terminator, in order, each piece
    /// trimmed. A piece may itself be longer than the budget — `caption`'s
    /// clamp is what bounds that case.
    private static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            guard c == "." || c == "!" || c == "?" else { continue }
            // What follows decides whether this ended a sentence. End of text
            // always does; otherwise it must be whitespace, and the next
            // non-space character must be a capital or an opening quote.
            var j = i + 1
            if j >= chars.count {
                out.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue
            }
            guard chars[j].isWhitespace else { continue }
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            guard j < chars.count else {
                out.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue
            }
            let next = chars[j]
            guard next.isUppercase || next == "\u{201C}" || next == "'" else { continue }
            out.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    /// A single sentence longer than the budget, cut at the last WORD boundary
    /// inside it. Never mid-word: a caption ending "the wallet moved 1.4% agai…"
    /// reads as a rendering fault rather than as an abridgement.
    private static func clamped(_ text: String) -> String {
        let head = String(text.prefix(captionBudget))
        guard let space = head.lastIndex(of: " ") else { return head + "…" }
        let cut = String(head[head.startIndex..<space])
            .trimmingCharacters(in: .whitespaces)
        return (cut.isEmpty ? head : cut) + "…"
    }

    /// The root line every answer document opens with. Spelled once so the
    /// splice below and its guard can never disagree about what it is looking
    /// for.
    private static let rootPrefix = "root = Stack(["

    /// Splices a figure line into a finished document as the FIRST child of the
    /// root — the mirror of `RootShell.appendingGrounding`'s suffix surgery, and
    /// deliberately the same shape: prefix surgery on the ref list, the line
    /// appended anywhere after. `GenParser`'s own law ("any prefix of any
    /// document renders; unresolved references drop from arrays") is what makes
    /// declaration order free here, so the line does not have to be threaded
    /// into the middle of a document that is still streaming.
    ///
    /// Returns the document UNTOUCHED when there is no figure, no root, or a
    /// root this cannot parse — a document that renders without its figure is a
    /// smaller answer, and a document with a corrupted root line is no answer at
    /// all.
    static func prepending(_ line: String?, to doc: [String]) -> [String] {
        guard let line,
              let ref = line.split(separator: " ", maxSplits: 1).first.map(String.init),
              !ref.isEmpty,
              // Idempotent: the streaming painter calls this on a fresh
              // `proseDoc` per snapshot, so this can't fire today — but a caller
              // that ever splices twice must get one figure, not two refs
              // pointing at one line.
              !doc.contains(where: { $0.hasPrefix(ref + " = ") }),
              let i = doc.firstIndex(where: { $0.hasPrefix(rootPrefix) }),
              doc[i].hasSuffix("])")
        else { return doc }
        let inner = doc[i].dropFirst(rootPrefix.count).dropLast(2)
        var out = doc
        out[i] = rootPrefix + (inner.isEmpty ? ref : ref + ", " + inner) + "])"
        out.append(line)
        return out
    }
}
