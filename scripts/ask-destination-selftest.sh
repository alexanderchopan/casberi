#!/bin/zsh
# The ask capsule's arithmetic (prd §543, 2026-08-31) — compiled AS SHIPPED.
#
# `Model/AskDestination.swift` is Foundation-only BY DESIGN so this harness can
# compile the whole file unmodified: no stubs, no copy, no drift between what
# is tested and what runs.
#
# Why it exists: every failure here renders as a perfectly ordinary capsule.
# An agent silently missing from the row (a stale recency entry outranking a
# configured one, or a slot arithmetic that drops instead of overflowing) looks
# exactly like a key that was never configured. A non-total order reshuffles
# the row between two opens over identical state, which reads as the app being
# broken and destroys the one property the capsule needs — being in the same
# place every time. And a device segment that says "iPhone" on a Mac is a claim
# about where the answer runs, on the one control whose job is to say where the
# answer runs, on a platform `verify.sh` gates every pass.
#
# Mutation-proven: each assertion block below is followed by a mutation that
# must break it. A check that cannot fail proves nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/AskDestination.swift"
[[ -f "$SRC" ]] || { print -u2 "missing $SRC"; exit 1 }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

run_case() {
  local file="$1" label="$2"
  if ! swiftc -O "$file" "$WORK/main.swift" -o "$WORK/bin" 2>"$WORK/err"; then
    print -u2 "✗ $label — did not compile"; sed -n '1,12p' "$WORK/err" >&2; return 1
  fi
  "$WORK/bin"
}

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// ---- split: the shown/overflow arithmetic -------------------------------
let three = ["anthropic", "openai", "bankr"]

// No keys: the capsule is the device pill alone.
let none = AskDestination.split(configured: [], recent: [])
check(none.shown.isEmpty && none.overflow.isEmpty, "no configured providers yields nothing")

// Under the slot count: everything shows, nothing overflows.
let one = AskDestination.split(configured: ["bankr"], recent: [])
check(one.shown == ["bankr"] && one.overflow.isEmpty, "a single provider shows")

let two = AskDestination.split(configured: ["anthropic", "bankr"], recent: [])
check(two.shown == ["anthropic", "bankr"] && two.overflow.isEmpty, "two providers both show")

// Over the slot count: the rest OVERFLOW — they are never dropped. A provider
// that vanishes because a third key was added is a key you cannot spend.
let over = AskDestination.split(configured: three, recent: [])
check(over.shown.count == AskDestination.agentSlots, "shown is capped at the slot count")
check(over.shown == ["anthropic", "openai"], "canonical order fills the slots with no history")
check(over.overflow == ["bankr"], "the remainder overflows rather than disappearing")
check(Set(over.shown + over.overflow) == Set(three), "every configured provider is reachable")

// Recency leads, and the rest keep canonical order behind it.
let recent = AskDestination.split(configured: three, recent: ["bankr"])
check(recent.shown == ["bankr", "anthropic"], "the most recent agent leads")
check(recent.overflow == ["openai"], "the displaced one overflows")

// DISPLAY ORDER IS FIXED (2026-09-02, user: "i don't like how these chips
// change position it is confusing b/c the phone is first but isn't the one
// that is active"). `split` decides membership from recency; `display` puts
// the survivors back where they always sit. A key that moves under the thumb
// makes you read the whole row before every tap.
let declared = ["anthropic", "bankr", "openai"]
check(AskDestination.display(["bankr", "anthropic"], configured: declared)
        == ["anthropic", "bankr"],
      "display restores declared order whatever the pick was")
check(AskDestination.display(["openai", "bankr", "anthropic"], configured: declared)
        == declared,
      "a fully shuffled row comes back in declared order")
let promoted = AskDestination.split(configured: declared, recent: [], active: "openai")
check(AskDestination.display(promoted.shown + promoted.overflow, configured: declared)
        == declared,
      "the active agent keeps its position — the fill says it is chosen, not the place")
