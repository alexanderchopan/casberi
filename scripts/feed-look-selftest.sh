#!/bin/zsh
# A source's row looks like its app (prd §1645), compiled AS SHIPPED.
#
# `Model/FeedLook.swift` is Foundation-only, so this compiles it whole — no
# stubs, no copied logic — and asks it what each source's row wears. Every
# failure it catches renders as an ordinary-looking Feed:
#
#   • a GitHub row that says Merged, a fact the bridge never stores
#   • a like drawn as a post, its "words" a sentence about you
#   • a notice's title doubled under its name, because the post look read
#     the title instead of `postText`
#   • a Stripe payment whose figure moved into its title behind a verdict
#   • a workout whose time is said twice ("45 min" … "45 min")
#   • a text file's first words taken for its size
#   • a pull request's number said twice, in the title and the place
#   • (§1648) an event with no hours, an issue key lost, a Done no tracker
#     stored, a profile link as Duolingo's line, a figure with no stored fact
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/FeedLook.swift"
SEAM="Casberi/Casberi/Model/TitleSeam.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
typealias F = FeedLook.Facts

// Agents: your question, in your bubble.
check(FeedLook.of(F(source: "Claude", kind: "chat", title: "How much did I train this week?", isAgent: true))
      == .agentAsk("How much did I train this week?"), "an agent chat is your question")
check(FeedLook.of(F(source: "ChatGPT", kind: "chat", title: "Trip plan: Lisbon",
                    content: "Plan four days in Lisbon in March", isAgent: true))
      == .agentAsk("Plan four days in Lisbon in March"), "a named chat shows your question, not its name")
check(FeedLook.of(F(source: "Telegram", kind: "chat", title: "Chat with Mia")) == .plain,
      "a chat with a person is not an agent's (ChatFace draws it)")

// Posts: name, why, words — from postText only.
check(FeedLook.of(F(source: "X", kind: "chat", title: "tomas replied: same", postText: "same, every single time",
                    author: "tomas", socialContext: "reply", contextLabel: "replied"))
      == .post(name: "tomas", context: "replied", words: "same, every single time"), "a reply is a post")
check(FeedLook.of(F(source: "Bluesky", kind: "chat", title: "sam liked your post", postText: "my post",
                    author: "sam", socialContext: "liked")) == .plain, "a like is no one's words")
check(FeedLook.of(F(source: "X", kind: "chat", title: "tomas replied: same", author: "tomas",
                    socialContext: "reply")) == .plain, "no postText, no post: the title would say the name twice")

// Mail: sender over subject.
check(FeedLook.of(F(source: "Gmail", kind: "mail", title: "Design review moved", mailSender: "Uma"))
      == .mail(sender: "Uma", subject: "Design review moved"), "a mail is its sender over its subject")
check(FeedLook.of(F(source: "Gmail", kind: "mail", title: "Hello")) == .plain, "a mail with no sender stays plain")

// GitHub: repository and number, a stamped state, never Merged.
let pr = F(source: "GitHub", kind: "link", title: "Sync conflicts (#414)",
           content: "https://github.com/quill/app/pull/414", tags: ["Review"])
check(FeedLook.of(pr) == .code(title: "Sync conflicts", place: "app #414",
                               state: .init(word: "Review", tone: .waiting)), "a PR names its place and its review")
var merged = pr; merged.tags = []; merged.title = "Merged: one screen"
if case let .code(_, _, state) = FeedLook.of(merged) { check(state == nil, "Merged is not stored, so no state") }
else { check(false, "a PR with no tags still names its place") }
var closed = pr; closed.tags = []; closed.mark = "done"
if case let .code(_, _, state) = FeedLook.of(closed) { check(state?.word == "Closed", "a done item is Closed") }
check(FeedLook.githubPlace("https://github.com/quill/app") == "app", "a repository alone")
check(FeedLook.githubPlace("see https://gitlab.com/x/y") == nil, "only github.com")

// Workouts: the figure, and the duration once.
check(FeedLook.of(F(source: "Apple Health", kind: "event", title: "Run · 5.2 km", sourceRef: "hkworkout:1", duration: "28:14"))
      == .workout(name: "Run", figure: "5.2 km", duration: "28:14"), "a run carries its distance and time")
check(FeedLook.of(F(source: "Strava", kind: "event", title: "Strength · 45 min", sourceRef: "hkworkout:2", duration: "45 min"))
      == .workout(name: "Strength", figure: "45 min", duration: nil), "a time is not said twice")

