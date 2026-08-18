#!/bin/zsh
# Casberi GitHub room self-test — the SHIPPED head behind the GitHub room
# (prd §401, 2026-08-18):
#
#   Casberi/Casberi/Model/GitHubRoom.swift
#     — Ask.weight / Ask.from  (which of three asks outranks which)
#     — compose                (ranking, the total sort, the cap)
#     — headline / subline     (an item leads; a count never does)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy.
#
# WHY A HARNESS. Every failure here renders as a perfectly good-looking card:
#
#   • a requested review — which BLOCKS another person's pull request — ranked
#     below a mention, so the card leads with the least urgent thing on it;
#   • the six FYI reasons (`author`, `comment`, `subscribed`, `manual`,
#     `state_change`, `ci_activity`) treated as asks, which turns the head into
#     a second copy of the feed with a ranking on top and buries the three
#     things actually waiting on you;
#   • the ask read back out of the TITLE rather than the tag — a parse that
#     works on every short row and fails on exactly the long ones, because
#     `IngestSupport.titleLine` clamps at 80 characters (the CursorRoom lesson,
#     written down here before it costs anything);
#   • a card that reshuffles between two opens over identical data;
#   • a COUNT as the headline, which §223 forbids and which reads as a chore
#     list rather than a thing to do.
#
# Pure, local, deterministic — no network, no simulator, no token. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/GitHubRoom.swift"
FEEDS="Casberi/Casberi/Model/GitHubFeeds.swift"
SOURCE="Casberi/Casberi/Model/GitHubRoomSource.swift"
SCREEN="Casberi/Casberi/Screens/FeedScreen.swift"
COMPOSITION="Casberi/Casberi/GenUI/HomeComposition.swift"
for f in "$ROOM" "$FEEDS" "$SOURCE" "$SCREEN" "$COMPOSITION"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# A temp DIRECTORY with fixed names inside — macOS `mktemp` only randomises
# TRAILING X's, so `file.XXXXXX.swift` does not randomise at all and two
# concurrent runs collide with "File exists" (paid for on the Radicle
# harness's first night, when a verify.sh pass and a hand-run overlapped).
TMP=$(mktemp -d /tmp/github-room-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

STRIPPED="$TMP/feeds.swift"
python3 - "$FEEDS" "$STRIPPED" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
out = []
for line in src.split("\n"):
    s = line.strip()
    if s.startswith("///") or s.startswith("//"):
        continue
    out.append(re.sub(r'\s//(?!/).*$', '', line))
open(sys.argv[2], "w").write("\n".join(out))
PY

# --- drift guards -----------------------------------------------------------
# THE MIRROR. `GitHubRoom.Ask`'s raw values ARE the strings
# `GitHubFeedFetch.notificationAsk` stamps. The two live in different files and
# cannot import each other — `GitHubFeeds.swift` reaches Thing, IngestSupport
# and the network, so no harness can compile it — so the only thing keeping
# them from drifting into disagreement is this check. A rename on one side
# alone makes `Ask.from` return nil for every row and the head silently
# disappears, with nothing anywhere reporting a problem.
for word in Review Assigned Mentioned; do
  grep -q "\"$word\"" "$STRIPPED" \
    || { echo "✗ GitHubFeeds no longer stamps the \"$word\" ask — GitHubRoom.Ask"; \
         echo "  still expects it, so every row of that kind vanishes from the head"; exit 1; }
  grep -q "= \"$word\"" "$ROOM" \
    || { echo "✗ GitHubRoom.Ask no longer carries \"$word\""; exit 1; }
done

# The six FYI reasons must stay UNTAGGED. If any becomes an ask, the head stops
# being "what needs you" and becomes the feed again.
python3 - "$STRIPPED" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'func notificationAsk.*?\n    \}', src, re.S)
if not m:
    sys.stderr.write("✗ notificationAsk is gone — nothing stamps the ask the head ranks on\n")
    sys.exit(1)
body = m.group(0)
for fyi in ["author", "comment", "subscribed", "manual", "state_change", "ci_activity"]:
    # Present as a case at all => it is being tagged as an ask.
    if re.search(r'case\s+"%s"' % fyi, body):
        sys.stderr.write(f'✗ "{fyi}" is being stamped as an ask — it means "this moved",\n'
                         f'  and tagging it makes the head a ranked copy of the feed\n')
        sys.exit(1)
if "default:                 nil" not in body and "default: nil" not in body.replace("  ", " "):
    sys.stderr.write("✗ notificationAsk no longer defaults to nil — an unknown reason\n"
                     "  would be stamped as an ask under whatever name it arrived with\n")
    sys.exit(1)
PY

