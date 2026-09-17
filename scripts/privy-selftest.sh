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
#   · a session gated on the refresh cookie alone "connects" a jar that can
#     never read, and one gated on a signed-out visit's cookies closes the
#     sheet before the email code is typed
#   · a refresh body's `"deprecated"` stored as the refresh token signs the
#     person out on the next renewal, an hour later, with no explanation
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
check(PrivyHomeFeed.session([("privy-session", "t"), ("_ga", "x")]) == nil,
      "a signed-out visit's cookies are not a session")
check(PrivyHomeFeed.session([("privy-refresh-token", "r")]) == nil,
      "a refresh token alone is not a session")
check(PrivyHomeFeed.session([("privy-token", "a")]) == nil,
      "an access token alone is not a session")
let s1 = PrivyHomeFeed.session([("privy-token", "a"), ("privy-refresh-token", "r")])
check(s1?.access == "a" && s1?.refresh == "r", "both halves make a session")
let s2 = PrivyHomeFeed.session([("privy-access-token", "b"), ("privy-refresh-token", "r")])
check(s2?.access == "b", "privy-access-token stands in for privy-token")
check(PrivyHomeFeed.session([("privy-token", ""), ("privy-refresh-token", "r")]) == nil,
      "an empty cookie is not a token")

let r1 = PrivyHomeFeed.rotated(body: json(#"{"token":"A2","refresh_token":"deprecated"}"#),
                               cookies: [("privy-refresh-token", "R2")])
check(r1.access == "A2" && r1.refresh == "R2", "cookie mode: the refresh comes from the cookie")
let r2 = PrivyHomeFeed.rotated(body: json(#"{"token":"A2","refresh_token":"deprecated"}"#), cookies: [])
check(r2.refresh == nil, "\"deprecated\" is never stored as a refresh token")
let r3 = PrivyHomeFeed.rotated(body: json(#"{"token":"A3","refresh_token":"R3"}"#), cookies: [])
check(r3.access == "A3" && r3.refresh == "R3", "body mode: both come from the body")

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
    .init(id: id, name: id, logoURL: nil, createdAt: nil, lastActiveAt: lastActive,
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
check(room.fundedCount == 1 && room.funded.first?.name == "funded", "only a funded app is a head row")
check(abs(room.totalUSD - 1.37) < 0.0001, "the total sums what was read")
check(room.recentCount == 1, "recent is by last use")
check(PrivyHomeFeed.footnote(room)?.contains("1") == true, "an unread wallet is said, not hidden")

print(failures == 0 ? "privy-selftest: all checks ✓" : "privy-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$FEED" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ privy-selftest: compile failed"; exit 1; }
"$TMP/run"
