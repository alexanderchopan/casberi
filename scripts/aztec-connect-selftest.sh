#!/bin/zsh
# Aztec connect self-test (prd §1700j) — an Aztec app in Casberi's browser
# finds Casberi as a wallet, and gets nothing before the person says yes:
#
#   tools/aztec-engine/src/connect-gate.js  — discovery answered at once;
#     Connect and the emoji check asked when Casberi is picked; the app's calls
#     held until both are yes; a no ends the session
#   tools/aztec-engine/src/main.js          — the engine routes through it
#
# Runs Aztec's own wallet-sdk on both sides (the app's WalletManager with Dark
# Forest Aztec's 5 s discovery window, the relay's and the engine's handlers)
# in tools/aztec-engine/test/connect-gate.test.mjs. Each failure it catches:
#
#   • discovery waiting on a sheet — the app's window closes first and it says
#     it found no wallet (the bug the user hit, 2026-11-06);
#   • an app's call answered before Connect and the emoji check — its address
#     read with nobody asked;
#   • a declined Connect that still lets a call through.
set -euo pipefail
cd "$(dirname "$0")/.."

ENGINE=tools/aztec-engine
GATE_SRC=$ENGINE/src/connect-gate.js
MAIN=$ENGINE/src/main.js
TEST=$ENGINE/test/connect-gate.test.mjs
for f in $GATE_SRC $MAIN $TEST; do [[ -f $f ]] || { echo "✗ $f not found"; exit 1; }; done
[[ -d $ENGINE/node_modules/@aztec-labs/wallet-sdk ]] || (cd $ENGINE && npm ci --no-audit --no-fund >/dev/null)

# ── The engine goes through the gate, read ─────────────────────────────
grep -q "import { connectGate } from './connect-gate.js';" $MAIN \
  || { echo "✗ main.js no longer builds its gate from connect-gate.js"; exit 1; }
grep -q "gate.discovered(discovery.requestId)" $MAIN \
  && grep -q "if (!gate.message(id, () => answerApp(session, message)))" $MAIN \
  || { echo "✗ main.js answers an app's discovery or call around the gate"; exit 1; }
(( $(grep -c "approveDiscovery" $MAIN) == 1 )) \
  || { echo "✗ main.js approves a discovery somewhere other than the gate's one hook"; exit 1; }

# ── Run ────────────────────────────────────────────────────────────────
(cd $ENGINE && node test/connect-gate.test.mjs) || { echo "✗ the connect checks failed"; exit 1; }

# ── Mutations: each must fail the run, or the run proves nothing ───────
TMP=$(mktemp -d "$PWD/$ENGINE/.selftest.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
mutant() { # name, then the run's env
  local name=$1; shift
  if (cd $ENGINE && env "$@" node test/connect-gate.test.mjs >/dev/null 2>&1); then
    echo "✗ mutation '$name' passed: the checks cannot see it"; exit 1
  fi
  echo "✓ mutation '$name' fails the checks"
}
mutant "discovery waits on Connect" MUTATION=ask-first
mutant "the app's calls skip the gate" MUTATION=no-hold

# The gate's own source, mutated in a copy (a tracked file is never edited).
sed 's/      if (s.open) run();/      run(); if (false)/' $GATE_SRC > $TMP/run-at-once.js
cmp -s $GATE_SRC $TMP/run-at-once.js && { echo "✗ mutation 'calls run before the yeses' changed nothing"; exit 1; }
mutant "calls run before the yeses" GATE=$TMP/run-at-once.js
sed 's/      if (!yes) return end(id);/      if (!yes) yes = true;/' $GATE_SRC > $TMP/no-means-yes.js
cmp -s $GATE_SRC $TMP/no-means-yes.js && { echo "✗ mutation 'a no to Connect is ignored' changed nothing"; exit 1; }
mutant "a no to Connect is ignored" GATE=$TMP/no-means-yes.js

echo "aztec connect self-test: ok"
