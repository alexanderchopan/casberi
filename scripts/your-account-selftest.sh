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
# and a swap's calls (prd §1539) written by the phone and checked, the batch
# rules held (`direct-swap-selftest.sh` pins the bytes). It
# also holds Move to every build — no hidden or dormant feature in a release
# (prd §1435, App Review 2.3.1) — and Base Sepolia to DEBUG always.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
ACROSS="Casberi/Casberi/Model/YourAccountAcross.swift"
ADAPTER="Casberi/Casberi/Model/YourAccount7579.swift"
FIXTURES="$PWD/scripts/fixtures/your-account"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
ROUNDUPS="Casberi/Casberi/Model/RoundUps.swift"
MOVE="Casberi/Casberi/Screens/MoveScreen.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
for f in "$ACCOUNT" "$OP" "$SWAP" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$MOVE" "$TABS"; do
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

// On Safe's 7579 adapter (prd §1447 item 11): the same batch through its
// `execute` as one delegatecall to MultiSend, and the SafeOp hash in the
// adapter's domain — pinned to what the deployed v1 adapter's `getSafeOp`
// answered on Base for these bytes (keccak of its operationData).
let adapterCalls = [YourAccountOp.call(for: eth)!]
let acd = YourAccountOp.callData(calls: adapterCalls, rotateTo: (x, y), entry: .adapter)!
check(Array(acd.prefix(5)) == SafeABI.hexBytes("0xe9ae5c53ff")!, "the adapter's call is not execute(bytes32,bytes) in delegatecall mode")
check(Keccak256.hexString(k(acd)) == "6577c8b4040928c27af4f5ae93fec2df1e7cc0846c3e1a3a34b0c069c4a71312", "the adapter's batch bytes changed")
var aop = YourAccountOp.Op(sender: want, nonce: 0, factory: nil, factoryData: [], callData: acd)
aop.verificationGasLimit = 500000; aop.callGasLimit = 100000; aop.preVerificationGas = 60000
aop.maxFeePerGas = 2000000; aop.maxPriorityFeePerGas = 1000000
aop.signature = YourAccountOp.dummySignature
aop.entry = .adapter
check(Keccak256.hexString(YourAccountOp.safeOpHash(aop, chainId: 8453)) == "1d9528b67175addfa7a3b85fb67ec3b4d6eca26614a74c754805404f5ab2b16a",
      "the SafeOp hash on the adapter is not what Safe's 7579 adapter on Base answered for the same op")
var amod = aop; amod.entry = .module4337
check(YourAccountOp.safeOpHash(amod, chainId: 8453) != YourAccountOp.safeOpHash(aop, chainId: 8453), "the adapter's hash does not take its own domain")
check(YourAccountOp.firstBytes(YourAccount.w(32) + YourAccount.w(3) + [1, 2, 3] + [UInt8](repeating: 0, count: 29)) == [1, 2, 3], "an answer's first bytes are not read")
// The spend limit's session (prd §1447 item 14), each pinned to bytes
// re-derived apart from this code and proven on Base: the passkey config
// packed into Smart Sessions' 320 bytes, the session's id, the session, the
// dollar transfer, and a session op's hash as the EntryPoint answered it.
let sx = [UInt8](repeating: 0x11, count: 32), sy = [UInt8](repeating: 0x22, count: 32)
let svi = YourAccount7579.validatorInitData(x: sx, y: sy)
check(svi.count == 320, "the session key's config no longer fits Smart Sessions' 320 bytes")
check(Keccak256.hexString(k(svi)) == "ce8b39a70ac8d8be4c45ed41d887c2cc38c659d2ecb29018deb7013bab3a93af", "the session key's packed config changed")
let susdc = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
// A period limit (prd §1447 item 15): one session per window, the dollar
// by `transfer` and ETH through Multicall3, each a total within the window.
let swin = YourAccount7579.Window(from: 1792560060, until: 1792560660)
let splan = YourAccount7579.Plan(chainId: 8453, dollar: susdc, dollarCap: "600000", ethCap: "2000000000000", windows: [swin])
check(SafeABI.hex(YourAccount7579.timeFrameInit(swin)) == "0x00006ad84e1400006ad84bbc", "a window's time frame is not validUntil then validAfter, six bytes each")
check(Keccak256.hexString(YourAccount7579.permissionId(validatorInit: svi, salt: YourAccount7579.salt(splan, swin)))
      == "22de65785c1c0634061ef98a5e609853cb7ca904ea19b329ebe33add6b88fad7", "a window's permission id changed")
check(Keccak256.hexString(k(YourAccount7579.session(validatorInit: svi, plan: splan, window: swin)!))
      == "6c5a443b08d2faee2e9ae231c2ed4a737f745aece0de9a712e563c97e2b90d75", "a window's session bytes changed")
check(YourAccount7579.windows(start: 100, seconds: 10, count: 3) == [.init(from: 100, until: 110), .init(from: 110, until: 120), .init(from: 120, until: 130)],
      "windows are not back to back")
check(splan.window(at: 1792560660) == nil && splan.window(at: 1792560060) == swin, "a window does not hold its start and drop its end")
let sacct = "0x82d443cb2dc0F924f5Cc5156e557ECB202283Dc6"
check(Keccak256.hexString(k(YourAccount7579.ethSendCall(to: sacct, wei: "1500000000000")!))
      == "0f786ad4dae2db1d610f549ea6a7f1e87a37be14b2ce0700d61e59e517886d93", "ETH under the limit no longer goes through Multicall3 as built")
let mApprove = YourAccountOp.Call(operation: 0, to: susdc, value: YourAccount.w(0),
                                  data: YourAccount.sel("approve(address,uint256)") + YourAccount.w(YourAccount7579.multicall3) + YourAccount.w(1))
let otherApprove = YourAccountOp.Call(operation: 0, to: susdc, value: YourAccount.w(0),
                                      data: YourAccount.sel("approve(address,uint256)") + YourAccount.w(sacct) + YourAccount.w(1))
check(YourAccount7579.approvesMulticall3(mApprove) && !YourAccount7579.approvesMulticall3(otherApprove),
      "an approval to Multicall3 is not caught, or another is")
