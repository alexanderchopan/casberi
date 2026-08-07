#!/bin/zsh
# Casberi agent-open self-test — verifies the SHIPPED composition behind the
# agent's room on a plain open (prd §332, 2026-08-07):
#
#   Casberi/Casberi/Model/AgentOpen.swift
#     — tiles / face / taskFace   (a kept ask's answer on its face)
#     — splitSentence             (a reading cut into headline + qualifier)
#     — group / terms             (the window threaded, single-assignment)
#     — row                       (the margin, and its priority)
#     — clamp                     (a cut that never invents half a word)
#
# WHY A HARNESS. This surface is the first thing a person sees every day, and
# every failure in it is a SILENT WRONG ANSWER that renders perfectly — there
# is no crash, no empty state, no log line. A build succeeds, the screen sweep
# passes, and the room simply says something untrue in the largest type on it:
#
#   • a tile printing "3 things late" — the tally the user ruling of
#     2026-07-31 removed from every other surface, restored in the biggest
#     type on the screen, because a composer changed its `delta` wording;
#   • a tile rendered from a reading that was never taken (`unreachable`, or a
#     cold launch where `refreshDigests` hasn't run) — §83's fake status,
#     indistinguishable from a real answer;
#   • a thing appearing under two threads, which reads as a duplicate row and
#     is what single assignment exists to prevent;
#   • threads reordering between two opens over identical data, which reads as
#     a broken screen long before it reads as fresh;
#   • the stoplist decaying so the biggest thread every night is "screenshot" —
#     a container word ranked as a subject (§313's ruling, one surface over);
#   • a margin claiming a deadline where the row only carries a date it read
#     out of a picture, which is a promise the app cannot keep.
#
# `AgentOpen.swift` is Foundation-only BY DESIGN — which is exactly what lets
# this compile it WHOLE and UNMODIFIED, with no stubs at all (`retriever-
# selftest` needs six). So there is no extraction step that can drift: the
# harness runs the shipped file or it does not run.
#
# Pure, local, deterministic — no network, no simulator, no corpus. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/AgentOpen.swift"
BOARD="Casberi/Casberi/Screens/AgentOpenBoard.swift"
COMPOSER="Casberi/Casberi/Shell/Composer.swift"
STORE="Casberi/Casberi/Model/KeptAskStore.swift"
INSIGHT="Casberi/Casberi/Model/HomeInsightStore.swift"

for f in "$SRC" "$BOARD" "$COMPOSER" "$STORE" "$INSIGHT"; do
  [[ -f "$f" ]] || { print -u2 "missing $f"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_754_500_000)   // fixed clock, no Date.now
func at(_ hoursAgo: Double) -> Date { now.addingTimeInterval(-hoursAgo * 3600) }
func inDays(_ d: Int) -> Date { now.addingTimeInterval(Double(d) * 86_400 + 3600) }

func item(_ id: String, _ title: String, source: String = "RSS",
          tags: [String] = [], author: String? = nil, hoursAgo: Double = 1,
          dueAt: Date? = nil, replyCount: Int? = nil, socialContext: String? = nil,
          priorKeep: Date? = nil, datedMoment: Date? = nil) -> AgentOpen.Item {
    AgentOpen.Item(id: id, title: title, source: source, tags: tags, author: author,
                   capturedAt: at(hoursAgo), dueAt: dueAt, replyCount: replyCount,
                   socialContext: socialContext, priorKeep: priorKeep,
                   datedMoment: datedMoment)
}

// ─────────────────────────── tiles ───────────────────────────
print("tiles")

// The whole reason the reduction exists: the task composers hand back
// "3, 3 things late", and printing it raw puts a tally in the headline.
let overdueRaw = AgentOpen.KeptAsk(kind: "overdue", title: "What's overdue?",
                                   delta: "3, 3 things late", digest: "3",
                                   changed: true, subject: nil)
let rawFace = AgentOpen.tiles(from: [overdueRaw]).first
check(rawFace?.headline == "Late", "a subjectless task tile leads with the word, not the count")
check(rawFace?.sub == "3 things", "…and the quantity trails as the qualifier")

// With a subject the design's actual shape: the NAME, then "+2 more".
var overdueNamed = overdueRaw
overdueNamed.subject = "Visa documents"
let namedFace = AgentOpen.tiles(from: [overdueNamed]).first
check(namedFace?.headline == "Visa documents", "a named task tile leads with the thing")
check(namedFace?.sub == "+2 more", "…and the remainder is an aside, not a scoreboard")

