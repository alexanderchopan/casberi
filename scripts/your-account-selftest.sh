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
# and a swap's calls (prd §1440) checked against two real Relay quotes, with
# every way of tampering with them refused. It
# also holds Move to every build — no hidden or dormant feature in a release
# (prd §1435, App Review 2.3.1) — and Base Sepolia to DEBUG always.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
FIXTURES="$PWD/scripts/fixtures/your-account"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
MOVE="Casberi/Casberi/Screens/MoveScreen.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
for f in "$ACCOUNT" "$OP" "$SWAP" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$MOVE" "$TABS"; do
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
let usdc = YourAccountOp.Payment(network: YourAccountOp.base, token: YourAccountOp.dollar(on: YourAccountOp.base), amount: "2500000", to: to, toName: nil)
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

// Swap, through Relay (prd §1440): two real Relay quotes on Base
// (2026-10-19), one selling ETH, one selling USDC, read and checked as the
// phone does — and every way of tampering with them refused.
func fixture(_ name: String) -> [String: Any] {
    let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FIXTURES"]! + "/" + name)
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}
let usdcBase = YourAccountOp.dollar(on: YourAccountOp.base)
let ethJSON = fixture("relay-quote-eth-base.json"), usdcJSON = fixture("relay-quote-usdc-base.json")
let ethQuote = YourAccountSwap.quote(from: ethJSON, chainId: 8453, sell: YourAccountOp.eth)!
check(ethQuote.sellAmount == "1000000000000000" && ethQuote.minimumBuy == "2367794", "Relay's ETH quote reads its amounts")
let ethChecked = YourAccountSwap.checked(ethQuote, sell: YourAccountOp.eth, amount: "1000000000000000")
check(ethChecked != nil && ethChecked!.approvals.isEmpty && ethChecked!.calls.count == 1
      && YourAccountSwap.routers.contains(ethChecked!.calls[0].to) && ethChecked!.calls[0].value == "1000000000000000",
      "selling ETH is one call to Relay's router carrying exactly the amount sold")
check(YourAccountSwap.checked(ethQuote, sell: YourAccountOp.eth, amount: "999") == nil, "a quote for another amount is refused")
check(YourAccountSwap.quote(from: ethJSON, chainId: 1, sell: YourAccountOp.eth) == nil, "a quote for another chain is refused")
var elsewhere = ethQuote.calls; elsewhere[0] = .init(to: "0x000000000000000000000000000000000000dead", value: elsewhere[0].value, data: elsewhere[0].data)
check(YourAccountSwap.checked(.init(sellAmount: ethQuote.sellAmount, buyAmount: ethQuote.buyAmount, minimumBuy: ethQuote.minimumBuy,
                                    fee: "0", requestId: nil, calls: elsewhere), sell: YourAccountOp.eth, amount: "1000000000000000") == nil,
      "a call to anything but Relay's contracts is refused")
var more = ethQuote.calls; more[0] = .init(to: more[0].to, value: "2000000000000000", data: more[0].data)
check(YourAccountSwap.checked(.init(sellAmount: ethQuote.sellAmount, buyAmount: ethQuote.buyAmount, minimumBuy: ethQuote.minimumBuy,
                                    fee: "0", requestId: nil, calls: more), sell: YourAccountOp.eth, amount: "1000000000000000") == nil,
      "more ETH than is sold is refused")
var signed = ethJSON; var steps = signed["steps"] as! [[String: Any]]; steps[0]["kind"] = "signature"; signed["steps"] = steps
check(YourAccountSwap.quote(from: signed, chainId: 8453, sell: YourAccountOp.eth) == nil, "a step asking for a signature is refused")

let usdcQuote = YourAccountSwap.quote(from: usdcJSON, chainId: 8453, sell: usdcBase)!
let usdcChecked = YourAccountSwap.checked(usdcQuote, sell: usdcBase, amount: "100000")
check(usdcChecked != nil && usdcChecked!.approvals.count == 1 && usdcChecked!.approvals[0].amount == "100000"
      && YourAccountSwap.approvalProxies.contains(usdcChecked!.approvals[0].spender)
      && usdcChecked!.calls.count == 1 && usdcChecked!.calls[0].value == "0",
      "selling a token approves exactly the amount sold to Relay's proxy, then one call")
