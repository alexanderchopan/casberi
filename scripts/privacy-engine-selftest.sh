#!/bin/zsh
# privacy-engine-selftest.sh — the Privacy Pools engine's Swift side (prd §1540).
#
# The engine is 0xBow's SDK in a hidden web view (`PrivacyEngine`). What makes
# it safe to run is Swift's, and Foundation-only, so this compiles the real
# files and drives them:
#   - the wire: an envelope decodes to its value or throws the engine's
#     error, and nothing else ever reads as a value;
#   - the network door: only https, the default port, no credentials, and a
#     host the engine's NetworkReach entry declares, on the label boundary;
#   - two networks (prd §1563): `PrivacyNetwork.check` opens Sepolia and
#     Ethereum and refuses every other chain, and Ethereum too when the kill
#     switch (`PrivateMainnet.on`) is off — compiled both ways; Ethereum's
#     addresses, first block and yield pools are the ones read on chain;
#   - the circuits: 27 pinned per network (Sepolia's dev keys, Ethereum's
#     ceremony keys), a path names a pinned file or nothing, and a byte that
#     does not hash to its pin is refused;
#   - the registry: every host the network and the gateways use is declared,
#     and the engine's reads go through Tor.
# It also asserts the USE — the door is asked before the funnel sends, the
# pin is checked before a file is kept and again when it is read, the page
# can reach no host itself, `open` checks the network first — or the rules
# are types nothing calls. Six mutations prove the assertions bite, each
# checked to have CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
WIRE="Casberi/Casberi/Model/PrivacyEngineWire.swift"
ART="Casberi/Casberi/Model/PrivacyArtifacts.swift"
PINS="Casberi/Casberi/Model/PrivacyArtifactPins.swift"
ENGINE="Casberi/Casberi/Model/PrivacyEngine.swift"
KEY="Casberi/Casberi/Model/PrivacyPoolsKey.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
NETJS="tools/privacy-pools-engine/src/net.js"
ENGJS="tools/privacy-pools-engine/src/engine.js"
BUNDLE="Casberi/Casberi/Resources/privacy-engine.js"
for f in "$WIRE" "$ART" "$PINS" "$ENGINE" "$KEY" "$REACH" "$NETJS" "$ENGJS" "$BUNDLE"; do
    [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
echo "privacy-engine self-test"

use() { grep -qF -- "$2" "$1" || { echo "✗ $3"; exit 1; } }
# The door is asked BEFORE the funnel sends, and the funnel is the only send.
awk '/class PrivacyEngineNet/,/^}$/' "$ENGINE" > /tmp/pe-net.$$
use /tmp/pe-net.$$ 'guard PrivacyEngineWire.allows(url, declared: declared) else {' "the network door no longer asks PrivacyEngineWire.allows"
use /tmp/pe-net.$$ 'IngestSupport.sendRequest(request, service: PrivacyEngine.service)' "the engine's requests no longer go through the funnel"
if [[ $(grep -n 'PrivacyEngineWire.allows' /tmp/pe-net.$$ | cut -d: -f1) -gt $(grep -n 'IngestSupport.sendRequest' /tmp/pe-net.$$ | cut -d: -f1) ]]; then
    echo "✗ the funnel sends before the door is asked"; rm -f /tmp/pe-net.$$; exit 1
fi
rm -f /tmp/pe-net.$$
if grep -nE 'URLSession|dataTask\(|[Ss]ession\.data\(' "$ENGINE" >/dev/null; then
    echo "✗ PrivacyEngine reaches the network around the funnel"; exit 1
fi
use "$ENGINE" 'NetworkReach.endpoint(forService: service)?.hosts' "the door no longer reads its hosts from NetworkReach"
# The pin is checked before a downloaded file is kept, and on every cached read.
awk '/actor PrivacyArtifactStore/,/^}$/' "$ENGINE" > /tmp/pe-store.$$
[[ $(grep -c 'PrivacyArtifacts.verify(' /tmp/pe-store.$$) -ge 3 ]] || { echo "✗ the store no longer checks the pin on download, on read and on isCached"; rm -f /tmp/pe-store.$$; exit 1; }
if awk '/guard PrivacyArtifacts.verify\(data, against: file\)/{v=1} /try data.write/{ if (!v) bad=1 } END{exit bad}' /tmp/pe-store.$$; then :; else
    echo "✗ a downloaded file is written before it is verified"; rm -f /tmp/pe-store.$$; exit 1
fi
rm -f /tmp/pe-store.$$
use "$ENGINE" 'guard let wanted = PrivacyArtifacts.request(path: path, pins: pins) else {' "the scheme serves circuit files without the pinned-path rule"
# The page can reach no host on its own.
use "$ENGINE" '"connect-src \(scheme):",' "the page's CSP no longer limits connect-src to the app's scheme"
if grep -E '"(connect|default)-src[^"]*https' "$ENGINE" >/dev/null; then echo "✗ the page's CSP lets it reach a host"; exit 1; fi
use "$ENGINE" 'config.websiteDataStore = .nonPersistent()' "the engine's page keeps data on disk"
use "$NETJS" 'globalThis.fetch = engineFetch;' "net.js no longer replaces fetch"
use "$NETJS" "globalThis.webkit.messageHandlers.engineNet.postMessage" "net.js no longer hands requests to the app"
use "$ENGJS" "import './net.js';" "engine.js no longer imports net.js first"
[[ $(grep -m1 -n "^import" "$ENGJS" | cut -d: -f2-) == "import './net.js';" ]] || { echo "✗ net.js is not engine.js's first import"; exit 1; }
# Two networks, on both sides; the kill switch is a constant in shipping code.
awk '/func open\(seed: Data/,/^    }$/' "$ENGINE" | grep -qF 'try network.check()' || { echo "✗ open no longer checks the network first"; exit 1; }
use "$ENGJS" "const NETWORKS = new Set([11155111, 1]);" "the page no longer refuses a chain it does not serve"
awk '/^enum PrivateMainnet \{/,/^\}/' "$WIRE" | grep -qF 'static let on = true' || { echo "✗ the kill switch is not ONE constant, on (prd §1563: on for the App Store and TestFlight)"; exit 1; }
awk '/^enum PrivateMainnet \{/,/^\}/' "$WIRE" | grep -q '#if' && { echo "✗ the kill switch hides behind a build flag"; exit 1; }
use "$WIRE" 'static var served: Set<Int> { PrivateMainnet.on ? testnets.union([1]) : testnets }' "Ethereum is served without the kill switch"
# The bundle is the build of these sources: its testnet guard and door are in it.
use "$BUNDLE" "engineNet" "the shipped bundle has no network door — rebuild with tools/privacy-pools-engine/build.mjs"
use "$BUNDLE" "11155111" "the shipped bundle has no network guard — rebuild"
use "$BUNDLE" "prepareYieldDeposit" "the shipped bundle cannot deposit into a yield pool — rebuild"
# Balance to balance on a yield pool (prd §1565): the transfer moves SHARES,
# sized from the token's amount at today's rate, to the recipient the
# keystore names — never secrets the app would have to deliver.
use "$ENGJS" "value = (await y.deposit.sharesForUnderlying(value)) + 1n;" "a transfer on a yield pool is not sized in shares"
use "$ENGJS" "const r = await s.prepareTransfer({ inputCommitments: inputsFor(token, value), amount: hex(value), tokenId: token," "a transfer spends notes of another token than it moves"
! grep -q "allowOutOfBandFallback" "$ENGJS" || { echo "✗ the engine opts into out-of-band transfers"; exit 1; }
# The seed is device-only behind Face ID outside DEBUG simulator builds.
use "$KEY" "kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.biometryCurrentSet]" "the seed is no longer device-only behind Face ID"
use "$KEY" "kSecAttrSynchronizable as String: false" "the seed may sync"
echo "  ok   the door is asked before the funnel, pins are checked before a file is kept, the page reaches no host, two networks behind one switch"

TMP=$(mktemp -d /tmp/privacy-engine-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
enum DS { static let device = "Casberi" }
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias W = PrivacyEngineWire

// The wire.
let good = #"{"ok":true,"value":{"registered":true,"ms":12}}"#
check((try? W.decode(W.Registered.self, from: good)) == W.Registered(registered: true, ms: 12), "an ok envelope decodes to its value")
do { _ = try W.decode(W.Registered.self, from: #"{"ok":false,"error":{"name":"NotTestnet","message":"chain 1"}}"#); check(false, "an error envelope threw") }
catch let f as W.Failure { check(f == W.Failure(name: "NotTestnet", message: "chain 1"), "an error envelope throws the engine's error") }
catch { check(false, "an error envelope throws a Failure") }
check((try? W.decode(W.Registered.self, from: #"{"ok":false,"value":{"registered":true,"ms":1},"error":{"name":"E","message":"m"}}"#)) == nil,
      "a failed envelope never reads as a value, even carrying one")
check((try? W.decode(W.Registered.self, from: #"{"ok":true}"#)) == nil, "ok without a value is a failure")
check((try? W.decode(W.Registered.self, from: "not json")) == nil, "a reply that is not an envelope is a failure")
let openJSON = (try? W.encode(W.Open(seed: "0x" + String(repeating: "ab", count: 32), revocableKeyIndex: "0x0", owner: "0x01", network: .sepolia))) ?? ""
check(openJSON.contains(#""chainId":11155111"#) && openJSON.contains(#""withdrawProcessor":"0x7430cc030d7eb8C83E76cD983996982C8C054204""#),
      "open carries the network the page checks")
check(Set(W.Method.allCases.map(\.rawValue)) == ["info", "open", "close", "isRegistered", "prepareRegister", "prepareDeposit", "discover", "prepareTransfer", "prepareWithdraw", "bench", "labelHash", "relay", "prepareRagequit", "prepareYieldDeposit"],
      "the methods are the page's")

// The network door.
let declared = ["api-dev.0xbow.io", "ethereum-sepolia-rpc.publicnode.com"]
func allows(_ s: String) -> Bool { W.allows(URL(string: s)!, declared: declared) }
check(allows("https://api-dev.0xbow.io/global/public/entrypoints"), "a declared host is allowed")
check(allows("https://eu.api-dev.0xbow.io/x"), "a declared host's subdomain is allowed")
check(!allows("http://api-dev.0xbow.io/x"), "plain http is refused")
check(!allows("https://user:pw@api-dev.0xbow.io/x"), "credentials in the URL are refused")
check(!allows("https://api-dev.0xbow.io:8443/x"), "another port is refused")
check(allows("https://api-dev.0xbow.io:443/x"), "the default port is allowed")
check(!allows("https://evilapi-dev.0xbow.io/x"), "a host that only ends with a declared one's text is refused")
check(!allows("https://api-dev.0xbow.io.evil.com/x"), "a declared host as a prefix is refused")
check(!allows("https://li.quest/v1/quote"), "an undeclared host is refused")
check(!allows("casberi-engine://engine/x"), "the app's own scheme never reaches the network door")

// Two networks behind one switch (prd §1563).
check((try? PrivacyNetwork.sepolia.check()) != nil, "Sepolia opens")
let eth = PrivacyNetwork.ethereum
if PrivateMainnet.on {
    check((try? eth.check()) != nil, "Ethereum opens with the switch on")
} else {
    do { try eth.check(); check(false, "Ethereum is refused with the switch off") }
    catch { check((error as? PrivacyNetwork.Refusal) == .notServed(1), "Ethereum is refused with the switch off") }
    check(PrivacyNetwork.forChain(1) == nil, "with the switch off no note names Ethereum's network")
}
for other in [8453, 10, 42161, 56, 137] {
    let n = PrivacyNetwork(chainId: other, rpcUrl: eth.rpcUrl, aspUrl: eth.aspUrl, relayerUrl: eth.relayerUrl, relayerAddress: eth.relayerAddress,
                           transferProcessor: eth.transferProcessor, withdrawProcessor: eth.withdrawProcessor, entrypoint: eth.entrypoint,
                           pool: eth.pool, keystore: eth.keystore, aspRegistry: eth.aspRegistry, fromBlock: eth.fromBlock)
    do { try n.check(); check(false, "chain \(other) is refused") } catch { check((error as? PrivacyNetwork.Refusal) == .notServed(other), "chain \(other) is refused") }
}
// Ethereum is the deployment read on chain 2026-10-26 (and run in
// simulation by tools/privacy-pools-engine/mainnet-sim.mjs).
check(eth.entrypoint == "0xca1e072236D231130059eeA6Bfceb7F4e9a1F0C3" && eth.pool == "0x0Eb42804BF897662aF851370eaeAdcDBEC1b97ed"
      && eth.keystore == "0x6E463391c79b7e1A88eF26E0B023f9A6C9938a71" && eth.aspRegistry == "0x259C0BEa1d783c202509BD3b2688d23b8AEf58B0",
      "Ethereum's Entrypoint, PoolVault, Keystore and ASP registry are the ones on chain")
check(eth.withdrawProcessor == "0x01a8Fa4dbb60187aD8d3c3d08E7Fb8C14198A461" && eth.relayerAddress == "0x9e2f1B234953F46c6091636290E9035618EA3C07",
      "Ethereum's relay and the relayer's signer are the production relayer's")
check(eth.fromBlock == 25_884_231, "Ethereum's first block is the keystore's (older than the pool and the ASP's fromBlock)")
check(eth.aspUrl == "https://api-v2.0xbow.io" && eth.relayerUrl == "https://relayer-v2-prod-149184580131.us-east1.run.app", "production ASP and relayer")
check(eth.yield.map(\.symbol) == ["ETH", "USDC"] && eth.yield[0].native && !eth.yield[1].native, "ppETH (native) and ppUSDC earn")
check(eth.yieldPool(for: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE")?.share == "0x66051920D25af4E3596A8a46309F4D045F9D83B7", "ETH deposits into ppETH")
check(eth.yieldPool(for: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")?.router == "0xe76E793d776c1e207aD7a7fa7C57d27420d85110", "USDC deposits through ppUSDC's router")
check(eth.yieldPool(for: "0xdAC17F958D2ee523a2206206994597C13D831ec7") == nil, "USDT has no pool here (not built)")
check(PrivacyNetwork.sepolia.yield.isEmpty && PrivacyNetwork.sepolia.yieldPool(for: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE") == nil, "Sepolia earns nothing")
check(eth.logsUrl == nil && PrivacyNetwork.sepolia.logsUrl == PrivacyNetwork.sepoliaLogsUrl, "Ethereum reads its logs from its own node")
let ethJSON = (try? W.encode(W.Open(seed: "0x" + String(repeating: "ab", count: 32), revocableKeyIndex: "0x0", owner: "0x01", network: eth))) ?? ""
check(ethJSON.contains(#""chainId":1,"#) && ethJSON.contains(#""router":"0x77613D670BB9fD48A9898D0eac8ebf21B566F960""#) && ethJSON.contains(#""native":true"#),
      "open carries Ethereum's yield pools to the page")
check(W.throttled(status: 200, body: #"{"error":{"code":-32603,"message":"service temporarily unavailable"}}"#), "MEV Blocker's busy answer is waited out")

// The circuits.
let pins = PrivacyArtifacts.sepoliaPins
check(pins.count == 27, "27 circuits are pinned (deposit, ragequit, transact 1x1…5x5)")
for (name, c) in pins { for kind in PrivacyArtifacts.Kind.allCases {
    let f = c.file(kind)
    check(f.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, "\(name).\(kind) has a SHA-256 pin")
    check(f.cid.hasPrefix("Qm") && f.cid.count == 46, "\(name).\(kind) has a CID")
} }
check(pins["deposit"]?.zkey.sha256 == "0e64b6d15ea540b3ab04d5596ab45d1ed6df0872e0261a850039372104837b30",
      "Sepolia's deposit key is 1.0.0's dev key, the one its verifier holds")
let ceremony = PrivacyArtifacts.ceremonyPins
check(ceremony.count == 27 && Set(ceremony.keys) == Set(pins.keys), "27 ceremony circuits, the same names")
check(PrivacyArtifacts.pins(chainId: 1) == ceremony && PrivacyArtifacts.pins(chainId: 11155111) == pins && PrivacyArtifacts.pins(chainId: 8453) == nil,
      "Ethereum proves with the ceremony keys, Sepolia with the dev keys, nothing else with any")
for name in pins.keys { check(ceremony[name]?.zkey != pins[name]?.zkey, "\(name)'s ceremony key is not the dev key") }
// The three keys whose proofs mainnet's verifiers accepted in simulation
// (mainnet-sim.mjs, 2026-10-26: a deposit, a ragequit, a relayed withdrawal).
check(ceremony["deposit"]?.zkey.sha256 == "e6fb5283c7b7511b0422a773d9f054925969e47e8ddf55a6b38b590c951a73a4"
      && ceremony["ragequit"]?.zkey.sha256 == "044abe871b1b79fecb6b4ca6128d08a142d7ce8665f439032953bae92f6ab076"
      && ceremony["transact_1x1"]?.zkey.sha256 == "e92ad88f417c034f073580658839b64fdd1ad3c89a86a9faa926728f80351121",
      "the deposit, ragequit and withdrawal keys are the ones mainnet verified in simulation")
check(PrivacyArtifacts.request(path: "artifact/deposit/zkey", pins: pins)?.file == pins["deposit"]?.zkey, "a pinned path names its file")
for bad in ["artifact/../zkey", "artifact/deposit/pkey", "artifact/deposit", "artifact/deposit/zkey/x", "artifact/transact_6x6/zkey",
            "artifact/Deposit/zkey", "files/deposit/zkey", "artifact/deposit%2F../zkey"] {
    check(PrivacyArtifacts.request(path: bad, pins: pins) == nil, "\(bad) names nothing")
}
let bytes = Data("a circuit file".utf8)
let pin = PrivacyArtifacts.File(cid: "Qm" + String(repeating: "x", count: 44), sha256: PrivacyArtifacts.sha256Hex(bytes))
check(PrivacyArtifacts.verify(bytes, against: pin), "bytes that hash to the pin pass")
check(PrivacyArtifacts.verify(bytes, against: .init(cid: pin.cid, sha256: pin.sha256.uppercased())), "the pin's case does not matter")
var flipped = bytes; flipped[0] ^= 1
check(!PrivacyArtifacts.verify(flipped, against: pin), "one flipped bit is refused")
check(!PrivacyArtifacts.verify(Data(), against: .init(cid: pin.cid, sha256: PrivacyArtifacts.sha256Hex(Data()))), "an empty file is refused")
check(!PrivacyArtifacts.verify(bytes, against: .init(cid: pin.cid, sha256: "")), "a missing pin passes nothing")
check(PrivacyArtifacts.cacheURL(for: pin, in: URL(fileURLWithPath: "/c")).lastPathComponent == pin.sha256, "a file is kept under its hash")
check(PrivacyArtifacts.urls(for: pin).allSatisfy { $0.absoluteString.hasSuffix("/ipfs/" + pin.cid) }, "a file is fetched by its CID")

// The registry.
let engine = NetworkReach.endpoint(forService: "Privacy Pools engine")
let circuits = NetworkReach.endpoint(forService: "Privacy Pools circuits")
check(engine?.throughTor == true, "the engine's reads go through Tor")
for host in PrivacyNetwork.sepolia.hosts + PrivacyNetwork.ethereum.hosts {
    check(engine.map { W.allows(URL(string: "https://\(host)/")!, declared: $0.hosts) } == true, "\(host) is declared for the engine")
}
for gateway in PrivacyArtifacts.gateways {
    let host = URL(string: gateway)!.host!
    check(circuits?.hosts.contains(host) == true, "\(host) is declared for the circuits")
}

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT

compile_and_run() {
    swiftc -Onone "$1" "$2" "$PINS" "$REACH" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" \
        || { head -20 "$TMP/err"; return 2; }
    "$TMP/run"
}
compile_and_run "$WIRE" "$ART" || { echo "✗ the engine's rules fail their own self-test"; exit 1; }
# The kill switch off: Ethereum is refused, and the rest still holds.
sed 's/    static let on = true/    static let on = false/' "$WIRE" > "$TMP/off.swift"
cmp -s "$WIRE" "$TMP/off.swift" && { echo "✗ the kill switch could not be turned off for its test"; exit 1; }
compile_and_run "$TMP/off.swift" "$ART" || { echo "✗ with the kill switch off, Ethereum is not refused"; exit 1; }
echo "  ok   the wire, the door, two networks behind one switch (both ways), 27 pinned circuits a network and the registry"

mutate() {
    local name="$1" file="$2" perl_expr="$3"
    cp "$file" "$TMP/mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/mut.swift"
    if cmp -s "$file" "$TMP/mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    local ok
    if [[ "$file" == "$WIRE" ]]; then ok=$(compile_and_run "$TMP/mut.swift" "$ART" >/dev/null 2>&1 && echo y || echo n)
    else ok=$(compile_and_run "$WIRE" "$TMP/mut.swift" >/dev/null 2>&1 && echo y || echo n); fi
    [[ "$ok" == n ]] || { echo "✗ SURVIVED  $name"; exit 1; }
    echo "  ok   catches  $name"
}
mutate "the door drops the label boundary" "$WIRE" 's/host\.hasSuffix\("\." \+ d\)/host.hasSuffix(d)/'
mutate "the door takes plain http" "$WIRE" 's/guard url\.scheme == "https", /guard url.scheme == "https" || url.scheme == "http", /'
mutate "a failed envelope with a value reads as one" "$WIRE" 's/if envelope\.ok, let value = envelope\.value/if let value = envelope.value/'
mutate "any chain opens" "$WIRE" 's/guard Self\.served\.contains\(chainId\) else/guard chainId > 0 else/'
mutate "Ethereum proves with the dev keys" "$ART" 's/case PrivacyNetwork\.ethereum\.chainId: ceremonyPins/case PrivacyNetwork.ethereum.chainId: sepoliaPins/'
mutate "Ethereum's first block is the pool's" "$WIRE" 's/fromBlock: 25_884_231,/fromBlock: 25_884_277,/'
mutate "a USDC deposit goes to ppETH's router" "$WIRE" 's/router: "0xe76E793d776c1e207aD7a7fa7C57d27420d85110"/router: "0x77613D670BB9fD48A9898D0eac8ebf21B566F960"/'
mutate "MEV Blocker's busy answer is an answer" "$WIRE" 's/\|temporarily unavailable"#/"#/'
mutate "a file is kept without its hash" "$ART" 's/return sha256Hex\(data\) == file\.sha256\.lowercased\(\)/return true/'
mutate "a longer path names a file" "$ART" 's/guard parts\.count == 3, /guard parts.count >= 3, /'
# The switch, off, must refuse Ethereum: a `served` that ignores it is caught.
cp "$TMP/off.swift" "$TMP/offmut.swift"
perl -0pi -e 's/static var served: Set<Int> \{ PrivateMainnet\.on \? testnets\.union\(\[1\]\) : testnets \}/static var served: Set<Int> { testnets.union([1]) }/' "$TMP/offmut.swift"
cmp -s "$TMP/off.swift" "$TMP/offmut.swift" && { echo "✗ mutation did not apply: the kill switch is ignored"; exit 1; }
if compile_and_run "$TMP/offmut.swift" "$ART" >/dev/null 2>&1; then echo "✗ SURVIVED  the kill switch is ignored"; exit 1; fi
echo "  ok   catches  the kill switch is ignored"
echo "  ok   11 mutations"
