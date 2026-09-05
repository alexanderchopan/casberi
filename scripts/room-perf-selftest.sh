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
#   C. THE AGENT'S RISE MORPHS A SHAPE, NEVER THE CONTENT (2026-08-22,
#      prd §445). `matchedGeometryEffect` matches SIZE. Paired with the
#      composer's content container it proposed the agent bar's capsule to the
#      whole risen surface, so every frame of the rise laid the brief's entire
#      document out at an interpolating size on the main actor — a full layout
#      pass per frame, growing with the brief.
#
#      The condition: `MorphMatch` rides `RootShell`'s ground SHAPE (a fill,
#      which has no layout children) and never returns to `Composer`'s
#      container. Put it back and the build is green, the animation still
#      looks like the approved morph, and the open is janky again — which is
#      exactly how it survived four prior perf passes.
#
# All three failures are INVISIBLE to everything else: the build is green,
# every static audit is green, the screen renders, and the number — or the
# frame rate — is simply wrong.
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
COMPOSER="${ROOM_PERF_COMPOSER:-Casberi/Casberi/Shell/Composer.swift}"
ROOT="${ROOM_PERF_ROOT:-Casberi/Casberi/Shell/RootShell.swift}"

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

# The same, over the WHOLE file at once. Section C's invariant is an ORDER of
# modifiers spread across several lines — that the matched view is a fill and
# not the surface above it — and a line-wise grep can only ever prove the words
# appear somewhere in the file, which the broken version satisfies just as well
# as the fixed one.
checkm() {  # checkm <description> <file> <perl-regex> <expect: yes|no>
  local desc="$1" file="$2" pattern="$3" expect="$4"
  local body
  body="$(strip_comments "$file")"
  if perl -0777 -ne "exit(/$pattern/s ? 0 : 1)" "$body"; then
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
#     AMENDED 2026-09-04 (prd §600): the read moved to `fullRoomRows`, so the
#     `.live` filter moved with it — onto the fallback it is handed and onto its
#     own return. The invariant is unchanged and now has two sites, both pinned;
#     a guarded function that moves takes its guard with it.
check "recomputeHeads filters .live at the read" \
      "$FEED" 'let onScreen = visible\.live' yes
check "fullRoomRows filters .live before it hands rows back" \
      "$FEED" 'let full = liveVisible\(rawOverride: raw\)\.live' yes

# A6. ONE narrowing rule. The lane strip scopes the head as well as the rows
#     (2026-08-06); two spellings of that scope is how a head ends up
#     describing a marketplace the reader just filtered away.
check "shapedSections narrows through roomScoped" \
      "$FEED" 'let visible = roomScoped\(allVisible\)' yes
#     Amended with A5 (prd §600): the argument is now the whole room rather than
#     the bounded list, and the rule this pins — that both readers narrow through
#     ONE function — is untouched.
check "recomputeHeads narrows through the same roomScoped" \
      "$FEED" 'let rows = roomScoped\(base\)' yes
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

# B1b. THE SAME DECLINE ON BOTH `@Query`-STALENESS SAFETY NETS (2026-09-01).
#      Those nets compare a real SQL COUNT against `things.count` and run a
#      recovery fetch on a mismatch — and while the swipe's bound is set the
#      mismatch is GUARANTEED, because we set it: 150 rows against a room of
#      thousands. Without this guard every room swipe runs a full, main-actor,
#      fully-hydrated fetch inside the slide's own frames, which is the largest
#      single cost in this file and goes red nowhere. Anchored to the line each
#      guard precedes, since all three now share one spelling.
net_all="$(perl -0777 -ne 'print $1 if /\.task\(id: safetyNetKey\) \{(.*?)\n        \}/s' "$FEED_STRIPPED")"
if print -r -- "$net_all" | grep -Eq 'guard rowBudget == nil else \{ return \}'; then
  ok "the All-room staleness net declines while rowBudget is set"
else
  fail "the All-room staleness net does NOT decline while rowBudget is set"
fi
if grep -Eq 'guard rowBudget == nil else \{ return \}\s*$' "$FEED_STRIPPED" \
   && perl -0777 -ne 'exit(/guard rowBudget == nil else \{ return \}\n            if things\.isEmpty/s ? 0 : 1)' "$FEED_STRIPPED"; then
  ok "the per-source staleness net declines while rowBudget is set"
else
  fail "the per-source staleness net does NOT decline while rowBudget is set"
fi
# Both nets must be keyed so the check RE-FIRES when the bound lifts. Keyed on
# `scenePhase` alone the guard above would not defer the net but DISABLE it for
# the life of the mount — and a room entered by swiping is most rooms.
check "the staleness nets re-fire when the bound lifts" \
      "$FEED" 'private var safetyNetKey' yes
check "safetyNetKey carries the budget" \
      "$FEED" 'rowBudget == nil \? "\|full" : "\|bounded"' yes

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
# AMENDED 2026-09-04 (prd §600), not loosened: the source room took a PERMANENT
# ceiling that day, so the transient budget is now the lower of the two rather
# than the only bound. The invariant is unchanged — the budget must still reach
# the descriptor — and the new spelling proves strictly more, since `min` also
# pins that the permanent ceiling cannot be lost by arming a swipe.
check "the source room honours rowBudget" \
      "$FEED" 'min\(Self\.sourceRoomFetchLimit, rowBudget \?\? \.max\)' yes
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

# The clock must cost nothing in a shipped build that was not asked to report.
#
# INVERTED 2026-09-04 (prd §600), the way C5's fade assertion was: this used to
# demand that every `NSLog` sit under `#if DEBUG`, and that compile-time gate is
# exactly what made the one instrument built for the one reported symptom unable
# to say anything about Release on a phone — the configuration this project has
# never measured. The rule it was protecting ("a shipped build is silent") is
# unchanged; what changed is that the gate is now a runtime flag nobody passes,
# which is `LaunchClock.reports`' and `SweepClock.isOn`'s own shape.
#
# So the check is now that the gate EXISTS and is a flag, not that the logs are
# compiled out — and it still refuses a clock that prints unconditionally.
if [[ -f "$CLOCK" ]]; then
  CLOCK_STRIPPED="$(strip_comments "$CLOCK")"
  if grep -Eq 'UserDefaults\.standard\.bool\(forKey: "swipeTimer"\)' "$CLOCK_STRIPPED"; then
    ok "SwipeClock reports in Release only under -swipeTimer"
  else
    fail "SwipeClock has no release gate (it either cannot report on a phone, or always does)"
  fi
  # `step` is the only entry point that starts a trace, so gating it gates every
  # `mark` below it — which is why `mark` may guard on `t0` alone. Without this
  # the flag exists and governs nothing.
  step_body="$(perl -0777 -ne 'print $1 if /static func step\(to source: String\) \{(.*?)\n    \}/s' "$CLOCK_STRIPPED")"
  if print -r -- "$step_body" | grep -Eq 'guard isOn else \{ return \}'; then
    ok "SwipeClock.step is gated on isOn"
  else
    fail "SwipeClock.step does not consult its own gate"
  fi
else
  fail "SwipeClock.swift is missing"
fi

# ------------------------------------- D: the permanent bound (prd §600)
#
# The 2026-08-14 ruling refused a `fetchLimit` on a source room because
# `sourceHead` composed from `visible` — so a bound made "your loudest year"
# describe the newest N posts, the §83 fake status. §600 takes the bound and
# keeps the ruling by SEPARATING THE TWO READERS: the list is bounded, and the
# head reads the whole room through `fullRoomRows`.
#
# Every check below pins one half of that separation. Break any of them and the
# build is green, the room renders, and a reading about years of history is
# quietly computed over six hundred rows.

# D1. The list is bounded.
check "the source room's query carries the permanent ceiling" \
      "$FEED" 'd\.fetchLimit = min\(Self\.sourceRoomFetchLimit, rowBudget \?\? \.max\)' yes

# D2. The head does NOT read that bounded list. This is the §83 condition, and
#     it is the whole reason the bound is allowed to exist.
heads_body="$(perl -0777 -ne 'print $1 if /private func recomputeHeads\(\) \{(.*?)\n    \}/s' "$FEED_STRIPPED")"
if print -r -- "$heads_body" | grep -Eq 'fullRoomRows\(fallback:'; then
  ok "recomputeHeads reads the whole room, not the bounded list"
else
  fail "recomputeHeads composes from the bounded query (§83: a head over a truncated room)"
fi
# …and nothing in it may take `visible` as the head's base any more. Negative,
# so read from the stripped copy — this file documents the change by naming the
# expression it no longer uses.
if print -r -- "$heads_body" | grep -Eq 'roomScoped\(visible'; then
  fail "recomputeHeads still scopes `visible` directly (the bound would truncate the head)"
else
  ok "recomputeHeads takes its base from fullRoomRows alone"
fi

# D3. The full read is genuinely full. A `fetchLimit` here re-introduces §83
#     through the back door; `propertiesToFetch` re-introduces the iOS 18.6
#     empty-room defect on a PREDICATED fetch, which is the worst bug this app
#     has shipped recently.
full_body="$(perl -0777 -ne 'print $1 if /private func fullRoomRows\(fallback: \[Thing\]\) -> \[Thing\] \{(.*?)\n    \}/s' "$FEED_STRIPPED")"
if [[ -z "$full_body" ]]; then
  fail "fullRoomRows is missing (the head has nothing to read the whole room from)"
else
  if print -r -- "$full_body" | grep -Eq 'fetchLimit'; then
    fail "fullRoomRows bounds its own fetch (§83: the head sees a truncated room again)"
  else
    ok "fullRoomRows fetches unbounded"
  fi
  if print -r -- "$full_body" | grep -Eq 'propertiesToFetch'; then
    fail "fullRoomRows projects columns on a predicated fetch (the iOS 18.6 empty-room defect)"
  else
    ok "fullRoomRows carries no propertiesToFetch"
  fi
  # D4. It can never make the head WORSE than before §600. If this device is one
  #     where `$0.source == source` disagrees with a plain fetch, the read comes
  #     back short — and without this the room's every reading is deleted.
  if print -r -- "$full_body" | grep -Eq 'full\.count >= fallback\.count \? full : fallback'; then
    ok "fullRoomRows never returns fewer rows than the list already has"
  else
    fail "fullRoomRows can return fewer rows than the list (a broken predicate would erase every reading)"
  fi
fi

# D5. A reachable bound must never render as the end of the corpus.
check "reachedFetchCeiling covers source rooms" \
      "$FEED" 'windowRowBudget >= Self\.sourceRoomFetchLimit' yes

# D6. The per-source staleness net compares against the SAME ceiling the query
#     carries. Uncapped, every bulk-import room is a permanent mismatch and runs
#     the recovery fetch on every foreground — the exact cost §600 removed,
#     arriving through the safety net instead of through the list, invisibly.
check "the per-source staleness net caps its comparison at the room's ceiling" \
      "$FEED" 'min\(rawCount, Self\.sourceRoomFetchLimit\) != things\.count' yes

# D7. The swipe suppression must not swallow Reduce Motion. `instant` and
#     `reduceMotion` both mean "arrive at rest", and replacing one with the
#     other would restore the §299 accessibility gap this modifier already had
#     once.
entrance_body="$(perl -0777 -ne 'print $1 if /private func reveal\(\) \{(.*?)\n    \}/s' "$FEED_STRIPPED")"
if print -r -- "$entrance_body" | grep -Eq 'guard !reduceMotion, !instant else'; then
  ok "RowEntrance honours Reduce Motion and the swipe suppression independently"
else
  fail "RowEntrance's entrance guard no longer names both reduceMotion and instant"
fi
# One construction site, so the flag cannot drift across twenty call sites.
check "every row entrance is built through one helper" \
      "$FEED" 'private func rowEntrance\(_ index: Int\) -> RowEntrance' yes
check "the helper suppresses the entrance during a swipe" \
      "$FEED" 'instant: rowBudget != nil' yes

# D8. Arithmetic, not taste: the ceiling must be many windows past anything a
#     person opens in one visit, or the footer people meet is the bound.
src_limit="$(grep -Eo 'sourceRoomFetchLimit = [0-9]+' "$FEED" | grep -Eo '[0-9]+')"
win="$(grep -Eo 'windowRowTarget = [0-9]+' "$FEED" | grep -Eo '[0-9]+')"
if [[ -n "$src_limit" && -n "$win" ]] && (( src_limit >= win * 10 )); then
  ok "sourceRoomFetchLimit ($src_limit) is ≥ 10 windows of $win"
else
  fail "sourceRoomFetchLimit ($src_limit) is too small against windowRowTarget ($win)"
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
  cp "$COMPOSER" "$dir/Composer.swift"
  cp "$ROOT"     "$dir/RootShell.swift"
  case "$which" in
    feed)     perl -0777 -i -pe "$expr" "$dir/FeedScreen.swift" ;;
    main)     perl -0777 -i -pe "$expr" "$dir/MainSurface.swift" ;;
    composer) perl -0777 -i -pe "$expr" "$dir/Composer.swift" ;;
    root)     perl -0777 -i -pe "$expr" "$dir/RootShell.swift" ;;
    clock)    perl -0777 -i -pe "$expr" "$dir/SwipeClock.swift" ;;
    *)    print -r -- "  ✗ unknown mutation target: $which"; rm -rf "$dir"; return 1 ;;
  esac
  local survived=0
  ROOM_PERF_FEED="$dir/FeedScreen.swift" \
  ROOM_PERF_MAIN="$dir/MainSurface.swift" \
  ROOM_PERF_SIGNAL="$dir/CorpusSignal.swift" \
  ROOM_PERF_CLOCK="$dir/SwipeClock.swift" \
  ROOM_PERF_COMPOSER="$dir/Composer.swift" \
  ROOM_PERF_ROOT="$dir/RootShell.swift" \
    "$SELF" --checks-only >/dev/null 2>&1 && survived=1
  rm -rf "$dir"
  if (( survived )); then
    print -r -- "  ✗ MUTATION SURVIVED: $desc"
    return 1
  fi
  print -r -- "  ✓ caught: $desc"
  return 0
}

