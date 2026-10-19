#!/bin/zsh
# Your account (prd §1421, §1422, §1424) — the address, the send's bytes and
# the Move tab's gate.
#
# The account's address is computed with no network (`YourAccount.address`),
# so a wrong byte anywhere in the initializer or the pinned creation code
# would hand out an address nobody controls, silently. This pins it to the
# address SafeProxyFactory 1.4.1's own simulated create returned for the same
# key on Base and on Ethereum (2026-10-19), and pins the creation code to the
# bytes the factory serves.
#
# The send (`YourAccountOp`) is pinned three ways for one batch — ETH, USDC
# and the key change, creating the account: its callData to the bytes
# `tools/safe-account-spike`'s encoder writes (whose sends landed on Base
# Sepolia); its `getOperationHash` call to the bytes Safe's module on Base
# answered a29a… for (2026-10-19); and the hash the phone signs, computed from
# the op's fields by EIP-712 (`safeOpHash`), to that same answer, so a field
# moved inside the packed tuple fails even when both encoders move together.
# The send's id (`userOpHash`) is pinned to EntryPoint v0.7's own answer. It also holds the Move tab to DEBUG until the
# account can recover, and Base Sepolia to DEBUG always.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
MOVE="Casberi/Casberi/Screens/MoveScreen.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
for f in "$ACCOUNT" "$OP" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$MOVE" "$TABS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/your-account-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The key: P-256 from sha256("casberi your-account selftest"); its address,
# as Base's and Ethereum's factory answered for the same initializer.
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
let x = SafeABI.hexBytes("401388e23199fca944d7348204397880c16a2755e94b1ad9f8e261a3baed3675")!
let y = SafeABI.hexBytes("77003361c4e50ee89f7df0c66b9fe9a69569d96eb353bac1e978f2b3e73b041f")!
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("✗ " + what); bad += 1 } }
let want = "0x09930469ea9d645Bb4141d94af5f2d02A22D29Ce"
check(YourAccount.address(x: x, y: y) == want, "the address is not the factory's (\(YourAccount.address(x: x, y: y) ?? "nil") ≠ \(want))")
check(YourAccount.address(x: x, y: y, salt: 1) != want, "a different salt gave the same address")
check(YourAccount.proxyCreationCode.count == 486, "the creation code is not the factory's 486 bytes")
check(Keccak256.hexString(Keccak256.hash(YourAccount.proxyCreationCode)) == "1856e0ee08399d74e0ea0b03adca210aeade6f748969ac023cdcb4dd62dcaf5f",
      "the creation code changed")
var flipped = y; flipped[31] ^= 1
check(YourAccount.address(x: x, y: flipped) != want, "another key gave the same address")
check(YourAccount.address(x: Array(x.prefix(31)), y: y) == nil, "a short key gave an address")

// The send: one batch, ETH and USDC on Base, the key moved, the account created.
let to = "0x4CC2193e5FA29b10ee4DEBC982e09125c79a78D9"
let eth = YourAccountOp.Payment(network: YourAccountOp.base, token: YourAccountOp.eth, amount: "1000000000000000", to: to, toName: nil)
let usdc = YourAccountOp.Payment(network: YourAccountOp.base, token: YourAccountOp.usdc(on: YourAccountOp.base), amount: "2500000", to: to, toName: nil)
let cd = YourAccountOp.callData([eth, usdc], rotateTo: (x, y))!
var op = YourAccountOp.Op(sender: want, nonce: 0, factory: YourAccount.proxyFactory,
                          factoryData: YourAccountOp.factoryData(x: x, y: y), callData: cd)
op.verificationGasLimit = 500000; op.callGasLimit = 100000; op.preVerificationGas = 60000
op.maxFeePerGas = 2000000; op.maxPriorityFeePerGas = 1000000
op.signature = YourAccountOp.dummySignature
func k(_ b: [UInt8]) -> [UInt8] { Keccak256.hash(b) }
check(Keccak256.hexString(k(cd)) == "7aac3ccb05746baf50fa7d3c8172de9e1ef69890c687c753aeb11b6abfce2a7b",
      "the batch's callData is not the spike's (its sends landed on chain)")
