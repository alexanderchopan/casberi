#!/bin/zsh
# tor-route-selftest.sh — which requests go through Tor (prd §1495).
#
# `TorRoute` and `NetworkReach` are Foundation-only, so this compiles the two
# real files against a stub `TorShim` module (so `canImport(TorShim)` holds, as
# on iOS) and drives the rule: a wallet host goes through Tor on a circuit
# keyed by the wallet it names; a host measured refusing Tor goes direct and is
# told apart; a Feed app's host never goes through Tor; and there is no way
# around Tor to read a wallet (user: "it shouldn't be optional it should be
# default"). It also asserts the USE — the funnel asks the rule before it sends, a Tor answer never falls back to a direct read, an exit's 403 is an
# outage and never the provider's refusal (§827b), no proxy may fail over, and
# the receipts count what went through Tor — or the rule is a type nothing
# calls. Four mutations prove the assertions bite, each checked to have
# CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/TorRoute.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
FUNNEL="Casberi/Casberi/Model/IngestSupport.swift"
CLIENT="Casberi/Casberi/Model/TorClient.swift"
LEDGER="Casberi/Casberi/Model/NetworkLedger.swift"
for f in "$SRC" "$REACH" "$FUNNEL" "$CLIENT" "$LEDGER"; do
    [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
echo "tor-route self-test"

use() { grep -q -- "$2" "$1" || { echo "✗ $3"; exit 1; } }
use "$FUNNEL" 'let way = TorRoute.way(for: request)' "IngestSupport.send no longer asks TorRoute before sending"
use "$FUNNEL" 'answer = await torData(for: request, isolation: tor)' "a Tor request no longer goes through torData"
use "$FUNNEL" 'NetworkLedger.shared.record(request, as: service, throughTor: tor != nil)' "the receipts no longer count what went through Tor"
use "$FUNNEL" '(again.1 as? HTTPURLResponse)?.statusCode != 403 else { return nil }' "an exit's second 403 no longer reads as an outage"
use "$CLIENT" 'proxy.allowFailover = false' "a Tor proxy may fail over to a direct read"
if grep -q 'allowFailover = true' "$FUNNEL" "$CLIENT"; then echo "✗ a proxy fails over to a direct read"; exit 1; fi
# torData must not reach the plain session: everything after its guard rides Tor.
if awk '/private static func torData/,/^    }$/' "$FUNNEL" | grep -q 'session\.data'; then
    echo "✗ torData falls back to the direct session"; exit 1
fi
# No way around Tor: the rule has no bypass flag and no screen offers one.
if grep -rn -E 'readDirectly|Read without Tor|setDirect' Casberi/Casberi --include='*.swift' >/dev/null; then
    echo "✗ a way around Tor came back — wallet reads are never optional"; exit 1
fi
# The fallback asks Tor first, only with Tor up, and counts the direct read.
use "$FUNNEL" 'if answer == nil, TorRoute.fallsBack(host: request.url?.host()), TorClient.shared.isConnected {' "the relayer's fallback no longer waits for Tor's refusal with Tor up"
use "$FUNNEL" 'NetworkLedger.shared.record(request, as: service, throughTor: false)' "a direct read after Tor's refusal is not counted as one"
use "Casberi/Casberi/Screens/MovePrivate.swift" 'move.relayerDirect ? String(localized: "not through Tor") : nil' "a private send reached directly no longer says it is not through Tor"
echo "  ok   the funnel routes through the rule, never fails over, has no bypass, and counts what went through Tor"

# Every move Relay carries says it left Tor (prd §1512): the foot reads one
# rule, and the rule names the two moves that still ask Relay. A swap and a
# sweep go to the pools through the account's own nodes, through Tor (prd
# §1539, measured 2026-10-26), so they are not Relay's and never say so.
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
use "$MOVE" 'if relayCarries, receipt == nil, !nothingToMove {' "Relay's foot no longer reads relayCarries"
use "$MOVE" 'case .sweep: false' "a sweep says Relay carries it, though it goes to the pools through Tor (prd §1539)"
use "$MOVE" 'case .swap, .send: roundUpCarried != nil && !RoundUps.setting.target.onExchanges(from: network.chainId)' "a send or swap says Relay carries it beyond its round-up buy on another network (prd §1539, §1545, §1561)"
use "$MOVE" 'case .receive: elsewhere != nil' "Receive from another network no longer says Relay carries it"
if awk '/Text\("Powered by Relay"\)/,/padding\(\.top/' "$MOVE" | grep -q 'not through Tor'; then :; else
    echo "✗ Relay's foot no longer says it is not through Tor"; exit 1
fi
echo "  ok   every move Relay carries says it is not through Tor"

TMP=$(mktemp -d /tmp/tor-route-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/shim"
cat > "$TMP/shim/module.modulemap" <<'MAP'
module TorShim { header "TorShim.h" export * }
MAP
echo '/* stub: TorRoute only asks whether the module exists */' > "$TMP/shim/TorShim.h"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
// `NetworkReach`'s purposes name the device through the design system.
enum DS { static let device = "Casberi" }
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func way(_ url: String, body: String? = nil) -> TorRoute.Way {
    TorRoute.way(host: URL(string: url)?.host(), url: url, body: body.map { Data($0.utf8) })
}
let a = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
let b = "0x3f5CE5FBFe3E9af3971dD833D26bA9b5C936f0bE"
let rpcBody = { (addr: String) in #"{"jsonrpc":"2.0","method":"eth_getBalance","params":["\#(addr)","latest"]}"# }

check(TorRoute.available, "the stub module makes Tor available, as on iOS")
check(way("https://rpc.mevblocker.io", body: rpcBody(a)) == .tor(isolation: a.lowercased()),
      "a public node's read naming a wallet goes through Tor on that wallet's circuit")
check(way("https://api.zerion.io/v1/wallets/\(a)/positions/") == .tor(isolation: a.lowercased()),
      "Zerion's read goes through Tor on the wallet's circuit")
check(way("https://rpc.mevblocker.io", body: rpcBody(a)) != way("https://rpc.mevblocker.io", body: rpcBody(b)),
      "two wallets never share a circuit")
check(way("https://public.pimlico.io/v2/8453/rpc", body: rpcBody(b)) == .tor(isolation: b.lowercased()),
      "the bundler goes through Tor")
check(way("https://mempool.space/api/address/bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq/txs")
      == .tor(isolation: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"),
      "a Bitcoin address keys its own circuit")
check(way("https://ethereum-beacon-api.publicnode.com/eth/v1/node/version") == .tor(isolation: "ethereum-beacon-api.publicnode.com"),
      "a wallet host's read naming no wallet shares the host's circuit")
check(way("https://api.relay.link/quote", body: rpcBody(a)) == .refusesTor, "Relay refuses Tor and is told apart")
check(way("https://tokens.uniswap.org") == .tor(isolation: "tokens.uniswap.org"),
      "Uniswap's token list (prd §1542) does not go through Tor, though it answered through it 3 of 3")
check(way("https://linea.gateway.tenderly.co/", body: rpcBody(a)) == .refusesTor, "a Tenderly gateway refuses Tor")
check(way("https://rpc.gnosischain.com", body: rpcBody(a)) == .refusesTor, "Gnosis's RPC refuses Tor")
check(way("https://rpc.plasma.to", body: rpcBody(a)) == .tor(isolation: a.lowercased()),
      "Plasma's own RPC answers over Tor while thirdweb's refuses")
for url in ["https://x.com/i/api/2/notifications/all.json", "https://www.instagram.com/api/v1/news/inbox/",
            "https://www.tiktok.com/api/notice/multi/", "https://api.github.com/notifications",
            "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed", "https://gmail.googleapis.com/gmail/v1/users/me"] {
    check(way(url, body: rpcBody(a)) == .direct, "a Feed app never goes through Tor: \(url)")
}
check(way("https://evil.example/\(a)") == .direct, "an undeclared host is not a wallet host")

for e in NetworkReach.endpoints where !e.refusesTor.isEmpty {
    check(e.throughTor, "\(e.service) lists hosts refusing Tor but is not routed")
    for h in e.refusesTor {
        check(e.hosts.contains { NetworkReach.matches(host: h, declared: $0) || NetworkReach.matches(host: $0, declared: h) },
              "\(e.service)'s refusing host \(h) is one of its hosts")
    }
}
// The one fallback: 0xBow's relayer alone may be read directly once Tor
// refused it, and only a routed entry's own host may be listed so.
check(TorRoute.fallsBack(host: "relayer-v2-prod-149184580131.us-east1.run.app"), "0xBow's relayer no longer falls back when Tor refuses it")
check(!TorRoute.fallsBack(host: "api-v2.0xbow.io"), "0xBow's review service falls back around Tor")
check(!TorRoute.fallsBack(host: "rpc.mevblocker.io"), "a node falls back around Tor")
check(!TorRoute.fallsBack(host: "api.zerion.io"), "Zerion falls back around Tor")
for e in NetworkReach.endpoints where !e.directWhenRefused.isEmpty {
    check(e.throughTor, "\(e.service) falls back but is not routed")
    for h in e.directWhenRefused {
        check(e.hosts.contains { NetworkReach.matches(host: h, declared: $0) }, "\(e.service)'s fallback host \(h) is one of its hosts")
    }
}
for name in ["X notifications", "Instagram live", "TikTok live", "Spotify", "Gmail", "iCloud Mail",
             "GitHub", "Bluesky", "Privy", "Connect a wallet", "Token prices"] {
    check(NetworkReach.endpoint(forService: name)?.throughTor == false, "\(name) is not routed through Tor")
}

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT

compile_and_run() {
    swiftc -Onone -I "$TMP/shim" "$1" "$REACH" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" \
        || { head -20 "$TMP/err"; return 2; }
    "$TMP/run"
}
compile_and_run "$SRC" || { echo "✗ the rule fails its own self-test"; exit 1; }
echo "  ok   wallets through Tor on their own circuits, refusers and Feed apps direct"

mutate() {
    local name="$1" perl_expr="$2"
    cp "$SRC" "$TMP/mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/mut.swift"
    if cmp -s "$SRC" "$TMP/mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    if compile_and_run "$TMP/mut.swift" >/dev/null 2>&1; then
        echo "✗ SURVIVED  $name"; exit 1
    fi
    echo "  ok   catches  $name"
}
mutate "a host refusing Tor is routed anyway" 's/return \.refusesTor\n/return .tor(isolation: host)\n/'
mutate "every wallet shares one circuit" 's/return \.tor\(isolation: isolationKey\(url: url, body: body, host: host\)\)/return .tor(isolation: host)/'
mutate "a refusing host's subdomain is routed" 's/endpoint\.refusesTor\.contains\(where: \{ NetworkReach\.matches\(host: host, declared: \$0\) \}\)/endpoint.refusesTor.contains(host)/'
mutate "every host goes through Tor" 's/guard let endpoint = endpoint\(forHost: host\), endpoint\.throughTor else \{ return \.direct \}/guard let endpoint = endpoint(forHost: host) else { return .tor(isolation: host) }/'
echo "  ok   4 mutations"