# The tags must be RULED, or the themes treemap draws them as subjects.
for word in Review Assigned Mentioned; do
  grep -q "\"$word\"" "$COMPOSITION" \
    || { echo "✗ \"$word\" is not in HomeComposition.mechanicalTags — the themes"; \
         echo "  treemap would draw it as something you write about"; exit 1; }
done

# The head must be WIRED, and the heatmap must stand down for it. Two leads is
# not a richer room, it is a room with no lead.
grep -q 'GitHubRoomSource.compose' "$SCREEN" \
  || { echo "✗ the GitHub head is not in sourceHead — it would never draw"; exit 1; }
grep -q 'source == "GitHub", sourceHeadIsAbsent' "$SCREEN" \
  || { echo "✗ the contributions heatmap no longer stands down for the head —"; \
       echo "  the room would draw two leads"; exit 1; }

# The Source adapter must filter live at the boundary (corollary 4).
grep -q 'things.live.filter' "$SOURCE" \
  || { echo "✗ GitHubRoomSource no longer filters .live at the boundary — the"; \
       echo "  caller's array is a debounced snapshot and the sweep deletes rows"; exit 1; }

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

let now = Date()
func row(_ tags: [String], _ title: String, minsAgo: Double, _ ref: String)
    -> (tags: [String], title: String, lastMoved: Date, ref: String) {
    (tags: tags, title: title, lastMoved: now.addingTimeInterval(-minsAgo * 60), ref: ref)
}

// ── the ask ────────────────────────────────────────────────────────────────
print("Ask — three asks, ranked by whose work is blocked")
do {
    check("a review outranks an assignment",
          GitHubRoom.Ask.review.weight > GitHubRoom.Ask.assigned.weight)
    check("an assignment outranks a mention",
          GitHubRoom.Ask.assigned.weight > GitHubRoom.Ask.mentioned.weight)
    check("every ask has a distinct weight",
          Set(GitHubRoom.Ask.allCases.map(\.weight)).count == GitHubRoom.Ask.allCases.count)
    check("there are exactly three", GitHubRoom.Ask.allCases.count == 3)
}
do {
    check("the ask is read off the tags", GitHubRoom.Ask.from(tags: ["Notifications", "Review"]) == .review)
    check("a feed tag alone is no ask", GitHubRoom.Ask.from(tags: ["Notifications"]) == nil)
    check("no tags is no ask", GitHubRoom.Ask.from(tags: []) == nil)
    check("an unrelated tag is no ask", GitHubRoom.Ask.from(tags: ["Stars", "Releases"]) == nil)
    // Case matters: the tag is data written by one table and read by another.
    check("the match is exact, not case-folded", GitHubRoom.Ask.from(tags: ["review"]) == nil)
}

