#!/bin/zsh
# Casberi Wei/Gwei name-service self-test — the SHIPPED pure logic behind
# `.wei` and `.gwei` name resolution (prd §597, 2026-09-04):
#
#   Casberi/Casberi/Model/WeiNames.swift
#     — Registry / registry(claiming:)  which service owns a suffix
#     — canonical                       one spelling, one cache entry
#     — computeIdCalldata / resolveCalldata / reverseCalldata
#     — encodeString / addressWord / word
#     — address(from:)                  THE zero-address rule
#     — string(from:)                   a reverse record off the wire
#
# That file is Foundation-only BY DESIGN (`Keccak256` beside it is pure too),
# so BOTH are compiled WHOLE AND UNMODIFIED here — no extraction, no `private `
# stripping, no copy. Every assertion is about the bytes the app runs.
#
# WHY A HARNESS. Nothing on this host can register a name, so there is no way
# to test this against a state we control — and every failure lands as a
# lookup that looks like it worked:
#
#   • AN UNREGISTERED NAME WATCHED AS THE ZERO ADDRESS. Measured: `alice.wei`
#     computes a real token id and resolves to `0x0000…0000`. A reader that
#     trusts the id watches the null address, which on mainnet holds burned
#     funds and an enormous transfer history — so it renders as a busy, healthy
#     wallet that is nobody's. This is the worst outcome available here and
#     `address(from:)` is the one line standing in front of it;
#   • `alice.gwei` claimed by the WEI registry, because it ends in `wei`. Both
#     contracts answer, and the wrong one answers zero — see above;
#   • the two contract addresses transposed, which fails exactly the same way;
#   • a token id parsed as an `Int`. These ids are keccak hashes —
#     `vitalik.wei`'s is a full 256 bits — so an `Int` round-trip overflows and
#     the name reads as one nobody has taken;
#   • a reverse record believed without the forward check, which lets any
#     address present as `vitalik.wei` in this app's own chrome (§83).
#
# THE FIXTURES ARE MEASURED, NOT INVENTED. Every calldata string and every
# return below was taken from the live contracts on 2026-09-04 and the
# calldata was fired at them (the Swift file's own bytes, and the chain
# answered) — see prd §597. Re-measure before changing one.
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches Ethereum, so it says
# nothing about whether either registry still answers or in what shape — that
# is `-weiNameProbe`'s job and `live-integrations.sh`'s nightly row. And it
# cannot prove the forward-verification RUNS; that is a drift guard below.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

NAMES="Casberi/Casberi/Model/WeiNames.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
SOURCE="Casberi/Casberi/Model/WeiNamesSource.swift"
ROUTER="Casberi/Casberi/Model/NameResolve.swift"
STORE="Casberi/Casberi/Model/AddressNames.swift"
APPROVALS="Casberi/Casberi/Model/WalletApprovals.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
VIEWS="Casberi/Casberi/Screens/AddressBookViews.swift"
for f in "$NAMES" "$KECCAK" "$SOURCE" "$ROUTER" "$STORE" "$APPROVALS" "$INGEST" "$VIEWS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/wei-names-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

# A COMMENT-STRIPPED copy for every negative guard. These files document their
# own rules by naming what they must not do — `WeiNames`' header spells out the
# zero-address failure, `AddressNames`' spells out the §169 rule against
# writing a resolved name into the book — so a guard grepping raw source fires
# on the prose explaining it (the Obsidian/Cursor lesson).
strip() {
  python3 - "$1" <<'PY'
import re, sys
for line in open(sys.argv[1]).read().split("\n"):
    if line.strip().startswith("//"):
        continue
    print(re.sub(r'\s//(?!/).*$', '', line))
PY
}
strip "$SOURCE" > "$TMP/source.stripped"
strip "$ROUTER" > "$TMP/router.stripped"
strip "$STORE"  > "$TMP/store.stripped"
strip "$APPROVALS" > "$TMP/approvals.stripped"
strip "$INGEST" > "$TMP/ingest.stripped"
strip "$VIEWS"  > "$TMP/views.stripped"

