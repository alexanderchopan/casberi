#!/bin/zsh
# Olla in Earn (prd §1970): AZTEC staked through Olla's vault from your
# account. The calls must be byte-exact to the ones simulated against Ethereum
# on 2026-11-24 (a real holder's requestRedeem returned request 17; the owner
# of finalized request 15 could claim it), the approval must be the deposit and
# name the vault, a deposit must mint to the account and a request must name
# it twice, and `checked` must refuse anything else. The reads decode Olla's
# real answers, and the rate is what the share price did over 30 days.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/OllaStake.swift"
AAVE="Casberi/Casberi/Model/AaveLend.swift"
MOVE="Casberi/Casberi/Model/LendMove.swift"
SCREEN="Casberi/Casberi/Screens/MoveLend.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias O = OllaStake
let me = "0x2222222222222222222222222222222222222222"
let holder = "0x2f005d8993fc9fbe8f5b3642171f548f31346b4a"

// The market, as Olla's mainnet deployment lists it and the chain confirms.
let m = AaveLend.olla!
check(m.chainId == 1 && m.symbol == "AZTEC" && m.decimals == 18 && m.place == .olla && m.placeName == "Olla",
      "Olla is not AZTEC on Ethereum")
check(m.pool == "0x561c7cff430d2351dba8d75bfc48b7a6aae6187a" && m.aToken == "0x5d422936ce2636f8a890cd73ac01e7f1523d20ca"
      && m.asset == "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2", "Olla's vault, stAZTEC or AZTEC is not the deployed one")
check(AaveLend.isReceipt(O.stAztec), "stAZTEC is counted as a spendable token beside what is staked")
check(AaveLend.lend("1", in: m, account: me) == nil && AaveLend.takeBack("1", all: false, in: m, account: me) == nil,
      "Aave's calls are built for Olla")

// Byte-exact: the request simulated from a real holder (it returned id 17).
let ask = O.requestBack("100000000000000000000", account: holder)!
check(ask == [.init(to: O.vault, data: "0x7d41c86e0000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000002f005d8993fc9fbe8f5b3642171f548f31346b4a0000000000000000000000002f005d8993fc9fbe8f5b3642171f548f31346b4a", value: "0")],
      "asking back 100 stAZTEC is not the simulated requestRedeem")
check(O.claim(["15"]) == [.init(to: O.vault, data: "0x809f8360000000000000000000000000000000000000000000000000000000000000000f", value: "0")],
      "claiming request 15 is not the simulated claimRequestById")
let dep = O.deposit("5000000000000000000000", minShares: "4560000000000000000000", account: me)!
check(dep == [
    .init(to: O.aztec, data: "0x095ea7b3000000000000000000000000561c7cff430d2351dba8d75bfc48b7a6aae6187a00000000000000000000000000000000000000000000010f0cf064dd59200000", value: "0"),
    .init(to: O.vault, data: "0xbc157ac100000000000000000000000000000000000000000000010f0cf064dd5920000000000000000000000000000022222222222222222222222222222222222222220000000000000000000000000000000000000000000000f732b66015a5400000", value: "0"),
], "depositing 5,000 AZTEC is not an exact approve and a deposit to the account")
check(O.requestBack("99999999999999999999", account: me) == nil, "a request under Olla's 100 stAZTEC is written")
check(O.claim([]) == nil && O.deposit("0", minShares: "0", account: me) == nil, "an empty move is written")

// What is checked, and what is refused.
check(O.checked(dep, account: me) && O.checked(ask, account: holder) && O.checked(O.claim(["15", "16"])!, account: me),
      "Olla's own calls are refused")
check(!O.checked(dep, account: holder), "a deposit minting to someone else passes")
check(!O.checked([dep[0]], account: me), "an approval no deposit spends passes")
check(!O.checked([dep[1]], account: me), "a deposit with no approval passes")
let bigger = AaveLend.Call(to: O.vault, data: "0xbc157ac1" + String(repeating: "f", count: 64) + dep[1].data.dropFirst(74), value: "0")
check(!O.checked([dep[0], bigger], account: me), "a deposit past its approval passes")
check(!O.checked([.init(to: O.vault, data: ask[0].data, value: "1")], account: holder), "ETH riding a call passes")
let elsewhere = AaveLend.Call(to: O.vault, data: "0x7d41c86e" + String(ask[0].data.dropFirst(10).prefix(64))
                              + String(repeating: "0", count: 24) + "3333333333333333333333333333333333333333"
                              + String(ask[0].data.suffix(64)), value: "0")
