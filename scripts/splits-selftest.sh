#!/bin/zsh
# Casberi Splits self-test (prd §820) — the SHIPPED pure logic behind the
# Splits seat, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/SplitsShape.swift
#
# driven off the shapes MEASURED on 2026-09-18 with a real Read key. Every
# failure here renders as a perfectly good-looking room:
#
#   · a Write or Owner key kept because its scopes were read loosely — the
#     page promises nothing here can propose a transaction
#   · the "data" wrapper missed, so every read parses to nothing and the
#     room reads as a quiet team
#   · a fractional ISO date refused, so every row lands dated NOW
#   · address-poisoning dust landed as the room's news (both transactions on
#     the measured team were exactly that)
#   · a proposal waiting on signatures drawn as done, or its stage word
#     clipped off the end of an 80-character title
#   · an unknown status guessed into done (§780b: say what we don't know)
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/SplitsShape.swift"
BRIDGE="Casberi/Casberi/Model/SplitsBridge.swift"
[[ -f "$SHAPE" && -f "$BRIDGE" ]] || { echo "✗ Splits sources not found"; exit 1; }

# ── Drift guards ────────────────────────────────────────────────────────────
# Nothing in the seat may write: a Read key could not, and the page says so.
if grep -nE 'httpMethod|"POST"|"PUT"|"DELETE"|"PATCH"|/proposals|/sign' "$BRIDGE" \
     | grep -vE '^\s*[0-9]+:\s*///' ; then
  echo "✗ SplitsBridge.swift names a write — the seat is read-only by promise"; exit 1
fi
# The connect screen keeps a key only when its scopes are Read alone.
grep -qF 'guard SplitsShape.isReadOnly(who.scopes) else { return .notReadOnly }' \
  Casberi/Casberi/Screens/SplitsScreen.swift \
  || { echo "✗ SplitsScreen no longer refuses a key that can do more than read"; exit 1; }
# A waiting proposal past the first page is re-read by id.
grep -qF 'await healWaiting(beyond: transactions, token: token, context: context)' "$BRIDGE" \
  || { echo "✗ a waiting proposal past the first page is no longer re-read — it would sit in Queue forever"; exit 1; }
# Dust is dropped at the one landing site.
grep -qF 'for tx in transactions where !SplitsShape.isDust(tx)' "$BRIDGE" \
  || { echo "✗ SplitsIngest no longer drops inbound dust before landing"; exit 1; }
# Never enrol an unwatched account in the watched wallets (Privy's rule).
if grep -n 'walletAddress\s*=' "$BRIDGE"; then
  echo "✗ SplitsBridge stamps walletAddress — it would enrol an unwatched account"; exit 1
fi
# The memo is DISPLAY copy and the hash is retrieval-only (prd §912): a memo
# on `enrichedText` is invisible on every screen, and a hash on `summary` is a
# hex block under a title.
grep -qF 'thing.summary = tx.memo.map(IngestSupport.titleLine)' "$BRIDGE" \
  || { echo "✗ a Splits memo no longer lands as display copy (summary)"; exit 1; }
grep -qF 'thing.enrichedText = tx.hash' "$BRIDGE" \
  || { echo "✗ a Splits hash left enrichedText — a pasted hash would find nothing"; exit 1; }
# The door is the chain's own transaction page, through WalletIngest's one table.
grep -qF 'thing.content = explorerURL(tx) ?? ""' "$BRIDGE" \
  || { echo "✗ a Splits row lost its explorer door (prd §912)"; exit 1; }
# The host is disclosed.
grep -qF 'hosts: ["api.splits.org"]' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ api.splits.org is not in NetworkReach"; exit 1; }
echo "splits-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }
typealias S = SplitsShape

// ── Scope ────────────────────────────────────────────────────────────────
check(S.isReadOnly(["read"]), "a Read key is kept")
check(S.isReadOnly(["Read "]), "scope words are compared trimmed and case-blind")
check(!S.isReadOnly(["read", "write"]), "Read + Write is refused")
check(!S.isReadOnly(["owner"]), "Owner is refused")
check(!S.isReadOnly([]), "a key with no scope is refused")

