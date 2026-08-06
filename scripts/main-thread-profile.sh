#!/bin/zsh
# Casberi main-thread profile — WHO is holding the main thread during the
# first seconds of a foreground (2026-08-06).
#
# WHY THIS EXISTS. The post-271 "laggy and latent" report survived three
# rounds of counters. Each round placed an instrument where the cost was
# *believed* to be, measured, and disproved the belief:
#
#   • the foreground bridge sweep  → A/B'd: 10 hitches vs 8, i.e. noise
#   • `.live` over the whole corpus → measured 18.7ms once, not seconds
#   • feed rebuild FREQUENCY        → cut 15 builds to 2; stall unchanged
#
# A counter can only ever answer about the place you already suspected, and
# after three misses the honest move is to stop guessing and ask the machine
# which stack is actually on the thread. That is a SAMPLING profile, and it is
# the same tool that found the last cost of this class here: `VerbDetection`'s
# own header records a `sample` run putting two `NSDataDetector` passes at ~21%
# of busy main-thread time, a cause nobody had suspected.
#
# WHAT IT MEASURES, exactly: `sample(1)` interrupts the process every ~1ms and
# records each thread's stack. A frame's SELF weight — samples where it was the
# innermost frame — is time actually spent in that function. Its INCLUSIVE
# weight is time spent in it or anything it called. Self weight names the cost;
# inclusive weight names the caller to blame. Both are printed, because either
# alone misleads: a hot leaf called from forty places is unfixable until you
# know the caller, and a fat caller says nothing about what to change.
#
# MAC CATALYST ONLY, and that is a real limit, stated rather than papered over:
# `sample` attaches to a macOS process, and an app on an iPhone is not one.
# The Mac build is the same SwiftUI/SwiftData/feed code against the same
# CloudKit corpus, so a stack that dominates here is worth fixing everywhere —
# but it is NOT proof about the phone, and AppKit/UIKit-on-Catalyst frames
# differ. For the phone the equivalent is Instruments; the command is printed
# at the end of a run rather than wrapped, because this file has no way to test
# it from here and an untested path that prints a confident empty report is
# exactly the failure this script exists to avoid.
#
# USAGE
#   scripts/main-thread-profile.sh              # launch cold, sample 12s
#   scripts/main-thread-profile.sh 20           # …for 20s
#   scripts/main-thread-profile.sh --attach     # sample the app already running
#   scripts/main-thread-profile.sh --self-test  # prove the summariser works
#
# Output: a ranked report to the terminal, plus the raw `sample` file kept at
# scripts/output/profile-<ts>.txt so a second opinion is always possible.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# ── the summariser ──────────────────────────────────────────────────────────
# Split out so `--self-test` can run it against a fixture. A profiler whose
# PARSER silently matches nothing prints "no hot spots" and reads as a healthy
# app — the §257 lesson in a new costume (perf.sh spent three weeks recording a
# launch climbing 293→763ms while its log predicate dropped the very markers
# the app was emitting). So the parser is tested against known input, and the
# test plants a hot frame it must find and idle frames it must not rank.
summarise() {  # summarise <sample-file>
python3 - "$1" <<'PY'
import re, sys, collections

path = sys.argv[1]
try:
    lines = open(path, errors="replace").read().splitlines()
except OSError as e:
    print(f"  cannot read {path}: {e}"); sys.exit(2)

# `sample` prints one "Call graph:" section, threads inside it. Matching the
# main thread by NAME rather than by "Thread_1", because thread order is not
# guaranteed and the first listed thread is regularly a worker.
#
# TWO SPELLINGS, and the second one cost a run: a macOS process labels it
#   8330 Thread_x   DispatchQueue_1: com.apple.main-thread  (serial)
# while an app hosted by the iOS SIMULATOR labels it
#   8330 Thread_x: Main Thread   DispatchQueue_<multiple>
# The first cut of this file knew only the macOS form, so the very first real
# iOS profile — the platform the bug was actually reported on — parsed to
# nothing. It failed loudly rather than printing an empty ranking, which is the
# one thing that saved it; both spellings are fixtured below now.
MAIN_MARKERS = ("com.apple.main-thread", ": Main Thread")
main_start = None
for i, ln in enumerate(lines):
    if any(m in ln for m in MAIN_MARKERS):
        main_start = i
        break
if main_start is None:
    print("  no main thread found in this sample — was the app running?")
    sys.exit(3)

base_indent = len(lines[main_start]) - len(lines[main_start].lstrip())
frames = []           # (depth, count, symbol, binary)
row = re.compile(r'^(?P<pad>[\s+!:|]*?)(?P<count>\d+)\s+(?P<sym>.+?)\s+\(in (?P<bin>[^)]+)\)')
plain = re.compile(r'^(?P<pad>[\s+!:|]*?)(?P<count>\d+)\s+(?P<sym>\S.*?)\s*$')

for ln in lines[main_start + 1:]:
    if not ln.strip():
        break                                  # blank line ends the thread block
    indent = len(ln) - len(ln.rstrip("\n")) + 0
    m = row.match(ln) or plain.match(ln)
    if not m:
        continue
    pad = m.group("pad")
    depth = len(pad)
    if depth <= base_indent and frames:
        break                                  # next thread
    sym = m.group("sym").strip()
    binary = m.groupdict().get("bin") or "?"
    frames.append((depth, int(m.group("count")), sym, binary))

if not frames:
    print("  main thread found but no frames parsed — the `sample` format may "
          "have changed; read the raw file before believing this.")
    sys.exit(3)

total = frames[0][1]

# SELF weight = a frame's own count minus the counts of its direct children.
# Direct children are the following frames at the next greater depth, until the
# depth returns to this frame's own or shallower.
self_w = collections.Counter()
incl_w = collections.Counter()
for i, (depth, count, sym, binary) in enumerate(frames):
    # DIRECT children only: the frames below this one at the first deeper
    # indent, stopping when the indent returns to this frame's own or
    # shallower. Summing every deeper frame instead would count grandchildren
    # twice and drive most self weights to zero — which reads as "nothing is
    # hot" rather than as a broken parser.
    kids, child_depth = 0, None
    for d2, c2, _, _ in frames[i + 1:]:
        if d2 <= depth:
            break
        if child_depth is None:
            child_depth = d2
        if d2 == child_depth:
            kids += c2
    key = (sym, binary)
    self_w[key] += max(0, count - kids)
    incl_w[key] = max(incl_w[key], count)

# Idle is not a finding. A main thread parked in the run loop waiting for an
# event is the HEALTHY state, and leaving it in would rank it first every time
# and bury everything real underneath it.
IDLE = ("mach_msg", "__CFRunLoopServiceMachPort", "kevent", "semaphore_wait",
        "__psynch_cvwait", "read", "select", "poll", "start_wqthread",
        "_dispatch_worker", "thread_start")
def idle(sym):
    return any(k in sym for k in IDLE)

busy = sum(c for (s, _), c in self_w.items() if not idle(s))
print(f"  samples on the main thread: {total}   busy (non-idle self): {busy}")
if busy == 0:
    print("  the main thread was idle for the whole window — it is not blocked; "
          "either nothing was happening, or sample the moment you SEE the lag.")
    sys.exit(0)

def show(title, counter, note):
    print(f"\n  {title}")
    print(f"  {note}")
    rows = [(c, s, b) for (s, b), c in counter.items() if not idle(s) and c > 0]
    rows.sort(reverse=True)
    if not rows:
        print("    (nothing)"); return
    for c, s, b in rows[:15]:
        pct = 100.0 * c / total if total else 0
        tag = "APP" if "Casberi" in b else "   "
        print(f"    {pct:5.1f}%  {c:6d}  {tag}  {s[:96]}")

show("HEAVIEST BY SELF TIME — what to actually make faster",
     self_w, "(samples where this function itself was running)")
show("HEAVIEST BY INCLUSIVE TIME — who to blame for calling it",
     incl_w, "(samples where this function was anywhere on the stack)")

app = [(c, s) for (s, b), c in self_w.items() if "Casberi" in b and not idle(s) and c > 0]
app.sort(reverse=True)
print("\n  OUR OWN CODE, by self time  (the actionable list)")
if app:
    for c, s in app[:15]:
        print(f"    {100.0*c/total:5.1f}%  {c:6d}  {s[:96]}")
else:
    print("    none — the cost is inside system frameworks; read the inclusive "
          "list above for the Casberi frame that called into them.")
PY
}

