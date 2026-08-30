#!/bin/zsh
# Casberi onboarding-fork self-test — the SHIPPED pure logic behind which card
# the fork leads with, plus drift guards for the wiring that logic can't prove
# (prd §422, 2026-08-20):
#
#   Casberi/Casberi/Model/StartAppetite.swift   — compiled WHOLE and unmodified
#     (Foundation-only by design: the catalog resolver is passed IN as a
#     closure precisely so this harness needs no `BridgeCatalog` stub, and so
#     the file it proves is byte-for-byte the file that ships).
#
# WHY A HARNESS. Every failure here is a SILENT WRONG ANSWER on the screen
# where a new person decides whether to keep the app — it renders perfectly
# either way:
#
#   • the fork leading with the card the person showed the LEAST interest in
#     (an inverted comparison), which is worse than never reordering;
#   • cards that reshuffle between two draws of identical data (a sort that
#     isn't a total order), which reads as broken;
#   • reordering on NO evidence, because a category that argues for nothing
#     was quietly mapped to an arm anyway;
#   • counting distinct rooms instead of visits, so nine minutes in the wallet
#     room loses to three rooms glanced at once each.
#
# And the drift half matters more than the arithmetic: the signal is recorded
# in one file, survives a teardown in a second, and is read in a third. Break
# any link and the fork silently returns to a fixed order with every test here
# still green.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

APPETITE="Casberi/Casberi/Model/StartAppetite.swift"
FORK="Casberi/Casberi/Screens/StartHereScreen.swift"
CHIPS="Casberi/Casberi/Model/ChipMemory.swift"
DEMO="Casberi/Casberi/Model/DemoMode.swift"
SEED="Casberi/Casberi/Model/DemoSeedAll.swift"
for f in "$APPETITE" "$FORK" "$CHIPS" "$DEMO" "$SEED"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/start-fork-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- comment-stripped copies ------------------------------------------------
# The negative guards below MUST read source with comments removed, because
# these files document the rules by NAMING the thing they must no longer do —
# `StartHereScreen` quotes the three retired fake placeholders verbatim while
# explaining why they were retired. A guard grepping raw source fires against
# the prose explaining it. That is the Obsidian/Cursor lesson and this is its
# sixth instance in this repo; it is cheaper to write the stripper than to
# rediscover it.
#
# The stripper tracks string literals rather than cutting at the first `//`,
# which matters for any URL literal in these files: a naive stripper truncates
# the very literal a positive guard is about to look for, and the guard then
# fails against correct code.
#
# **Its proof is a FIXTURE, not an anchor in production source (§527).** It used
# to grep the stripped fork for `"https://www.nasa.gov/feed/"` — a real literal
# that really did contain `//` — and that read correctly right up until §527
# deleted the follow form the literal lived in, at which point the harness
# failed with a message about a broken stripper while the stripper was fine.
# A check whose subject can be moved by an unrelated edit reports the wrong
# thing at exactly the moment somebody is least able to tell. The fixture below
# carries both hazards on purpose and can never be edited out from under it.
strip_comments() {
  python3 - "$1" <<'PY'
import sys
src = open(sys.argv[1]).read()
out, i, n = [], 0, len(src)
in_str = in_line = in_block = False
depth = 0
while i < n:
    c = src[i]
    nxt = src[i + 1] if i + 1 < n else ''
    if in_line:
        if c == '\n':
            in_line = False
            out.append(c)
    elif in_block:
        if c == '*' and nxt == '/':
            depth -= 1
            i += 2
            if depth == 0:
                in_block = False
            continue
        if c == '/' and nxt == '*':
            depth += 1
            i += 2
            continue
        if c == '\n':
            out.append(c)
    elif in_str:
        out.append(c)
        if c == '\\':
            if i + 1 < n:
                out.append(nxt)
            i += 2
            continue
        if c == '"':
            in_str = False
    else:
        if c == '"':
            in_str = True
            out.append(c)
        elif c == '/' and nxt == '/':
            in_line = True
            i += 2
            continue
        elif c == '/' and nxt == '*':
            in_block = True
            depth = 1
            i += 2
            continue
        else:
            out.append(c)
    i += 1
sys.stdout.write(''.join(out))
PY
}

