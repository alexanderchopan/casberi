#!/bin/zsh
# Disk sweep — the nightly's first step (2026-11-01, user: "why does it build
# up so fast and can we clean it daily as part of the nightly").
#
# WHY IT BUILDS UP. Every Claude session and worktree builds into its OWN
# DerivedData (~3.5 GB each, several a day), every App Store upload leaves a
# 330–590 MB `XcodeDistPipeline.*` in the user temp dir that nothing removes
# (~80 of them on 11-01), and the main simulator's lock-screen poster cache
# regrows to 7+ GB within a week. verify.sh's own sweep reaches only the build
# caches, only past two days, and only when someone runs verify — twelve
# hand sweeps (memory: deriveddata-fills-the-disk) found the disk at 3–60 GB
# free each time.
#
# What it removes, each only past the age floor (DISK_SWEEP_DAYS, default 1):
#   1. build caches — any dir that PROVES it is DerivedData (`Build/` plus
#      `info.plist` or `Logs/`) under ~/Library/Developer, Xcode/DerivedData,
#      /private/tmp, /private/tmp/claude-501 and inside session scratchpads.
#      Only the cache, never the scratchpad around it: a session's notes and
#      worktrees stay. The proof is what keeps a checkout safe — a worktree
#      named `casberi-ship-wt` matches every name glob and has neither.
#   2. upload temp — `XcodeDistPipeline.*`.
#   3. simulators — unavailable devices; the poster cache of a SHUT-DOWN
#      device over 1 GB (it regenerates); a runtime with no devices that has
#      not booted in a week (iOS 18.6 re-downloaded itself twice).
#   4. worktrees — CLEAN ones idle three days, via `git worktree remove`,
#      which refuses a dirty tree on its own. Every repo under ~/Developer.
#   5. caches — `brew cleanup`, and the macOS screensaver videos (they
#      re-download on demand).
#
# Never touched: the five fixed dirs below, by ABSOLUTE PATH (a stray sharing
# a keeper's name has happened), the newest `Casberi-*`, anything a running
# process names in its arguments (an `xcodebuild -derivedDataPath` in flight),
# dirty worktrees, documents, Claude transcripts.
#
# Age is the NEWEST mtime among the dir and what a build writes into, not the
# dir's own: rewriting a file does not touch its parent, so a warm dir rebuilt
# daily can carry a months-old stamp. `zstat`, never `find -mtime` (bfs).
#
#   scripts/disk-sweep.sh             sweep, append a row to scripts/output/disk-sweep.log
#   scripts/disk-sweep.sh --dry-run   say what would go
#   scripts/disk-sweep.sh --self-test fixtures: what must go goes, what must stay stays
#
# REPORTS, NEVER FAILS (outside --self-test): housekeeping must not redden a
# nightly that had nothing to do with disk.
set -uo pipefail
zmodload -F zsh/stat b:zstat
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=${1:-}

LIBDEV=${DISK_SWEEP_LIBDEV:-$HOME/Library/Developer}
TMPROOT=${DISK_SWEEP_TMP:-/private/tmp}
USERTMP=${DISK_SWEEP_USERTMP:-$(getconf DARWIN_USER_TEMP_DIR)}
USERTMP=${USERTMP%/}
ONLY=${DISK_SWEEP_ONLY:-}          # "files": the filesystem arms alone (self-test)
LEDGER=${DISK_SWEEP_LEDGER:-$ROOT/scripts/output/disk-sweep.log}
DAYS=${DISK_SWEEP_DAYS:-1}
CUTOFF=$(( $(date +%s) - DAYS * 86400 ))
WT_CUTOFF=$(( $(date +%s) - 3 * 86400 ))
RUNTIME_CUTOFF=$(( $(date +%s) - 7 * 86400 ))

