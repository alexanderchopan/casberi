#!/bin/zsh
# ENS renew self-test — the SHIPPED encoding behind the renew card (prd §540,
# paid in a stablecoin since ENSv2, prd §1585):
#
#   Casberi/Casberi/Model/ENSRenew.swift
#     — calldata / priceCalldata / isRenewableCalldata  (the ABI bytes)
#     — approveCalldata / handoffJSON  (the exact approval, then the renewal)
#     — Amount / tokenLine        (a 32-byte word, never a Double; rounded up)
#     — encodedString             (dynamic-string encoding)
#     — selector                  (derived from the signature, not pasted)
#     — ownershipNote             (the one sentence permissionless renewal owes)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here alongside `Keccak256.swift` — no extraction, no copy. Every
# assertion is about the bytes the app runs.
#
# WHY THIS HARNESS IS THE MOST LOAD-BEARING ONE IN THE ENS SET. Every other
# prepared transaction this app produces carries `"value": "0x0"` — a revoke
# costs gas and moves nothing. This one MOVES REAL MONEY when signed, and the
# failure mode is not a crash: a wrong byte produces a transaction that is
# well-formed, that a wallet will render a confirm screen for, and that a chain
# will execute — doing something nobody asked for. The build is green, the card
# looks right, the tap is right, and the money leaves. That is the same class
# `safetx-selftest.sh` exists for, and the same answer: pinned vectors.
#
# THE VECTORS ARE FROM AN INDEPENDENT IMPLEMENTATION, not from this code. They
# were produced by viem 2.56.7's `encodeFunctionData` on 2026-10-28 and
# cross-checked against the live contracts: every selector is in BOTH
# `ETHRenewerV1`'s and `ETHRegistrar`'s deployed bytecode, and `getRenewPrice`
# calls built the same way returned $8.000021 / $160.000009 / $640.000005 a
# year in USDC. A test that only agrees with the thing it tests proves nothing.
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches a chain, so it says
# nothing about whether the controller is still authorized or still prices this
# way — that is `-ensRenewProbe`'s job and `live-integrations.sh`'s. And it
# cannot prove a renewal SUCCEEDS: nothing on this host owns a `.eth` name to
# renew, so no transaction encoded here has ever been signed or submitted.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RENEW="Casberi/Casberi/Model/ENSRenew.swift"
PREPARE="Casberi/Casberi/Model/ENSRenewPrepare.swift"
CARD="Casberi/Casberi/Screens/ENSRenewCard.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
for f in "$RENEW" "$PREPARE" "$CARD" "$KECCAK"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/ens-renew-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# A COMMENT-STRIPPED copy for every negative guard. All three files DOCUMENT
# their rules by naming what they must not do ("signs nothing", "no owner
# check", "the two-argument form"), so a guard grepping raw source fires on the
# prose explaining it (the Obsidian/Cursor lesson).
strip() {
  python3 - "$1" <<'PY'
import re, sys
for line in open(sys.argv[1]).read().split("\n"):
    if line.strip().startswith("//"):
        continue
    print(re.sub(r'\s//(?!/).*$', '', line))
PY
}
strip "$RENEW" > "$TMP/renew.stripped"
strip "$PREPARE" > "$TMP/prepare.stripped"
strip "$CARD" > "$TMP/card.stripped"

# --- conduct guards ----------------------------------------------------------
# This seat's whole promise is that it PREPARES and never signs. Unlike the
# read-only bridges, breaking this doesn't leak data — it spends money.

for verb in eth_sendTransaction eth_sendRawTransaction personal_sign eth_sign signTypedData; do
  if grep -q "$verb" "$TMP/renew.stripped" "$TMP/prepare.stripped" "$TMP/card.stripped"; then
    echo "✗ the ENS renew path names '$verb' — this surface PREPARES a"
    echo "  transaction and hands it over (§112). It must never submit or sign one."
    exit 1
  fi
done
if grep -qE 'SignerKey|SafeSigner|WalletConnect' "$TMP/renew.stripped" "$TMP/prepare.stripped" "$TMP/card.stripped"; then
  echo "✗ the ENS renew path reaches a signer — §540 ships the hand-off ONLY."
  echo "  In-app signing is its own decision with its own review, not a rider."
  exit 1
fi

# --- drift guards ------------------------------------------------------------