let stc = YourAccount7579.transferCall(token: susdc, to: "0x82d443cb2dc0F924f5Cc5156e557ECB202283Dc6", units: "500000")!
check(Keccak256.hexString(k(stc)) == "e7ac0d56f0e885a1c04b91ad63d5ba08cfb27a6281c837ac0675b8e6d27dd0be", "the session's transfer call changed")
var sop = YourAccountOp.Op(sender: "0x82d443cb2dc0F924f5Cc5156e557ECB202283Dc6", nonce: 7, factory: nil, factoryData: [], callData: stc)
sop.nonceKey = YourAccount7579.sessionNonceKey
sop.verificationGasLimit = 500000; sop.callGasLimit = 100000; sop.preVerificationGas = 60000
sop.maxFeePerGas = 2000000; sop.maxPriorityFeePerGas = 1000000
check(Keccak256.hexString(YourAccountOp.userOpHash(sop, chainId: 8453)) == "d59bff9f0a72eb2cdb01e14642cc07c376eaf838ea00ae8478e9697f0abec4b9",
      "a session op's hash is not what the EntryPoint on Base answered")
check(sop.json["nonce"] as? String == "0x8bdaba73cd9815d79069c247eb4bda000000000000000000000007", "a session op's nonce is not its key then its sequence")
// Both keys (prd §1447 item 16): Safe takes signatures by owner, ascending,
// 65-byte static parts, the passkey's assertion after them at offset 130.
let ecdsa = [UInt8](repeating: 0xAB, count: 64) + [27]
let low = YourAccountOp.bothSignatures(r: x, s: y, signer: "0x3abcb61a90a342e1465525508469b3b5d860f612", ecdsa: ecdsa)!
let high = YourAccountOp.bothSignatures(r: x, s: y, signer: "0xfffffffffffffffffffffffffffffffffffffff0", ecdsa: ecdsa)!
check(Array(low[12..<77]) == ecdsa && Array(low[77..<109]) == YourAccount.w(YourAccount.sharedSigner), "a Signer below the passkey's address does not sign first")
check(Array(high[12..<44]) == YourAccount.w(YourAccount.sharedSigner) && Array(high[77..<142]) == ecdsa, "a Signer above the passkey's address does not sign second")
check(Array(low[109..<141]) == YourAccount.w(130) && Array(high[44..<76]) == YourAccount.w(130), "the passkey's assertion is not after both static parts")
check(low.count == high.count && Array(low.suffix(from: 142)) == Array(high.suffix(from: 142)), "the passkey's assertion moved with the order")
// What the Signer's wallet is asked to sign (prd §1447 item 17): the SafeOp
// as typed data, whose EIP-712 digest — read by the app's own general parser
// — is the very hash this phone signs, on the adapter's domain and with a
// session's keyed nonce alike.
for (label, tdOp) in [("the adapter's op", aop), ("a keyed-nonce op", { var o = sop; o.entry = .adapter; return o }())] {
    let json = YourAccountOp.safeOpTypedData(tdOp, chainId: 8453)!
    let parsed = EIP712.parse(try! JSONSerialization.jsonObject(with: Data(json.utf8)))!
    check(EIP712.digest(parsed) == YourAccountOp.safeOpHash(tdOp, chainId: 8453), "\(label)'s typed data does not hash to the SafeOp hash the phone signs")
}
check(YourAccountOp.decimal(YourAccount.w(0)) == "0" && YourAccountOp.decimal(YourAccount.w(1234567890)) == "1234567890"
      && YourAccountOp.decimal(sop.nonceWord) == "57532766240966947952054840643333136270388981957654712034659401735",
      "a word's decimal is wrong")
// Round-ups (prd §1452): the change to the next $1 or $5, nothing when whole,
// counted until the count reaches $5, then everything counted is bought.
check(RoundUps.change("4300000", step: 1) == "700000" && RoundUps.change("4000000", step: 1) == "0"
      && RoundUps.change("4300000", step: 5) == "700000" && RoundUps.change("5300000", step: 5) == "4700000"
      && RoundUps.change("1", step: 1) == "999999", "a round-up's change is wrong")
check(RoundUps.plan(dollarSent: "4300000", saved: "3400000", step: 1) == .init(change: "700000", buy: nil, savedAfter: "4100000"),
      "a round-up under $5 is not counted")
check(RoundUps.plan(dollarSent: "4300000", saved: "4500000", step: 1) == .init(change: "700000", buy: "5200000", savedAfter: "0"),
      "a round-up reaching $5 does not buy everything counted")
check(RoundUps.plan(dollarSent: "4300000", saved: "4300000", step: 1) == .init(change: "700000", buy: "5000000", savedAfter: "0"),
      "exactly $5 does not buy")
// Adding a key keeps the network's threshold (prd §1456): at 2 — the spend
// limit on — a recovery key or a Signer added never drops it to one key.
check(Array(YourAccountOp.addOwnerCall(account: want, owner: want, threshold: 2).data.suffix(32)) == YourAccount.w(2)
      && Array(YourAccountOp.addRecoveryCalls(account: want, x: x, y: y, signer: want, threshold: 2)[1].data.suffix(32)) == YourAccount.w(2),
      "adding a key resets the threshold: the spend limit would switch itself off")
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
check(YourAccount.short(want) == "...29Ce", "an address is its last four or the whole of it (prd §495)")

// Swap, straight to the exchanges (prd §1539, §1542): the phone writes the
// calls; `direct-swap-selftest.sh` pins them byte for byte against swaps
// simulated on Base. Here, the batch rules the account relies on: selling
// ETH is one call carrying exactly the amount, selling a token one exact
// approval to the router that swaps it, and two sales of one token through
// one router approve their sum once.
let usdcBase = YourAccountOp.dollar(on: YourAccountOp.base)
let book = YourAccountSwap.base
let me = "0x09930469ea9d645bb4141d94af5f2d02a22d29ce"
let ethRoute = YourAccountSwap.Route(venue: book.venues[0], hops: [.init(from: book.weth, to: usdcBase.contract!.lowercased(), step: 500)])
let ethCalls = YourAccountSwap.calls(ethRoute, in: book, sellsETH: true, buysETH: false, amount: "1000000000000000",
                                     minimum: "2367794", account: me, deadline: 2_000_000_000)!
