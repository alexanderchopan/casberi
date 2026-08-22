#!/bin/zsh
# Casberi address-DIFF self-test — the SHIPPED judgement behind the address
# card's look-alike band (prd §444, 2026-08-22):
#
#   Casberi/Casberi/Model/AddressDiff.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. This is the arithmetic behind a SECURITY notice, and every one
# of its failure modes renders as a perfectly ordinary highlighted character:
#
#   · an off-by-one marks the character AFTER the one that differs, so the
#     person compares the wrong column and concludes the two addresses are the
#     same up to a point they are not
#   · the EIP-55 case fold applied when it must not be (base58) hides a real
#     difference; not applied when it must be (hex) invents one, and then two
#     spellings of ONE address wear a red marker at character 3
#   · the head and tail runs overlapping report more shared characters than
#     either string has, which renders as an address with no differing region
#     at all — a warning that shows two identical-looking strings and marks
#     nothing, i.e. the exact failure the band exists to prevent
#   · a bad multi-twin fold dims a character the subject does NOT share with
#     one of the addresses it is being warned about — the one thing this band
#     must never do
#   · a segment run that drops a character silently shortens an address printed
#     in full on the screen whose whole promise is that it prints it in full
#
# Nothing in a build, a screen sweep or any static audit can see one of these.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

DIFF="Casberi/Casberi/Model/AddressDiff.swift"
VIEWS="Casberi/Casberi/Screens/AddressBookViews.swift"
SAFETY="Casberi/Casberi/Model/AddressSafety.swift"
for f in "$DIFF" "$VIEWS" "$SAFETY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. Both files DOCUMENT what
# they must never do — `AddressDiff` explains at length why it does not
# highlight every differing character, `AddressBookViews` explains why the band
# prints both addresses whole — so a guard grepping raw source fires against
# the prose explaining it (the Obsidian/Cursor lesson).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*///?.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$DIFF"  > "$TMP/diff-bare.swift"
strip_comments "$VIEWS" > "$TMP/views-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. Perfect arithmetic is
# worthless if the band draws its own comparison, or decides the case rule with
# its own hex test rather than the app's.

grep -q 'AddressDiff.combined(current.address, against: twins.map(\\.address)' "$VIEWS" \
  || { echo "✗ the band no longer folds every twin into one comparison — it would dim a character the subject does not share with all of them"; exit 1; }
grep -q 'AddressDiff.segments(' "$VIEWS" \
  || { echo "✗ the band no longer renders through AddressDiff.segments — it would be drawing its own runs and nothing could test them"; exit 1; }
grep -q 'ENS.isHexAddress' "$VIEWS" \
  || { echo "✗ the case rule is no longer decided by the app's own hex test — a private one would drift from AddressSafety's"; exit 1; }
grep -q 'allSatisfy(ENS.isHexAddress)' "$VIEWS" \
  || { echo "✗ the fold no longer requires EVERY side to be hex — one base58 twin in the set and case differences it carries would be folded away"; exit 1; }

# The band is reached FROM the book's own look-alike finder, so the pair the
# arithmetic describes is the pair the app warned about.
grep -q 'book.lookalikes(of: current.address)' "$VIEWS" \
  || { echo "✗ the band no longer takes its twins from AddressBook.lookalikes"; exit 1; }
grep -q 'static func displayForm' "$SAFETY" \
  || { echo "✗ AddressSafety no longer states the display form the whole look-alike check keys on"; exit 1; }