check(AskDestination.display(["ghost", "bankr"], configured: declared)
        == ["bankr", "ghost"],
      "an unknown destination sorts last and is never dropped")

let recentTwo = AskDestination.split(configured: three, recent: ["bankr", "openai"])
check(recentTwo.shown == ["bankr", "openai"], "two recents fill both slots in recency order")
check(recentTwo.overflow == ["anthropic"], "canonical order survives in the overflow")

// A STALE recency entry — a key that was cleared — is dropped, never shown.
// Otherwise the capsule offers a segment pointed at a credential that does not
// exist: a dead control that also reaches a live host.
let stale = AskDestination.split(configured: ["anthropic"], recent: ["venice", "grok"])
check(stale.shown == ["anthropic"], "a cleared key is not resurrected by the ledger")
check(stale.overflow.isEmpty, "and does not linger in the overflow")

// A duplicate cannot draw twice (two segments, one destination).
let dupe = AskDestination.split(configured: ["anthropic", "anthropic", "bankr"], recent: ["bankr", "bankr"])
check(dupe.shown == ["bankr", "anthropic"], "duplicates collapse")
check(dupe.overflow.isEmpty, "and do not pad the overflow")

// TOTAL ORDER: the same inputs must produce byte-identical output every call.
// A capsule that reshuffles between opens is the failure this guards.
var stable = true
let first = AskDestination.split(configured: three, recent: ["openai"])
for _ in 0..<50 {
    let again = AskDestination.split(configured: three, recent: ["openai"])
    if again.shown != first.shown || again.overflow != first.overflow { stable = false }
}
check(stable, "the split is deterministic across repeated calls")

// ---- FIND JOINS THE ROW (prd §575) --------------------------------------
// Find is a segment of this capsule now rather than a solid tint capsule of
// its own, so the row is device + Find + agents and one agent slot had to go.
// The failure this pins is silent in both directions: too many slots and the
// row overflows its own edge with the last segment half-drawn, too few and a
// configured key drops into a menu for no reason.
check(AskDestination.slots(findShown: false) == AskDestination.agentSlots,
      "without Find the row keeps its two agent slots")
check(AskDestination.slots(findShown: true) == AskDestination.agentSlotsWithFind,
      "with Find the row makes room by giving up one")
check(AskDestination.slots(findShown: true) < AskDestination.slots(findShown: false),
      "Find costs a slot rather than being free")
// NOTHING BECOMES UNREACHABLE. The displaced agent overflows into the menu,
// whose items send identically to a segment — the whole reason the overflow
// exists. A slot count that DROPPED one would be a key you cannot spend.
let withFind = AskDestination.split(configured: three, recent: [],
                                    slots: AskDestination.slots(findShown: true))
check(withFind.shown.count == 1, "one agent shows beside Find")
check(Set(withFind.shown + withFind.overflow) == Set(three),
      "every configured provider is still reachable with Find in the row")

// slots: 0 is a real answer (every agent overflows), never a crash.
let zero = AskDestination.split(configured: three, recent: [], slots: 0)
check(zero.shown.isEmpty && zero.overflow == three, "zero slots overflows everything")

// ---- active: the destination the ask is actually going to ---------------
// The capsule fills the active segment, so an active agent folded into the
// overflow menu is a mark nobody can see — which is the whole bug this
// parameter exists for, one layer down.
//
// ACTIVE BEATS RECENCY, and the fixture says so by disagreeing with it: with
// `recent: ["openai"]` alone the row would read openai, anthropic — so this
// case fails if `active` is ignored AND passes every other rule here, which
// is the only way it tests the rule it names.
let activeLeads = AskDestination.split(configured: three, recent: ["openai"], active: "bankr")
check(activeLeads.shown == ["bankr", "openai"], "the active agent leads even the most recent one")
check(activeLeads.overflow == ["anthropic"], "recency still orders behind it")