typeset -a KEEP
KEEP=("$LIBDEV/CasberiDD" "$LIBDEV/CasberiCatalystDD" "$LIBDEV/CasberiMacDD"
      "$LIBDEV/CasberiReleaseDD" "$LIBDEV/CasberiReleaseDDMac"
      "$(ls -dt "$LIBDEV/Xcode/DerivedData"/Casberi-*(N/) 2>/dev/null | head -1)")
[[ -n ${DISK_SWEEP_KEEP:-} ]] && KEEP+=("${DISK_SWEEP_KEEP%/}")   # a caller's own fixed dir (verify.sh's $DD)

FREED=0
typeset -a SWEPT

newest_mtime() {
  local d=$1 p t newest=0
  for p in "$d" "$d/info.plist" "$d/Build" "$d/Build/Products" "$d/Build/Intermediates.noindex" \
           "$d/Logs" "$d/Logs/Build" "$d/Index.noindex" "$d/ModuleCache.noindex"; do
    [[ -e $p ]] || continue
    t=$(zstat +mtime "$p" 2>/dev/null) || continue
    (( t > newest )) && newest=$t
  done
  print -r -- $newest
}

is_dd() { [[ -d $1/Build && ( -e $1/info.plist || -d $1/Logs ) ]] }

in_use() { pgrep -f -- "$1" >/dev/null 2>&1 }

remove() {                         # remove <arm> <path>
  local arm=$1 d=${2%/} kb
  kb=$(du -sk "$d" 2>/dev/null | cut -f1); kb=${kb:-0}
  if [[ $MODE == --dry-run ]]; then
    print -r -- "would remove| $arm | $d | $(( kb / 1024 )) MB"
  else
    rm -rf "$d" 2>/dev/null || { chmod -R u+w "$d" 2>/dev/null; rm -rf "$d" 2>/dev/null; } || return
    [[ -e $d ]] && return
  fi
  SWEPT+=("$arm:${d:t}")
  (( FREED += kb ))
}

