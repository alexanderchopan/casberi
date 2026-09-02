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
strip_comments() { perl -pe 's{//.*$}{}' "$1"; }

COMPOSER="Casberi/Casberi/Shell/Composer.swift"
CAPSULE="Casberi/Casberi/Shell/AskDestinationCapsule.swift"
strip_comments "$COMPOSER" > "$WORK/composer.nc"
strip_comments "$CAPSULE"  > "$WORK/capsule.nc"

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

# The capsule is mounted, and it is mounted in the bar's control row.
guard "the capsule is in the composer's input bar" "$WORK/composer.nc" \
      'AskDestinationCapsule\('
# THE SEND BUTTON STAYS GONE. Its return is the confusion §543 removed: an
# unnamed arrow beside named agent segments makes the device the odd one out.
guard_absent "no send button returns to the bar" "$WORK/composer.nc" \
      'private var sendButton'
# NOTHING IS PREPOPULATED. Each of these was a door onto a document the field
# can ask for by name; a chip row growing back needs an argument against §543.
guard_absent "the launcher chips stay deleted" "$WORK/composer.nc" \
      'private var launcherChips'
guard_absent "the ask chips stay deleted" "$WORK/composer.nc" \
      'private var askChips'
guard_absent "the category chip row stays deleted" "$WORK/composer.nc" \
      'private var categoryChipsRow'
guard_absent "the day card stays deleted" "$WORK/composer.nc" \
      'private var dayCard'
# The kept pills are the ONE thing that may appear at rest — and they must,
# or "Keep" mints a standing question with nowhere to appear (§83).
guard "the kept pills are mounted at rest" "$WORK/composer.nc" \
      '^\s+keptAskPills\s*$'
# The greeting greets by name.
guard "the greeting uses the named clock greeting" "$WORK/composer.nc" \
      'Text\(clockGreeting\(\)\)'
guard_absent "the weekday greeting is not restored" "$WORK/composer.nc" \
      'Text\(timeGreeting\(\)\)'
# VOICE ANSWERS ON DEVICE. A voice note must never silently spend a key.
guard "the capsule stands its agents down while recording" "$WORK/capsule.nc" \
      'guard !recording else \{ return \(\[\], \[\]\) \}'
# THE FILL MARKS THE ACTIVE DESTINATION, not the usual one (2026-09-01). A
# device pill filled unconditionally names a destination the return key stops
# using the moment a conversation goes keyed.
guard "the capsule orders on the active destination" "$WORK/capsule.nc" \
      'active: active\?\.rawValue'
guard "the device segment fills only when it is the destination" "$WORK/capsule.nc" \
      'segment\(glyph: deviceGlyph, title: deviceLabel, filled: active == nil\)'
guard_absent "the device pill is never filled unconditionally" "$WORK/capsule.nc" \
      'filled: true'
guard "the answering agent's segment fills" "$WORK/capsule.nc" \
      'filled: provider == active'
# The capsule must never resolve the agent itself: `AgentKey.active` says which
# key a keyed answer would SPEND, not whether this conversation is keyed at
# all, so reading it here lights a segment for somebody who has only ever asked
# their phone — and costs a keychain read per keystroke of a follow-up.
guard_absent "the capsule does not read the active key itself" "$WORK/capsule.nc" \
      'AgentKey\.active'
guard "the composer names the destination for the capsule" "$WORK/composer.nc" \
      'active: activeAskAgent'
# In flight it is who is ANSWERING; settled it is where the next plain send
# goes — `commit`'s own `stayKeyed` term, spelled the same way so the fill and
# the routing can never disagree.
guard "the fill reads in-flight and settled state apart" "$WORK/composer.nc" \
      'inFlight \? keyedCurrent : \(conversationIsKeyed && keyAvailable\)'
# The device is never hardcoded in the view either.
guard_absent "the capsule does not hardcode a device name" "$WORK/capsule.nc" \
      '"(iPhone|iPad|Mac)"'
guard "the capsule asks the model for the device name" "$WORK/capsule.nc" \
      'AskDestination\.deviceLabel'
# A DOCUMENT opens at its top — §288's rule, extended to the wallet.
guard "the wallet answer is a document for the scroll anchor" "$WORK/composer.nc" \
      'WalletAsk\.matches\(currentQuestion\)'
guard "the anchor and the typewriter guard read the same term" "$WORK/composer.nc" \
      'documentInView'

print "  ok   AskDestination — 13 mutations, 22 drift guards"
