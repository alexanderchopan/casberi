#!/bin/zsh
# Casberi wallet-action-mark self-test — the SHIPPED pure logic behind the mark
# a transaction row leads with (2026-08-28, prd §516):
#
#   Casberi/Casberi/Model/WalletActionMark.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED here — no
# extraction, no `private ` stripping, no copy. Every assertion is about the
# bytes the app runs.
#
# WHY A HARNESS. Every failure here renders as a perfectly ordinary row, and
# three of them are actively misleading rather than merely dull:
#
#   • the approval namespace drifting, so a GRANT — the row that says somebody
#     else can move your money — goes back to wearing the two-way exchange
#     arrow, with nothing broken and nothing logged (§311's failure: the room
#     does not break, it goes quiet);
#   • sent and received swapped, which is the mark saying the opposite of the
#     word eight points to its right, on a ledger — and since the user's colour
#     ruling (2026-08-29) that is a RED receipt and a GREEN payment out;
#   • two actions collapsing onto one shape or one hue, which is this feature
#     failing in exactly the terms it was asked for: the complaint was a column
#     of one repeated mark.
#
# Nothing else in the tree can see any of it: the compiler is happy with any
# string that is a symbol name, the screen sweep proves a row painted and never
# that it painted the right glyph, and the two rooms it draws in are reached
# only through a wallet with landed history.
#
# Pure, local, deterministic — no network, no simulator, no wallet. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MARK="Casberi/Casberi/Model/WalletActionMark.swift"
APPROVALS="Casberi/Casberi/Model/WalletApprovals.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
GLYPH="Casberi/Casberi/Design/KindGlyph.swift"
ROW="Casberi/Casberi/Screens/WalletRow.swift"
HISTORY="Casberi/Casberi/Screens/WalletHistoryScreen.swift"
BOOK="Casberi/Casberi/Screens/AddressBookViews.swift"
ASKS="Casberi/Casberi/Model/KeptAskComposers.swift"

for f in "$MARK" "$APPROVALS" "$INGEST" "$GLYPH" "$ROW" "$HISTORY" "$BOOK" "$ASKS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for every NEGATIVE guard below. `WalletActionMark`
# DOCUMENTS the rules it must never break — its header explains §443's
# no-verdict-colour ruling by describing green on an inbound transfer, and
# explains the no-prose rule by naming the title it may not read — so a guard
# grepping raw source fires on the prose explaining it. (The Obsidian/Cursor
# lesson, and it caught this harness on its first run.)
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<!:)//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$MARK" > "$TMP/mark.nc"

# --- drift guards -----------------------------------------------------------
echo "drift guards"
fail=0
guard() {  # name, file, pattern
  if grep -qE -- "$3" "$2"; then echo "  ✓ $1"
  else echo "  ✗ $1 — not found in $2"; fail=1; fi
}
guard_absent() {
  if grep -qE -- "$3" "$2"; then echo "  ✗ $1 — found in $2"; fail=1
  else echo "  ✓ $1"; fi
}

# THE ONE THAT GOES QUIET RATHER THAN BREAKING. `WalletApprovals` builds its ref
# by interpolating the namespace, so the producer and this consumer are two
# files written apart — exactly the §311 shape the ref-shape audit exists for,
# and here the consumer's literal is a prefix test that simply stops matching.
guard "WalletApprovals still stamps the approval/permit2 namespaces" "$APPROVALS" \
  'wallet:\\\(e\.viaPermit2 \? "permit2" : "approval"\):'
guard "both namespaces are still the ones the mark tests" "$TMP/mark.nc" \
  '"wallet:approval:", "wallet:permit2:"'

# The stamp this ruling added, at BOTH sites. Landing gives new mints their
# glyph; the heal gives it to rows already in the store. Losing either leaves
# half the corpus wearing the generic mark with nothing to say so.
guard "the void arm stamps the shape at landing" "$INGEST" \
  'direction = received \? WalletActionMark\.minted : WalletActionMark\.burned'
