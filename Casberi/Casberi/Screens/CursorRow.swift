import SwiftUI

/// A finished agent run, drawn as what it is: a piece of work somebody's
/// machine did while they weren't watching, and a paragraph saying what came
/// of it (2026-08-08, prd §340).
///
/// **Why this exists.** Cursor had no `FeedScreen.Shape` case, so its room fell
/// to `.plain` and drew a `BandRow` per run — an icon, `titleLine`'s 80-character
/// clamp, and a timestamp. Meanwhile the agent's own `summary`, which is the
/// entire reason to keep a finished run at all, sat on the model unrendered.
/// That is precisely the §313 X finding one room over: the words are in the
/// store, and nothing draws them.
///
/// Three things this row says that the band row could not:
///
///   • **The outcome, as a mark rather than a word buried in a title.** It is
///     read from the row's TAGS (`CursorAgentStatus.facetTag`), never parsed
///     back out of the localized title — see that type's note for why the
///     title is the wrong place to ask.
///   • **The summary**, clamped rather than cut, so a run reads like a report.
///   • **Whether there is a pull request**, which is the difference between a
///     run that produced something and one that only tried.
struct CursorRow: View {
    let thing: Thing

    /// Liveness guard (build 188, corollary 5 — see `ThingRowKeying.swift`).
    /// SwiftUI re-evaluates a LEAF view's body on the model's own observation,
    /// independently of whatever parent built it, so a row already on screen
    /// is not covered by any guard the parent does.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        // ONE ANATOMY (prd §744): it had no lead, and its outcome word sat
        // BEFORE the title. The outcome and the pull request are one quiet
        // line under the report.
        DSFeedRow(name: CursorFetch.displayTitle(thing.title), nameLines: 3,
                  line: DSFeed.line(report), lineLines: 6) {
            BridgeIcon(name: thing.source, size: DS.Mark.row)
        } trailing: {
            LiveTimeText(date: thing.capturedAt)
        } below: {
            if let quiet = quietLine {
                quiet
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityLabel(Text(outcome.map { "Outcome: \($0)" } ?? ""))
            }
        }
    }

    /// The outcome in its attention ink, then the pull request, as one `Text`.
    private var quietLine: Text? {
        var parts: [Text] = []
        if let outcome { parts.append(Text(outcome).foregroundStyle(DS.attention)) }
        if let pullRequest { parts.append(Text(pullRequest)) }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(verbatim: " · ") + $1 }
    }

    /// The outcome word, or nil for a run that simply succeeded. Read from the
    /// tags the bridge lands, so it survives a language change and a clamped
    /// title alike.
    private var outcome: String? {
        thing.tags.first { CursorAgentStatus.facetTags.contains($0) }
    }

    /// What the agent says it did. Absent on runs that never got far enough to
    /// write one, which is common for a failure and is not a defect — the row
    /// is then its title and its outcome, which is the whole truth available.
    private var report: String? {
        guard let text = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text != thing.title else { return nil }
        return text
    }

    /// What became of the pull request, or nil when the run opened none.
    ///
    /// Gated on the TAG rather than on the link, because `content` always
    /// carries a URL — the agent's own Cursor page when there is no PR — so
    /// testing the link would claim a pull request for every run.
    ///
    /// "Opened" is the honest word while it is still open: the loop-closer
    /// (`CursorPullRequests`) only speaks once GitHub has given a final
    /// answer, so an unresolved row must not imply one either way.
    private var pullRequest: String? {
        guard thing.tags.contains("PR") else { return nil }
        if thing.tags.contains(CursorPullRequests.mergedTag) {
            return String(localized: "Pull request merged")
        }
        if thing.tags.contains(CursorPullRequests.closedTag) {
            return String(localized: "Pull request closed without merging")
        }
        return String(localized: "Opened a pull request")
    }
}