// ── whoami (measured shape) ─────────────────────────────────────────────
let who = S.whoami(json(#"{"data":{"orgId":"o","orgName":"Team","keyName":"k","scopes":["read"],"accountCount":1}}"#))
check(who?.scopes == ["read"] && who?.orgName == "Team" && who?.accountCount == 1, "whoami parses through the data wrapper")
check(S.whoami(json(#"{"orgName":"Team","scopes":["read"]}"#)) == nil, "an unwrapped whoami is not read as one")

// ── Accounts ────────────────────────────────────────────────────────────
let accounts = S.accounts(json(#"""
{"data":[
 {"id":"a","name":"Treasury","address":"0x731611e67dE2EA246316dF261FCfaba21a002866","type":"SPLITS_VAULT_V1","role":"x","isArchived":false,"createdAt":"2025-01-21T22:18:04.911Z"},
 {"id":"b","name":null,"address":"0x0000000000000000000000000000000000000001","type":"SPLITS_VAULT_V1","role":null,"isArchived":true,"createdAt":"2025-01-21T22:18:04Z"},
 {"id":"c","name":"Bad","address":"not-an-address","isArchived":false}
]}
"""#))
check(accounts?.count == 2, "two valid accounts, the malformed address dropped")
check(accounts?.first?.createdAt != nil, "a fractional-second ISO date parses (measured shape)")
check(accounts?.last?.createdAt != nil, "a whole-second ISO date parses too")
check(accounts?.last?.isArchived == true && accounts?.last?.name == nil, "archived and nameless survive the parse")
check(S.accountLine(accounts![0]) == "Account", "the contract type is never drawn as a word")
check(S.accountLine(accounts![1]) == "Archived account", "an archived account says so")
check(S.ref(account: "0xABC") == "splits:account:0xabc", "an account ref is lowercased")

// ── Balances ────────────────────────────────────────────────────────────
let held = S.balances(json(#"{"data":[{"address":"0x0","chainId":8453,"symbol":"ETH","decimals":18,"amount":"1000","usdValue":0.004},{"address":"0x0","chainId":1,"symbol":"USDC","decimals":6,"amount":"5","usdValue":12.5},{"address":"0x0","chainId":1,"symbol":"JUNK","decimals":18,"amount":"9"}]}"#))!
check(held.count == 3, "balances parse, an unpriced one included")
check(abs((S.total([held]) ?? 0) - 12.504) < 1e-9, "the total sums the priced balances only")
check(S.total([[S.Balance(chainId: 1, symbol: "X", usd: nil)]]) == nil, "nothing priced is no total, never zero")

// ── Transactions (the measured page) ────────────────────────────────────
let page = S.transactions(json(#"""
{"data":[
 {"id":"t1","status":"SUCCEEDED","chainId":8453,"smartAccountAddress":"0x731611e67dE2EA246316dF261FCfaba21a002866","smartAccountName":"Treasury","memo":"","properties":null,"usdDisplayValue":null,"createdAt":"2025-01-21T22:30:03.000Z","transactionTime":"2025-01-21T22:30:03.000Z","title":"Received <$0.01 (<0.001 ETH) from 0x2F60","direction":"inbound","transactionHash":"0xabc","userOpHash":null},
 {"id":"t2","status":"QUEUED","direction":"outbound","title":"Sent $4,500 (4,500 USDC) to Dana","usdDisplayValue":"$4,500.00","createdAt":"2025-02-01T10:00:00.000Z","transactionTime":null}
],"pagination":{"hasMore":true,"count":2,"cursor":"next"}}
"""#))!
check(page.rows.count == 2 && page.cursor == "next", "a page and its cursor parse")
check(S.transactions(json(#"{"data":[],"pagination":{"hasMore":false,"count":0,"cursor":"x"}}"#))?.cursor == nil,
      "no more pages means no cursor, whatever the field holds")
let t1 = page.rows[0], t2 = page.rows[1]
check(t1.memo == nil, "an empty memo is absent, not an empty string")
check(t1.at != nil, "transactionTime is the row's date")
check(t2.at != nil, "a null transactionTime falls back to createdAt")
check(t2.usd == 4500, "a display dollar string parses")

// ── Dust ────────────────────────────────────────────────────────────────
check(S.isDust(t1), "the measured under-a-cent inbound send is dust")
check(!S.isDust(t2), "an outbound transaction is never dust")
var bigIn = t1; bigIn.title = "Received $12,000 (12,000 USDC) from Acme"; bigIn.usd = nil
check(!S.isDust(bigIn), "an inbound send with no price and no <$0.01 is kept")
var pricedDust = t1; pricedDust.usd = 0.004; pricedDust.title = "Received"
check(S.isDust(pricedDust), "a priced inbound send under a cent is dust")
check(S.usd("<$0.01") == 0, "\"<$0.01\" reads as nothing")

// ── Stage and title ─────────────────────────────────────────────────────
check(S.stage("SUCCEEDED") == .done, "SUCCEEDED is done")
check(S.stage("CREATED") == .waiting && S.stage("queued") == .waiting, "CREATED and QUEUED wait on signatures")
check(S.stage("FAILED") == .notExecuted && S.stage("CANCELLED") == .notExecuted, "a failure or cancel is not executed")
check(S.stage("SOMETHING_NEW") == .unknown, "an unseen status is unknown, never guessed")
check(S.rowTitle(t2).hasPrefix("Waiting for signatures · "), "a waiting proposal LEADS with its stage")
check(S.tags(t2) == ["Transfer", S.waitingTag], "a waiting proposal carries the tag the tile's dot reads")
var odd = t2; odd.status = "SOMETHING_NEW"
check(S.rowTitle(odd) == "Sent $4,500 (4,500 USDC) to Dana" && S.tags(odd) == ["Transfer"],
      "an unknown status draws Splits' own title with no stage word")
var bare = t2; bare.title = nil; bare.status = "SUCCEEDED"
check(S.rowTitle(bare) == "Sent", "a missing title falls back to the direction")
check(S.direction(t1) == "received" && S.direction(t2) == "sent", "direction maps to the transfer vocabulary")

// ── One transaction by id, and the cursor escape ────────────────────────
let one = S.transaction(json(#"{"data":{"id":"t9","status":"SUCCEEDED","direction":"outbound","title":"Sent"}}"#))
check(one?.id == "t9" && S.stage(one!.status) == .done, "a single transaction parses through the data wrapper")
check(S.transaction(json(#"{"data":[{"id":"t9"}]}"#)) == nil, "a list is not read as one transaction")
check(S.queryValue("a+b/c=d&e") == "a%2Bb%2Fc%3Dd%26e", "a cursor's + / = & are escaped")

// ── Contacts ────────────────────────────────────────────────────────────
let contacts = S.contacts(json(#"{"data":[{"address":"0x2F60000000000000000000000000000000000000","label":"Acme"},{"address":"0x1","label":"Short"},{"address":"0x2F60000000000000000000000000000000000001","label":"  "}]}"#))
check(contacts?.map(\.label) == ["Acme"], "a contact needs a real address and a label")

// ── Unreadable ──────────────────────────────────────────────────────────
check(S.accounts(json(#"{"items":[]}"#)) == nil, "a body with no data wrapper is unreadable, not empty")
check(S.keyNames(json(#"{"data":[{"b":1,"a":2}]}"#)) == ["a", "b"], "key names are reported sorted, never values")

print(failures == 0 ? "splits-selftest: all checks ✓" : "splits-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$SHAPE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  cat "$TMP/build.log"; echo "✗ splits-selftest: compile failed"; exit 1
fi
"$TMP/run"