# ------------------------------------------------------------- C: the rise

# C1. The morph is OFF the composer's content container. This is the whole
#     removal: `matchedGeometryEffect` proposes the paired frame, so a content
#     container wearing it is re-laid-out at every frame of the rise.
#
#     Negative, and therefore read from the comment-stripped copy — `Composer`
#     documents this rule by naming the exact modifier it must no longer carry.
check "the composer's container carries no MorphMatch" \
      "$COMPOSER" '\.modifier\(MorphMatch' no

# C2/C3. It rides the ground SHAPE instead, in `RootShell`'s agent layer. C3 is
#     the one that matters: a fill has no layout children, so the same
#     interpolation costs nothing to run. Checked as an ORDER, not as a set of
#     words, or moving the modifier back onto `agentSurface` passes.
check "RootShell's agent layer carries the morph" \
      "$ROOT" 'MorphMatch\(ns: agentMorph\)' yes
checkm "the matched view is a shape fill, not the risen surface" \
       "$ROOT" 'RoundedRectangle\(.*?\)\s*\.fill\(DS\.page\)\s*\.ignoresSafeArea\(\)\s*\.modifier\(MorphMatch\(ns: agentMorph\)\)' yes

# C4. The flat ground stays BENEATH it. The matched shape carries a corner
#     radius, and a rounded rectangle sized to a square-cornered window (iPad,
#     Mac) shows the feed through its four corners once the rise settles. A
#     phone hides them behind the display's own mask; the other two surfaces
#     this app ships on do not.
#
#     AMENDED 2026-09-02 (prd §577b), not loosened. §577b made this ground the
#     ask surface's TINT while a keyed job runs — `(chrome.askOnTint ? DS.tint
#     : DS.page)` — because a `.background` inside the composer is laid out
#     within the agent layer's safe-area insets and could never reach the
#     status bar or the home indicator. The ruling C4 exists for is about the
#     ground being FLAT, FULL-BLEED and UNDERNEATH; which colour it is was
#     never the point. So the pattern accepts either the bare token or a
#     ternary that resolves to one, and still demands `.ignoresSafeArea()`
#     immediately before the `RoundedRectangle` — which is the whole of what
#     the corners depend on.
checkm "a flat ground still sits under the matched shape" \
       "$ROOT" '\(chrome\.askOnTint \? DS\.tint : DS\.page\)\.ignoresSafeArea\(\)\s*\.animation\([^)]*\)\s*RoundedRectangle' yes