// One overdue thing has no remainder — "+0 more" would be noise.
var single = overdueRaw
single.subject = "Renew passport"
single.delta = "1, 1 thing late"
check(AgentOpen.tiles(from: [single]).first?.sub == nil,
      "a lone task names the thing and says nothing else")

// §83: a reading that was never taken is never a face.
//
// The delta is DELIBERATELY non-empty. The shipped composers pair
// `digest: "unreachable"` with `delta: ""`, so a realistic fixture is caught by
// the empty-delta guard one line later and proves nothing about the unreachable
// guard at all — the mutation that deletes it survived exactly that way on this
// harness's first run. A composer changing its wording is precisely the drift
// this guard defends against, so the fixture states that shape.
let unreachable = AgentOpen.KeptAsk(kind: "watchlist", title: "How's my watchlist?",
                                    delta: "Couldn't read prices.", digest: "unreachable",
                                    changed: false, subject: nil)
check(AgentOpen.tiles(from: [unreachable]).isEmpty,
      "an unreachable read renders no tile at all")

// A cold launch: refreshDigests hasn't run, so there is no delta yet.
let notRead = AgentOpen.KeptAsk(kind: "wallet", title: "How's my wallet?",
                                delta: "", digest: "", changed: false, subject: nil)
check(AgentOpen.tiles(from: [notRead]).isEmpty, "an unread ask renders no tile")

let money = AgentOpen.KeptAsk(kind: "wallet", title: "How's my wallet?",
                              delta: "ETH is up 2.1% — the rest is flat.",
                              digest: "x", changed: true, subject: nil)
let moneyFace = AgentOpen.tiles(from: [money]).first
check(moneyFace?.headline == "ETH is up 2.1%", "a money reading splits at the dash")
check(moneyFace?.sub == "the rest is flat.", "…and its remainder becomes the qualifier")
check(moneyFace?.changed == true, "changed carries through to the tile")

check(AgentOpen.tiles(from: [money, money, money, money]).count == AgentOpen.maxTiles,
      "tiles cap at maxTiles")

// splitSentence, directly — the case with neither a dash nor a sentence end.
check(AgentOpen.splitSentence("Quiet across the board").sub == nil,
      "a bare line has no qualifier invented for it")
check(AgentOpen.splitSentence("Up 4%. Mostly SOL.").headline == "Up 4%",
      "a sentence end splits when there is no dash")

// ETH must not become Eth — capitalizedFirst, not `capitalized`.
check(AgentOpen.tiles(from: [money]).first!.headline.hasPrefix("ETH"),
      "an all-caps symbol keeps its case")

// ─────────────────────────── terms ───────────────────────────
print("terms")

check(!AgentOpen.terms(of: item("a", "Screenshot of a receipt")).contains("screenshot"),
      "a container word is not a subject")
check(AgentOpen.terms(of: item("b", "The stablecoin bill")).contains("stablecoin"),
      "a real subject survives the stoplist")
check(!AgentOpen.terms(of: item("c", "What are the new ones")).contains("what"),
      "ordinary English is stoplisted")
check(AgentOpen.terms(of: item("d", "x", tags: ["Onchain"])).contains("onchain"),
      "a tag someone chose counts as a term")
check(!AgentOpen.terms(of: item("e", "A fix for it")).contains("fix"),
      "a three-letter title word is below the floor")

// ─────────────────────────── threads ───────────────────────────
print("threads")

let window = [
    item("1", "Stablecoin bill drops the custody carve-out", tags: ["Onchain"], hoursAgo: 1),
    item("2", "Stablecoin liquidity after the bill", tags: ["Onchain"], hoursAgo: 2),
    item("3", "Stablecoin rails in Europe", tags: ["Onchain"], hoursAgo: 3),
    item("4", "A recipe for focaccia", source: "Photos", hoursAgo: 4),
    item("5", "Weather next week", source: "Bluesky", hoursAgo: 5),
    item("6", "A note to self", source: "Obsidian", hoursAgo: 6),
]
let (threads, fold) = AgentOpen.group(window, now: now)
check(threads.first?.rows.count == 3, "a real theme gathers its things")
check(threads.contains { $0.loose }, "what doesn't cluster gets the loose bucket")
check(threads.last?.loose == true, "the loose bucket ranks last")

// Single assignment — the rule that keeps a row from rendering twice.
let allRows = threads.flatMap { $0.rows.map(\.item.id) }
check(Set(allRows).count == allRows.count, "no thing appears in two threads")

check(fold?.count == 1, "what the loose bucket couldn't show is folded, not dropped")
check(fold?.sources.contains("Obsidian") == true, "the fold names who it folded")