// Files: type and a stored size, never a text file's words.
check(FeedLook.of(F(source: "Files", kind: "file", title: "TAP-1147.pdf", content: "84 KB"))
      == .file(name: "TAP-1147.pdf", type: "PDF", size: "84 KB"), "a PDF wears its type and size")
check(FeedLook.of(F(source: "Files", kind: "file", title: "notes.txt", content: "Remember the milk"))
      == .file(name: "notes.txt", type: "TXT", size: nil), "a text file's words are not a size")

// Work verdicts, and money keeps its column.
let alarm = FeedLook.Status(word: "Firing", tone: .failed)
check(FeedLook.of(F(source: "AWS", kind: "link", title: "prod-api-5xx", workOutcome: alarm))
      == .status(title: "prod-api-5xx", alarm), "an alarm says it is firing")
check(FeedLook.of(F(source: "Stripe", kind: "link", title: "Ada Lovelace · $49.00",
                    workOutcome: .init(word: "Paid", tone: .landed), hasPrice: true)) == .plain,
      "a payment keeps its money column")

// prd §1648. Calendar: the hours and place; all day has no end; cancelled says so.
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
check(FeedLook.of(F(source: "Calendar", kind: "event", title: "Design review", content: "14:00 · Studio 3",
                    sourceRef: "ekevent:1", start: t0, end: t0 + 3600))
      == .event(title: "Design review", start: t0, end: t0 + 3600, allDay: false, place: "Studio 3", cancelled: false),
      "an event says its hours and its place")
check(FeedLook.of(F(source: "Calendar", kind: "event", title: "Offsite", content: "All day",
                    sourceRef: "ekevent:2", start: t0, end: t0 + 86_400, allDay: true))
      == .event(title: "Offsite", start: t0, end: nil, allDay: true, place: nil, cancelled: false),
      "an all-day event draws no end and no place it does not have")
if case let .event(_, _, _, _, _, cancelled) = FeedLook.of(F(source: "Calendar", kind: "event", title: "Lunch",
        sourceRef: "ekevent:3", start: t0, cancelled: true)) { check(cancelled, "a cancelled event says so") }
else { check(false, "a cancelled event is still an event") }
check(FeedLook.of(F(source: "Calendar", kind: "event", title: "Lunch", sourceRef: "ics:1", start: t0)) == .plain,
      "a subscribed calendar's row is not EventKit's")

// Issues: the key in code type; the tracker's status name is not stored.
check(FeedLook.of(F(source: "Linear", kind: "link", title: "Paste freezes — ENG-142", mark: "doing"))
      == .code(title: "Paste freezes", place: "ENG-142", state: .init(word: "In progress", tone: .neutral)),
      "a Linear issue names its key and that it is started")
check(FeedLook.of(F(source: "Jira", kind: "reminder", title: "Export drops a page — QM-88", mark: "done"))
      == .code(title: "Export drops a page", place: "QM-88", state: .init(word: "Closed", tone: .neutral)),
      "a finished Jira issue is Closed, never a guessed Done")
check(FeedLook.of(F(source: "Linear", kind: "link", title: "Ship it — soon")) == .plain, "no key, no code look")
check(FeedLook.of(F(source: "Sentry", kind: "link", title: "web · QUILL-3F · TypeError: rows", tags: ["Regression"]))
      == .code(title: "TypeError: rows", place: "QUILL-3F", state: .init(word: "Regression", tone: .waiting)),
      "a Sentry regression names its short id")

// Packages: the version is the figure; a deprecation says so in red.
check(FeedLook.of(F(source: "npm", kind: "link", title: "quill-parser 2.4.1", tags: ["Release"]))
      == .figure(title: "quill-parser", line: nil, figure: "2.4.1", style: .code), "a release is its version")
check(FeedLook.of(F(source: "PyPI", kind: "link", title: "Deprecated · fold-tools", tags: ["Deprecated"]))
      == .status(title: "fold-tools", .init(word: "Deprecated", tone: .failed)), "a deprecation is red")

// Reviews: the stars the title carries, out of five.
check(FeedLook.of(F(source: "App Store Connect", kind: "link", title: "Keeps up — ★★★★☆ · Quillmark",
                    tags: ["Review"], authorHandle: "mara_k"))
      == .review(title: "Keeps up", by: "mara_k", stars: 4), "a review is its stars")
check(FeedLook.of(F(source: "App Store Connect", kind: "link", title: "Build 286 — Ready to test", tags: ["Build"]))
      == .plain, "a build is no review")

