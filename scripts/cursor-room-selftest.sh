#!/bin/zsh
# Casberi Cursor-room self-test — the SHIPPED pure judgement behind the Cursor
# feed-room head (prd §340, 2026-08-08):
#
#   Casberi/Casberi/Model/CursorRoom.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything that touches `Thing` lives in `CursorRoomSource.swift`, which no
# harness can compile and which contains no judgement to test.
#
# WHY A HARNESS AND NOT A LIVE PROBE. The bridge itself has never been measured
# against a live account — no Cursor key is stored on this host, and there is an
# open question the vendor's own docs and forum contradict each other on
# (whether an individual on a personal plan can mint a Cloud Agents key at all).
# So the live probe may be unavailable to this project indefinitely, and this
# card would otherwise ship with nothing proving it.
#
# Every failure mode here is a SILENT WRONG ANSWER that renders perfectly:
#
#   · a repository with a broken run ranked BELOW a busy clean one — the exact
#     inversion of the card's whole premise, and invisible because both cards
#     look equally plausible;
#   · a run whose repository could not be named quietly bucketed as "Unknown",
#     which then ranks beside real repositories and can lead the card;
#   · a CANCELLED run — a decision the person made themselves — counted as a
#     failure, so the card opens by alarming you about your own choice;
#   · the outcome read from a LOCALIZED title when an unlocalized tag was
#     available, so every past failure reads as a success the day the device
#     changes language (§340's own stated reason for landing the tag);
#   · a truncated title's second component named as a repository that does not
#     exist (`IngestSupport.titleLine` clamps at 80 characters);
#   · an order that is not total, so the card reshuffles between opens over
#     identical rows and reads as broken.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/CursorRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"   # prd §585 — the shared lede type these rooms now return
SOURCE="Casberi/Casberi/Model/CursorRoomSource.swift"
CARD="Casberi/Casberi/Screens/CursorRoomCard.swift"
BRIDGE="Casberi/Casberi/Model/CursorBridge.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
for f in "$ROOM" "$SOURCE" "$CARD" "$BRIDGE" "$BRIDGES" "$FEED" "$PROBES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. Both of these files DOCUMENT
# the things they must never do ("Stores no `Thing`", "never bucketed into an
# 'Unknown' repository"), so a guard grepping raw source fires against the prose
# explaining it — the Obsidian/Cursor lesson, earned on those harnesses' own
# first runs.
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)   # whole-line comments
src = re.sub(r'//.*$', '', src, flags=re.M)          # trailing comments
sys.stdout.write(src)
PY
}
strip_comments "$CARD" > "$TMP/card-bare.swift"
strip_comments "$ROOM" > "$TMP/room-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled file cannot prove about itself. A perfect `ordered`
# is worthless if the card draws its own order, and a perfect `outcome` is
# worthless if the bridge stops landing the tag it reads.

# THE MIRROR. `CursorRoom.Outcome`'s raw values ARE `CursorAgentStatus.facetTag`'s
# words. This file cannot import that enum — `CursorBridge.swift` reaches
# `Thing`, `IngestSupport` and `TokenVault`, so nothing there compiles in a
# harness — so the two are spelled separately and pinned here. A word changed on
# one side alone means every failure reads as a success, with nothing on screen
# to say so.
for pair in 'error:Failed' 'expired:Expired' 'cancelled:Cancelled'; do
  st="${pair%%:*}"; word="${pair##*:}"
  grep -qE "case \.$st:[[:space:]]+\"$word\"" "$BRIDGE" \
    || { echo "✗ CursorAgentStatus.facetTag no longer spells .$st as \"$word\" — CursorRoom.Outcome's raw values mirror it, and a drift makes every $st run read as a success"; exit 1; }
  grep -qE "case [a-z]+ *= *\"$word\"" "$ROOM" \
    || { echo "✗ CursorRoom.Outcome no longer carries \"$word\" — the tag the bridge lands would stop being recognised"; exit 1; }
done

