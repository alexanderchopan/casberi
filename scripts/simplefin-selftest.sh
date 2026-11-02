#!/bin/zsh
# Casberi SimpleFIN self-test (prd §1663) — the SHIPPED pure logic behind the
# SimpleFIN seat, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/SimpleFINShape.swift
#
# driven off the shapes MEASURED on 2026-11-02 with the bridge's own demo
# token. Every failure here renders as a perfectly good-looking room:
#
#   · a pasted token naming a host off simplefin.org followed, carrying the
#     person's bank credentials to it
#   · the Access URL's credentials left IN the address, where every log,
#     ledger and error string would carry them
#   · a read with no start-date, which holds only what posted since yesterday
#   · one transaction id shared by two accounts landed once (the demo has it)
#   · a transfer or card payment counted as spending — a card's charge twice
#   · a read past the bridge's ~24 a day, which turns the token off
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/SimpleFINShape.swift"
BRIDGE="Casberi/Casberi/Model/SimpleFINBridge.swift"
[[ -f "$SHAPE" && -f "$BRIDGE" ]] || { echo "✗ SimpleFIN sources not found"; exit 1; }

# ── Drift guards ────────────────────────────────────────────────────────────
# The claim is the ONE post, and it goes through the claim function alone.
if grep -nE 'httpMethod|postJSON|requestJSON' "$BRIDGE" | grep -vE '^\s*[0-9]+:\s*///'; then
  echo "✗ SimpleFINBridge.swift makes a request other than the claim and the read"; exit 1
fi
[[ $(grep -c 'IngestSupport.postText' "$BRIDGE") == 1 ]] \
  || { echo "✗ SimpleFIN posts from more than one place — the claim is its only POST"; exit 1; }
# Every read goes through the rate gate.
grep -qF 'guard SimpleFINShape.mayRead(lastAsked: SimpleFINState.lastAsked, now: .now, force: force)' "$BRIDGE" \
  || { echo "✗ SimpleFINIngest no longer waits out the bridge's rate"; exit 1; }
grep -qF 'SimpleFINState.lastAsked = .now' "$BRIDGE" \
  || { echo "✗ the rate clock is never stamped — every pass would read"; exit 1; }
# A pending row is never landed (its id may change when it posts).
grep -qF 'for t in account.transactions where !t.pending' "$BRIDGE" \
  || { echo "✗ SimpleFIN lands pending rows — a posted twin would count twice"; exit 1; }
# The Access URL never syncs to another device's quota.
grep -qE 'localTokenBridges: Set<TokenBridge> = \[.*\.simplefin' Casberi/Casberi/Model/TokenVault.swift \
  || { echo "✗ the Access URL syncs through iCloud — two devices would spend one quota"; exit 1; }
# Spending and Subscriptions read shop charges only.
grep -qF 'guard SimpleFINShape.isShopCharge(tags: thing.tags),' Casberi/Casberi/Model/SpendingSource.swift \
  || { echo "✗ Spending counts SimpleFIN rows that name no shop"; exit 1; }
grep -qF 'guard SimpleFINShape.isShopCharge(tags: thing.tags) else { return nil }' Casberi/Casberi/Model/SubscriptionsSource.swift \
  || { echo "✗ Subscriptions reads SimpleFIN rows that name no shop"; exit 1; }
# The host family is disclosed, and the credential arg is redacted.
grep -qF 'hosts: ["simplefin.org", "beta-bridge.simplefin.org", "bridge.simplefin.org"]' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ simplefin.org is not in NetworkReach"; exit 1; }
grep -qF '"-simplefinConnect",' Casberi/Casberi/Shell/ProbeHooks.swift \
  || { echo "✗ -simplefinConnect is not redacted from probeArgs"; exit 1; }
# A bank's icon under 32px is refused (Bank of America's 16px favicon smears).
grep -qF 'guard let best, min(best.width, best.height) >= minimumSide else { return nil }' "$BRIDGE" \
  || { echo "✗ a bank icon of any size is kept — a 16px favicon would smear"; exit 1; }
# A zero amount never lands.
grep -qF 'guard let posted = t.posted, let amount = t.amount, amount != 0,' "$BRIDGE" \
  || { echo "✗ a zero amount lands as a \$0.00 row"; exit 1; }