// Determinism — the same input twice must produce byte-identical threads. A
// screen that reshuffles over unchanged data reads as broken.
let (again, _) = AgentOpen.group(window, now: now)
check(again.map(\.name) == threads.map(\.name), "grouping is deterministic")

// The TIE is what makes the order total. Two themes of equal size sort by name,
// and without a fixture that ties them the sort can lose its tie-break with no
// visible effect — which is how that mutation survived the first run. Swift's
// sort is not stable, so an untied comparator really can reorder equals.
let tied = [
    item("t1", "Zebra migration routes", tags: ["Zebras"]),
    item("t2", "Zebra herd counts", tags: ["Zebras"]),
    item("t3", "Anchovy fishery limits", tags: ["Anchovies"]),
    item("t4", "Anchovy stock recovery", tags: ["Anchovies"]),
]
let (tiedThreads, _) = AgentOpen.group(tied, now: now)
let named = tiedThreads.filter { !$0.loose }.map(\.name)
check(named == named.sorted(), "threads of equal size sort by name, so the order is total")

// The person's own spelling survives into the heading.
let cased = [item("c1", "one", tags: ["ETH"]), item("c2", "two", tags: ["ETH"])]
check(AgentOpen.group(cased, now: now).0.first?.name == "ETH",
      "a thread named for a tag keeps the tag's own case")

// A term below the floor is not a theme.
let thin = [item("1", "Focaccia recipe"), item("2", "Weather report")]
let (thinThreads, _) = AgentOpen.group(thin, now: now)
check(thinThreads.allSatisfy(\.loose), "two unrelated things make no thread")

// The streak rides the ledger's answer, and only past the floor.
let (streaked, _) = AgentOpen.group(window, streakFor: { $0 == "onchain" ? 4 : 0 }, now: now)
check(streaked.first?.streak?.contains("4") == true, "a ledger streak reaches the thread")
let (unstreaked, _) = AgentOpen.group(window, streakFor: { _ in 1 }, now: now)
check(unstreaked.allSatisfy { $0.streak == nil }, "a one-day 'streak' is not a streak")

check(AgentOpen.group([], now: now).0.isEmpty, "an empty window makes no threads")

// ─────────────────────────── margins ───────────────────────────
print("margins")

let due = item("d1", "Send evidence", dueAt: inDays(5))
check(AgentOpen.row(due, in: [due], now: now).margin?.contains("in 5 days") == true,
      "a deadline says how long is left")
let late = item("d2", "Send evidence", dueAt: at(48))
check(AgentOpen.row(late, in: [late], now: now).margin == "Overdue",
      "a passed deadline says so plainly")
let today = item("d3", "Call the bank", dueAt: now.addingTimeInterval(3600))
check(AgentOpen.row(today, in: [today], now: now).margin == "Due today",
      "today is named, not counted as zero days")

// The date read out of a picture must never claim to be a deadline — it is a
// moment the text mentions, and the wording is the whole difference.
let shot = item("s1", "Flight confirmation", datedMoment: inDays(15))
let shotMargin = AgentOpen.row(shot, in: [shot], now: now).margin
check(shotMargin?.hasPrefix("Carries a date") == true,
      "a date found in text is reported as found, never as owed")
check(shotMargin?.contains("Due") == false, "…and never borrows the deadline wording")

// Priority: consequence first. A row with both says the deadline.
let both = item("b1", "Renew", dueAt: inDays(2), priorKeep: at(2000))
check(AgentOpen.row(both, in: [both], now: now).margin?.contains("Due") == true,
      "a deadline outranks a prior keep")
// And the pairing that actually pins the ORDER of the first two rungs. Without
// a fixture carrying both, moving the read-date check above the deadline check
// changes nothing observable — the mutation survived that way on the first run.
let clash = item("b2", "Ticket", dueAt: inDays(2), datedMoment: inDays(20))
check(AgentOpen.row(clash, in: [clash], now: now).margin?.hasPrefix("Due") == true,
      "a real deadline outranks a date read out of the text")

let prior = item("p1", "The x402 long tail", priorKeep: at(24 * 60))
check(AgentOpen.row(prior, in: [prior], now: now).margin?.hasPrefix("You kept this before") == true,
      "a thing kept before says when")

let hot = item("h1", "my cast", replyCount: 7, socialContext: "mention")
check(AgentOpen.row(hot, in: [hot], now: now).margin?.contains("7") == true,
      "replies gathering under your own post is the one place a count leads")
let quietMention = item("h2", "my cast", replyCount: 1, socialContext: "mention")
check(AgentOpen.row(quietMention, in: [quietMention], now: now).margin == nil,
      "one reply is not a gathering")
