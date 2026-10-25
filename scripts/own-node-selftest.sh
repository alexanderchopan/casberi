#!/bin/zsh
# Your own node (prd §1517, Phase 5 of docs/signing-safety-spec.md) —
# `OwnNode`: the address rule (http or https, a host, nothing else), the
# check's verdict (the chain id must be the network's and a block must
# answer, a wrong chain is never kept), its words, and the switch; then the
# wiring: a network with your node reads from it and from NOTHING else (no
# fall-through to the list), only a checked address is saved, and the
# requests name their service to the ledger.
set -euo pipefail
cd "$(dirname "$0")/.."

NODE="Casberi/Casberi/Model/OwnNode.swift"
STORE="Casberi/Casberi/Model/OwnNodeStore.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
PAGE="Casberi/Casberi/Screens/OwnNodePage.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$NODE" "$STORE" "$CHAIN" "$PAGE" "$REACH"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

TMP=$(mktemp -d /tmp/own-node-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias N = OwnNode
var bad = 0, ran = 0
func check(_ ok: Bool, _ what: String) { ran += 1; if !ok { print("✗ " + what); bad += 1 } }

check(N.normalized("http://192.168.1.20:8545") == "http://192.168.1.20:8545", "a home node over http was refused")
check(N.normalized("  base.mynode.home:8545 ") == "https://base.mynode.home:8545", "a bare host did not get https")
check(N.normalized("ftp://node.example") == nil && N.normalized("ws://node.example") == nil, "a non-http scheme was taken")
check(N.normalized("") == nil && N.normalized("my node") == nil && N.normalized("https://") == nil, "a non-address was taken")

// The verdict, as the measured answers came back (2026-10-24).
check(N.verdict(expected: 8453, chainId: "0x2105", block: "0x3299a0a") == .answers(chainId: 8453, block: 0x3299a0a), "Base's node did not answer")
check(N.verdict(expected: 8453, chainId: "0x1", block: "0x10") == .wrongChain(1), "an Ethereum node passed for Base")
check(N.verdict(expected: 8453, chainId: nil, block: nil) == .noAnswer, "a web page passed as a node")
check(N.verdict(expected: 8453, chainId: "0x2105", block: nil) == .noAnswer, "a node with no block passed")
check(N.quantity("0x") == nil && N.quantity("12") == nil && N.quantity("0xzz") == nil, "a malformed quantity read")

// The words.
let ok = N.words(.answers(chainId: 8453, block: 31_882_104), network: "Base", expected: 8453)
check(ok.ok && ok.text.hasPrefix("Chain 8453 · block 31") && ok.text.hasSuffix("882,104"), "the green line drifted from the canvas")
let wrong = N.words(.wrongChain(1), network: "Base", expected: 8453)
check(!wrong.ok && wrong.text == "Answers for chain 1, not Base's 8453", "a wrong chain is not said")

// The switch: off, no network reads from a node, whatever is kept.
var s = N.Settings(on: false, nodes: ["8453": "http://192.168.1.20:8545"])
check(s.address(for: 8453) == nil, "your node is used with the switch off")
s.on = true
check(s.address(for: 8453) == "http://192.168.1.20:8545" && s.address(for: 1) == nil, "the switch on did not route one network alone")
let round = try! JSONDecoder().decode(N.Settings.self, from: JSONEncoder().encode(s))
check(round == s, "the settings do not survive being kept")

print(bad == 0 ? "own-node self-test: \(ran) checks ok" : "own-node self-test: \(bad) of \(ran) failed")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$NODE" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; echo "✗ OwnNode.swift does not compile with Foundation alone"; exit 1; }
"$TMP/t" || exit 1

# The wiring: your node, and nothing else, for that network.
awk '/static func rpc\(_ net: Network/,/^    }$/' "$CHAIN" > "$TMP/rpc.swift"
grep -q 'if let own = OwnNodeStore.settings.address(for: net.chainId) {' "$TMP/rpc.swift" \
  || { echo "✗ the account's reads no longer ask your node first (prd §1517)"; exit 1; }
awk '/if let own = OwnNodeStore/,/^        }$/' "$TMP/rpc.swift" | grep -q 'throw Failure' \
  || { echo "✗ a network with your node falls through to Casberi's list — your address would go where you said not to"; exit 1; }
grep -q 'as: OwnNodeStore.service' "$TMP/rpc.swift" || { echo "✗ requests to your node no longer name their service to the ledger"; exit 1; }
grep -q 'if case .answers = verdict, let url {' "$PAGE" || { echo "✗ an address is saved without answering its check"; exit 1; }
grep -q 'service: "Your own node"' "$REACH" || { echo "✗ NetworkReach no longer declares your own node's family"; exit 1; }
true
