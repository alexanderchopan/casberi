#!/bin/zsh
# World App self-test (prd §795, 2026-09-16) — the pure half of World App's money
# on World Chain, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/WorldApp.swift   (+ Keccak256.swift, which it hashes with)
#
# WHY A HARNESS. Every read here answers with the same silence when it is wrong:
#
#   • A WRONG SELECTOR. `eth_call` with a mistyped selector reverts, and a vault
#     balance or a grant amount simply never appears. This file's first draft
#     hardcoded `grant()` and `getAmount(uint256)` from memory, and BOTH were
#     wrong. Pinned here against an outside keccak.
#   • A BALANCE OVER 18.4 WLD READ THROUGH A UInt64. The raw word overflows and
#     the vault reads as nothing — the measured depositors held 127, 100 and 40.
#   • AN OFF-BY-ONE GRANT MONTH. `WLDGrant` numbers grants `39 + months since
#     August 2024` in UTC; measured on chain, September 2026 is 64. One month
#     wrong states the wrong amount on the wrong date.
#   • A USERNAME FOR SOMEBODY ELSE. The record must name the SAME address, or a
#     stranger's handle lands beside your money.
#   • AN UNREACHABLE READ AS A ZERO. A malformed or empty return is nil, never 0.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Casberi/Casberi/Model/WorldApp.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
DEFI="Casberi/Casberi/Model/WorldAppDeFi.swift"
for f in "$APP" "$KECCAK" "$DEFI"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/world-app-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// keccak256(sig)[0..<4], computed by an implementation outside this app.
check(WorldApp.selector("balanceOf(address)") == "70a08231", "balanceOf selector")
check(WorldApp.selector("grant()") == "30c3eaa8", "grant() selector")
check(WorldApp.selector("getAmount(uint256)") == "9980ec86", "getAmount(uint256) selector")
check(WorldApp.grantCalldata == "0x30c3eaa8", "grant() calldata")

let who = "0x18F1E337A502C7DEA1AC46316F9B64512B71FABF"
check(WorldApp.balanceOfCalldata(owner: who)
      == "0x70a08231000000000000000000000000" + "18f1e337a502c7dea1ac46316f9b64512b71fabf",
      "balanceOf calldata, lowercased and left-padded")
check(WorldApp.balanceOfCalldata(owner: "0x1234") == nil, "a short address is refused")
check(WorldApp.balanceOfCalldata(owner: "vitalik.eth") == nil, "a name is refused")
check(WorldApp.getAmountCalldata(grantId: 64)
      == "0x9980ec86" + String(repeating: "0", count: 62) + "40", "getAmount(64) calldata")
check(WorldApp.getAmountCalldata(grantId: -1) == nil, "a negative grant id is refused")

// 127.309 WLD — far past UInt64's 18.44 WLD.
let bigHex = "6e6c46cfcee348000"
let big = "0x" + String(repeating: "0", count: 64 - bigHex.count) + bigHex
let amount = WorldApp.amount18(fromWord: big) ?? -1
check(amount > 100 && amount < 200, "a balance over 18.4 WLD reads whole — got \(amount)")
check(WorldApp.amount18(fromWord: "0x" + String(repeating: "0", count: 64)) == 0, "a zero word is zero")
check(WorldApp.amount18(fromWord: "0x") == nil, "an empty return is no balance, not zero")
check(WorldApp.amount18(fromWord: nil) == nil, "no return is no balance")
check(WorldApp.amount18(fromWord: "0x1234") == nil, "a truncated word is no balance")
check(WorldApp.address(fromWord: "0x0000000000000000000000001baa488dfed63954084f8c08367e79a695a229a5")
      == "0x1baa488dfed63954084f8c08367e79a695a229a5", "an address word")
check(WorldApp.address(fromWord: "0x") == nil, "a reverted grant() names no contract")

// The grant calendar, UTC months. MEASURED: Sep 2026 → 64 (checkValidity passes 63 and 64).
let utc = TimeZone(identifier: "UTC")!
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    var c = Calendar(identifier: .gregorian); c.timeZone = utc
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}
check(WorldApp.grantId(at: day(2024, 8, 15)) == 39, "August 2024 is grant 39")
check(WorldApp.grantId(at: day(2026, 9, 16)) == 64, "September 2026 is grant 64 (measured)")
check(WorldApp.grantId(at: day(2026, 10, 1, 0)) == 65, "October 2026 is grant 65")
check(WorldApp.grantId(at: day(2026, 9, 30, 23)) == 64, "the last hour of September is still 64")
let opens = WorldApp.nextGrantOpens(after: day(2026, 9, 16))
check(opens == day(2026, 10, 1, 0), "the next grant opens Oct 1 00:00 UTC — got \(String(describing: opens))")
check(WorldApp.nextGrantOpens(after: day(2026, 12, 20)) == day(2027, 1, 1, 0), "December rolls the year")