// A reply count on someone ELSE's post is not about you.
let notMine = item("h3", "their post", replyCount: 9, socialContext: "liked")
check(AgentOpen.row(notMine, in: [notMine], now: now).margin == nil,
      "a busy post you merely liked earns no margin")

let twice = [item("w1", "one", author: "haley.eth"), item("w2", "two", author: "haley.eth")]
check(AgentOpen.row(twice[0], in: twice, now: now).margin?.contains("haley.eth") == true,
      "the same person twice in one window is worth saying")
let once = [item("w1", "one", author: "haley.eth"), item("w2", "two", author: "someone")]
check(AgentOpen.row(once[0], in: once, now: now).margin == nil,
      "one thing from one person is not a pattern")

check(AgentOpen.row(item("n1", "plain"), in: [item("n1", "plain")], now: now).margin == nil,
      "a row with nothing to add says nothing")

// ─────────────────────────── clamp ───────────────────────────
print("clamp")
check(AgentOpen.clamp("short", max: 20) == "short", "a short string is untouched")
let cut = AgentOpen.clamp("the quick brown fox jumps over", max: 15)
check(cut.hasSuffix("…"), "a clamp marks itself")
// EXACT, not a `contains` probe: "the quick brown…" (the mid-word cut) fails no
// substring check anyone would think to write, so the loose assertion passed
// against the broken version on this harness's first run.
check(cut == "the quick…", "a clamp cuts at a word, never mid-word")

// ─────────────────────────── composition ───────────────────────────
print("composition")
check(AgentOpen.Composition().isEmpty, "a blank composition reports empty")
var withQuiet = AgentOpen.Composition()
withQuiet.quiet = "Nothing from GitHub today."
check(!withQuiet.isEmpty, "a composition with only a quiet line is not empty")

let full = AgentOpen.compose(window: window, kept: [money], now: now)
check(!full.isEmpty, "a real open composes something")
check(full.tiles.count == 1 && !full.threads.isEmpty, "…with both halves present")

print("")
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("agent-open self-test passed")
SWIFT

print "AgentOpen self-test — the shipped file, compiled whole"
xcrun swiftc -O -enable-bare-slash-regex \
  -o "$WORK/run" "$SRC" "$WORK/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$WORK/run" ]] || { print -u2 "✗ compile failed"; exit 1; }
"$WORK/run" || exit 1

# ── Mutations ───────────────────────────────────────────────────────────────
# Each is a real defect this file could ship. A mutation that SURVIVES means the
# assertions above prove less than they appear to (the retriever lesson: a test
# can pass for the wrong reason).
print ""
print "Mutations — each must FAIL the suite"
mutate() {
  local name="$1" from="$2" to="$3"
  local dir="$WORK/mut"; rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$SRC" "$dir/AgentOpen.swift" "$from" "$to" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if a not in s:
    sys.stderr.write("MUTATION ANCHOR MISSING: %r\n" % a); sys.exit(3)
open(dst, "w").write(s.replace(a, b, 1))
PY
  if [[ $? -eq 3 ]]; then print "  ✗ $name — anchor missing (harness is stale)"; return 1; fi
  if xcrun swiftc -O -enable-bare-slash-regex -o "$dir/run" \
       "$dir/AgentOpen.swift" "$WORK/main.swift" >/dev/null 2>&1 && "$dir/run" >/dev/null 2>&1; then
    print "  ✗ $name — SURVIVED"; return 1
  fi
  print "  ✓ $name caught"
}

rc=0
# The headline defect: the tally comes back.
mutate "task tile prints the raw delta" \
  'return taskFace(delta, subject: ask.subject)' \
  'return (delta, nil)' || rc=1
# §83 — a reading nobody took, shown as an answer.
mutate "unreachable renders a tile" \
  'guard ask.digest != "unreachable" else { return nil }' \
  'if false { return nil }' || rc=1
# Single assignment removed — a row renders under two threads.
mutate "a thing lands in every thread it matches" \
  'guard let term = assigned[item.id] else { continue }' \
  'for t2 in terms(of: item) where themes[t2] != nil { if members[t2] == nil { order.append(t2) }; members[t2, default: []].append(item) }; guard let term = assigned[item.id] else { continue }' || rc=1
# The stoplist stops holding — container words rank as subjects.
mutate "container words become subjects" \
  '"screenshot", "screenshots", "photo", "photos", "image", "images",' \
  '' || rc=1
# The floor drops — a thing of one becomes a "theme".
mutate "a single thing becomes a thread" \
  'static let threadFloor = 2' \
  'static let threadFloor = 1' || rc=1
