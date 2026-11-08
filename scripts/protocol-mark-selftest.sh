#!/bin/zsh
# Casberi protocol-mark self-test — the SHIPPED rule for which protocol's mark
# rides the corner of a wallet row's action glyph (prd §1685):
#
#   Casberi/Casberi/Model/ProtocolMark.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED here.
#
# WHY A HARNESS. Every failure here renders as an ordinary row:
#
#   • a venue that loses its mark (a renamed imageset, a Zerion name with a
#     version suffix) just draws the glyph alone, with nothing broken;
#   • a prefix rule that catches too much puts Safe's mark on a SafePal row,
#     a real brand standing for the wrong company;
#   • a row that lets the mark LEAD again is the confusion the user ruled
#     out: a protocol's circle at a money row's head reads as the token.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MARK="Casberi/Casberi/Model/ProtocolMark.swift"
ASSETS="Casberi/Casberi/Assets.xcassets"
ROW="Casberi/Casberi/Screens/WalletRow.swift"
HISTORY="Casberi/Casberi/Screens/WalletHistoryScreen.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
BADGE="Casberi/Casberi/Design/AssetMark.swift"
LEND="Casberi/Casberi/Screens/MoveLend.swift"
PRIVATE="Casberi/Casberi/Screens/MovePrivate.swift"
LENT="Casberi/Casberi/Screens/FeedScreen+WalletLent.swift"
HELD="Casberi/Casberi/Screens/FeedScreen+WalletPrivate.swift"
BAND="Casberi/Casberi/Screens/ShapedRows.swift"

for f in "$MARK" "$ROW" "$HISTORY" "$ROOM" "$BADGE" "$LEND" "$PRIVATE" "$LENT" "$HELD" "$BAND"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0

# --- the rule, compiled whole ------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failed = 0
func check(_ name: String, _ got: String?, _ want: String?) {
    if got == want { print("  ✓ \(name)") }
    else { print("  ✗ \(name) — got \(got ?? "nil"), want \(want ?? "nil")"); failed += 1 }
}
check("Uniswap", ProtocolMark.mark(forVenue: "Uniswap"), "uniswap")
check("a version suffix (Zerion's names)", ProtocolMark.mark(forVenue: "Uniswap V3"), "uniswap")
check("any case", ProtocolMark.mark(forVenue: "aave v3"), "aave")
check("0xBow's long name before its short one", ProtocolMark.mark(forVenue: "0xBow Privacy Pools"), "privacy-pools")
check("Privacy Pools", ProtocolMark.mark(forVenue: "Privacy Pools"), "privacy-pools")
check("a trailing word (Aztec staking)", ProtocolMark.mark(forVenue: "Aztec staking"), "aztec")
check("CoW Protocol wears CoW Swap's mark", ProtocolMark.mark(forVenue: "CoW Protocol"), "cowswap")
check("ether.fi", ProtocolMark.mark(forVenue: "ether.fi"), "etherfi")
check("a longer word is not the venue (Sparkle)", ProtocolMark.mark(forVenue: "Sparkle"), nil)
check("a joined word is not the venue (Peerless)", ProtocolMark.mark(forVenue: "Peerless"), nil)
check("the chain read is no venue", ProtocolMark.mark(forVenue: "Wallet"), nil)
check("a person is no venue", ProtocolMark.mark(forVenue: "Sam"), nil)
check("a token is no venue", ProtocolMark.mark(forVenue: "USDC"), nil)
check("empty", ProtocolMark.mark(forVenue: "  "), nil)
check("nil", ProtocolMark.mark(forVenue: nil), nil)
check("the counterparty first", ProtocolMark.mark(counterparty: "Uniswap", venue: "Aave", source: "Privacy Pools"), "uniswap")
check("then the program", ProtocolMark.mark(counterparty: "Sam", venue: "Aave", source: "Wallet"), "aave")
check("then the seat", ProtocolMark.mark(counterparty: nil, venue: nil, source: "Privacy Pools"), "privacy-pools")
check("a Wallet row with no venue", ProtocolMark.mark(counterparty: nil, venue: nil, source: "Wallet"), nil)
for v in ProtocolMark.venues { print("MARK \(v.mark)") }
exit(failed == 0 ? 0 : 1)
SWIFT

run_rule() {  # source file → output
  swiftc -O -o "$TMP/rule" "$1" "$TMP/main.swift" 2>"$TMP/swiftc.err" || { cat "$TMP/swiftc.err"; return 2; }
  "$TMP/rule"
}

