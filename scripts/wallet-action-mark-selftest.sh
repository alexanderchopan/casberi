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
#     word eight points to its right, on a ledger;
#   • the default arm returning a symbol instead of nil, which claims a shape
#     for every swap, wrap, stake and self-move this deliberately refuses to
#     guess at.
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
guard "WalletRow.Mark.kind carries the symbol through" "$ROW" \
  'KindGlyph\(kind: kind, size: Self\.markSize, symbol: symbol\)'
guard "the wallet history screen asks for the action mark" "$HISTORY" \
  'WalletActionMark\.symbol\('
guard "an address's own history asks for it too" "$BOOK" \
  'WalletActionMark\.symbol\('

# The reader whose vocabulary this ruling widened. `activityRows` used to
# accept any non-empty direction and print everything that was not "received"
# as "Sent" — which for a mint is a wrong verb, an empty amount and no
# counterparty.
guard "the gen-UI activity rows gate on the two DIRECTIONAL values" "$ASKS" \
  'dir == WalletActionMark\.sent \|\| dir == WalletActionMark\.received'

# NEGATIVES, over the comment-stripped copy.
# §443, mechanically: the shape differs, the hue is the kind's. A mark that
# tints an inbound transfer green congratulates you for being dusted.
guard_absent "the mark never names a state colour" "$TMP/mark.nc" \
  'DS\.(confirm|destructive|attention)'
# §363: facts come from stamped fields, never from a localized title.
guard_absent "the mark never reads a title" "$TMP/mark.nc" \
  '\.(title|hasPrefix\("Sent|hasPrefix\("Minted)'
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
func mark(_ direction: String?, _ ref: String?) -> String? {
    WalletActionMark.symbol(direction: direction, sourceRef: ref)
}

let transfer = "wallet:eth-mainnet:0xabc:0"
print("the four actions that earn a mark of their own:")
expect("a send points away", mark("sent", transfer), "arrow.up.right")
expect("a receipt points back", mark("received", transfer), "arrow.down.left")
expect("a mint makes something exist", mark("minted", transfer), "sparkles")
expect("a burn destroys it", mark("burned", transfer), "flame")

print("the grant, which is not an exchange:")
expect("an approval is read off its namespace",
       mark(nil, "wallet:approval:eth-mainnet:0xabc:3"), "hand.raised")
expect("a Permit2 grant is the same event",
       mark(nil, "wallet:permit2:base-mainnet:0xdef:1"), "hand.raised")
// The namespace is the stronger fact: it says what the row IS.
expect("the namespace beats a direction that arrives beside it",
       mark("sent", "wallet:approval:eth-mainnet:0xabc:3"), "hand.raised")
// A PREFIX, never a contains — a ref that merely mentions the word is not one.
expect("the namespace must LEAD the ref",
       mark(nil, "wallet:eth-mainnet:wallet:approval:0xabc"), nil)

print("everything it deliberately refuses to guess:")
// Each of these is genuinely two-legged, which is what ⇄ says. None of them is
// separable from the others by any stamped fact.
expect("a swap keeps the kind's own mark", mark(nil, transfer), nil)
expect("a self-move keeps it", mark(nil, "wallet:eth-mainnet:0x1:2"), nil)
expect("a Solana move keeps it", mark(nil, "wallet:sol:5xy"), nil)
expect("a Peer fill keeps it", mark(nil, "peer:buy:0xabc"), nil)
expect("a pool deposit keeps it", mark(nil, "privacypools:dep:0xabc"), nil)
// A mint landed before the stamp existed. There is nothing on such a row that
// separates it from a burn, and the title is the one place this may not look —
// so the generic mark stands rather than a coin flip.
expect("a mint from before the stamp keeps the generic mark", mark(nil, transfer), nil)
expect("a row with no ref at all is not an approval", mark(nil, nil), nil)
expect("an unknown future value degrades rather than guessing",
       mark("teleported", transfer), nil)
expect("an empty direction is not a send", mark("", transfer), nil)

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

// EVERY MARK IS DISTINCT. The whole complaint was a column of one repeated
// glyph, so two actions resolving to the same symbol is this feature failing
// in exactly its own terms — and it is the shape a careless edit takes.
let all = [mark("sent", transfer), mark("received", transfer),
           mark("minted", transfer), mark("burned", transfer),
           mark(nil, "wallet:approval:x:y:1")].compactMap { $0 }
expect("five actions, five different marks", String(Set(all).count), String(all.count))
// And none of them may be the kind's own, or that action is indistinguishable
// from the generic bucket it was pulled out of.
expect("none of them is the kind's own two-way arrow",
       all.contains("arrow.left.arrow.right") ? "collides" : "distinct", "distinct")

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
  'if isApprovalRef(sourceRef) { return "hand.raised" }' \
  'if false { return "hand.raised" }'

# 2. Only the first namespace honoured, so every Permit2 grant goes quiet.
mutate "only one of the two grant namespaces matched" \
  'approvalRefPrefixes.contains { ref.hasPrefix($0) }' \
  'ref.hasPrefix(approvalRefPrefixes[0])'

# 3. A prefix test loosened to a substring — a ref that merely mentions the
#    namespace becomes a grant.
mutate "the namespace matched anywhere in the ref" \
  'ref.hasPrefix($0)' 'ref.contains($0)'

# 4. The mark saying the opposite of the word beside it.
mutate "sent and received swapped" \
  'case sent:     return "arrow.up.right"' \
  'case sent:     return "arrow.down.left"'

# 5. Same, one action over.
mutate "a mint drawn as a burn" \
  'case minted:   return "sparkles"' \
  'case minted:   return "flame"'

# 6. The refusal removed — every swap, wrap, stake and self-move now claims a
#    shape nothing on the row supports.
mutate "the default arm claiming a shape it cannot know" \
  'default:       return nil' \
  'default:       return "sparkles"'

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

echo
echo "✓ wallet action mark: all checks passed"
