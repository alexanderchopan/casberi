#!/bin/zsh
# Casberi Privy self-test (prd §803c) — the pure half of the Privy Home seat,
# compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/PrivyHomeFeed.swift
#
# MEASURED, 2026-09-17: the response's top shape (`user.apps[]`, and each
# app's keys) and the request's needs (`Origin`, the app id, a bearer). NOT
# measured: the inner shape of `accounts`, which was past the capture's depth,
# so the fixtures below pin THIS READER'S tolerance, not Privy's schema.
# `-privyProbe` prints the account keys on the first real sync.
#
# Every failure here is silent on a device:
#
#   · an email account read as a wallet puts a person's address in a row
#     titled like an app, and asks Zerion for the holdings of an email
#   · a session sent as a bearer alone, or as one token under both cookie
#     names, is refused (MEASURED) — and the page then says "signed out" over
#     a sign-in that worked
#   · a session gated on a signed-out visit's cookies closes the sheet before
#     the email code is typed
#   · a refresh body's `"deprecated"` stored as the refresh token signs the
#     person out on the next renewal, with no explanation
#   · a 200 that is not `user.apps` read as "no apps" says "up to date" over
#     a body nobody understood (§83)
#   · a millisecond timestamp read as seconds dates every app in the year
#     57000, above everything in the feed, forever
#   · re-reading every empty wallet each pass spends the shared Zerion
#     allowance (§216) on 100+ wallets holding nothing
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FEED="Casberi/Casberi/Model/PrivyHomeFeed.swift"
LIVE="Casberi/Casberi/Model/PrivyHomeLive.swift"
for f in "$FEED" "$LIVE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# Only a refusal clears the session (§711).
grep -qF 'if case .refused = failure { PrivyHomeAuth.clear() }' "$LIVE" \
  || { echo "✗ PrivyHomeLive no longer clears the session on a refusal alone"; exit 1; }
# The rotated session must never land in the shared cookie store.
grep -qF 'request.httpShouldHandleCookies = false' "$LIVE" \
  || { echo "✗ the Privy session refresh lets URLSession store the rotated cookies"; exit 1; }
# Read-only: nothing in the live half may call anything but me and sessions.
if grep -nE 'https://[^"]*privy[^"]*' "$LIVE" | grep -vE 'meURL|sessionsURL' | grep -q .; then
  echo "✗ PrivyHomeLive calls a Privy URL other than me and sessions"; exit 1
fi
# NotifySweep spells the ref prefix literally (it compiles against stubs).
grep -qF 'if ref.hasPrefix("privy:app:") { return .appWalletMade }' Casberi/Casberi/Model/NotifySweep.swift \
  || { echo "✗ NotifySweep no longer classifies a Privy app row"; exit 1; }
grep -qF 'static let refPrefix = "privy:app:"' "$FEED" \
  || { echo "✗ PrivyHomeFeed.refPrefix drifted from NotifySweep's literal"; exit 1; }
echo "privy-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

let evm = "0xF9c4aE8b1d2C3e4F5a6B7c8D9e0F1a2B3c4Df152"
let evm2 = "0x1111111111111111111111111111111111111111"
let sol = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"

// ── The session ──────────────────────────────────────────────────────────
// Measured 2026-09-17: a bearer alone is "Missing auth token", and one token
// sent under both cookie names is "Invalid auth token". The session is every
// cookie the API host receives, each with its own value.
let jar: [(name: String, value: String, domain: String)] = [
    ("privy-token", "T", ".home.privy.io"),
    ("privy-access-token", "A", ".privy.home.privy.io"),
    ("privy-refresh-token", "R", ".privy.home.privy.io"),
    ("privy-session", "S", ".home.privy.io"),
    ("cf_clearance", "C", ".privy.io"),
    ("privy-other", "X", ".auth.privy.io"),
    ("evil", "E", "privy.home.privy.io.evil"),
    ("empty", "", ".privy.io"),
    ("hubspotutk", "H", ".privy.io"),
    ("_ga", "G", ".privy.io"),
]
let api = PrivyHomeFeed.apiCookies(jar)
check(api["privy-token"] == "T" && api["privy-access-token"] == "A",
      "the two access tokens keep their OWN values")
