#!/bin/zsh
# Lend (prd §1674): Move's verb for Aave. The calls must be byte-exact to the
# ones simulated against Base's and Ethereum's real state on 2026-11-02 (each
# landed: USDC and ETH, lend and take back, on both networks), the approval
# must be the amount and name the Pool, the supply must be on behalf of the
# account and a withdrawal must pay it, and `checked` must refuse any call
# that goes anywhere else. The rate is read, never written in.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/AaveLend.swift"
MOVE="Casberi/Casberi/Model/LendMove.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias L = AaveLend
let me = "0x2222222222222222222222222222222222222222"
let baseUSDC = L.market(chainId: 8453, symbol: "USDC")!, ethETH = L.market(chainId: 1, symbol: "ETH")!

// The four markets, as read off each Pool's getReserveData on 2026-11-02.
check(L.markets.count == 4 && L.chainIds == [8453, 1], "the markets are not Base's and Ethereum's USDC and ETH")
check(baseUSDC.pool == "0xa238dd80c259a72e81d7e4664a9801593f98d1c5" && ethETH.pool == "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
      "a Pool is not Aave v3's")
check(baseUSDC.aToken == "0x4e65fe4dba92790696d040ac24aa414708f5c0ab" && ethETH.aToken == "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8",
      "an aToken is not the reserve's")
check(ethETH.asset == "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2" && L.market(chainId: 8453, symbol: "ETH")!.asset == "0x4200000000000000000000000000000000000006",
      "ETH is not lent as its network's WETH")
check(L.market(chainId: 4663, symbol: "USDC") == nil, "Robinhood Chain, where Aave has no market, is offered")

// Byte-exact to the simulated calls.
let usdc = L.lend("25000000", in: baseUSDC, account: me)!
check(usdc == [
    .init(to: baseUSDC.asset, data: "0x095ea7b3000000000000000000000000a238dd80c259a72e81d7e4664a9801593f98d1c500000000000000000000000000000000000000000000000000000000017d7840", value: "0"),
    .init(to: baseUSDC.pool, data: "0x617ba037000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000017d784000000000000000000000000022222222222222222222222222222222222222220000000000000000000000000000000000000000000000000000000000000000", value: "0"),
], "lending 25 USDC on Base is not the simulated approve and supply")
let eth = L.lend("10000000000000000", in: ethETH, account: me)!
check(eth == [
    .init(to: ethETH.asset, data: "0xd0e30db0", value: "10000000000000000"),
    .init(to: ethETH.asset, data: "0x095ea7b300000000000000000000000087870bca3f3fd6335c3f4ce8392d69350b4fa4e2000000000000000000000000000000000000000000000000002386f26fc10000", value: "0"),
    .init(to: ethETH.pool, data: "0x617ba037000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000002386f26fc1000000000000000000000000000022222222222222222222222222222222222222220000000000000000000000000000000000000000000000000000000000000000", value: "0"),
], "lending 0.01 ETH on Ethereum is not the simulated wrap, approve and supply")
check(L.takeBack("150000000", all: true, in: baseUSDC, account: me)! == [
    .init(to: baseUSDC.pool, data: "0x69328dec000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000002222222222222222222222222222222222222222", value: "0"),
], "taking back all USDC does not withdraw the whole balance to the account")
check(L.takeBack("10000000000000000", all: false, in: ethETH, account: me)! == [
    .init(to: ethETH.pool, data: "0x69328dec000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000002222222222222222222222222222222222222222", value: "0"),
    .init(to: ethETH.asset, data: "0x2e1a7d4d000000000000000000000000000000000000000000000000002386f26fc10000", value: "0"),
], "taking back 0.01 ETH does not withdraw exactly it and unwrap it")
check(L.lend("0", in: baseUSDC, account: me) == nil && L.lend("1.5", in: baseUSDC, account: me) == nil
      && L.lend("5", in: baseUSDC, account: "0x12") == nil, "nothing, a fraction or a bad account is written")

