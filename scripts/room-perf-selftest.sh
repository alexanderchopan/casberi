#!/bin/zsh
# room-perf-selftest.sh — the 2026-08-21 perf pass's invariants, as checks.
#
# Two costs were removed from paths a person feels, and BOTH removals are
# correct only while a condition holds that no compiler and no existing audit
# can see. That is what this file is for.
#
#   A. THE ROOM HEAD IS MEMOISED (`FeedScreen.headMemo` / `heads` / the
#      `.task(id: headKey)`). The head chain used to be derived inline in
#      `shapedSections`, i.e. once per body evaluation over the room's whole
#      contents — and since §265 made a room change a REMOUNT, every swipe paid
#      it from zero inside the slide's own frames.
#
#      The condition: nothing in `RoomHeads` may hold a `Thing`. A cached model
#      reference outliving the mount is the SwiftData liveness class this repo
#      has six corollaries for, arriving by a seventh route none of them covers
#      — and it would render perfectly right up until the heal pass that deletes
#      under it.
#
#   B. THE SWIPE BOUNDS THE INCOMING QUERY (`FeedScreen.rowBudget` /
#      `MainSurface.swipeRowBudget`). A source room's query is deliberately
#      unbounded (the 2026-08-14 ruling: a head must see the room's full span,
#      so a permanent `fetchLimit` was written there and taken back OUT).
#
#      The condition: the head must never be computed while the bound is set.
#      Break it and the room draws "your loudest year" over the newest 150
#      posts — the §83 fake status the 2026-08-14 ruling refuses, reintroduced
#      by the very change that was careful not to.
#
# Both failures are INVISIBLE to everything else: the build is green, every
# static audit is green, the screen renders, and the number is simply wrong.
#
# Static text checks over the shipped source, plus a mutation pass proving each
# guard can actually fail — a check that cannot fail certifies nothing.
#
# Negative guards read a COMMENT-STRIPPED copy: all three files DOCUMENT these
# rules by naming exactly what they must not do, so a guard grepping raw source
# scores the prose explaining the rule as a violation of it. (The Obsidian /
# Cursor lesson; this is at least the sixth instance in this repo.)

set -euo pipefail
SELF="${0:A}"           # absolute BEFORE the cd, so the mutation pass can re-enter
cd "$(dirname "$SELF")/.."

# The mutation pass NEVER writes to the tracked tree — it copies the four files
# somewhere else, breaks the copy, and re-runs the checks against that. Proving
# a guard means holding a deliberately broken file for a moment, and this repo
# is a PUBLIC remote with a post-commit hook that pushes immediately; a
# concurrent session's `git add -A` landing in that moment publishes the
# mutation under someone else's commit message. Copies remove the window
# entirely rather than narrowing it.
FEED="${ROOM_PERF_FEED:-Casberi/Casberi/Screens/FeedScreen.swift}"
MAIN="${ROOM_PERF_MAIN:-Casberi/Casberi/Shell/MainSurface.swift}"
SIGNAL="${ROOM_PERF_SIGNAL:-Casberi/Casberi/Model/CorpusSignal.swift}"
CLOCK="${ROOM_PERF_CLOCK:-Casberi/Casberi/Shell/SwipeClock.swift}"

fails=0
ok()   { print -r -- "  ✓ $1" }
fail() { print -r -- "  ✗ $1"; fails=$((fails + 1)) }

# A comment-stripped copy of a file: block comments and line comments removed.
#
# `//` must be preceded by whitespace or a line start, which does two jobs at
# once — it leaves `https://` alone (the `:` before it is not whitespace), and it
# keeps the match inside ONE line. The first cut spelled that gap `\s*`, and
# because `\s` matches a newline it happily ran from a code character on one
# line to a `//` several lines below and deleted everything between: thirteen
# checks reported MISSING against source that was sitting right there. A
# stripper that eats code is a guard that fails for reasons unrelated to the
# rule it protects, which is the one failure mode worse than no guard at all.
#
# Written to a FILE rather than passed around as a shell string: `FeedScreen`
# is ~208KB stripped, and a value that size going through a variable and a pipe
# is a way to get an empty match with no error anywhere — which reads exactly
# like the rule being broken. Grepping a file has neither problem.
STRIP_DIR="$(mktemp -d)"
trap 'rm -rf "$STRIP_DIR"' EXIT

