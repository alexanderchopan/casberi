#!/bin/zsh
# Tacit, read only. Casberi opens a Tacit account a person ALREADY has, with
# the key their co-signer's wallet makes by signing Tacit's fixed message, and
# reads it through Tacit's own wallet in a hidden web view. This holds:
#   - the key is Tacit's, byte for byte: the pinned message, its EIP-191
#     digest, SHA-256 of the signature, and a high-s signature refused. The
#     vector is Tacit's own test wallet (`tests/identity-message.test.mjs`),
#     its signature computed with ethers 6 on 2026-11-24;
#   - the engine cannot send: its wallet is opened with no provider, it calls
#     none of the wallet's moving methods, its page can reach no host, and
#     every request passes the host check before it leaves;
#   - the wallet file is the pinned one.
set -euo pipefail
cd "$(dirname "$0")/.."
M="Casberi/Casberi/Model"
SRC="$M/TacitIdentity.swift"
ENGINE="$M/TacitEngine.swift"
JS="tools/tacit-engine/src/engine.js"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []; var i = hex.startIndex
    while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); out.append(UInt8(hex[i..<j], radix: 16)!); i = j }
    return out
}
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
typealias T = TacitIdentity

// The message, pinned: one character off opens a different, empty account.
check(T.message == "Tacit identity\n\nSigning this creates your Tacit private key. Anyone who has this signature controls all of your Tacit funds.\n\nSign it only in a Tacit app you trust. Every Tacit app asks for exactly this message.\n\nnetwork: mainnet\nversion: 1",
      "the identity message is not Tacit's")
check(T.message.utf8.count == 240, "the message's length moved")
check(T.messageHex.hasPrefix("0x5461636974206964656e74697479") && T.messageHex.count == 2 + 2 * 240, "personal_sign's parameter is not the message's bytes")
// What the wallet signs: ethers' hashMessage of the same words.
check(hex(T.digest) == "13cd0bd6ddabffa3fa8971170d9b55a934cf917eae507135bd62dc705b7e5944", "the EIP-191 digest is not the message's")

// Tacit's test wallet: its signature over the message, and the key that makes.
let signature = bytes("39be0db0be35278658a49b95b2291961de3c1ec8ada6ab675fd6af8377d4fd8a726dfaeb9b9cc7c878aa529c16242d84a19ad83d8069866a71a748bcdc8f53ba1c")
check((try? T.key(fromSignature: signature)).map(hex) == "f05bf1d9bb3fbe2766822069f56d6abeb47b00ea07c25e9357189dc8dc036f92",
      "the test wallet's signature does not make Tacit's key")

