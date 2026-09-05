#!/bin/zsh
# Casberi cloud-sync self-test — the SHIPPED sentence the Data tray draws about
# iCloud sync, plus the wiring around it (prd §607, 2026-09-04):
#
#   Casberi/Casberi/Model/CloudSyncReading.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS, and the reason here is as strong as any in this repo: **no
# check that exists can see this code run.** `verify-mac.sh` launches every run
# with `-storeScratch YES`, which bypasses the group container and the mirror
# entirely; the simulator has no second device to receive from; and every
# failure below renders as a perfectly ordinary settings row that a screenshot
# certifies as correct. That combination is exactly how the Catalyst
# group-container prefix bug ran for weeks with every Mac save landing in an
# in-memory store and every gate green.
#
# Each failure it catches is a sentence that is CONFIDENT AND WRONG on the one
# screen where the app makes a promise about somebody's data:
#
#   · "Synced just now" over a mirror that connected and exchanged nothing —
#     `.setup` is a succeeded event, so reading any success says this
#   · "Synced" to a person with one device, whose mirror has only ever SENT,
#     teaching them to expect an arrival that has not happened and then to read
#     its absence as a bug
#   · a stale "Received an hour ago" leading over a mirror that is failing NOW
#   · "Stays on this Mac" for a choice the person did not make, because the
#     guard turned sync off and said so only in a four-second flash
#   · "from your next launch" on a Mac, where closing the window is not
#     quitting — a phrase the reader believes they have already satisfied, so a
#     setting that is merely waiting reads as broken
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

READING="Casberi/Casberi/Model/CloudSyncReading.swift"
STATUS="Casberi/Casberi/Shell/CloudSyncStatus.swift"
GUARD="Casberi/Casberi/Shell/CloudSyncGuard.swift"
STORE="Casberi/Shared/SharedStore.swift"
SHEET="Casberi/Casberi/Screens/AccountDetailSheet.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
MACVERIFY="scripts/verify-mac.sh"
for f in "$READING" "$STATUS" "$GUARD" "$STORE" "$SHEET" "$PROBES" "$MACVERIFY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. Every one of these files
# DOCUMENTS the broken behaviour it replaced by naming it — `CloudSyncReading`
# quotes the old "Synced" sentence, `AccountDetailSheet` explains what
# `lastSuccessDate` used to do — so a guard grepping raw source fires against
# the prose explaining the fix (the Obsidian/Cursor lesson, and it caught this
# harness on its own first run).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$SHEET"  > "$TMP/sheet-bare.swift"
strip_comments "$STATUS" > "$TMP/status-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself.

# 1. The three directions stay APART. Collapsing them back to one date is the
#    original bug, and it is a one-line edit away at all times.
for t in setup import export; do
  grep -q "case .$t:" "$STATUS" \
    || { echo "✗ CloudSyncStatus no longer stamps .$t separately — the tray is back to reading any succeeded event, so '.setup' says 'Synced' over a mirror that has exchanged nothing"; exit 1; }
done
grep -q '@unknown default' "$STATUS" \
  || { echo "✗ the event switch lost its @unknown default — a new Apple event type would stamp nothing and the tray would go quiet with no way to tell it from a dead mirror"; exit 1; }

# 2. The sheet must ASK, never assemble. It used to build this sentence inline
#    off `lastSuccessDate`; a second copy of the decision is how the tray and
#    the probe start disagreeing about the same mirror.
grep -q 'CloudSyncStatus.line(engaged:' "$TMP/sheet-bare.swift" \
  || { echo "✗ the Data tray no longer reads CloudSyncStatus.line — the sentence has been re-assembled locally"; exit 1; }
grep -q 'lastSuccessDate' "$TMP/sheet-bare.swift" \
  && { echo "✗ the Data tray reads lastSuccessDate again — that is stamped by ANY succeeded event, '.setup' included, which is the exact bug §607 fixed"; exit 1; }

# 3. The Mac gets its own next-launch phrasing, and it must name the KEY.
#    Without ⌘Q the sentence tells a Mac user to do the thing they believe
#    closing the window already did.
grep -q '⌘Q' "$READING" \
  || { echo "✗ the Mac's relaunch sentence no longer names ⌘Q — on a Mac 'your next launch' is a phrase the reader believes they have already satisfied"; exit 1; }
grep -q 'macIdiom: ProcessInfo.processInfo.isMacCatalystApp' "$TMP/sheet-bare.swift" \
  || { echo "✗ the Data tray no longer passes the Mac idiom — the Mac would be told to wait for a launch it thinks it has performed"; exit 1; }

