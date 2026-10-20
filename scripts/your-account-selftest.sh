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
# The send's id (`userOpHash`) is pinned to EntryPoint v0.7's own answer, and
# the recovery key's two operations (prd §1427) to the spike's landed ones,
# and a swap's order id (prd §1430) to the one CoW's API answered for it. It
# also holds Move to every build — no hidden or dormant feature in a release
# (prd §1435, App Review 2.3.1) — and Base Sepolia to DEBUG always.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
COW="Casberi/Casberi/Model/CowOrder.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
MOVE="Casberi/Casberi/Screens/MoveScreen.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
for f in "$ACCOUNT" "$OP" "$SWAP" "$COW" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$MOVE" "$TABS"; do
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

// Recovery (prd §1427): adding the recovery key and recovering onto a new
// key, byte for byte what the spike's encoder wrote for the two operations
// it landed on Base Sepolia (owner added, then the shared signer moved).
let recoverySigner = "0x87Ec95Af16F72bF4282C9E029884361cd79a91D7"
check(Keccak256.hexString(k(YourAccountOp.callData(calls: YourAccountOp.addRecoveryCalls(account: want, x: x, y: y, signer: recoverySigner), rotateTo: nil)!))
      == "60088496eb09e42870575c66360c1b73653df9a819bb5d174dd602f627a21d6e",
      "adding the recovery key is not the spike's operation (deploy its signer, addOwnerWithThreshold(signer, 1))")
check(Keccak256.hexString(k(YourAccountOp.callData(calls: [YourAccountOp.recoverCall(to: (x, y))], rotateTo: nil)!))
      == "678cded4304811761e84978325558234f4c0f857bb42266b1aa265c6894b0512",
      "recovery is not the spike's operation (a delegate call re-configuring the shared signer)")
check(YourAccountOp.dummySignature(owner: recoverySigner) != YourAccountOp.dummySignature,
      "the recovery key's estimate signs as the shared signer")
check(YourAccount.short(want) == "…29Ce", "an address is its last four or the whole of it (prd §495)")

// Swap (prd §1430): a real CoW quote on Base (2026-10-19) built into the
// order HERE gives the id CoW's own API answered when that order was posted
// — 0x32fa…bab2 — so this phone and CoW agree on every byte the person
// pre-signs. The pre-sign call reads back through §1285's parser.
let quoteJSON: [String: Any] = ["id": 417304251, "quote": [
    "sellAmount": "198563874188220", "buyAmount": "476693", "feeAmount": "1436125811780",
    "validTo": 1792457394] as [String: Any]]
let cowAccount = "0xb91a38aA11C903bf5A465326b9c0cf8680F43416"
let swapQuote = YourAccountSwap.quote(from: quoteJSON)!
check(swapQuote.sellAmount == "200000000000000", "the order sells what was asked (the quote's amount plus its fee)")
check(swapQuote.minimumBuy == "474309", "the minimum is 0.5% under the quote, rounded down")
let cowOrder = YourAccountSwap.order(sell: YourAccountOp.eth, buy: YourAccountOp.usdc(on: YourAccountOp.base),
                                     on: YourAccountOp.base, account: cowAccount, quote: swapQuote)!
let cowUID = YourAccountSwap.uid(cowOrder, owner: cowAccount, chainId: 8453)!
check(SafeABI.hex(cowUID) == "0x32fa77466b4b4845779d6546e6d5a61cec74725646d688962d71c16db94ab24cb91a38aa11c903bf5a465326b9c0cf8680f434166ad6bab2",
      "the order's id is not the one CoW's API answered for it")
check(SafeABI.hex(YourAccountSwap.appDataHash) == "0x868db1f7ba62a9708787a6ce366c687ddc6a32e22b6722aebbc0e8bd0c00da59",
      "the app data hash is not CoW's")
let swapCalls = YourAccountSwap.calls(order: cowOrder, uid: cowUID, sellingETH: true, network: YourAccountOp.base)!
check(swapCalls.count == 3 && swapCalls[0].to == YourAccountSwap.weth(chainId: 8453)! && swapCalls[0].value == cowOrder.sellAmount,
      "selling ETH wraps exactly what is sold first")
check(swapCalls[1].data == YourAccount.sel("approve(address,uint256)") + YourAccount.w(YourAccountSwap.vaultRelayer) + cowOrder.sellAmount,
      "the approval is exactly what is sold, to CoW's vault relayer only")
check(CowOrder.preSignature(swapCalls[2].data).map { $0.uid == cowUID && $0.signed } == true && swapCalls[2].to == CowOrder.settlement,
      "the pre-signature is not setPreSignature(uid, true) on the settlement contract")
check(YourAccountSwap.calls(order: cowOrder, uid: cowUID, sellingETH: false, network: YourAccountOp.base)!.count == 2,
      "selling a token wraps nothing")
check(YourAccountSwap.minus(basisPoints: 50, of: "1000") == "995" && YourAccountSwap.minus(basisPoints: 50, of: "1") == "0"
      && YourAccountSwap.minus(basisPoints: 50, of: "123456789012345678901234567890") == "122839505067283950506728395050",
      "slippage arithmetic")
check(!YourAccountSwap.supported(YourAccountOp.baseSepolia), "CoW does not settle on Base Sepolia")

// The outside key (prd §1432): an owner at threshold 1; a wallet upgraded by
// EIP-7702 is still a wallet (the user's own, measured on Base), a contract is not.
check(YourAccountOp.addOwnerCall(account: want, owner: to).data
      == YourAccount.sel("addOwnerWithThreshold(address,uint256)") + YourAccount.w(to) + YourAccount.w(1)
      && YourAccountOp.addOwnerCall(account: want, owner: to).to == want, "the outside key is not addOwnerWithThreshold(key, 1) on the account")
check(!YourAccountOp.isContractCode("0x") && !YourAccountOp.isContractCode("0xef0100d6cedde84be40893d153be9d467cd6ad37875b28")
      && YourAccountOp.isContractCode("0x6080604052") && YourAccountOp.isContractCode("0xef0100d6cedde84be40893d153be9d467cd6ad37875b2800"),
      "a 7702-delegated wallet must read as a wallet, any other code as a contract")

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
xcrun swiftc -O -o "$TMP/t" "$ACCOUNT" "$OP" "$SWAP" "$COW" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccount.swift and YourAccountOp.swift do not compile alone (Foundation and the Safe encoders only)"; exit 1; }
"$TMP/t" || { echo "✗ your account's arithmetic drifted — see above"; exit 1; }

# The gates: Move is a tab in every build, with no switch to hide it, and a
# release build never offers a test network.
grep -rq 'MoveTab' Casberi/Casberi --include='*.swift' && { echo "✗ a switch hides Move again — a dormant feature in a release build is App Review 2.3.1 (prd §1435)"; exit 1; }
grep -q 'case feed, wallet, move, library, search' "$TABS" || { echo "✗ Move is not one of the five tabs (prd §1422)"; exit 1; }
grep -q 'static var allCases' "$TABS" && { echo "✗ PlaceTab.allCases is overridden — a build could drop a tab (prd §1435)"; exit 1; }
grep -A3 'static var networks' "$OP" | grep -q '#if DEBUG' || { echo "✗ YourAccountOp.networks offers Base Sepolia outside DEBUG"; exit 1; }

echo "✓ your account: the address is the factory's, the send's bytes are the module's, amounts add up, Move is in every build"
