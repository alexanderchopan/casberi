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
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/FeedLook.swift"
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

if failures > 0 { print("feed-look-selftest: \(failures) failed"); exit(1) }
print("feed-look-selftest: OK")
SWIFT

swiftc -O -o "$work/run" "$SRC" "$work/main.swift" 2>"$work/err" || { cat "$work/err"; exit 1; }
"$work/run"

# A guard must be able to fail: put Merged back and the run must catch it.
sed 's/if set.contains("Checks failing")/return Status(word: "Merged", tone: .landed); if set.contains("Checks failing")/' "$SRC" > "$work/mut.swift"
if ! grep -q 'word: "Merged"' "$work/mut.swift"; then print "✗ mutation did not apply"; exit 1; fi
swiftc -O -o "$work/mut" "$work/mut.swift" "$work/main.swift" 2>/dev/null || { print "✗ mutant did not compile"; exit 1; }
if "$work/mut" >/dev/null; then print "✗ mutation survived: a GitHub row saying Merged passed"; exit 1; fi
print "  ✓ mutation caught: a GitHub state the bridge never stored"
