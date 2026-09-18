#!/bin/zsh
# repo-sync.sh — keep the canonical working copy current with origin/main.
#
# WHY THIS EXISTS. The post-commit hook auto-pushes, so work LEAVES this
# machine reliably. Nothing ever brought work back IN. The hook only integrates
# when this copy commits AND the push is rejected, and it skips the integration
# entirely when the tree is dirty — which, with several sessions sharing this
# checkout, it usually is. So a copy that nobody commits from drifts silently:
# on 2026-09-17 `main` sat 13 commits behind origin with a clean-looking
# `git status`, and a ship prepared from it would have archived stale code and
# re-used a closed version train. `git status` alone cannot show this; only a
# fetch can, and nothing was fetching.
#
# WHAT IT DOES, and deliberately does not:
#   • ALWAYS fetches. A fetch never touches the working tree, so it is safe at
#     any moment, and it is what makes `git status -sb`'s [behind N] true.
#   • Fast-forwards `main` to `origin/main` ONLY when that cannot lose
#     anything: tree clean, index clean, branch not ahead, no rebase/merge in
#     flight. A fast-forward with a clean tree is the one integration with no
#     judgment in it.
#   • NEVER stashes, rebases, merges non-trivially, resets or forces. Anything
#     that needs a decision is reported and left alone — a script cannot know
#     which of two sessions' edits is the one you meant to keep.
#   • REFUSES to move the tree while a build, verify or ship is running. Both
#     ship scripts rsync the WORKING TREE, so a fast-forward landing mid-archive
#     would splice two trees into one binary.
#
# Run it from anywhere; it always acts on the canonical copy, never a worktree.
# Log: .git/last-sync.log (one line per run, newest at the bottom).

set -uo pipefail

REPO="${CASBERI_REPO:-$HOME/Developer/casberi}"
BRANCH="main"

cd "$REPO" 2>/dev/null || { echo "repo not found: $REPO"; exit 1; }

LOG="$(git rev-parse --git-dir)/last-sync.log"
say() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# Keep the ledger from growing without bound.
[[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt 2000 ]] && tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

# ── 1 · fetch, always ───────────────────────────────────────────────────────
if ! git fetch -q origin "$BRANCH" 2>/dev/null; then
  say "fetch failed (offline?) — nothing changed"
  exit 0
fi

CUR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
AHEAD="$(git rev-list --count "origin/$BRANCH..$BRANCH" 2>/dev/null || echo 0)"
BEHIND="$(git rev-list --count "$BRANCH..origin/$BRANCH" 2>/dev/null || echo 0)"

[[ "$BEHIND" == 0 && "$AHEAD" == 0 ]] && exit 0   # in sync: say nothing, log nothing

# ── 2 · the reasons not to touch the tree ───────────────────────────────────
#
# Each of these leaves the fetch in place (so the [behind N] is now truthful)
# and declines the fast-forward. Reported, never silently skipped: a sync that
# quietly does nothing is the failure this script was written to end.
refuse() { say "behind $BEHIND, ahead $AHEAD — NOT fast-forwarded: $1"; exit 0; }

[[ "$CUR" != "$BRANCH" ]]                        && refuse "checked out on '$CUR', not $BRANCH"
[[ "$AHEAD" != 0 ]]                              && refuse "branch has $AHEAD local commit(s); integrating them is your call (git pull --rebase)"
[[ -n "$(git status --porcelain --untracked-files=no)" ]] \
                                                 && refuse "uncommitted changes in the tree (another session is probably mid-edit)"
[[ -d "$(git rev-parse --git-dir)/rebase-merge" || -d "$(git rev-parse --git-dir)/rebase-apply" ]] \
                                                 && refuse "a rebase is in progress"
[[ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]] && refuse "a merge is in progress"
[[ -f "$(git rev-parse --git-dir)/BISECT_LOG" ]] && refuse "a bisect is in progress"

# A build, verify or ship reads the working tree for minutes at a time, and both
# ship scripts rsync it. Moving files under one of those is how a single binary
# ends up half from one commit and half from another.
if pgrep -fl 'xcodebuild|verify\.sh|verify-mac\.sh|testflight.*\.sh' >/dev/null 2>&1; then
  refuse "a build/verify/ship is running — the tree is being read right now"
fi

# ── 3 · the one safe integration ────────────────────────────────────────────
if git merge --ff-only "origin/$BRANCH" >/dev/null 2>&1; then
  say "fast-forwarded $BRANCH by $BEHIND commit(s) → $(git rev-parse --short HEAD)"
else
  say "behind $BEHIND — fast-forward REFUSED by git (diverged?); left untouched"
fi