# 4. The guard's verdict is DURABLE. A four-second flash was the only notice,
#    after which the tray described the app's own decision as the person's
#    preference.
grep -q 'cloudGuardDisabledKey' "$STORE" \
  || { echo "✗ SharedStore no longer records that IT turned sync off — the tray would read 'Stays on <device>' for a choice nobody made"; exit 1; }
grep -q 'defaults.set(true, forKey: cloudGuardDisabledKey)' "$STORE" \
  || { echo "✗ the auto-disable no longer sets the durable flag"; exit 1; }
grep -q 'SharedStore.syncDisabledByGuard' "$TMP/sheet-bare.swift" \
  || { echo "✗ the Data tray no longer states the guard's verdict"; exit 1; }
grep -q 'if \$0 { SharedStore.syncDisabledByGuard = false }' "$TMP/sheet-bare.swift" \
  || { echo "✗ turning sync back on no longer retires the guard's notice — it would describe a situation that has ended"; exit 1; }

# 5. The THIRD proof of survival. Both original signals are events, and on a
#    Mac neither is reliable — a window left open never backgrounds, and the
#    mirror event only fires while sync is already working. Without a
#    time-based clear, any unrelated crash counts as a CloudKit trap and two of
#    them silently switch the person's sync off.
grep -q 'survivalProof' "$GUARD" \
  || { echo "✗ CloudSyncGuard lost its time-based proof of survival — on a Mac an unrelated crash counts as a CloudKit trap, and two switch sync off silently"; exit 1; }
grep -q 'try? await Task.sleep(for: survivalProof)' "$GUARD" \
  || { echo "✗ the survival timer no longer waits on survivalProof"; exit 1; }

# 6. The probe and the Mac gate. `-syncProbe` is the only instrument this
#    subsystem has ever had, and the Mac gate is the only automated check that
#    the group container resolves at all.
grep -q 'Hook(key: "syncProbe")' "$PROBES" \
  || { echo "✗ -syncProbe is gone — the sync path has no instrument again"; exit 1; }
grep -q 'syncProbe| group=.* resolved=YES' "$MACVERIFY" \
  || { echo "✗ verify-mac.sh no longer gates on the app-group container resolving — the ephemeral-store failure would ship again invisibly"; exit 1; }

echo "drift guards: all pass"

# --- assertions -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ok  \(label)") }
    else { print("  ✗   \(label)"); failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)
let mac = "this Mac", phone = "this iPhone"

func state(wants: Bool = true, engaged: Bool = true, err: Bool = false,
           imp: Date? = nil, exp: Date? = nil, setup: Date? = nil)
-> CloudSyncReading.State {
    .init(wantsSync: wants, engaged: engaged, hasLiveError: err,
          lastImport: imp, lastExport: exp, lastSetup: setup)
}
func line(_ s: CloudSyncReading.State, mac isMac: Bool = false) -> String {
    CloudSyncReading.line(state: s, deviceName: isMac ? mac : phone, macIdiom: isMac)
}

print("Off / not yet engaged")
// Off and not mirroring: the plain resting truth.
check("off and idle names the device",
      line(state(wants: false, engaged: false)).contains("Stays on \(phone)"))
// Off but STILL mirroring — the container binds once, so the flip is not live
// until a relaunch. Claiming it has stopped is the same lie the other way.
check("off while still engaged says it stops later",
      line(state(wants: false, engaged: true)).contains("Stops syncing"))
check("off while still engaged does NOT claim it already stopped",
      !line(state(wants: false, engaged: true)).contains("Stays on"))
// On but not engaged yet.
check("on and not engaged says it starts later",
      line(state(wants: true, engaged: false)).hasPrefix("Syncs"))

print("")
print("The Mac's own sentence")
// The whole reason `macIdiom` is threaded down here.
check("Mac names ⌘Q",
      line(state(wants: true, engaged: false), mac: true).contains("⌘Q"))
check("Mac does not say 'next launch'",
      !line(state(wants: true, engaged: false), mac: true).contains("next launch"))
check("phone still says 'next launch'",
      line(state(wants: true, engaged: false)).contains("next launch"))
check("the Mac wording applies to turning it OFF too",
      line(state(wants: false, engaged: true), mac: true).contains("⌘Q"))

