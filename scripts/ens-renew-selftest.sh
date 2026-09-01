#!/bin/zsh
# ENS renew self-test — the SHIPPED encoding behind the renew card (prd §540):
#
#   Casberi/Casberi/Model/ENSRenew.swift
#     — calldata / priceCalldata  (the ABI bytes a wallet would sign)
#     — encodedString             (dynamic-string encoding, the new capability)
#     — payable / weiHex          (what goes in `value`)
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
# were produced by a Python encoder (pysha3 + hand-rolled ABI) on 2026-08-31 and
# cross-checked against the live contract: the selectors match the deployed
# bytecode, and `rentPrice` calls built the same way returned ENS's published
# $5 / $160 / $640 per-year tiers from two independent controllers. A test that
# only agrees with the thing it tests proves nothing.
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

# Fail CLOSED on a short price reply. "0x" parses to zero, and a price of zero
# shown to somebody about to sign is the worst number this card could print.
grep -q 'hex.count >= 2 + 64 \* 2' "$TMP/prepare.stripped" \
  || { echo "✗ ENSRenewPrepare no longer requires a full two-word price reply —"; \
       echo "  a reverted read would parse as a FREE renewal"; exit 1; }

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
// Measured 2026-08-31: the live controller's bytecode contains 18026ad1 and
// 83e7f6ff. It does NOT contain acf1a841, the two-argument renew the retired
// controller took.
eq("renew(string,uint256,bytes32)", "0x" + ENSRenew.renewSelector, "0x18026ad1")
eq("rentPrice(string,uint256)", "0x" + ENSRenew.rentPriceSelector, "0x83e7f6ff")

print("the contract — measured on mainnet, not recalled")
// `BaseRegistrar.controllers()` answers 1 for this address and 0 for the
// long-standing one everybody's notes name. Calldata built against the retired
// one encodes perfectly and reverts on submission.
eq("controller", ENSRenew.controller, "0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547")
check("mainnet, and there is no chain picker", ENSRenew.chainID == 1)
check("ENS's 365-day year, not a calendar year", ENSRenew.year == 31_536_000)

print("calldata — vectors from an independent Python encoder")
eq("vitalik / 1 year", ENSRenew.calldata(label: "vitalik", term: .oneYear),
 "0x18026ad100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e1338000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007766974616c696b00000000000000000000000000000000000000000000000000")
eq("abc / 2 years", ENSRenew.calldata(label: "abc", term: .twoYears),
 "0x18026ad100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000003c26700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036162630000000000000000000000000000000000000000000000000000000000")
// A 32-byte label is EXACTLY one word. The naive `32 - count % 32` appends a
// whole dead word here, which no ordinary name would ever reveal.
eq("32-byte label adds no padding word",
   ENSRenew.calldata(label: String(repeating: "a", count: 32), term: .oneYear),
 "0x18026ad100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e13380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000206161616161616161616161616161616161616161616161616161616161616161")
eq("33-byte label spills to a second word",
   ENSRenew.calldata(label: String(repeating: "a", count: 33), term: .oneYear),
 "0x18026ad100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e133800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002161616161616161616161616161616161616161616161616161616161616161616100000000000000000000000000000000000000000000000000000000000000")
// "café" is FOUR characters and FIVE UTF-8 bytes. Encoding 4 yields a
// well-formed, signable transaction that renews a truncated label.
eq("multi-byte label counts BYTES, not characters",
   ENSRenew.calldata(label: "café", term: .oneYear),
 "0x18026ad100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000001e1338000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005636166c3a9000000000000000000000000000000000000000000000000000000")

print("the two arities differ, and sharing an offset would break one")
check("renew's head is three words (offset 0x60)",
      ENSRenew.calldata(label: "abc", term: .oneYear)!.dropFirst(10).prefix(64)
        == String(repeating: "0", count: 62) + "60")
check("rentPrice's head is two words (offset 0x40)",
      ENSRenew.priceCalldata(label: "abc", term: .oneYear)!.dropFirst(10).prefix(64)
        == String(repeating: "0", count: 62) + "40")

print("refusals — the label, never the name")
check("a full name is refused", ENSRenew.calldata(label: "vitalik.eth", term: .oneYear) == nil)
check("an empty label is refused", ENSRenew.calldata(label: "", term: .oneYear) == nil)
check("whitespace is refused", ENSRenew.calldata(label: "a b", term: .oneYear) == nil)
check("priceCalldata refuses the same", ENSRenew.priceCalldata(label: "a.b", term: .oneYear) == nil)

print("value — the buffer, and which way it rounds")
let base = 2_022_000_000_000_000.0        // the real 5+ character tier, measured
check("a buffer is added", ENSRenew.payable(base: base) > base)
// SMALL on purpose: the controller refunds the excess with `.transfer()`,
// which forwards 2,300 gas — not always enough for a smart-account wallet, and
// a failed refund reverts the whole renewal.
check("the buffer stays under 10%", ENSRenew.payable(base: base) < base * 1.10)
// A FRACTIONAL wei amount is the only input that can tell the two roundings
// apart. The obvious test — feeding `payable(base:)` a real tier price — is
// NOT discriminating: 2022000000000000 x 1.05 is exactly representable, so
// `.up` and `.down` agree and the mutation survives green. Caught by the
// mutation pass on this harness's first run; the standing rule, fourth
// instance in this repo: a fixture only tests the rule it names if it FAILS
// that rule and passes every other one.
eq("a fraction of a wei rounds UP", ENSRenew.weiHex(1.5), "0x2")
eq("an exact amount is unchanged", ENSRenew.weiHex(2), "0x2")
check("value is never below what was asked for",
      Double(UInt64(ENSRenew.weiHex(ENSRenew.payable(base: base)).dropFirst(2), radix: 16)!)
        >= ENSRenew.payable(base: base))