# ── self-test ───────────────────────────────────────────────────────────────
# A fixture in `sample`'s real shape, carrying: an idle main-thread branch that
# must NOT rank, a hot APP leaf that must rank first by self time, and a parent
# that must rank above it by INCLUSIVE time. If the parser drifts, this fails
# loudly instead of the script reporting a healthy app forever.
if [[ "${1:-}" == "--self-test" ]]; then
  WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/fixture.txt" <<'FIX'
Analysis of sampling Casberi (pid 123) every 1 millisecond
Call graph:
    1000 Thread_1   DispatchQueue_1: com.apple.main-thread  (serial)
      1000 start (in dyld) + 1  [0x1]
        1000 CasberiApp.main() (in Casberi) + 2  [0x2]
          400 mach_msg_trap (in libsystem_kernel.dylib) + 3  [0x3]
          600 FeedScreen.builtBody.getter (in Casberi) + 4  [0x4]
            600 VerbDerivation.placeURL(in:) (in Casberi) + 5  [0x5]
              500 NSDataDetector.firstMatch (in Foundation) + 6  [0x6]
    2000 Thread_2
      2000 _dispatch_worker_thread (in libdispatch.dylib) + 7  [0x7]
FIX
  print -r -- "self-test:"
  OUT="$(summarise "$WORK/fixture.txt")" || { print -r -- "  ✗ summariser exited non-zero"; exit 1; }
  fail=0
  chk() { if print -r -- "$OUT" | grep -qE "$2"; then print -r -- "  ✓ $1"; else print -r -- "  ✗ $1"; fail=1; fi }
  chk "reads the main thread's sample total (1000, not thread 2's 2000)" 'samples on the main thread: 1000'
  chk "the hot system leaf is found by self time"                        'NSDataDetector\.firstMatch'
  chk "our own frame is attributed to Casberi"                           'VerbDerivation\.placeURL'
  chk "the actionable app-only list is produced"                         'OUR OWN CODE'
  # The iOS-simulator thread label, which is spelled differently from macOS's
  # and which the first cut of this file could not find at all — so the first
  # real profile of the platform the bug was reported on parsed to nothing.
  cat > "$WORK/sim.txt" <<'FIX'