check(Keccak256.hexString(k(YourAccountOp.operationHashCall(op))) == "f1e72c2d1e10d082292951bbce2e3096116a40e3c61fe8f84457ccadc0ca355e",
      "the getOperationHash call changed: Base's module answered a29a… for the pinned bytes")
check(Keccak256.hexString(YourAccountOp.safeOpHash(op, chainId: 8453)) == "a29a4b3b0fd7f559963a728a079a9ee2d0e85489f715ba8e6102bbe88745b53e",
      "the SafeOp hash this phone signs is not what Safe's module on Base answered for the same op")
check(Keccak256.hexString(YourAccountOp.safeOpHash(op, chainId: 84532)) == "91e26c8a6272e312f8079580f324de34be506ea7850d396debbd8f95f1c781e1",
      "the SafeOp hash on Base Sepolia is not the module's")
check(Keccak256.hexString(YourAccountOp.userOpHash(op, chainId: 8453)) == "d9a4f87e3a300872e4f599fee93366c0b1a0dbb144c25dd32bb3622efcc65e17",
      "the userOp id is not EntryPoint v0.7's getUserOpHash on Base — a send could not be followed")
var huge = op; huge.maxFeePerGas = UInt64.max
check(huge.maxCost == nil && op.maxCost == 1320000000000, "maxCost overflows into a trap, or is wrong")
check(YourAccountOp.spoken("500000000000", decimals: 18) == "0.0000005", "a real amount must never be spoken as 0")
check(YourAccountOp.callData([eth], rotateTo: nil) == YourAccountOp.execute(YourAccountOp.call(for: eth)!),
      "a lone payment with no key change is not a plain executeUserOp")
let stray = YourAccountOp.Payment(network: YourAccountOp.base, token: YourAccountOp.eth, amount: "1", to: "0xnope", toName: nil)
check(YourAccountOp.callData([eth, stray], rotateTo: nil) == nil, "a batch with a bad address still wrote calldata")

// Amounts: base units in, readable out, rounded down, never invented.
check(YourAccountOp.baseUnits("0.01", decimals: 18) == "10000000000000000", "0.01 ETH")
check(YourAccountOp.baseUnits("1,5", decimals: 6) == "1500000", "a comma is a decimal point")
check(YourAccountOp.baseUnits("0.0000001", decimals: 6) == nil, "more decimals than the token has")
check(YourAccountOp.baseUnits("0", decimals: 6) == nil, "zero is not an amount")
check(YourAccountOp.baseUnits("1e3", decimals: 6) == nil, "only plain digits")
check(YourAccountOp.baseUnits(".5", decimals: 6) == "500000", ".5")
check(YourAccountOp.display("1999999", decimals: 6, places: 2) == "1.99", "display rounds down")
check(YourAccountOp.display("10000000000000000", decimals: 18) == "0.01", "display cuts zeros")
check(YourAccountOp.display("0", decimals: 18) == "0", "display of nothing")
check(YourAccountOp.atMost("999", "1000") && !YourAccountOp.atMost("1001", "1000") && YourAccountOp.atMost("0100", "100"), "atMost")
check(YourAccountOp.sum("999999999999999999999", "1") == "1000000000000000000000", "sum carries past UInt64")
check(YourAccountOp.decimal(hexQuantity: "0xde0b6b3a7640000") == "1000000000000000000", "hex quantity")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$ACCOUNT" "$OP" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccount.swift and YourAccountOp.swift do not compile alone (Foundation and the Safe encoders only)"; exit 1; }
"$TMP/t" || { echo "✗ your account's arithmetic drifted — see above"; exit 1; }

# The gates: the Move tab is DEBUG-only, the bar's cases follow it, and a
# release build never offers a test network.
grep -q '#if DEBUG' "$MOVE" || { echo "✗ MoveTab.enabled is no longer DEBUG-only — release builds would offer an account that cannot recover yet (prd §1422, §1424)"; exit 1; }
grep -q 'MoveTab.enabled ?' "$TABS" || { echo "✗ PlaceTab.allCases no longer reads MoveTab.enabled"; exit 1; }
grep -A3 'static var networks' "$OP" | grep -q '#if DEBUG' || { echo "✗ YourAccountOp.networks offers Base Sepolia outside DEBUG"; exit 1; }

echo "✓ your account: the address is the factory's, the send's bytes are the module's, amounts add up, Move stays DEBUG-only"
