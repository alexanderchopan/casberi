#!/bin/zsh
# repo-sync-selftest.sh — prove scripts/repo-sync.sh both ACTS and REFUSES.
#
# The whole value of repo-sync.sh is a pair of opposite behaviours, and either
# one failing silently is the bug it was written to end: it must fast-forward a
# clean stale copy (or the drift it exists to stop just continues), and it must
# keep its hands off a tree that somebody is editing (or it becomes the thing
# that eats a session's uncommitted work). A script that only ever did one of
# those would look fine in casual use.
#
# Runs against throwaway clones in a temp dir. Touches nothing real.

set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/repo-sync.sh"
PASS=0 FAIL=0
ok()   { print -P "  %F{green}✓%f $1"; ((PASS++)) }
bad()  { print -P "  %F{red}✗%f $1"; ((FAIL++)) }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# An "origin" with one commit, and a clone of it standing in for the working copy.
fresh() {
  rm -rf "$TMP/up" "$TMP/wc"
  git init -q --bare "$TMP/up"
  git init -q "$TMP/seed" 2>/dev/null
  # TWO tracked files on purpose: `advance` only ever touches f.txt, so g.txt
  # is a tracked file an incoming commit leaves alone — which is what case 2
  # needs to test this script's guard rather than git's conflict refusal.
  (cd "$TMP/seed" && git checkout -q -b main \
     && echo one > f.txt && echo untouched > g.txt && git add f.txt g.txt \
     && git -c user.email=t@t -c user.name=t commit -qm one \
     && git remote add origin "$TMP/up" && git push -q origin main) >/dev/null 2>&1
  git clone -q "$TMP/up" "$TMP/wc" >/dev/null 2>&1
  rm -rf "$TMP/seed"
}
# Land one more commit on the bare remote, so the clone is behind by one.
advance() {
  rm -rf "$TMP/push"; git clone -q "$TMP/up" "$TMP/push" >/dev/null 2>&1
  (cd "$TMP/push" && echo two >> f.txt \
     && git -c user.email=t@t -c user.name=t commit -qam two && git push -q origin main) >/dev/null 2>&1
  rm -rf "$TMP/push"
}
run() { CASBERI_REPO="$TMP/wc" zsh "$SCRIPT" >/dev/null 2>&1 }
head_of() { git -C "$TMP/wc" rev-parse HEAD }

print "repo-sync self-test"

# 1 · the point of the thing: a clean copy that is behind catches up.
fresh; advance
BEFORE="$(head_of)"; run
if [[ "$(head_of)" != "$BEFORE" ]] && [[ "$(git -C "$TMP/wc" rev-list --count main..origin/main)" == 0 ]]; then
  ok "a clean copy that is behind is fast-forwarded"
else
  bad "a clean copy that is behind was NOT fast-forwarded — the drift continues"
fi

# 2 · the opposite, and the one that would cost real work: a dirty tree is
#     left exactly as it is, including the uncommitted edit itself.
#
#     The edit is to a file the incoming commit does NOT touch, and that is the
#     whole point of the case. Dirty the SAME file and git's own "would be
#     overwritten by merge" refusal saves the tree whether this script has a
#     guard or not — the check then passes with the guard deleted, which is a
#     check that certifies nothing. On a file git sees no conflict in, a
#     fast-forward succeeds happily and moves every other file under the
#     session that is mid-edit. Only this script's own guard stops that.
fresh; advance
print -r -- "a session was typing this" > "$TMP/wc/g.txt"
BEFORE="$(head_of)"; run
if [[ "$(head_of)" == "$BEFORE" ]] && [[ "$(cat "$TMP/wc/g.txt")" == "a session was typing this" ]]; then
  ok "a dirty tree is refused, and the uncommitted edit survives untouched"
else
  bad "a dirty tree was moved or an uncommitted edit was lost"
fi

# 3 · local commits are a judgment call, never a silent rewrite.
fresh; advance
(cd "$TMP/wc" && echo mine >> h.txt && git add h.txt \
  && git -c user.email=t@t -c user.name=t commit -qm mine) >/dev/null 2>&1
BEFORE="$(head_of)"; run
if [[ "$(head_of)" == "$BEFORE" ]]; then
  ok "a branch with local commits is refused, not rebased"
else
  bad "a branch with local commits was moved — local work is at risk"
fi

# 4 · a fetch happens even when the tree cannot be touched, because the whole
#     failure mode was a stale copy that LOOKED current.
fresh; advance
print -r -- "dirty" > "$TMP/wc/f.txt"
run
if [[ "$(git -C "$TMP/wc" rev-list --count main..origin/main)" == 1 ]]; then
  ok "a refused run still fetched, so 'behind N' is now truthful"
else
  bad "a refused run did not fetch — git status still lies about the position"
fi

# 5 · in sync is a no-op that writes no ledger noise.
fresh
LOGF="$TMP/wc/.git/last-sync.log"; rm -f "$LOGF"; run
if [[ ! -s "$LOGF" ]]; then
  ok "an in-sync run logs nothing"
else
  bad "an in-sync run wrote to the ledger"
fi

# 6 · the refusal is REPORTED. A sync that quietly does nothing is exactly the
#     silence this replaces, so the ledger line is part of the contract.
fresh; advance
print -r -- "dirty" > "$TMP/wc/f.txt"
LOGF="$TMP/wc/.git/last-sync.log"; rm -f "$LOGF"; run
if grep -q "NOT fast-forwarded" "$LOGF" 2>/dev/null; then
  ok "a refusal says so in the ledger, with its reason"
else
  bad "a refusal was silent — indistinguishable from being in sync"
fi

print ""
if (( FAIL )); then print -P "%F{red}repo-sync-selftest: $FAIL failed, $PASS passed%f"; exit 1; fi
print -P "%F{green}repo-sync-selftest: OK — $PASS checks%f"
