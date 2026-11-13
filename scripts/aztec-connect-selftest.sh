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

# ── A send behind its sheet (prd §1777) ─────────────────────────────────
# Move's send within Aztec goes on after its sheet closes, in its own slot:
# a second move started meanwhile must not overwrite it, the engine's words
# must still reach it, and it comes back only to a sheet with nothing running.
# `PrivateSendSteps.swift` is compiled whole but for UIKit's device word.
STEPS_SWIFT=Casberi/Casberi/Model/PrivateSendSteps.swift
ROWS_SWIFT=Casberi/Casberi/Screens/PrivateStepRows.swift
AZTEC_MOVE=Casberi/Casberi/Screens/MoveAztecPrivate.swift
sed -e '/^import UIKit$/d' -e '/^\/\/\/ \*\*THIS DEVICE, BY NAME/,$d' $STEPS_SWIFT > $TMP/Steps.swift
grep -q "enum DeviceWord" $TMP/Steps.swift && { echo "✗ the harness could not cut the device word out of $STEPS_SWIFT"; exit 1; }
cat > $TMP/main.swift <<'SWIFT'
import Foundation
enum DeviceWord {
    @MainActor static var proving: String { "Proving" }
    @MainActor static var proved: String { "Proved" }
}
@MainActor func runChecks() -> Int {
    var fails = 0
    func check(_ name: String, _ ok: Bool) { if !ok { print("  ✗ \(name)"); fails += 1 } }
    let s = PrivateSendSteps.shared
    s.sendAway()
    check("nothing running, nothing goes away", s.away == nil)
    s.begin(.app, plan: .send(.aztec))
    s.sendAway()
    check("an app's send never leaves its page", s.away == nil && s.run?.kind == .app)
    s.clear()
    s.begin(.move, plan: .send(.aztec))
    s.sendAway()
    check("Move's send leaves the sheet's slot", s.run == nil && s.away?.isRunning == true)
    s.begin(.move, plan: .signed(.ethereum))
    s.received(["step": "proving", "kind": "move"], plan: .send(.aztec))
    check("the engine's words reach the send behind the sheet", s.away?.currentIndex == 1)
    check("a second move in the sheet is not moved by them", s.run?.currentIndex == 0 && s.run?.plan == .signed(.ethereum))
    s.received(["step": "checking", "kind": "move"], plan: .send(.aztec))
    check("a checking for it starts no new run", s.run?.plan == .signed(.ethereum) && s.away?.currentIndex == 1)
    s.bringBack()
    check("never brought back over a move still running", s.away != nil && s.run?.plan == .signed(.ethereum))
    s.received(["step": "done", "kind": "move", "sent": true], plan: .send(.aztec))
    check("done ends the send behind the sheet, not the one in it", s.away?.ok == true && s.run?.isRunning == true)
    s.finish()
    s.clearAway()
    s.forget(.move)
    check("both put away", s.run == nil && s.away == nil)
    s.begin(.move, plan: .send(.aztec))
    s.sendAway()
    s.failAway("Aztec's node did not answer")
    check("its failure keeps its reason", s.away?.ok == false && s.away?.reason == "Aztec's node did not answer")
    s.bringBack()
    check("a failed send comes back to its sheet", s.run?.ok == false && s.run?.reason != nil && s.away == nil)
    s.clear()
    s.begin(.move, plan: .send(.aztec))
    s.sendAway()
    s.finishAway()
    check("a send handed back without the engine's word is done", s.away?.ok == true && s.away?.reachedNetwork == true)
    s.failAway("late")
    check("a finished send is not failed afterwards", s.away?.ok == true)
    return fails
}
let fails = MainActor.assumeIsolated { runChecks() }
exit(fails == 0 ? 0 : 1)
SWIFT
swiftc -Onone -o $TMP/steps-run $TMP/Steps.swift $TMP/main.swift 2>&1 | grep -E 'error:' || true
[[ -x $TMP/steps-run ]] || { echo "✗ the send-behind-its-sheet harness did not compile"; exit 1; }
$TMP/steps-run || { echo "✗ a send behind its sheet is not kept apart (prd §1777)"; exit 1; }
away_mutant() { # name, sed expression
  sed "$2" $TMP/Steps.swift > $TMP/StepsMutant.swift
  cmp -s $TMP/Steps.swift $TMP/StepsMutant.swift && { echo "✗ mutation '$1' changed nothing"; exit 1; }
  rm -f $TMP/steps-mrun
  swiftc -Onone -o $TMP/steps-mrun $TMP/StepsMutant.swift $TMP/main.swift 2>/dev/null || { echo "✗ mutation '$1' did not compile"; exit 1; }
  if $TMP/steps-mrun >/dev/null 2>&1; then echo "✗ mutation '$1' passed: the checks cannot see it"; exit 1; fi
  echo "✓ mutation '$1' fails the checks"
}
away_mutant "the engine's words go to the sheet's run" 's/if let behind = away, behind.kind == kind, behind.isRunning {/if let behind = away, behind.kind == kind, false {/'
away_mutant "an app's send goes away" 's/guard let current = run, current.kind == .move, current.isRunning else { return }/guard let current = run, current.isRunning else { return }/'
away_mutant "brought back over a running move" 's/guard let current = away, run?.isRunning != true else { return }/guard let current = away else { return }/'
away_mutant "a send that went away stays in the sheet too" 's/^        run = nil$/        _ = run/'
# The wiring no compiled function can prove: the sheet closes only after
# every ask, one send at a time, and the shell draws it.
awk '/try await AztecCoSign.approve\(/{a=NR} /steps.sendAway\(\)/{if(!s)s=NR} /AztecEngine.shared.call\("sendPrivately"/{c=NR} END{exit !(a && s && c && a<s && s<c)}' $AZTEC_MOVE \
  || { echo "✗ the sheet closes before Face ID and the co-signer answered, or after the send began (prd §1777)"; exit 1; }