strip_comments() {
  local out="$STRIP_DIR/$(basename "$1").stripped"
  perl -0777 -pe 's{/\*.*?\*/}{}gs; s{(^|[ \t])//[^\n]*}{$1}gm' "$1" > "$out"
  print -r -- "$out"
}

check() {  # check <description> <file> <pattern> <expect: yes|no>
  local desc="$1" file="$2" pattern="$3" expect="$4"
  local body
  body="$(strip_comments "$file")"
  if grep -Eq -- "$pattern" "$body"; then
    [[ "$expect" == yes ]] && ok "$desc" || fail "$desc (found what must not be there)"
  else
    [[ "$expect" == no ]] && ok "$desc" || fail "$desc (missing)"
  fi
}

print -r -- "room-perf-selftest"

# ---------------------------------------------------------------- A: the memo

# A1. The cache exists and survives the mount. `@State` would be destroyed by
#     the very remount this exists to make cheap, so `static` is the invariant,
#     not a style choice.
check "headMemo is static (survives the room remount)" \
      "$FEED" 'static var headMemo' yes

# A2. NOTHING IN THE CACHE HOLDS A MODEL. The struct's own fields are the whole
#     surface here, so they are checked by name rather than by a blanket grep:
#     a new field is exactly what this guard is for.
FEED_STRIPPED="$(strip_comments "$FEED")"
MAIN_STRIPPED="$(strip_comments "$MAIN")"

head_fields="$(perl -0777 -ne 'print $1 if /private struct RoomHeads \{(.*?)\n    \}/s' "$FEED_STRIPPED")"
if [[ -z "$head_fields" ]]; then
  fail "RoomHeads not found (did it move or get renamed?)"
elif print -r -- "$head_fields" | grep -Eq '\bThing\b'; then
  fail "RoomHeads holds a Thing — a cached model reference outlives its mount"
else
  ok "RoomHeads holds no Thing"
fi

# A3. `liveStream` and `anniversary` stay COMPUTED, never cached — they are the
#     two head candidates that do hold a `Thing`, which is why the gates had to
#     stay in the body when everything else moved out.
check "liveStream still derived in the body" \
      "$FEED" 'let liveStream = visible\.first' yes
check "anniversary still derived in the body" \
      "$FEED" 'let anniversary: OnThisDay\.Echo\? = liveStream == nil' yes

# A4. The head is READ from the cache in `shapedSections`, not recomputed there.
#     This is the cost removal itself; without it the memo is dead weight and
#     every swipe pays exactly what it paid before, with a cache beside it
#     saying otherwise.
for field in topicMap leaderboard distribution mosaic; do
  check "shapedSections reads heads?.$field" \
        "$FEED" "heads\?\.$field" yes
  check "shapedSections no longer calls FeedInsight.$field inline" \
        "$FEED" "FeedInsight\.$field\(source: source, things: visible\)" no
done
check "shapedSections reads heads?.sourceHead" "$FEED" 'heads\?\.sourceHead' yes
check "shapedSections no longer calls sourceHead(visible) inline" \
      "$FEED" 'sourceHead\(visible\)' no

# A5. The recompute reads live models. `visible` is re-read INSIDE the task and
#     `.live`-filtered — liveness corollary 6, and the reason the audit's own
#     check 6 exists. A perf change that moves a fetch is always also a
#     liveness change.
check "recomputeHeads filters .live at the read" \
      "$FEED" 'roomScoped\(visible\.live\)' yes