strip_comments "$FORK"  > "$TMP/fork.stripped.swift"
strip_comments "$CHIPS" > "$TMP/chips.stripped.swift"
strip_comments "$DEMO"  > "$TMP/demo.stripped.swift"
strip_comments "$SEED"  > "$TMP/seed.stripped.swift"

# The stripper is itself a check, so prove it works before trusting it — a
# stripper that returned an empty file would make every negative guard below
# pass vacuously, which is a check satisfied for the wrong reason.
cat > "$TMP/stripper-fixture.swift" <<'FIXTURE'
// a leading comment that must go
let keep = "https://www.nasa.gov/feed/"   // a trailing comment that must go
/* a block
   comment that must go */
let alsoKeep = "trailing slashes // inside a literal"
FIXTURE
strip_comments "$TMP/stripper-fixture.swift" > "$TMP/stripper-fixture.out"
grep -q 'https://www.nasa.gov/feed/' "$TMP/stripper-fixture.out" \
  || { echo "✗ the comment stripper ate a string literal containing '//' — every"; \
       echo "  positive guard below would now fail against correct code"; exit 1; }
grep -q 'trailing slashes // inside a literal' "$TMP/stripper-fixture.out" \
  || { echo "✗ the comment stripper truncated a literal at an interior '//'"; exit 1; }
grep -q 'must go' "$TMP/stripper-fixture.out" \
  && { echo "✗ the comment stripper left comment text behind — every negative guard"; \
       echo "  below would fire against the prose explaining the rule"; exit 1; }
# …and that it produced usable source from the real files, not an empty one:
# a stripper returning nothing makes every negative guard pass vacuously.
grep -q 'struct StartHereScreen' "$TMP/fork.stripped.swift" \
  || { echo "✗ the comment stripper produced no usable source"; exit 1; }

# --- drift guards: the signal's three links ---------------------------------
# (1) RECORDED. `ChipMemory.visited` is the one place a room open is counted,
# and the demo keeps its own copy because `DemoSeedAll.teardown` erases the
# ChipMemory keys for every demo source on the way out. Drop this call and the
# fork has nothing to read, forever, silently.
grep -q 'DemoMode.noteRoomVisit(source)' "$TMP/chips.stripped.swift" \
  || { echo "✗ ChipMemory.visited no longer records demo room visits — the fork's"; \
       echo "  ordering signal is never written and it silently returns to a fixed order"; exit 1; }

# (2) SURVIVES. The record must be cleared when a demo BEGINS (a fresh run,
# a fresh record) and must NOT be cleared on the way out — the fork reads it
# one screen after the demo ends, so a symmetric teardown would erase the
# answer at exactly the moment it is asked for. This is the pairing that is
# easiest to "tidy up" into uselessness.
grep -q 'removeObject(forKey: roomVisitsKey)' "$TMP/demo.stripped.swift" \
  || { echo "✗ DemoMode.begin no longer clears the room-visit record — a second demo"; \
       echo "  run inherits the first one's answer"; exit 1; }
grep -q 'roomVisits' "$TMP/seed.stripped.swift" \
  && { echo "✗ DemoSeedAll now touches the room-visit record — teardown must NOT clear it,"; \
       echo "  or the fork reads an empty answer one screen after the demo ends"; exit 1; }

# (3) READ. Dead code is the other silent failure: the ordering can be perfect
# and the fork can still draw a hardcoded order.
grep -q 'StartAppetite.order(' "$TMP/fork.stripped.swift" \
  || { echo "✗ the fork no longer asks StartAppetite for its order"; exit 1; }
