#!/bin/zsh
# Casberi ask-scope self-test — guards the PERF work of 2026-08-13, which made
# tapping an agent chip stop materialising the entire store twice.
#
#   Casberi/Casberi/Model/KeptAskComposers.swift  — CorpusNeed / corpusNeed(for:)
#   Casberi/Casberi/Shell/RootShell.swift         — keptCorpus(for:) / lastKnownDoc
#   Casberi/Casberi/Shell/Composer.swift          — the deferred settle bookkeeping
#
# WHY A HARNESS. The reported symptom was "it's pretty good when you first open
# the agent but not so much when you click one of the chips", and the cause was
# that the 2026-08-11 pass fixed the feed (`allRoomFetchLimit`), the chip strip
# (`newestPerSource`) and the agent's OPEN (`composeBoard`, moved off the
# critical path) and never reached the TAP. A chip tap ran two unbounded,
# fully-hydrated fetches of every `Thing` on the main actor: one in
# `answerDocument` before any composer ran, and one in the settle path ABOVE
# the line that paints the answer.
#
# The fix replaces the first with a per-kind scoped fetch. That trade is only
# safe while the declared scope keeps matching what the composer actually
# reads, and EVERY failure of that is silent:
#
#   • a kind declared `.none` whose composer later grows a `things` argument
#     reads an EMPTY corpus — "Nothing overdue" over a pile of overdue things,
#     with every screen still rendering perfectly;
#   • a leg added to `moneyFlow`, or a source added to `overdue`/`walletDoc`,
#     without the fetch scope following it — the room quietly stops counting;
#   • `showtag:` narrowed to a `#Predicate` over `tags`, which is a
#     TRANSFORMABLE attribute: that compiles clean and TRAPS at runtime inside
#     CoreData (CLAUDE.md's own standing gotcha), so it is a crash, not a
#     miscount;
#   • `keptCorpus` losing its empty-read fallback, which is the one thing
#     keeping a mis-scoped fetch to "slow" instead of "wrong";
#   • the settle bookkeeping drifting back above the paint, which restores
#     exactly half the original latency with nothing on screen to say so.
#
# None of these is visible to `xcodebuild`, to the screen sweep, or to the
# nightly perf pass — that pass times launch, RSS and answer latency, and this
# work lands AFTER the answer is computed.
#
# The scope table is DERIVED from the constants the composers filter on, so the
# checks below verify the derivation is still in place rather than re-stating
# the lists (a second copy is the drift this whole file exists to prevent).
#
# Negative guards read a COMMENT-STRIPPED copy: the sources document these
# rules by naming the very literals they must no longer use, so a guard
# grepping raw source fires on the prose explaining it (the Obsidian/Cursor
# lesson, earned again here on this guard's first run).
#
# Pure, local, deterministic — no build, no network, no simulator. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSERS="Casberi/Casberi/Model/KeptAskComposers.swift"
ROOTSHELL="Casberi/Casberi/Shell/RootShell.swift"
COMPOSER="Casberi/Casberi/Shell/Composer.swift"

for f in "$COMPOSERS" "$ROOTSHELL" "$COMPOSER"; do
  [[ -f "$f" ]] || { print "FAIL: missing source $f"; exit 1; }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/casberi-askscope.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Comment-stripped copies. `//`-to-end-of-line and `/* … */`, nothing else —
# string literals in this codebase never contain `//`.
strip_comments() {
  python3 - "$1" "$2" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
src = re.sub(r"//[^\n]*", "", src)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
}

FAILURES=0
CHECKS=0
note() { print "  · $1"; }
fail() { print "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# ── The checks, each a function over a directory of stripped sources, so the
# ── mutation pass below can re-run them against a deliberately broken copy.

# CHECK 1 — every kind declared `.none` really takes no `things`.
#
# This is the invariant that makes returning an EMPTY array for those kinds
# safe, and it is the one most likely to rot: a composer that grows a corpus
# argument is an ordinary, correct-looking edit, and the kind would then read
# nothing forever. The `.none` list is PARSED OUT of `corpusNeed` rather than
# restated here — a hand-copied list would itself be the drift.
check_none_kinds() {
  local dir="$1" c="$1/KeptAskComposers.swift"
  local kinds
  kinds=$(python3 - "$c" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"if\s*\[(.*?)\]\.contains\(kind\)\s*\{\s*return\s*\.none", src, re.S)
if not m:
    sys.exit("NO-NONE-LIST")
print(" ".join(re.findall(r'"([^"]+)"', m.group(1))))
PY
) || { fail "check 1: could not find the \`.none\` list in corpusNeed"; return; }

  [[ -n "$kinds" ]] || { fail "check 1: the \`.none\` list is empty"; return; }

  local kind line
  for kind in ${=kinds}; do
    # The dispatch line in `compose` for this kind.
    line=$(grep -E "kind == \"$kind\"" "$c" | head -1 || true)
    if [[ -z "$line" ]]; then
      fail "check 1: \`$kind\` is declared .none but nothing in compose dispatches it (stale entry)"
      continue
    fi
    if print -r -- "$line" | grep -q "things"; then
      fail "check 1: \`$kind\` is declared .none but its composer is handed \`things\` — it would read an EMPTY corpus"
    fi
  done
}

