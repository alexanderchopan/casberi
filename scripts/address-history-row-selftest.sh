#!/bin/zsh
# Casberi address-history-row self-test — the SHIPPED split behind every row on
# an address's own profile (prd §443, 2026-08-22):
#
#   Casberi/Casberi/Model/AddressHistoryRow.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. Every failure here renders as a perfectly ordinary row, on the
# one screen in the app where you decide whether to trust somebody:
#
#   · a SENT transfer shown with a `+` — the relationship reading backwards,
#     in the column whose whole job is direction, and the row is otherwise
#     immaculate
#   · a spoofed token's trailing phishing domain promoted into the symbol slot,
#     which is the ONE slot §374's mask leaves visible (the `MoneyReceipt.split`
#     lesson, §363, in a second file)
#   · a stamped "-0.25" printing "−−0.25", which reads as a rendering fault on
#     a number somebody is checking
#   · §374 on, and the figure surviving anyway — the privacy control whose
#     failure mode is "shows it anyway, invisibly", which is worse than one
#     that hides too much
#   · §374 on, and the SIGN going with the figure, so a masked row no longer
#     says which way the money ran (a fact that is not a balance)
#   · an approval — no stamped transfer — silently losing its sentence and
#     rendering as a bare verb with no amount and no subject
#
# Nothing in a build, a screen sweep or any static audit can see one of these.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROW="Casberi/Casberi/Model/AddressHistoryRow.swift"
VIEWS="Casberi/Casberi/Screens/AddressBookViews.swift"
PRIVACY="Casberi/Casberi/Model/BalancePrivacy.swift"
for f in "$ROW" "$VIEWS" "$PRIVACY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. Both files DOCUMENT what
# they must never do — `AddressHistoryRow`'s own header explains at length why
# it never reaches for `DS.confirm`/`DS.destructive`, and names them — so a
# guard grepping raw source fires against the prose explaining it (the
# Obsidian/Cursor lesson, earned on several harnesses' own first runs).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*///?.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$VIEWS" > "$TMP/views-bare.swift"
strip_comments "$ROW"   > "$TMP/row-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. A perfect split is
# worthless if the card never calls it, if it hands it a title it parsed back
# out of prose, or if the view paints a verdict over the fact.

grep -q 'AddressHistoryRow.parts(direction: thing.transferDirection,' "$VIEWS" \
  || { echo "✗ the card no longer takes its row split from AddressHistoryRow — the split would be the view's own and nothing could test it"; exit 1; }
grep -q 'fallbackTitle: WalletValue.title(thing)' "$VIEWS" \
  || { echo "✗ the fallback title no longer comes from WalletValue.title — an unsplittable row would print its amount straight through §374's mask"; exit 1; }
grep -q 'hidden: BalancePrivacy.shared.hidden' "$VIEWS" \
  || { echo "✗ the row split is no longer handed the §374 gate — every amount would render in the clear"; exit 1; }
grep -q 'mask: BalancePrivacy.mask' "$VIEWS" \
  || { echo "✗ the row split no longer uses the shared mask constant — a second spelling would drift from every other masked figure in the app"; exit 1; }

# NO VERDICT COLOUR (§443). Direction is a fact on this screen, not a win or a
# loss: `+120 USDC` in confirm-green congratulates you for your mother paying
# you back, and congratulates you identically for a stranger dusting your
# wallet. Anchored to the row builder, not the whole file — the lookalike band
# on the same screen legitimately uses `DS.destructive`, and a whole-file grep
# would either fail forever or have to be switched off.
python3 - "$TMP/views-bare.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'private func historyRow\(.*?\n    \}\n', src, re.S)
if not m:
    sys.stderr.write("✗ historyRow no longer exists — the record's row builder moved\n"); sys.exit(1)
body = m.group(0)
for token in ("DS.confirm", "DS.destructive"):
    if token in body:
        sys.stderr.write("✗ the history row paints %s — direction is a fact on this screen, not a verdict (§443)\n" % token); sys.exit(1)
PY