guard "healLandedTransfers backfills the void shape" "$INGEST" \
  'thing\.transferDirection = leg\.received \? WalletActionMark\.minted'
# Never overwrite a stamped direction — a heal that did would rewrite a real
# transfer's own side.
guard "the heal only fills a NIL direction" "$INGEST" \
  'thing\.transferDirection == nil,'

# The override, and the two rooms that ask for it. A `symbol:` that KindGlyph
# ignores is the whole feature drawing nothing, with every call site intact.
guard "KindGlyph honours the symbol override" "$GLYPH" \
  'Image\(systemName: symbol \?\? kind\.symbol\)'
guard "WalletRow.Mark.kind carries both overrides through" "$ROW" \
  'KindGlyph\(kind: kind, size: Self\.markSize, tint: tint, symbol: symbol\)'
guard "the wallet history screen asks for the action mark" "$HISTORY" \
  'WalletActionMark\.action\('
guard "an address's own history asks for it too" "$BOOK" \
  'WalletActionMark\.action\('

# The reader whose vocabulary this ruling widened. `activityRows` used to
# accept any non-empty direction and print everything that was not "received"
# as "Sent" — which for a mint is a wrong verb, an empty amount and no
# counterparty.
guard "the gen-UI activity rows gate on the two DIRECTIONAL values" "$ASKS" \
  'dir == WalletActionMark\.sent \|\| dir == WalletActionMark\.received'

# NEGATIVES, over the comment-stripped copy.
# The hues are FIXED hexes from the kind palette, never `DS.confirm`/
# `DS.destructive`/`DS.attention` — those are `Color.adaptive` pairs that swap
# per scheme and per Increase Contrast, and `KindGlyph`'s palette is fixed for
# its own stated reason: the mark must not shift. (The user's colour ruling of
# 2026-08-29 retired the previous form of this guard, which forbade colour
# outright; what survives is WHICH colour vocabulary this file may reach for.)
guard_absent "the mark never reaches for an adaptive state colour" "$TMP/mark.nc" \
  'DS\.(confirm|destructive|attention)'
guard_absent "the mark never imports SwiftUI" "$TMP/mark.nc" 'import SwiftUI'
# §363: facts come from stamped fields, never from a localized title.
guard_absent "the mark never reads a title" "$TMP/mark.nc" \
  '\.(title|hasPrefix\("Sent|hasPrefix\("Minted)'
# The hue has to REACH the glyph, or every mark draws in the kind's own amber
# and the ruling is a no-op with every call site intact.
guard "KindGlyph honours the tint override" "$GLYPH" \
  'let base = tint \?\? kind\.hue'
guard "the wallet history screen passes the action's hue" "$HISTORY" \
  'tint: Color\(hex: act\.hex\)'
guard "an address's own history passes it too" "$BOOK" \
  'tint: Color\(hex: act\.hex\)'
[[ $fail -eq 0 ]] || { echo "✗ wallet action mark: drift guards failed"; exit 1; }

# --- assertions -------------------------------------------------------------
cp "$MARK" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func expect(_ label: String, _ got: String?, _ want: String?) {
    if got == want { print("  ✓ \(label)") }
    else { print("  ✗ \(label): got \(got ?? "nil") want \(want ?? "nil")"); failures += 1 }
}
func act(_ direction: String?, _ ref: String?) -> WalletActionMark.Action {
    WalletActionMark.action(direction: direction, sourceRef: ref)
}
func mark(_ direction: String?, _ ref: String?) -> String {
    let a = act(direction, ref)
    return "\(a.rawValue) \(a.symbol) \(a.hex)"
}

let transfer = "wallet:eth-mainnet:0xabc:0"
print("the four actions read off a stamped direction:")
expect("a send points away, in red",
       mark("sent", transfer), "sent arrow.up.right #ff453a")
