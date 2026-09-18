#!/bin/zsh
# install-hooks.sh — put the tracked hooks in scripts/hooks/ into .git/hooks,
# and load the repo-sync LaunchAgent.
#
# `.git/hooks` is not version controlled and does not survive a fresh clone, so
# every hook this repo depends on lived on one machine and in no backup. This
# is the one command that makes a clone behave like the canonical copy.
#
# Idempotent. Run it after cloning, and after changing anything in
# scripts/hooks/.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITDIR="$(git rev-parse --git-common-dir 2>/dev/null)"
[[ -n "$GITDIR" ]] || { print "not a git repo"; exit 1 }
[[ "$GITDIR" = /* ]] || GITDIR="$ROOT/$GITDIR"

print "installing hooks → $GITDIR/hooks"
mkdir -p "$GITDIR/hooks"
for h in "$ROOT"/scripts/hooks/*(N); do
  name="$(basename "$h")"
  if [[ -f "$GITDIR/hooks/$name" ]] && ! cmp -s "$h" "$GITDIR/hooks/$name"; then
    cp "$GITDIR/hooks/$name" "$GITDIR/hooks/$name.replaced-$(date +%Y%m%d%H%M%S)"
    print "  kept a copy of the existing $name alongside it"
  fi
  cp "$h" "$GITDIR/hooks/$name" && chmod +x "$GITDIR/hooks/$name"
  print "  ✓ $name"
done

# The timer that pulls other sessions' work IN. The hooks above only push.
PLIST="com.casberi.repo-sync.plist"
if [[ -f "$ROOT/scripts/$PLIST" ]]; then
  mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/scripts/output"
  cp "$ROOT/scripts/$PLIST" "$HOME/Library/LaunchAgents/$PLIST"
  launchctl bootout "gui/$UID/com.casberi.repo-sync" 2>/dev/null
  if launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$PLIST" 2>/dev/null; then
    print "  ✓ com.casberi.repo-sync loaded (fetches every 5 min)"
  else
    print "  ✗ could not load com.casberi.repo-sync — load it by hand:"
    print "    launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/$PLIST"
  fi
fi

print ""
print "Check it with:  launchctl list | grep casberi"
print "Its ledger:     tail $GITDIR/last-sync.log"