// ORDERING, NEVER INCLUSION: an active raw value that is not configured is
// dropped exactly as a stale recency entry is — otherwise it mints a segment
// pointed at a credential that does not exist (§83, at a live host).
let activeStale = AskDestination.split(configured: ["anthropic"], recent: [], active: "grok")
check(activeStale.shown == ["anthropic"], "an unconfigured active agent mints no segment")
check(activeStale.overflow.isEmpty, "and does not linger in the overflow")

// One list, so the active agent cannot also draw as its own recency entry.
let activeDupe = AskDestination.split(configured: three, recent: ["bankr"], active: "bankr")
check(activeDupe.shown == ["bankr", "anthropic"], "the active agent is not listed twice")
check(activeDupe.overflow == ["openai"], "nor padded into the overflow")

// A resting capsule (no ask in flight, no keyed conversation) is EXACTLY what
// it was before this parameter existed.
let resting = AskDestination.split(configured: three, recent: ["openai"], active: nil)
let restingBefore = AskDestination.split(configured: three, recent: ["openai"])
check(resting.shown == restingBefore.shown && resting.overflow == restingBefore.overflow,
      "no active destination leaves the order untouched")

// ---- the device names itself --------------------------------------------
check(AskDestination.deviceLabel(isMac: false, isPad: false) == "iPhone", "phone says iPhone")
check(AskDestination.deviceLabel(isMac: false, isPad: true) == "iPad", "pad says iPad")
check(AskDestination.deviceLabel(isMac: true, isPad: false) == "Mac", "mac says Mac")
// isMac wins: Catalyst reports a pad idiom in some configurations, and a Mac
// labelled "iPad" is the same wrong claim one step quieter.
check(AskDestination.deviceLabel(isMac: true, isPad: true) == "Mac", "mac beats pad")
check(AskDestination.deviceGlyph(isMac: false, isPad: false) == "iphone", "phone glyph")
check(AskDestination.deviceGlyph(isMac: false, isPad: true) == "ipad", "pad glyph")
check(AskDestination.deviceGlyph(isMac: true, isPad: false) == "laptopcomputer", "mac glyph")
check(AskDestination.deviceGlyph(isMac: true, isPad: true) == "laptopcomputer", "mac glyph beats pad")

// The device's ledger key must never collide with a provider raw value —
// they share one list, and a collision silently promotes or drops an agent.
check(AskDestination.deviceRaw.hasPrefix("__"), "the device raw value is not a bare word")
let providerRaws = ["anthropic", "openai", "google", "venice", "bankr", "openrouter", "grok"]
check(!providerRaws.contains(AskDestination.deviceRaw), "the device raw value is not a provider")

// ---- the recency ledger --------------------------------------------------
let suite = UserDefaults(suiteName: "ask-destination-selftest")!
AskDestination.forget(suite)
check(AskDestination.recent(suite).isEmpty, "an unwritten ledger reads empty")
AskDestination.used("bankr", suite)
AskDestination.used("openai", suite)
check(AskDestination.recent(suite) == ["openai", "bankr"], "newest first")
AskDestination.used("bankr", suite)
check(AskDestination.recent(suite) == ["bankr", "openai"], "re-asking promotes rather than duplicating")
for i in 0..<20 { AskDestination.used("p\(i)", suite) }
check(AskDestination.recent(suite).count <= 8, "the ledger is bounded")
AskDestination.forget(suite)

if failures == 0 { print("  ok   AskDestination — every assertion") }
exit(failures == 0 ? 0 : 1)
SWIFT

print "AskDestination self-test"
cp "$SRC" "$WORK/AskDestination.swift"
run_case "$WORK/AskDestination.swift" "shipped source" || exit 1