check(api["privy-session"] == "S" && api["cf_clearance"] == "C", "parent-domain cookies ride along, as a browser sends them")
check(api["privy-other"] == nil, "a sibling subdomain's cookie is not sent")
check(api["hubspotutk"] == nil && api["_ga"] == nil, "analytics trackers are never kept or sent")
check(api["evil"] == nil, "a lookalike domain is not a domain match")
check(api["empty"] == nil, "an empty cookie is not kept")
check(PrivyHomeFeed.isSession(api), "access + refresh is a session")
check(!PrivyHomeFeed.isSession(["privy-session": "S", "_ga": "x"]), "a signed-out visit's cookies are not a session")
check(!PrivyHomeFeed.isSession(["privy-refresh-token": "R"]), "a refresh token alone is not a session")
check(!PrivyHomeFeed.isSession(["privy-token": "T"]), "an access token alone is not a session")
check(PrivyHomeFeed.bearer(api) == "T", "the bearer is privy-token")
check(PrivyHomeFeed.cookieHeader(["b": "2", "a": "1"]) == "a=1; b=2", "the Cookie header carries every cookie")

let r1 = PrivyHomeFeed.rotated(api, body: json(#"{"token":"T2","refresh_token":"deprecated"}"#),
                               setCookies: [("privy-access-token", "A2"), ("privy-refresh-token", "R2")])
check(r1["privy-access-token"] == "A2" && r1["privy-refresh-token"] == "R2", "Set-Cookie rotates by name")
check(r1["privy-token"] == "T", "a body token does not overwrite when a cookie carried access")
let r2 = PrivyHomeFeed.rotated(["privy-refresh-token": "R"], body: json(#"{"token":"T3","refresh_token":"deprecated"}"#), setCookies: [])
check(r2["privy-refresh-token"] == "R", "\"deprecated\" is never stored as a refresh token")
check(r2["privy-token"] == "T3", "body mode: the token comes from the body")
let r3 = PrivyHomeFeed.rotated(api, body: nil, setCookies: [("privy-session", "")])
check(r3["privy-session"] == nil, "a cleared cookie is dropped")

check(PrivyHomeFeed.classify(status: 200) == nil, "200 is not a failure")
check(PrivyHomeFeed.classify(status: 401) == .refused(401), "401 is a refusal")
check(PrivyHomeFeed.classify(status: 429) == .throttled, "429 is a throttle, not a refusal")
check(PrivyHomeFeed.classify(status: 0) == .unreachable, "no response is unreachable")
check(PrivyHomeFeed.headers["Origin"] == "https://home.privy.io", "every read carries the measured Origin")

// ── The apps ─────────────────────────────────────────────────────────────
check(PrivyHomeFeed.apps(json(#"{"error":"x"}"#)) == nil, "a body without user.apps is drifted, not empty")
check(PrivyHomeFeed.apps(json(#"{"user":{"id":"u","apps":[]}}"#))?.isEmpty == true,
      "an empty apps list is a real empty")

let body = """
{"user":{"id":"u","apps":[
 {"id":"a1","name":"Wildcard","logo_url":"https://x/y.png","created_at":1714089600,"last_active_at":1719705600000,
  "accounts":[{"type":"email","address":"person@example.com"},
              {"type":"wallet","address":"\(evm)","chain_type":"ethereum"}]},
 {"id":"a2","name":"  ","created_at":"2025-01-02T03:04:05.000Z",
  "accounts":[{"type":"wallet","address":"\(sol)","chain_type":"solana"},
              {"type":"smart_wallet","address":"\(evm2)"},
              {"type":"wallet","address":"\(evm2.uppercased().replacingOccurrences(of: "0X", with: "0x"))"}]},
 {"id":"a3","name":"Only email","accounts":[{"type":"email","address":"p@q.com"}]},
 {"id":"a1","name":"Duplicate","accounts":[{"type":"wallet","address":"\(evm)"}]}
]}}
"""
let apps = PrivyHomeFeed.apps(json(body)) ?? []
check(apps.count == 2, "an app with no wallet and a repeated id are dropped")
check(apps.first?.wallets.map(\.address) == [evm], "an email account is never a wallet")
check(apps.first?.wallets.first?.chain == "ethereum", "chain_type is kept")
check(apps.first?.createdAt == Date(timeIntervalSince1970: 1714089600), "unix seconds read as seconds")
check(apps.first?.lastActiveAt == Date(timeIntervalSince1970: 1719705600), "milliseconds read as milliseconds")
check(apps.last?.createdAt != nil, "an ISO date reads")
check(apps.last?.wallets.count == 2, "the same EVM address in two cases is one wallet")
check(apps.last?.name == PrivyHomeFeed.shortAddress(sol), "a blank name falls back to the wallet, never empty")
check(PrivyHomeFeed.line(apps.last!) == "\(PrivyHomeFeed.shortAddress(sol)) +1", "two wallets say so on the line")
check(PrivyHomeFeed.ref(apps.first!) == "privy:app:a1", "the ref is the app id")
check(!PrivyHomeFeed.isWalletAddress("person@example.com"), "an email is not address-shaped")
check(!PrivyHomeFeed.isWalletAddress("0x123"), "a short hex is not an address")

// ── What to read, and what the room says ─────────────────────────────────
let now = Date(timeIntervalSince1970: 1790000000)
func app(_ id: String, _ address: String, lastActive: Date? = nil) -> PrivyHomeFeed.App {
    .init(id: id, name: id, logoURL: nil, origin: nil, createdAt: nil, lastActiveAt: lastActive,
          wallets: [.init(address: address, chain: nil)])
}
func hex(_ n: Int) -> String { "0x" + String(repeating: String(n % 10), count: 40) }
let fundedApp = app("funded", hex(1))
let emptyOld = app("emptyOld", hex(2))
let emptyRecent = app("emptyRecent", hex(3), lastActive: now.addingTimeInterval(-86_400))
let neverRead = app("never", hex(4))
var balances: [String: PrivyHomeFeed.Balance] = [
    PrivyHomeFeed.key(hex(1)): .init(usd: 1.37, bySymbol: ["ETH": 1.37], readAt: now.addingTimeInterval(-7 * 3600)),
    PrivyHomeFeed.key(hex(2)): .init(usd: 0, bySymbol: [:], readAt: now.addingTimeInterval(-86_400)),
    PrivyHomeFeed.key(hex(3)): .init(usd: 0, bySymbol: [:], readAt: now.addingTimeInterval(-7 * 3600)),
]
let targets = PrivyHomeFeed.toRead([fundedApp, emptyOld, emptyRecent, neverRead], balances: balances, now: now)
check(targets.contains(hex(1)), "a funded wallet past six hours is re-read")
check(targets.contains(hex(3)), "a recently used empty wallet past six hours is re-read")
check(targets.contains(hex(4)), "a wallet never read is read")
check(!targets.contains(hex(2)), "an old empty wallet read yesterday is NOT re-read (weekly)")
balances[PrivyHomeFeed.key(hex(2))]?.readAt = now.addingTimeInterval(-8 * 86_400)
check(PrivyHomeFeed.toRead([emptyOld], balances: balances, now: now) == [hex(2)],
      "…until a week has passed")
let many = (0..<100).map { app("m\($0)", "0x" + String(format: "%040d", $0)) }
check(PrivyHomeFeed.toRead(many, balances: [:], now: now).count == PrivyHomeFeed.readsPerPass,
      "a first sync spreads its reads over passes")

let room = PrivyHomeFeed.room([fundedApp, emptyOld, emptyRecent, neverRead], balances: balances, now: now)
check(room.appCount == 4 && room.readCount == 3, "the room counts what has been read")
check(room.fundedCount == 1 && room.funded.first?.name == "funded", "a funded app leads")
check(room.recent.map(\.name) == ["emptyRecent"], "an empty app used lately is listed after the funded")
check(room.quietCount == 2, "everything else is one count, never a row each")
check(abs(room.totalUSD - 1.37) < 0.0001, "the total sums what was read")
check(room.recentCount == 1, "recent is by last use")
check(PrivyHomeFeed.footnote(room)?.contains("1 not read yet") == true, "an unread wallet is said, not hidden")
check(PrivyHomeFeed.lastUsed(now.addingTimeInterval(-3 * 86_400), now: now) == "Used 3 days ago", "a row says when the app was last used")

// ── What the feed shows, and where the doors go ─────────────────────────
let apps4 = [fundedApp, emptyOld, emptyRecent, neverRead]
let shownDefault = PrivyHomeFeed.shown(apps4, balances: balances, hidden: [], showEmpty: false, now: now)
check(shownDefault == ["privy:app:funded", "privy:app:emptyRecent", "privy:app:never"],
      "by default an empty app nobody uses is not a row; an unread one still is")
check(PrivyHomeFeed.shown(apps4, balances: balances, hidden: [], showEmpty: true, now: now).count == 4,
      "Show empty apps draws them all")
check(!PrivyHomeFeed.shown(apps4, balances: balances, hidden: ["privy:app:funded"], showEmpty: true, now: now)
        .contains("privy:app:funded"), "a hidden app is never drawn, funded or not")
check(PrivyHomeFeed.webOrigin("https://zora.co/path") == "https://zora.co", "an origin keeps only its host")
check(PrivyHomeFeed.webOrigin("zora.co") == "https://zora.co", "a bare host becomes https")
check(PrivyHomeFeed.webOrigin("http://zora.co") == nil, "plain http is not a door")
check(PrivyHomeFeed.webOrigin("localhost") == nil, "a host with no dot is not a door")
check(PrivyHomeFeed.explorerURL(.init(address: evm, chain: nil)).hasPrefix("https://blockscan.com/address/"),
      "an EVM wallet opens Blockscan's cross-chain page")
check(PrivyHomeFeed.explorerURL(.init(address: sol, chain: "solana")).hasPrefix("https://solscan.io/account/"),
      "a Solana wallet opens Solscan")

// ── Activity and sections ────────────────────────────────────────────────
let txr = PrivyHomeFeed.txRef(appID: "a1", hash: "0xABC", received: true, symbol: "ETH")
check(txr == "privy:tx:a1:0xabc:in:eth", "a leg's ref names its app, hash, direction and symbol")
check(txr.hasPrefix(PrivyHomeFeed.txPrefix(appID: "a1")), "an app finds its own activity by prefix")
check(!txr.hasPrefix(PrivyHomeFeed.refPrefix), "an activity row is never read as an app row")
let solApp = PrivyHomeFeed.App(id: "sol", name: "sol", logoURL: nil, origin: nil, createdAt: nil,
                               lastActiveAt: now, wallets: [.init(address: sol, chain: "solana")])
let targetsA = PrivyHomeFeed.activityTargets([fundedApp, emptyOld, emptyRecent, solApp],
                                             balances: balances, readAt: [:], now: now)
check(targetsA.map(\.address) == [hex(1), hex(3)], "activity reads funded then recent EVM wallets, never an empty unused one or Solana")
let targetsB = PrivyHomeFeed.activityTargets([fundedApp], balances: balances,
                                             readAt: [PrivyHomeFeed.key(hex(1)): now.addingTimeInterval(-3600)], now: now)
check(targetsB.isEmpty, "a wallet read an hour ago is not re-read")
check(PrivyHomeFeed.txTitle(received: true, value: 0.00213456, symbol: "ETH") == "Received 0.002135 ETH",
      "an amount keeps four significant digits")
check(PrivyHomeFeed.Section.present(hasActivity: false) == [.home, .apps], "no Activity tile over nothing")
check(PrivyHomeFeed.Section.apps.allows(ref: "privy:app:x") && !PrivyHomeFeed.Section.apps.allows(ref: txr),
      "Apps holds app rows only")
check(PrivyHomeFeed.Section.activity.allows(ref: txr) && !PrivyHomeFeed.Section.activity.allows(ref: "privy:app:x"),
      "Activity holds what moved only")

print(failures == 0 ? "privy-selftest: all checks ✓" : "privy-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$FEED" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ privy-selftest: compile failed"; exit 1; }
"$TMP/run"