# C5. THERE IS NO BOTTOM FADE, and this check is INVERTED (prd §586a).
#
#     It used to demand one: §445 gave the brief's document a gradient into the
#     chrome so the edge was a dissolve rather than a hard clip. §581b deleted
#     it FROM A DEVICE REPORT — the fade painted `DS.page` over the last 40pt
#     of the paper, and the last 40pt is where the newest sentence sits, so the
#     line you most want to read was the one being dimmed. A fade earns its
#     place where content runs under FLOATING chrome; this foot is opaque and
#     adjacent, so there is nothing to run under.
#
#     The guard was not updated with the ruling, so it has been RED on the tree
#     since 2026-09-03 — asserting a treatment a later ruling deliberately
#     removed. Inverted rather than deleted, exactly as §583's tear assertions
#     were: §445 is still in the ledger arguing for the gradient, and a fade is
#     easy to re-add by someone reading that entry and not this one.
checkm "the bottom fade stays gone (prd §581b)" \
       "$COMPOSER" 'LinearGradient\(colors: \[DS\.page\.opacity\(0\), DS\.page\]' no

if [[ "${1:-}" == "--checks-only" ]]; then
  exit $(( fails > 0 ))
fi

if (( fails > 0 )); then
  print -r -- "room-perf-selftest: FAILED ($fails)"
  exit 1