expect("a receipt points back, in green",
       mark("received", transfer), "received arrow.down.left #30d158")
expect("a mint makes something exist, in gold",
       mark("minted", transfer), "minted sparkles #ffd60a")
expect("a burn destroys it, in orange",
       mark("burned", transfer), "burned flame #ff9f0a")

print("the grant, which is not an exchange:")
expect("an approval is read off its namespace",
       mark(nil, "wallet:approval:eth-mainnet:0xabc:3"), "granted hand.raised #ff375f")
expect("a Permit2 grant is the same event",
       act(nil, "wallet:permit2:base-mainnet:0xdef:1").rawValue, "granted")
// The namespace is the stronger fact: it says what the row IS.
expect("the namespace beats a direction that arrives beside it",
       act("sent", "wallet:approval:eth-mainnet:0xabc:3").rawValue, "granted")
// A PREFIX, never a contains — a ref that merely mentions the word is not one.
expect("the namespace must LEAD the ref",
       act(nil, "wallet:eth-mainnet:wallet:approval:0xabc").rawValue, "exchanged")

print("everything it deliberately refuses to guess, in purple:")
// Each of these is genuinely two-legged, which is what ⇄ says. None of them is
// separable from the others by any stamped fact.
expect("a swap keeps the kind's own arrow",
       mark(nil, transfer), "exchanged arrow.left.arrow.right #bf5af2")
expect("a self-move keeps it", act(nil, "wallet:eth-mainnet:0x1:2").rawValue, "exchanged")
expect("a Solana move keeps it", act(nil, "wallet:sol:5xy").rawValue, "exchanged")
expect("a Peer fill keeps it", act(nil, "peer:buy:0xabc").rawValue, "exchanged")
expect("a pool deposit keeps it", act(nil, "privacypools:dep:0xabc").rawValue, "exchanged")
// A mint landed before the stamp existed. There is nothing on such a row that
// separates it from a burn, and the title is the one place this may not look —
// so the generic mark stands rather than a coin flip.
expect("a mint from before the stamp keeps the generic mark",
       act(nil, transfer).rawValue, "exchanged")
expect("a row with no ref at all is not an approval", act(nil, nil).rawValue, "exchanged")
expect("an unknown future value degrades rather than guessing",
       act("teleported", transfer).rawValue, "exchanged")
expect("an empty direction is not a send", act("", transfer).rawValue, "exchanged")

print("the vocabulary the field carries:")
// Spelled through the constants, so a rename here cannot leave the ingest
// stamping one string while the mark tests another.
expect("sent", WalletActionMark.sent, "sent")
expect("received", WalletActionMark.received, "received")
expect("minted", WalletActionMark.minted, "minted")
expect("burned", WalletActionMark.burned, "burned")
// Every reader of `transferDirection` outside this ruling gates on the two
// originals; these two must never collide with them.
expect("the new values are distinct from the originals",
       String(Set([WalletActionMark.sent, WalletActionMark.received,
                   WalletActionMark.minted, WalletActionMark.burned]).count), "4")

// EVERY MARK IS DISTINCT, IN BOTH CHANNELS. The whole complaint was a column of
// one repeated mark, so two actions sharing a shape OR a hue is this feature
// failing in exactly its own terms — and it is the shape a careless edit takes.
let all = WalletActionMark.Action.allCases
expect("every action has its own shape",
       String(Set(all.map(\.symbol)).count), String(all.count))
expect("every action has its own hue",
       String(Set(all.map(\.hex)).count), String(all.count))
// Every hue must be a real 6-digit hex, or `Color(hex:)` draws whatever its
// own fallback is and the column silently loses the ruling.
for a in all {
    let body = a.hex.dropFirst()
    expect("\(a.rawValue) is a real hex",
           (a.hex.hasPrefix("#") && body.count == 6
            && body.allSatisfy(\.isHexDigit)) ? "yes" : "no", "yes")
}
// The one action that must keep the kind's own arrow, named rather than
// implied: `exchanged` IS the generic bucket.
expect("only the generic bucket wears the two-way arrow",
       String(all.filter { $0.symbol == "arrow.left.arrow.right" }.map(\.rawValue)
                 .joined(separator: ",")), "exchanged")