// The same signature in its high form (r, n - s, the other v) is refused,
// never normalised: hashing it would open another account.
let n = bytes("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
var high = signature
var borrow = 0
for i in stride(from: 31, through: 0, by: -1) {
    let d = Int(n[i]) - Int(high[32 + i]) - borrow
    high[32 + i] = UInt8((d + 256) % 256); borrow = d < 0 ? 1 : 0
}
high[64] = 28
var refused = false
do { _ = try T.key(fromSignature: high) } catch T.Failure.notCanonical { refused = true } catch {}
check(refused, "a high-s signature is not refused")

// Malformed answers make nothing.
var badV = signature; badV[64] = 0
for bad in [Array(signature.dropLast()), signature + [0], badV, []] {
    var threw = false
    do { _ = try T.key(fromSignature: bad) } catch T.Failure.malformed { threw = true } catch {}
    check(threw, "a malformed signature (\(bad.count) bytes) is not refused")
}

// Tacit's prfBytesToScalar: a valid scalar stands; zero and the order do not.
let one = [UInt8](repeating: 0, count: 31) + [1]
check(T.scalar(one) == one, "a valid scalar is changed")
check(T.scalar([UInt8](repeating: 0, count: 32)) != [UInt8](repeating: 0, count: 32), "zero stands as a key")
check(T.scalar(n) != n && T.scalar([UInt8](repeating: 0xff, count: 32)) != [UInt8](repeating: 0xff, count: 32),
      "a value at or past the curve's order stands as a key")

// Wei, 0x-hex, as ETH.
typealias W = TacitEngineWire
check(W.eth("0xde0b6b3a7640000") == 1 && W.eth("0x0") == 0 && W.eth("0x2386f26fc10000") == Decimal(string: "0.01"), "wei is misread")
// The Tacit chain counts TAC in 8 decimals.
check(W.tac("0x3b9aca00") == 10 && W.tac("0x1") == Decimal(string: "0.00000001") && W.tac("zz") == nil, "chain units are misread as TAC")
check(W.eth("12") == nil && W.eth("0x") == nil && W.eth("0xzz") == nil && W.eth("0x" + String(repeating: "f", count: 65)) == nil, "nonsense reads as an amount")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   Tacit's message, its test wallet's key, a high-s and a malformed signature, wei and chain units")
SWIFT

# The wire is pure but leans on the Privacy Pools wire's envelope types.
cat > "$work/stub.swift" <<'SWIFT'
import Foundation
enum PrivacyEngineWire { struct Failure: Error, Equatable, Decodable { let name: String; let message: String } }
SWIFT
OTHERS=("$M/Keccak256.swift" "$M/TacitEngineWire.swift" "$work/stub.swift")

xcrun swiftc -O "$SRC" "${OTHERS[@]}" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "${OTHERS[@]}" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "a high-s signature is hashed"      's/guard !greater\(Array\(signature\[32\.\.<64\]\), halfOrder\) else \{ throw Failure\.notCanonical \}//'
mutate "the message loses a word"          's/Every Tacit app asks for exactly this message\./Every Tacit app asks for this message./'
mutate "the network line moves"            's/"network: mainnet"/"network: signet"/'
mutate "a bare v is taken"                 's/signature\[64\] == 27 \|\| signature\[64\] == 28 else/signature[64] <= 28 else/'
mutate "the signature is hashed in part"   's/SHA256\.hash\(data: signature\)/SHA256.hash(data: signature.dropLast())/'
mutate "the order stands as a key"         's/\|\| !greater\(order, bytes\)//'
mutate "the digest drops the length"       's/Signed Message:\\n\\\(body\.count\)/Signed Message:\\n/'

# ── The engine cannot send, and its page reaches no host itself ──────────────
has() { grep -qF -- "$2" "$1" || fail "$3"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$3"; true; }
has "$JS" "import './net.js';" "the engine no longer imports its network door first"
[[ "$(grep -n "^import" "$JS" | head -1)" == *"./net.js"* ]] || fail "net.js is not the engine's FIRST import"
has "$JS" "makeEvmPoolWallet({ chainId, identityKey: key, rpc: n.rpcUrl, relay: n.relayUrl ?? null })" \
    "the wallet is no longer opened view-only (rpc and relay, no provider)"
hasnt "$JS" "provider:" "the engine hands the wallet a provider: a wallet with one can send"
# Making TAC private (prd §1971 item 20) is the engine's ONE way money moves,
# and it moves only by a permit the app checks and the co-signer signs: the
# engine proves (`.shield(`), hands it to the leader (`.offer(`, once, in
# `shieldHand`) and never sends a transaction or calls another moving verb.
[[ "$(grep -c "\.offer(" "$JS")" == "2" ]] || fail "the engine hands a deposit to the leader from somewhere new"
grep -A12 "async shieldHand" "$JS" | grep -qF ".offer(" || fail "the permit hand-off is not in shieldHand"
grep -A8 "async shieldOffer" "$JS" | grep -qF ".offer({ back: p.back, meta:" || fail "the account's hand-off carries something besides the return path"
for verb in ".deposit(" ".send(" ".withdraw(" ".sweep(" ".bridgeOut(" ".toV1(" "setArtifacts" ".spend(" ".publish(" ".makeNote(" ".submit(" "sendTransaction" "eth_sendRawTransaction"; do
  hasnt "$JS" "$verb" "the engine calls $verb: it reads only"
done
has "$ENGINE" '"connect-src \(scheme):",' "the page's Content-Security-Policy lets it reach a host"
has "$ENGINE" '"default-src '"'"'none'"'"'",' "the page's Content-Security-Policy no longer starts from nothing"
has "$ENGINE" "config.websiteDataStore = .nonPersistent()" "the page keeps data on disk"
allows=$(grep -n "PrivacyEngineWire.allows(url, declared: declared)" "$ENGINE" | head -1 | cut -d: -f1)
sends=$(grep -n "IngestSupport.sendRequest(request, service: TacitEngine.service)" "$ENGINE" | head -1 | cut -d: -f1)
[[ -n "$allows" && -n "$sends" && "$allows" -lt "$sends" ]] || fail "a request is sent before its host is checked"
has "Casberi/Casberi/Model/NetworkReach.swift" 'Endpoint(service: "Tacit engine",' "the engine's hosts are not declared"
# The Tacit chain: read with Tacit's own wallet, given no prover, at the
# contract and server Tacit's own config names.
has "$JS" "makeChainWallet({ poseidon, prover: null," "the chain wallet is handed a prover: with one it could spend"
has "$JS" "keep: false, known:" "the chain scan keeps a tree it has no use for"
# The DeFi pool: Tacit's pool library, its balance read and nothing else.
has "$JS" "pool.balance(key, { spent: true, positions: false" "the DeFi pool is no longer read by its balance"
[[ "$(grep -o "pool\.[a-zA-Z]*(" "$JS" | sort -u | tr -d '\n')" == "pool.balance(" ]] || fail "the engine calls the DeFi pool library for something other than its balance"
grep -A4 'Endpoint(service: "Tacit engine",' Casberi/Casberi/Model/NetworkReach.swift | grep -qE '"(mempool\.space|blockstream\.info|mempool\.emzy\.de)"' \
  && fail "a Bitcoin explorer is declared for the engine: the DeFi read waited minutes on it through Tor"
has "$M/TacitEngineWire.swift" 'static let blocks = "0x00000000000a9147ffd8d41d152d730ca5f84e6c"' "the Tacit chain's contract moved"
has "$M/TacitEngineWire.swift" 'static let leader = "https://tacit-chain-leader.onrender.com"' "the Tacit chain's server moved"
has "Casberi/Casberi/Model/NetworkReach.swift" '"tacit-chain-leader.onrender.com",' "the Tacit chain's server is not declared"
has "$M/TacitPocket.swift" "digest: TacitIdentity.digest, signer: coSigner," "the co-signer's answer is no longer checked against Tacit's message"
has "$M/TacitPocket.swift" 'static let tacToken = "0xA1313eb9f3A445606D9583bcAc3ebeB56a858279"' "TAC's token address moved: Public would read another token"
has "$M/TacitPocket.swift" "IngestSupport.sendRequest(request, service: TacitEngine.service)" "the public TAC read leaves the engine's funnel"
hasnt "$M/TacitAccount.swift" "kSecClass" "the account keeps something in the Keychain: the key is never stored"

# ── The wallet file is the pinned one, and the bundle is built from it ───────
python3 - <<'PY' || fail "a vendored file is not the pinned file"
import hashlib, json, sys
files = json.load(open('tools/tacit-engine/upstream.json'))['files']
bad = [p for p, f in files.items() if hashlib.sha256(open('tools/tacit-engine/' + p, 'rb').read()).hexdigest() != f['sha256']]
if len(files) < 14 or bad: print(bad or 'files are missing from upstream.json'); sys.exit(1)
PY
[[ -s Casberi/Casberi/Resources/tacit-engine.js ]] || fail "the engine's bundle is missing"
if command -v node >/dev/null; then
  (cd tools/tacit-engine && node test/chain-scan.mjs) || fail "the chain scan does not find an account's own notes"
fi
if [[ -d tools/tacit-engine/node_modules/esbuild ]]; then
  (cd tools/tacit-engine && node build.mjs --check >/dev/null) || fail "tacit-engine.js is not what tools/tacit-engine builds"
  print "  ok   the bundle reproduces from the pinned wallet"
fi
print "✓ tacit engine: Tacit's own key rule, a view-only wallet, no host but the declared ones (7 mutations)"