// Usernames: the record must be THIS address's.
let rec: [String: Any] = ["username": "laary.8938", "address": "0x18f1e337a502c7dea1ac46316f9b64512b71fabf",
                          "profile_picture_url": "https://static.usernames.app-backend.toolsforhumanity.com/a.png"]
check(WorldApp.username(fromJSON: rec, for: who)?.name == "laary.8938", "a record for this address, case folded")
check(WorldApp.username(fromJSON: rec, for: "0x" + String(repeating: "1", count: 40)) == nil,
      "a record naming a different address is refused")
check(WorldApp.username(fromJSON: ["error": "Record not found."], for: who) == nil, "not found is no name")
var http = rec; http["profile_picture_url"] = "http://example.com/a.png"
check(WorldApp.username(fromJSON: http, for: who)?.pictureURL == nil, "a non-https picture is dropped")

// A typed username (prd §802), MEASURED shapes: letters and digits, an optional
// ".NNNN" tag, case ignored, and nothing that could be half an address.
check(WorldApp.usernameQuery("andy") == "andy", "a bare username")
check(WorldApp.usernameQuery(" @Andy ") == "Andy", "a leading @ and whitespace are dropped, case kept")
check(WorldApp.usernameQuery("laary.8938") == "laary.8938", "the four-digit tag shape")
check(WorldApp.usernameQuery("vitalik.eth") == nil, "an ENS name is not a username")
check(WorldApp.usernameQuery("andy.123") == nil, "a three-digit tag is not World's shape")
check(WorldApp.usernameQuery("a_b") == nil && WorldApp.usernameQuery("a-b") == nil
      && WorldApp.usernameQuery("a b") == nil, "punctuation and spaces are not username characters")
check(WorldApp.usernameQuery("0x1234") == nil, "a half-typed hex address never asks World")
check(WorldApp.usernameQuery(String(repeating: "a", count: 20)) != nil
      && WorldApp.usernameQuery(String(repeating: "a", count: 21)) == nil, "twenty characters is the bound")
check(WorldApp.usernameQuery("1BoatSLRHtKNngkdXEeobR76b53LETtpyT") == nil, "a Bitcoin address is not a username")
check(WorldApp.usernameQuery("") == nil && WorldApp.usernameQuery("@") == nil, "nothing is not a username")

let holderRecord: [String: Any] = ["username": "worLd", "address": "0x9D5A5203A1B4B7F0B9C5E8C2A1D3E4F5A6B7C8D9"]
check(WorldApp.holder(fromJSON: holderRecord, forUsername: "world")
      == WorldApp.UsernameHolder(name: "worLd", address: "0x9d5a5203a1b4b7f0b9c5e8c2a1d3e4f5a6b7c8d9"),
      "the holder keeps World's spelling and a lowercased address")
check(WorldApp.holder(fromJSON: holderRecord, forUsername: "worlds") == nil,
      "a record for a different username names nobody")
check(WorldApp.holder(fromJSON: ["username": "andy", "address": "andy.eth"], forUsername: "andy") == nil,
      "a record without a hex address names nobody")
check(WorldApp.holder(fromJSON: ["error": "Record not found."], forUsername: "andy") == nil, "an error body names nobody")

// Blockscout logs (prd §797): the two shapes that differ from a node's.
let padded: [String: Any] = ["status": "1", "message": "OK", "result": [
    ["address": "0x2cfc85d8e48f8eab294be644d9e25c3030863003", "blockNumber": "0x4b45cc", "logIndex": "0x9a",
     "transactionHash": "0xabc", "data": "0xff",
     "topics": ["0x8c5b", "0x0000e135", "0x000022d4", NSNull()]]]]
let logs = WorldApp.blockscoutLogs(fromJSON: padded)
check((logs?.first?["topics"] as? [String])?.count == 3,
      "Blockscout's null topic pad is stripped — an ERC-20 approval keeps its 3 topics")
check(WorldApp.blockscoutLogs(fromJSON: ["status": "0", "message": "No logs found", "result": [Any]()])?.isEmpty == true,
      "'No logs found' is an empty answer, not a failure")
check(WorldApp.blockscoutLogs(fromJSON: ["status": "0", "message": "Something went wrong", "result": [Any]()]) == nil,
      "any other status 0 is a failure — the cursor must not advance")
check(WorldApp.blockscoutLogs(fromJSON: nil) == nil, "no answer is a failure")
let url = WorldApp.blockscoutLogsURL(address: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
                                     topic0: "0xDA9F", topic1: "0x0000E135", from: 10, to: 20)