# ---- mutations: each must FAIL the assertions above ----------------------
mutate() {
  local label="$1" from="$2" to="$3"
  cp "$SRC" "$WORK/mutant.swift"
  if ! grep -qF -- "$from" "$WORK/mutant.swift"; then
    print -u2 "  ✗ mutation '$label' matched nothing — the guard is stale"; exit 1
  fi
  # A LITERAL replace, in python, deliberately not perl: a mutation string
  # containing `$0` (every Swift closure shorthand) is interpolated by perl
  # INSIDE the regex even under \Q, so the pattern silently matches nothing,
  # the mutant is identical to the shipped file, and the mutation "survives"
  # for a reason that has nothing to do with the code. Paid for on this
  # harness's first run — the dedupe guard was the one that could never fire.
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/mutant.swift" <<'PYEOF'
import os, sys
path = sys.argv[1]
src = open(path).read()
open(path, 'w').write(src.replace(os.environ['MUT_FROM'], os.environ['MUT_TO'], 1))
PYEOF
  if run_case "$WORK/mutant.swift" "$label" >/dev/null 2>&1; then
    print -u2 "  ✗ mutation SURVIVED: $label"; exit 1
  fi
  print "  ok   mutation caught — $label"
}

mutate "display leaves the pick promoted, so keys move under the thumb" \
       "let ra = rank[a.element] ?? Int.max, rb = rank[b.element] ?? Int.max" \
       "let ra = a.offset, rb = b.offset"
mutate "an unknown destination is sorted first instead of last" \
       "?? Int.max, rb = rank[b.element] ?? Int.max" \
       "?? Int.min, rb = rank[b.element] ?? Int.min"

mutate "the remainder is dropped instead of overflowing" \
       "return (Array(ordered.prefix(slots)), Array(ordered.dropFirst(slots)))" \
       "return (Array(ordered.prefix(slots)), [])"
mutate "recency is ignored, so a key pasted long ago outranks the agent you use" \
       "for raw in recent where configured.contains(raw) && !seen.contains(raw) {" \
       "for raw in [String]() where configured.contains(raw) && !seen.contains(raw) {"
mutate "a cleared key is still offered" \
       "for raw in recent where configured.contains(raw) && !seen.contains(raw) {" \
       "for raw in recent where !seen.contains(raw) {"
mutate "duplicates draw twice" \
       "for raw in configured where !seen.contains(raw) {" \
       "for raw in configured {"
mutate "the active agent is not promoted, so the marked segment can hide in the overflow" \
       "if let active, configured.contains(active) {" \
       "if let active, active.isEmpty, configured.contains(active) {"
mutate "an active agent whose key was cleared still mints a segment" \
       "if let active, configured.contains(active) {" \
       "if let active, true {"
mutate "the slot count changes" \
       "static let agentSlots = 2" \
       "static let agentSlots = 1"
mutate "Find is free, so the row overflows its own trailing edge" \
       "static let agentSlotsWithFind = 1" \
       "static let agentSlotsWithFind = 2"
mutate "the slot count ignores Find" \
       "findShown ? agentSlotsWithFind : agentSlots" \
       "agentSlots"
mutate "a Mac claims to be an iPhone" \
       'if isMac { return String(localized: "Mac") }' \
       'if false { return String(localized: "Mac") }'
mutate "a Mac wears a phone glyph" \
       'if isMac { return "laptopcomputer" }' \
       'if false { return "laptopcomputer" }'
mutate "iPad is reported as iPhone" \
       'return isPad ? String(localized: "iPad") : String(localized: "iPhone")' \
       'return String(localized: "iPhone")'
mutate "the device shares a provider's raw value" \
       'static let deviceRaw = "__device"' \
       'static let deviceRaw = "bankr"'
mutate "re-asking duplicates the ledger entry instead of promoting" \
       "var list = recent(defaults).filter { \$0 != raw }" \
       "var list = recent(defaults)"
mutate "the ledger grows without bound" \
       "defaults.set(Array(list.prefix(recentCap)), forKey: recentKey)" \
       "defaults.set(list, forKey: recentKey)"