fi

print -r -- "mutations"
mfails=0
# ANCHORED to the line it follows, and that anchoring is the point (2026-09-01).
# `perl -0777` with no /g removes the FIRST match in the whole file, and this
# guard is no longer unique: the two `@Query`-staleness safety nets took the
# same one-line guard above, for the same swipe budget. Unanchored, this
# mutation deleted a SAFETY NET's guard, left the head task's intact, and
# survived — a mutation that no longer breaks the rule it names, which is this
# repo's own standing lesson about a fixture that passes for the wrong reason.
mutate "the head task stops declining on a bound room (§83)"  feed \
  's/guard rowBudget == nil else \{ return \}\n            recomputeHeads\(\)/recomputeHeads()/' || mfails=$((mfails + 1))
# The same guard on each safety net, pinned separately — each is the whole
# reason a room swipe no longer runs a full main-actor fetch mid-animation, and
# each is one line that reads as redundant.
mutate "the All-room staleness net stops declining on a bound room"  feed \
  's/guard rowBudget == nil else \{ return \}\n            let cappedRaw/let cappedRaw/' || mfails=$((mfails + 1))
mutate "the per-source staleness net stops declining on a bound room"  feed \
  's/guard rowBudget == nil else \{ return \}\n            if things\.isEmpty/if things.isEmpty/' || mfails=$((mfails + 1))