check(usdcQuote.fee == "59", "Relay's fee in the sold token is read")
var wider = usdcQuote.calls
wider[0] = .init(to: wider[0].to, value: "0", data: Array(wider[0].data.prefix(36)) + SafeABI.word(uint256: "100001")!)
check(YourAccountSwap.checked(.init(sellAmount: "100000", buyAmount: usdcQuote.buyAmount, minimumBuy: usdcQuote.minimumBuy, fee: "0",
                                    requestId: nil, calls: wider), sell: usdcBase, amount: "100000") == nil,
      "an approval for more than is sold is refused")
var stranger = usdcQuote.calls
stranger[0] = .init(to: stranger[0].to, value: "0", data: YourAccountSwap.approveSelector + YourAccount.w("0x000000000000000000000000000000000000dEaD") + SafeABI.word(uint256: "100000")!)
check(YourAccountSwap.checked(.init(sellAmount: "100000", buyAmount: usdcQuote.buyAmount, minimumBuy: usdcQuote.minimumBuy, fee: "0",
                                    requestId: nil, calls: stranger), sell: usdcBase, amount: "100000") == nil,
      "an approval to anyone but Relay is refused")
let summed = YourAccountSwap.approvalCalls([(usdcChecked!.approvals[0].token, usdcChecked!.approvals[0].spender, "100000"),
                                            (usdcChecked!.approvals[0].token, usdcChecked!.approvals[0].spender, "250000")])!
check(summed.count == 1 && summed[0].data == YourAccountSwap.approveSelector + YourAccount.w(usdcChecked!.approvals[0].spender) + SafeABI.word(uint256: "350000")!,
      "two swaps selling one token approve their sum once (an approval replaces, never adds)")
check(YourAccountSwap.supported(YourAccountOp.base) && YourAccountSwap.supported(YourAccountOp.ethereum)
      && YourAccountSwap.supported(YourAccountOp.robinhood)
      && !YourAccountSwap.supported(YourAccountOp.baseSepolia), "Relay swaps on every live network the account is on, never a test network")
check(YourAccountOp.networks.filter { !$0.isTest }.allSatisfy(YourAccountSwap.supported),
      "a live network without swaps — send, receive and swap arrive together (prd §1441)")
check(YourAccountOp.dollar(on: YourAccountOp.robinhood).symbol == "USDG", "Robinhood Chain's dollar is USDG")

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
check(YourAccountOp.spoken("314172465981", decimals: 18) == "0.000000314" && YourAccountOp.spoken("1500000", decimals: 6) == "1.5"
      && YourAccountOp.spoken("100", decimals: 18) == "0.0000000000000001", "a tiny amount is spoken to three significant digits, never eighteen places")
check(YourAccountOp.atMost("999", "1000") && !YourAccountOp.atMost("1001", "1000") && YourAccountOp.atMost("0100", "100"), "atMost")
check(YourAccountOp.sum("999999999999999999999", "1") == "1000000000000000000000", "sum carries past UInt64")
check(YourAccountOp.decimal(hexQuantity: "0xde0b6b3a7640000") == "1000000000000000000", "hex quantity")

// The sentence's arithmetic (prd §1438): what is left, the slider's share,
// dollars typed, and a token's symbol as its contract answers it.
check(YourAccountOp.difference("1000", "1") == "999" && YourAccountOp.difference("5", "7") == "0"
      && YourAccountOp.difference("1000000000000000000000", "1") == "999999999999999999999", "what is left of a holding")
check(YourAccountOp.share("7948", percent: 50) == "3974" && YourAccountOp.share("7948", percent: 25) == "1987"
      && YourAccountOp.share("7948", percent: 100) == "7948" && YourAccountOp.share("3", percent: 25) == "0"
      && YourAccountOp.share("123456789012345678901234567890", percent: 75) == "92592591759259259175925925917", "the slider's share rounds down, past UInt64")
check(YourAccountOp.baseUnits(dollars: "5", price: 2.5, decimals: 6) == "2000000"
      && YourAccountOp.baseUnits(dollars: "1", price: 3, decimals: 6) == "333333"
      && YourAccountOp.baseUnits(dollars: "0", price: 3, decimals: 6) == nil
      && YourAccountOp.baseUnits(dollars: "5", price: 0, decimals: 6) == nil, "dollars typed become the token's units, rounded down")
let usdcSymbol = "0x" + String(repeating: "0", count: 62) + "20" + String(repeating: "0", count: 63) + "4"
    + "5553444300000000000000000000000000000000000000000000000000000000"