# The card must never be offered on a RELEASED name: `renew` REVERTS there
# (registering a released name is a different call at a different price), so a
# Renew control on one takes money and fails.
grep -q 'case .expiring, .grace: return true' "$TMP/prepare.stripped" \
  || { echo "✗ ENSRenewPrepare.applies no longer gates on .expiring/.grace alone —"; \
       echo "  a renew card on a RELEASED name is a control that reverts"; exit 1; }

# Fail CLOSED on a short reply. "0x" parses to zero, and a price of zero shown
# to somebody about to sign is the worst number this card could print; every
# read goes through `ENSRenew.Amount(reply:)`, which refuses it.
grep -q 'return ENSRenew.Amount(reply: hex)' "$TMP/prepare.stripped" \
  || { echo "✗ ENSRenewPrepare no longer reads through ENSRenew.Amount(reply:) —"; \
       echo "  a reverted read would parse as a FREE renewal"; exit 1; }

# The contract is the one the CHAIN says renews this name, never a constant:
# an unmigrated name renews only through ETHRenewerV1 and a migrated one only
# through ETHRegistrar (measured), and the wrong one reverts after the approval.
grep -q 'return yes.count == 1 ? yes\[0\].0 : nil' "$TMP/prepare.stripped" \
  || { echo "✗ ENSRenewPrepare no longer requires exactly one contract to say"; \
       echo "  isRenewable — the card could name the contract that reverts"; exit 1; }

# Never an open-ended approval. The price is exact, so the allowance is too; a
# max-uint approval is the exposure this app's own approvals card flags.
grep -qiE 'f{16}' "$TMP/renew.stripped" \
  && { echo "✗ ENSRenew.swift spells a max-uint word — the renewal approves the"; \
       echo "  exact price, never an open-ended allowance"; exit 1; }

# The card must state the permissionless-ownership fact. Measured: `renew` has
# no owner check, so this card can renew a stranger's name, and paying does not
# transfer it.
grep -q 'ENSRenew.ownershipNote' "$TMP/card.stripped" \
  || { echo "✗ the renew card no longer draws ownershipNote — renewing is"; \
       echo "  permissionless, and 'paying does not transfer it' is the one"; \
       echo "  sentence somebody must not learn after signing"; exit 1; }

# The label, never the name.
grep -q 'ENSName.label(of: name)' "$TMP/prepare.stripped" \
  || { echo "✗ ENSRenewPrepare no longer takes the LABEL from ENSName.label —"; \
       echo "  handing the controller 'vitalik.eth' renews a different entry"; exit 1; }

# --- compile + assert --------------------------------------------------------

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    print(ok ? "  ✓ \(label)" : "  ✗ \(label)")
    if !ok { failures += 1 }
}
func eq(_ label: String, _ got: String?, _ want: String?) {
    check(label, got == want)
    if got != want { print("      got  \(got ?? "nil")\n      want \(want ?? "nil")") }
}

print("selectors — derived from the signature, pinned to the DEPLOYED bytecode")
// Measured 2026-10-28: 2d06649b, ddf0effc and 130d6f00 are PUSH4s in both
// ETHRenewerV1's and ETHRegistrar's bytecode.
eq("renew((string,uint64,bytes32),address)", "0x" + ENSRenew.selector(ENSRenew.renewSignature), "0x2d06649b")
eq("getRenewPrice(string,uint64,address)", "0x" + ENSRenew.selector(ENSRenew.priceSignature), "0xddf0effc")
eq("isRenewable(string)", "0x" + ENSRenew.selector(ENSRenew.isRenewableSignature), "0x130d6f00")
eq("approve(address,uint256)", "0x" + ENSRenew.selector(ENSRenew.approveSignature), "0x095ea7b3")