mutate "RoomHeads gains a Thing"  feed 's/(private struct RoomHeads \{)/$1\n        let row: Thing?/' || mfails=$((mfails + 1))
mutate "the memo is keyed by source alone (a scope change flashes the wrong head)"  feed \
  's/headMemo\[headIdentity\]/headMemo[source]/g' || mfails=$((mfails + 1))
mutate "the head is recomputed inline again"  feed 's/\? heads\?\.topicMap : nil/? FeedInsight.topicMap(source: source, things: visible) : nil/' \
  || mfails=$((mfails + 1))
# RETARGETED 2026-09-04 (prd §600): the head's base is `fullRoomRows(...)` now,
# and the `.live` filter it must keep moved with it — onto `let onScreen =
# visible.live` and onto `fullRoomRows`' own return. Left pointing at the old
# expression this matched nothing, which is a mutation that cannot fail and
# therefore proves nothing (the same no-op-survivor shape C5 announced).
mutate "recomputeHeads drops its .live filter"  feed 's/let onScreen = visible\.live/let onScreen = visible/' || mfails=$((mfails + 1))
mutate "headIdentity stops covering the wallet scope"  feed 's/selectedWallet \?\? "", //' || mfails=$((mfails + 1))
# The bug this pass wrote and caught by re-reading its own diff: without the
# budget in the key, the task never re-fires when the budget lifts and the head
# is not deferred but DROPPED.
mutate "headKey stops covering the row budget (deferred becomes dropped)"  feed \
  's/\+ \(rowBudget == nil \? "\|full" : "\|bounded"\)//' || mfails=$((mfails + 1))
mutate "headIdentity counts through the @Query getter"  feed 's/String\(revision\.count\)/String(things.count)/' || mfails=$((mfails + 1))
mutate "rowBudget leaves FeedScreen: Equatable"  feed 's/\n            && a\.rowBudget == b\.rowBudget//' || mfails=$((mfails + 1))
mutate "the source room stops honouring rowBudget"  feed \
  's/d\.fetchLimit = min\(Self\.sourceRoomFetchLimit, rowBudget \?\? \.max\)/d.fetchLimit = Self.sourceRoomFetchLimit/' \
  || mfails=$((mfails + 1))
mutate "the budget is never released"  main 's/        swipeRowBudget = nil\n//' || mfails=$((mfails + 1))