# ---- drift guards: the wiring the compiled file cannot prove -------------
# Comments are stripped first: this file DOCUMENTS the rules by naming the very
# things it must not do ("never a hardcoded iPhone", "there is no send button"),
# so a guard grepping raw source fires on the prose explaining it — the
# Obsidian/Cursor lesson, earned again here.
#
# REWRITTEN 2026-09-03 (prd §581). Everything below used to guard the deck, the
# capsule, the greeting, the kept pills, the Send-to chips, the brief nav, the
# receipt paper and the turn disc. All of them are deleted with the chat they
# belonged to, so guarding them would be a suite proving a surface that is not
# on any screen. The MUTATION half above is untouched: `AskDestination` is the
# picker's own arithmetic and every rule in it still holds.
strip_comments() { perl -pe 's{//.*$}{}' "$1"; }

COMPOSER="Casberi/Casberi/Shell/Composer.swift"
TERMINAL="Casberi/Casberi/Shell/AgentTerminal.swift"
REPLY="Casberi/Casberi/Model/AgentReply.swift"
strip_comments "$COMPOSER" > "$WORK/composer.nc"
strip_comments "$TERMINAL" > "$WORK/terminal.nc"
strip_comments "$REPLY"    > "$WORK/reply.nc"
# A WHITESPACE-FLATTENED copy for the guards that span lines. `grep` is
# line-based, so a multi-line pattern matches NOTHING — and this file already
# records paying for exactly that once ("the first cut of this guard matched
# nothing and passed vacuously"). Flattening makes the span expressible instead
# of forcing each guard down to a single line it can be satisfied by alone.
tr '\n' ' ' < "$WORK/composer.nc" | tr -s ' ' > "$WORK/composer.flat"

guard() {
  local what="$1" file="$2" pattern="$3"
  if grep -qE "$pattern" "$file"; then print "  ok   $what"
  else print -u2 "  ✗ drift: $what"; exit 1; fi
}
guard_absent() {
  local what="$1" file="$2" pattern="$3"
  if grep -qE "$pattern" "$file"; then print -u2 "  ✗ drift: $what"; exit 1
  else print "  ok   $what"; fi
}

# ---- THE SWITCHER IS IN THE FOOT ----------------------------------------
# The user's own ruling (2026-09-03: "i like the switcher at the footer").
# Above the words it was a picker for a decision most people make once, and it
# made the head of the screen a control rather than an answer.
guard "the destination keys are mounted in the foot" "$WORK/composer.nc" \
      'AgentDestinationKeys\('
guard "the foot holds the keys and the verb on one row" "$WORK/composer.flat" \
      'AgentDestinationKeys\(.*footSlot'
# EVERY CONFIGURED AGENT GETS A KEY. §578 retired the overflow menu because a
# scroller has no width budget; nothing here may reintroduce a cap.
guard "the keys scroll rather than folding into a menu" "$WORK/terminal.nc" \
      'ScrollView\(.horizontal'
guard_absent "no slot cap returns to the keys" "$WORK/terminal.nc" \
      'AskDestination\.(split|slots)\('
# THE "+" IS THE OFFER. A destination-shaped hole rather than a banner — it
# needs no dismissal and can never be a dead control.
guard "an empty agent list offers the catalog as a key" "$WORK/terminal.nc" \
      'onAddAgent'

# ---- THE SEND ACTUALLY SENDS (prd §579, the shipped dead control) --------
# `askWithKey()` re-asks `currentQuestion`, which is empty until a `commit()`
# has run — so routing a DRAFT there did nothing on the first message of every
# conversation and asked the PREVIOUS question on every one after it.
# `askDirectly()` is the draft-send. A dead control renders as a perfectly
# ordinary armed blue pill, so this is guarded rather than remembered.
guard "the send routes the draft through askDirectly" "$WORK/composer.nc" \
      'AgentWideKey\(title: String\(localized: "Send"\), tone: .tint\) \{ askDirectly\(\) \}'