# The split must never reach for a title. §363's rule, and the reason `parts`
# takes stamped fields: a localized title reorders, and a row landed before
# those fields existed carries its number only inside prose.
for bad in 'title.hasPrefix' 'title.contains' 'title.range(of:'; do
  if grep -qF -- "$bad" "$TMP/row-bare.swift"; then
    echo "✗ AddressHistoryRow parses a title ($bad) — facts come from stamped fields (§363)"; exit 1
  fi
done

# The mask constant still exists to be passed.
grep -q 'static let mask = "••••"' "$PRIVACY" \
  || { echo "✗ BalancePrivacy.mask moved — the card passes it by name"; exit 1; }

# --- fixtures ---------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ got: String, _ want: String) {
    if got != want {
        FileHandle.standardError.write("FAIL \(label): got \(got) want \(want)\n".data(using: .utf8)!)
        failures += 1
    }
}
func p(_ direction: String?, _ amount: String?,
       _ fallback: String = "Approved Unlimited USDC",
       hidden: Bool = false) -> AddressHistoryRow.Parts {
    AddressHistoryRow.parts(direction: direction, amount: amount,
                            fallbackTitle: fallback, hidden: hidden, mask: "••••")
}

// ── The two directions, which is the whole point of the trailing column ──
check("sent lead",   p("sent", "0.25 ETH").lead, "Sent")
check("sent amount", p("sent", "0.25 ETH").amount ?? "nil", "\u{2212}0.25 ETH")
check("recv lead",   p("received", "120 USDC").lead, "Received")
check("recv amount", p("received", "120 USDC").amount ?? "nil", "+120 USDC")

// A TRUE MINUS, matching the net line one section up. A hyphen there and a
// minus here is two glyphs for one idea, eight points apart on one screen.
check("minus is U+2212", String(p("sent", "1 ETH").amount!.first!), "\u{2212}")

// ── Not a transfer: the sentence survives whole, and states no amount ──
check("approval lead",  p(nil, nil).lead, "Approved Unlimited USDC")
check("approval amount", p(nil, nil).amount ?? "nil", "nil")
// Direction stamped but no amount (and the reverse) — both are half a transfer
// and neither may be shown as one.
check("no amount",    p("sent", nil).lead, "Approved Unlimited USDC")
check("no direction", p(nil, "0.25 ETH").lead, "Approved Unlimited USDC")
check("blank amount", p("sent", "   ").lead, "Approved Unlimited USDC")
// An unknown direction word is NOT silently treated as inbound.
check("unknown direction", p("swapped", "0.25 ETH").lead, "Approved Unlimited USDC")

// ── §374: the sign survives, the figure does not, the symbol does ──
check("hidden sent",  p("sent", "0.25 ETH", hidden: true).amount ?? "nil", "\u{2212}•••• ETH")
check("hidden recv",  p("received", "120 USDC", hidden: true).amount ?? "nil", "+•••• USDC")
// Hidden AND unsymbolled — still signed, because direction is not a balance.
check("hidden bare",  p("sent", "0.25", hidden: true).amount ?? "nil", "\u{2212}••••")
// The fallback title is handed in ALREADY gated, so this type must not mask it
// a second time (that would double-mask "••••" into itself and, worse, would
// mask a title `WalletValue` deliberately left alone).
check("hidden fallback untouched", p(nil, nil, "Approved Uniswap", hidden: true).lead,
      "Approved Uniswap")