Analysis of sampling Casberi (pid 456) every 1 millisecond
Call graph:
    900 Thread_162091: Main Thread   DispatchQueue_<multiple>
    + 900 start_sim (in dyld_sim) + 20  [0x1]
    + ! 900 FeedScreen.feedList.getter (in Casberi) + 21  [0x2]
    + !   700 SwiftUI.ViewGraph.updateOutputs (in SwiftUI) + 22  [0x3]
    2000 Thread_162137: com.apple.uikit.eventfetch-thread
      2000 __NSThread__start__ (in Foundation) + 23  [0x4]
FIX
  SIM="$(summarise "$WORK/sim.txt")" || { print -r -- "  ✗ simulator-format sample not parsed"; exit 1; }
  if print -r -- "$SIM" | grep -q 'samples on the main thread: 900'; then
    print -r -- "  ✓ the iOS-simulator main-thread label is recognised"
  else
    print -r -- "  ✗ the iOS-simulator main-thread label is NOT recognised"; fail=1
  fi
  if print -r -- "$SIM" | grep -q 'ViewGraph.updateOutputs'; then
    print -r -- "  ✓ frames parse through the simulator's '+ !' tree prefixes"
  else
    print -r -- "  ✗ the simulator's '+ !' tree prefixes break frame parsing"; fail=1
  fi
  if print -r -- "$OUT" | grep -q 'mach_msg_trap'; then
    print -r -- "  ✗ idle frame was ranked (it must be excluded)"; fail=1
  else
    print -r -- "  ✓ the idle branch is excluded, not ranked first"
  fi
  # Self vs inclusive must DISAGREE here, or the two lists are one list and the
  # distinction the report is built on does not exist.
  selfblock="${OUT%%HEAVIEST BY INCLUSIVE*}"
  if print -r -- "$selfblock" | grep -q 'builtBody'; then
    print -r -- "  ✗ a pure-parent frame ranked by SELF time (self weight is wrong)"; fail=1
  else
    print -r -- "  ✓ a parent that only called others carries no self time"
  fi
  [[ $fail -eq 0 ]] && { print -r -- "main-thread-profile self-test: OK"; exit 0; }
  print -r -- "main-thread-profile self-test: FAILED"; exit 1