askwithkey_calls=$(grep -c 'askWithKey()' "$WORK/composer.nc")
if [[ $askwithkey_calls -ne 2 ]]; then
  print -u2 "  ✗ drift: askWithKey has $askwithkey_calls sites, expected 2 (its definition and the deferred retry)"
  exit 1
fi
print "  ok   askWithKey keeps exactly one caller, the deferred keyed follow-up"

# ---- ONE PICKER, ONE HANDLER (prd §579) ---------------------------------
# Two pickers were two copies of one handler and they had already drifted (one
# cleared `askProvider`, the other did not). Counting them would have worked and
# still described a rule kept in two places; one function both callers reach is
# the stronger answer, and this is that they reach it.
picker_handlers=$(grep -c 'AskDestination.used(' "$WORK/composer.nc")
if [[ $picker_handlers -ne 2 ]]; then
  print -u2 "  ✗ drift: AskDestination.used has $picker_handlers sites, expected 2 (pickDevice and pickAgent)"
  exit 1
fi
print "  ok   both picks go through one handler each, and only those"

# ---- A PICK MID-WAIT RE-ADDRESSES (prd §580) ----------------------------
# The one resend that is safe, and the reason is the change of ADDRESS: one
# question asked of somebody else, with the key you pressed as the consent.
guard "a key pressed mid-wait re-addresses the running question" "$WORK/composer.flat" \
      'if readdressed\(to: provider\) \{ return \}'

# ---- THE KEYCHAIN IS NOT READ PER KEYSTROKE (prd §579) ------------------
# `AgentKey.configured` is seven decrypting Keychain round trips; the foot's
# body reads `draft`, so a direct read there fires on every character typed.
guard_absent "the foot reads the mirror, never the Keychain" "$WORK/composer.nc" \
      'providers: AgentKey\.configured'
guard "the foot reads the mirrored key list" "$WORK/composer.nc" \
      'providers: configuredAgents'
mirror_writes=$(grep -c 'configuredAgents = ' "$WORK/composer.nc")
if [[ $mirror_writes -lt 3 ]]; then
  print -u2 "  ✗ drift: the key mirror is written $mirror_writes times, expected at least 3"
  exit 1
fi
print "  ok   the key mirror refreshes at the raise and both settles"

# ---- THE VERB IS WHATEVER IS AVAILABLE ----------------------------------
# A dim Send with nothing to send is the dead control §83 bans. At rest the
# slot carries Record — the voice-note capture path, a thing that really enters
# the corpus — which is also how the mic keeps its door without taking a key.
guard "the resting verb is the mic, not a dead send" "$WORK/composer.flat" \
      'AgentWideKey\(glyph: "mic", tone: .ink, compact: true\)'
guard "a live ask offers Stop" "$WORK/composer.nc" \
      'AgentWideKey\(title: String\(localized: "Stop"\)'
# FIND IS OFFERED ON THE DEVICE ALONE. Bankr cannot search your things, so a
# Find key beside it would be a control that provably does nothing.
guard "Find is gated on the device being the destination" "$WORK/composer.flat" \
      'if activeAskAgent == nil \{ AgentWideKey\(glyph: "magnifyingglass"'
# NO RETRY ON A LIVE JOB (§580): a second identical job on an agent that can act
# can act twice.
SLOT=$(awk '/private var footSlot/,/^    }$/' "$WORK/composer.nc")
print -r -- "$SLOT" | grep -qiE 'retry|resend' \
  && { print -u2 "  ✗ drift: the foot offers a retry — a live job must never be re-sent"; exit 1 }
print "  ok   the foot offers no retry"

# ---- A STOP LEAVES NO TOMBSTONE (prd §580) ------------------------------
guard "stop and edit are one withdrawal with two answers about your words" \
      "$WORK/composer.nc" 'if keepingWords \{'