if failures == 0 { print("\n✓ wallet action mark: all checks passed") }
else { print("\n✗ wallet action mark: \(failures) failed"); exit(1) }
SWIFT

echo
echo "assertions"
if ! swiftc -O -o "$TMP/run" "$TMP/WalletActionMark.swift" "$TMP/main.swift" 2> "$TMP/build.log"; then
  echo "✗ harness build failed:"; grep -E 'error:' "$TMP/build.log" | head -20; exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"
WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$MARK" "$WORK/WalletActionMark.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/WalletActionMark.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/WalletActionMark.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/WalletActionMark.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The grant loses its own mark and rejoins the exchange bucket — silent, and
#    on the row where the mark matters most.
mutate "the approval namespace no longer consulted" \
  'if isApprovalRef(sourceRef) { return .granted }' \
  'if false { return .granted }'

# 2. Only the first namespace honoured, so every Permit2 grant goes quiet.
mutate "only one of the two grant namespaces matched" \
  'approvalRefPrefixes.contains { ref.hasPrefix($0) }' \
  'ref.hasPrefix(approvalRefPrefixes[0])'

# 3. A prefix test loosened to a substring — a ref that merely mentions the
#    namespace becomes a grant.
mutate "the namespace matched anywhere in the ref" \
  'ref.hasPrefix($0)' 'ref.contains($0)'

# 4. The mark saying the opposite of the word beside it. Since the colour
#    ruling this is also a green payment out and a red receipt.
mutate "sent and received swapped" \
  'case sent:     return .sent' \
  'case sent:     return .received'

# 5. Same, one action over.
mutate "a mint read as a burn" \
  'case minted:   return .minted' \
  'case minted:   return .burned'

# 6. The refusal removed — every swap, wrap, stake and self-move now claims a
#    shape and a hue nothing on the row supports.
mutate "the default arm claiming a shape it cannot know" \
  'default:       return .exchanged' \
  'default:       return .minted'

# 7. A nil ref read as a grant, which would put "somebody can spend this" on
#    every row a bridge landed without one.
mutate "a missing ref treated as an approval" \
  'guard let ref else { return false }' \
  'guard let ref else { return true }'

# 8. The stamped vocabulary colliding with the field's originals, which would
#    make a mint read as a send to every OTHER reader in the tree.
mutate "the mint value collided with the original vocabulary" \
  'static let minted = "minted"' \
  'static let minted = "sent"'

# 9. TWO ACTIONS ON ONE SHAPE — the wall re-forming, two rows at a time. This
#    is the complaint this whole section answers, so it must be catchable.
mutate "a send and a swap sharing one arrow" \
  'case .sent:      return "arrow.up.right"' \
  'case .sent:      return "arrow.left.arrow.right"'

# 10. TWO ACTIONS ON ONE HUE, the same failure in the other channel — and the
#     one a shape-only check could never see.
mutate "a send and a receipt sharing one hue" \
  'case .sent:      return "#ff453a"' \
  'case .sent:      return "#30d158"'

# 11. A hue `Color(hex:)` cannot parse. It renders as that initializer's own
#     fallback on every row of that action, with nothing logged.
mutate "an unparseable hue" \
  'case .minted:    return "#ffd60a"' \
  'case .minted:    return "gold"'

# 12. The user's ruling reversed to the shipped default — every mark back in
#     the kind's own amber, with every call site intact.
mutate "the hue collapsed back onto one colour" \
  'case .received:  return "#30d158"' \
  'case .received:  return "#ff453a"'

echo
echo "✓ wallet action mark: all checks passed"
