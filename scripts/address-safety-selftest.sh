#!/bin/zsh
# Casberi address-safety self-test — verifies the SHIPPED
# Casberi/Casberi/Model/AddressSafety.swift by compiling the ACTUAL source
# file with a test driver appended, never a duplicated copy.
#
# Why this exists rather than a sim check: both functions here are pure, and
# both fail SILENTLY and WRONGLY when they drift. A checksum check that
# answers `unavailable` for everything simply never warns; a lookalike test
# with a mis-shaped display key finds nothing. Neither shows up on screen,
# because "no warning" is the normal, correct, overwhelmingly common result.
# The only way to know they work is to feed them a case that MUST warn.
#
# Pure, local, deterministic — no network. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/AddressSafety.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
for f in "$SRC" "$KECCAK"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# AddressSafety leans on three one-line helpers that live in files too big to
# compile standalone here (ENS/SNS both carry resolvers; WalletStore is an
# @Observable store). They're shimmed below — so these guards fail the run if
# the shipped originals ever stop matching what the shim mirrors. A shim that
# silently disagrees with production would make this whole harness a liar.
grep -q 'return "\\(address.prefix(6))…\\(address.suffix(4))"' \
  Casberi/Casberi/Model/WalletStore.swift \
  || { echo "✗ WalletStore.shortAddress changed shape — update the shim in $0"; exit 1; }
grep -q 'guard t.hasPrefix("0x"), t.count == 42 else { return false }' \
  Casberi/Casberi/Model/ENS.swift \
  || { echo "✗ ENS.isHexAddress changed shape — update the shim in $0"; exit 1; }
grep -q 'guard (32...44).contains(t.count) else { return false }' \
  Casberi/Casberi/Model/SNS.swift \
  || { echo "✗ SNS.isAddress changed shape — update the shim in $0"; exit 1; }

TMP=$(mktemp /tmp/address-safety-selftest.XXXXXX).swift
trap 'rm -f "$TMP"' EXIT

# Dependency shims, mirroring the shipped one-liners the guards above pin.
cat > "$TMP" <<'SWIFT'
import Foundation

enum WalletStore {
    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
enum ENS {
    static func isHexAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        return t.dropFirst(2).allSatisfy { $0.isHexDigit }
    }
}
enum SNS {
    private static let base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    static func isAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...44).contains(t.count) else { return false }
        return t.allSatisfy { base58.contains($0) }
    }
}
/// Only `isAddress` is reached from AddressSafety; a Bitcoin address is
/// base58/bech32 shaped and the real validator is exercised in the app.
enum BitcoinAddress {
    static func isAddress(_ address: String) -> Bool {
        let t = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("bc1") || t.hasPrefix("1") || t.hasPrefix("3")
    }
}
SWIFT

cat "$KECCAK" >> "$TMP"
cat "$SRC" >> "$TMP"

cat >> "$TMP" <<'SWIFT'

// --- self-test driver (appended by scripts/address-safety-selftest.sh) ---
var failures = 0
func expect(_ label: String, _ got: String, _ want: String) {
    if got == want { print("  \u{2713} \(label)") }
    else { print("  \u{2717} \(label): got \(got) want \(want)"); failures += 1 }
}
func verdict(_ a: String) -> String {
    switch AddressSafety.checksum(a) {
    case .verified: return "verified"
    case .failed: return "failed"
    case .unavailable: return "unavailable"
    }
}
func look(_ a: String, _ b: String) -> String { AddressSafety.isLookalike(a, b) ? "yes" : "no" }

print("Checksum:")
// The EIP-55 spec's own vector, correctly cased.
expect("correctly checksummed address verifies",
       verdict("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"), "verified")
// The SAME address with ONE letter's case flipped — a transcription error,
// and the entire reason this check exists.
expect("one flipped character fails",
       verdict("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"), "failed")
// The common case: no case variation carries no checksum. Must be silent,
// NOT a warning — most pasted addresses look like this.
expect("all-lowercase is unavailable, never failed",
       verdict("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"), "unavailable")
expect("all-uppercase is unavailable (indistinguishable from shouting)",
       verdict("0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED"), "unavailable")
expect("a Solana address has no EIP-55 to check",
       verdict("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"), "unavailable")
expect("a name has no EIP-55 to check", verdict("vitalik.eth"), "unavailable")
expect("empty input is unavailable", verdict(""), "unavailable")

print("Lookalikes:")
// THE ATTACK: first four and last four hex digits match, middle differs.
// Both shorten to 0x5aAeb…eAed, which is all any screen in the app shows.
let real  = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
let fake  = "0x5aaeb0000000000000000000000000000f1beaed"
expect("a poisoned twin is caught", look(real, fake), "yes")
expect("…and the check is symmetric", look(fake, real), "yes")
expect("display forms really do collide",
       (AddressSafety.displayForm(real) ?? "?") + "==" + (AddressSafety.displayForm(fake) ?? "?"),
       "0x5aae…eaed==0x5aae…eaed")
// The false positive that would matter most: an address against ITSELF in
// checksummed form. EIP-55 case is a checksum, not identity — warning here
// would fire on every wallet in the book.
expect("an address is not its own lookalike (checksummed form)",
       look(real, "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"), "no")
expect("an address is not its own lookalike (identical)", look(real, real), "no")
expect("unrelated addresses don't collide",
       look(real, "0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb"), "no")
// Base58 case IS identity — two Solana addresses differing only by case in
// the MIDDLE are DIFFERENT wallets that print the same, so this is a real
// collision, not a folding artifact. (The difference has to sit in the
// hidden middle: a first draft of this vector varied the last character,
// which every screen shows, and the harness correctly said "no".)
let sol     = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
let solTwin = "9WzDXwBbmkg8ZTbNMqUxvqRAyrZzDsGYdLVL9zYtAWWM"
expect("Solana twins collide too", look(sol, solTwin), "yes")
// The per-family asymmetry stated directly: hex folds case (EIP-55 case is
// a checksum), base58 does not (its case IS identity, and folding it would
// merge two different wallets). That `solTwin` above collides at all is the
// proof base58 isn't folded — folded, it would be the same address and the
// answer would be "no".
expect("hex display folds case",
       AddressSafety.displayForm("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") ?? "nil",
       "0x5aae…eaed")
expect("base58 display keeps case", AddressSafety.displayForm(sol) ?? "nil", "9WzDXw…AWWM")
// Names are excluded: two long names sharing a truncation aren't an attack.
expect("names are never lookalikes",
       look("supercalifragilistic1.eth", "supercalifragilistic2.eth"), "no")
expect("a name has no display form",
       AddressSafety.displayForm("vitalik.eth") ?? "nil", "nil")
// Short strings can't hide anything — shortAddress passes them through.
expect("short strings don't collide", look("0xabc", "0xdef"), "no")

if failures == 0 { print("\n✓ address safety: all checks passed") }
else { print("\n✗ address safety: \(failures) failed"); exit(1) }
SWIFT

swift "$TMP"