# A6. ONE narrowing rule. The lane strip scopes the head as well as the rows
#     (2026-08-06); two spellings of that scope is how a head ends up
#     describing a marketplace the reader just filtered away.
check "shapedSections narrows through roomScoped" \
      "$FEED" 'let visible = roomScoped\(allVisible\)' yes
check "recomputeHeads narrows through the same roomScoped" \
      "$FEED" 'roomScoped\(visible\.live\)' yes
check "x402Scoped is not applied a second way in shapedSections" \
      "$FEED" 'shape == \.x402 \? x402Scoped\(allVisible\)' no

# A7. The key covers every scope the head describes. A head that survived a
#     scope change would be a card about rows no longer on screen.
head_key="$(perl -0777 -ne 'print $1 if /private var headIdentity: String \{(.*?)\n    \}/s' "$FEED_STRIPPED")"
for term in 'source' 'filter.tag' 'selectedWallet' 'chrome.personScope' 'x402Lane' \
            'chrome.refreshPulse' 'revision'; do
  if print -r -- "$head_key" | grep -qF -- "$term"; then
    ok "headIdentity covers $term"
  else
    fail "headIdentity does not cover $term"
  fi
done

# A8. The key's content term is a COUNT, never the query's own `.count`. That
#     property is the `@Query` getter and materialises every row it counts —
#     paying, in the key, the exact price the memo exists to avoid. This is the
#     trap `corpusRevision`'s own doc already records once.
# The MEMO key must NOT carry the budget (a room re-entered mid-swipe has to hit
# its cached head — the whole point of a cache that survives the remount), and
# the TASK key must (or the head is not deferred but dropped when the bound
# lifts). Two spellings, and collapsing them breaks one of them either way.
if print -r -- "$head_key" | grep -q 'rowBudget'; then
  fail "headIdentity carries rowBudget — a re-entry mid-swipe would miss its own cached head"
else
  ok "headIdentity excludes rowBudget (the memo still hits mid-swipe)"
fi
task_key="$(perl -0777 -ne 'print $1 if /private var headKey: String \{(.*?)\n    \}/s' "$FEED_STRIPPED")"
if print -r -- "$task_key" | grep -q 'rowBudget'; then
  ok "headKey carries rowBudget (the task re-fires when the bound lifts)"
else
  fail "headKey omits rowBudget — deferred silently becomes dropped"
fi
if grep -q 'headMemo\[headIdentity\]' "$FEED_STRIPPED"; then
  ok "the memo is keyed on headIdentity, not on source alone"
else
  fail "the memo is not keyed on headIdentity — a scope change would flash the previous scope's head"
fi
if print -r -- "$head_key" | grep -Eq 'things\.count'; then
  fail "headIdentity reads things.count — the @Query getter materialises to count"
else
  ok "headIdentity does not read things.count"
fi
check "the scoped revision is a fetchCount" \
      "$SIGNAL" 'fetchCount\(d\)' yes

# ------------------------------------------------------------- B: the budget

# B1. THE HEAD DECLINES WHILE THE BOUND IS SET. The single most load-bearing
#     line in the pass: without it the 2026-08-14 ruling is broken by the
#     change that was written specifically not to break it.
task_body="$(perl -0777 -ne 'print $1 if /\.task\(id: headKey\) \{(.*?)\n        \}/s' "$FEED_STRIPPED")"
if print -r -- "$task_body" | grep -Eq 'guard rowBudget == nil else \{ return \}'; then
  ok "the head task declines while rowBudget is set"
else
  fail "the head task does NOT decline while rowBudget is set (§83: a head over a truncated room)"
fi
# …and it must come BEFORE the computation, not merely appear in the file.
if print -r -- "$task_body" \
   | awk '/guard rowBudget == nil/{g=NR} /recomputeHeads\(\)/{c=NR} END{exit !(g && c && g < c)}'; then
  ok "the decline is above recomputeHeads()"