sweep_build_caches() {
  local d
  typeset -aU cand
  cand=("$LIBDEV"/*(N/) "$LIBDEV/Xcode/DerivedData"/*(N/) "$TMPROOT"/*(N/) "$TMPROOT/claude-501"/*(N/))
  # Inside a session scratchpad: <project>/<session>/… up to three levels down.
  cand+=("$TMPROOT/claude-501"/*/*/{,*/,*/*/,*/*/*/}Build(N/:h))
  for d in $cand; do
    d=${d%/}
    [[ -n "${KEEP[(r)$d]:-}" ]] && continue
    is_dd "$d" || continue
    (( $(newest_mtime "$d") < CUTOFF )) || continue
    in_use "$d" && continue
    remove build "$d"
  done
}

sweep_upload_temp() {
  local d
  for d in "$USERTMP"/XcodeDistPipeline.*(N/); do
    (( $(zstat +mtime "$d") < CUTOFF )) || continue
    in_use "$d" && continue
    remove upload "$d"
  done
}

sweep_simulators() {
  local before=$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(')
  if (( before > 0 )) && [[ $MODE != --dry-run ]]; then
    xcrun simctl delete unavailable >/dev/null 2>&1 && SWEPT+=("sim:$before unavailable")
  fi
  local udid state poster
  xcrun simctl list devices -j 2>/dev/null | python3 -c '
import json,sys
for r,v in json.load(sys.stdin)["devices"].items():
  for x in v: print(x["udid"], x["state"])' | while read -r udid state; do
    poster="$LIBDEV/CoreSimulator/Devices/$udid/data/Library/Application Support/PRBPosterExtensionDataStore"
    [[ $state == Shutdown && -d $poster ]] || continue
    (( $(du -sk "$poster" | cut -f1) > 1048576 )) || continue
    remove poster "$poster"
  done
  local id
  xcrun simctl runtime list -j 2>/dev/null | RC=$RUNTIME_CUTOFF python3 -c '
import json,sys,os,subprocess,datetime
devs=json.loads(subprocess.run(["xcrun","simctl","list","devices","-j"],capture_output=True,text=True).stdout)["devices"]
busy={k for k,v in devs.items() if v}
cut=int(os.environ["RC"])
for k,r in json.load(sys.stdin).items():
  if not r.get("deletable") or r.get("runtimeIdentifier") in busy: continue
  t=r.get("lastUsedAt")
  if t and datetime.datetime.fromisoformat(t.replace("Z","+00:00")).timestamp()>=cut: continue
  print(k, r.get("version"), r.get("sizeBytes",0))' | while read -r id ver bytes; do
    if [[ $MODE == --dry-run ]]; then
      print -r -- "would remove| runtime | iOS $ver | $(( bytes / 1048576 )) MB"
    else
      xcrun simctl runtime delete "$id" >/dev/null 2>&1 || continue
    fi
    SWEPT+=("runtime:iOS $ver"); (( FREED += bytes / 1024 ))
  done
}

sweep_worktrees() {
  local repo w gitdir t idx
  for repo in "$HOME/Developer"/*/.git(N/:h); do
    git -C "$repo" worktree prune 2>/dev/null
    git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while read -r w; do
      [[ $w == "$repo" || ! -d $w ]] && continue
      [[ -z "$(git -C "$w" status --porcelain 2>/dev/null)" ]] || continue
      gitdir=$(git -C "$w" rev-parse --absolute-git-dir 2>/dev/null) || continue
      t=$(zstat +mtime "$w"); idx=$(zstat +mtime "$gitdir/index" 2>/dev/null || print 0)
      (( idx > t )) && t=$idx
      (( t < WT_CUTOFF )) || continue
      in_use "$w" && continue
      if [[ $MODE == --dry-run ]]; then
        print -r -- "would remove| worktree | $w"; continue
      fi
      local kb=$(du -sk "$w" 2>/dev/null | cut -f1)
      git -C "$repo" worktree remove "$w" 2>/dev/null || continue
      SWEPT+=("worktree:${w:t}"); (( FREED += ${kb:-0} ))
    done
  done
}

sweep_caches() {
  local aerials="$HOME/Library/Application Support/com.apple.wallpaper/aerials"
  if [[ -d $aerials ]] && (( $(du -sk "$aerials" | cut -f1) > 1048576 )); then
    remove aerials "$aerials"
  fi
  if [[ $MODE != --dry-run ]] && command -v brew >/dev/null; then
    local kb=$(brew cleanup -s --prune=7 2>/dev/null | grep -oE 'freed approximately [0-9.]+[KMG]B' | grep -oE '[0-9.]+[KMG]')
    [[ -n $kb ]] && SWEPT+=("brew:${kb}B")
  fi
}

# ── self-test ──────────────────────────────────────────────────────────────
if [[ $MODE == --self-test ]]; then
  T=$(mktemp -d); trap 'kill $HOLD 2>/dev/null; rm -rf "$T"' EXIT
  OLD=$(date -v-3d +%Y%m%d%H%M)
  mkdd() { mkdir -p "$1/Build/Products" "$1/Logs/Build"; : > "$1/info.plist"; }
  age() { find "$1" -exec touch -t "$OLD" {} + ; }
  L=$T/lib; P=$T/tmp; U=$T/utmp
  mkdd "$L/Xcode/DerivedData/Casberi-old";       age "$L/Xcode/DerivedData/Casberi-old"
  mkdd "$L/Xcode/DerivedData/Casberi-warm";      age "$L/Xcode/DerivedData/Casberi-warm"
  : > "$L/Xcode/DerivedData/Casberi-warm/Logs/Build/today.xcactivitylog"      # rebuilt today
  mkdd "$L/Xcode/DerivedData/Casberi-newest"                                  # the live keeper
  mkdd "$L/CasberiDD";                           age "$L/CasberiDD"           # fixed keeper
  mkdd "$L/CasberiOneOffDD";                     age "$L/CasberiOneOffDD"
  mkdir -p "$P/casberi-ship-wt/Casberi"; : > "$P/casberi-ship-wt/.git"; age "$P/casberi-ship-wt"
  mkdir -p "$P/repo-with-build/Build"; : > "$P/repo-with-build/README"; age "$P/repo-with-build"
  mkdd "$P/casberi-perf-dd";                     age "$P/casberi-perf-dd"
  mkdd "$P/casberi-building-dd";                 age "$P/casberi-building-dd"
  mkdd "$P/casberi-callers-dd";                  age "$P/casberi-callers-dd"   # DISK_SWEEP_KEEP
  mkdd "$P/claude-501/proj/sess/scratchpad/dd";  : > "$P/claude-501/proj/sess/scratchpad/notes.md"
  age "$P/claude-501/proj/sess"
  mkdd "$P/claude-501/loose-dd";                 age "$P/claude-501/loose-dd"
  mkdir -p "$U/XcodeDistPipeline.~~~old" "$U/XcodeDistPipeline.~~~new"; age "$U/XcodeDistPipeline.~~~old"
  zsh -c 'sleep 60; :' "$P/casberi-building-dd" & HOLD=$!                         # a build in flight
  sleep 0.3
  DISK_SWEEP_LIBDEV=$L DISK_SWEEP_TMP=$P DISK_SWEEP_USERTMP=$U DISK_SWEEP_ONLY=files DISK_SWEEP_KEEP=$P/casberi-callers-dd/ \
    DISK_SWEEP_LEDGER=/dev/null zsh "$0" >/dev/null 2>&1
  fails=0
  gone() { [[ ! -e $1 ]] || { print -r -- "✗ should be swept: ${1#$T/}"; (( fails++ )); } }
  kept() { [[ -e $1 ]] || { print -r -- "✗ should be kept: ${1#$T/}"; (( fails++ )); } }
  gone "$L/Xcode/DerivedData/Casberi-old"
  gone "$L/CasberiOneOffDD"
  gone "$P/casberi-perf-dd"
  gone "$P/claude-501/proj/sess/scratchpad/dd"
  gone "$P/claude-501/loose-dd"
  gone "$U/XcodeDistPipeline.~~~old"
  kept "$L/Xcode/DerivedData/Casberi-warm"
  kept "$L/Xcode/DerivedData/Casberi-newest"
  kept "$L/CasberiDD"
  kept "$P/casberi-ship-wt"
  kept "$P/repo-with-build/Build"
  kept "$P/casberi-building-dd"
  kept "$P/casberi-callers-dd"
  kept "$P/claude-501/proj/sess/scratchpad/notes.md"
  kept "$U/XcodeDistPipeline.~~~new"
  (( fails == 0 )) && { print -r -- "✓ disk-sweep self-test: 6 swept, 9 kept"; exit 0; }
  exit 1
fi

# ── sweep ──────────────────────────────────────────────────────────────────
free_gb() { df -g "$TMPROOT" 2>/dev/null | awk 'NR==2{print $4}'; }
BEFORE=$(free_gb)
sweep_build_caches
sweep_upload_temp
if [[ $ONLY != files ]]; then
  sweep_simulators
  sweep_worktrees
  sweep_caches
fi
AFTER=$(free_gb)

GB=$(( FREED / 1048576 ))
if (( FREED >= 1048576 )); then SIZE="~${GB} GB"; else SIZE="$(( FREED / 1024 )) MB"; fi
print -r -- "disk-sweep| freed ${SIZE} in ${#SWEPT} item(s); free ${BEFORE} → ${AFTER} GB (df lags after a sim delete)"
(( ${#SWEPT} )) && print -r -- "  ${SWEPT[*]}"
if [[ $MODE != --dry-run ]]; then
  mkdir -p "${LEDGER:h}" 2>/dev/null
  print -r -- "$(date +%Y-%m-%dT%H:%M:%S)  freed=${GB}GB  items=${#SWEPT}  free=${BEFORE}->${AFTER}GB" >> "$LEDGER" 2>/dev/null
fi
exit 0