# NEGATIVE, on comment-stripped copies. The band prints both addresses WHOLE —
# the one screen that exists to tell two look-alikes apart cannot be the screen
# that truncates them, and a `lineLimit` or a middle truncation on this text is
# exactly that.
grep -q 'truncationMode(.middle)' "$TMP/views-bare.swift" && {
  # `addressChip` legitimately middle-truncates the single address under the
  # name. The BAND must not — so the guard is that the band's own runs are
  # never given one, checked by proximity to the segment draw.
  python3 - "$TMP/views-bare.swift" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
i = src.find("AddressDiff.segments(")
if i == -1:
    sys.stderr.write("segments call vanished\n"); sys.exit(1)
window = src[i:i + 1400]
if "truncationMode" in window or "lineLimit(1)" in window:
    sys.stderr.write("the look-alike band truncates an address\n"); sys.exit(1)
PY
}
grep -q 'lowercased()' "$TMP/diff-bare.swift" || {
  echo "✗ the ASCII case fold is gone — an EIP-55 checksummed address would read as a different address"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

typealias Comparison = AddressDiff.Comparison

// The real poisoning shape: a vanity address matching the last four, which is
// all `WalletStore.shortAddress` shows. Both 42 characters, both hex.
let mine  = "0x9a2E4c7b1f0D3a5E8c6B4d2F1a0C9e8D7b6A44b1"
let twin  = "0x1f7C3e5A9b2D4c6E8a0F1b3D5c7E9a2B4d6C44b1"

print("Comparing")
let c = AddressDiff.compare(mine, with: twin, foldCase: true)
check("the shared head is 0x and nothing more", c.sharedPrefix == 2)
check("the shared tail is what a short form shows", c.sharedSuffix == 4)
check("the length is the subject's own", c.length == mine.count)
check("the pivot is the first character that differs", c.pivot == 2)
check("the position it reports is 1-based", c.pivotPosition == 3)

// Two spellings of ONE address. EIP-55 encodes a checksum in the case of a hex
// address's letters, so this pair is the same money — marking a difference
// here is a false alarm on a security notice.
let checksummed = "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01"
let flat        = "0xabcdef0123456789abcdef0123456789abcdef01"
let folded = AddressDiff.compare(checksummed, with: flat, foldCase: true)
check("a case-only difference is no difference at all", folded.pivot == nil)
check("…and the whole string reads as shared", folded.sharedPrefix == checksummed.count)

// base58 (Solana, Bitcoin) is the opposite: case IS the value.
let unfolded = AddressDiff.compare(checksummed, with: flat, foldCase: false)
check("with the fold off, case is a real difference", unfolded.pivot == 2)

// The fold is deliberately ASCII-only: `AddressSafety` carries a confusables
// table because non-ASCII reaches this app in address-shaped strings, and a
// Unicode-aware fold could map two distinct code points onto one.
let cyrillic = "0x\u{0410}bc"          // Cyrillic А
let latin    = "0xAbc"
check("a confusable is never folded away",
      AddressDiff.compare(cyrillic, with: latin, foldCase: true).pivot == 2)
// The ASCII guard is what makes that true in general, and it needs a character
// that DOES fold onto an ASCII one: U+212A KELVIN SIGN lowercases to "k".
// Without the guard this pair reads as the same string.
let kelvin = "0x\u{212A}bc"
check("a non-ASCII character that folds onto ASCII is still a difference",
      AddressDiff.compare(kelvin, with: "0xkbc", foldCase: true).pivot == 2)

print("")
print("Runs never overlap")
// The shape that renders as an address with NO differing region — a warning
// showing two strings and marking nothing.
let same = AddressDiff.compare("abcdef", with: "abcdef", foldCase: false)
check("identical strings report no differing region", same.pivot == nil)
check("…and the two runs cannot exceed the string", same.sharedPrefix + same.sharedSuffix <= 6)
let oneApart = AddressDiff.compare("aXa", with: "aYa", foldCase: false)
check("a single middle difference is found", oneApart.pivot == 1)
check("…with one character on each side", oneApart.sharedPrefix == 1 && oneApart.sharedSuffix == 1)

// Different lengths: an address that reached the book malformed must not walk
// off either end.
let shortOne = AddressDiff.compare("0xabc", with: "0xabcdef", foldCase: true)
check("a shorter subject still compares", shortOne.sharedPrefix == 5)
check("…and reports its own length", shortOne.length == 5)
let longOne = AddressDiff.compare("0xabcdef", with: "0xabc", foldCase: true)
check("a longer subject still compares", longOne.sharedPrefix == 5)
check("…and finds its own pivot", longOne.pivot == 5)

print("")
print("Several twins at once")
// Two twins. A character is shared only when it is shared with BOTH — taking
// the maximum, or the first twin's answer, dims a character that distinguishes
// the subject from one of the addresses it is being warned about.
let subject = "0xAAAA1111BBBB2222"
let twinA   = "0xAAAA9999BBBB2222"   // head parts at 6, tail shared from 10
let twinB   = "0xAA119999CBBB2222"   // head parts at 4, tail shared from 11
let both = AddressDiff.combined(subject, against: [twinA, twinB], foldCase: true)
check("the shared head is the shortest of them", both.sharedPrefix == 4)
check("the shared tail is the shortest of them", both.sharedSuffix == 7)
check("the pivot is the earliest parting", both.pivot == 4)
let reversed = AddressDiff.combined(subject, against: [twinB, twinA], foldCase: true)
check("the order the twins arrive in changes nothing", reversed == both)
let none = AddressDiff.combined(subject, against: [], foldCase: true)
check("no twins shares nothing", none.sharedPrefix == 0 && none.sharedSuffix == 0)
check("…and still knows the subject's length", none.length == subject.count)

print("")
print("Segments")
let segs = AddressDiff.segments(of: mine, comparison: c)
check("every character survives", segs.map(\.text).joined() == mine)
check("exactly one pivot", segs.filter { $0.run == .pivot }.count == 1)
check("the pivot is one character", segs.first { $0.run == .pivot }?.text.count == 1)
check("the pivot is the character at the parting",
      segs.first { $0.run == .pivot }?.text == String(Array(mine)[2]))
check("it opens with the shared head", segs.first?.run == .shared)
check("it closes with the shared tail", segs.last?.run == .shared)
check("the tail is the four a short form shows", segs.last?.text.count == 4)
// Maximal runs, or the band draws forty-two Texts for a forty-two character
// address and the layout engine pays for every one on every body pass.
check("adjacent same-kind characters merge",
      zip(segs, segs.dropFirst()).allSatisfy { $0.run != $1.run })
let identical = AddressDiff.segments(of: "abcdef", comparison: same)
check("an identical pair has no pivot to draw",
      identical.allSatisfy { $0.run == .shared })
check("…and still prints in full", identical.map(\.text).joined() == "abcdef")
check("an empty subject draws nothing",
      AddressDiff.segments(of: "", comparison: none).isEmpty)
// A comparison built against a DIFFERENT string must not slice off the end.
let mismatched = Comparison(sharedPrefix: 99, sharedSuffix: 99, length: 3)
check("a stale comparison is clamped, never a crash",
      AddressDiff.segments(of: "abc", comparison: mismatched).map(\.text).joined() == "abc")

print("")
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("all assertions pass")
SWIFT

echo "address-diff-selftest: compiling AddressDiff.swift AS SHIPPED…"
swiftc -O -o "$TMP/run" "$DIFF" "$TMP/main.swift" 2>&1 | sed 's/^/  /'
"$TMP/run"

# --- the mutation pass ------------------------------------------------------
# A check that cannot fail proves nothing. Each of these is a silent wrong
# answer on a security notice.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$DIFF" "$target"
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
echo "Mutations — each is a warning that looks completely normal:"

# The two runs meeting in the middle and counting the same characters twice —
# a band that prints two addresses and marks nothing.
mutate "the head and tail runs stop being kept apart" \
  'while suffix < limit - prefix,' \
  'while suffix < limit,'
# Two spellings of one address, wearing a red marker at character 3.
mutate "the case fold stops being conditional" \
  'guard foldCase, a.isASCII, b.isASCII else { return false }' \
  'guard a.isASCII, b.isASCII else { return false }'
# A confusable folded away on the screen whose whole job is confusables.
mutate "the fold stops being ASCII-only" \
  'guard foldCase, a.isASCII, b.isASCII else { return false }' \
  'guard foldCase else { return false }'
# The band dimming a character the subject does not share with every twin.
mutate "several twins fold to the longest agreement instead of the shortest" \
  'prefix = min(prefix, c.sharedPrefix)' \
  'prefix = max(prefix, c.sharedPrefix)'
mutate "the shared tail folds the same way" \
  'suffix = min(suffix, c.sharedSuffix)' \
  'suffix = max(suffix, c.sharedSuffix)'
# No twins reading as "shares everything", which dims an address in full.
mutate "an empty twin set starts claiming agreement" \
  'return Comparison(sharedPrefix: 0, sharedSuffix: 0, length: subject.count)' \
  'return Comparison(sharedPrefix: subject.count, sharedSuffix: 0, length: subject.count)'
# The marker one character to the right of where the two addresses part.
mutate "the pivot goes off by one" \
  'sharedPrefix < length - sharedSuffix ? sharedPrefix : nil' \
  'sharedPrefix < length - sharedSuffix ? sharedPrefix + 1 : nil'
mutate "the reported position stops being 1-based" \
  'pivot.map { $0 + 1 }' \
  'pivot'
# An address silently shortened on the screen that promises to print it whole.
mutate "the shared tail stops being drawn" \
  'push(tailStart..<chars.count, .shared)' \
  'push(tailStart..<tailStart, .shared)'
# A whole region marked as the one character that differs.
mutate "the pivot swallows the rest of the difference" \
  'push(prefix..<(prefix + 1), .pivot)' \
  'push(prefix..<tailStart, .pivot)'
# Every character reading as shared — the band dims the entire address.
mutate "the comparison stops comparing" \
  'if a == b { return true }' \
  'return true; if a == b { return true }'
# The clamp removed: a comparison built against another string slices past the
# end of this one.
mutate "the segment clamp is dropped" \
  'let prefix = max(0, min(comparison.sharedPrefix, chars.count))' \
  'let prefix = comparison.sharedPrefix'

echo ""
echo "address-diff-selftest: OK — assertions pass and every mutation is caught."