eq("zero is refused rather than encoded", ENSRenew.weiHex(0), "0x0")
eq("a non-finite amount is refused", ENSRenew.weiHex(Double.nan), "0x0")

print("the transaction object")
let json = ENSRenew.transactionJSON(from: "0xabc", label: "vitalik", term: .oneYear, base: base)!
check("it carries a REAL value, never 0x0", !json.contains("\"value\": \"0x0\""))
check("it targets the controller", json.contains(ENSRenew.controller))
check("it names chain 1", json.contains("\"chainId\": 1"))
check("no transaction without a sender",
      ENSRenew.transactionJSON(from: "0x1", label: "vitalik", term: .oneYear, base: 0) == nil)

print("the sentence permissionless renewal owes")
check("a name that isn't yours gets the warning",
      ENSRenew.ownershipNote(isYours: false)?.lowercased().contains("does not transfer") == true)
check("your own name doesn't", ENSRenew.ownershipNote(isYours: true) == nil)

print("words")
check("never a fiat figure — no ETH price is trusted on this path",
      !ENSRenew.ethLine(base).contains("$"))
check("the cheap tier doesn't round to nothing", ENSRenew.ethLine(base) != "0.0000 ETH")

print("")
if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("All assertions passed.")
SWIFT

swiftc -O -o "$TMP/run" "$RENEW" "$KECCAK" "$TMP/main.swift" 2>&1 | head -30
"$TMP/run"

# --- mutations ---------------------------------------------------------------
# Each is a silent wrong answer that renders as a perfectly ordinary card. A
# check that cannot fail proves nothing.
echo
echo "mutations (each must be caught)"
mutate() {
  local label="$1" from="$2" to="$3"
  mkdir -p "$TMP/m"
  python3 - "$RENEW" "$TMP/m/ENSRenew.swift" "$from" "$to" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if a not in s:
    print(f"MUTATION TARGET NOT FOUND: {a[:70]}"); sys.exit(2)
open(dst, "w").write(s.replace(a, b, 1))
PY
  if swiftc -O -o "$TMP/m/run" "$TMP/m/ENSRenew.swift" "$KECCAK" "$TMP/main.swift" 2>/dev/null; then
    if "$TMP/m/run" >/dev/null 2>&1; then
      echo "  ✗ NOT CAUGHT: $label"; exit 1
    fi
  fi
  echo "  ✓ $label"
}

# 1. The retired controller. Encodes perfectly, reverts on submission — after
#    somebody has approved spending money.
mutate "the retired controller address" \
  '"0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547"' \
  '"0x253553366Da8546fC250F225fe3d25d0C782303b"'

# 2. The two-argument renew the retired controller took. The live one does not
#    have this selector in its bytecode at all.
mutate "the two-argument renew signature" \
  '"renew(string,uint256,bytes32)"' \
  '"renew(string,uint256)"'

# 3. renew's offset borrowed from rentPrice's arity — three head words read as
#    two, so the string is decoded from the wrong place.
mutate "renew's string offset set to rentPrice's" \
  'return "0x" + renewSelector
            + word(0x60)' \
  'return "0x" + renewSelector
            + word(0x40)'

# 4. Characters instead of bytes — a truncated label, signed and paid for.
mutate "string length counted in characters" \
  'var hex = word(bytes.count)' \
  'var hex = word(s.count)'

# 5. The dead padding word on an exactly-32-byte label.
mutate "padding added even at a word boundary" \
  'if remainder != 0 { hex += String(repeating: "00", count: 32 - remainder) }' \
  'hex += String(repeating: "00", count: 32 - remainder)'

# 6. No buffer — the transaction reverts the moment the oracle moves.
mutate "the oracle-drift buffer removed" \
  'base * (1 + bufferPercent / 100)' \
  'base'

# 7. Rounding DOWN lands below price.base and reverts for a fraction of a wei.
mutate "value rounds down" \
  'let rounded = wei.rounded(.up)' \
  'let rounded = wei.rounded(.down)'

# 8. A full name accepted as a label — renews an entry nobody owns.
mutate "a dotted name accepted as a label" \
  'guard !label.isEmpty, !label.contains("."), !label.contains(where: \.isWhitespace)
        else { return nil }
        // Head: offset' \
  'guard !label.isEmpty
        else { return nil }
        // Head: offset'

# 9. The footgun sentence removed.
mutate "the ownership warning silenced" \
  'isYours ? nil : String(localized: "Renewing pays for this name and does not transfer it — it stays with its current owner.")' \
  'isYours ? nil : nil'

echo
echo "✓ ens-renew-selftest passed"