# CHECK 2 — the three scoped composers filter on the shared constants.
#
# `corpusNeed` derives their fetch scope from these same constants, so a
# composer that goes back to a literal breaks the derivation silently: the
# fetch keeps returning the old set while the filter looks for a new one.
check_constants() {
  local dir="$1" c="$1/KeptAskComposers.swift"
  grep -q "overdueSources.contains(\$0.source)" "$c" \
    || fail "check 2: overdue() no longer filters on overdueSources"
  grep -q "walletDocSources.contains(\$0.source)" "$c" \
    || fail "check 2: walletDoc() no longer filters on walletDocSources"
  grep -q "rows(moneyFlowInboundSource)" "$c" \
    || fail "check 2: moneyFlow()'s inbound leg no longer uses moneyFlowInboundSource"
  grep -q "rows(moneyFlowShieldedSource)" "$c" \
    || fail "check 2: moneyFlow()'s shielded leg no longer uses moneyFlowShieldedSource"
  # And the union really is built from those two, not restated.
  grep -q "Corpus.cardSpendSources.union(\[moneyFlowInboundSource, moneyFlowShieldedSource\])" "$c" \
    || fail "check 2: moneyFlowSources is no longer derived from the leg constants"
}

# CHECK 3 — `showtag:` must never be narrowed to a sources/predicate scope.
#
# `tags` is a transformable attribute. A `#Predicate` testing membership on one
# compiles clean and traps at runtime inside CoreData mid-fetch — a crash, not
# a wrong answer. Guarded two ways: `corpusNeed` must have no showtag branch,
# and no `#Predicate` anywhere in `keptCorpus` may mention `tags`.
check_showtag() {
  local dir="$1" c="$1/KeptAskComposers.swift" r="$1/RootShell.swift"
  if grep -E 'hasPrefix\("showtag:"\)' "$c" | grep -q "return \."; then
    fail "check 3: corpusNeed grew a showtag branch — a tags predicate TRAPS at runtime"
  fi
  # The whole keptCorpus body, predicates included, must not touch `tags`.
  if ! python3 - "$r" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"private func keptCorpus\(for kind: String\) -> \[Thing\] \{(.*?)\n    \}", src, re.S)
if not m:
    sys.exit("keptCorpus(for:) not found")
if re.search(r"#Predicate[^\n]*tags|\.tags", m.group(1)):
    sys.exit("keptCorpus builds a predicate over `tags` — that TRAPS at runtime")
PY
  then
    fail "check 3: see above"
  fi
}

# CHECK 4 — `keptCorpus` keeps its fail-safe.
#
# An empty scoped read is treated as no scope at all and re-fetched whole. That
# single line is what bounds the worst case of this entire change to
# "yesterday's performance" instead of "a confidently empty answer".
check_failsafe() {
  local dir="$1" r="$1/RootShell.swift"
  grep -q "rows.isEmpty ? fullCorpus() : rows" "$r" \
    || fail "check 4: keptCorpus lost its empty-read fallback to fullCorpus()"
  grep -q "(try? modelContext.fetch(descriptor)) ?? \[\]" "$r" \
    || fail "check 4: keptCorpus no longer swallows a fetch throw"
}

# CHECK 5 — the settle bookkeeping stays BELOW the paint, and re-guards.
#
# Two separate failures. Moving the fetch back above `answerStream` restores
# half the original latency invisibly. Dropping the post-yield `gen` re-guard
# is worse than a perf regression: the yield is a real suspension, so a newer
# ask can begin inside it and would wear this question's Keep pill.
check_settle_order() {
  local dir="$1" c="$1/Composer.swift"
  if ! python3 - "$c" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
fetch = src.find("let settledThings")
if fetch < 0:
    sys.exit("settledThings fetch not found")
paint = src.find("else { answerStream.stream(finalDoc) }")
if paint < 0:
    sys.exit("the answer paint not found")
if fetch < paint:
    sys.exit("the settle's full-corpus fetch runs BEFORE the answer is painted")
# The yield and the re-guard must both sit between the paint and the fetch.
window = src[paint:fetch]
if "await Task.yield()" not in window:
    sys.exit("no yield between painting the answer and the settle fetch")
if "guard gen == askGeneration else { return }" not in window:
    sys.exit("the deferred settle work is not re-guarded on askGeneration")
PY
  then
    fail "check 5: see above"
  fi
}