echo "simplefin-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }
func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
typealias S = SimpleFINShape

// ── The Setup Token (measured: the developer page's demo token) ──────────
let demo = "aHR0cHM6Ly9iZXRhLWJyaWRnZS5zaW1wbGVmaW4ub3JnL3NpbXBsZWZpbi9jbGFpbS9ERU1PLXYyLTRBRjVCOEE4MzEwMkJFQzMwOTMz"
check(S.claimURL(fromSetupToken: demo)?.absoluteString
      == "https://beta-bridge.simplefin.org/simplefin/claim/DEMO-v2-4AF5B8A83102BEC30933",
      "the measured demo token decodes to its claim URL")
check(S.claimURL(fromSetupToken: "  \(demo)\n") != nil, "whitespace around a pasted token is ignored")
let padded = b64("https://bridge.simplefin.org/simplefin/claim/demo")
check(padded.hasSuffix("=") && S.claimURL(fromSetupToken: padded) != nil, "a padded token decodes")
check(S.claimURL(fromSetupToken: String(padded.drop(while: { _ in false }).filter { $0 != "=" })) != nil,
      "an unpadded token decodes")
let urlSafe = b64("https://bridge.simplefin.org/simplefin/claim/a??>").replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
check(S.claimURL(fromSetupToken: urlSafe) != nil, "a URL-safe token decodes")
check(S.claimURL(fromSetupToken: b64("https://evil.example/simplefin/claim/x")) == nil,
      "a token naming another host is refused")
check(S.claimURL(fromSetupToken: b64("https://simplefin.org.evil.example/claim/x")) == nil,
      "a look-alike host is refused")
check(S.claimURL(fromSetupToken: b64("http://bridge.simplefin.org/simplefin/claim/x")) == nil,
      "a plain-http token is refused")
check(S.claimURL(fromSetupToken: "not base64 at all!") == nil, "garbage is not a token")
check(S.claimURL(fromSetupToken: "https://user:pass@bridge.simplefin.org/simplefin") == nil,
      "an Access URL is not read as a token")

// ── The Access URL (measured shape) ──────────────────────────────────────
let a = S.access("https://AB12:secretpw@beta-bridge.simplefin.org/simplefin/")
check(a?.base == "https://beta-bridge.simplefin.org/simplefin", "the credentials come OUT of the address")
check(a?.authorization == "Basic " + b64("AB12:secretpw"), "and ride a Basic header instead")
check(!(a?.base.contains("secretpw") ?? true), "no password survives in the base")
check(S.access("https://beta-bridge.simplefin.org/simplefin") == nil, "an address with no credentials is no access")
check(S.access("https://u:p@example.com/simplefin") == nil, "an Access URL off simplefin.org is refused")
check(S.isAccessURL("https://u:p@bridge.simplefin.org/simplefin"), "a pasted Access URL is recognised as one")

// ── The window and the rate ──────────────────────────────────────────────
let now = Date(timeIntervalSince1970: 1_800_000_000)
check(S.startDate(cursor: nil, now: now) == 1_800_000_000 - 44 * 86_400,
      "first sight reaches back 44 days, inside the bridge's 45")
let recent = now.addingTimeInterval(-2 * 86_400)
check(S.startDate(cursor: recent, now: now) == Int(recent.timeIntervalSince1970) - 5 * 86_400,
      "a later read overlaps its cursor by five days")
let stale = now.addingTimeInterval(-200 * 86_400)
check(S.startDate(cursor: stale, now: now) == 1_800_000_000 - 44 * 86_400,
      "an old cursor never reaches past the window")
check(S.mayRead(lastAsked: nil, now: now), "a never-asked bridge may be read")
check(!S.mayRead(lastAsked: now.addingTimeInterval(-600), now: now), "ten minutes after a read, no read")
check(S.mayRead(lastAsked: now.addingTimeInterval(-600), now: now, force: true), "the forced first read goes")
check(S.mayRead(lastAsked: now.addingTimeInterval(-3_600), now: now), "an hour after, a read")
check(24 * 3_600 / S.readGap <= 24, "the gap holds a day to the bridge's 24 reads")

