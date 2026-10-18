#!/bin/zsh
# Casberi unfollow-prune self-test (prd §1411) — the unwatch tombstone outlives
# the pass that may still be landing the wallet's rows.
#
# The bug (measured 2026-10-18): follow vitalik.eth, unfollow two minutes in,
# and the Safe sync that the follow started landed 22 rows (four "Your turn")
# AFTER the unfollow's prune — under an address nothing remembered any more,
# because that prune had consumed the unwatched queue and the name's
# resolution. Needs you listed a stranger's signatures under no wallet at all.
#
# Three drift guards over the shipped sources, each proven live by a mutation
# the guard must catch:
#   1. `FollowPrune.pruneUnwatchedWallets` consumes the queue only between
#      passes — `forgetUnwatched` stands under the `isRefreshing`/`isSweeping`
#      gate.
#   2. `WalletIngest.refresh` ends with its own prune, declared BEFORE
#      `defer { running = false }` so it runs after the flag clears and the
#      prune consumes.
#   3. `SafeBridge.backgroundSweep` ends the same way.
set -euo pipefail
cd "$(dirname "$0")/.."

INGEST="Casberi/Casberi/Model/WalletIngest.swift"
SAFE="Casberi/Casberi/Model/SafeBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
for f in "$INGEST" "$SAFE" "$SUPPORT"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

TMP=$(mktemp -d /tmp/unfollow-prune-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Strip // comments so a guard never passes on prose.
bare() { sed -E 's#//.*$##' "$1"; }

# The prune's gate: the first `forgetUnwatched(` inside pruneUnwatchedWallets
# must follow an `isRefreshing` + `isSweeping` test, in that function.
check_gate() {
  local body
  body=$(bare "$1" | awk '/static func pruneUnwatchedWallets\(/{f=1} f{print} f&&/^    }$/{exit}')
  [[ -n "$body" ]] || return 1
  local gate forget
  gate=$(print -r -- "$body" | grep -n 'isRefreshing' | grep 'isSweeping' | head -1 | cut -d: -f1)
  forget=$(print -r -- "$body" | grep -n 'forgetUnwatched(' | head -1 | cut -d: -f1)
  [[ -n "$gate" && -n "$forget" && "$gate" -lt "$forget" ]]
}

# A pass's closing prune: inside the named function, a
# `defer { FollowPrune.pruneUnwatchedWallets(` BEFORE `defer { running = false }`.
check_closing() {
  local body
  body=$(bare "$1" | awk -v fn="$2" 'index($0, "static func " fn "("){f=1} f{print} f&&/^    }$/{exit}')
  [[ -n "$body" ]] || return 1
  local prune clear
  prune=$(print -r -- "$body" | grep -n 'defer { FollowPrune.pruneUnwatchedWallets(context: context) }' | head -1 | cut -d: -f1)
  clear=$(print -r -- "$body" | grep -n 'defer { running = false }' | head -1 | cut -d: -f1)
  [[ -n "$prune" && -n "$clear" && "$prune" -lt "$clear" ]]
}

check_gate "$SUPPORT" \
  || { echo "✗ pruneUnwatchedWallets consumes the unwatched queue while a pass may still be landing — forgetUnwatched must stand under the isRefreshing/isSweeping gate (§1411)"; exit 1; }
echo "  ✓ the prune consumes the queue only between passes"
check_closing "$INGEST" "refresh" \
  || { echo "✗ WalletIngest.refresh does not end with its own prune ahead of 'defer { running = false }' (§1411)"; exit 1; }
echo "  ✓ the transfer pass ends with its own prune"
check_closing "$SAFE" "backgroundSweep" \
  || { echo "✗ SafeBridge.backgroundSweep does not end with its own prune ahead of 'defer { running = false }' (§1411)"; exit 1; }
echo "  ✓ the Safe sweep ends with its own prune"
grep -q 'static var isRefreshing: Bool { running }' "$INGEST" \
  || { echo "✗ WalletIngest.isRefreshing no longer reads the running flag (§1411)"; exit 1; }
grep -q 'static var isSweeping: Bool { running }' "$SAFE" \
  || { echo "✗ SafeBridge.isSweeping no longer reads the running flag (§1411)"; exit 1; }
echo "  ✓ both flags are read off the passes' own running state"

# ── Mutations: each must be caught, and each must have changed the file. ──
mutate() { # $1 src, $2 perl expression, $3 out
  perl -0pe "$2" "$1" > "$3"
  if cmp -s "$1" "$3"; then echo "✗ mutation changed nothing: $2"; exit 1; fi
}
# 1. The gate removed: forgetUnwatched runs unconditionally again.
mutate "$SUPPORT" 's/if !WalletIngest\.isRefreshing && !SafeBridge\.isSweeping \{\n(\s*store\.forgetUnwatched\(forms\))\n\s*\}/$1/' "$TMP/support-1.swift"
check_gate "$TMP/support-1.swift" && { echo "✗ mutation 1 survived: the gate is not guarded"; exit 1; }
# 2. The transfer pass's defers swapped: the prune runs while running is still true.
mutate "$INGEST" 's/(        defer \{ FollowPrune\.pruneUnwatchedWallets\(context: context\) \}\n)(        defer \{ running = false \}\n)/$2$1/' "$TMP/ingest-2.swift"
check_closing "$TMP/ingest-2.swift" "refresh" && { echo "✗ mutation 2 survived: the defers' order is not guarded"; exit 1; }
# 3. The transfer pass's closing prune deleted.
mutate "$INGEST" 's/        defer \{ FollowPrune\.pruneUnwatchedWallets\(context: context\) \}\n//' "$TMP/ingest-3.swift"
check_closing "$TMP/ingest-3.swift" "refresh" && { echo "✗ mutation 3 survived: a pass with no closing prune passes"; exit 1; }
# 4. The Safe sweep's defers swapped.
mutate "$SAFE" 's/(        defer \{ FollowPrune\.pruneUnwatchedWallets\(context: context\) \}\n)(        defer \{ running = false \}\n)/$2$1/' "$TMP/safe-4.swift"
check_closing "$TMP/safe-4.swift" "backgroundSweep" && { echo "✗ mutation 4 survived: the sweep's defer order is not guarded"; exit 1; }
echo "  ✓ 4 mutations caught"

echo "ALL PASS — the unwatch tombstone outlives the pass (prd §1411)"