grep -q 'thing.authorHandle = repo' "$BRIDGE" \
  || { echo "✗ the bridge no longer stamps the repository on authorHandle — the room would fall back to parsing clamped titles forever, silently excluding runs"; exit 1; }
grep -q 'joined(separator: " · ")' "$BRIDGE" \
  || { echo "✗ the title separator moved — CursorRoom.separator splits on \" · \" and would stop finding the lead clause and the repo"; exit 1; }
grep -q 'source: "Cursor"' "$BRIDGE" \
  || { echo "✗ the bridge no longer lands rows under source \"Cursor\""; exit 1; }
grep -qE 'case cursor +=[[:space:]]*"Cursor"' "$BRIDGES" \
  || { echo "✗ TokenBridge.cursor's raw value moved — CursorRoomSource.source reads it and would filter to nothing"; exit 1; }

grep -q 'things.live' "$SOURCE" \
  || { echo "✗ CursorRoomSource no longer filters live at the boundary (corollary 4)"; exit 1; }
grep -q 'compose(things: things, now: now)' "$SOURCE" \
  || { echo "✗ probeLines no longer calls the REAL compose — a probe that reimplements the card can disagree with it"; exit 1; }
grep -q 'CursorRoomSource.rowCap' "$CARD" \
  || { echo "✗ the card no longer honours the row cap — the note would count repositories that are drawn"; exit 1; }
grep -q 'CursorRoom.share(runs:' "$CARD" \
  || { echo "✗ the card no longer sizes its bars through the shipped share() — a NaN width draws as nothing"; exit 1; }
grep -q 'accessibilityReduceMotion' "$CARD" \
  || { echo "✗ the card's entrance no longer honours Reduce Motion (design-motion-audit check 1)"; exit 1; }
# Corollary 5: a card that stores a `Thing` must guard its own body, and this
# family's answer is never to store one at all.
grep -qE '(let|var) [A-Za-z]+ *: *Thing\b' "$TMP/card-bare.swift" \
  && { echo "✗ CursorRoomCard now stores a Thing — the room-head family holds value types only (corollary 5)"; exit 1; }
# The refusal that keeps every number on this card true: a run with no
# repository is COUNTED, never given a bucket.
grep -qE '"Unknown"|"unknown"' "$TMP/room-bare.swift" \
  && { echo "✗ CursorRoom now names an 'Unknown' repository — an unplaceable run must be excluded and counted, never bucketed"; exit 1; }

# SELF-ARMING WIRING GUARDS. The head is composed here and rendered by
# `FeedScreen`'s `sourceHead` chain; until that wiring lands there is nothing to
# guard, and a hard failure would just be noise. So: the moment either file
# mentions the room AT ALL, the exact anchors become required — which means the
# wiring can never be half-done silently, and the guard arms itself without
# anybody remembering to come back.
if grep -q 'CursorRoom' "$FEED"; then
  grep -q 'CursorRoomCard(room:' "$FEED" \
    || { echo "✗ FeedScreen names CursorRoom but never draws CursorRoomCard — the head would compose and render nothing"; exit 1; }
  grep -q 'CursorRoomSource.compose' "$FEED" \
    || { echo "✗ FeedScreen draws the Cursor head without composing it through CursorRoomSource"; exit 1; }
  echo "  ✓ wiring: FeedScreen renders the head"
else
  echo "  · wiring: FeedScreen has no Cursor head yet — guard is dormant and arms itself the moment it does"
fi
if grep -q 'CursorRoomSource' "$PROBES"; then
  grep -q 'CursorRoomSource.probeLines' "$PROBES" \
    || { echo "✗ ProbeHooks names CursorRoomSource but not probeLines — the probe would reimplement the card"; exit 1; }
  echo "  ✓ wiring: -cursorRoomProbe reports through probeLines"
else
  echo "  · wiring: ProbeHooks has no Cursor room probe yet — guard is dormant and arms itself the moment it does"
fi

# --- the harness ------------------------------------------------------------

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
var checks = 0
func check(_ name: String, _ ok: Bool) {
    checks += 1
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let cal = Calendar.current
let t0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: t0)! }