else
  fail "the rowBudget guard does not precede recomputeHeads()"
fi

# B2. The bound is TRANSIENT. A `rowBudget` that no one clears is the permanent
#     `fetchLimit` the 2026-08-14 ruling refused, wearing a new name.
check "MainSurface arms the budget on a room change" \
      "$MAIN" 'swipeRowBudget = Self\.swipeRowBudgetRows' yes
check "MainSurface releases it" \
      "$MAIN" 'swipeRowBudget = nil' yes
check "the release is wired to a task keyed on the source" \
      "$MAIN" '\.task\(id: filter\.source\) \{ await releaseSwipeBudget\(\) \}' yes

# B3. The budget is armed BEFORE the source changes, or the unbounded query is
#     built once and thrown away — the whole cost, paid and discarded.
if awk '/swipeRowBudget = Self\.swipeRowBudgetRows/{a=NR} /filter\.source = target/{s=NR} END{exit !(a && s && a < s)}' "$MAIN_STRIPPED"; then
  ok "the budget is armed before filter.source changes"
else
  fail "the budget is armed after the source change (the bound arrives too late to bound anything)"
fi

# B4. `rowBudget` is part of FeedScreen's Equatable. It changes by being
#     CLEARED, and `.equatable()` is what decides whether the parent's new value
#     reaches the child at all — so without this the room keeps its 150-row
#     query for the life of the mount and "Show older" stops at the bound with
#     nothing on screen able to say why.
eq_body="$(perl -0777 -ne 'print $1 if /extension FeedScreen: Equatable \{(.*?)\n\}/s' "$FEED_STRIPPED")"
if print -r -- "$eq_body" | grep -q 'rowBudget'; then
  ok "rowBudget is compared in FeedScreen: Equatable"
else
  fail "rowBudget is missing from FeedScreen: Equatable (the bound would never lift)"
fi

# B5. The bound applies to the rooms that can be enormous, and the All room's
#     own ceiling still wins when both are present.
check "the source room honours rowBudget" \
      "$FEED" 'if let rowBudget \{ d\.fetchLimit = rowBudget \}' yes
check "the All room takes the lower of its ceiling and the budget" \
      "$FEED" 'min\(Self\.allRoomFetchLimit, rowBudget \?\? \.max\)' yes

# B6. The budget is smaller than nothing a person can open inside a slide, and
#     comfortably above the feed's own first window. Arithmetic, not taste.
budget="$(grep -Eo 'swipeRowBudgetRows = [0-9]+' "$MAIN" | grep -Eo '[0-9]+')"
target="$(grep -Eo 'windowRowTarget = [0-9]+' "$FEED" | grep -Eo '[0-9]+')"
if [[ -n "$budget" && -n "$target" ]] && (( budget >= target * 4 )); then
  ok "swipeRowBudgetRows ($budget) is ≥ 4 windows of $target"
else
  fail "swipeRowBudgetRows ($budget) is too small against windowRowTarget ($target)"
fi

# ------------------------------------------------------------ the instrument

# The clock must cost nothing in a shipped build. An instrument that survives
# into release is a log line on every swipe, forever.
if [[ -f "$CLOCK" ]]; then
  if grep -q 'NSLog' "$(strip_comments "$CLOCK")" \
     && [[ "$(grep -c 'NSLog' "$(strip_comments "$CLOCK")")" -le "$(grep -c '#if DEBUG' "$(strip_comments "$CLOCK")")" ]]; then
    ok "SwipeClock logs only under #if DEBUG"
  else
    fail "SwipeClock has an NSLog outside #if DEBUG"
  fi
else
  fail "SwipeClock.swift is missing"
fi

# ---------------------------------------------------------------- mutations
#
# Each mutation is a real defect this file is here to catch. A guard that has
# never been shown to fail is a guard nobody should trust.