run_all() {
  local dir="$1"
  check_none_kinds "$dir"
  check_constants "$dir"
  check_showtag "$dir"
  check_failsafe "$dir"
  check_settle_order "$dir"
}

# ── Pass 1: the real tree ────────────────────────────────────────────
print "ask-scope self-test"
CLEAN="$WORK/clean"
mkdir -p "$CLEAN"
strip_comments "$COMPOSERS" "$CLEAN/KeptAskComposers.swift"
strip_comments "$ROOTSHELL"  "$CLEAN/RootShell.swift"
strip_comments "$COMPOSER"   "$CLEAN/Composer.swift"

run_all "$CLEAN"
if (( FAILURES > 0 )); then
  print "\n$FAILURES failure(s) against the real tree."
  exit 1
fi
print "  ✓ 5 checks pass against the tree"

# ── Pass 2: mutations — a check that cannot fail proves nothing ──────
# Each mutation is a real defect this change could plausibly reintroduce.
MUT_FAILS=0
mutate() {
  local name="$1" file="$2" find="$3" replace="$4" checkfn="$5"
  local dir="$WORK/mut"
  rm -rf "$dir"; cp -R "$CLEAN" "$dir"
  python3 - "$dir/$file" "$find" "$replace" <<'PY'
import sys
p, find, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(p, encoding="utf-8").read()
if find not in src:
    sys.exit("ANCHOR-MISSING")
open(p, "w", encoding="utf-8").write(src.replace(find, repl, 1))
PY
  if [[ $? -ne 0 ]]; then
    print "  ✗ mutation '$name' — anchor not found (the mutation is STALE and tests nothing)"
    MUT_FAILS=$((MUT_FAILS + 1)); return
  fi
  FAILURES=0
  $checkfn "$dir" || true
  if (( FAILURES > 0 )); then
    print "  ✓ caught: $name"
  else
    print "  ✗ MISSED: $name"
    MUT_FAILS=$((MUT_FAILS + 1))
  fi
  FAILURES=0
}

print "\nmutations"
# 1. A `.none` composer grows a corpus argument — reads nothing, forever.
mutate "a .none kind handed things" KeptAskComposers.swift \
  'if kind == "noticed" { return noticed() }' \
  'if kind == "noticed" { return noticed(things) }' \
  check_none_kinds
# 2. A `.none` entry left behind after its kind is renamed.
mutate "a stale .none entry" KeptAskComposers.swift \
  '"walletgas", "walletsafe"].contains(kind)' \
  '"walletgas", "walletsafeRENAMED"].contains(kind)' \
  check_none_kinds
# 3. overdue() goes back to source literals — fetch scope silently diverges.
mutate "overdue filtering on literals" KeptAskComposers.swift \
  'overdueSources.contains($0.source)' \
  '($0.source == "Reminders" || $0.source == "Todoist")' \
  check_constants
# 4. moneyFlow's shielded leg hardcoded again.
mutate "moneyFlow leg hardcoded" KeptAskComposers.swift \
  'rows(moneyFlowShieldedSource)' \
  'rows("Privacy Pools")' \
  check_constants
# 5. The union restated instead of derived.
mutate "moneyFlowSources restated" KeptAskComposers.swift \
  'Corpus.cardSpendSources.union([moneyFlowInboundSource, moneyFlowShieldedSource])' \
  'Corpus.cardSpendSources.union(["Peer", "Privacy Pools"])' \
  check_constants
# 6. keptCorpus loses the fail-safe — a mis-scoped fetch becomes a wrong answer.
mutate "fail-safe removed" RootShell.swift \
  'return rows.isEmpty ? fullCorpus() : rows' \
  'return rows' \
  check_failsafe
# 7. The settle fetch drifts back above the paint.
mutate "settle fetch above the paint" Composer.swift \
  '                await Task.yield()' \
  '                let settledThingsEARLY = 0; _ = settledThingsEARLY; await Task.yield()' \
  check_settle_order
# 8. The post-yield re-guard dropped — a newer ask wears this one's Keep pill.
mutate "settle re-guard dropped" Composer.swift \
  'guard gen == askGeneration else { return }
                let settledThings' \
  'let settledThings' \
  check_settle_order

if (( MUT_FAILS > 0 )); then
  print "\n$MUT_FAILS mutation(s) not caught — the checks above do not prove what they claim."
  exit 1
fi

print "\nask-scope self-test: 5 checks, 8 mutations, all good"