/// A landed row, the way the source builds one.
func sight(_ title: String, tags: [String] = ["Agent run"], repo: String? = nil,
           at days: Int = 0) -> CursorRoom.Sighting {
    CursorRoom.Sighting(title: title, tags: tags, repo: repo, at: day(days))
}
/// A modern row: repo stamped on authorHandle, outcome carried as a tag.
func run(_ repo: String, _ outcome: CursorRoom.Outcome = .succeeded,
         at days: Int = 0) -> CursorRoom.Sighting {
    var tags = ["Agent run"]
    if outcome != .succeeded { tags.append(outcome.rawValue) }
    return CursorRoom.Sighting(title: "\(repo) · an agent", tags: tags,
                               repo: repo, at: day(days))
}

print("Days")
check("a run earlier today is zero days back",
      CursorRoom.days(from: t0, to: t0.addingTimeInterval(3600)) == 0)
// The whole reason this is calendar days and not interval/86400: a run at
// 11pm is A DAY old by the next morning, not zero-point-oh-four.
check("a run last night is one day back this morning, not a fraction",
      CursorRoom.days(from: t0.addingTimeInterval(23 * 3600), to: day(1)) == 1)
check("a week is seven", CursorRoom.days(from: t0, to: day(7)) == 7)

print("")
print("Outcome markers — the tag's words, mirrored from CursorAgentStatus")
check("Failed is a marker", CursorRoom.marker("Failed") == .failed)
check("Expired is a marker", CursorRoom.marker("Expired") == .expired)
check("Cancelled is a marker", CursorRoom.marker("Cancelled") == .cancelled)
// Nothing leads a successful run's title, so "Succeeded" can never appear
// there — treating it as a marker would strip a real repository named that.
check("Succeeded is not a marker", CursorRoom.marker("Succeeded") == nil)
check("an ordinary word is not a marker", CursorRoom.marker("Agent run") == nil)
check("the match is exact, not case-folded", CursorRoom.marker("failed") == nil)
// Failed and expired both mean "nothing came back". Cancelled is a decision
// the person made, and must never lead a card that ranks by what stops you.
check("a failed run didn't finish", CursorRoom.Outcome.failed.unfinished)
check("an expired run didn't finish", CursorRoom.Outcome.expired.unfinished)
check("a CANCELLED run is not a failure", !CursorRoom.Outcome.cancelled.unfinished)
check("a succeeded run is not a failure", !CursorRoom.Outcome.succeeded.unfinished)

print("")
print("Reading the outcome — tag first, title second")
check("a tag is read, and says so",
      CursorRoom.outcome(tags: ["Agent run", "Failed"], title: "org/repo · x")
        == (.failed, .stored))
// The §340 ruling as a test: the tag is unlocalized and the title is not, so
// the tag must win even when they disagree.
check("the TAG beats a disagreeing title clause",
      CursorRoom.outcome(tags: ["Cancelled"], title: "Failed · org/repo · x")
        == (.cancelled, .stored))
check("a legacy row falls back to the title clause",
      CursorRoom.outcome(tags: ["Agent run"], title: "Failed · org/repo · x")
        == (.failed, .title))
check("no clause and no tag is a success",
      CursorRoom.outcome(tags: ["Agent run"], title: "org/repo · x")
        == (.succeeded, .none))
// Defensive by ruling: an unrecognised lead clause is a SUCCESS. Claiming a
// failure we cannot evidence is the expensive direction.
check("an unknown lead clause reads as a success",
      CursorRoom.outcome(tags: [], title: "Whatever · org/repo · x")
        == (.succeeded, .none))
check("a non-English legacy clause reads as a success, never a guess",
      CursorRoom.outcome(tags: [], title: "Échoué · org/repo · x")
        == (.succeeded, .none))
check("a bare title with no separator at all is a success",
      CursorRoom.outcome(tags: [], title: "Background agent") == (.succeeded, .none))

