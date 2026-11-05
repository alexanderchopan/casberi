#!/bin/zsh
# Shield bridge self-test (prd §1700b, §1700d, §1700e) — the words Casberi
# writes to Shield's contracts and the guards around them:
#
#   Casberi/Casberi/Model/Aztec/ShieldWire.swift
#     — depositCalldata   (the portal's depositToAztecPrivate, cleanHands blank)
#     — withdrawCalldata  (the portal's withdraw, finishing an exit on Ethereum)
#     — leafID            (the outbox's key for "already withdrawn")
#     — message(in:)      (the deposit's event: what Aztec will carry)
#
# Expected bytes were encoded by viem (tools/aztec-account) on 2026-11-04;
# Shield's portal is unverified on Etherscan, so its ABI is Shield's own web
# app's. Every failure below moves real money wrong:
#
#   • the two signature tuples swapped — the deposit reverts, or worse, a
#     Clean Hands (government ID) slot filled by the Passport limit;
#   • a withdraw whose path offset is off — the portal reverts, and the money
#     waits on Ethereum while the app says it can be finished;
#   • a leaf id off by the tree's depth — a finished exit offered again forever;
#   • an exit that pays someone other than your own account, an authwit for the
#     bridge instead of its minter proxy (the burn reverts after proving), or a
#     content hash under another selector (the exit can never be finished);
#   • any request to Proof of Clean Hands (ID) — Passport only, §1700e item 1.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/Aztec/ShieldWire.swift"
APP="Casberi/Casberi/Model/Aztec/ShieldBridge.swift"
ENGINE="tools/aztec-engine/src/main.js"
for f in "$WIRE" "$APP" "$ENGINE"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

# ── The app half, read ──────────────────────────────────────────────────
grep -q 'shield.human.tech' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ Shield's host is not declared in NetworkReach"; exit 1; }
if grep -n 'attestation/poch\|cleanHands"\]\s*=' "$APP" "$WIRE" | grep -v '^\s*[0-9]*:\s*///' | grep -q .; then
  echo "✗ Shield's Proof of Clean Hands (government ID) is asked for: Passport only (prd §1700e)"; exit 1
fi
grep -q 'ShieldBridge.exit\|static func exit' "$APP" \
  && grep -q '"shieldExit", \[asset.symbol, units, account, text\]' "$APP" \
  || { echo "✗ an exit no longer pays your own account (the Safe that signed in)"; exit 1; }
grep -q "caller: AztecAddress.fromStringUnsafe(asset.proxy), call: burn" "$ENGINE" \
  || { echo "✗ the exit's authwit no longer names the bridge's minter proxy: the burn reverts after proving"; exit 1; }
grep -q "Buffer.from('69328dec', 'hex')" "$ENGINE" \
  || { echo "✗ the exit's content is no longer withdraw(address,uint256,address)'s: it could never be finished"; exit 1; }
grep -q "proxyClass: '0x18fa95a66c31125278bf4d07166e30fff3ad7e12b232710bf7e376f36f2d4b8a'" "$ENGINE" \
  || { echo "✗ the minter proxy's class is no longer pinned"; exit 1; }

# ── The wire, run ──────────────────────────────────────────────────────
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'EOF'
import Foundation
var failed = 0
func check(_ ok: Bool, _ what: String) { if !ok { failed += 1; print("✗ \(what)") } }

let sig = "0x" + String(repeating: "11", count: 32) + String(repeating: "22", count: 32) + "1b"
let limit = ShieldBridge.Limit(maxAmount: "1000000000", nonce: "7", deadline: "1767225600", signature: sig)
let deposit = ShieldBridge.depositCalldata(units: "25000000",
    secretHash: "0x0abc000000000000000000000000000000000000000000000000000000000def", limit: limit)
check(deposit == "0x62470a1000000000000000000000000000000000000000000000000000000000017d78400abc000000000000000000000000000000000000000000000000000000000def0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000006955b90000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000041111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222221b00000000000000000000000000000000000000000000000000000000000000",
      "depositToAztecPrivate is not viem's bytes")

let withdraw = ShieldBridge.withdrawCalldata(recipient: "0xef4d9e1f4e9e2dd9e747b53f4be3d04bfa935f2d", units: "5000000",
    epoch: "812", checkpoints: "3", leaf: "5",
    path: ["0x" + String(repeating: "aa", count: 32), "0x" + String(repeating: "bb", count: 32), "0x00" + String(repeating: "cc", count: 31)])
