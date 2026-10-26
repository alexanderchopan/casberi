#!/bin/zsh
# Casberi address-tail self-test — the one shortener (prd §1551, user rule
# 2026-10-26: "...xxxx", three ASCII dots and the last four, never both ends):
#
#   Casberi/Shared/AddressTail.swift   compiled WHOLE and unmodified
#
# Every failure here renders as an ordinary row: `0x4b19…e07a` reads fine,
# `…e07a` reads fine, and only a person who made the rule sees it is wrong.
# So the shape is asserted on real ids of every family the app draws (EVM,
# Aztec, Solana, Bitcoin, Logos, a tx hash), then each rule is broken on
# purpose and the run must notice.
#
# The forwarders (`WalletStore.shortAddress`, `LogosWire.short`,
# `YourAccount.short`, `YourAccountPreview.short`, `AztecWire.short`,
# `AztecSignRequest.short`) are pinned to the helper by grep below, so a
# forwarder that grows its own spelling again fails here, not on screen.
# `address-tail-audit.py` is the tree-wide half: no new shortener elsewhere.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

TAIL="Casberi/Shared/AddressTail.swift"
[[ -f "$TAIL" ]] || { echo "✗ $TAIL not found"; exit 1; }

# --- the forwarders say nothing of their own --------------------------------
pin() { grep -qF -- "$2" "$1" || { echo "✗ $1 no longer forwards to AddressTail ($3)"; exit 1; }; }
pin Casberi/Casberi/Model/WalletStore.swift        '        AddressTail.short(address)'                      "WalletStore.shortAddress"
pin Casberi/Casberi/Model/LogosWire.swift          'static func short(_ id: String) -> String { AddressTail.short(id, wholeUpTo: 10) }' "LogosWire.short"
pin Casberi/Casberi/Model/YourAccount.swift        'static func short(_ address: String) -> String { AddressTail.short(address, wholeUpTo: 4) }' "YourAccount.short"
pin Casberi/Casberi/Model/YourAccountPreview.swift 'static func short(_ address: String) -> String { AddressTail.short(address) }' "YourAccountPreview.short"
pin Casberi/Casberi/Model/AztecWire.swift          'static func short(_ address: String) -> String { AddressTail.short(address) }' "AztecWire.short"
pin Casberi/Casberi/Model/AztecSignRequest.swift   'AddressTail.short(normalized(hex), wholeUpTo: 20)'      "AztecSignRequest.short"
echo "✓ the six forwarders pass straight through"

TMP=$(mktemp -d /tmp/address-tail-selftest.XXXXXX)
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("  \(ok ? "✓" : "✗") \(what)")
    if !ok { failures += 1 }
}

let ids: [(String, String)] = [
    ("EVM", "0x4B19aE0c7d2F8e1a9b3C5D6e7F8091a2B3c4e07a"),
    ("Aztec", "0x07ba1234567890abcdef00000000000000000000000000000000000000008416"),
    ("Solana", "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"),
    ("Bitcoin", "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"),
    ("Logos", "CbgR6tj3Lp2x8E1WnvQZu5qGxHkF7mYcD9sPaTbSr2r"),
    ("a tx hash", "0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060"),
]
for (family, id) in ids {
    let s = AddressTail.short(id)
    check(s == "..." + String(id.suffix(4)), "\(family): three dots, then the last four (\(s))")
    check(!s.contains("…"), "\(family): no … character")
    check(!s.dropFirst(3).contains("."), "\(family): the dots once, at the head only")
    check(!s.contains(String(id.prefix(4))) || id.prefix(4) == id.suffix(4), "\(family): never the head")
    check(AddressTail.isTail(s), "\(family): reads as a tail, not a name")
}

// Whole when it is short enough to show whole.
check(AddressTail.short("0x12") == "0x12", "a four-character id is whole")
check(AddressTail.short("0x1234567890") == "0x1234567890", "twelve or fewer is whole by default")
check(AddressTail.short("0x12345678901") == "...8901", "past the floor it is cut")
check(AddressTail.short("abcdefghijk", wholeUpTo: 10) == "...hijk", "a caller's floor is honoured")
check(AddressTail.short("abcdefghij", wholeUpTo: 10) == "abcdefghij", "…at the floor it is whole")
check(AddressTail.short("abcde", wholeUpTo: 4) == "...bcde", "a floor of four cuts five")
check(AddressTail.short("abcd", wholeUpTo: 0) == "abcd", "never a tail longer than the id")
check(AddressTail.short("") == "", "empty is empty")

// A name is not a tail; both spellings of a tail are.
check(AddressTail.isTail("…e07a"), "the … spelling written before 2026-10-26 still reads as a tail")
check(!AddressTail.isTail("Mom"), "a name is not a tail")
check(!AddressTail.isTail("vitalik.eth"), "an ENS name is not a tail")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "AddressTail, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "$TAIL" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1
fi
"$TMP/run" || exit 1

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$TAIL" "$WORK/AddressTail.swift"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AddressTail.swift" <<'PY'
import os, sys
p = sys.argv[1]; s = open(p).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, t, 1))
PY
  then echo "  ✗ $name — the mutation did not apply"; exit 1; fi
  if cmp -s "$TAIL" "$WORK/AddressTail.swift"; then echo "  ✗ $name — changed nothing"; exit 1; fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/AddressTail.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "the … character back" \
  'static let dots = "..."' \
  'static let dots = "…"'
mutate "head and tail (0x4b19…e07a)" \
  'return dots + String(id.suffix(shown))' \
  'return String(id.prefix(6)) + dots + String(id.suffix(shown))'
mutate "bare four, no mark" \
  'return dots + String(id.suffix(shown))' \
  'return String(id.suffix(shown))'
mutate "the head instead of the tail" \
  'return dots + String(id.suffix(shown))' \
  'return dots + String(id.prefix(shown))'
mutate "six of the tail" \
  'static let shown = 4' \
  'static let shown = 6'
mutate "the caller's floor ignored" \
  'guard id.count > max(wholeUpTo, shown) else { return id }' \
  'guard id.count > max(12, shown) else { return id }'
mutate "a short id cut anyway" \
  'guard id.count > max(wholeUpTo, shown) else { return id }' \
  'guard id.count > shown else { return id }'
mutate "the old spelling read as a name" \
  'text.hasPrefix(dots) || text.hasPrefix("…")' \
  'text.hasPrefix(dots)'

echo "✓ address-tail self-test passed"