# Section D (prd §600). Each of these builds green and renders a room that
# looks entirely correct while making a false claim about it, or pays back the
# cost the bound was added to remove.
mutate "the head reads the bounded list again (§83)"  feed \
  's/let base = fullRoomRows\(fallback: onScreen\)/let base = onScreen/' || mfails=$((mfails + 1))
mutate "the whole-room read is itself bounded (§83 through the back door)"  feed \
  's/        let d = FetchDescriptor<Thing>\(\n            predicate/        var d = FetchDescriptor<Thing>(\n            predicate/; s/(\n        guard let raw = try\? modelContext\.fetch\(d\) else \{ return fallback \})/\n        d.fetchLimit = Self.sourceRoomFetchLimit$1/' \
  || mfails=$((mfails + 1))
mutate "the whole-room read loses its never-fewer-rows guard"  feed \
  's/return full\.count >= fallback\.count \? full : fallback/return full/' || mfails=$((mfails + 1))
mutate "the source room's permanent ceiling is dropped"  feed \
  's/d\.fetchLimit = min\(Self\.sourceRoomFetchLimit, rowBudget \?\? \.max\)/if let rowBudget { d.fetchLimit = rowBudget }/' \
  || mfails=$((mfails + 1))
mutate "the ceiling footer goes back to All-only (the bound reads as the end)"  feed \
  's/return windowRowBudget >= Self\.sourceRoomFetchLimit/return false/' || mfails=$((mfails + 1))
mutate "the per-source net compares against an uncapped count"  feed \
  's/min\(rawCount, Self\.sourceRoomFetchLimit\) != things\.count/rawCount != things.count/' \
  || mfails=$((mfails + 1))
mutate "the swipe suppression swallows Reduce Motion (§299)"  feed \
  's/guard !reduceMotion, !instant else/guard !instant else/' || mfails=$((mfails + 1))
mutate "the row entrance stops being suppressed during a swipe"  feed \
  's/instant: rowBudget != nil/instant: false/' || mfails=$((mfails + 1))
mutate "SwipeClock loses its release gate (the phone can never be measured)"  clock \
  's/UserDefaults\.standard\.bool\(forKey: "swipeTimer"\)/true/' || mfails=$((mfails + 1))
mutate "SwipeClock.step stops consulting its gate"  clock \
  's/        guard isOn else \{ return \}\n        t0 = \.now/        t0 = .now/' || mfails=$((mfails + 1))

# Section C. Each of these builds green, renders correctly, and re-introduces
# a defect a person feels rather than sees.
mutate "the morph goes back on the composer's content"  composer \
  's/(\.scaleEffect\(embedded \? 1 : \(isOpen \? 1 : 0\.3\), anchor: \.bottomTrailing\))/$1\n        .modifier(MorphMatch(ns: embedded ? glassNamespace : nil))/' \
  || mfails=$((mfails + 1))
mutate "the morph moves off the shape onto the risen surface"  root \
  's/\.modifier\(MorphMatch\(ns: agentMorph\)\)\n                    agentSurface/\n                    agentSurface\n                        .modifier(MorphMatch(ns: agentMorph))/' \
  || mfails=$((mfails + 1))
mutate "the flat ground under the matched shape is dropped (corners leak on iPad and Mac)"  root \
  's/                    \(chrome\.askOnTint \? DS\.tint : DS\.page\)\.ignoresSafeArea\(\)\n\s*\.animation\(DS\.Motion\.standard, value: chrome\.askOnTint\)\n(?=\s*\/\/ THE MORPH RIDES)//' \
  || mfails=$((mfails + 1))
# INVERTED with C5 (prd §586a): the old mutation DELETED the fade, and there is
# no longer one to delete — so it was a no-op that "survived" every run, which
# is how this pair announced that the ruling had moved out from under it. It
# now ADDS the gradient back and proves the check refuses it.
mutate "the bottom fade is re-added over the newest sentence"  composer \
  's/^import SwiftUI$/import SwiftUI\nlet reAdded = LinearGradient(colors: [DS.page.opacity(0), DS.page], startPoint: .top, endPoint: .bottom)/m' \
  || mfails=$((mfails + 1))

if (( mfails > 0 )); then
  print -r -- "room-perf-selftest: $mfails mutation(s) survived"
  exit 1
fi

print -r -- "room-perf-selftest: OK"