grep -q 'guard mode != .send || !anotherIsGoing else {' $AZTEC_MOVE \
  || { echo "✗ a second send can start while one is behind its sheet (prd §1777)"; exit 1; }
grep -q 'move.onAway = inTray ? { chrome.moveTray = false } : nil' $AZTEC_MOVE \
  || { echo "✗ Send no longer closes its sheet, or closes a page that has no sheet (prd §1777)"; exit 1; }
grep -q '.task(id: move.mode) { if AztecMove.kept !== move { await move.read() } }' $AZTEC_MOVE \
  || { echo "✗ a send behind its sheet is read over when its sentence opens again (prd §1777)"; exit 1; }
grep -q 'if Self.kept === self, steps.away != nil { steps.failAway(words) } else { steps.fail(words) }' $AZTEC_MOVE \
  || { echo "✗ a failure behind the sheet fails whatever is in the sheet (prd §1777)"; exit 1; }
grep -q 'let aztecMove = (aztec == .send ? AztecMove.kept : nil) ?? AztecMove()' Casberi/Casberi/Screens/MoveSentence.swift \
  || { echo "✗ Move opened on Aztec no longer shows the send behind its sheet (prd §1777)"; exit 1; }
grep -q 'MoveStepCapsule()' Casberi/Casberi/Shell/RootShell.swift \
  || { echo "✗ the shell no longer draws a send behind its sheet (prd §1777)"; exit 1; }
grep -q 'if let run = steps.away {' $ROWS_SWIFT \
  || { echo "✗ the shell's capsule ticks with nothing to draw, or draws the sheet's own run (prd §1777)"; exit 1; }
echo "✓ a send behind its sheet: its own slot, the engine's words, one at a time, the shell's capsule"

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
(( $(grep -c "await sendOwn(wallet, " $MAIN) == 4 )) \
  || { echo "✗ Casberi's four sends (a claim, a private send, an exit, an authorization's take-back) no longer all pay through sendOwn"; exit 1; }
(( $(grep -c "sendOwn(wallet, " $MAIN) == 6 )) \
  || { echo "✗ sendOwn has a caller the pass does not know (its own line, the four sends, an app's authorization)"; exit 1; }
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
(( $(grep -c "return ownTurn(() => sendPaying({" $MAIN) == 2 )) \
  || { echo "✗ Casberi's sends, or an app's, no longer take turns: two can be offered the same gas deposit"; exit 1; }

# ── An app's transaction pays as Casberi's own do (prd §1759) ────────────
# It named no payer, so the account's own Fee Juice paid: an account whose
# gas is in the private fee contract could not pay for anything an app asked.
fees_mutant "an app's transaction skips the private balance" "s/  if \(privateBalance > 0n\) return 'private';\n//"
fees_mutant "a transaction naming its own payer is paid by Casberi" "s/  if \(payer\) return [^\n]*\n//"
fees_mutant "the app's scopes are dropped for the contract's" 's/\[\.\.\.\(opts\?\.additionalScopes \?\? \[\]\), \.\.\.\(paid\.additionalScopes \?\? \[\]\)\]/[...(paid.additionalScopes ?? [])]/'
fees_mutant "the app's own gas settings are kept over the measured ones" 's/fee: \{ \.\.\.\(opts\?\.fee \?\? \{\}\), gasSettings: paid\.fee\.gasSettings \}/fee: { gasSettings: paid.fee.gasSettings, ...(opts?.fee ?? {}) }/'
fees_mutant "an account with no gas is sent anyway" "s/    if \(ownHolds && !\(await ownHolds\(\)\)\) throw new Error\(NO_GAS\);\n//"
grep -q "if (method === 'sendTx' && !parsed\[0\]?.feePayer) {" $MAIN \
  || { echo "✗ an app's transaction with no payer is no longer paid as Casberi's own, or one with its own payer is rewritten"; exit 1; }
grep -q "pay: () => feeFor(wallet, appInteraction(wallet, payload, opts), gasJSON)," $MAIN \
  || { echo "✗ an app's transaction is no longer measured and capped as Casberi's own sends are"; exit 1; }