let ethQuote = YourAccountSwap.Quote(sellAmount: "1000000000000000", buyAmount: "2380000", minimumBuy: "2367794", route: ethRoute, calls: ethCalls)
let ethChecked = YourAccountSwap.checked(ethQuote, sell: YourAccountOp.eth, amount: "1000000000000000", chainId: 8453)
check(ethChecked != nil && ethChecked!.approvals.isEmpty && ethChecked!.calls.count == 1
      && YourAccountSwap.routers(8453).contains(ethChecked!.calls[0].to) && ethChecked!.calls[0].value == "1000000000000000",
      "selling ETH is one call to a pinned router carrying exactly the amount sold")
check(YourAccountSwap.checked(ethQuote, sell: YourAccountOp.eth, amount: "999", chainId: 8453) == nil, "a quote for another amount is refused")
check(YourAccountSwap.checked(ethQuote, sell: YourAccountOp.eth, amount: "1000000000000000", chainId: 1) == nil, "a quote for another chain is refused")
let usdcRoute = YourAccountSwap.Route(venue: book.venues[0], hops: [.init(from: usdcBase.contract!.lowercased(), to: book.weth, step: 500)])
let usdcCalls = YourAccountSwap.calls(usdcRoute, in: book, sellsETH: false, buysETH: true, amount: "100000",
                                      minimum: "40000000000000", account: me, deadline: 2_000_000_000)!
let usdcChecked = YourAccountSwap.checked(.init(sellAmount: "100000", buyAmount: "41000000000000", minimumBuy: "40000000000000",
                                                route: usdcRoute, calls: usdcCalls), sell: usdcBase, amount: "100000", chainId: 8453)
check(usdcChecked != nil && usdcChecked!.approvals.count == 1 && usdcChecked!.approvals[0].amount == "100000"
      && usdcChecked!.approvals[0].spender == book.venues[0].router
      && usdcChecked!.calls.count == 1 && usdcChecked!.calls[0].value == "0",
      "selling a token approves exactly the amount sold to the router that swaps it, then one call")
let summed = YourAccountSwap.approvalCalls([(usdcChecked!.approvals[0].token, usdcChecked!.approvals[0].spender, "100000"),
                                            (usdcChecked!.approvals[0].token, usdcChecked!.approvals[0].spender, "250000")])!
check(summed.count == 1 && summed[0].data == YourAccountSwap.approveSelector + YourAccount.w(usdcChecked!.approvals[0].spender) + SafeABI.word(uint256: "350000")!,
      "two swaps selling one token approve their sum once (an approval replaces, never adds)")
check(YourAccountSwap.supported(YourAccountOp.base) && YourAccountSwap.supported(YourAccountOp.ethereum)
      && YourAccountSwap.supported(YourAccountOp.robinhood) && !YourAccountSwap.supported(YourAccountOp.baseSepolia),
      "the account swaps on every live network it is on, never a test network")
check(YourAccountOp.networks.filter { !$0.isTest }.allSatisfy(YourAccountSwap.supported),
      "a live network without swaps — send, receive and swap arrive together (prd §1441)")
check(YourAccountOp.networks.contains { $0.chainId == 4663 } && YourAccountOp.network(appName: "robinhood-mainnet")?.chainId == 4663,
      "Robinhood Chain is back with every feature (prd §1454): the spend limit's contracts are all there")

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
// An exported key's Remove (prd §1493): Safe's owner list is linked, so the
// call names the owner BEFORE it (the sentinel before the first) and keeps
// the threshold; it refuses an owner that is not one, or one too few left.
let ownA = "0x00000000000000000000000000000000000000aa", ownB = "0x00000000000000000000000000000000000000bb"
let ownC = "0x00000000000000000000000000000000000000cc", acct = "0x09930469ea9d645Bb4141d94af5f2d02A22D29Ce"
let removeSel = YourAccount.sel("removeOwner(address,address,uint256)")
check(removeSel == [0xf8, 0xdc, 0x5d, 0xd9], "removeOwner's selector is not Safe's f8dc5dd9")
check(YourAccountOp.removeOwnerCall(account: acct, owners: [ownA, ownB, ownC], owner: ownB, threshold: 1)?.data
      == removeSel + YourAccount.w(ownA) + YourAccount.w(ownB) + YourAccount.w(1), "removing the second owner does not name the first before it")
check(YourAccountOp.removeOwnerCall(account: acct, owners: [ownA, ownB], owner: ownA, threshold: 1)?.data
      == removeSel + YourAccount.w("0x0000000000000000000000000000000000000001") + YourAccount.w(ownA) + YourAccount.w(1), "removing the first owner does not name the sentinel")
check(YourAccountOp.removeOwnerCall(account: acct, owners: [ownA, ownB, ownC], owner: ownC, threshold: 2)?.data.suffix(32) == YourAccount.w(2)[...],
      "removing a key lowered the threshold (prd §1456 item 3)")
check(YourAccountOp.removeOwnerCall(account: acct, owners: [ownA, ownB], owner: ownB, threshold: 2) == nil, "a removal that leaves fewer owners than the threshold was written")
check(YourAccountOp.removeOwnerCall(account: acct, owners: [ownA, ownB], owner: ownC, threshold: 1) == nil, "a removal of a key that is no owner was written")
check(YourAccountOp.removeOwnerCall(account: acct, owners: [ownA, ownB], owner: ownB, threshold: 1)?.to == acct, "the removal is not a call to the account itself")
exit(bad == 0 ? 0 : 1)
SWIFT
# Round-ups read the demo's own account (prd §1475), which needs the app; off here.
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
xcrun swiftc -O -o "$TMP/t" "Casberi/Shared/AddressTail.swift" "$ACCOUNT" "$OP" "$SWAP" "$ACROSS" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/demo-stub.swift" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccount.swift and YourAccountOp.swift do not compile alone (Foundation and the Safe encoders only)"; exit 1; }
FIXTURES="$FIXTURES" "$TMP/t" || { echo "✗ your account's arithmetic drifted — see above"; exit 1; }

