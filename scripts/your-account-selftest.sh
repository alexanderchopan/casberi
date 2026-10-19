#!/bin/zsh
# Your account (prd §1421, §1422) — the address and the Move tab's gate.
#
# The account's address is computed with no network (`YourAccount.address`),
# so a wrong byte anywhere in the initializer or the pinned creation code
# would hand out an address nobody controls, silently. This pins it to the
# address SafeProxyFactory 1.4.1's own simulated create returned for the same
# key on Base and on Ethereum (2026-10-19), and pins the creation code to the
# bytes the factory serves. It also holds the Move tab to DEBUG until the
# account can send: a release build may not offer an address it cannot move.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
MOVE="Casberi/Casberi/Screens/MoveScreen.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
for f in "$ACCOUNT" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$MOVE" "$TABS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/your-account-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The key: P-256 from sha256("casberi your-account selftest"); its address,
# as Base's and Ethereum's factory answered for the same initializer.
cat > "$TMP/main.swift" <<'EOF'
import Foundation
let x = SafeABI.hexBytes("401388e23199fca944d7348204397880c16a2755e94b1ad9f8e261a3baed3675")!
let y = SafeABI.hexBytes("77003361c4e50ee89f7df0c66b9fe9a69569d96eb353bac1e978f2b3e73b041f")!
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("✗ " + what); bad += 1 } }
let want = "0x09930469ea9d645Bb4141d94af5f2d02A22D29Ce"
check(YourAccount.address(x: x, y: y) == want, "the address is not the factory's (\(YourAccount.address(x: x, y: y) ?? "nil") ≠ \(want))")
check(YourAccount.address(x: x, y: y, salt: 1) != want, "a different salt gave the same address")
check(YourAccount.proxyCreationCode.count == 486, "the creation code is not the factory's 486 bytes")
check(Keccak256.hexString(Keccak256.hash(YourAccount.proxyCreationCode)) == "1856e0ee08399d74e0ea0b03adca210aeade6f748969ac023cdcb4dd62dcaf5f",
      "the creation code changed")
var flipped = y; flipped[31] ^= 1
check(YourAccount.address(x: x, y: flipped) != want, "another key gave the same address")
check(YourAccount.address(x: Array(x.prefix(31)), y: y) == nil, "a short key gave an address")
exit(bad == 0 ? 0 : 1)
EOF
xcrun swiftc -O -o "$TMP/t" "$ACCOUNT" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccount.swift does not compile alone (Foundation and the Safe encoders only)"; exit 1; }
"$TMP/t" || { echo "✗ your account's address arithmetic drifted — see above"; exit 1; }

# The gate: the Move tab is DEBUG-only, and the bar's cases follow it.
grep -q '#if DEBUG' "$MOVE" || { echo "✗ MoveTab.enabled is no longer DEBUG-only — release builds would offer an account that cannot send (prd §1422)"; exit 1; }
grep -q 'MoveTab.enabled ?' "$TABS" || { echo "✗ PlaceTab.allCases no longer reads MoveTab.enabled"; exit 1; }

echo "✓ your account: the address is the factory's, the creation code is pinned, Move stays DEBUG-only"