grep -q "const fee = method === 'sendTx' ? await appFeeKind(wallet, args) : '';" $MAIN \
  || { echo "✗ the approval sheet is no longer told how an app's transaction is paid"; exit 1; }
! grep -q "Paid from your Fee Juice" $MAIN \
  || { echo "✗ the sheet's fixed fee line is back: it said Fee Juice whatever paid"; exit 1; }

# ── An app's public authorization (prd §1760) ────────────────────────────
# `grantPublicAuthwit`, the Nulo wallet's method RavenHouse calls. For a
# token it is a spending approval: a request for another account, a caller
# that is the account itself, or a sheet that hides who gets it, each a way
# to sign something the person did not read.
GRANT_SRC=$ENGINE/src/app-grant.js
[[ -f $GRANT_SRC ]] || { echo "✗ $GRANT_SRC not found"; exit 1; }
(cd $ENGINE && node test/app-grant.test.mjs) || { echo "✗ the authorization checks failed"; exit 1; }
grant_mutant() { # name, perl expression
  perl -0pe "$2" $GRANT_SRC > $TMP/app-grant.js
  cmp -s $GRANT_SRC $TMP/app-grant.js && { echo "✗ mutation '$1' changed nothing"; exit 1; }
  if (cd $ENGINE && GRANT=$TMP/app-grant.js node test/app-grant.test.mjs >/dev/null 2>&1); then
    echo "✗ mutation '$1' passed: the authorization checks cannot see it"; exit 1
  fi
  echo "✓ mutation '$1' fails the authorization checks"
}
grant_mutant "an app grants from an account that is not connected" "s/  if \(!same\(account, me\)\) throw [^\n]*\n//"
grant_mutant "the account authorizes itself" "s/  if \(same\(caller, me\)\) throw [^\n]*\n//"
grant_mutant "a function name is taken unread" 's/\|\| !METHOD\.test\(method\)//'
grant_mutant "a long argument is drawn whole" 's/s\.length > 14 \?/s.length > 1400 ?/'
grep -q "if (method === 'grantPublicAuthwit') return grantForApp(wallet, args, origin);" $MAIN \
  || { echo "✗ main.js no longer answers grantPublicAuthwit"; exit 1; }
grep -q "const answer = await new Promise(resolve => waiting.set(id, resolve));" $MAIN \
  && grep -q "if (!answer.yes) throw new Error('The person declined grantPublicAuthwit');" $MAIN \
  || { echo "✗ an authorization is written without the person's yes"; exit 1; }
grep -q "const sent = await watched('app', () => sendOwn(wallet, grant, answer.gas, async () => (await ownFeeJuice(wallet)) > 0n));" $MAIN \
  || { echo "✗ an authorization's transaction no longer pays and takes turns as Casberi's sends do"; exit 1; }
grep -q 'It lets \\(grantee) make this call in your name, once. Anyone can see it.' Casberi/Casberi/Screens/AztecBrowser.swift \
  || { echo "✗ the sheet no longer says who an authorization is for"; exit 1; }

# ── What a call says (prd §1763) ─────────────────────────────────────────
# An app's call laid over its contract's own interface, for the sheet a
# person approves from: a wrong lay is a wrong recipient or amount.
WORDS_SRC=$ENGINE/src/call-words.js
[[ -f $WORDS_SRC ]] || { echo "✗ $WORDS_SRC not found"; exit 1; }
(cd $ENGINE && node test/call-words.test.mjs) || { echo "✗ the call-words checks failed"; exit 1; }
words_mutant() { # name, perl expression
  perl -0pe "$2" $WORDS_SRC > $TMP/call-words.js
  cmp -s $WORDS_SRC $TMP/call-words.js && { echo "✗ mutation '$1' changed nothing"; exit 1; }
  if (cd $ENGINE && WORDS=$TMP/call-words.js node test/call-words.test.mjs >/dev/null 2>&1); then
    echo "✗ mutation '$1' passed: the call-words checks cannot see it"; exit 1
  fi
  echo "✓ mutation '$1' fails the call-words checks"
}
words_mutant "a call that does not fit its interface is read anyway" 's/ \|\| sizes\.reduce\(\(a, b\) => a \+ b, 0\) !== flat\.length//'
words_mutant "a wide value shifts the ones after it" 's/    at \+= sizes\[i\];\n/    at += 1;\n/'
words_mutant "any number is drawn as the token's amount" 's/token && AMOUNT\.test\(params\[i\]\.name\) && /token \&\& /'
words_mutant "a dust amount is rounded to nothing" 's/  if \(!part && whole === 0n && n > 0n\) return [^\n]*\n//'
grep -q "calls.push({ name: c.name, to: tail(c.to), type: c.type, args: await wordsOf(wallet, c.to, c.name, c.args) });" $MAIN \
  || { echo "✗ the sheet is no longer told what each call says"; exit 1; }

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