print("")
print("Naming a repository — a title candidate has to earn it")
check("org/repo is a repository", CursorRoom.looksLikeRepo("org/repo"))
check("a nested group is a repository", CursorRoom.looksLikeRepo("group/sub/project"))
check("a bare word is not", !CursorRoom.looksLikeRepo("myrepo"))
check("an agent name is not", !CursorRoom.looksLikeRepo("fix the flaky test"))
// titleLine clamps at 80 and appends "…" — half a repository name is a
// repository that does not exist.
check("a clamped candidate is refused", !CursorRoom.looksLikeRepo("org/re…"))
check("a leading slash is refused", !CursorRoom.looksLikeRepo("/repo"))
check("a trailing slash is refused", !CursorRoom.looksLikeRepo("org/"))
check("a lone slash is refused", !CursorRoom.looksLikeRepo("/"))
check("an empty candidate is refused", !CursorRoom.looksLikeRepo(""))

print("")
print("Reading a repository out of a title")
check("the first component is the repo",
      CursorRoom.repoInTitle("org/repo · Add README") == "org/repo")
check("a lead clause is skipped first",
      CursorRoom.repoInTitle("Failed · org/repo · Add README") == "org/repo")
check("a title with no repo names none",
      CursorRoom.repoInTitle("Background agent") == nil)
check("a failed run with no repo names none",
      CursorRoom.repoInTitle("Expired · Background agent") == nil)
check("a clamped repo names none rather than half a name",
      CursorRoom.repoInTitle("Failed · org/some-very-long-re…") == nil)

print("")
print("Reading a row — stored fields win, the title is the legacy fallback")
let modern = CursorRoom.read(sight("Failed · a/b · x", tags: ["Agent run", "Failed"], repo: "org/repo"))
check("the stored repo wins over the title's", modern.repo == "org/repo")
check("and says it came from a stored field", modern.repoFrom == .stored)
check("the tag is read alongside it", modern.outcome == .failed && modern.outcomeFrom == .stored)
// The stored value is what the bridge read off the API — a single-component
// remote is a real answer and must not be held to the title's slash test.
check("a stored repo needs no slash",
      CursorRoom.read(sight("myrepo · x", repo: "myrepo")).repo == "myrepo")
check("a blank stored repo falls through to the title",
      CursorRoom.read(sight("org/repo · x", repo: "   ")).repo == "org/repo")
let legacy = CursorRoom.read(sight("Failed · org/repo · x", tags: ["Agent run"]))
check("a legacy row is placed by its title", legacy.repo == "org/repo")
check("and says the repo came from the title", legacy.repoFrom == .title)
check("and its outcome came from the title too", legacy.outcomeFrom == .title)
let unplaced = CursorRoom.read(sight("Background agent", tags: []))
check("a row naming no repo anywhere is unplaced", unplaced.repo == nil)
check("and says so", unplaced.repoFrom == .none)

print("")
print("Composing — grouping, counting, and never inventing")
let mixed = CursorRoom.compose(runs: [
    run("acme/api", .failed, at: -1),
    run("acme/api", at: -2),
    run("acme/api", .cancelled, at: -3),
    run("acme/web", at: -1),
    run("acme/web", at: -4),
    run("acme/web", at: -5),
    run("acme/web", .expired, at: -6),
    sight("Background agent", tags: [], at: -1),
])
check("repositories are grouped", mixed.repos.count == 2)
check("placed runs are counted", mixed.totalRuns == 7)
// A run this card cannot place is a run missing from every number above it.
check("an unplaceable run is EXCLUDED, not bucketed", mixed.excluded == 1)
check("and no repository was invented for it",
      !mixed.repos.contains { $0.name.isEmpty })
check("failed and expired are both counted as unfinished", mixed.totalUnfinished == 2)
check("a cancelled run counts as a run", mixed.repos.first { $0.name == "acme/api" }?.runs == 3)
check("but not as an unfinished one",
      mixed.repos.first { $0.name == "acme/api" }?.unfinished == 1)