check(url.contains("fromBlock=10&toBlock=20") && url.contains("topic0=0xda9f&topic1=0x0000e135&topic0_1_opr=and")
      && url.hasSuffix("&address=0x000000000022d473030f116ddee9f6b43ac78ba3"), "the Blockscout logs query — got \(url)")

if failures > 0 { print("✗ world-app-selftest: \(failures) failure(s)"); exit(1) }
SWIFT

swiftc -O -o "$TMP/run" "$APP" "$KECCAK" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ world-app-selftest did not compile"; exit 1; }
"$TMP/run"

# --- drift guards --------------------------------------------------------------
# A username is forward-verified: two lookups, the second by the username.
grep -q 'WorldApp.username(fromJSON: await IngestSupport.getJSON(usernamesAPI + encoded), for: addr) != nil' "$DEFI" \
  || { echo "✗ a World App username is no longer forward-verified — a stranger's handle could name this address"; exit 1; }
# A typed username is a name ONLY in the follow field (prd §802): the book's bulk
# paste reads a bare word as a person's name, so no Family may claim one.
ROUTER="Casberi/Casberi/Model/NameResolve.swift"
FIELD="Casberi/Casberi/Screens/WalletWatchField.swift"
awk '/static func family\(of raw: String\)/,/^    }$/' "$ROUTER" | grep -q 'usernameQuery' \
  && { echo "✗ NameResolve.family claims a World App username — a bulk paste's names become addresses"; exit 1; }
grep -q 'if let username = WorldApp.usernameQuery(raw) { return .worldAppUsername(username) }' "$ROUTER" \
  || { echo "✗ followTarget no longer asks for a username before ENS's catch-all"; exit 1; }
[[ $(grep -c 'NameResolve.followTarget(of:' "$FIELD") -ge 4 ]] \
  || { echo "✗ the follow field reads a draft without followTarget — a username arms, previews or follows inconsistently"; exit 1; }
grep -q 'case 404:' "$DEFI" && grep -q 'return .unreachable' "$DEFI" \
  || { echo "✗ a username lookup no longer tells nobody from unreachable (§83)"; exit 1; }
# Every read is demo-gated.
for fn in 'static func book(addresses:' 'static func syncGrantEvents(' 'static func username(for'; do
  awk -v f="$fn" 'index($0,f){on=1} on{print} on&&/^    }$/{exit}' "$DEFI" | grep -q 'DemoMode.isActive' \
    || { echo "✗ $fn reaches the network in the demo"; exit 1; }
done
# An unreachable vault read is nil, not an empty book.
grep -q 'guard reached else { return nil }' "$DEFI" \
  || { echo "✗ an unreachable World Chain read reports an empty vault"; exit 1; }
# The vault joins the holdings total, and the live state carries it.
grep -q 'Deposit(place: "WLD Vault"' Casberi/Casberi/Model/WalletComposition.swift \
  || { echo "✗ the WLD Vault no longer joins the composition"; exit 1; }
grep -q 'worldApp: live.worldApp' Casberi/Casberi/Shell/ProbeHooks.swift \
  && grep -q 'worldApp: walletLive.worldApp' Casberi/Casberi/Screens/FeedScreen.swift \
  || { echo "✗ a WalletComposition caller drops the WLD Vault book"; exit 1; }
grep -q 'WorldAppDeFi.syncGrantEvents' Casberi/Casberi/Model/WalletIngest.swift \
  || { echo "✗ the next-grant row is not synced"; exit 1; }
grep -q '"usernames.worldcoin.org"' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ the usernames host is not declared"; exit 1; }

# World Chain approvals ride Blockscout, and the chain is in the approvals table.
grep -q 'Chain(network: "worldchain-mainnet", chainId: 480,' Casberi/Casberi/Model/WalletApprovals.swift \
  && grep -q 'maxRange: 50_000_000, logsViaBlockscout: true)' Casberi/Casberi/Model/WalletApprovals.swift \
  || { echo "✗ World Chain is not in the approvals table on Blockscout — its approvals go unread (prd §797)"; exit 1; }
[[ $(grep -c 'if chain.logsViaBlockscout' Casberi/Casberi/Model/WalletApprovals.swift) -eq 2 ]] \
  || { echo "✗ a log read ignores logsViaBlockscout — World Chain would hit a 100-block RPC cap"; exit 1; }
grep -q '"worldchain-mainnet.explorer.alchemy.com"' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ World Chain's Blockscout host is not declared"; exit 1; }
# "World App wallet" rests on a verified World App username, never the module.
grep -q 'primaryNames.contains { $0.label == NameResolve.worldAppLabel }' Casberi/Casberi/Screens/AddressBookViews.swift \
  || { echo "✗ the address card's World App wallet label no longer rests on the verified username"; exit 1; }

echo "✓ world-app-selftest passed"
