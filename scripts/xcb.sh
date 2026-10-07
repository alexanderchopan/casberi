#!/bin/zsh
# xcb.sh — `xcodebuild` behind ONE machine-wide lock. Use it wherever you would
# type `xcodebuild`; the arguments and the exit code are xcodebuild's own.
#
# Why (2026-10-07): one Swift build already runs a compiler per core, so two
# sessions building at once is 2× the Mac and three is 3× — load average 66 on
# 8 cores, measured, with only three sessions live. Every session builds into
# its own DerivedData (a shared one collides), so each build is cold and the
# whole app compiles from scratch. Queued, each build finishes sooner than it
# does fighting for the cores, and a simulator launch stops stalling behind it.
#
# The lock is `flock(2)` on $XCB_LOCK, held by a perl parent that forks
# xcodebuild WITHOUT the descriptor (perl marks it close-on-exec), so a build
# daemon xcodebuild leaves running can never hold it. The kernel drops the lock
# when the parent exits however it exits: no stale lock file, ever. TERM and HUP
# are forwarded to the build, so `kill`/`pkill -P` on this script still stops it.
#
#   XCB_NO_LOCK=1   run xcodebuild unlocked (a cheap `-showBuildSettings`, say)
#   XCB_LOCK=<path> a different lock file (the self-test's own)
#   --self-test     prove two holders serialise and the exit code survives
#
# Not covered: builds started from the Xcode IDE or the Xcode MCP server.

LOCK=${XCB_LOCK:-/tmp/casberi-xcodebuild.lock}

if [[ "$1" == "--self-test" ]]; then
  zmodload zsh/datetime
  T=$(mktemp -d) || exit 1
  trap 'rm -rf "$T"' EXIT
  export XCB_LOCK="$T/lock"
  # Two holders of a 1s "build": serialised they take ≥2s, concurrent ~1s.
  start=$EPOCHREALTIME
  XCB_CMD=sleep "$0" 1 2>"$T/a.err" & a=$!
  XCB_CMD=sleep "$0" 1 2>"$T/b.err" & b=$!
  wait $a; wait $b
  elapsed=$(( EPOCHREALTIME - start ))
  (( elapsed >= 1.9 )) || { print "FAIL: two holders ran together (${elapsed}s)"; exit 1; }
  grep -q "waiting for the build lock" "$T/a.err" "$T/b.err" \
    || { print "FAIL: the waiter never said what it was waiting on"; exit 1; }
  XCB_CMD=false "$0" 2>/dev/null; rc=$?
  (( rc == 1 )) || { print "FAIL: exit code not passed through (got $rc)"; exit 1; }
  print "ok: serialised in ${elapsed}s, waiter announced, exit code kept"
  exit 0
fi

CMD=${XCB_CMD:-xcodebuild}
[[ -n "${XCB_NO_LOCK:-}" ]] && exec "$CMD" "$@"

exec /usr/bin/perl -MFcntl=:flock -MPOSIX=WNOHANG -e '
  my ($lock, @cmd) = @ARGV;
  open(my $fh, "+>>", $lock) or die "xcb: cannot open $lock: $!\n";
  unless (flock($fh, LOCK_EX | LOCK_NB)) {
    seek($fh, 0, 0); my $who = <$fh> // "unknown"; chomp $who;
    print STDERR "xcb: waiting for the build lock — held by $who\n";
    my $t = time;
    flock($fh, LOCK_EX) or die "xcb: flock: $!\n";
    printf STDERR "xcb: got the build lock after %ds\n", time - $t;
  }
  truncate($fh, 0);
  my $cwd = `pwd`; chomp $cwd;
  syswrite($fh, "pid $$ since " . scalar(localtime) . " in $cwd\n");
  my $pid = fork() // die "xcb: fork: $!\n";
  if ($pid == 0) { exec { $cmd[0] } @cmd; die "xcb: exec $cmd[0]: $!\n" }
  $SIG{INT} = "IGNORE";   # the terminal already sent it to the build
  $SIG{$_} = sub { kill $_[0], $pid } for qw(TERM HUP);
  1 while waitpid($pid, 0) == -1 && $!{EINTR};
  my $st = $?;
  exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
' "$LOCK" "$CMD" "$@"