# The gates: Move is a tab in every build, with no switch to hide it, and a
# release build never offers a test network.
grep -rq 'MoveTab' Casberi/Casberi --include='*.swift' && { echo "✗ a switch hides Move again — a dormant feature in a release build is App Review 2.3.1 (prd §1435)"; exit 1; }
grep -q 'case feed, wallet, move, library, search' "$TABS" || { echo "✗ Move is not one of the five tabs (prd §1422)"; exit 1; }
grep -q 'static var allCases' "$TABS" && { echo "✗ PlaceTab.allCases is overridden — a build could drop a tab (prd §1435)"; exit 1; }
# The account's networks are the same in every build, no test network among
# them, DEBUG included (prd §1441a).
grep -q 'static let networks: \[Network\] = \[base, ethereum, robinhood\]$' "$OP" || { echo "✗ YourAccountOp.networks is not Base, Ethereum and Robinhood Chain in every build (prd §1441a, §1454)"; exit 1; }
grep -A4 'static let baseSepolia' "$OP" | grep -q 'isTest: true' || { echo "✗ Base Sepolia is not marked a test network"; exit 1; }

# The exported private key (prd §1493): never on Robinhood, never read as a
# Signer, its address noted before it goes on, never shown before it landed,
# and its bytes kept nowhere.
EXPORT=Casberi/Casberi/Model/YourAccountExport.swift
EXPORTPAGE=Casberi/Casberi/Screens/MoveExportKey.swift
grep -q 'net.chainId != YourAccountOp.robinhood.chainId' "$EXPORT" || { echo "✗ an exported key may go on Robinhood, which Safe's app is not known to open (prd §1493)"; exit 1; }
grep -q '&& !YourAccountExport.isExported(owner, for: account)' Casberi/Casberi/Model/YourAccountChain.swift || { echo "✗ YourAccountChain.signers reads an exported key as a Signer — a send would ask it to co-sign (prd §1493)"; exit 1; }
grep -q 'if YourAccountExport.isExported(owner, for: account) { exported.append(owner) }' Casberi/Casberi/Screens/MoveSecurity.swift || { echo "✗ Security draws an exported key as the Signer (prd §1493)"; exit 1; }
grep -qE 'SecItemAdd|kSecValueData' "$EXPORT" "$EXPORTPAGE" && { echo "✗ the exported key's bytes are written somewhere (prd §1493: shown once, kept nowhere)"; exit 1; }
grep -qE 'set\(.*hex' "$EXPORT" "$EXPORTPAGE" && { echo "✗ the exported key's hex is stored (prd §1493)"; exit 1; }
noted=$(grep -n 'YourAccountExport.note(key.address' "$EXPORTPAGE" | cut -d: -f1)
added=$(grep -n 'YourAccountChain.addOutsideKey(' "$EXPORTPAGE" | cut -d: -f1)
landed=$(grep -n 'guard !on.isEmpty else' "$EXPORTPAGE" | cut -d: -f1)
shown=$(grep -n 'stage = .shown(key, on: on, failed: failed)' "$EXPORTPAGE" | head -1 | cut -d: -f1)
[[ -n "$noted" && -n "$added" && "$noted" -lt "$added" ]] || { echo "✗ the exported key's address is no longer noted before it goes on — a crash would leave it read as a Signer (prd §1493)"; exit 1; }
[[ -n "$landed" && -n "$shown" && "$landed" -lt "$shown" ]] || { echo "✗ the export page can show a key that landed nowhere (prd §1493)"; exit 1; }

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
# (the lists moved behind `recoveryTargets`/`outsideTargets` when the opening operation took its rides, §1475; the rule is unchanged)
grep -q 'let targets = recoveryTargets.map(\\.network)' "$SEC" && grep -q 'return fixable.filter { !rides.contains($0.id) }' "$SEC" || { echo "✗ the recovery row's Finish no longer aims only at this phone's networks (prd §1442m)"; exit 1; }
grep -q 'let targets = outsideTargets.map(\\.network)' "$SEC" && grep -q 'outside.isEmpty && canFix($0) && !rides.contains($0.id) }' "$SEC" || { echo "✗ the outside key's Finish no longer aims only at this phone's networks (prd §1442m)"; exit 1; }
# Money on a network without the recovery key is asked about, from the sweep,
# and never signed for on its own (prd §1442m).
grep -q 'await YourAccountProtection.check()' Casberi/Casberi/Model/BridgeRefresh.swift || { echo "✗ the foreground sweep no longer checks for money the recovery key does not cover (prd §1442m)"; exit 1; }
grep -v '^[[:space:]]*//' Casberi/Casberi/Model/YourAccountProtection.swift | grep -q 'addRecovery\|addOutsideKey\|transact(' && { echo "✗ YourAccountProtection signs: opening a network is a Face ID the person asks for (prd §1442m)"; exit 1; }
# The nudge moved with Home's lists to the pages file (prd §1480); the guard followed it 2026-10-24.
grep -q 'RecoveryKeyNudge().listRow' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift || { echo "✗ the Wallet's Home no longer draws the recovery-key row (prd §1442m)"; exit 1; }