# --- the compiled assertions -------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func eq(_ a: String?, _ b: String?, _ what: String) {
    if a != b { print("  ✗ \(what) — got \(a ?? "nil"), want \(b ?? "nil")"); failures += 1 }
}

// MEASURED on-chain, 2026-09-04.
let vitalikWeiCalldata = "0xfb0219390000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000b766974616c696b2e776569000000000000000000000000000000000000000000"
let vitalikID = "4c2c7a515beeb81799099653a046698c54e575ec43be9ec53ca9d5f6cf13d263"
let resolveCalldata = "0x4f896d4f" + vitalikID
let reverseCalldata = "0x9af8b7aa0000000000000000000000001c0aa8ccd568d90d61659f060d1bfb1e6f855a20"
let vitalikReturn = "0x000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045"
let zeroReturn = "0x" + String(repeating: "0", count: 64)
// `reverseResolve(0x1c0a…5a20)` on WNS, byte for byte off the wire.
let rossReturn = "0x0000000000000000000000000000000000000000000000000000000000000020"
    + "0000000000000000000000000000000000000000000000000000000000000008"
    + "726f73732e776569000000000000000000000000000000000000000000000000"

// --- which registry owns a name ---------------------------------------------
eq(WeiNames.registry(claiming: "alice.wei")?.rawValue, "wns", "a .wei name is WNS")
eq(WeiNames.registry(claiming: "alice.gwei")?.rawValue, "gns", "a .gwei name is GNS")
// THE BOUNDARY CASE. "alice.gwei" ends in "wei"; only the dot separates them,
// and matching without it sends every GNS name to the wrong contract.
check(WeiNames.registry(claiming: "alice.gwei") != .wns, "a .gwei name is NOT claimed by WNS")
eq(WeiNames.registry(claiming: "vitalik.eth")?.rawValue, nil, "an ENS name is claimed by neither")
eq(WeiNames.registry(claiming: "toly.sol")?.rawValue, nil, "a .sol name is claimed by neither")
eq(WeiNames.registry(claiming: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")?.rawValue, nil,
   "a hex address is not a name")
// A bare suffix is not a name: it computes a real id, resolves to nothing, and
// would present as a name we merely failed to find.
eq(WeiNames.registry(claiming: ".wei")?.rawValue, nil, "a bare .wei is not a name")
eq(WeiNames.registry(claiming: ".gwei")?.rawValue, nil, "a bare .gwei is not a name")
eq(WeiNames.registry(claiming: "  Alice.WEI  ")?.rawValue, "wns", "trimmed and case-folded")
check(WeiNames.looksLikeName("a.wei"), "a one-letter label is still a name")
check(!WeiNames.looksLikeName("wei"), "the bare word is not a name")
check(!WeiNames.looksLikeName(""), "empty is not a name")

// --- the two contracts, kept apart -------------------------------------------
check(WeiNames.Registry.wns.contract != WeiNames.Registry.gns.contract,
      "the two registries have different contracts")
eq(WeiNames.Registry.wns.contract, "0x0000000000696760E15f265e828DB644A0c242EB", "WNS contract")
eq(WeiNames.Registry.gns.contract, "0x9D51D507BC7264d4fE8Ad1cf7Fe191933A0a81d6", "GNS contract")
eq(WeiNames.Registry.wns.suffix, ".wei", "WNS suffix")
eq(WeiNames.Registry.gns.suffix, ".gwei", "GNS suffix")
// The precondition that lets `registry(claiming:)` match in any order. A
// registry added later with a subname-shaped suffix (`.x.wei` beside `.wei`)
// breaks it, and this is where that is found out.
check(WeiNames.suffixesAreUnambiguous, "no registry's suffix ends with another's")
// …and the check can actually SAY no. Without this pair it returns true for
// the shipped registries whether or not it works at all.
check(!WeiNames.suffixesAreUnambiguous([".wei", ".x.wei"]),
      "a subname-shaped suffix is caught as ambiguous")
check(WeiNames.suffixesAreUnambiguous([".wei", ".gwei"]),
      "the shipped pair is unambiguous — the dot is what separates them")

// --- calldata, against the bytes the chain accepted --------------------------
eq(WeiNames.computeIdCalldata("vitalik.wei"), vitalikWeiCalldata, "computeId calldata")
eq(WeiNames.computeIdCalldata("VITALIK.WEI"), vitalikWeiCalldata, "computeId canonicalises first")
eq(WeiNames.resolveCalldata(idWord: vitalikID), resolveCalldata, "resolve calldata")
eq(WeiNames.resolveCalldata(idWord: "0x" + vitalikID), resolveCalldata, "resolve takes a 0x id")
eq(WeiNames.resolveCalldata(idWord: "abc"), nil, "a short id is refused, never padded")
eq(WeiNames.reverseCalldata(address: "0x1c0aa8ccd568d90d61659f060d1bfb1e6f855a20"),
   reverseCalldata, "reverseResolve calldata")
eq(WeiNames.reverseCalldata(address: "0x1C0AA8CCD568D90D61659F060D1BFB1E6F855A20"),
   reverseCalldata, "an EIP-55 address is lowercased — the case is a checksum, not identity")
eq(WeiNames.reverseCalldata(address: "toly.sol"), nil, "a non-hex address is refused")
eq(WeiNames.reverseCalldata(address: "0x1c0a"), nil, "a short address is refused")
check(WeiNames.computeIdCalldata("a.wei").hasPrefix("0x"), "calldata carries its 0x")
check(!WeiNames.selector("computeId(string)").hasPrefix("0x"), "a selector is a bare fragment")

// --- decoding ----------------------------------------------------------------
eq(WeiNames.address(from: vitalikReturn), "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
   "a resolved address")
// THE RULE. Measured: `alice.wei` has a real token id and resolves to zero.
eq(WeiNames.address(from: zeroReturn), nil, "the ZERO ADDRESS is nobody, never an address")
eq(WeiNames.address(from: "0x"), nil, "an empty return is not an address")
eq(WeiNames.address(from: "0xnothex"), nil, "a non-hex return is not an address")
// A word whose top 12 bytes are not zero is not an address-shaped answer.
eq(WeiNames.address(from: "0x" + String(repeating: "f", count: 64)), nil,
   "a full-width word is refused rather than truncated to its low 20 bytes")
eq(WeiNames.tokenIdWord(from: "0x" + vitalikID), vitalikID, "the token id comes back whole")
check(WeiNames.tokenIdWord(from: "0x" + vitalikID)?.count == 64, "a token id is a full word")
eq(WeiNames.string(from: rossReturn), "ross.wei", "a reverse record off the wire")
// An address that set no primary name answers with an empty string.
let emptyString = "0x0000000000000000000000000000000000000000000000000000000000000020"
    + String(repeating: "0", count: 64)
eq(WeiNames.string(from: emptyString), nil, "an empty reverse record is nil, never \"\"")
eq(WeiNames.string(from: "0x"), nil, "a truncated string return is nil")

// --- canonical ----------------------------------------------------------------
eq(WeiNames.canonical("  Alice.WEI "), "alice.wei", "canonical trims and lowercases")

if failures == 0 { print("  assertions passed") } else { exit(1) }
SWIFT

echo "wei-names-selftest: compiling the shipped source…"
swiftc -Onone -o "$TMP/run" "$NAMES" "$KECCAK" "$TMP/main.swift" 2>&1 | head -20
"$TMP/run" || { echo "✗ assertions failed"; exit 1; }

# --- drift guards -------------------------------------------------------------
# Facts the compiled functions cannot prove: a perfect encoder is worthless if
# the wrong thing calls it, or if what it returns is believed unverified.

# THE FORWARD CHECK. A reverse record is a claim an address makes about itself
# and this app prints it beside money — so it is believed only once resolving
# it comes back to the same address (§83; ENSIP-3's rule, for ENSIP-3's reason).
grep -q 'let back = await resolve(name, in: registry)' "$TMP/source.stripped" \
  || { echo "✗ primaryName no longer forward-resolves the name it was given —"; \
       echo "  an unverified reverse record lets any address present as vitalik.wei"; exit 1; }
grep -q 'back.caseInsensitiveCompare(address) == .orderedSame' "$TMP/source.stripped" \
  || { echo "✗ primaryName no longer COMPARES the forward answer to the address"; exit 1; }
# …and the answer must belong to the registry that gave it.
grep -q 'WeiNames.registry(claiming: name) == registry' "$TMP/source.stripped" \
  || { echo "✗ primaryName no longer checks the record's suffix against its own"; \
       echo "  registry — a WNS record reading foo.gwei would be resolved on WNS"; exit 1; }

# THE ZERO-ADDRESS RULE, at the call site. The encoder refuses it, but only if
# the read actually goes through the encoder.
grep -q 'return WeiNames.address(from: addressReturn)' "$TMP/source.stripped" \
  || { echo "✗ resolve no longer reads its answer through WeiNames.address —"; \
       echo "  an unregistered name would resolve to the zero address"; exit 1; }

# THE DEMO REACHES NOTHING, gated at each function that reads.
for fn in resolve primaryName heldCount; do
  python3 - "$TMP/source.stripped" "$fn" <<'PY' || exit 1
import re, sys
src, fn = open(sys.argv[1]).read(), sys.argv[2]
m = re.search(r'\n    static func %s\(.*?\n    \}\n' % fn, src, re.S)
if not m:
    print(f"✗ WeiNamesSource.{fn} is gone — the guard cannot run"); sys.exit(1)
if "DemoMode.isActive" not in m.group(0):
    print(f"✗ WeiNamesSource.{fn} no longer gates on DemoMode — the demo would")
    print("  reach the chain for its own fabricated addresses")
    sys.exit(1)
PY
done

# THE ORDER, which is the whole of NameResolve's correctness: the specific
# suffixes must be asked BEFORE ENS, whose own test takes any dotted string.
python3 - "$TMP/router.stripped" <<'PY' || exit 1
import sys
src = open(sys.argv[1]).read()
try:
    sns = src.index("SNS.looksLikeName")
    wei = src.index("WeiNames.registry(claiming:")
    ens = src.index("ENS.looksLikeName")
except ValueError:
    print("✗ NameResolve.family no longer asks all three families"); sys.exit(1)
if not (sns < wei < ens):
    print("✗ NameResolve.family's order changed — ENS's test is a catch-all, so")
    print("  anything asked after it is never asked at all")
    sys.exit(1)
PY

# THE SIX CALL SITES. The point of the router is that the order is spelled
# ONCE; a resurrected ternary is the drift this replaced.
for f in "$TMP/ingest.stripped" "$TMP/approvals.stripped"; do
  if grep -qE 'SNS\.looksLikeName\([^)]*\)\s*(\?|\|\|)' "$f"; then
    echo "✗ $(basename $f) spells the family order by hand again (prd §597) —"
    echo "  that is six copies of one rule, which drift rather than break"
    exit 1
  fi
done
grep -q 'NameResolve.family(of: address) == .ens' "$TMP/approvals.stripped" \
  || { echo "✗ WalletApprovals.canServe no longer asks for ENS exactly — the"; \
       echo "  excluding form fails OPEN and hands .wei names to Revoke.cash"; exit 1; }
grep -q 'await NameResolve.resolve(a)' "$TMP/ingest.stripped" \
  || { echo "✗ WalletIngest.resolvedAddresses no longer routes through NameResolve"; exit 1; }

# §169: A NAME SOMEBODY TYPED IS THEIR DATA. A resolved name may stand in for
# an AUTO name on screen and may never be written into the book.
if grep -q 'setName' "$TMP/store.stripped"; then
  echo "✗ AddressNames now writes to the address book — a name the ADDRESS"
  echo "  claims must never overwrite the name the PERSON chose (§169)"
  exit 1
fi
grep -q 'guard WalletStore.isAutoName(entry.name, for: entry.address) else { return nil }' \
  "$TMP/views.stripped" \
  || { echo "✗ the book row no longer restricts a standing-in name to an AUTO"; \
       echo "  name — a name somebody typed would be silently replaced"; exit 1; }

# The address must stay the FIRST reach line: `actionTiles` copies it.
python3 - "$TMP/views.stripped" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
if "return [address] + primaryNames.map" not in src:
    print("✗ the card's reach lines no longer lead with the address — the Copy")
    print("  tile takes reachLines.first, so it would copy a name instead")
    sys.exit(1)
PY

echo "wei-names-selftest: mutations…"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$NAMES" "$WORK/WeiNames.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/WeiNames.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/WeiNames.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/WeiNames.swift" "$KECCAK" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE ONE THAT MATTERS. Without the zero-address refusal an unregistered
#    name resolves to 0x0000…0000 — an address with a huge transfer history
#    that renders as a busy wallet and belongs to nobody.
mutate "the zero address accepted as a real address" \
  'guard body.contains(where: { $0 != "0" }) else { return nil }' \
  'guard true else { return nil }'

# 2. The suffix matched without its dot — every `.gwei` name claimed by WNS,
#    resolved against the wrong contract, answering nobody.
mutate "the suffix matched without its dot" \
  'value.hasSuffix($0.suffix) && value.count > $0.suffix.count' \
  'value.hasSuffix(String($0.suffix.dropFirst())) && value.count > $0.suffix.count'

# 3. A bare suffix accepted as a name — a lookup that can only ever fail,
#    offered as though it might work.
mutate "a bare suffix accepted as a name" \
  'value.hasSuffix($0.suffix) && value.count > $0.suffix.count' \
  'value.hasSuffix($0.suffix)'

# 4. The two contracts transposed. Both answer, and each answers zero for the
#    other's names — the §83 failure wearing a working screen.
mutate "the two registry contracts transposed" \
  'case .wns: return "0x0000000000696760E15f265e828DB644A0c242EB"' \
  'case .wns: return "0x9D51D507BC7264d4fE8Ad1cf7Fe191933A0a81d6"'

# 5. The ambiguity precondition made vacuous. `registry(claiming:)` matches in
#    declaration order, which is only safe while no suffix ends with another;
#    a check that cannot fail would let a subname-shaped registry land with the
#    match silently resolving to whichever case came first.
mutate "the suffix-ambiguity check made vacuous" \
  'if a.hasSuffix(b) { return false }' \
  'if false { return false }'

# 6. The name not canonicalised before it is hashed. The contracts fold case
#    themselves, so this is not wrong on-chain — it splits the CACHE, and two
#    spellings of one name become two lookups forever.
mutate "the name no longer canonicalised into the calldata" \
  'selector("computeId(string)") + encodeString(canonical(name))' \
  'selector("computeId(string)") + encodeString(name)'

# 7. An empty reverse record returned as "" rather than nil — an address that
#    set no name would present as having one, blank.
mutate "an empty reverse record returned as a string" \
  '!text.isEmpty else { return nil }' \
  'true else { return nil }'

# 8. A token id silently padded instead of refused — a short or malformed id
#    would address a DIFFERENT token, which resolves to a real stranger.
mutate "a malformed token id padded rather than refused" \
  'guard s.count == 64, s.allSatisfy(\.isHexDigit) else { return nil }' \
  'guard s.count <= 64, s.allSatisfy(\.isHexDigit) else { return nil }'

# 9. The address word not lowercased. EIP-55 case is a checksum, and a
#    mixed-case word addresses nothing.
mutate "the address word no longer lowercased" \
  'let value = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()' \
  'let value = address.trimmingCharacters(in: .whitespacesAndNewlines)'

# 10. The top-12-bytes check dropped, so any 32-byte word is read as an
#     address by truncation — a token id would resolve to "an address".
mutate "a full-width word truncated into an address" \
  'word.hasPrefix(String(repeating: "0", count: 24))' \
  'word.count == 64'

echo
echo "✓ wei-names-selftest passed"