check(YourAccountOp.abiString(usdcSymbol) == "USDC", "an ABI string symbol")
check(YourAccountOp.abiString("0x4d4b520000000000000000000000000000000000000000000000000000000000") == "MKR", "a bytes32 symbol")
check(YourAccountOp.abiString("0x") == nil, "no answer is no symbol")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$ACCOUNT" "$OP" "$SWAP" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccount.swift and YourAccountOp.swift do not compile alone (Foundation and the Safe encoders only)"; exit 1; }
FIXTURES="$FIXTURES" "$TMP/t" || { echo "✗ your account's arithmetic drifted — see above"; exit 1; }

# The gates: Move is a tab in every build, with no switch to hide it, and a
# release build never offers a test network.
grep -rq 'MoveTab' Casberi/Casberi --include='*.swift' && { echo "✗ a switch hides Move again — a dormant feature in a release build is App Review 2.3.1 (prd §1435)"; exit 1; }
grep -q 'case feed, wallet, move, library, search' "$TABS" || { echo "✗ Move is not one of the five tabs (prd §1422)"; exit 1; }
grep -q 'static var allCases' "$TABS" && { echo "✗ PlaceTab.allCases is overridden — a build could drop a tab (prd §1435)"; exit 1; }
# The account's networks are the same in every build, no test network among
# them, DEBUG included (prd §1441a).
grep -q 'static let networks: \[Network\] = \[base, ethereum, robinhood\]$' "$OP" || { echo "✗ YourAccountOp.networks is not Base, Ethereum and Robinhood Chain in every build (prd §1441a)"; exit 1; }
grep -A4 'static let baseSepolia' "$OP" | grep -q 'isTest: true' || { echo "✗ Base Sepolia is not marked a test network"; exit 1; }

# Where the account can be used is read, never assumed (prd §1442k): Move
# names its networks only through YourAccountReach, and Receive reads it.
REACH=Casberi/Casberi/Model/YourAccountReach.swift
grep -q 'if YourAccountKey.holdsOrigin { return live }' "$REACH" || { echo "✗ YourAccountReach no longer limits a recovered phone to the networks the account exists on (prd §1442k)"; exit 1; }
for f in Casberi/Casberi/Screens/MoveSentence.swift Casberi/Casberi/Screens/MoveScreen.swift; do
  grep -q 'isTest }.map(\\.name)' "$f" && { echo "✗ $f names every network outright — a recovered phone would be told to receive where it cannot (prd §1442k)"; exit 1; }
done
grep -q 'reach = await YourAccountReach.usable(account)' Casberi/Casberi/Screens/MoveSentence.swift || { echo "✗ the sentence no longer reads where the account can be used (prd §1442k)"; exit 1; }

# Security offers only the networks this phone can sign on (prd §1442m): a
# Finish aimed at the rest is offered and then refused.
SEC=Casberi/Casberi/Screens/MoveSecurity.swift
grep -q 'let targets = fixable.map(\\.network)' "$SEC" || { echo "✗ the recovery row's Finish no longer aims only at this phone's networks (prd §1442m)"; exit 1; }
grep -q 'outside.isEmpty && canFix($0) }.map(\\.network)' "$SEC" || { echo "✗ the outside key's Finish no longer aims only at this phone's networks (prd §1442m)"; exit 1; }
# Money on a network without the recovery key is asked about, from the sweep,
# and never signed for on its own (prd §1442m).
grep -q 'await YourAccountProtection.check()' Casberi/Casberi/Model/BridgeRefresh.swift || { echo "✗ the foreground sweep no longer checks for money the recovery key does not cover (prd §1442m)"; exit 1; }
grep -v '^[[:space:]]*//' Casberi/Casberi/Model/YourAccountProtection.swift | grep -q 'addRecovery\|addOutsideKey\|transact(' && { echo "✗ YourAccountProtection signs: opening a network is a Face ID the person asks for (prd §1442m)"; exit 1; }
grep -q 'RecoveryKeyNudge().listRow' Casberi/Casberi/Screens/FeedScreen+WalletHome.swift || { echo "✗ the Wallet's Home no longer draws the recovery-key row (prd §1442m)"; exit 1; }

echo "✓ your account: the address is the factory's, the send's bytes are the module's, amounts add up, Move is in every build, it names only networks this phone can use, and asks where money lacks the recovery key"