grep -q 'BridgeCatalog.category(forSource:)' "$TMP/fork.stripped.swift" \
  || { echo "✗ the fork no longer resolves sources through the catalog registry —"; \
       echo "  a hand list here goes stale the day a seat is added"; exit 1; }

# --- drift guards: leave-first (the change §422 exists for) ------------------
# The acting arm must hand back to the feed BEFORE awaiting its sync, or the
# rows are revealed already landed instead of watched arriving. Checked
# POSITIONALLY rather than by presence: `onStart(nil)` and a `Task` both exist
# in either order, and the whole feature is which comes first.
#
# ONE arm since §527, not two: the follow arm went with the third card, and its
# `follow(_ handle:)` was the other subject here. The rule is unchanged and so
# is this check's shape — if a second acting arm is ever added, add it to the
# tuple below rather than trusting it to inherit the rule.
python3 - "$TMP/fork.stripped.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
for fn, label in (("private func connectFolder()", "the files arm"),):
    at = src.find(fn)
    if at < 0:
        sys.exit(f"✗ {label}: '{fn}' not found — the harness is stale, not the code")
    # Body = from the signature to the start of the next top-level-ish func.
    rest = src[at + len(fn):]
    end = rest.find("\n    private func ")
    body = rest if end < 0 else rest[:end]
    leave = body.find("onStart(nil)")
    work = body.find("Task {")
    if leave < 0:
        sys.exit(f"✗ {label} no longer hands back to the feed at all")
    if work < 0:
        sys.exit(f"✗ {label} no longer does its work off the main flow")
    if leave > work:
        sys.exit(f"✗ {label} awaits its sync BEFORE handing back (prd §422): the person\n"
                 f"  waits on a spinner and the feed is then revealed already full, which\n"
                 f"  reads as a screenshot rather than as their things arriving.")
    # The environment must be captured into locals first: `onStart` tears this
    # screen down, and an `@Environment` read afterwards is a dead view's storage.
    if not re.search(r"let\s+shell\s*=\s*chrome", body):
        sys.exit(f"✗ {label} uses `chrome` after teardown without capturing it first")
print("  ✓ the acting arm hands back before its sync, capturing the environment first")
PY

# --- drift guards: the fork asks ONE question (§527) -------------------------
# The screen carries exactly the arms `StartAppetite` orders and nothing else
# wearing the same `card(…)` shape. Two things were deleted for the same
# reason — they read as extra answers to a question that has two — and both
# come back the same way, by somebody adding a `card(` call:
#
#   • the DEMO card, which only ever rendered for a person who had just tapped
#     past "Try a demo" on the screen before, so it re-asked a question they
#     had answered seconds earlier;
#   • the FOLLOW card, whose audience the catalog serves better than a form
#     with three segments could.
#
# ONE card call site PER ARM and no more. Counted against `StartAppetite.Arm`
# rather than against a literal, so adding an arm needs no edit here while a
# card that belongs to no arm is caught the day it lands — which is precisely
# what both deleted cards were.
python3 - "$TMP/fork.stripped.swift" "$APPETITE" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
appetite = open(sys.argv[2]).read()

# Call sites are every `card(figure:` that is not the declaration itself.
calls = len(re.findall(r"(?<!func )card\(figure:", src))

m = re.search(r"enum Arm[^{]*\{\s*case ([^\n]+)", appetite)
if not m:
    sys.exit("✗ could not read StartAppetite.Arm — the harness is stale, not the code")
arms = [a.strip() for a in m.group(1).split(",") if a.strip()]