// ── The account set (measured: the demo's own payload) ───────────────────
let set = S.accountSet(json(#"""
{"errlist":[{"code":"gen.api","msg":"Requested date range exceeds <b>recommended</b> range\nof 45 days."}],
 "x-api-message":["Provide a 'start-date' parameter to receive transactions prior to yesterday"],
 "connections":[{"conn_id":"CON-SIMPLEFIN-DEMO","name":"SimpleFIN Demo","org_id":"simplefin.demoorg","org_name":"SimpleFIN Bridge","org_url":"https://beta-bridge.simplefin.org","sfin_url":"https://beta-bridge.simplefin.org/simplefin"},
                {"conn_id":"C2","name":"Chase","org_id":"chase","org_url":"chase.com","sfin_url":"x"}],
 "accounts":[
  {"id":"Demo Savings","name":"SimpleFIN Savings","currency":"USD","balance":"115245.51","available-balance":"115245.51","balance-date":1793664000,
   "transactions":[{"id":"1793606400","posted":1793606400,"amount":"-10.00","description":"Fishing bait","payee":"John's Fishin Shack","memo":"JOHNS FISHIN SHACK BAIT","transacted_at":1793606400,"mcc":"5812"}],
   "holdings":[],"conn_id":"CON-SIMPLEFIN-DEMO"},
  {"id":"Demo Checking","name":"SimpleFIN Checking","currency":"USD","balance":"25767.79","balance-date":1793664000,
   "transactions":[{"id":"1793606400","posted":1793606400,"amount":"-13.31","description":"Fishing bait","payee":"John's Fishin Shack","memo":"JOHNS FISHIN SHACK BAIT","mcc":"5812"},
                   {"id":"t2","posted":1793700000,"amount":"2500.00","description":"PAYROLL ACME"},
                   {"id":"t3","posted":1793700001,"amount":"-812.00","description":"CHASE CREDIT CRD AUTOPAY"},
                   {"id":"t4","posted":1793700002,"amount":"4.10","description":"Coffee refund","payee":"Blue Bottle","mcc":"5814"},
                   {"id":"t5","posted":0,"amount":"-3.00","description":"Pending thing","pending":true}],
   "conn_id":"CON-SIMPLEFIN-DEMO"},
  {"id":"Card","name":"Sapphire","currency":"usd","balance":"-812.40","conn_id":"C2","transactions":[]},
  {"id":"Miles","name":"Airline Miles","currency":"https://www.example.com/flight-miles","balance":"1200","transactions":[]},
  {"name":"no id"}
 ]}
"""#))!
check(set.accounts.count == 4, "four accounts, the one with no id dropped")
check(set.accounts[0].connID == "CON-SIMPLEFIN-DEMO", "an account names its connection")
check(set.connections.map(\.name) == ["SimpleFIN Bridge", "Chase"], "an institution goes by org_name, else name")
check(set.connections[1].url == "https://chase.com", "a bare org_url domain becomes an https door")
check(set.messages == ["Requested date range exceeds recommended range of 45 days."],
      "errlist is shown cleaned: no markup, one line")
let savings = set.accounts[0], checking = set.accounts[1]
check(savings.balance == 115245.51 && savings.balanceDate != nil, "a string balance and an epoch date parse")
check(set.accounts[2].currency == "USD" && set.accounts[2].balance == -812.40,
      "a lowercase code is uppercased; a card's balance is negative")
check(set.accounts[3].currency == nil, "a custom currency (a URL) is no money")
check(S.ref(conn: savings.connID, account: savings.id, transaction: savings.transactions[0].id)
      != S.ref(conn: checking.connID, account: checking.id, transaction: checking.transactions[0].id),
      "one transaction id in two accounts is two refs (measured)")
check(S.connID(fromRef: S.ref(conn: "C:2", account: "a:b", transaction: "t")) == "C:2",
      "a ref names its bank, a colon in an id included")
check(S.ref(conn: "C", account: "a:b", transaction: "c") != S.ref(conn: "C", account: "a", transaction: "b:c"),
      "a colon in an id cannot shift the parts")
check(S.connID(fromRef: S.ref(conn: nil, account: "a", transaction: "t")) == nil, "no bank is no bank, never \"\"")
check(S.connID(fromHolder: S.holderID(conn: "CON-1", account: "Demo Savings")) == "CON-1",
      "a balance's holder names its bank")
check(S.holderID(conn: "c", account: "a").hasPrefix("cash:simplefin:"), "a balance is cash, as WalletPortfolio.isVenue reads it")
check(S.connID(fromHolder: "cash:wise") == nil, "another app's cash names no bank")

// ── Bank names and marks ─────────────────────────────────────────────────
check(S.accountLabel(name: "Total Checking", institution: "Chase") == "Chase · Total Checking",
      "an account goes by its bank, then its name")
check(S.accountLabel(name: "SimpleFIN Savings", institution: "SimpleFIN Bridge") == "SimpleFIN Savings",
      "a name that already says the bank is not said twice")
check(S.accountLabel(name: "Savings", institution: nil) == "Savings", "no bank, the name alone")
check(S.accountLabel(name: "First Checking", institution: "First Republic") == "First Republic · First Checking",
      "a generic first word (\"First\") does not stand for the bank")
check(S.iconCandidates(orgURL: "https://chase.com").map(\.absoluteString)
      == ["https://chase.com/apple-touch-icon.png", "https://chase.com/apple-touch-icon-precomposed.png",
          "https://chase.com/favicon.ico"], "a bank's icon is asked of its own site, largest first")
check(S.iconCandidates(orgURL: "https://chase.com/some/path?x=1").first?.absoluteString
      == "https://chase.com/apple-touch-icon.png", "never a path from the payload")
check(S.iconCandidates(orgURL: "http://chase.com").isEmpty, "never over plain http")
check(S.iconCandidates(orgURL: nil).isEmpty && S.iconCandidates(orgURL: "https://localhost").isEmpty,
      "no site, or no real host, is no icon")
let txns = checking.transactions
check(txns.count == 5, "every transaction with an id parses")
check(txns[4].pending && txns[4].posted == nil, "posted 0 is pending, never dated 1970")
check(!txns[0].pending, "a posted row is not pending")

// ── Kind, title, tags ────────────────────────────────────────────────────
check(S.kind(txns[0]) == .purchase && S.tags(txns[0]) == ["Purchase"], "a shop's charge is a Purchase")
check(S.kind(txns[3]) == .refund && S.tags(txns[3]) == ["Refund"], "a shop's credit is a Refund")
check(S.kind(txns[2]) == .paid && S.tags(txns[2]).isEmpty, "a card payment off checking names no shop")
check(S.kind(txns[1]) == .received && S.tags(txns[1]) == ["Deposit"], "a paycheck is a Deposit")
check(S.isShopCharge(tags: S.tags(txns[0])) && S.isShopCharge(tags: S.tags(txns[3])),
      "Spending reads purchases and refunds")
check(!S.isShopCharge(tags: S.tags(txns[1])) && !S.isShopCharge(tags: S.tags(txns[2])),
      "Spending never reads a deposit or a payment between accounts")
check(S.rowTitle(txns[0], money: "$13.31") == "John's Fishin Shack · $13.31", "a purchase leads with the shop")
check(S.rowTitle(txns[3], money: "$4.10").hasPrefix("Refunded · "), "a refund LEADS with being one")
check(S.rowTitle(txns[1], money: "$2,500.00") == "Received · PAYROLL ACME · $2,500.00",
      "money in leads with Received, named by its description when there is no payee")
check(S.statementLine(txns[0]) == "JOHNS FISHIN SHACK BAIT", "the memo is the statement line")
check(S.statementLine(txns[1]) == nil, "a line that repeats the title says nothing")

// ── Unreadable ───────────────────────────────────────────────────────────
check(S.accountSet(json(#"{"errlist":[]}"#)) == nil, "a body with no accounts is unreadable, not empty")
check(S.accountSet(json(#"{"accounts":[],"errors":["Chase needs you to sign in again"]}"#))?.messages
      == ["Chase needs you to sign in again"], "v1's errors strings are shown too")
check(S.keyNames(["b": 1, "a": 2]) == ["a", "b"], "key names are reported sorted, never values")

print(failures == 0 ? "simplefin-selftest: all checks ✓" : "simplefin-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$SHAPE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  cat "$TMP/build.log"; echo "✗ simplefin-selftest: compile failed"; exit 1
fi
"$TMP/run"