// ── The symbol slot: §363's rule, because it is what the mask leaves visible ──
check("plain symbol",   AddressHistoryRow.split("0.9962 ETH").symbol ?? "nil", "ETH")
check("plain figure",   AddressHistoryRow.split("0.9962 ETH").figure, "0.9962")
// Grouped figures keep their separators — `WalletIngest.format` groups by
// locale, so a split that required a bare Double would drop every large amount.
check("grouped figure", AddressHistoryRow.split("1,200 USDC").figure, "1,200")
check("grouped symbol", AddressHistoryRow.split("1,200 USDC").symbol ?? "nil", "USDC")
// A phishing domain in the tail is NOT a symbol.
check("domain refused", AddressHistoryRow.split("4,672 gitos.org").symbol ?? "nil", "nil")
check("domain whole",   AddressHistoryRow.split("4,672 gitos.org").figure, "4,672 gitos.org")
// Too long, too short, and digits in the tail — each refused, each returned whole.
check("long tail refused",  AddressHistoryRow.split("5 ABCDEFGHIJKLM").symbol ?? "nil", "nil")
check("short tail refused", AddressHistoryRow.split("5 X").symbol ?? "nil", "nil")
check("digit tail refused", AddressHistoryRow.split("5 W3T").symbol ?? "nil", "nil")
// No space at all: the whole string is the figure.
check("no space", AddressHistoryRow.split("500").figure, "500")
check("no space symbol", AddressHistoryRow.split("500").symbol ?? "nil", "nil")

// ── A sign already on the stamped string is stripped, never doubled ──
check("stamped hyphen",  p("sent", "-0.25 ETH").amount ?? "nil", "\u{2212}0.25 ETH")
check("stamped minus",   p("sent", "\u{2212}0.25 ETH").amount ?? "nil", "\u{2212}0.25 ETH")
check("stamped plus",    p("received", "+120 USDC").amount ?? "nil", "+120 USDC")

// ── Determinism: the same row twice is the same row ──
check("stable", p("sent", "0.25 ETH").amount ?? "a", p("sent", "0.25 ETH").amount ?? "b")

if failures > 0 {
    FileHandle.standardError.write("\(failures) assertion(s) failed\n".data(using: .utf8)!)
    exit(1)
}
print("  \(31) assertions pass")
SWIFT

echo "Compiling the shipped source WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$ROW" "$TMP/main.swift" 2>&1 | sed 's/^/  /'
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each of these renders as a perfectly
# ordinary row.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$ROW" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations — each is a row that looks completely normal:"

# The relationship, reading backwards.
mutate "direction inverts" \
  'let received = direction == "received"' \
  'let received = direction == "sent"'
# A sent transfer wearing a plus, which on a profile is the difference between
# somebody who pays you and somebody you pay.
mutate "the sign stops following direction" \
  'let sign = received ? "+" : "\u{2212}"' \
  'let sign = "+"'
# §374 on, and the figure printed anyway — the privacy control that shows it
# anyway, invisibly.
mutate "the mask stops being applied" \
  'let shown = hidden ? mask : figure' \
  'let shown = figure'
# §374 on, and a masked row that no longer says which way the money ran.
mutate "the sign goes with the figure" \
  'guard let symbol else { return Parts(lead: verb, amount: sign + shown) }' \
  'guard let symbol else { return Parts(lead: verb, amount: shown) }'
# A spoofed token's phishing domain promoted into the one slot the mask leaves
# visible — the §363 lesson, in a second file.
mutate "the symbol stops being letters-only" \
  'tail.count >= 2, tail.count <= 12, tail.allSatisfy(\.isLetter)' \
  'tail.count >= 2'
# An unknown direction word treated as a transfer, so a swap renders as an
# inbound payment from the person whose profile you are reading.
mutate "any direction word counts as a transfer" \
  'guard let direction, direction == "sent" || direction == "received",' \
  'guard let direction, !direction.isEmpty,'
# Half a transfer shown as a whole one: a stamped direction with no amount
# renders as a bare "Sent" with nothing beside it.
mutate "a missing amount stops falling back" \
  'let amount, !amount.trimmingCharacters(in: .whitespaces).isEmpty' \
  'let amount, amount.isEmpty || !amount.isEmpty'
# "−−0.25", on a number somebody is checking.
mutate "an already-signed amount doubles its sign" \
  'while let first = out.first, first == "-" || first == "+" || first == "\u{2212}" {' \
  'while false {'
# An approval losing its sentence — a bare verb with no amount and no subject.
mutate "an unsplittable row loses its title" \
  'else { return Parts(lead: fallbackTitle, amount: nil) }' \
  'else { return Parts(lead: "", amount: nil) }'

echo ""
echo "address-history-row-selftest: OK — assertions pass and every mutation is caught."