check(withdraw == "0xaab5a3f1000000000000000000000000ef4d9e1f4e9e2dd9e747b53f4be3d04bfa935f2d00000000000000000000000000000000000000000000000000000000004c4b400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000032c0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000003aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "the portal's withdraw is not viem's bytes")
check(ShieldBridge.withdrawCalldata(recipient: "0xef4d", units: "1", epoch: "1", checkpoints: "1", leaf: "0", path: ["0xzz"]) == nil,
      "a sibling that is not hex was written anyway")

check(ShieldBridge.leafID(leaf: "5", depth: 3) == "13", "leaf id is not 2^depth + leaf")
check(ShieldBridge.leafID(leaf: "0", depth: 0) == "1", "leaf id of a one-message epoch")
check(ShieldBridge.word(decimal: "115792089237316195423570985008687907853269984665640564039457584007913129639935") == String(repeating: "f", count: 64),
      "2^256 - 1 is not one full word")
check(ShieldBridge.word(decimal: "115792089237316195423570985008687907853269984665640564039457584007913129639936") == nil,
      "2^256 overflowed into a word")

// The deposit's event, as a receipt carries it (amount after fee 24,875,000; leaf 702).
let words = ["00000000000000000000000000000000000000000000000000000000017b8ff8",
             "000000000000000000000000000000000000000000000000000000000001e848",
             "0abc000000000000000000000000000000000000000000000000000000000def",
             "00967aa4307fc16f08f3dc9a0b2974ebe4ce4905d7b4dc7fff3a97283e89719a",
             "00000000000000000000000000000000000000000000000000000000000002be"]
let portal = ShieldBridge.assets[0].portal
let receipt: [String: Any] = ["logs": [
    ["address": "0x0000000000000000000000000000000000000001", "topics": [ShieldBridge.depositTopic], "data": "0x" + words.joined()],
    ["address": portal.uppercased().replacingOccurrences(of: "0X", with: "0x"), "topics": [ShieldBridge.depositTopic], "data": "0x" + words.joined()],
]]
let m = ShieldBridge.message(in: receipt, portal: portal)
check(m?.amount == "24875000", "the deposit's amount after fee")
check(m?.key == "0x00967aa4307fc16f08f3dc9a0b2974ebe4ce4905d7b4dc7fff3a97283e89719a", "the deposit's message key")
check(m?.index == "702", "the deposit's leaf index")
check(ShieldBridge.message(in: ["logs": [receipt["logs"].map { ($0 as! [[String: Any]])[0] }!]], portal: portal) == nil,
      "another contract's event was read as Shield's portal")

exit(failed == 0 ? 0 : 1)
EOF
xcrun swiftc -Onone -o "$TMP/run" "$WIRE" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; echo "✗ the wire did not compile"; exit 1; }
"$TMP/run" || exit 1

# ── Mutations: the checks above catch what they claim ───────────────────
mutate() { # label, perl expression
  sed -e '' "$WIRE" > "$TMP/wire.swift"
  perl -0pi -e "$2" "$TMP/wire.swift"
  cmp -s "$WIRE" "$TMP/wire.swift" && { echo "✗ mutation '$1' changed nothing (its anchor drifted)"; exit 1; }
  if xcrun swiftc -Onone -o "$TMP/mut" "$TMP/wire.swift" "$TMP/main.swift" 2>/dev/null && "$TMP/mut" >/dev/null; then
    echo "✗ mutation survived: $1"; exit 1
  fi
}
mutate "tuples swapped" 's/cleanHands \+ passport/passport + cleanHands/'
mutate "path offset off" 's/word\(int: 7 \* 32\)/word(int: 6 * 32)/'
mutate "leaf id without depth" 's/pow\(Decimal\(2\), depth\) \+ l/l/'
mutate "decimal carry dropped" 's/guard carry == 0 else \{ return nil \}/_ = carry/'
mutate "any contract's event" 's/\(log\["address"\] as\? String\)\?\.lowercased\(\) == portal\.lowercased\(\),/true,/'

echo "✓ Shield bridge self-test (deposit + withdraw bytes match viem, leaf ids, the deposit event, Passport only, 5 mutations caught)"