print("")
print("Direction, which is the whole point")
// SETUP ALONE IS NOT AN EXCHANGE. This is the shipped bug: `.setup` is a
// succeeded event, so a tray reading any success said "Synced" here.
check("setup alone never claims a sync",
      line(state(setup: t0)) == "Connected — nothing exchanged yet")
check("setup alone is not reported as received",
      !line(state(setup: t0)).contains("Received"))
// SENT is not RECEIVED. Working perfectly for a one-device person, and saying
// "Synced" teaches them to expect an arrival that has not happened.
check("export alone says sent, and says nothing arrived",
      line(state(exp: t0, setup: t0)).contains("Sent")
      && line(state(exp: t0, setup: t0)).contains("nothing received yet"))
// The question the tray is actually opened to answer.
check("an import is what earns 'Received'",
      line(state(imp: t0, exp: t0, setup: t0)).hasPrefix("Received"))
check("an import outranks the export beside it",
      !line(state(imp: t0, exp: t0, setup: t0)).contains("Sent"))
// Nothing at all yet.
check("engaged with no event of any kind is honest about it",
      line(state()) == "Connecting to iCloud…")

print("")
print("Trouble outranks a timestamp")
// A mirror that received an hour ago and is failing now is FAILING; leading
// with the hour reads as health.
check("a live error beats a good import",
      line(state(err: true, imp: t0, exp: t0, setup: t0))
        == "Couldn't sync — will keep retrying")
check("a live error beats an export",
      line(state(err: true, exp: t0)).contains("Couldn't sync"))
// …but an error while the toggle is OFF is not the tray's business: the
// person asked for it to stop.
check("an error is not reported once sync is switched off",
      !line(state(wants: false, engaged: false, err: true)).contains("Couldn't"))

print("")
print("The guard's notice")
// It must not be mistakable for the person's own choice.
let notice = CloudSyncReading.guardNotice(deviceName: mac)
check("the guard notice says the app turned it off", notice.contains("turned itself off"))
check("the guard notice says nothing was lost", notice.contains("Nothing was lost"))
check("the guard notice names where the corpus is", notice.contains(mac))

print("")
if failures > 0 {
    print("cloud-sync-selftest: \(failures) FAILED")
    exit(1)
}
print("assertions: all pass")
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$READING" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped source:"
  cat "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# Each is a silent-wrong-answer this file exists to catch. A mutation the
# harness still passes means nothing was testing that behaviour.
#
# `-Onone`, not `-O`, and the reason is recorded in CLAUDE.md: 97% of a pure
# harness's wall time is `swiftc`, the optimizer buys nothing an assertion can
# see, and this file traps nowhere — probe with
# `scripts/support/harness-opt-probe.sh` before assuming that stays true.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$READING" "$target"
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
  if ! swiftc -Onone -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations"
# THE SHIPPED BUG: any succeeded event reads as a sync.
mutate "setup counts as an exchange" \
  'if state.lastSetup != nil { return String(localized: "Connected — nothing exchanged yet") }' \
  'if state.lastSetup != nil { return String(localized: "Received \(relative(state.lastSetup!))") }'
# Sent read as received — the one-device person told an arrival happened.
mutate "an export is reported as an arrival" \
  'return String(localized: "Sent \(relative(sent)) — nothing received yet")' \
  'return String(localized: "Received \(relative(sent))")'
# Stale good news leading over a live failure.
mutate "a live error stops outranking the timestamps" \
  'if state.hasLiveError { return String(localized: "Couldn'\''t sync' \
  'if state.hasLiveError, state.lastImport == nil { return String(localized: "Couldn'\''t sync'
# The Mac told to do the thing it believes it has done.
mutate "the Mac loses its own relaunch sentence" \
  'macIdiom
            ? String(localized: "\(verb) after you quit and reopen Casberi (⌘Q)")' \
  'false
            ? String(localized: "\(verb) after you quit and reopen Casberi (⌘Q)")'
# "It has already stopped" — false while the container is still mirroring.
mutate "turning it off claims to have stopped already" \
  'return state.engaged
                ? relaunchLine("Stops syncing", macIdiom: macIdiom)
                : String(localized: "Stays on \(deviceName)")' \
  'return String(localized: "Stays on \(deviceName)")'
# The half-states collapsed into one confident word, which is where this
# whole pass started.
mutate "every engaged state reads as synced" \
  'if let received = state.lastImport {' \
  'if true { let received = state.lastImport ?? Date() ;'

echo ""
echo "cloud-sync-selftest: PASS"