mutate() {  # mutate <description> <which: feed|main> <perl-expression>
  local desc="$1" which="$2" expr="$3"
  local dir; dir="$(mktemp -d)"
  cp "$FEED"   "$dir/FeedScreen.swift"
  cp "$MAIN"   "$dir/MainSurface.swift"
  cp "$SIGNAL" "$dir/CorpusSignal.swift"
  cp "$CLOCK"  "$dir/SwipeClock.swift"
  case "$which" in
    feed) perl -0777 -i -pe "$expr" "$dir/FeedScreen.swift" ;;
    main) perl -0777 -i -pe "$expr" "$dir/MainSurface.swift" ;;
    *)    print -r -- "  ✗ unknown mutation target: $which"; rm -rf "$dir"; return 1 ;;
  esac
  local survived=0
  ROOM_PERF_FEED="$dir/FeedScreen.swift" \
  ROOM_PERF_MAIN="$dir/MainSurface.swift" \
  ROOM_PERF_SIGNAL="$dir/CorpusSignal.swift" \
  ROOM_PERF_CLOCK="$dir/SwipeClock.swift" \
    "$SELF" --checks-only >/dev/null 2>&1 && survived=1
  rm -rf "$dir"
  if (( survived )); then
    print -r -- "  ✗ MUTATION SURVIVED: $desc"
    return 1
  fi
  print -r -- "  ✓ caught: $desc"
  return 0
}

if [[ "${1:-}" == "--checks-only" ]]; then
  exit $(( fails > 0 ))
fi

if (( fails > 0 )); then
  print -r -- "room-perf-selftest: FAILED ($fails)"
  exit 1
fi

print -r -- "mutations"
mfails=0
mutate "the head task stops declining on a bound room (§83)"  feed 's/guard rowBudget == nil else \{ return \}//' || mfails=$((mfails + 1))
mutate "RoomHeads gains a Thing"  feed 's/(private struct RoomHeads \{)/$1\n        let row: Thing?/' || mfails=$((mfails + 1))
mutate "the memo is keyed by source alone (a scope change flashes the wrong head)"  feed \
  's/headMemo\[headIdentity\]/headMemo[source]/g' || mfails=$((mfails + 1))
mutate "the head is recomputed inline again"  feed 's/\? heads\?\.topicMap : nil/? FeedInsight.topicMap(source: source, things: visible) : nil/' \
  || mfails=$((mfails + 1))
mutate "recomputeHeads drops its .live filter"  feed 's/roomScoped\(visible\.live\)/roomScoped(visible)/' || mfails=$((mfails + 1))
mutate "headIdentity stops covering the wallet scope"  feed 's/selectedWallet \?\? "", //' || mfails=$((mfails + 1))
# The bug this pass wrote and caught by re-reading its own diff: without the
# budget in the key, the task never re-fires when the budget lifts and the head
# is not deferred but DROPPED.
mutate "headKey stops covering the row budget (deferred becomes dropped)"  feed \
  's/\+ \(rowBudget == nil \? "\|full" : "\|bounded"\)//' || mfails=$((mfails + 1))
mutate "headIdentity counts through the @Query getter"  feed 's/String\(revision\.count\)/String(things.count)/' || mfails=$((mfails + 1))
mutate "rowBudget leaves FeedScreen: Equatable"  feed 's/\n            && a\.rowBudget == b\.rowBudget//' || mfails=$((mfails + 1))
mutate "the source room stops honouring rowBudget"  feed 's/if let rowBudget \{ d\.fetchLimit = rowBudget \}//' || mfails=$((mfails + 1))
mutate "the budget is never released"  main 's/        swipeRowBudget = nil\n//' || mfails=$((mfails + 1))

if (( mfails > 0 )); then
  print -r -- "room-perf-selftest: $mfails mutation(s) survived"
  exit 1
fi

print -r -- "room-perf-selftest: OK"