echo "the venue rule"
if ! run_rule "$MARK" > "$TMP/out"; then
  grep -v '^MARK ' "$TMP/out"; fail=1
else
  grep -v '^MARK ' "$TMP/out"
fi

# --- every listed mark ships ---------------------------------------------------
echo "every venue's mark ships"
for m in $(grep '^MARK ' "$TMP/out" | cut -d' ' -f2 | sort -u); do
  if [[ -f "$ASSETS/brand-$m.imageset/Contents.json" ]]; then echo "  ✓ brand-$m"
  else echo "  ✗ brand-$m.imageset is missing — the row would draw no badge"; fail=1; fi
done

# --- the mutation: the trailing-space rule is what keeps Sparkle out ----------
echo "mutation"
sed 's/venue.hasPrefix(name + " ")/venue.hasPrefix(name)/' "$MARK" > "$TMP/Mutant.swift"
if cmp -s "$MARK" "$TMP/Mutant.swift"; then
  echo "  ✗ the mutation changed nothing — its anchor drifted"; fail=1
elif run_rule "$TMP/Mutant.swift" > /dev/null 2>&1; then
  echo "  ✗ SURVIVED: a bare prefix match passed the rule's tests"; fail=1
else
  echo "  ✓ a bare prefix match is caught"
fi

# --- drift guards: the rule is drawn, on the corner, never leading ------------
echo "drift guards"
guard() {
  if grep -qE -- "$3" "$2"; then echo "  ✓ $1"
  else echo "  ✗ $1 — not found in $2"; fail=1; fi
}
guard_absent() {
  if grep -qE -- "$3" "$2"; then echo "  ✗ $1 — found in $2"; fail=1
  else echo "  ✓ $1"; fi
}
guard "the row's glyph draws the badge, a flag outranking it" "$ROW" \
  '\.protocolBadge\(flagged \? nil : badge\)'
guard "the badge draws at the inline rung" "$BADGE" \
  'frame\(width: DS\.Mark\.inline, height: DS\.Mark\.inline\)'
guard "the history page asks the rule" "$HISTORY" 'badge: ProtocolMark\.mark\('
guard "Activity asks the rule" "$ROOM" 'let carrier = ProtocolMark\.mark\('
guard "Activity's protocol row leads with the action glyph" "$ROOM" \
  'symbol: act\.symbol, tint: Color\(hex: act\.hex\),'
guard_absent "the protocol's mark never leads an Activity row" "$ROOM" \
  '(AssetMark|BridgeIcon)\(name: carrier'
guard "a swap's feed row asks the rule (it carries no direction)" "$BAND" \
  'return ProtocolMark\.mark\(counterparty: thing\.transferCounterparty'
guard "the feed row's carried lead is the action glyph with the badge" "$BAND" \
  'case \.carried\(let mark\):'
guard "Lend's foot credits Aave" "$LEND" 'Text\("Powered by Aave"\)'
guard "the private send's foot credits Privacy Pools (prd §1718)" "$PRIVATE" 'Text\("Powered by Privacy Pools"\)'
guard "Lend's credit wears the mark through Move's one door" "$LEND" 'MoveSentence\.mark\(of: "Aave"\)'
guard "Move's mark door falls back to the rule" \
  "Casberi/Casberi/Screens/MoveSentence.swift" 'ProtocolMark\.mark\(forVenue: service\)'
# No small mark on a Holdings row's second line (prd §1718, user: "even aave
# itself is a token in reality so that can be confusing"): the words carry
# the place, last — "Base · 5.1% · Aave", "Ethereum · 1.5% on Aave · Privacy Pools".
guard_absent "a Lent row's line wears a small mark again (prd §1718)" "$LENT" 'ProtocolInlineMark\('
guard_absent "a private row's line wears a small mark again (prd §1718)" "$HELD" 'ProtocolInlineMark\('
guard "a Lent row's line ends on its place" "$LENT" '"Aave"\]\.compactMap'
guard "a private row's line ends on its place" "Casberi/Casberi/Model/PrivateMoneyStore.swift" 'let place = PrivacyPoolsBridge\.sourceName'
guard_absent "the rule never reads a title (§363)" "$MARK" '\.title'

if (( fail )); then echo "protocol-mark self-test: FAILED"; exit 1; fi
echo "protocol-mark self-test: ok"