check("each repository keeps its own newest run",
      mixed.repos.first { $0.name == "acme/web" }?.newest == day(-1))
// If an unplaced run landed this morning, "no runs for 12 days" would be false.
check("the room's newest run counts the excluded ones too", mixed.newest == day(-1))
check("an empty corpus composes to an empty room",
      CursorRoom.compose(runs: []).repos.isEmpty)

print("")
print("Ranking — what stops you leads")
// The card's whole premise: one failure outranks twenty clean runs.
let ranked = CursorRoom.compose(runs:
    Array(repeating: run("acme/web"), count: 20) + [run("acme/api", .failed)])
check("a single failure leads twenty clean runs", ranked.lead?.name == "acme/api")
check("a repo with a broken run outranks one without",
      CursorRoom.rank(CursorRoom.Repo(name: "a", runs: 1, unfinished: 1, newest: t0))
        > CursorRoom.rank(CursorRoom.Repo(name: "b", runs: 99, unfinished: 0, newest: t0)))
let byVolume = CursorRoom.compose(runs:
    [run("acme/web"), run("acme/web"), run("acme/api")])
check("with nothing broken, the busiest leads", byVolume.lead?.name == "acme/web")
// A total order, or the card reshuffles between opens over identical rows.
let tied = CursorRoom.compose(runs: [run("zeta/one"), run("alpha/two")])
check("a tie falls back to the name", tied.repos.map(\.name) == ["alpha/two", "zeta/one"])
let shuffledA = CursorRoom.compose(runs: [run("b/x"), run("a/x"), run("c/x"), run("a/x")])
let shuffledB = CursorRoom.compose(runs: [run("a/x"), run("c/x"), run("a/x"), run("b/x")])
check("two composes over the same rows agree exactly",
      shuffledA.repos.map(\.name) == shuffledB.repos.map(\.name))
check("and the busiest still leads", shuffledA.repos.map(\.name) == ["a/x", "b/x", "c/x"])
check("failing repositories sort among themselves by volume",
      CursorRoom.compose(runs: [run("a/x", .failed), run("b/x", .failed), run("b/x")])
        .repos.map(\.name) == ["b/x", "a/x"])

print("")
print("The bar")
check("the busiest fills it", CursorRoom.share(runs: 10, of: 10) == 1)
check("half is half", abs(CursorRoom.share(runs: 5, of: 10) - 0.5) < 0.0001)
// A zero denominator draws as a NaN width, which SwiftUI renders as nothing.
check("nothing to compare against draws nothing, never NaN",
      CursorRoom.share(runs: 5, of: 0) == 0)
check("a share past the top clamps", CursorRoom.share(runs: 20, of: 10) == 1)

print("")
print("Emptiness — one run is a row, not a card")
check("no runs, no card", CursorRoom.compose(runs: []).isEmpty)
check("one run, no card", CursorRoom.compose(runs: [run("a/x")]).isEmpty)
check("two runs earn a card", !CursorRoom.compose(runs: [run("a/x"), run("a/x")]).isEmpty)
// Excluded runs are not placed runs — a room of one real run and three
// unplaceable ones has one run in it.
check("excluded runs don't get a card over the line",
      CursorRoom.compose(runs: [run("a/x"), sight("x", tags: []),
                                sight("y", tags: []), sight("z", tags: [])]).isEmpty)

print("")
print("The headline — trouble first, volume second")
check("an empty room says so", CursorRoom.headline(CursorRoom.compose(runs: [])) == "Nothing to report")
check("one broken run names its repository",
      CursorRoom.headline(CursorRoom.compose(runs: [run("a/x", .failed), run("a/x")]))
        == "1 run didn't finish in a/x")
check("several in one repository are counted",
      CursorRoom.headline(CursorRoom.compose(runs: [run("a/x", .failed), run("a/x", .expired)]))
        == "2 runs didn't finish in a/x")
check("across repositories it counts the repositories",
      CursorRoom.headline(CursorRoom.compose(runs: [run("a/x", .failed), run("b/x", .failed)]))
        == "2 runs didn't finish across 2 repos")