WITHDRAW=$(awk '/private func withdrawAsk/,/^    }$/' "$WORK/composer.nc")
print -r -- "$WITHDRAW" | grep -q 'Insight' \
  && { print -u2 "  ✗ drift: a withdrawal settles a card — the tombstone the user called weird"; exit 1 }
print "  ok   a withdrawal leaves no tombstone"

# ---- THE ANSWER IS THE SCREEN (prd §581) --------------------------------
# The question folds to a caption and the reply's first sentence takes the
# display rung. The user's verdict on every version before this one was that
# the text "blends into the question and bankr name" — three things in one
# voice with only size between them.
guard "the question is a caption, not a heading" "$WORK/composer.nc" \
      'AgentAskedCaption\(question:'
guard "a written reply is set rather than poured" "$WORK/composer.nc" \
      'AgentReply\.prose\(els\)'
guard "the lead takes the display rung" "$WORK/terminal.nc" \
      'dsText\(.price40\)'
guard "the rest steps down to reading size" "$WORK/terminal.nc" \
      'dsText\(.heading22\)'
# A DOCUMENT KEEPS ITS ROWS. `AgentReply.prose` recognises one shape and
# returns nil for everything else; a false positive would delete content.
guard "a document still renders through GenRender" "$WORK/composer.nc" \
      'GenRender\(id: "root", els: els\)'
guard "prose is recognised only as a lone Insight" "$WORK/reply.nc" \
      'only.comp == "Insight"'
guard "a growing document is never mistaken for prose" "$WORK/reply.nc" \
      'els.count == 2'

# ---- THE ROLL, NOT A THREAD (prd §581) ----------------------------------
# Answers sit on one column in order, newest at the bottom, separated by dated
# rules. No bubbles and no alternating sides — and no sheet, because a sheet
# over a surface that itself rose from a button reads as a stack of trays.
guard "the roll dates the rule between answers" "$WORK/composer.nc" \
      'AgentTurnDivider\(landed:'
guard "a turn knows when it landed" "$WORK/composer.nc" \
      'var landedAt = Date\(\)'
guard_absent "no sheet of earlier questions returns" "$WORK/composer.nc" \
      'private var earlierSheet'

# ---- THE RETIRED CHROME STAYS RETIRED (prd §581) ------------------------
# Each of these was a part added to fix the chat, and together they were the
# confusion. A return needs an argument, not an omission.
for dead in draftCrown keptAskPills takeChips briefNav agentChoiceHeader \
            askWorking askConsole waitPaper sendPill lowerButton micButton \
            turnHeader turnDisc clockGreeting inputBar; do
  guard_absent "the retired $dead stays deleted" "$WORK/composer.nc" \
        "private (var|func) ${dead}[^A-Za-z0-9_]"
done
guard_absent "the 158pt deck stays deleted" "$WORK/composer.nc" \
      'AskDestinationRail\('
guard_absent "the ask capsule stays deleted" "$WORK/composer.nc" \
      'AskDestinationCapsule\('
[[ -e Casberi/Casberi/Shell/AskDestinationRail.swift ]] \
  && { print -u2 "  ✗ drift: the deck's file is back"; exit 1 }
[[ -e Casberi/Casberi/Shell/AskDestinationCapsule.swift ]] \
  && { print -u2 "  ✗ drift: the capsule's file is back"; exit 1 }
print "  ok   both retired picker files stay deleted"

# ---- THE BLUE GROUND IS GONE (prd §581) ---------------------------------
# §577 turned the whole surface `DS.tint` while a keyed ask was out; §577b
# pulled it back to the wait after "we really went overkill with all this
# blue". The one saturated block left is the armed verb, which is §563's budget
# spent on something you can act on.
guard_absent "nothing paints the surface blue" "$WORK/composer.nc" \
      'chrome.askOnTint = (now|true)'
guard "the tint flag is written false so no stale blue is left behind" \
      "$WORK/composer.nc" 'chrome.askOnTint = false'

print "  ok   AskDestination — 16 mutations, 47 drift guards"