print("the contracts and tokens — measured on mainnet, not recalled")
eq("ETHRenewerV1", ENSRenew.Contract.renewer.address, "0x56c447F308F463A01121C41E72b0E7e7557fCb68")
eq("ETHRegistrar", ENSRenew.Contract.registrar.address, "0xD6D8369e55c94Ae8AFA714E6cF7AB5bE54D5CC81")
eq("USDC", ENSRenew.Token.usdc.address, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
eq("DAI", ENSRenew.Token.dai.address, "0x6B175474E89094C44Da98b954EedeAC495271d0F")
check("USDC has 6 decimals, DAI 18", ENSRenew.Token.usdc.decimals == 6 && ENSRenew.Token.dai.decimals == 18)
check("USDC is tried first", ENSRenew.Token.allCases.first == .usdc)
check("the oracle takes these two and nothing else", ENSRenew.Token.allCases.count == 2)
check("mainnet, and there is no chain picker", ENSRenew.chainID == 1)
check("ENS's 365-day year, not a calendar year", ENSRenew.year == 31_536_000)

print("renew calldata — vectors from viem")
eq("vitalik / 1 year / USDC", ENSRenew.calldata(label: "vitalik", term: .oneYear, token: .usdc),
 "0x2d06649b0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e1338000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007766974616c696b00000000000000000000000000000000000000000000000000")
eq("abc / 2 years / DAI", ENSRenew.calldata(label: "abc", term: .twoYears, token: .dai),
 "0x2d06649b00000000000000000000000000000000000000000000000000000000000000400000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000003c26700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036162630000000000000000000000000000000000000000000000000000000000")
// A 32-byte label is EXACTLY one word. The naive `32 - count % 32` appends a
// whole dead word here, which no ordinary name would ever reveal.
eq("32-byte label adds no padding word",
   ENSRenew.calldata(label: String(repeating: "a", count: 32), term: .oneYear, token: .usdc),
 "0x2d06649b0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e13380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000206161616161616161616161616161616161616161616161616161616161616161")
eq("33-byte label spills to a second word",
   ENSRenew.calldata(label: String(repeating: "a", count: 33), term: .oneYear, token: .usdc),
 "0x2d06649b0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e133800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002161616161616161616161616161616161616161616161616161616161616161616100000000000000000000000000000000000000000000000000000000000000")
// "café" is FOUR characters and FIVE UTF-8 bytes.
eq("multi-byte label counts BYTES, not characters",
   ENSRenew.calldata(label: "café", term: .oneYear, token: .usdc),
 "0x2d06649b0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e1338000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005636166c3a9000000000000000000000000000000000000000000000000000000")

print("the reads' calldata — vectors from viem")
eq("getRenewPrice vitalik / 1 year / USDC", ENSRenew.priceCalldata(label: "vitalik", term: .oneYear, token: .usdc),
 "0xddf0effc00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e13380000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000000007766974616c696b00000000000000000000000000000000000000000000000000")
eq("getRenewPrice abc / 5 years / DAI", ENSRenew.priceCalldata(label: "abc", term: .fiveYears, token: .dai),
 "0xddf0effc000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000096601800000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000000036162630000000000000000000000000000000000000000000000000000000000")
eq("isRenewable casberi", ENSRenew.isRenewableCalldata(label: "casberi"),
 "0x130d6f00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000076361736265726900000000000000000000000000000000000000000000000000")
eq("allowance", ENSRenew.allowanceCalldata(owner: "0x1111111111111111111111111111111111111111", spender: .renewer),
 "0xdd62ed3e000000000000000000000000111111111111111111111111111111111111111100000000000000000000000056c447f308f463a01121c41e72b0e7e7557fcb68")
eq("balanceOf", ENSRenew.balanceCalldata(owner: "0x1111111111111111111111111111111111111111"),
 "0x70a082310000000000000000000000001111111111111111111111111111111111111111")

print("the approval — exactly the price, never more")
let eight = ENSRenew.Amount(reply: "0x" + String(format: "%064x", 8_000_021))!
eq("8.000021 USDC to the renewer", ENSRenew.approveCalldata(spender: .renewer, amount: eight),
 "0x095ea7b300000000000000000000000056c447f308f463a01121c41e72b0e7e7557fcb6800000000000000000000000000000000000000000000000000000000007a1215")
// 3,200 DAI is 3.2 × 10²¹ base units, past a UInt64: the word is the chain's.
let big = ENSRenew.Amount(reply: "0x0000000000000000000000000000000000000000000000ad78ebc5ac62000000")!
eq("3,200 DAI to the registrar (past UInt64)", ENSRenew.approveCalldata(spender: .registrar, amount: big),
 "0x095ea7b3000000000000000000000000d6d8369e55c94ae8afa714e6cf7ab5be54d5cc810000000000000000000000000000000000000000000000ad78ebc5ac62000000")

print("the two head layouts differ, and sharing an offset would break one")
check("renew's tuple sits at 0x40, two head words",
      ENSRenew.calldata(label: "abc", term: .oneYear, token: .usdc)!.dropFirst(10).prefix(64)
        == String(repeating: "0", count: 62) + "40")
check("getRenewPrice's string sits at 0x60, three head words",
      ENSRenew.priceCalldata(label: "abc", term: .oneYear, token: .usdc)!.dropFirst(10).prefix(64)
        == String(repeating: "0", count: 62) + "60")

print("refusals — the label, never the name")
check("a full name is refused", ENSRenew.calldata(label: "vitalik.eth", term: .oneYear, token: .usdc) == nil)
check("an empty label is refused", ENSRenew.calldata(label: "", term: .oneYear, token: .usdc) == nil)
check("whitespace is refused", ENSRenew.calldata(label: "a b", term: .oneYear, token: .usdc) == nil)
check("priceCalldata refuses the same", ENSRenew.priceCalldata(label: "a.b", term: .oneYear, token: .usdc) == nil)
check("isRenewableCalldata refuses the same", ENSRenew.isRenewableCalldata(label: "a.b") == nil)
check("a malformed owner is refused", ENSRenew.balanceCalldata(owner: "0xabc") == nil)

print("amounts — the chain's word, and a short reply is no price")
check("\"0x\" (a revert) is no amount, never zero", ENSRenew.Amount(reply: "0x") == nil)
check("a short reply is no amount", ENSRenew.Amount(reply: "0x1234") == nil)
check("a non-hex reply is no amount", ENSRenew.Amount(reply: "0x" + String(repeating: "z", count: 64)) == nil)
check("a zero word is zero", ENSRenew.Amount(reply: "0x" + String(repeating: "0", count: 64))!.isZero)
let seven = ENSRenew.Amount(reply: "0x" + String(format: "%064x", 7_999_999))!
check("amounts compare as numbers", seven < eight && !(eight < seven))
check("a word compares above any smaller one, past UInt64", eight < big)

print("words — exact, and never shown below what is taken")
eq("8.000021 USDC", ENSRenew.tokenLine(eight, .usdc), "8.000021 USDC")
eq("an even figure keeps two places", ENSRenew.tokenLine(ENSRenew.Amount(reply: "0x" + String(format: "%064x", 160_000_000))!, .usdc), "160.00 USDC")
eq("past UInt64, grouped", ENSRenew.tokenLine(big, .dai), "3,200.00 DAI")
// 8.000020944 DAI, measured: six places rounds UP to 8.000021, never down.
let dai = ENSRenew.Amount(reply: "0x" + String(format: "%064llx", UInt64(8_000_020_944_000_000_000)))!
eq("a seventh place rounds up", ENSRenew.tokenLine(dai, .dai), "8.000021 DAI")
check("the fee is in ETH", ENSRenew.ethLine(4e14) == "0.0004 ETH")

print("the hand-off")
let from = "0x1111111111111111111111111111111111111111"
let renewOnly = ENSRenew.handoffJSON(from: from, contract: .renewer, label: "vitalik", term: .oneYear,
                                     token: .usdc, amount: eight, needsApproval: false)!
check("enough allowance: one object, the renewal", renewOnly.hasPrefix("{") && renewOnly.contains(ENSRenew.Contract.renewer.address))
// nonpayable: any ETH attached reverts.
check("the renewal carries no ETH", renewOnly.contains("\"value\": \"0x0\""))
check("it names chain 1", renewOnly.contains("\"chainId\": 1"))
let both = ENSRenew.handoffJSON(from: from, contract: .registrar, label: "nick", term: .oneYear,
                                token: .dai, amount: eight, needsApproval: true)!
check("short allowance: an array, approval FIRST", both.hasPrefix("[")
      && both.range(of: ENSRenew.Token.dai.address)!.lowerBound < both.range(of: ENSRenew.Contract.registrar.address + "\"")!.lowerBound)
check("the approval goes to the TOKEN and names the renewing contract",
      both.contains(ENSRenew.approveCalldata(spender: .registrar, amount: eight)))
check("neither carries ETH", both.components(separatedBy: "\"value\": \"0x0\"").count == 3)
check("no hand-off without a sender",
      ENSRenew.handoffJSON(from: "", contract: .renewer, label: "vitalik", term: .oneYear,
                           token: .usdc, amount: eight, needsApproval: false) == nil)
check("no approval for nothing",
      ENSRenew.handoffJSON(from: from, contract: .renewer, label: "vitalik", term: .oneYear,
                           token: .usdc, amount: ENSRenew.Amount(reply: "0x" + String(repeating: "0", count: 64))!,
                           needsApproval: true) == nil)

print("the sentence permissionless renewal owes")
check("a name that isn't yours gets the warning",
      ENSRenew.ownershipNote(isYours: false)?.lowercased().contains("does not transfer") == true)
check("your own name doesn't", ENSRenew.ownershipNote(isYours: true) == nil)

print("")
if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("All assertions passed.")
SWIFT

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 1.6x faster).
# Re-probe before trusting it again after adding mutations.
swiftc -Onone -o "$TMP/run" "$RENEW" "$KECCAK" "$TMP/main.swift" 2>&1 | head -30
"$TMP/run"