check("a quiet room states its volume",
      CursorRoom.headline(CursorRoom.compose(runs: [run("a/x"), run("a/x"), run("a/x")]))
        == "3 agent runs in a/x")
check("a quiet room spanning repositories counts them",
      CursorRoom.headline(CursorRoom.compose(runs: [run("a/x"), run("b/x"), run("b/x")]))
        == "3 agent runs across 2 repos")
// Trouble outranks volume even when volume is the bigger number.
check("one failure beats nineteen clean runs to the headline",
      CursorRoom.headline(CursorRoom.compose(runs:
        Array(repeating: run("busy/repo"), count: 19) + [run("quiet/repo", .failed)]))
        == "1 run didn't finish in quiet/repo")

print("")
print("The repository line")
check("a clean repository states its runs",
      CursorRoom.repoLine(CursorRoom.Repo(name: "a", runs: 5, unfinished: 0, newest: t0))
        == "5 runs")
check("one run reads singular",
      CursorRoom.repoLine(CursorRoom.Repo(name: "a", runs: 1, unfinished: 0, newest: t0))
        == "1 run")
// "Didn't finish", not "failed" — the count holds two different outcomes.
check("breakage is stated beside the volume",
      CursorRoom.repoLine(CursorRoom.Repo(name: "a", runs: 5, unfinished: 2, newest: t0))
        == "5 runs · 2 didn't finish")

print("")
print("The note — what isn't drawn, and what couldn't be placed")
let small = CursorRoom.compose(runs: [run("a/x"), run("a/x")])
check("a fully drawn, freshly run room says nothing",
      CursorRoom.note(small, drawn: 1, now: t0) == nil)
check("undrawn repositories are counted",
      CursorRoom.note(CursorRoom.compose(runs: [run("a/x"), run("b/x"), run("c/x"), run("d/x")]),
                      drawn: 3, now: t0) == "1 more repo")
check("several are pluralised",
      CursorRoom.note(CursorRoom.compose(runs: [run("a/x"), run("b/x"), run("c/x"),
                                                run("d/x"), run("e/x")]),
                      drawn: 3, now: t0) == "2 more repos")
check("unplaceable runs are named, never swallowed",
      CursorRoom.note(CursorRoom.compose(runs: [run("a/x"), run("a/x"), sight("x", tags: [])]),
                      drawn: 1, now: t0) == "1 run has no repo")
check("several unplaceable runs are pluralised",
      CursorRoom.note(CursorRoom.compose(runs: [run("a/x"), run("a/x"),
                                                sight("x", tags: []), sight("y", tags: [])]),
                      drawn: 1, now: t0) == "2 runs have no repo")
check("all three clauses join in order",
      CursorRoom.note(CursorRoom.compose(runs: [run("a/x"), run("b/x"), run("c/x"),
                                                run("d/x"), sight("x", tags: [])]),
                      drawn: 3, now: day(30))
        == "1 more repo · 1 run has no repo · no runs for 30 days")

print("")
print("Idle — said only when the silence means something")
check("a room that ran today says nothing",
      CursorRoom.idleNote(newest: t0, now: t0) == nil)
check("a few quiet days need no explanation",
      CursorRoom.idleNote(newest: t0, now: day(6)) == nil)
check("a week of silence is stated",
      CursorRoom.idleNote(newest: t0, now: day(7)) == "no runs for 7 days")
check("longer counts the days",
      CursorRoom.idleNote(newest: t0, now: day(40)) == "no runs for 40 days")
check("no runs at all makes no claim", CursorRoom.idleNote(newest: nil, now: t0) == nil)

print("")
if failures > 0 { print("cursor-room-selftest: ✗ \(failures) of \(checks) assertion(s) failed"); exit(1) }
print("cursor-room-selftest: OK — \(checks) assertions passed against the shipped source.")
SWIFT

if ! swiftc -O -o "$TMP/cr-selftest" "$ROOM" "$LEDE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/cr-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above.
echo ""
echo "Mutations (each must break something)"

mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut-room.swift"
  cp "$ROOM" "$target"
  # Literal, via argv — NOT interpolated into a regex. Both the shipped snippets
  # and their replacements are Swift, full of parentheses, slashes and
  # backslashes, and a regex-based replacer spends its life escaping them
  # (`room-heads-selftest.sh`'s own first cut died on exactly that).
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$target" "$LEDE" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# The card's entire premise: what came back broken leads.
mutate "a broken repository stops outranking a busy one" \
  'static func rank(_ repo: Repo) -> Int { repo.unfinished > 0 ? 2 : 1 }' \
  'static func rank(_ repo: Repo) -> Int { 1 }'
# An order that is not total reshuffles between opens over identical rows.
mutate "the name tie-break inverts, so the order stops being the one drawn" \
  'return a.name < b.name' \
  'return a.name > b.name'
# A cancelled run is a decision the person made; counting it alarms them about
# their own choice.
mutate "a cancelled run is counted as a failure" \
  'var unfinished: Bool { self == .failed || self == .expired }' \
  'var unfinished: Bool { self != .succeeded }'
# §340's own reason for landing the tag: the title is localized and the tag is
# not, so reading the title first makes every past failure read as a success the
# day the device changes language.
mutate "the localized title is consulted before the stable tag" \
  'for tag in tags {' \
  'for tag in [String]() {'
# Half a repository name is a repository that does not exist.
mutate "a clamped title candidate is accepted as a repository" \
  'guard !candidate.contains("…"), !candidate.contains(" ") else { return false }' \
  'guard !candidate.contains(" ") else { return false }'
# The refusal that keeps every number on the card true.
mutate "an unplaceable run is bucketed instead of counted" \
  'guard let repo = run.repo else { excluded += 1; continue }' \
  'let repo = run.repo ?? "unplaced"'
# An unrecognised lead clause must read as a SUCCESS — claiming a failure we
# cannot evidence is the expensive direction.
mutate "an unrecognised word becomes an outcome" \
  'guard let outcome = Outcome(rawValue: word), outcome != .succeeded else { return nil }
        return outcome' \
  'return Outcome(rawValue: word) ?? .failed'
# Calendar days vs interval arithmetic.
mutate "days measured by interval instead of calendar" \
  'let a = calendar.startOfDay(for: now)' \
  'let a = now'
# A zero denominator draws as a NaN width, which SwiftUI renders as nothing.
mutate "the bar divides by a zero top" \
  'guard top > 0 else { return 0 }' \
  'if top < 0 { return 0 }'
# One run is a row, and the row already says everything the card would.
mutate "a single run earns a whole card" \
  'static let minimumRuns = 2' \
  'static let minimumRuns = 1'
# Excluded runs are not placed runs.
mutate "excluded runs are counted toward the card's minimum" \
  'var isEmpty: Bool { repos.isEmpty || totalRuns < CursorRoom.minimumRuns }' \
  'var isEmpty: Bool { repos.isEmpty || (totalRuns + excluded) < CursorRoom.minimumRuns }'
# Volume leading over breakage is the inversion the whole card exists to avoid.
mutate "volume leads the headline instead of trouble" \
  'if room.totalUnfinished > 0 {' \
  'if false {'
# A total that silently omits rows is the failure the import drop counters exist
# to prevent, one room over.
mutate "the note stops naming unplaceable runs" \
  'if room.excluded > 0 {' \
  'if false {'
# The stored repo is data; the title is a guess. Preferring the guess silently
# excludes every run whose title was clamped.
mutate "the stored repository stops winning over the title" \
  'if let stored, !stored.isEmpty {' \
  'if let stored, stored.isEmpty {'
# A card that narrates every ordinary gap is a card people stop reading.
mutate "the idle clause fires on every quiet day" \
  'guard days >= quietAfter else { return nil }' \
  'guard days >= 0 else { return nil }'

echo ""
echo "cursor-room-selftest: OK — assertions pass and every mutation is caught."