// Feeds: the publication over the headline, never the app's own name.
check(FeedLook.of(F(source: "Substack", kind: "link", title: "Why every app is a feed", authorHandle: "The Weekly Fold"))
      == .byline(who: "The Weekly Fold", what: "Why every app is a feed"), "a post is its publication over its headline")
check(FeedLook.of(F(source: "RSS", kind: "link", title: "Hello", authorHandle: "RSS")) == .plain,
      "a byline that is the app's name says nothing the icon does not")

// Highlights: the passage, quoted, over its book.
check(FeedLook.of(F(source: "Kindle", kind: "note", title: "A habit is a decision.",
                    authorHandle: "The Slow Library — R. Okafor", summary: "page 42"))
      == .quote(passage: "A habit is a decision.", from: "The Slow Library — R. Okafor · page 42"), "a Kindle highlight")
check(FeedLook.of(F(source: "Readwise", kind: "note", title: "Attention is rare.", content: "Essays — S. Weil"))
      == .quote(passage: "Attention is rare.", from: "Essays — S. Weil"), "a Readwise highlight")

// Figures at the edge.
check(FeedLook.of(F(source: "Duolingo", kind: "event", title: "40 XP in Spanish",
                    content: "https://duolingo.com/profile/x", summary: "3 lessons · 12 min · Streak extended"))
      == .figure(title: "Spanish", line: "3 lessons · 12 min · Streak extended", figure: "40 XP", style: .bold),
      "Duolingo's XP is the figure, never a profile link as the line")
check(FeedLook.of(F(source: "Steam", kind: "link", title: "Played Hollow Pines",
                    summary: "1.5h past two weeks · 40.2h all time"))
      == .figure(title: "Hollow Pines", line: "past two weeks · 40.2h all time", figure: "1.5h", style: .bold),
      "Steam's hours are the figure")
check(FeedLook.of(F(source: "Apple Music", kind: "link", title: "Night Ferry — Lowtide", length: "3:42"))
      == .figure(title: "Night Ferry", line: "Lowtide", figure: "3:42", style: .quiet), "a song's length")
check(FeedLook.of(F(source: "Apple Music", kind: "link", title: "Night Ferry — Lowtide")) == .plain,
      "no stored length, no figure")
check(FeedLook.of(F(source: "ENS", kind: "link", title: "quill.eth expires Dec 3", tags: ["Expiring"],
                    authorHandle: "quill.eth", dueAt: t0 + 23 * 86_400 + 60, now: t0))
      == .figure(title: "quill.eth", line: nil, figure: "23 days", style: .attention), "an expiring name counts down")
check(FeedLook.of(F(source: "ENS", kind: "link", title: "quill.eth expired", authorHandle: "quill.eth",
                    dueAt: t0 - 60, now: t0)) == .plain, "a lapsed name keeps the title that says so")

if failures > 0 { print("feed-look-selftest: \(failures) failed"); exit(1) }
print("feed-look-selftest: OK")
SWIFT

swiftc -O -o "$work/run" "$SRC" "$SEAM" "$work/main.swift" 2>"$work/err" || { cat "$work/err"; exit 1; }
"$work/run"

# A guard must be able to fail: put Merged back and the run must catch it.
sed 's/if set.contains("Checks failing")/return Status(word: "Merged", tone: .landed); if set.contains("Checks failing")/' "$SRC" > "$work/mut.swift"
if ! grep -q 'word: "Merged"' "$work/mut.swift"; then print "✗ mutation did not apply"; exit 1; fi
swiftc -O -o "$work/mut" "$work/mut.swift" "$SEAM" "$work/main.swift" 2>/dev/null || { print "✗ mutant did not compile"; exit 1; }
if "$work/mut" >/dev/null; then print "✗ mutation survived: a GitHub row saying Merged passed"; exit 1; fi
print "  ✓ mutation caught: a GitHub state the bridge never stored"

# And for §1648: a finished issue said as Done, a word the tracker never stored.
sed 's/case "done":  Status(word: String(localized: "Closed"), tone: .neutral)/case "done":  Status(word: "Done", tone: .landed)/' "$SRC" > "$work/mut2.swift"
if ! grep -q 'word: "Done", tone: .landed' "$work/mut2.swift"; then print "✗ mutation 2 did not apply"; exit 1; fi
swiftc -O -o "$work/mut2" "$work/mut2.swift" "$SEAM" "$work/main.swift" 2>/dev/null || { print "✗ mutant 2 did not compile"; exit 1; }
if "$work/mut2" >/dev/null; then print "✗ mutation survived: a finished issue said Done"; exit 1; fi
print "  ✓ mutation caught: an issue state the tracker never stored"
