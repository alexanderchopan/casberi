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

# ── The steps a send shows (prd §1700w) ─────────────────────────────────
STEPS_SRC=$ENGINE/src/steps.js
grep -q "if (isSendTx(body)) sawSendTx();" $ENGINE/src/net-shim.js \
  && grep -q "    sawProof();" $ENGINE/src/native-backend.js \
  && grep -q "WATCHED_OWN.has(method) ? watched('move', go) : go()" $MAIN \
  && grep -q "READS.has(method) ? run() : watched('app', run)" $MAIN \
  || { echo "✗ a send's steps are not read where they happen (the prover, the node's sendTx, Move's sends, an app's transaction)"; exit 1; }
(cd $ENGINE && node test/steps.test.mjs) || { echo "✗ the step checks failed"; exit 1; }
steps_mutant() { # name, sed expression
  sed "$2" $STEPS_SRC > $TMP/steps.js
  cmp -s $STEPS_SRC $TMP/steps.js && { echo "✗ mutation '$1' changed nothing"; exit 1; }
  if (cd $ENGINE && STEPS=$TMP/steps.js node test/steps.test.mjs >/dev/null 2>&1); then
    echo "✗ mutation '$1' passed: the step checks cannot see it"; exit 1
  fi
  echo "✓ mutation '$1' fails the step checks"
}
steps_mutant "proving posted on every proof" 's/  if (!watching || watching.proving) return;/  if (!watching) return;/'
steps_mutant "a claim's proof posts with nothing watched" 's/  if (!watching || watching.sent) return;/  if (watching?.sent) return;/'
steps_mutant "a failure reads as done" "s/ok ? 'done' : 'failed'/'done'/"
steps_mutant "only a string body is a send" 's/  else if (ArrayBuffer.isView(body))/  else if (false)/'

echo "aztec connect self-test: ok"