# The margin priority inverts — a picture's date outranks a real deadline.
mutate "a read date outranks a deadline" \
  'if let due = item.dueAt {' \
  'if let moment = item.datedMoment { return Row(item: item, margin: String(localized: "Carries a date: \(dateLine(moment))"), marginIsSignal: true) }; if let due = item.dueAt {' || rc=1
# A date found in text starts claiming to be owed.
mutate "a read date borrows the deadline wording" \
  'margin: String(localized: "Carries a date: \(dateLine(moment))")' \
  'margin: String(localized: "Due \(dateLine(moment))")' || rc=1
# The reply margin stops checking whose post it is.
mutate "someone else's busy post earns your margin" \
  'if let replies = item.replyCount, replies >= 3, item.socialContext == "mention" {' \
  'if let replies = item.replyCount, replies >= 3 {' || rc=1
# Ordering stops being total — the screen reshuffles over identical data.
mutate "thread order becomes unstable" \
  'threads.sort { $0.rows.count == $1.rows.count ? $0.name < $1.name
                                                     : $0.rows.count > $1.rows.count }' \
  'threads.sort { $0.rows.count > $1.rows.count }' || rc=1
# The clamp starts cutting mid-word.
mutate "clamp cuts mid-word" \
  'if let sp = head.range(of: " ", options: .backwards) {
            return String(head[..<sp.lowerBound]) + "…"
        }' \
  'if false { return "" }' || rc=1
# ETH becomes Eth.
# A thread named for a tag must keep the person's own spelling. Title-casing it
# back up turns a tag of "ETH" into "Eth" and "x402" into "X402" — in the
# heading of a section about their own subject. (The original mutation here
# targeted `capitalizedFirst` itself and SURVIVED, because both call sites feed
# it lowercase input: the property was never exercised, and the real defect was
# one layer up in the display name.)
mutate "a thread loses the person's own spelling" \
  'return Thread(name: spelling[term] ?? term.capitalizedFirst,' \
  'return Thread(name: term.capitalizedFirst,' || rc=1

# ── Drift guards ────────────────────────────────────────────────────────────
# The wiring the compiled functions cannot prove. Each names a promise made in
# a DIFFERENT file that this composition depends on.
print ""
print "Drift guards"
guard_has() {
  local what="$1" file="$2" pat="$3"
  # Comments stripped: several of these files DOCUMENT the old behaviour in
  # prose, so a guard grepping raw source passes against the words explaining
  # the bug rather than the code (the Obsidian/§319 lesson).
  # A here-string, NOT a pipe into `grep -q`: under `pipefail` a matching
  # `grep -q` exits the moment it matches, `sed` dies on SIGPIPE, and the
  # PIPELINE reports failure — so a guard reads as broken exactly when it
  # succeeds. It is size-dependent, which is what makes it vicious: the small
  # files raced through before grep quit and passed, and only Composer.swift
  # (3,300 lines) was slow enough to lose. Caught on this harness's first run.
  local body; body="$(sed 's|//.*||' "$file")"
  if grep -qE "$pat" <<< "$body"; then print "  ✓ $what"
  else print "  ✗ $what"; return 1; fi
}

# The tiles are worthless if the store still throws the readings away.
guard_has "KeptAskStore holds currentDeltas" "$STORE" 'currentDeltas\[kind\] *= *result\.delta|deltas\[kind\] *= *result\.delta' || rc=1
# The evidence pair is worthless if the store still keeps one pick.
guard_has "HomeInsightStore keeps every pick" "$INSIGHT" 'pickedThingIDs *=' || rc=1
# The board and the day card must never both show.
guard_has "day card yields to the board" "$COMPOSER" 'dayLede\.isEmpty && composition\.isEmpty' || rc=1
# A kept ask answered by a tile must not also wear a pill.
guard_has "a tile suppresses its pill" "$COMPOSER" 'onBoard\.contains' || rc=1
# The board must never outlive rest — an answer in flight owns the surface.
guard_has "the board is rest-only" "$COMPOSER" 'restChrome\(keepBrief: false\) && !composition\.isEmpty' || rc=1
# The entrance must honour Reduce Motion (design-motion-audit's first check).
guard_has "the board entrance honours Reduce Motion" "$BOARD" 'reduceMotion \? nil' || rc=1
# The kicker must not claim a model looked when none did.
guard_has "the kicker tracks who looked" "$BOARD" 'notice\.deterministic \?' || rc=1

print ""
if [[ $rc -ne 0 ]]; then print "✗ agent-open self-test FAILED"; exit 1; fi
print "✓ agent-open self-test passed"