check(!O.checked([elsewhere], account: holder), "a request paying another controller passes")
check(!O.checked([.init(to: O.aztec, data: "0xa9059cbb" + String(repeating: "0", count: 128), value: "0")], account: me),
      "a transfer of AZTEC passes")

// Olla's real answers (2026-11-24).
check(O.ids("0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000f") == ["15"],
      "activeRequestIds is not read as [15]")
check(O.ids("0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000") == [],
      "an empty request list is not read as empty")
let r16 = O.request(id: "16", "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000661f5c4508e64f12fc00000000000000000000000000000000000000000000006ee88d1ad83e8741f70000000000000000000000000000000000000000000000000f125d39d2a730a0")
check(r16 == O.Request(id: "16", ready: true, shares: "1883827652535933407996", assets: "2045898927412630471159"),
      "request 16 is not read as finalized, its shares and what it pays")
check(O.amount("0x0f2441a7de61d6") == nil, "a short answer is read")

// Arithmetic at the measured price (1 stAZTEC = 1.0910789877996692 AZTEC).
let rate = "1091078987799669200"
check(O.shares(forAssets: "1091078987799669200", rate: rate) == "1000000000000000000", "one share's worth is not one share")
check(O.assets(forShares: "4593580000000000000000", rate: rate) == "5011950000000000000000"
      || O.assets(forShares: "4593580000000000000000", rate: rate)!.hasPrefix("50119"), "shares are not worth their AZTEC")
let least = Decimal(string: O.minShares(forAssets: "1091078987799669200000", rate: rate)!)!
check(least == 995 * pow(10, 18), "a deposit does not mint at least 0.5% under the quote")

// The rate: 30 days of the share price, measured 1.0671 → 1.0911.
let apy = O.apy(now: "1091078987799669200", then: "1067071454659212200")!
check(apy > 0.30 && apy < 0.32, "the measured 30 days are not about 31% a year (\(apy))")
check(O.apy(now: "1", then: "2") == nil, "a falling share price is a rate")
check(AaveLend.rateOnly(apy) == "31%", "the rate does not read 31%")

if failures > 0 { exit(1) }
print("  ok   the market, the simulated calls byte for byte, what is refused, the reads, the rate")
SWIFT

xcrun swiftc -O "$SRC" "$AAVE" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the Olla self-test did not compile"
"$work/t" || fail "the Olla self-test failed"

# Earn signs Olla's calls only through `checked`, then the account's one
# simulated path, as it does Aave's.
grep -qF 'ollaCalls(units, account: account)' "$MOVE" || fail "Earn does not build Olla's calls"
grep -qF 'if m.place == .olla { return OllaStake.checked(calls, account: account) }' "$AAVE" || fail "Olla's calls are checked as Aave's"
grep -qF 'guard let calls, AaveLend.checked(calls, in: m, account: account) else {' "$MOVE" || fail "Earn signs calls checked by nothing"
! grep -qE 'rates\[[^]]*\] = [0-9]' "$MOVE" || fail "a rate is written in, not read"
# The audit gap is said where AZTEC goes in, and the queue where it comes out.
grep -qF "Olla's latest contract change isn't covered by its audit." "$SCREEN" || fail "Deposit on Olla no longer says the audit gap"
grep -qF '"in about a day"' "$SCREEN" || fail "Withdraw on Olla no longer says it takes about a day"
grep -qF 'Notifications.outcome(.readyToClaim' "$MOVE" || fail "a ready request is no longer told"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$AAVE" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "an approval left standing"    's/return approved == nil/return true/'
mutate "a deposit past its approval"  's/approved\.map\(\{ \$0 >= args\[0\] \}\) == true/true/'
mutate "a deposit to anyone"          's/args\.count == 3 && args\[1\] == me && approved/args.count == 3 \&\& approved/'
mutate "a request to any controller"  's/args\[1\] == me && args\[2\] == me:/args[2] == me:/'
mutate "ETH riding a call"            's/guard c\.value == "0" else \{ return false \}//'
mutate "no floor under the minimum"   's/\(Decimal\(string: shares\) \?\? 0\) >= minimumShares/true/'
mutate "the rate uncompounded"        's/pow\(n \/ t, 365 \/ days\) - 1/(n \/ t - 1) * 365 \/ days/'
mutate "the slippage floor dropped"   's/digits\(d \* keepBps \/ 10_000\)/digits(0)/'
