#!/bin/zsh
# Move's Details (prd §1509 item 1, docs/signing-safety-spec.md Phase 1) —
# the fee arithmetic, ERC-8213's digests, the revert words and the calls in
# words (`YourAccountPreview`), plus the wiring a compiler cannot see: sends
# are simulated before Face ID, a failing simulation dims the verb, "Not
# checked" is never drawn as "Lands as written", and signing takes the kept
# preview so the hash Raw transaction shows is the one Face ID signs.
#
# The Calldata Digest is pinned to ERC-8213's own test vector (the draft in
# ethereum/ERCs#1639, read 2026-10-24), and the revert words to the bytes
# Base's node returned for a USDC transfer from an empty address (measured
# the same day: `status 0x0`, `error.data` an `Error(string)`).
set -euo pipefail
cd "$(dirname "$0")/.."

PREVIEW="Casberi/Casberi/Model/YourAccountPreview.swift"
ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
ACROSS="Casberi/Casberi/Model/YourAccountAcross.swift"
ADAPTER="Casberi/Casberi/Model/YourAccount7579.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
ROUNDUPS="Casberi/Casberi/Model/RoundUps.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
CHAINPREVIEW="Casberi/Casberi/Model/YourAccountChain+Preview.swift"
SENTENCE="Casberi/Casberi/Screens/MoveSentence.swift"
DETAILS="Casberi/Casberi/Screens/MoveDetails.swift"
for f in "$PREVIEW" "$ACCOUNT" "$OP" "$SWAP" "$ACROSS" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" \
         "$CHAIN" "$CHAINPREVIEW" "$SENTENCE" "$DETAILS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/move-details-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/demo-stub.swift" <<'SWIFT'
enum YourAccountDemo {
    static var isOn: Bool { false }
    static var roundUps: RoundUps.Setting { RoundUps.Setting() }
}
// What `RoundUps.privatePools` reads (the review of 2026-10-26, finding 7):
// the kill switch on, an account on the phone.
enum PrivateMainnet { static let on = true }
enum YourAccountKey { static var stubbed: String? = "0x4a1a2b3c4d5e6f708192a3b4c5d6e7f809102030"; static var address: String? { stubbed } }
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias P = YourAccountPreview
var bad = 0, ran = 0
func check(_ ok: Bool, _ what: String) { ran += 1; if !ok { print("✗ " + what); bad += 1 } }
func money(_ usd: Double) -> String { String(format: "$%.2f", usd) }

// The fee: every gas limit times the most a unit costs, a ceiling.
check(P.networkFee(verification: 420_000, call: 140_000, preVerification: 60_000, maxFeePerGas: 5_000_000) == "3100000000000",
      "the fee is not (verification + call + preVerification) × maxFeePerGas")
check(P.networkFee(verification: .max, call: 1, preVerification: 0, maxFeePerGas: 1) == nil, "an overflowing fee was a number")
check(P.networkFee(verification: 1 << 40, call: 0, preVerification: 0, maxFeePerGas: 1 << 40) == nil, "an overflowing product was a number")
// …said as a ceiling, a cent the floor of "under a cent".
check(P.feePhrase(usd: 0.004, wei: "1", money: money) == "Fee under a cent", "a fee under a cent was not said so")
check(P.feePhrase(usd: 0.012, wei: "1", money: money) == "Fee up to $0.01", "a fee was not said as its ceiling (§83)")
check(P.feePhrase(usd: 0.01, wei: "1", money: money) == "Fee up to $0.01", "exactly a cent was said as under one")
check(P.feePhrase(usd: nil, wei: "3100000000000", money: money) == "Fee up to 0.0000031 ETH", "an unpriced fee did not fall back to the coin")