# One per arm, PLUS EXACTLY ONE for the catalog row — the last answer in the
# slab, which wears the arms' own shape (§527) and is the only card that is not
# an arm. Any further call site is an answer belonging to nothing, which is what
# the demo card was and what made the screen read as a menu of five.
expected = len(arms) + 1
if calls != expected:
    sys.exit(f"✗ the fork draws {calls} `card(figure:` call sites, expected {expected}\n"
             f"  ({len(arms)} arms — {', '.join(arms)} — plus the catalog row).\n"
             f"  An extra one is an answer at the same visual weight as the real ones\n"
             f"  belonging to no question, which is exactly what the demo card was.")
print(f"  ✓ {calls} cards: one per arm plus the catalog row, nothing else")
PY
# The escape hatch names the OUTCOME and is in the arms' own voice, so it reads
# as belonging to the question rather than as a peer of the demo (§527). The
# retired label named our surface instead, on the second screen of a first run.
grep -qF 'Show me all the apps' "$TMP/fork.stripped.swift" \
  || { echo "✗ the exit no longer says 'Show me all the apps' (§527) — it must name"; \
       echo "  what the tap produces, in the same voice as the arms above it"; exit 1; }
grep -qF 'Browse the catalog' "$TMP/fork.stripped.swift" \
  && { echo "✗ 'Browse the catalog' is back — it names our surface rather than the"; \
       echo "  outcome, and the common path here routes around the screen that"; \
       echo "  teaches the word (§527)"; exit 1; }
# A COUNT must never return to that label (user, 2026-08-11): a number is a
# claim to survey rather than a destination to go to.
grep -qE 'See all [0-9]+ apps|all \\\(.*count.*\) apps' "$TMP/fork.stripped.swift" \
  && { echo "✗ a count is back in the catalog label — 2026-08-11: the number becomes"; \
       echo "  the argument, and a number is a claim to survey"; exit 1; }
# The standing rule, mechanical for the first time: never dwr, anywhere in a
# demo or an onboarding suggestion.
grep -qiE '\bdwr\b' "$TMP/fork.stripped.swift" \
  && { echo "✗ 'dwr' appears in the onboarding fork — standing rule: never in a demo"; exit 1; }

# --- compile StartAppetite WHOLE, and exercise it ---------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func order(_ visits: [String: Int], _ cat: [String: String]) -> [StartAppetite.Arm] {
    StartAppetite.order(visits: visits, category: { cat[$0] })
}

let D = StartAppetite.defaultOrder
check(D == [.files, .wallet], "default order is files, wallet")
// TWO arms since §527 — the follow card went to "Show me all the apps", whose
// catalog serves that audience better than a three-segment form. Asserted as a
// count so a third arm cannot be added without this harness being read: every
// ordering fixture below is written against a two-arm default and several of
// them stop discriminating the moment that changes.
check(StartAppetite.Arm.allCases.count == 2, "the fork has exactly two arms (§527)")

// No signal at all — somebody who skipped the demo, or walked it without
// opening a single room. This is the COMMON case, not a fallback.
check(order([:], [:]) == D, "no visits ⇒ the screen §217 shipped")
check(order(["Photos": 0], ["Photos": "Life"]) == D, "zero counts ⇒ default order")

// A source the catalog has never heard of resolves to nil and must not be
// invented into an arm.
check(order(["Nonesuch": 40], [:]) == D, "an unknown source orders nothing")

// One appetite, stated loudly. Note the wallet is the ONLY arm whose lead is
// distinguishable from the default: `.files` leads `defaultOrder` already, so
// every fixture from here on that means to prove a signal was READ has to
// prove `.wallet` leads. A "files-heavy demo leads with files" check would be
// the "right result for the wrong reason" trap in its purest form — it passes
// against a function that ignores its arguments entirely.
check(order(["Wallet": 9], ["Wallet": "Wallet"]) == [.wallet, .files],
      "a wallet-heavy demo leads with the wallet")

// Markets is money too — §322 keeps Wallet and Markets far apart on the
// catalog wall so the app doesn't read as crypto-only, but for "what did you
// come for?" they are one answer. Deleting this mapping is a live mutation.
check(order(["Kalshi": 6, "Stocktwits": 5], ["Kalshi": "Markets", "Stocktwits": "Markets"])
        == [.wallet, .files],
      "time spent in market rooms argues for the wallet card")

