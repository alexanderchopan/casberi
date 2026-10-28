#!/bin/zsh
# Branch prune (2026-10-28) — run weekly by scripts/nightly-mac.sh (Mondays).
#
# Every Claude session, worktree and helper agent makes a branch, and nothing
# ever deleted one: the repo held 154 in September and 92 again by late
# October, every one of them landed or obsolete. This deletes the ones that
# are provably safe to delete, and nothing else:
#
#   * remote: no commit missing from origin/main, untouched for 2 days (a live
#     session's fresh branch is left alone), and not the head of an open PR
#     (deleting a head leaves its PR open and unmergeable). If `gh` cannot list
#     the open PRs, the remote half is skipped, never guessed.
#   * local: `git branch -d` on branches merged into origin/main. It refuses a
#     branch a worktree has checked out, so a peer's session is never touched.
#
# A branch holding commits main lacks is never deleted here, even when its work
# landed under another commit: that verdict needs a reading, not a rule.
#
#   scripts/branch-prune.sh            prune, print one `branches:` line
#   scripts/branch-prune.sh --dry-run  print what would go, delete nothing
#
# Never fails its caller: every outcome exits 0.
setopt null_glob
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0; [[ "${1:-}" == --dry-run ]] && DRY=1
G=(git -C "$ROOT")

$G fetch --prune origin -q 2>/dev/null || { print -r -- "branches: fetch failed, nothing pruned"; exit 0; }

CUTOFF=$(( $(date +%s) - 2 * 86400 ))
typeset -a GONE
if PRHEADS=$(gh pr list --repo alexanderchopan/casberi --state open --limit 200 \
      --json headRefName --jq '.[].headRefName' 2>/dev/null); then
  for b in $($G for-each-ref refs/remotes/origin --format='%(refname:lstrip=3)'); do
    [[ "$b" == main || "$b" == HEAD ]] && continue
    print -r -- "$PRHEADS" | grep -qxF -- "$b" && continue
    (( $($G rev-list --count "origin/main..origin/$b") == 0 )) || continue
    (( $($G log -1 --format=%ct "origin/$b") < CUTOFF )) || continue
    GONE+=("$b")
  done
  REMOTE_NOTE=""
else
  REMOTE_NOTE=" (remote skipped: gh could not list open PRs)"
fi

typeset -a LOCAL
for b in $($G branch --merged origin/main --format='%(refname:short)'); do
  [[ "$b" == main ]] && continue
  LOCAL+=("$b")
done

if (( DRY )); then
  print -r -- "branches (dry run): would delete ${#GONE} remote, try ${#LOCAL} local merged$REMOTE_NOTE"
  print -rl -- "${GONE[@]/#/  remote }" "${LOCAL[@]/#/  local  }"
  exit 0
fi

RDEL=0
if (( ${#GONE} )); then
  # stdin from /dev/null: `git push` reads stdin, and inside a loop it eats
  # the list (memory: branch-sweep-is-safe).
  RDEL=$($G push origin --delete "${GONE[@]}" </dev/null 2>&1 | grep -c '\[deleted\]')
fi
LDEL=0
(( ${#LOCAL} )) && LDEL=$($G branch -d "${LOCAL[@]}" 2>&1 | grep -c '^Deleted')
print -r -- "branches: deleted $RDEL remote, $LDEL local$REMOTE_NOTE"
exit 0
