#!/bin/zsh
# Casberi mail-shelf self-test — the mail rooms' tiles, All · From · Subject
# (the music rooms' shape, prd §995):
#
#   Casberi/Casberi/Model/MailShelf.swift    (compiled WHOLE, Foundation-only)
#   Casberi/Casberi/Model/MusicShelf.swift   (its letters and A–Z order)
#
# WHY A HARNESS. Every failure here renders as an ordinary A–Z list:
#
#   · "Re: Lease" filed under R, away from the "Lease" it answers
#   · one person listed twice under From because their client spelt their
#     name two ways, or two people who share a name merged into one
#   · "Uma Patel <uma@studio.example>" drawn whole as a sender's name
#
# Plus drift guards for the wiring no function can prove: the mail face draws
# its own sections, a room change opens on All, From stands only over a
# sender, and each tile has its own glyph. Pure, local, no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

SHELF="Casberi/Casberi/Model/MailShelf.swift"
MUSIC="Casberi/Casberi/Model/MusicShelf.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
GLYPHS="Casberi/Casberi/Screens/ScopeTileGlyphs.swift"
SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
for f in "$SHELF" "$MUSIC" "$FEED" "$GLYPHS" "$SURFACE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d /tmp/mail-shelf-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}

echo "Drift guards"
guard "the mail face draws its own sections"      'mailSections\(visible, nextEventID: nextEventID, heroShown: heroShown\)' "$FEED"
guard "From stands only over a sender"            'scope != \.from \|\| live\.contains \{ mailSenderKey\(\$0\) != nil \}' "$FEED"
guard "a room change opens on All"                'chrome\.mailScope = \.all'                            "$SURFACE"
guard "From wears its own glyph"                  'case \.from:    return ScopeTileGlyph\.from'          "$GLYPHS"
guard "Subject wears its own glyph"               'case \.subject: return ScopeTileGlyph\.subject'       "$GLYPHS"
[[ $fail -eq 0 ]] || { echo "mail-shelf-selftest: ✗ drift guard(s) failed"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

print("Tile order")
check(MailScope.allCases == [.all, .from, .subject],
      "the tiles are A–Z and open on All (got \(MailScope.allCases))")

print("Sender names")
check(MailShelf.displayName("Uma Patel <uma@studio.example>") == "Uma Patel", "the name, not the address")
check(MailShelf.displayName("\"Uma Patel\" <uma@studio.example>") == "Uma Patel", "the quotes off")
check(MailShelf.displayName("<uma@studio.example>") == "uma@studio.example", "an address alone stands")
check(MailShelf.displayName("uma@studio.example") == "uma@studio.example", "a bare address stands")
check(MailShelf.displayName("  ") == nil, "a blank is no sender")

print("Sender keys")
check(MailShelf.senderKey(name: "Uma", address: "Uma@Studio.example") == "uma@studio.example",
      "the address wins, folded")
check(MailShelf.senderKey(name: "Émile ", address: nil) == MailShelf.senderKey(name: "emile", address: "  "),
      "no address: the name, folded")
check(MailShelf.senderKey(name: nil, address: nil) == nil, "nothing files nowhere")

print("Senders")
let senders = MailShelf.senders([
    ("Uma Patel", "uma@studio.example"),
    ("Uma P.", "UMA@studio.example"),
    ("Sam", "sam@a.example"),
    ("Sam", "sam@b.example"),
    (nil, nil),
])
check(senders.count == 3, "one sender per address, a mail with none nowhere (got \(senders.count))")
check(senders.first?.name == "Uma Patel", "the name on the newest mail")
check(senders.first?.count == 2, "two spellings of one address are one sender")
check(senders.filter { $0.name == "Sam" }.count == 2, "one name at two addresses is two senders")

print("Subjects")
check(MailShelf.subjectKey("Re: Lease") == "Lease", "a reply sorts with its mail")
check(MailShelf.subjectKey("RE: Fwd: Lease") == "Lease", "every prefix off, any case")
check(MailShelf.subjectKey("Fwd:Lease") == "Lease", "no space after the colon")
check(MailShelf.subjectKey("AW: Termin") == "Termin", "Outlook's German reply")
check(MailShelf.subjectKey("Meeting: notes") == "Meeting: notes", "a colon in a subject stays")
check(MailShelf.subjectKey("Re:") == "Re:", "a bare prefix is its own subject")
let sections = MusicShelf.sections(["Re: Lease", "Invoice", "Lease"]) { MailShelf.subjectKey($0) }
check(sections.map(\.letter) == ["I", "L"], "letters by the subject read (got \(sections.map(\.letter)))")
check(sections.last?.items.count == 2, "the reply stands under the mail's letter")

if failures > 0 { print("mail-shelf-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$SHELF" "$MUSIC" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ MailShelf.swift did not compile against the harness"; cat "$TMP/build.log"; exit 1
fi
"$TMP/run"

echo "Mutations"
mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$SHELF" "$a"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$a" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$a"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$a" "$MUSIC" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "the tiles out of order" \
  'case all, from, subject' \
  'case all, subject, from'
mutate "an address keeps its case" \
  '.whitespacesAndNewlines).lowercased(),' \
  '.whitespacesAndNewlines),'
mutate "senders keyed by name" \
  'guard let key = senderKey(name: row.name, address: row.address),' \
  'guard let key = senderKey(name: row.name, address: nil),'
mutate "the address drawn with the name" \
  'if let open = s.firstIndex(of: "<"), s.hasSuffix(">") {' \
  'if let open = s.firstIndex(of: "<"), s.hasSuffix("never") {'
mutate "one prefix off, not every one" \
  'guard replyPrefixes.contains(head) else { break }' \
  'guard replyPrefixes.contains(head), s == subject.trimmingCharacters(in: .whitespacesAndNewlines) else { break }'
mutate "a forward keeps its prefix" \
  '["re", "fwd", "fw", "aw", "wg", "sv", "tr"]' \
  '["re", "fw", "aw", "wg", "sv", "tr"]'

echo "mail-shelf-selftest: OK — assertions and mutations both pass."