// The pool's fee, said as the pool charges it (prd §1539): a percentage of
// what passes through it, in the price, never added to the network's.
check(YourAccountSwap.percent(pips: 500) == "0.05%" && YourAccountSwap.percent(pips: 773) == "0.08%"
      && YourAccountSwap.percent(pips: 80) == "under 0.01%",
      "a pool fee is not said as its percentage, rounded (prd §1545)")

// ERC-8213's Calldata Digest, its own test vector.
let transfer = SafeABI.hexBytes("a9059cbb0000000000000000000000004675c7e5baafbffbca748158becba61ef3b0a2630000000000000000000000000000000000000000000000000de0b6b3a7640000")!
check(transfer.count == 68, "the vector's calldata is not 68 bytes")
check(P.hex(P.calldataDigest(transfer)) == "0x812cee5d9cc7461c04bbcd7b70af9c28b243ac5d74d3453b008b93b7dac69985",
      "the Calldata Digest is not ERC-8213's test vector")
check(P.calldataDigest([]) != P.calldataDigest([0]), "the length prefix does not separate empty from one zero byte")
check(P.HashKind.eip712.label == "EIP-712 Digest", "a SafeOp's hash is not labelled exactly as ERC-8213 names it")
check(P.HashKind.userOp.label == "Operation hash", "the session key's hash claims an EIP-712 name it is not")

// The revert, in words where the bytes carry them.
let base = "0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002645524332303a207472616e7366657220616d6f756e7420657863656564732062616c616e63650000000000000000000000000000000000000000000000000000"
check(P.revertReason(base) == "ERC20: transfer amount exceeds balance", "Base's measured revert did not decode")
check(P.revertReason("0x356680b7") == "InsufficientFunds()", "Robinhood USDG's measured custom error did not decode")
check(P.revertReason("0x4e487b710000000000000000000000000000000000000000000000000000000000000011") == "Panic 0x11", "a Panic did not decode")
check(P.revertReason("0x12345678") == "0x12345678", "an unknown error did not name its selector")
check(P.revertReason("0x") == nil && P.revertReason(nil) == nil && P.revertReason("zz") == nil, "nothing decoded to a reason")
check(P.revertReason("0x08c379a0" + String(repeating: "f", count: 128)) == nil, "a lying Error(string) length decoded")

// The red line: only a refusal draws it, naming the token that refused.
check(P.failLine(.fails(call: 0, token: "USDC", reason: nil), swap: false, network: "Base") == "This send would fail: USDC refuses it.",
      "a refused send did not name its token")
check(P.failLine(.fails(call: nil, token: nil, reason: nil), swap: true, network: "Base") == "This swap would fail on Base.",
      "a refused swap did not name its network")
check(P.failLine(.notChecked, swap: false, network: "Base") == nil, "a send no node checked was drawn as failing")
check(P.failLine(.lands, swap: false, network: "Base") == nil, "a send that lands drew a red line")
check(!P.Checked.notChecked.fails && P.Checked.fails(call: nil, token: nil, reason: nil).fails, "fails is not what fails")

// The calls in words.
check(P.rotate(to: 5) == P.Step(words: "Moves your account to a new key", detail: "This iPhone's key 5. The old key stops working."),
      "the key change is not said as the canvas says it")
check(P.send("25", "USDC", to: P.short("0x1a2B8f0c4E7d9A61b3C5e2F04d8a7B93c6E19cD0")).words == "Sends 25 USDC to ...9cD0",
      "a send's words changed")
check(P.approve("100", "USDC", to: "Uniswap").words == "Lets Uniswap spend exactly 100 USDC", "an approval is not said as exact")
check(P.swap("100", "USDC", atLeast: "0.0101", "ETH", on: "Aerodrome").words == "Swaps 100 USDC for at least 0.0101 ETH on Aerodrome",
      "a swap's words do not name the exchange that does it (prd §1539)")
check(P.short("0x12") == "0x12", "a short string was cut")
check(P.coin("4100000000000") == "0.0000041" && P.coin("1250000000000000000") == "1.25" && P.coin("0") == "0",
      "the fee in its coin is not two significant figures under one")