// ── compose ────────────────────────────────────────────────────────────────
print("compose — the blocking thing leads")
do {
    let room = GitHubRoom.compose(rows: [
        row(["Notifications", "Mentioned"], "someone said your name", minsAgo: 1, "a"),
        row(["Notifications", "Review"], "please review this", minsAgo: 500, "b"),
        row(["Notifications", "Assigned"], "this is yours now", minsAgo: 100, "c"),
    ])
    check("the card composes", room != nil)
    // THE ONE THAT MATTERS. The mention is the most RECENT; the review blocks
    // somebody else. Newest-first would lead with the mention.
    check("the REVIEW leads, though it is the oldest", room?.items.first?.ask == .review)
    check("the assignment is second", room?.items[1].ask == .assigned)
    check("the mention is last", room?.items.last?.ask == .mentioned)
    check("the headline names the strongest ask",
          room?.headline == GitHubRoom.Ask.review.line)
    check("the subline counts, since the asks differ",
          room?.subline?.contains("3") == true)
}
do {
    // Only FYI rows: nothing is waiting, so there is no card. This is the
    // healthy common case, not a failure.
    check("rows with no ask compose nothing",
          GitHubRoom.compose(rows: [
            row(["Notifications"], "ci went green", minsAgo: 1, "a"),
            row(["Stars"], "you starred a repo", minsAgo: 2, "b"),
          ]) == nil)
    check("no rows at all composes nothing", GitHubRoom.compose(rows: []) == nil)
}
do {
    // Same ask several times: the headline pluralises rather than naming one.
    let room = GitHubRoom.compose(rows: [
        row(["Review"], "one", minsAgo: 10, "a"),
        row(["Review"], "two", minsAgo: 20, "b"),
    ])
    check("two of one ask reads as a count of that ask",
          room?.headline.contains("2") == true)
    // …and the subline would be repeating it, so it stands down.
    check("the subline stands down when there is only one kind", room?.subline == nil)
}
do {
    // Within one ask, most-recently-moved first.
    let room = GitHubRoom.compose(rows: [
        row(["Review"], "older", minsAgo: 900, "a"),
        row(["Review"], "newer", minsAgo: 5, "b"),
    ])
    check("within an ask, the newest movement leads", room?.items.first?.ref == "b")
}
do {
    // A card that reshuffles between two opens over identical data reads as
    // broken (the ASCRoom rule). Everything tied so only the tiebreak orders.
    let t = now.addingTimeInterval(-60)
    let tied = [(tags: ["Review"], title: "x", lastMoved: t, ref: "zz"),
                (tags: ["Review"], title: "x", lastMoved: t, ref: "aa")]
    let a = GitHubRoom.compose(rows: tied)
    let b = GitHubRoom.compose(rows: tied.reversed())
    check("the sort is TOTAL — identical data orders identically",
          a?.items.map(\.ref) == b?.items.map(\.ref))
    check("…and the tiebreak is the ref", a?.items.map(\.ref) == ["aa", "zz"])
}
do {
    let many = (0..<12).map { row(["Review"], "r\($0)", minsAgo: Double($0), "r\($0)") }
    let room = GitHubRoom.compose(rows: many)
    check("the card is capped", room?.items.count == GitHubRoom.cap)
    check("…keeping the newest-moved", room?.items.first?.ref == "r0")
}
do {
    // A row with an ask but no title has nothing to draw and nothing to tap
    // toward. COUNTED rather than silently dropped — a head that quietly loses
    // rows is the failure this project keeps re-learning.
    let room = GitHubRoom.compose(rows: [
        row(["Review"], "   ", minsAgo: 1, "a"),
        row(["Review"], "real", minsAgo: 2, "b"),
    ])
    check("a titleless row is not drawn", room?.items.count == 1)
    check("…and is counted", room?.unplaced == 1)
    check("an all-titleless card composes nothing",
          GitHubRoom.compose(rows: [row(["Review"], " ", minsAgo: 1, "a")]) == nil)
}
do {
    // §223: a tally is not a thing. The headline is always an ASK, never "N
    // notifications".
    let room = GitHubRoom.compose(rows: [row(["Mentioned"], "hi", minsAgo: 1, "a")])
    check("a single ask's headline is the ask itself, not a count",
          room?.headline == GitHubRoom.Ask.mentioned.line)
    check("…and carries no digit", room?.headline.contains(where: \.isNumber) == false)
}

print("")
if failures > 0 { print("✗ \(failures) assertion(s) failed"); exit(1) }
print("✓ all assertions passed")
SWIFT

if ! swiftc -O -o "$TMP/run" "$ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped GitHubRoom.swift:"
  sed -n '1,40p' "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
echo
echo "mutations — each must be caught"

mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ROOM" "$WORK/GitHubRoom.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/GitHubRoom.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/GitHubRoom.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/GitHubRoom.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE HEADLINE BUG: a mention outranking a review, so the card leads with
#    the least urgent thing on it.
mutate "a mention ranked above a review" \
  'case .review:    3' \
  'case .review:    0'

# 2. The ranking dropped entirely — newest-first, which is the list beneath.
mutate "the ask weighting removed" \
  'if $0.ask.weight != $1.ask.weight { return $0.ask.weight > $1.ask.weight }' \
  'if false { return false }'

# 3. The total sort broken, so the card reshuffles between opens.
mutate "the sort made non-total" \
  'return $0.ref < $1.ref' \
  'return false'

# 4. Within an ask, oldest-first — the stalest movement leads.
mutate "oldest movement leads within an ask" \
  'if $0.lastMoved != $1.lastMoved { return $0.lastMoved > $1.lastMoved }' \
  'if $0.lastMoved != $1.lastMoved { return $0.lastMoved < $1.lastMoved }'

# 5. The cap removed — the head becomes the feed.
mutate "the cap removed" \
  'Array(items.prefix(cap))' \
  'items'

# 6. A titleless row drawn rather than counted.
mutate "a titleless row drawn" \
  'guard !title.isEmpty else { unplaced += 1; continue }' \
  'if title.isEmpty { unplaced += 1 }'

# 7. The headline made a COUNT (§223 — a tally is not a thing).
mutate "the headline made a tally" \
  'guard let top = items.first else { return String(localized: "Nothing waiting") }' \
  'return "\(items.count) notifications"; guard let top = items.first else { return "" }'

# 8. Any tag accepted as an ask, so a feed tag ("Stars") ranks as a request.
mutate "any tag accepted as an ask" \
  'if let ask = Ask(rawValue: tag) { return ask }' \
  'if let ask = Ask(rawValue: tag) ?? Ask.mentioned as Ask? { return ask }'

echo
echo "✓ github-room self-test: assertions and mutations all passed"