// SOCIAL AND READING ARGUE FOR NOTHING (§527), and this is the fixture that
// proves it rather than assuming it. When the follow arm existed they were its
// two halves; with it gone they are unmapped, and the tempting wrong answer is
// to fold them into `.files` on the grounds that a feed is "your stuff too".
// It is not — somebody who spent the demo in Bluesky told us they came for
// other people's writing, which argues for NEITHER remaining arm, and pointing
// it at the folder card would be the guess-dressed-as-a-preference the map
// exists to refuse.
//
// Built so it can actually FAIL: a LOUD social category against a QUIET wallet
// one. If Social were mapped to `.files`, files would score 9 against the
// wallet's 1 and lead — which is also `defaultOrder`, so the assertion below
// flips. Testing a lone social visit would not discriminate at all.
check(order(["Bluesky": 9, "Wallet": 1], ["Bluesky": "Social", "Wallet": "Wallet"])
        == [.wallet, .files],
      "Social argues for no arm even when it dominates the visits")
check(order(["RSS": 9, "Wallet": 1], ["RSS": "Reading", "Wallet": "Wallet"])
        == [.wallet, .files],
      "Reading argues for no arm even when it dominates the visits")

// THE PARTIAL MAP, same shape and the same reason. A demo spent entirely in
// Work/Agents/Media/Shopping says nothing about whether somebody's own things
// live in a folder or a wallet.
check(order(["Linear": 9, "Wallet": 1], ["Linear": "Work", "Wallet": "Wallet"])
        == [.wallet, .files],
      "an unmapped category scores nothing even when it dominates the visits")
check(order(["Claude": 9, "Wallet": 1], ["Claude": "Agents", "Wallet": "Wallet"])
        == [.wallet, .files],
      "Agents argues for no arm")

// VISITS, not distinct rooms. One room read nine times beats three rooms
// glanced at once each — the person who did the former was reading. Under a
// `+= 1` accumulation this fixture inverts, which is what makes it a test:
// the wallet's 9 becomes 1 and loses to the folder's 3.
check(order(["Wallet": 9, "Photos": 1, "Obsidian": 1, "Calendar": 1],
            ["Wallet": "Wallet", "Photos": "Life", "Obsidian": "Notes", "Calendar": "Life"])
        == [.wallet, .files],
      "nine visits to one room beat three rooms visited once each")

// Ties keep the default relative order — checked on a tie that is NOT zero,
// so it exercises the comparator rather than the early-out above. Both arms
// score 4, so the default order stands; reverse the tiebreak and it inverts.
check(order(["Wallet": 4, "Photos": 4], ["Wallet": "Wallet", "Photos": "Life"])
        == [.files, .wallet],
      "an equal score keeps the default relative order")

// TOTAL ORDER: identical input, identical output, every time. A fork whose
// cards reshuffle between draws reads as broken.
let mixed = ["Wallet": 3, "Kalshi": 3, "Photos": 3, "Obsidian": 1]
let cats = ["Wallet": "Wallet", "Kalshi": "Markets", "Photos": "Life", "Obsidian": "Notes"]
let first = order(mixed, cats)
for _ in 0..<200 {
    check(order(mixed, cats) == first, "ordering is deterministic across draws")
}
check(first.count == 2 && Set(first).count == 2, "every arm is drawn exactly once")

// Every arm is always present, whatever the input — this orders, it never
// hides, which is what keeps §217's "one decision, not offers of different
// weight" intact.
check(Set(order(["Wallet": 99], ["Wallet": "Wallet"])) == Set(StartAppetite.Arm.allCases),
      "no arm is ever dropped")

