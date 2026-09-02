#!/bin/zsh
# Is this harness's verdict the same under `-Onone` as under `-O`?
#
# WHY THIS EXISTS. 97% of a pure-logic harness's wall time is `swiftc`, and the
# identical compiles run 3.9x–6.4x faster unoptimized (measured 2026-09-01 on
# `l2beat-selftest.sh`: 46.8s -> 7.3s on its biggest compile). With 86 harnesses
# doing ~600 optimizing compiles, that is by a wide margin the largest remaining
# cost in `verify.sh`.
#
# CLAUDE.md has recorded since 2026-08-19 that a blanket `-O` -> `-Onone` swap
# is NOT safe, and that objection stands: `retriever-selftest`'s own header
# records that a trapping harness under `-O` prints NOTHING, so the flag can
# change a harness's OBSERVABLE BEHAVIOUR, not merely its speed. A blanket swap
# is exactly the green-and-wrong class this repo bans.
#
# What that entry left implicit is that "each would need checking" describes a
# MECHANICAL check, not a prohibitive one. This is that check: run the harness
# both ways over the same tree and compare its output bytes and its exit code.
# An identical pair is a proof that, for this harness, the flag is a speed knob
# and nothing else — which is the only evidence that licenses the swap.
#
# HOW THE FLAG IS CHANGED WITHOUT EDITING THE HARNESS. A PATH shim named
# `swiftc` (and `xcrun`, since two harnesses go through it and would otherwise
# bypass a `swiftc`-only shim) rewrites a standalone `-O` to `-Onone` and
# forwards everything else untouched. Nothing in the tree is modified, so this
# is safe to run while other sessions are live — the lesson from probing
# tracked files with a concurrent `git add -A` around.
#
# WHAT A "SAME" VERDICT DOES NOT PROVE, stated because a check trusted past its
# limits is worse than none: it proves the two runs agreed ON THIS TREE, today.
# A harness whose fixtures do not currently reach a trapping path would agree
# here and could still diverge after someone adds one. That is why the swap is
# per-harness and why this probe stays runnable rather than being deleted once
# the conversion is done — re-run it for a harness that grows new mutations.
#
# A run whose two halves BOTH fail identically is reported as DIFFER-SAFE=n/a:
# equal output from two failing runs says nothing about the passing path, so it
# never licenses a swap.
#
# Usage: scripts/support/harness-opt-probe.sh <harness.sh> [more...]
# Always exits 0 — an instrument, never a gate.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

SHIM=$(mktemp -d)
trap 'rm -rf "$SHIM"' EXIT

cat > "$SHIM/swiftc" <<'EOF'
#!/bin/zsh
args=(); for a in "$@"; do [[ "$a" == "-O" ]] && args+=(-Onone) || args+=("$a"); done
exec /usr/bin/swiftc "${args[@]}"
EOF
# `xcrun swiftc ...` must be rewritten too, or the two harnesses that use it
# are silently measured UNCHANGED and reported as safe on evidence that never
# tested anything.
cat > "$SHIM/xcrun" <<'EOF'
#!/bin/zsh
args=(); for a in "$@"; do [[ "$a" == "-O" ]] && args+=(-Onone) || args+=("$a"); done
exec /usr/bin/xcrun "${args[@]}"
EOF
chmod +x "$SHIM/swiftc" "$SHIM/xcrun"

zmodload zsh/datetime
printf '%-34s %9s %9s %7s  %s\n' harness "-O" "-Onone" speedup verdict

for h in "$@"; do
  name="${h:t}"
  # An absolute path is used as given. Blindly prefixing `$ROOT/` made the
  # harness unfindable and then reported the two "no such file" messages as a
  # DIFFER — a probe crying wolf on its own plumbing, caught by its first
  # negative test.
  # NEVER name a variable `path` in zsh: lowercase `path` is the ARRAY FORM of
  # `PATH`, tied to it, so `path=...` silently replaces the whole search path
  # and every later `mktemp`/`cmp`/`diff` is "command not found". Cost one
  # debugging round here, and it is the same shape as this repo's other zsh
  # traps (job control off, `grep -q` under pipefail).
  [[ "$h" == /* ]] && hpath="$h" || hpath="$ROOT/$h"
  if [[ ! -x "$hpath" ]]; then
    printf '%-34s %9s %9s %7s  %s\n' "$name" - - - "SKIP — not an executable file: $hpath"
    continue
  fi
  out_o=$(mktemp); out_n=$(mktemp)

  t0=$EPOCHREALTIME
  "$hpath" > "$out_o" 2>&1; rc_o=$?
  t_o=$(( EPOCHREALTIME - t0 ))

  t0=$EPOCHREALTIME
  PATH="$SHIM:$PATH" "$hpath" > "$out_n" 2>&1; rc_n=$?
  t_n=$(( EPOCHREALTIME - t0 ))

  if [[ "$rc_o" != "$rc_n" ]]; then
    verdict="DIFFER (rc $rc_o vs $rc_n) — do NOT swap"
  elif ! cmp -s "$out_o" "$out_n"; then
    verdict="DIFFER (output) — do NOT swap"
  elif (( rc_o != 0 )); then
    # Identical, but identical FAILURE. Says nothing about the passing path.
    verdict="n/a — both failed (rc $rc_o); fix the harness, then re-probe"
  else
    verdict="SAME — safe to swap"
  fi

  sp=$(printf '%.1f' $(( t_n > 0 ? t_o / t_n : 0 )))
  printf '%-34s %8.1fs %8.1fs %6sx  %s\n' "$name" "$t_o" "$t_n" "$sp" "$verdict"
  [[ "$verdict" == DIFFER* ]] && { echo "    first divergence:"; diff "$out_o" "$out_n" | head -6 | sed 's/^/      /'; }
  rm -f "$out_o" "$out_n"
done
exit 0