// What is signed is only this.
check(L.checked(usdc, in: baseUSDC, account: me) && L.checked(eth, in: ethETH, account: me), "a written lend is refused")
check(L.checked(L.takeBack("1", all: false, in: ethETH, account: me)!, in: ethETH, account: me), "a written take back is refused")
let other = "0x3333333333333333333333333333333333333333"
func swap(_ s: String, _ a: String, _ b: String) -> String { s.replacingOccurrences(of: a, with: b) }
check(!L.checked(L.lend("25000000", in: baseUSDC, account: other)!, in: baseUSDC, account: me), "a supply for someone else is signed")
check(!L.checked(L.takeBack("1", all: true, in: baseUSDC, account: other)!, in: baseUSDC, account: me), "a withdrawal to someone else is signed")
check(!L.checked([usdc[0], .init(to: usdc[1].to, data: swap(usdc[1].data, "017d7840", "017d7841"), value: "0")], in: baseUSDC, account: me),
      "a supply over its approval is signed")
check(!L.checked([.init(to: usdc[0].to, data: swap(usdc[0].data, "a238dd80", "b238dd80"), value: "0"), usdc[1]], in: baseUSDC, account: me),
      "an approval to another spender is signed")
check(!L.checked([usdc[0]], in: baseUSDC, account: me), "an approval no supply spends is signed")
check(!L.checked(usdc.map { .init(to: other, data: $0.data, value: $0.value) }, in: baseUSDC, account: me), "a call to another contract is signed")
check(!L.checked(usdc, in: ethETH, account: me), "Base's calls are signed for Ethereum")
check(!L.checked([.init(to: baseUSDC.asset, data: "0xd0e30db0", value: "5")] + usdc, in: baseUSDC, account: me), "a wrap is signed for USDC")
check(!L.checked([], in: baseUSDC, account: me), "nothing is signed as something")

// Reads: the rate and the aToken off a reserve's answer.
func w(_ hex: String) -> String { String(repeating: "0", count: 64 - hex.count) + hex }
let ray = "2907356344813d98000000"   // 4.96% a year, per second, in rays
var words = Array(repeating: w("0"), count: 15)
words[2] = w(ray); words[8] = w("4e65fe4dba92790696d040ac24aa414708f5c0ab")
let answer = "0x" + words.joined()
check(L.aToken(reserveData: answer) == baseUSDC.aToken, "the reserve's aToken is misread")
let apy = L.apy(reserveData: answer) ?? -1
check(apy > 0.0507 && apy < 0.0510, "a 4.96% supply rate does not compound to 5.08% a year (\(apy))")
check(L.rateLine(apy) == "5.1% on Aave" && L.rateLine(0.123) == "12% on Aave" && L.rateLine(nil) == nil && L.rateLine(0) == nil,
      "the rate's words are wrong")
check(L.apy(reserveData: "0x1234") == nil, "a short answer reads as a rate")
check(L.decimal(hex: "0x017d7840") == "25000000" && L.decimal(hex: "0x0") == "0", "a balance is misread")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   the markets, the simulated calls byte for byte, what is refused, the rate")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

# Lend signs through your account's one simulated path, after `checked`.
grep -qF 'guard let calls, AaveLend.checked(calls, in: m, account: account) else {' "$MOVE" || fail "Lend signs calls checked by nothing"
c=$(grep -n 'AaveLend.checked(calls' "$MOVE" | cut -d: -f1); s=$(grep -n 'try await YourAccountChain.lendCalls(' "$MOVE" | cut -d: -f1)
[[ -n "$c" && -n "$s" && "$c" -lt "$s" ]] || fail "Lend signs before its calls are checked"
awk '/static func lendCalls\(/,/^    }$/' "$CHAIN" | grep -qF 'try await privateCalls(list, on: net, reason: reason, stage: stage)' \
    || fail "Lend no longer takes the account's simulated path"
grep -qF 'a.lowercased() != m.aToken { refused.insert(r.key) }' "$MOVE" || fail "a reserve naming another aToken is still offered"
! grep -qE 'rates\[[^]]*\] = [0-9]' "$MOVE" || fail "a rate is written in, not read"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "an unlimited approval"         's/data: "0x095ea7b3" \+ word\(address: m\.pool\) \+ a,/data: "0x095ea7b3" + word(address: m.pool) + max,/'
mutate "a supply on behalf of no one"  's/\+ a \+ word\(address: account\) \+ zero/+ a + zero + zero/'
mutate "a withdrawal anywhere"         's/args\[0\] == asset && args\[2\] == me && c\.value == "0":/args[0] == asset \&\& c.value == "0":/'
mutate "an approval left standing"     's/return approved == nil/return true/'
mutate "a supply past its approval"    's/approved\.map\(\{ \$0 >= args\[1\] \}\) == true/true/'
mutate "the rate uncompounded"         's/return pow\(1 \+ apr \/ seconds, seconds\) - 1/return apr/'
