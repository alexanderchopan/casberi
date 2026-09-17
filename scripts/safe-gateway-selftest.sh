#!/bin/zsh
# Casberi Safe Client Gateway self-test — the translation between Safe's two
# dialects (prd §789b):
#
#   Casberi/Casberi/Model/SafeGatewayShape.swift   (compiled whole)
#   Casberi/Casberi/Model/SafeBridge.swift
#   Casberi/Casberi/Model/SafeSigner.swift
#   Casberi/Casberi/Model/NetworkReach.swift
#
# WHY. On 2026-09-17 every Safe READ left `api.safe.global` — whose keyless
# tier is one 5,000-a-month pool shared with every keyless caller on earth, and
# which was measured EMPTY — for `safe-client.safe.global`, which is what
# `app.safe.global` itself reads: no quota, no auth scheme in its own OpenAPI,
# a per-IP burst cap a sequential pass never reaches.
#
# The readers inland (SafeBridge.describe, SafeSigner.transaction(from:), the
# confirmation walk) were NOT rewritten — they still parse the transaction
# service's row shape, and `SafeGatewayShape` adapts at the edge. So this file
# is where the four silent failures live, and every fixture below is a verbatim
# excerpt of a real response measured against a real Safe with a real pending
# queue, not a shape read off the spec:
#
#   1. an address is {value,name,logoUri} — except `gasToken`, which is bare
#   2. an absent guard is `null`, not the zero address
#   3. a time is milliseconds, where ClaudeImport.parseDate wants ISO 8601
#   4. the queued LIST carries no dataDecoded, and its LABEL/CONFLICT_HEADER
#      rows are furniture that carry no transaction at all
#
# Each one fails SILENTLY if mishandled: an empty owner set, a phantom guard,
# a missing date, a queue row built from furniture. None of them errors.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
#   scripts/safe-gateway-selftest.sh [--self-test]
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/SafeGatewayShape.swift"
BRIDGE="Casberi/Casberi/Model/SafeBridge.swift"
SIGNER="Casberi/Casberi/Model/SafeSigner.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$SHAPE" "$BRIDGE" "$SIGNER" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GATEWAY_HOST="safe-client.safe.global"
TXSERVICE_HOST="api.safe.global"

# --- wiring -------------------------------------------------------------------
# WHOLE-LINE comments only. The obvious `s://.*$::` also eats the `//` inside
# every `https://` string literal, which turns "the bridge names this host"
# into "the bridge names no host at all" and fails the code for the
# stripper's bug — paid for once here already.
strip() { local out="$TMP/${1:t}"; [[ -f "$out" ]] || grep -vE '^[[:space:]]*//' "$1" > "$out"; print -r -- "$out"; }
B=$(strip "$BRIDGE"); S=$(strip "$SIGNER")

wiring() {
  # Every read is on the gateway; the bridge names the old host nowhere.
  grep -qF "$GATEWAY_HOST" "$1" \
    || { echo "✗ SafeBridge no longer reads $GATEWAY_HOST — the reads went back to the exhausted pool"; return 1; }
  ! grep -qF "$TXSERVICE_HOST" "$1" \
    || { echo "✗ SafeBridge names $TXSERVICE_HOST — every READ moved to the gateway (prd §789b); only SafeSigner's one POST may stay"; return 1; }
  # The old tx-service paths do not survive against the new host: the gateway
  # has no /multisig-transactions/ read and its safe path takes no trailing /.
  ! grep -qF 'multisig-transactions' "$1" \
    || { echo "✗ SafeBridge still builds a /multisig-transactions/ path — the gateway does not serve one"; return 1; }
  return 0
}
wiring "$B" || exit 1

# The signer keeps its one POST on the transaction service and reads on the
# gateway. Both are Safe's; neither is optional.
grep -qF "$GATEWAY_HOST" "$S" \
  || { echo "✗ SafeSigner no longer reads the proposal from $GATEWAY_HOST — signing would still be gated on the empty pool"; exit 1; }
grep -qF "$TXSERVICE_HOST" "$S" \
  || { echo "✗ SafeSigner no longer names $TXSERVICE_HOST — the one confirmation POST has to land on the transaction service"; exit 1; }

# The gateway is a host this app reaches, so the privacy screen has to say so.
grep -qF "$GATEWAY_HOST" "$REACH" \
  || { echo "✗ NetworkReach does not disclose $GATEWAY_HOST — the privacy screen understates what this app reads"; exit 1; }

# --- the translation ----------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failed = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failed += 1 }
}
func json(_ s: String) -> Any? {
    try? JSONSerialization.jsonObject(with: Data(s.utf8))
}

