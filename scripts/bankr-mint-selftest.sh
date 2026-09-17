#!/bin/zsh
# Casberi Bankr key-mint self-test (prd §800) — the pure half of "sign in and
# the key is made for you", compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/BankrKeyMint.swift
#
# The key this seat makes can reach a wallet's agent, so what it ASKS for and
# what it will STORE are the whole check:
#
#   · the request body carries exactly the six fields bankr.bot's own page
#     sends (measured, §777's capture), with Agent API and read-only on and
#     everything else off
#   · a key that comes back wider than asked — read-only off, or wallet or
#     token-launch on, or a flag simply ABSENT — is not a key to store
#   · a 401/403 is a session, not a failure to report
#   · a lookalike cookie domain is not a Bankr session
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MINT="Casberi/Casberi/Model/BankrKeyMint.swift"
SHEET="Casberi/Casberi/Screens/BankrSignInSheet.swift"
for f in "$MINT" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# A Bankr session is a wallet's session: nothing of it outlives the sheet.
grep -qF '.nonPersistent()' "$SHEET" \
  || { echo "✗ the Bankr sign-in's jar is not non-persistent — a wallet session would stay in the app"; exit 1; }
# The sheet reads cookie NAMES. A value read is the thing this must never do.
if grep -vE '^[[:space:]]*//' "$SHEET" | grep -qE '\.value\b'; then
  echo "✗ the Bankr sign-in reads a cookie VALUE"; exit 1
fi
# What is stored is decided by `outcome`, never by a raw body.
grep -qF 'BankrKeyMint.outcome(status:' "$SHEET" \
  || { echo "✗ the sheet no longer reads the response through BankrKeyMint.outcome"; exit 1; }
if grep -vE '^[[:space:]]*//' "$SHEET" | grep -qiE 'NSLog|print\('; then
  echo "✗ the Bankr sign-in logs — a key must never reach a log"; exit 1
fi
echo "bankr-mint-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

// ── What is asked for ────────────────────────────────────────────────────
let body = BankrKeyMint.requestBody(name: "Casberi 2026-09-16")
let sent = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
check(Set(sent.keys) == ["name", "agentApiEnabled", "readOnly", "walletApiEnabled",
                         "tokenLaunchApiEnabled", "llmGatewayEnabled"],
      "the body is exactly the six fields bankr.bot's own page sends")
check(sent["agentApiEnabled"] as? Bool == true && sent["readOnly"] as? Bool == true,
      "Agent API on, read-only on")
check(sent["walletApiEnabled"] as? Bool == false && sent["tokenLaunchApiEnabled"] as? Bool == false
      && sent["llmGatewayEnabled"] as? Bool == false, "everything else off")
var noon = DateComponents(); noon.year = 2026; noon.month = 9; noon.day = 16; noon.hour = 12
let date = Calendar(identifier: .gregorian).date(from: noon)!
check(BankrKeyMint.keyName(on: date) == "Casberi 2026-09-16", "the key is named so it can be found on bankr.bot")
check(BankrKeyMint.startURL.absoluteString == "https://bankr.bot/terminal/chat",
      "the sheet opens straight on the sign-in, not a home page with two buttons")
check(BankrKeyMint.isBankrPage(BankrKeyMint.startURL), "and the key call can run from where it starts")

// ── What is stored ───────────────────────────────────────────────────────
func reply(_ fields: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
}
let good: [String: Any] = ["apiKey": "bk_test", "success": true, "readOnly": true,
                           "agentApiEnabled": true, "walletApiEnabled": false,
                           "tokenLaunchApiEnabled": false, "llmGatewayEnabled": false]
check(BankrKeyMint.outcome(status: 201, body: reply(good)) == .minted(key: "bk_test"), "a key issued as asked is stored")
var wide = good; wide["readOnly"] = false
check(BankrKeyMint.outcome(status: 201, body: reply(wide)) == .tooWide, "a key that can write is NOT stored")
var wallet = good; wallet["walletApiEnabled"] = true
check(BankrKeyMint.outcome(status: 201, body: reply(wallet)) == .tooWide, "a key with the wallet API on is not stored")
var silent = good; silent.removeValue(forKey: "readOnly")
check(BankrKeyMint.outcome(status: 201, body: reply(silent)) == .tooWide, "an ABSENT read-only flag is not a yes")
var noAgent = good; noAgent["agentApiEnabled"] = false
check(BankrKeyMint.outcome(status: 201, body: reply(noAgent)) == .tooWide, "a key without the Agent API is not the one asked for")
var blank = good; blank["apiKey"] = "  "
check(BankrKeyMint.outcome(status: 201, body: reply(blank)) == .failed(status: 201), "a blank key is not a key")
check(BankrKeyMint.outcome(status: 401, body: "") == .signedOut, "a 401 is the session, not a failure")
check(BankrKeyMint.outcome(status: 403, body: "{}") == .signedOut, "and so is a 403")
check(BankrKeyMint.outcome(status: 500, body: "{}") == .failed(status: 500), "a 500 is a failure with its status")
check(BankrKeyMint.outcome(status: 0, body: "") == .failed(status: 0), "no answer at all is a failure")
check(BankrKeyMint.line(for: .minted(key: "x")) == nil, "a made key has no failure sentence")
check(BankrKeyMint.line(for: .tooWide)?.contains("bankr.bot") == true, "a key too wide says where to remove it")
check(!(BankrKeyMint.line(for: .failed(status: 0)) ?? "").isEmpty, "every failure has a sentence")

// ── Signed in? ───────────────────────────────────────────────────────────
check(BankrKeyMint.isSignedIn([("privy-token", ".bankr.bot")]), "privy-token on .bankr.bot is a session")
check(BankrKeyMint.isSignedIn([("privy-token", "bankr.bot")]), "…with or without the leading dot")
check(!BankrKeyMint.isSignedIn([("privy-token", ".notbankr.bot")]), "a lookalike domain is not Bankr")
check(!BankrKeyMint.isSignedIn([("privy-session", ".bankr.bot")]), "another Privy cookie is not the sign-in")
check(!BankrKeyMint.isSignedIn([]), "an empty jar is signed out")
check(BankrKeyMint.isBankrPage(URL(string: "https://bankr.bot/api-keys")), "bankr.bot is Bankr's page")
check(!BankrKeyMint.isBankrPage(URL(string: "https://privy.bankr.bot/x")), "Privy's host is not the page the call runs on")
check(!BankrKeyMint.isBankrPage(URL(string: "https://x.com/i/oauth2/authorize")), "and neither is X's")

// ── Other apps ───────────────────────────────────────────────────────────
check(BankrKeyMint.isAppHandoff(URL(string: "farcaster://signin")!), "a custom scheme leaves for its app")
check(BankrKeyMint.isAppHandoff(URL(string: "https://farcaster.xyz/~/siwf?channelToken=x")!), "Farcaster's sign-in leaves for Farcaster")
check(!BankrKeyMint.isAppHandoff(URL(string: "https://bankr.bot/")!), "Bankr's own page stays")
check(!BankrKeyMint.isAppHandoff(URL(string: "about:blank")!), "about:blank stays")
check(!BankrKeyMint.isAppHandoff(URL(string: "https://notfarcaster.xyz/")!), "a lookalike host stays")

print(failures == 0 ? "bankr-mint-selftest: all checks ✓" : "bankr-mint-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$MINT" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ bankr-mint-selftest: compile failed"; exit 1; }
"$TMP/run"