# --- mutations ---------------------------------------------------------------
# Each is a silent wrong answer that renders as a perfectly ordinary card. A
# check that cannot fail proves nothing.
echo
echo "mutations (each must be caught)"
mutate() {
  local label="$1" from="$2" to="$3"
  mkdir -p "$TMP/m"
  python3 - "$RENEW" "$TMP/m/ENSRenew.swift" "$from" "$to" <<'PY' || { echo "  ✗ STALE MUTATION: the applier exited non-zero (anchor not found — nothing was tested)"; exit 1; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if a not in s:
    print(f"MUTATION TARGET NOT FOUND: {a[:70]}"); sys.exit(2)
open(dst, "w").write(s.replace(a, b, 1))
PY
  if swiftc -Onone -o "$TMP/m/run" "$TMP/m/ENSRenew.swift" "$KECCAK" "$TMP/main.swift" 2>/dev/null; then
    if "$TMP/m/run" >/dev/null 2>&1; then
      echo "  ✗ NOT CAUGHT: $label"; exit 1
    fi
  fi
  echo "  ✓ $label"
}

# 1. The registrar and the renewer swapped — every name renews through the
#    contract that reverts on it, after the approval was paid for.
mutate "the two contracts swapped" \
  'case .renewer:   return "0x56c447F308F463A01121C41E72b0E7e7557fCb68"' \
  'case .renewer:   return "0xD6D8369e55c94Ae8AFA714E6cF7AB5bE54D5CC81"'

# 2. §540's renew — the v1 controller's three-argument call, absent from both.
mutate "the v1 renew signature" \
  '"renew((string,uint64,bytes32),address)"' \
  '"renew(string,uint256,bytes32)"'

# 3. The tuple's offset taken for the price read's — the string is decoded
#    from the wrong place.
mutate "renew's tuple offset set to 0x60" \
  'return "0x" + selector(renewSignature)
            + word(0x40)' \
  'return "0x" + selector(renewSignature)
            + word(0x60)'

# 4. The string offset counted from the calldata, not the tuple.
mutate "the string offset inside the tuple set to 0xa0" \
  '+ addressWord(token.address)
            + word(0x60)
            + word(term.seconds)
            + noReferrer' \
  '+ addressWord(token.address)
            + word(0xa0)
            + word(term.seconds)
            + noReferrer'

# 5. Characters instead of bytes — a truncated label, signed and paid for.
mutate "string length counted in characters" \
  'var hex = word(bytes.count)' \
  'var hex = word(s.count)'

# 6. The dead padding word on an exactly-32-byte label.
mutate "padding added even at a word boundary" \
  'if remainder != 0 { hex += String(repeating: "00", count: 32 - remainder) }' \
  'hex += String(repeating: "00", count: 32 - remainder)'

# 7. A short reply read as a price — "0x" becomes a free renewal.
mutate "a short reply accepted as an amount" \
  'guard hex.count >= 64 else { return nil }
            let first = String(hex.prefix(64))' \
  'let first = String(hex.padding(toLength: 64, withPad: "0", startingAt: 0).prefix(64))'

# 8. Display rounded DOWN — the card shows less than the approval takes.
mutate "the figure rounds down" \
  'NSDecimalRound(&rounded, &value, 6, .up)' \
  'NSDecimalRound(&rounded, &value, 6, .down)'

# 9. The approval sent after the renewal — the renewal reverts on a missing
#    allowance, then the approval stands open.
mutate "the renewal ordered before the approval" \
  'return "[" + approve + ", " + renew + "]"' \
  'return "[" + renew + ", " + approve + "]"'

# 10. USDC's decimals read as DAI's — every figure off by 10¹².
mutate "USDC read with 18 decimals" \
  'case .usdc: return 6' \
  'case .usdc: return 18'

# 11. A full name accepted as a label — renews an entry nobody owns.
mutate "a dotted name accepted as a label" \
  '!label.isEmpty && !label.contains(".") && !label.contains(where: \.isWhitespace)' \
  '!label.isEmpty'

# 12. The footgun sentence removed.
mutate "the ownership warning silenced" \
  'isYours ? nil : String(localized: "Renewing pays for this name and does not transfer it — it stays with its current owner.")' \
  'isYours ? nil : nil'

echo
echo "✓ ens-renew-selftest passed"
