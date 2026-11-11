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
[[ -d $ENGINE/node_modules/@aztec-labs/wallet-sdk && -d $ENGINE/node_modules/@alejoamiras/private-fee-juice ]] \
  || (cd $ENGINE && npm ci --no-audit --no-fund >/dev/null \
        && shasum -a 256 package-lock.json | cut -c1-16 > node_modules/.lock-stamp) # aztec-engine.sh's stamp: no second install

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
steps_mutant "an unwatched send is not counted" 's/^  reached++;$/  if (watching) reached++;/'

# ── Private gas (prd §1700aa) ───────────────────────────────────────────
# The shared private fee contract: used only on its rollup and at the address
# its own bytecode derives, never asked for more than is there, and a send
# that reached Aztec never sent twice. Each a failure that loses gas or sends
# money twice, and none of them shows on a screen.
FEES_SRC=$ENGINE/src/private-fees.js
grep -q "if (version !== PRIVATE_FEES.rollupVersion) {" $MAIN \
  || { echo "✗ main.js uses the private fee contract on a rollup it is not pinned to"; exit 1; }
grep -q "if (!derived.equals(AztecAddress.fromStringUnsafe(PRIVATE_FEES.address))) {" $MAIN \
  || { echo "✗ main.js registers the private fee contract without checking the address its bytecode derives"; exit 1; }
grep -q "additionalScopes: \[fpc.address\], maxAcceptableGasCost: cap," $MAIN \
  || { echo "✗ a private payment is measured with no ceiling: the contract keeps the whole declared limit"; exit 1; }
grep -q "    reached: sendsReached," $MAIN \
  || { echo "✗ a failed private send no longer asks whether it reached Aztec before it is tried again"; exit 1; }
(( $(grep -c "await sendOwn(wallet, " $MAIN) == 3 )) \
  || { echo "✗ Casberi's three sends (a claim, a private send, an exit) no longer all pay through sendOwn"; exit 1; }
(( $(grep -c "\.send({ from: me" $MAIN) == 2 )) \
  || { echo "✗ a send in main.js goes around sendOwn (two are allowed: sendOwn's own, and the legacy gas claim)"; exit 1; }
(cd $ENGINE && node test/private-fees.test.mjs) || { echo "✗ the private gas checks failed"; exit 1; }
fees_mutant() { # name, perl expression
  perl -0pe "$2" $FEES_SRC > $TMP/private-fees.js
  cmp -s $FEES_SRC $TMP/private-fees.js && { echo "✗ mutation '$1' changed nothing"; exit 1; }
  if (cd $ENGINE && FEES=$TMP/private-fees.js node test/private-fees.test.mjs >/dev/null 2>&1); then
    echo "✗ mutation '$1' passed: the private gas checks cannot see it"; exit 1
  fi
  echo "✓ mutation '$1' fails the private gas checks"
}
fees_mutant "a deposit Aztec has not carried is minted" 's/    if \(!item\.ready\) continue;\n//'
fees_mutant "a mint that failed its measure is sent at the fixed limits" 's/UNMEASURED\.test\(words\(e\)\) && item\.amount >= ceiling/item.amount >= ceiling/'
fees_mutant "a private payment is measured past the balance" "s/await estimate\('private', balance\)/await estimate('private', ceiling)/"
fees_mutant "a send that reached Aztec is sent again" 's/    if \(reached\(\) !== before\) throw first;[^\n]*\n//'
fees_mutant "the second failure hides the first" 's/    \} catch \{\n      throw first;/    } catch (second) {\n      throw second;/'
fees_mutant "the pinned address is not the one the bytecode derives" 's/0x0516ebb4/0x0516ebb5/'
fees_mutant "two sends choose how to pay at once" 's/    const mine = last\.then\(run\);/    const mine = Promise.resolve().then(run);/'
grep -q "return ownTurn(() => sendPaying({" $MAIN \
  || { echo "✗ Casberi's sends no longer take turns: a claim and a send can be offered the same gas deposit"; exit 1; }

# ── zk.money's short links (prd §1748) ──────────────────────────────────
# The tag a link's record stands under, the locator's pinned address, and
# what counts as a record in the node's reply. A wrong separator or address
# finds nothing and reads as "this link could not be read" for every link.
ZKLINK_SRC=$ENGINE/src/zk-link.js
[[ -f $ZKLINK_SRC ]] || { echo "✗ $ZKLINK_SRC not found"; exit 1; }
(cd $ENGINE && node test/zk-link.test.mjs) || { echo "✗ the short-link checks failed"; exit 1; }
zklink_mutant() { # name, perl expression
  perl -0pe "$2" $ZKLINK_SRC > $ENGINE/src/zz-zk-link-mutant.js
  cmp -s $ZKLINK_SRC $ENGINE/src/zz-zk-link-mutant.js && { rm -f $ENGINE/src/zz-zk-link-mutant.js; echo "✗ mutation '$1' changed nothing"; exit 1; }
  if (cd $ENGINE && ZKLINK=../src/zz-zk-link-mutant.js node test/zk-link.test.mjs >/dev/null 2>&1); then
    rm -f $ENGINE/src/zz-zk-link-mutant.js; echo "✗ mutation '$1' passed: the short-link checks cannot see it"; exit 1
  fi
  rm -f $ENGINE/src/zz-zk-link-mutant.js
  echo "✓ mutation '$1' fails the short-link checks"
}
zklink_mutant "the locator is not its class's address" 's/0x1335463038d5/0x1335463038d6/'
zklink_mutant "the tag's second hash dropped" 's/const tag = await poseidon2HashWithSeparator\(\[pre\], ZK_LINK\.tagSeparator\);/const tag = pre;/'
zklink_mutant "the kind left out of the tag" 's/\[new Fr\(BigInt\(kind\)\), new Fr/[new Fr(2n), new Fr/'
zklink_mutant "any kind taken" 's/!\[1, 2\]\.includes\(kind\) \|\| //'
zklink_mutant "the log's own tag handed back as the record's first field" 's/\.slice\(1, 1 \+ ZK_LINK\.fields\)/.slice(0, ZK_LINK.fields)/'
grep -q "const tag = await siloedTag(Number(kind), String(seedHex));" $MAIN && grep -q "return { payloads: payloads(reply.result) };" $MAIN \
  || { echo "✗ the engine no longer reads a short link's record by its tag"; exit 1; }
awk '/async zkLinkLogs\(/,/^  },/' $MAIN | grep -q "getWallet" \
  && { echo "✗ a short link's read starts the wallet: it needs no account"; exit 1; }

echo "aztec connect self-test: ok"