print(bad == 0 ? "move-details self-test: \(ran) checks ok" : "move-details self-test: \(bad) of \(ran) failed")
exit(bad == 0 ? 0 : 1)
SWIFT

xcrun swiftc -O -o "$TMP/t" "Casberi/Shared/AddressTail.swift" "$PREVIEW" "$ACCOUNT" "$OP" "$SWAP" "$ACROSS" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" \
  "$TMP/demo-stub.swift" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccountPreview.swift does not compile with Foundation and the Safe encoders alone"; exit 1; }
"$TMP/t" || exit 1

# The wiring. Every send is simulated before Face ID (§1509 item 3): the
# owner path through `assemble` and `require`, the session key's in sessionSend.
grep -q 'let simulated = await check(net, account: account, approvals: approvalCalls, steps: steps, symbols: symbols)' "$CHAIN" \
  || { echo "✗ assemble no longer simulates every step — sends would go unchecked again (prd §1509)"; exit 1; }
grep -q 'try require(a.simulated, on: net, swaps:' "$CHAIN" \
  || { echo "✗ transact signs without reading the simulation"; exit 1; }
awk '/static func sessionSend\(/,/^    }$/' "$CHAIN" | grep -q 'try require(await check(' \
  || { echo "✗ a send under the spend limit is no longer simulated"; exit 1; }
# A node that will not simulate refuses a swap and lets a send go, never the reverse.
awk '/static func require\(/,/^    }$/' "$CHAIN" | grep -A1 'case .notChecked:' | grep -q 'if swaps { throw' \
  || { echo "✗ 'not checked' no longer refuses a swap only (§1440 keeps the swap's proof)"; exit 1; }

# What Details showed is what is signed: the kept preview is taken by both
# signing paths, and its gas pinned only when the bytes are the same.
grep -q 'await Prepared.take(items, roundUp: roundUp, route: route)' "$CHAIN" \
  || { echo "✗ transact no longer signs the kept preview — Raw transaction's hash would not be Face ID's"; exit 1; }
grep -q 'await Prepared.take(payments.map(Item.send), roundUp: roundUp, route: .session)' "$CHAIN" \
  || { echo "✗ the session key no longer signs the kept preview"; exit 1; }
grep -q 'pinned.callData == op.callData' "$CHAIN" \
  || { echo "✗ a pinned preview is no longer checked byte for byte before its gas is reused"; exit 1; }
grep -q 'static let lifetime: TimeInterval = 60' "$CHAINPREVIEW" \
  || { echo "✗ a kept preview's lifetime moved — the page re-reads every 40s against 60"; exit 1; }
grep -q 'try? await Task.sleep(for: .seconds(40))' "$SENTENCE" \
  || { echo "✗ Move no longer re-reads its preview inside a kept preview's lifetime"; exit 1; }

# A refusal dims the verb; "Not checked" is never green.
grep -q 'stage == nil && !all.isEmpty && failNote == nil' "$SENTENCE" \
  || { echo "✗ a send the simulation refuses no longer dims its verb (canvas figure 9)"; exit 1; }
awk '/case .notChecked:/{getline; print}' "$DETAILS" | grep -q 'Lands as written\|confirmInk' \
  && { echo "✗ 'Not checked' is drawn as checked (§83)"; exit 1; }
grep -q 'case .lands:' "$DETAILS" && grep -q '"Lands as written"' "$DETAILS" \
  || { echo "✗ a simulated send no longer says it lands as written"; exit 1; }

# The demo reaches nothing (§1475): its preview is its table's.
awk '/static func preview\(/,/^    }$/' "$CHAINPREVIEW" | grep -q 'if YourAccountDemo.isDemo(account) { return demoPreview' \
  || { echo "✗ the demo's preview is no longer read off its table — the demo would reach a node"; exit 1; }
true
