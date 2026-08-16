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
/// THE RANKING — mix, then bars, and the order is the point.
///
///   • `sourceMixLine` answers WHERE, which holds for any retrieved set. A
///     search is not a time window: its matches can be from this morning or
///     from a 2014 archive, and provenance is true of both.
///   • `dailyBars` answers WHEN, which §247 already ruled the weakest lead when
///     it moved the heatmap to the end of `shapedSections` for exactly this
///     reason. It leads here only when the mix declined — a set that all came
///     from one room has no mix to draw, and then WHEN is the only thing left
///     that is both true and not already in the rows.
///
/// NEITHER FLOOR IS THIS FILE'S. Both emitters decline on their own terms
/// (`sourceMixLine`: ≥2 sources and ≥4 rows; `dailyBars`: ≥4 rows), and a
/// figure that declines twice means no figure — never a smaller or a faked one.
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
        if let mix = TodayBrief.sourceMixLine(
            rows, eyebrow: String(localized: "Where these came from")) {
            return mix
        }
        // Only the rows inside the chart's own window — see the type comment.
        let cutoff = Calendar.current.date(byAdding: .day, value: -(barsWindowDays - 1),
                                           to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(-Double(barsWindowDays) * 86_400)
        let recent = rows.filter { $0.capturedAt >= cutoff }
        return KeptAskComposers.dailyBars(recent,
                                          eyebrow: String(localized: "When these landed"))
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