fi

# Re-read a raw file captured earlier (or on another machine) without
# sampling anything. This is how a `sample` someone else ran gets analysed —
# and it is what lets the parser be exercised against real output from any
# process, not just this app's.
if [[ "${1:-}" == "--summarise" || "${1:-}" == "--summarize" ]]; then
  [[ -n "${2:-}" && -f "${2:-}" ]] || { print -r -- "usage: $0 --summarise <raw-sample-file>"; exit 1; }
  summarise "$2"
  exit 0
fi

# ── run ─────────────────────────────────────────────────────────────────────
SECS=12
ATTACH=0
for a in "$@"; do
  case "$a" in
    --attach) ATTACH=1 ;;
    ''|*[!0-9]*) ;;
    *) SECS="$a" ;;
  esac
done

mkdir -p "$ROOT/scripts/output"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW="$ROOT/scripts/output/profile-$STAMP.txt"

pid_of() { pgrep -f "Casberi.app/Contents/MacOS/Casberi" | head -1; }

if [[ $ATTACH -eq 1 ]]; then
  PID="$(pid_of || true)"
  [[ -n "$PID" ]] || { print -r -- "✗ Casberi is not running — start it, or drop --attach to launch it"; exit 1; }
  print -r -- "attaching to running Casberi (pid $PID)"
else
  # Prefer whatever the person actually runs; fall back to a dev build.
  APP=""
  for cand in "/Applications/Casberi.app" \
              "$HOME/Applications/Casberi.app" \
              "$HOME/Library/Developer/CasberiDD/Build/Products/Debug-maccatalyst/Casberi.app"; do
    [[ -d "$cand" ]] && { APP="$cand"; break }
  done
  if [[ -z "$APP" ]]; then
    print -r -- "✗ no Mac Casberi.app found. Install the Mac TestFlight build, or build one:"
    print -r -- "    xcodebuild -project Casberi/Casberi.xcodeproj -scheme Casberi \\"
    print -r -- "      -destination 'platform=macOS,variant=Mac Catalyst' \\"
    print -r -- "      -derivedDataPath ~/Library/Developer/CasberiDD build"
    exit 1
  fi
  # `open -n`, never the binary directly: launching Contents/MacOS/Casberi runs
  # the process but the UI never mounts, so the profile would be of an app that
  # never drew a frame (verify-mac.sh's own measured finding).
  pkill -f "Casberi.app/Contents/MacOS/Casberi" 2>/dev/null || true
  sleep 1
  print -r -- "launching $APP"
  open -n "$APP"
  PID=""
  for _ in {1..40}; do
    PID="$(pid_of || true)"
    [[ -n "$PID" ]] && break
    sleep 0.25
  done
  [[ -n "$PID" ]] || { print -r -- "✗ launched but never appeared in the process list"; exit 1; }
  print -r -- "pid $PID — sampling the FIRST $SECS s, which is the window the report is about"
fi

# -mayDie so a crash mid-window still yields what it collected.
sample "$PID" "$SECS" -mayDie -file "$RAW" >/dev/null 2>&1 || {
  print -r -- "✗ sample failed. If macOS asked for permission, grant it and re-run."
  exit 1
}

print -r -- ""
print -r -- "── main thread, first ${SECS}s ────────────────────────────────"
summarise "$RAW"
print -r -- ""
print -r -- "raw sample kept at: ${RAW#$ROOT/}"
print -r -- ""
print -r -- "NOTE: this is Mac Catalyst. Same feed/SwiftData code and the same"
print -r -- "CloudKit corpus, but it is not proof about the phone. For an iPhone,"
print -r -- "profile with Instruments (UNTESTED from this script, so it is printed"
print -r -- "rather than run):"
print -r -- "    xcrun xctrace record --template 'Time Profiler' \\"
print -r -- "      --device <device-udid> --attach Casberi --time-limit ${SECS}s \\"
print -r -- "      --output profile.trace"