// ─── measured: GET /v1/chains/1/safes/0x8CF60B28…  (SafeDAO treasury) ───
let safeState = json("""
{"address":{"value":"0x8CF60B289f8d31F737049B590b5E4285Ff0Bd1D1","name":null,"logoUri":null},
 "nonce":74,"threshold":3,
 "owners":[{"value":"0xee375Eb11b4Ca34407a49eD9E9D9bD246f9bf9d5","name":null,"logoUri":null},
           {"value":"0x6b28FdCF3059dd13847648213175dCa8853557B5","name":null,"logoUri":null}],
 "modules":[{"value":"0x4ECeFC422c98a096eD8b56EaD67477c4B6e8702b","name":null,"logoUri":null}],
 "guard":null,"version":"1.3.0"}
""")
let d = SafeGatewayShape.detail(safeState)
check(d?.nonce == 74, "the nonce is an Int here, where the service sent a string")
check(d?.threshold == 3, "the threshold survives")
check(d?.owners.count == 2, "an owner wrapped in {value,name,logoUri} is still an owner")
check(d?.owners.first == "0x6b28fdcf3059dd13847648213175dca8853557b5",
      "owners come back lowercased and sorted, as SafeConfig compares them")
check(d?.modules == ["0x4ecefc422c98a096ed8b56ead67477c4b6e8702b"], "a module is unwrapped too")
check(d?.guardAddr == nil, "TRAP 2: a null guard is no guard")

// The same read in the service's own dialect must still work — the app is not
// re-pointed by a flag, but a bare-string body is what every fixture and every
// cached shape elsewhere looks like, and silently dropping it would empty an
// owner set rather than fail.
check(SafeGatewayShape.detail(json("""
{"nonce":"5","threshold":2,"owners":["0xAA","0xBB"],"modules":[],
 "guard":"0x0000000000000000000000000000000000000000"}
""")).map { $0.owners == ["0xaa","0xbb"] && $0.guardAddr == nil && $0.nonce == 5 } == true,
      "a bare-string body reads identically, and the ZERO guard is also no guard")

