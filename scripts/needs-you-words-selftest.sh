#!/bin/zsh
# Under the Wallet's "Needs you" heading a row does not say it needs you
# (prd §1378), compiled AS SHIPPED: `Model/NeedsYouWords.swift` is
# Foundation-only, so this compiles it whole.
#
# Every failure reads as an ordinary row:
#   • "Needs attention · £200 → €235" under "Needs you" (Wise's stuck word kept)
#   • a Safe line of "your signature is needed · Everyday" (Safe's clause kept)
#   • a Safe row losing "2 of 3 signatures collected on …" (the title cut too)
#   • a row with no name at all, when the title was only the stuck word
#   • the Feed losing those words, where the title still has to carry them
# and the drift that no build sees: a bridge rewording its phrase so the trim
# silently stops matching, or the rows no longer reading the rule.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/NeedsYouWords.swift"
WISE="Casberi/Casberi/Model/WiseBridge.swift"
SAFE="Casberi/Casberi/Model/SafeBridge.swift"
ROWS="Casberi/Casberi/Screens/ShapedRows.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// Wise: the amounts lead.
check(NeedsYouWords.name("Needs attention · £200 → €235 · Deposit") == "£200 → €235 · Deposit",
      "a stuck Wise transfer leads with its amounts")
check(NeedsYouWords.name("Sending · £200 → €235") == "Sending · £200 → €235",
      "a transfer that is not stuck keeps its word")
check(NeedsYouWords.name("Needs attention") == "Needs attention",
      "a title that is only the word keeps it: never a nameless row")
check(NeedsYouWords.name("Needs attention ·  ") == "Needs attention ·  ",
      "a word and nothing after it keeps it too")
check(NeedsYouWords.name("Rent — Needs attention · later") == "Rent — Needs attention · later",
      "the word is dropped only where it leads")

// Safe: the clause goes, the count stays (the count is the title, not the clause).
check(NeedsYouWords.qualifier("your signature is needed") == nil,
      "Safe's clause is dropped")
check(NeedsYouWords.qualifier("Your signature is needed ") == nil,
      "in any case and with stray space")
check(NeedsYouWords.qualifier("waiting on others") == "waiting on others",
      "a clause that says something else stays")
check(NeedsYouWords.qualifier(nil) == nil, "no clause stays none")
check(NeedsYouWords.name("2 of 3 signatures collected on a transfer of 1,500 USDC")
      == "2 of 3 signatures collected on a transfer of 1,500 USDC",
      "the Safe title, the a-of-b count, is never touched")

if failures > 0 { print("\(failures) failed"); exit(1) }
SWIFT

swiftc -O -o "$work/t" "$SRC" "$work/main.swift" 2>"$work/err" || { cat "$work/err"; fail "needs-you-words did not compile"; }
"$work/t" || fail "needs-you-words cases failed"

# The phrases the trim matches are the ones the bridges write.
grep -q 'String(localized: "Needs attention · \\(amounts)' "$WISE" \
    || fail "WiseBridge no longer leads a stuck transfer with \"Needs attention · \" — NeedsYouWords.stuck must follow it"
grep -q 'static var stuckTag: String { String(localized: "Needs attention") }' "$WISE" \
    || fail "WiseBridge.stuckTag changed — NeedsYouWords.stuck must follow it"
grep -q 'String(localized: " — your signature is needed")' "$SAFE" \
    || fail "SafeBridge no longer appends \" — your signature is needed\" — NeedsYouWords.yourSignature must follow it"
grep -q 'String(localized: "your signature is needed")' "$SRC" \
    || fail "NeedsYouWords.yourSignature no longer spells SafeBridge's clause"

# The rows read the rule, and only under the heading.
grep -q 'underNeedsYou ? NeedsYouWords.name(seam.name) : seam.name' "$ROWS" \
    || fail "ShapedRows no longer trims the name under Needs you"
grep -q 'underNeedsYou ? NeedsYouWords.qualifier(seam.line) : seam.line' "$ROWS" \
    || fail "ShapedRows no longer trims the clause under Needs you"
grep -q 'line(project: project, leader: leader, qualifier: qualifier)' "$ROWS" \
    || fail "ShapedRows draws the untrimmed clause"
grep -q 'environment(\\.dsUnderNeedsYou, label == Self.needsYouGroup)' "$ROOM" \
    || fail "the Wallet's day sections no longer mark the Needs you rows"
grep -q 'underNeedsYou: label == Self.needsYouGroup)' "$ROOM" \
    || fail "the Wallet's move row is no longer told it stands under Needs you"
grep -q 'let who = underNeedsYou ? NeedsYouWords.name(named) : named' "$ROOM" \
    || fail "the Wallet's move row no longer trims the stuck word"
grep -q 'static let defaultValue = false' "$ROOM" \
    || fail "dsUnderNeedsYou is on by default — the Feed would lose the words"

print "✓ needs-you-words self-test passed"