// The category map's own contract.
check(StartAppetite.arm(forCategory: "Wallet") == .wallet, "Wallet ⇒ wallet")
check(StartAppetite.arm(forCategory: "Markets") == .wallet, "Markets ⇒ wallet")
check(StartAppetite.arm(forCategory: "Life") == .files, "Life ⇒ files")
check(StartAppetite.arm(forCategory: "Notes") == .files, "Notes ⇒ files")
// Social and Reading join the unmapped set since §527 — listed here beside
// the four that were always unmapped so the map's whole contract reads in one
// place rather than the change living only in a comment.
for none in ["Social", "Reading", "Work", "Agents", "Media", "Shopping", "", "wallet"] {
    check(StartAppetite.arm(forCategory: none) == nil, "'\(none)' argues for no arm")
}

if failures > 0 { print("✗ \(failures) assertion(s) failed"); exit(1) }
print("  ✓ StartAppetite: ordering, the partial map, and determinism")
SWIFT

build_and_run() {
  local appetite="$1" label="$2"
  swiftc -O \
    "$appetite" "$TMP/main.swift" \
    -o "$TMP/run" 2> "$TMP/build.log" || {
      echo "✗ $label failed to compile:"; sed -n '1,20p' "$TMP/build.log"; return 2
    }
  "$TMP/run"
}

build_and_run "$APPETITE" "StartAppetite.swift" || exit 1

# --- mutations --------------------------------------------------------------
# Each one is a silent wrong answer that renders as a perfectly good fork. A
# check that cannot fail proves nothing, so every mutation must be shown to
# turn this suite red.
#
# NOT claimed as a mutation, deliberately, because it would SURVIVE and saying
# otherwise would be a false claim of coverage: removing `order`'s early
# `guard score.values.contains…` return. With no signal every score is zero,
# the comparator falls through to the default-position tiebreak, and the same
# order comes out. That guard is an early-out, not a correctness rail, and the
# suite is honest about which is which.
mutate() {
  local label="$1" find="$2" replace="$3"
  python3 - "$APPETITE" "$TMP/mutant.swift" "$find" "$replace" <<'PY'
import sys
src_path, out_path, find, replace = sys.argv[1:5]
src = open(src_path).read()
if find not in src:
    sys.exit(f"STALE: mutation target not found: {find!r}")
open(out_path, "w").write(src.replace(find, replace, 1))
PY
  if build_and_run "$TMP/mutant.swift" "mutant ($label)" > /dev/null 2>&1; then
    echo "✗ MUTATION SURVIVED — $label"
    echo "  the suite cannot catch this, so it proves nothing about it"
    exit 1
  fi
  echo "  ✓ caught: $label"
}

mutate "leading with the LEAST-visited card" \
  "if a != b { return a > b }" "if a != b { return a < b }"

mutate "ties reversing the default order" \
  "return left.offset < right.offset" "return left.offset > right.offset"

mutate "counting distinct rooms instead of visits" \
  "score[arm, default: 0] += count" "score[arm, default: 0] += 1"

mutate "Markets no longer arguing for the wallet" \
  'case "Wallet", "Markets":  .wallet' 'case "Wallet":  .wallet'

mutate "an unmapped category invented into an arm" \
  "default:                   nil" "default:                   .files"

# The §527 mutation, and the one this pass exists for: folding Social back into
# the folder card. It is the tempting wrong answer now that the follow arm is
# gone — "a feed is your stuff too" — and it renders as a perfectly ordinary
# fork that simply leads with the wrong card for every reader in the demo.
mutate "Social folded into the files card" \
  "        case \"Life\", \"Notes\":      .files" \
  "        case \"Life\", \"Notes\", \"Social\", \"Reading\":      .files"

mutate "the default order rewritten" \
  "static let defaultOrder: [Arm] = [.files, .wallet]" \
  "static let defaultOrder: [Arm] = [.wallet, .files]"

echo "✓ onboarding-fork self-test passed"