// A body we did not understand is not an empty Safe (prd §83).
check(SafeGatewayShape.detail(json(#"{"threshold":2,"owners":[]}"#)) == nil,
      "a body with no owners is unreadable, NOT a Safe with nobody on it")
check(SafeGatewayShape.detail(json(#"{"error":"nope"}"#)) == nil, "an error body is not a config")
check(SafeGatewayShape.detail(nil) == nil, "a refused read is not a config")

// ─── measured: GET /v1/chains/1/owners/0xee375Eb1…/safes ───
check(SafeGatewayShape.ownerSafes(json("""
{"safes":["0x0B00b3227A5F3df3484f03990A87e02EbaD2F888","0x8CF60B289f8d31F737049B590b5E4285Ff0Bd1D1"]}
""")) == ["0x0B00b3227A5F3df3484f03990A87e02EbaD2F888","0x8CF60B289f8d31F737049B590b5E4285Ff0Bd1D1"],
      "the owner lookup needed no translation at all — same envelope as the service")
check(SafeGatewayShape.ownerSafes(json(#"{"results":[]}"#)) == nil,
      "a body with no `safes` key is unreadable, not an address that signs for nothing")
check(SafeGatewayShape.ownerSafes(nil) == nil, "a refused owner lookup is not an empty list")

// ─── measured: GET …/transactions/queued on a Safe with two pending ───
let queued = json("""
{"count":2,"next":null,"previous":null,"results":[
 {"type":"LABEL","label":"Next"},
 {"type":"TRANSACTION","transaction":{"id":"multisig_0x0391_0xeb6e","txStatus":"AWAITING_CONFIRMATIONS",
   "txInfo":{"type":"Custom","methodName":"multiSend","actionCount":2},
   "executionInfo":{"type":"MULTISIG","nonce":2,"confirmationsRequired":2,
     "confirmationsSubmitted":1,"missingSigners":[{"value":"0xb1Df"}]}},"conflictType":"None"},
 {"type":"CONFLICT_HEADER","nonce":3},
 {"type":"TRANSACTION","transaction":{"id":"multisig_0x0391_0xaaaa","txStatus":"AWAITING_CONFIRMATIONS",
   "txInfo":{"type":"Custom"},"executionInfo":{"type":"MULTISIG","nonce":3}},"conflictType":"HasNext"}]}
""")
check(SafeGatewayShape.queuedIDs(queued) == ["multisig_0x0391_0xeb6e","multisig_0x0391_0xaaaa"],
      "TRAP 4: LABEL and CONFLICT_HEADER are furniture — only transactions carry ids")
check(SafeGatewayShape.queuedIDs(json(#"{"count":0,"results":[]}"#)) == [],
      "an EMPTY queue is an empty list, and must not be nil — nil means unreachable")
check(SafeGatewayShape.queuedIDs(nil) == nil, "a refused queue read is nil, never an empty queue")
check(SafeGatewayShape.queuedIDs(json(#"{"count":1}"#)) == nil, "a body with no results is unreadable")

// ─── measured: GET /v1/chains/1/transactions/0xeb6ead7a…  (a real multiSend) ───
let details = json("""
{"safeAddress":"0x03916D54Cd6287325B6cF6A9A02a12F79676266C","txStatus":"AWAITING_CONFIRMATIONS",
 "executedAt":null,
 "txData":{"hexData":"0xdeadbeef","value":"0","operation":1,
   "to":{"value":"0x9641d764fc13c8B624c04430C7356C1C7C8102e2","name":null,"logoUri":null},
   "dataDecoded":{"method":"multiSend","parameters":[{"name":"transactions","type":"bytes","value":"0x00"}]}},
 "detailedExecutionInfo":{"type":"MULTISIG","nonce":2,"safeTxGas":"0","baseGas":"0","gasPrice":"0",
   "gasToken":"0x0000000000000000000000000000000000000000",
   "refundReceiver":{"value":"0x0000000000000000000000000000000000000000","name":null,"logoUri":null},
   "safeTxHash":"0xeb6ead7a1283a706a527abd3f0366c65135bf3829065de81eb4c214007ad9770",
   "submittedAt":1778185203879,"confirmationsRequired":2,
   "confirmations":[{"signer":{"value":"0x3242071b0b406B6661AF2dE1115CD46567Ab0917"},
     "signature":"0x5b49","submittedAt":1778185203879}]}}
""")
let row = SafeGatewayShape.txRow(details)
check(row?["safe"] as? String == "0x03916D54Cd6287325B6cF6A9A02a12F79676266C", "the Safe comes back")
check(row?["to"] as? String == "0x9641d764fc13c8B624c04430C7356C1C7C8102e2",
      "TRAP 1: the destination is nested under {value}, where the service sent it bare")
check(row?["data"] as? String == "0xdeadbeef", "`hexData` becomes the `data` the encoder signs")
check(row?["operation"] as? Int == 1, "operation 1 (DELEGATECALL) survives — a multiSend is not a call")
check(row?["value"] as? String == "0", "value stays a string, which is what amountField expects")
check(row?["nonce"] as? Int == 2, "the nonce is on the row, not nested, where transaction(from:) reads it")
check((row?["dataDecoded"] as? [String: Any])?["method"] as? String == "multiSend",
      "the decoded call rides along — this is what the list could NOT give us (§652)")
check(row?["safeTxHash"] as? String == "0xeb6ead7a1283a706a527abd3f0366c65135bf3829065de81eb4c214007ad9770",
      "the service's own hash claim, which SafeSigner re-encodes and refuses on mismatch")
check(row?["gasToken"] as? String == "0x0000000000000000000000000000000000000000",
      "TRAP 1 again: gasToken arrives BARE while refundReceiver beside it is wrapped")
check(row?["refundReceiver"] as? String == "0x0000000000000000000000000000000000000000",
      "…and the wrapped one unwraps to the same spelling")
check(row?["isExecuted"] as? Bool == false, "a null executedAt is not executed")
check(row?["confirmationsRequired"] as? Int == 2, "the threshold for THIS transaction")

// TRAP 3 — the dates. An Int handed to ClaudeImport.parseDate is nil, and nil
// is "no date", which is not an error anywhere downstream.
check(row?["submissionDate"] as? String == "2026-05-07T20:20:03Z",
      "TRAP 3: milliseconds become the ISO 8601 spelling ClaudeImport.parseDate reads")
let confs = row?["confirmations"] as? [[String: Any]]
check(confs?.count == 1, "one confirmation")
check(confs?.first?["owner"] as? String == "0x3242071b0b406B6661AF2dE1115CD46567Ab0917",
      "a confirmation's `signer` becomes the `owner` the walk reads")
check(confs?.first?["submissionDate"] as? String == "2026-05-07T20:20:03Z",
      "a confirmation's own time is converted too — signedAt reads it per owner")
check(SafeGatewayShape.iso8601(millis: nil) == nil, "no time is no date, not the epoch")

// An executed transaction, so the pending-duration line has both ends.
let done = SafeGatewayShape.txRow(json("""
{"safeAddress":"0xAA","executedAt":1778199999000,
 "txData":{"hexData":"0x","value":"0","operation":0,"to":{"value":"0xBB"}},
 "detailedExecutionInfo":{"nonce":1,"safeTxGas":"0","baseGas":"0","gasPrice":"0",
   "submittedAt":1778185203879,"confirmations":[]}}
"""))
check(done?["isExecuted"] as? Bool == true, "a real executedAt IS executed")
check(done?["executionDate"] as? String == "2026-05-08T00:26:39Z", "and it dates the outcome")

// A body that is not a multisig transaction at all.
check(SafeGatewayShape.txRow(json(#"{"safeAddress":"0xAA","txData":{}}"#)) == nil,
      "no detailedExecutionInfo is not a queued Safe transaction — nil, not a half-built row")
check(SafeGatewayShape.txRow(nil) == nil, "a refused detail read is not a row")

// The scalars, because everything above rests on them.
check(SafeGatewayShape.address("0xAA") == "0xAA", "a bare address")
check(SafeGatewayShape.address(["value": "0xBB"]) == "0xBB", "a wrapped address")
check(SafeGatewayShape.address(["name": "Safe"]) == nil, "an object with no value is no address")
check(SafeGatewayShape.address("") == nil, "an empty string is no address")
check(SafeGatewayShape.address(NSNull()) == nil, "a null is no address")
check(SafeGatewayShape.int("7") == 7 && SafeGatewayShape.int(7) == 7, "an Int from either dialect")

if failed > 0 { print("\n✗ \(failed) gateway-shape check(s) failed"); exit(1) }
SWIFT

xcrun swiftc -O -o "$TMP/safegw" "$SHAPE" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/safegw" ]] || { echo "✗ the harness did not compile — SafeGatewayShape.swift is no longer Foundation-only"; exit 1; }
"$TMP/safegw"

# --- does this check catch anything? (--self-test) -----------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  echo
  echo "self-test: each mutation below MUST be caught"
  st_fail=0
  expect_caught() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "  FAIL not caught: $what"; st_fail=1
    else echo "  ok   caught: $what"; fi
  }

  # A bridge that went back to the exhausted pool.
  M="$TMP/mut-bridge.swift"
  sed "s|$GATEWAY_HOST|$TXSERVICE_HOST/tx-service|" "$B" > "$M"
  expect_caught "SafeBridge reading api.safe.global again" wiring "$M"

  # A bridge that kept a path the gateway does not serve.
  M2="$TMP/mut-path.swift"
  { cat "$B"; echo 'let dead = "\(baseURL(chain))/multisig-transactions/x/"' } > "$M2"
  expect_caught "a /multisig-transactions/ read the gateway has no route for" wiring "$M2"

  # The four traps, each mutated in the shape file itself — a check that cannot
  # fail when the code is wrong is a check that certifies nothing.
  mutate_shape() {   # <perl-expr> <name>
    local out="$TMP/mut-shape.swift"
    perl -0pe "$1" "$SHAPE" > "$out"
    if ! cmp -s "$out" "$SHAPE"; then
      if xcrun swiftc -O -o "$TMP/mutbin" "$out" "$TMP/main.swift" 2>/dev/null && "$TMP/mutbin" >/dev/null 2>&1; then
        echo "  FAIL not caught: $2"; st_fail=1
      else
        echo "  ok   caught: $2"
      fi
    else
      echo "  FAIL mutation never applied (anchor drifted): $2"; st_fail=1
    fi
  }
  # TRAP 1 — stop unwrapping {value}.
  mutate_shape 's/if let o = any as\? \[String: Any\], let v = o\["value"\] as\? String \{/if false, let o = any as? [String: Any], let v = o["value"] as? String {/' \
               "an address left wrapped in {value} (an empty owner set)"
  # TRAP 2 — treat the zero address as a real guard.
  mutate_shape 's/\(raw == nil \|\| raw == zeroAddress\)/(raw == nil)/' \
               "the zero address read as a real guard"
  # TRAP 3 — hand milliseconds straight through.
  mutate_shape 's/f\.dateFormat = "yyyy-MM-dd.T.HH:mm:ss.Z."/f.dateFormat = "yyyy-MM-dd"/' \
               "a date that loses its time"
  # TRAP 4 — let the list's furniture through as queue entries. Mutating the
  # `type` check alone does NOTHING (furniture carries no `transaction` key at
  # all, so the next guard still drops it) and would print a passing line for a
  # mutation that never ran. The load-bearing part is that a row which yields
  # no id yields no ENTRY, so that is what is broken here.
  mutate_shape 's/!id\.isEmpty\s*\n(\s*)else \{ return nil \}/!id.isEmpty\n$1else { return "" }/' \
               "LABEL and CONFLICT_HEADER rows counted as queued transactions"
  # An unreadable body folded into an empty answer (prd §83 / §789).
  mutate_shape 's/guard !owners\.isEmpty else \{ return nil \}//' \
               "a body with no owners returned as a Safe with nobody on it"

  [[ $st_fail -eq 0 ]] || { echo "✗ a mutation went uncaught — this check certifies nothing"; exit 1; }
  echo "  ✓ every mutation caught"
fi

echo
echo "✓ safe gateway: Safe's two dialects translate, and the reads are off the exhausted pool"
