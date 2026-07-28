#!/bin/zsh
# Casberi Keccak-256 self-test — verifies the SHIPPED
# Casberi/Casberi/Model/Keccak256.swift against ground truth (raw hashes
# cross-checked against pycryptodome) and the EIP-55 spec's own four
# published test vectors, by running the ACTUAL source file with a test
# driver appended — never a duplicated copy. A hand-rolled crypto primitive
# that silently drifted from a separately-maintained test would be worse
# than no primitive: a wrong checksum reads as a different-but-valid
# address, no crash — and a wrong Safe/wallet label rides along with it.
#
# Pure, local, deterministic — no network, no third-party host. Exit
# non-zero on failure: unlike live-integrations.sh this isn't measuring a
# third party, so a red result IS a real break, not a warning.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/Keccak256.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }

TMP=$(mktemp /tmp/keccak256-selftest.XXXXXX).swift
trap 'rm -f "$TMP"' EXIT

cat "$SRC" > "$TMP"
cat >> "$TMP" <<'SWIFT'

// --- self-test driver (appended by scripts/keccak256-selftest.sh, not part of the shipped file) ---
var failures = 0
func expect(_ label: String, _ got: String, _ want: String) {
    if got == want { print("  \u{2713} \(label)") }
    else { print("  \u{2717} \(label): got \(got) want \(want)"); failures += 1 }
}

// Raw hash, cross-checked against pycryptodome's Keccak (digest_bits=256).
expect("keccak256(\"\")", Keccak256.hexString(Keccak256.hash([])),
       "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
expect("keccak256(\"abc\")", Keccak256.hexString(Keccak256.hash(Array("abc".utf8))),
       "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")

// The EIP-55 spec's own four published test vectors.
expect("EIP55 #1", EIP55.checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"),
       "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
expect("EIP55 #2", EIP55.checksum("0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359"),
       "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359")
expect("EIP55 #3", EIP55.checksum("0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb"),
       "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB")
expect("EIP55 #4", EIP55.checksum("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb"),
       "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb")

// WETH — matches what api.safe.global actually accepted live (measured
// 2026-07-28: lowercase and all-caps both 422'd; this exact mixed-case
// form got the honest 404).
expect("WETH (live api.safe.global vector)",
       EIP55.checksum("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
       "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

// The two invariants SafeBridge's callers rely on.
expect("idempotent on an already-checksummed address",
       EIP55.checksum(EIP55.checksum("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")),
       "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
expect("non-hex input passes through unchanged", EIP55.checksum("toly.sol"), "toly.sol")

if failures > 0 {
    print("\n\(failures) FAILURE(S)")
    exit(1)
} else {
    print("\nALL PASS (7 vectors) — Keccak256.swift matches ground truth")
}
SWIFT

swift "$TMP"
