#!/bin/zsh
# Aztec transaction self-test (prd §1711) — what the engine says about one
# Aztec transaction, run in node against Aztec's own types:
#
#   tools/aztec-engine/src/aztec-tx.js — an address anyone can receive at
#     (Aztec's own `isValid`), the private transfer a token's interface offers,
#     who pays an app's fee and what it costs at today's prices, and the hash
#     and fee off a receipt or an app's send
#   tools/aztec-engine/src/main.js     — the engine routes through it: every
#     send to an Aztec address is checked first, an app's send asks with its
#     fee, and lands in Activity
#
# Each failure it catches renders as a working send: a note sent to an
# address no one can read, a public transfer taken for a private one, a
# sponsor's fee said to come from your Fee Juice, a fee made up from nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

ENGINE=tools/aztec-engine
TX_SRC=$ENGINE/src/aztec-tx.js
MAIN=$ENGINE/src/main.js
TEST=$ENGINE/test/aztec-tx.test.mjs
for f in $TX_SRC $MAIN $TEST; do [[ -f $f ]] || { echo "✗ $f not found"; exit 1; }; done
[[ -d $ENGINE/node_modules/@aztec-labs/aztec.js ]] || (cd $ENGINE && npm ci --no-audit --no-fund >/dev/null)

# ── The engine goes through it, read ───────────────────────────────────
grep -q "if (!(await addressValid(AztecAddress, to))) throw new Error('No one can receive at this Aztec address');" $MAIN \
  || { echo "✗ main.js sends to an Aztec address it has not checked"; exit 1; }
grep -q "return own.sendToken(asset.token, to, units);" $MAIN \
  || { echo "✗ sendPrivately no longer goes through sendToken's checks"; exit 1; }
grep -q "const transfer = artifact && transferCall(artifact);" $MAIN \
  && grep -q "if (!transfer) throw new Error('This token cannot be sent from Casberi');" $MAIN \
  || { echo "✗ main.js sends a token without reading its transfer off its interface"; exit 1; }
grep -q "described = await describe(wallet, method, parsed);" $MAIN \
  && grep -q "const yes = await askPerson(method, origin, described);" $MAIN \
  || { echo "✗ an app's transaction is asked without its fee"; exit 1; }
grep -q "if (out.tx) native('engineSent', { origin, ...out, calls: described?.calls ?? \[\] });" $MAIN \
  || { echo "✗ an app's send no longer lands in Activity"; exit 1; }
grep -q "return receiptOut(receipt);" $MAIN \
  || { echo "✗ the engine's own sends no longer report their fee"; exit 1; }

# ── Run ────────────────────────────────────────────────────────────────
(cd $ENGINE && node test/aztec-tx.test.mjs) || { echo "✗ the Aztec transaction checks failed"; exit 1; }

# ── Mutations: each must fail the run, or the run proves nothing ───────
TMP=$(mktemp -d "$PWD/$ENGINE/.selftest.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
mutant() { # name, sed expression
  local name=$1 expr=$2 out=$TMP/m-$RANDOM.js
  sed "$expr" $TX_SRC > $out
  cmp -s $TX_SRC $out && { echo "✗ mutation '$name' changed nothing"; exit 1; }
  if (cd $ENGINE && TX=$out node test/aztec-tx.test.mjs >/dev/null 2>&1); then
    echo "✗ mutation '$name' passed: the checks cannot see it"; exit 1
  fi
  echo "✓ mutation '$name' fails the checks"
}
mutant "any 64 digits are an address" 's/  return address.isValid();/  return true;/'
mutant "a public transfer counts" "s/ \&\& String(f.functionType ?? 'private') === 'private'//"
mutant "the nonce is dropped" 's/args: (me, to, amount) => \[me, to, amount, 0n\]/args: (me, to, amount) => [me, to, amount]/'
mutant "a sponsor's fee is yours" "s/return from \&\& payer.equals?.(from) ? 'claim' : 'app';/return 'you';/"
mutant "the fee ignores today's prices" 's/return gasUsed.totalGas.computeFee(fees).toBigInt().toString();/return String(gasUsed.totalGas.l2Gas);/'

echo "aztec tx self-test: ok"