# The spend limit (prd §1455): Smart Sessions on Safe's adapter, never a
# contract of ours; turning it on refuses an account with no Signer (every send
# over it would wait on nobody); the row is drawn in every build (no hidden
# feature, §1435); the adapter's publish stays a throwaway's alone.
grep -q 'Add a signer first: over the limit, a send waits on it' Casberi/Casberi/Model/YourAccountChain.swift || { echo "✗ turning the limit on no longer refuses an account with no Signer (prd §1455)"; exit 1; }
grep -q '^                coSignerSwitchRow$' "$SEC" || { echo "✗ the co-signer switch is not drawn in every build (prd §1570, §1435)"; exit 1; }
grep -A9 'static func publishAdapter' Casberi/Casberi/Model/YourAccountChain.swift | grep -q 'guard dryRun || throwaway(account) else' || { echo "✗ publishing Safe's adapter runs outside the throwaway (prd §1447 item 18)"; exit 1; }
grep -q 'YourAccountSigning\|AllowanceModule' Casberi/Casberi/Model/*.swift Casberi/Casberi/Screens/*.swift && { echo "✗ the dropped Allowance-module design is back (prd §1447 item 9, §1455)"; exit 1; }
grep -q 'guard !calls.contains(where: YourAccount7579.approvesMulticall3) else' Casberi/Casberi/Model/YourAccountChain.swift || { echo "✗ operations no longer refuse an approval to Multicall3, which would ride the spend limit's ETH route (prd §1447 item 15)"; exit 1; }
grep -q '(c\["vmType"\] as? String) == "evm", (c\["depositAddressEnabled"\] as? Bool) == true' Casberi/Casberi/Model/YourAccountElsewhere.swift || { echo "✗ receiving from another network offers a network Relay takes no keyless deposit address on (prd §1453: EVM only, no Relay key)"; exit 1; }
grep -q 'WalletWatch.sameAddress(recipient, account)' Casberi/Casberi/Model/YourAccountChain.swift || { echo "✗ a Relay deposit address is taken without Relay naming the account as the one that gets it (prd §1452, §1453)"; exit 1; }
# Round-ups on the exchanges (prd §1545, user 2026-10-26): a Face ID send buys
# a token on its own network through the direct swap; the spend limit's
# session key never buys on the exchanges and is never widened to (its change
# keeps counting); Relay is only for a token on another network; an exchange
# buy is noted before Face ID so its own transaction reads as the buy.
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
grep -q 'if let roundUp = sessionRoundUp(roundUp, on: net) {' "$CHAIN" || { echo "✗ the session key's calls carry a round-up buy on the exchanges (prd §1545: the session is send-only)"; exit 1; }
grep -q 'let roundUp = sessionRoundUp(roundUp, on: net)' "$CHAIN" || { echo "✗ a session send keeps a round-up it cannot buy (prd §1545)"; exit 1; }
grep -q 'let roundUp = sessionRoundUp(asked, on: net)' Casberi/Casberi/Model/YourAccountChain+Preview.swift || { echo "✗ the session preview shows a round-up buy the session never makes (prd §1545)"; exit 1; }
grep -q 'if roundUp.target.onExchanges(from: net.chainId) {' "$CHAIN" || { echo "✗ a round-up on the send's own network is not bought on the exchanges (prd §1545)"; exit 1; }
grep -q 'let quote = try await swapQuote(net, sell: dollar, buy: buy, amount: roundUp.units, account: account)' "$CHAIN" || { echo "✗ a round-up's exchange buy is not quoted off the pools like a swap (prd §1545)"; exit 1; }
grep -q 'guard let checked = YourAccountSwap.checked(quote, sell: dollar, amount: roundUp.units, chainId: net.chainId)' "$CHAIN" || { echo "✗ a round-up's exchange buy is signed without the swap's check (prd §1542, §1545)"; exit 1; }
python3 - "$CHAIN" <<'PY' || { echo "✗ an exchange round-up is not noted before Face ID, so its transaction would read as spending (prd §1545)"; exit 1; }
import sys
s = open(sys.argv[1]).read()
t = s[s.index("static func transact("):]
t = t[:t.index("static func assemble(")]
n, o = t.find("RoundUps.noteSwapBuy("), t.find("let outcome = try await operate(")
sys.exit(0 if 0 <= n < o and "!dryRun" in t[t.rfind("if let roundUp", 0, n):n] else 1)
PY
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
grep -qF 'let bought = !toPrivate && buy != nil && !done.roundUpWaits' "$MOVE" \
  && grep -qF 'RoundUps.setSaved(RoundUps.savedAfter(roundUp, bought: bought), on: net.chainId)' "$MOVE" \
  || { echo "✗ a send that did not buy empties the round-up count (prd §1545)"; exit 1; }
grep -q 'return Chain.Transacted(sent: sent, roundUpWaits: roundUp != nil && Chain.sessionRoundUp(roundUp, on: net) == nil)' "$MOVE" || { echo "✗ a session send's round-up is counted as bought (prd §1545)"; exit 1; }
grep -q 'case .swap, .send: roundUpCarried != nil && !RoundUps.setting.target.onExchanges(from: network.chainId)' "$MOVE" || { echo "✗ an exchange round-up still says Relay carries it (prd §1545)"; exit 1; }

# Receive from another network, widened (prd §1470): what they send is every
# coin Relay bridges from their network, what arrives is your pick, the
# network's dollar unless they send ETH. The pure half compiles against a
# stub of YourAccountChain (the quote itself is a request) and reads Relay's
# own chain records, saved 2026-10-22.
ELSEWHERE="Casberi/Casberi/Model/YourAccountElsewhere.swift"
cat > "$TMP/elsewhere-stubs.swift" <<'SWIFT'
import Foundation
enum ENS { static func isHexAddress(_ s: String) -> Bool { let t = s.lowercased(); return t.hasPrefix("0x") && t.count == 42 && t.dropFirst(2).allSatisfy(\.isHexDigit) } }
enum YourAccountChain {
    struct Failure: Error, Equatable { let message: String; var from: String? = nil; init(message: String, from: String? = nil) { self.message = message; self.from = from } }
    struct Deposit: Equatable, Sendable { let address: String; let outUSD: Double?; let feeUSD: Double?; let seconds: Int? }
    static func relayChains() async -> [[String: Any]] { [] }
    static func depositAddress(fromChain chainId: Int, currency: String, to target: RoundUps.Target, amount: String, account: String, name: String) async throws -> Deposit { throw Failure(message: "stub") }
}
SWIFT
mkdir -p "$TMP/elsewhere"; cat > "$TMP/elsewhere/main.swift" <<'SWIFT'
import Foundation
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { bad += 1; print("✗ \(what)") } }
typealias E = YourAccountElsewhere
let data = try! Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["FIXTURES"]! + "/relay-chains.json"))
let chains = (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["chains"] as! [[String: Any]]
func chain(_ id: Int) -> [String: Any] { chains.first { ($0["id"] as? Int) == id }! }
let polygon = E.coins(of: chain(137)), ethereum = E.coins(of: chain(1)), base = E.coins(of: chain(8453))
let bnb = E.coins(of: chain(56)), arbitrum = E.coins(of: chain(42161))
// The native coin obeys its OWN supportsBridging: POL is listed and not bridged.
check(!polygon.contains { $0.isNative }, "POL is offered from Polygon though Relay does not bridge it")
check(polygon.map(\.symbol) == ["pUSD", "USDC", "USDC.e", "USDT"], "Polygon's coins are not its bridged ERC-20s A–Z: \(polygon.map(\.symbol))")
check(ethereum.first?.isNative == true && ethereum.first?.symbol == "ETH" && ethereum.count == 17, "Ethereum's coins are not ETH then its sixteen ERC-20s: \(ethereum.count)")
check(ethereum.map(\.symbol).contains("USDT") && ethereum.map(\.symbol).contains("DAI") && ethereum.map(\.symbol).contains("PYUSD"), "USDT, DAI and PYUSD are not offered from Ethereum")
check(!base.map(\.symbol).contains("DEGEN") && base.map(\.symbol).contains("cbBTC"), "Base's unbridged DEGEN is offered, or cbBTC is not")
check(arbitrum.map(\.symbol) == ["ETH", "APE", "USDC", "USDe", "USDT", "WETH"], "Arbitrum's coins: \(arbitrum.map(\.symbol))")
// What arrives unless you pick: the network's dollar, ETH for ETH.
let usdt = arbitrum.first { $0.symbol == "USDT" }!, eth = arbitrum.first { $0.isNative }!
check(E.defaultArrival(for: usdt, on: YourAccountOp.base) == YourAccountOp.dollar(on: YourAccountOp.base), "USDT does not land as USDC on Base by default")
check(E.defaultArrival(for: usdt, on: YourAccountOp.robinhood).symbol == "USDG", "USDT does not land as USDG on Robinhood Chain by default")
check(E.defaultArrival(for: eth, on: YourAccountOp.ethereum) == YourAccountOp.eth, "ETH does not land as ETH by default")
check(E.defaultArrival(for: bnb.first { $0.isNative }!, on: YourAccountOp.base) == YourAccountOp.dollar(on: YourAccountOp.base), "BNB does not land as USDC by default")
// The quote's amount: a fraction of a chain's coin or a bitcoin, ten of anything else, in that coin's units.
check(E.quoteAmount(eth) == "10000000000000000", "ETH's quote amount is not over Relay's 0.005 floor (prd §1485): \(E.quoteAmount(eth))")
// Relay's floor refusal is asked again over it, never shown (prd §1485).
check(E.overFloor("Amount must be greater than 5000000000000000 for deposit address quotes") == "10000000000000000", "Relay's floor is not read off its refusal")
check(E.overFloor("Route not supported") == nil, "a refusal with no floor is asked again")
check(E.quoteAmount(usdt) == "10000000", "USDT (6)'s quote amount: \(E.quoteAmount(usdt))")
check(E.quoteAmount(bnb.first { $0.symbol == "USDT" }!) == "10000000000000000000", "USDT on BNB (18 decimals) quotes ten in 6-decimal units")
check(E.quoteAmount(base.first { $0.symbol == "cbBTC" }!) == "50000", "cbBTC's quote amount: \(E.quoteAmount(base.first { $0.symbol == "cbBTC" }!))")
// A dollar that is the chain's own coin quotes ten, not half a cent (prd §1483: Arc's gas coin is USDC, 18 decimals).
let arcUSDC = E.Coin(symbol: "USDC", address: YourAccountSwap.native, decimals: 18)
check(arcUSDC.isNative && E.quoteAmount(arcUSDC) == "10000000000000000000", "Arc's own USDC quotes under Relay's floor: \(E.quoteAmount(arcUSDC))")
// One address per PAIR: the kept key names what arrives.
let k1 = E.keptKey("0xAbC", 42161, usdt, 8453, YourAccountOp.dollar(on: YourAccountOp.base)), k2 = E.keptKey("0xAbC", 42161, usdt, 8453, YourAccountOp.eth)
check(k1 != k2 && k1.hasPrefix("yourAccount.elsewhere.0xabc.42161."), "the kept address is not keyed on what arrives: \(k1)")
// The first coin offered on a network you switch to: what you were sending, where it has it, else USDC.
check(E.Network(id: 137, name: "Polygon", coins: polygon).coin(like: usdt)?.symbol == "USDT", "switching networks drops the coin being sent")
check(E.Network(id: 137, name: "Polygon", coins: polygon).coin(like: eth)?.symbol == "USDC", "a network without the coin being sent does not fall back to USDC")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/e" "Casberi/Shared/AddressTail.swift" "$ACCOUNT" "$OP" "$SWAP" "$ACROSS" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/demo-stub.swift" "$ELSEWHERE" "$TMP/elsewhere-stubs.swift" "$TMP/elsewhere/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccountElsewhere.swift does not compile against a stub of the chain (prd §1470)"; exit 1; }
FIXTURES="$FIXTURES" "$TMP/e" || { echo "✗ receiving from another network drifted (prd §1470) — see above"; exit 1; }
grep -q 'Picks what you receive' Casberi/Casberi/Screens/MoveSentence.swift && grep -q 'Picks what they send' Casberi/Casberi/Screens/MoveSentence.swift || { echo "✗ the receive sentence's two words are not both picks (prd §1470)"; exit 1; }
grep -q 'at the price when it lands' Casberi/Casberi/Screens/MoveSentence.swift || { echo "✗ a route that swaps on the way no longer says so (prd §1470, §83)"; exit 1; }
for f in requireBoth; do
  grep -A9 "static func $f" Casberi/Casberi/Model/YourAccountChain.swift | grep -q 'guard dryRun || throwaway(account) else' || { echo "✗ $f runs for real outside the throwaway (prd §1447 items 14–15)"; exit 1; }
done
awk '/private static func throwaway/,/^    }$/' Casberi/Casberi/Model/YourAccountChain.swift | grep -A1 '#else' | grep -q 'return false' || { echo "✗ a build outside DEBUG may install the adapter for real (prd §1447 item 13)"; exit 1; }
grep -q '0x540fb4f9\|initializeAccount((address,bytes)\[\],(address,bytes)\[\],(address,bytes)\[\],(address,bytes)\[\]' Casberi/Casberi/Model/YourAccount7579.swift || { echo "✗ initializeAccount is not the deployed v1 signature (prd §1447 item 11)"; exit 1; }
# The co-signer switch (prd §1570, retiring §1455's allowance): offered only
# where a co-signer stands on every network read; one switch walks every
# network; off asks the co-signer on each, since at 2-of-2 it cannot be one key's.
grep -q 'unsettled == nil && outsideOwner != nil && outsideTargets.isEmpty && !coSignerNetworks.isEmpty' "$SEC" || { echo "✗ the co-signer switch can be turned on with no co-signer on a network (prd §1570)"; exit 1; }
grep -q 'on ? notRequired : coSignerNetworks.filter { $0.threshold == 2 }' "$SEC" || { echo "✗ the one co-signer switch no longer walks every network (prd §1570)"; exit 1; }
grep -q 'turnOffLimit(on: net, coSigner: co,' "$SEC" && grep -q 'let co = s.threshold == 2 ? coSigner(s, batch) : nil' "$SEC" && grep -q 'Self.sharedSigner(cosigned)' "$SEC" || { echo "✗ turning the co-signer off no longer asks the co-signer — at 2-of-2 it cannot be one key's (prd §1570, §83)"; exit 1; }

# The keys chosen at Create (prd §1457): they ride only the operation that
# opens a network, the limit only with a Signer, both keys switched on LAST
# (while this phone alone still signs), and Create walks through them.
CH=Casberi/Casberi/Model/YourAccountChain.swift
grep -q 'if !deployed, let setup = try await setupCalls(net, account)' "$CH" || { echo "✗ the keys chosen at Create ride an operation on a network the account is already on (prd §1457)"; exit 1; }
awk '/static func setupCalls/,/^    }$/' "$CH" | awk '/addRecoveryCalls/{a=NR}/addOwnerCall/{b=NR}/changeThreshold/{e=NR}/installCalls|limitCalls/{x=1}END{exit !(a<b && b<e && !x)}' \
  || { echo "✗ setupCalls no longer adds recovery, the co-signer, then both keys last, with no allowance (prd §1457, §1570)"; exit 1; }
grep -q 'guard signer != nil, let limitDollars' Casberi/Casberi/Model/YourAccountSetup.swift || { echo "✗ a spend limit chosen at Create can stand with no Signer to sign over it (prd §1457)"; exit 1; }
awk '/static func setupCalls/,/^    }$/' Casberi/Casberi/Model/YourAccountChain.swift | grep -q 'limitPlan' && { echo "✗ the opening operation sets up an allowance again — the co-signer is required or not (prd §1570)"; exit 1; }
# A bundler's refusal reaches the person in the app's words (prd §1461 item 4).
grep -q 'last = worded(error, on: net)' Casberi/Casberi/Model/YourAccountChain.swift && grep -q 'lower.contains("max gas")' Casberi/Casberi/Model/YourAccountChain.swift || { echo "✗ a bundler's raw refusal (\"UserOperation max gas … is larger than\") reaches the person (prd §1461 item 4)"; exit 1; }
# Security's box is nine, three across, the figure centered over its word (prd §1462):
# the six counts and your account's limit, Signers and round-ups; the Signers
# figure is a last reading MoveSecurity stamps, never a zero it did not read.
# Security's box went with Security (prd §1480); the facts now trail Your
# account's door on Home as the one missing control, in amber (prd §1496).
FIG=Casberi/Casberi/Screens/FeedScreen+WalletPages.swift
grep -q 'if let facts = YourAccountFacts.current, facts.signers == 0' "$FIG" && grep -q 'walletDoor(.yourAccount, word: yourAccountWants, wordTone: DS.attentionInk)' "$FIG" || { echo "✗ Home's Your account door no longer trails the missing co-signer off the last reading (prd §1462, §1496)"; exit 1; }
grep -q 'YourAccountFacts.noteSigners(Set(live.flatMap' Casberi/Casberi/Screens/MoveSecurity.swift || { echo "✗ the box's Signers figure is no longer stamped by Security's read (prd §1462)"; exit 1; }
# The box's "Limit a month" went with the box (prd §1480); the limit is Your account's row word (prd §1496).
grep -q 'Every send and swap needs approval in' Casberi/Casberi/Screens/MoveSecurity.swift || { echo "✗ the co-signer row no longer says what required means (prd §1570)"; exit 1; }
# The wash says the state (prd §1463): a threat red, an ask orange, on green, nothing for a zero.
# The state is the figure's ink on Home's doors (prd §1463, §1496): a threat red, a grant with no limit amber, what waits on you pink.
grep -q 'figureTone: DS.destructiveInk' "$FIG" && grep -q 'figureTone: counts.unlimited > 0 ? DS.attentionInk : DS.textPrimary' "$FIG" && grep -q 'figureTone: DS.pickInk' "$FIG" || { echo "✗ Home's doors no longer carry the state in the figure's ink (prd §1463, §1496)"; exit 1; }
grep -q 'needsYouRow(glyph: kind.glyph, critical: true,' Casberi/Casberi/Screens/FeedScreen+WalletSecurity.swift || { echo "✗ a fake transfer's row is no longer red with the other threats (prd §1463)"; exit 1; }
awk '/case .threat: return DS.destructive/{a=1}/case .wants: return DS.attention$/{b=1}/case .on: return DS.confirm$/{c=1}END{exit !(a&&b&&c)}' Casberi/Casberi/Design/DSCountTile.swift || { echo "✗ DSCountTile's tones no longer map threat→destructive, wants→attention, on→confirm (prd §1463)"; exit 1; }
# The demo's account (prd §1475): it holds the demo's table and reaches no node,
# and nothing it shows can sign, copy or share — its address holds no key, so
# money sent there would be lost.
grep -q 'if YourAccountDemo.isDemo(account) { return YourAccountDemo.held(on: net) }' Casberi/Casberi/Model/YourAccountTokens.swift || { echo "✗ the demo account's holdings are read off a node, not the demo's table (prd §1475)"; exit 1; }
grep -q 'if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }' Casberi/Casberi/Screens/MoveSentence.swift || { echo "✗ Move can sign or copy the demo account's address (prd §1475)"; exit 1; }
[[ $(grep -c 'if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }' Casberi/Casberi/Screens/MoveSentence.swift) -ge 2 ]] || { echo "✗ Move's sign() and copy() no longer both refuse in the demo (prd §1475)"; exit 1; }
[[ $(grep -c 'if demoSays() { return }' Casberi/Casberi/Screens/MoveSecurity.swift) -ge 5 ]] || { echo "✗ a Security act changes a key in the demo (prd §1475)"; exit 1; }
grep -q 'walking = true' Casberi/Casberi/Screens/MoveScreen.swift || { echo "✗ Create no longer walks through your keys (prd §1457)"; exit 1; }
# ONE SIZE, ALWAYS (prd §1501, retiring §1479's pick-by-fit): every Move
# sentence and every screen of the create flow is heading52; a clause wider
# than a whole line wraps inside itself and a word wider than a line shrinks,
# so nothing ever steps the sentence down. These guards hold the mechanism,
# not the look: a fit returning (a ladder, a measurement feeding a pick) is
# the rule undone without anyone deciding it.
SENTENCE=Casberi/Casberi/Screens/MoveSentence.swift
FLOW=Casberi/Casberi/Screens/ThingSheetView.swift
WALK=Casberi/Casberi/Screens/MoveKeysWalk.swift
[[ -f Casberi/Casberi/Model/MoveFit.swift ]] && { echo "✗ MoveFit is back — the sentence picks a size again (prd §1501)"; exit 1; }
grep -q 'static let rung: DSTextStyle = .heading52' "$SENTENCE" || { echo "✗ Move's one size is no longer heading52 (prd §1501)"; exit 1; }
grep -q '.environment(\\.moveRung, MoveSentence.rung)' "$SENTENCE" || { echo "✗ MoveFlow no longer sets the one size for every word under it (prd §1501)"; exit 1; }
grep -q 'fitsWide: true' "$SENTENCE" && grep -q 'var fitsWide = false' "$FLOW" \
  || { echo "✗ a clause wider than a line is no longer offered the line — it would overflow the screen (prd §1501)"; exit 1; }
grep -q 'MoveClauseLayout(spacing: MoveSentence.clauseGap)' "$SENTENCE" || { echo "✗ a clause can no longer wrap inside itself (prd §1501)"; exit 1; }
grep -q 'rows(proposal.width, subviews).frames' "$SENTENCE" \
  || { echo "✗ a clause is placed against its rounded bounds, not the width it was measured for — its last word drops onto the next clause's line (prd §1511)"; exit 1; }
grep -q 'let width = proposal.width ?? bounds.width' "$FLOW" \
  || { echo "✗ the flow wraps against its rounded bounds, not the width it was measured for (prd §1511)"; exit 1; }
grep -q '\.minimumScaleFactor(0.5)' "$SENTENCE" || { echo "✗ a word wider than a line no longer shrinks — it would clip (prd §1501)"; exit 1; }
grep -q '@Environment(\\.moveRung) private var rung' "$SENTENCE" || { echo "✗ MoveWord no longer reads the flow's size (prd §1501)"; exit 1; }
grep -rq 'dsText(.heading28)\|dsText(.heading52)\|dsText(.heading44)' "$SENTENCE" Casberi/Casberi/Screens/MoveScreen.swift "$WALK" \
  && { echo "✗ a Move view names a sentence size itself instead of reading the flow's (prd §1501)"; exit 1; }
# The walk (prd §1501): the limit only with a co-signer, round-ups always,
# Created last; Done closes Move, Receive opens it on Receive.
grep -q 'case .signer: next = choice.signer == nil ? .roundUps : .limit' "$WALK" || { echo "✗ the walk's order drifted: the limit needs a co-signer, round-ups always follow (prd §1501)"; exit 1; }
grep -q 'case .created: String(localized: "Done")' "$WALK" && grep -q 'done(.close)' "$WALK" && grep -q 'done(.receive)' "$WALK" \
  || { echo "✗ Created no longer ends the walk with Done and Receive (prd §1501)"; exit 1; }
grep -q 'if ending == .close, inTray { chrome.moveTray = false }' Casberi/Casberi/Screens/MoveScreen.swift \
  || { echo "✗ Done no longer closes Move (prd §1501)"; exit 1; }
grep -q 'case created' "$SENTENCE" && { echo "✗ Move's Created arrival is back beside the walk's Created page (prd §1501, §723)"; exit 1; }
grep -q 'Self.short($0, decimals: buy.token.decimals)' "$SENTENCE" || { echo "✗ the For word draws the exact quote again — the clause outgrows 52 (prd §1479)"; exit 1; }
# WETH and ETH, one for one (prd §1559): asked before any pool, checked
# before Face ID, said on the foot.
grep -q 'if let w = YourAccountSwap.wrap(sell: sell, buy: buy, chainId: net.chainId) {' "Casberi/Casberi/Model/YourAccountChain+Swap.swift" \
  || { echo "✗ WETH for ETH asks the pools again, which find no route (prd §1559)"; exit 1; }
grep -q 'let checked = YourAccountSwap.checkedWrap(quote, sell: s.sell, buy: s.buy, amount: s.amount,' "Casberi/Casberi/Model/YourAccountChain.swift" \
  || { echo "✗ an unwrap is signed without its check (prd §1559)"; exit 1; }
grep -q 'steps.append((calls, (s.buy, s.amount)))' "Casberi/Casberi/Model/YourAccountChain.swift" \
  || { echo "✗ an unwrap is not simulated to pay back exactly what is sold (prd §1559)"; exit 1; }
grep -q 'return YourAccountSwap.words(w)' "$SENTENCE" || { echo "✗ the foot no longer says 'Unwraps WETH · no fee' (prd §1559)"; exit 1; }
# The ≈ stands before a pool's quote; Across's output is exact (prd §1556),
# unless the receiving network's pools swap it (prd §1566).
grep -q 'return (exact ? "" : "≈ ") + Self.figure(back, decimals: token.decimals)' "$SENTENCE" \
  && grep -q 'let exact = quote?.across.map { $0.swap == nil } == true || quote?.wrap != nil' "$SENTENCE" \
  || { echo "✗ the print line no longer carries the ≈ and the exact quote, or drops the ≈ for a pool's quote (prd §1479, §83, §1556)"; exit 1; }
# The fee after it is the network's alone since §1539: the pool's is in the price (`swapFeePrint`).
grep -q 'case .swap: \[soldPrint, quotePrint, swapFeePrint\]' "$SENTENCE" || { echo "✗ the swap's print line dropped the exact quote or the whole fee (prd §1479, §1509)"; exit 1; }

echo "✓ your account: the address is the factory's, the send's bytes are the module's, amounts add up, Move is in every build, it names only networks this phone can use, asks where money lacks the recovery key, the sentence is one size that wraps, the create walk ends on Created, and an exported key is kept apart and shown only once it landed"
