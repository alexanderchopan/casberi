#!/bin/zsh
# Casberi share-home self-test (prd §1200) — where a share into Casberi lands,
# compiled WHOLE and UNMODIFIED:
#
#   Casberi/Shared/ShareHome.swift — forLink, link(inText:), source, mediaHosts
#
# Every failure here is a thing filed where nobody looks: an article in Media,
# a video in Reading, a sentence that happens to hold an address taken for a
# link, a share stamped with a room name no room answers to.
#
# The drift guards cover what the pure file cannot prove: that the extension
# routes through it, that the pill names the place, that a picture keeps its
# bytes, that a failed save is never "Saved", and that the heal names a
# share's link.
#
# Usage: scripts/share-home-selftest.sh     (exit 0 = clean)

set -u
cd "${0:A:h}/.."

HOME_SWIFT="Casberi/Shared/ShareHome.swift"
EXT="Casberi/ShareExtension/ShareViewController.swift"
ROOMS="Casberi/Casberi/Model/RoomAccounts.swift"
HEAL="Casberi/Casberi/Model/LinkHeal.swift"
KEPT="Casberi/Casberi/Model/NoteSheetSource.swift"
GLYPH="Casberi/Casberi/Design/KindGlyph.swift"

fail=0
guard() {  # name, pattern, file
  if grep -Eq -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1 ($3)"; fail=1; fi
}

echo "Drift guards — the wiring"
guard "Reading's source is the Reading room's name" 'static let readingRoom = "Reading"' "$ROOMS"
guard "Media's source is the Media room's name" 'static let mediaRoom = "Media"' "$ROOMS"
guard "Notes' source is a note of yours" 'static let keptSource = "You"' "$KEPT"
guard "a shared URL is homed by ShareHome" 'let home = ShareHome\.forLink\(url\)' "$EXT"
guard "a shared link is stamped with its home" 'source: home\.source\)' "$EXT"
guard "shared text that is only an address is a link" 'ShareHome\.link\(inText: text\)' "$EXT"
guard "a Safari share reads the page's address off the preprocessing result" 'if let raw = pageInfo\?\["url"\] as\? String, let url = ShareHome\.link\(inText: raw\)' "$EXT"
guard "the preprocessor hands the page's address" '"url": document\.URL' "Casberi/ShareExtension/SharePreprocessor.js"
guard "shared words are a note" 'thing\.kind = \.note' "$EXT"
guard "a shared picture keeps its bytes" 'thing\.previewImageData = bytes' "$EXT"
guard "a picture that will not read is not kept" 'guard let bytes = await pictureBytes\(from: provider\) else \{ return nil \}' "$EXT"
guard "the pill names the place" 'label\.text = home\?\.confirmation' "$EXT"
guard "a failed save is never Saved" 'guard context\.saveHonestly\(\) else \{ return false \}' "$EXT"
guard "the heal names a share's link in Reading and Media" 'ShareHome\.reading\.source, ShareHome\.media\.source' "$HEAL"
guard "a share's row wears Reading's glyph" 'case "reading": +return "book"' "$GLYPH"
guard "a share's row wears Media's glyph" 'case "media": +return "play\.circle"' "$GLYPH"
[[ $fail -eq 0 ]] || { echo "share-home-selftest: ✗ drift guard(s) failed"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}
func home(_ s: String) -> ShareHome { ShareHome.forLink(URL(string: s)!) }

print("A link's home")
check("an article is Reading's", home("https://stratechery.com/2026/the-thing/") == .reading)
check("a newsletter is Reading's", home("https://simon.substack.com/p/hello") == .reading)
check("a YouTube video is Media's", home("https://www.youtube.com/watch?v=abc") == .media)
check("a short YouTube link is Media's", home("https://youtu.be/abc") == .media)
check("YouTube on the phone's host is Media's", home("https://m.youtube.com/watch?v=abc") == .media)
check("a podcast episode is Media's", home("https://podcasts.apple.com/us/podcast/x/id1?i=2") == .media)
check("a Spotify show is Media's", home("https://open.spotify.com/show/abc") == .media)
check("a Twitch channel is Media's", home("https://www.twitch.tv/somebody") == .media)
check("a look-alike host is not", home("https://notyoutube.com/watch") == .reading)
check("a host that only contains one is not", home("https://youtube.com.example.org/x") == .reading)
check("a social post is Reading's, never Media's", home("https://www.tiktok.com/@a/video/1") == .reading)

print("Shared text")
check("an address alone is a link", ShareHome.link(inText: "  https://example.com/a \n") != nil)
check("words around an address are a note", ShareHome.link(inText: "read this https://example.com/a") == nil)
check("an address followed by words is a note", ShareHome.link(inText: "https://example.com/a and more") == nil)
check("a sentence is a note", ShareHome.link(inText: "buy milk") == nil)
check("a non-web address is a note", ShareHome.link(inText: "mailto:a@b.c") == nil)
check("an empty share is nothing", ShareHome.link(inText: "   ") == nil)

print("Sources")
check("Reading files under the room's own name", ShareHome.reading.source == "Reading")
check("Media files under the room's own name", ShareHome.media.source == "Media")
check("Notes files as a note of yours", ShareHome.notes.source == "You")
check("every pill names a place, never Casberi",
      ShareHome.allCases.allSatisfy { $0.confirmation.hasPrefix("Saved to ") && !$0.confirmation.contains("Casberi") })

if failures > 0 { print("share-home-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("share-home-selftest: assertions pass")
SWIFT

if ! swiftc -Onone -o "$TMP/sh" "$HOME_SWIFT" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "share-home-selftest: ✗ did not compile"; cat "$TMP/build.log"; exit 1
fi
"$TMP/sh" || exit 1

# MUTATIONS — each must be APPLIED (the file changed) and then CAUGHT.
mutate() {  # name, perl expression
  local name=$1 expr=$2
  local copy="$TMP/mut-ShareHome.swift"
  cp "$HOME_SWIFT" "$copy"
  perl -0pi -e "$expr" "$copy"
  if cmp -s "$HOME_SWIFT" "$copy"; then echo "  ✗ mutation did not apply: $name"; fail=1; return; fi
  if swiftc -Onone -o "$TMP/mut" "$copy" "$TMP/main.swift" 2>/dev/null && "$TMP/mut" >/dev/null 2>&1; then
    echo "  ✗ SURVIVED: $name"; fail=1
  else
    echo "  ✓ caught: $name"
  fi
}

echo "Mutations"
mutate "every link is Reading's" 's/return isMedia \? \.media : \.reading/return .reading/'
mutate "a host matches by containing" 's/host == \$0 \|\| host\.hasSuffix\("\." \+ \$0\)/host.contains(\$0)/'
mutate "words around an address make a link" 's/!trimmed\.contains\(where: \\\.isWhitespace\),//'
mutate "Reading files under a seat" 's/case \.reading: return "Reading"/case .reading: return "Bookmarks"/'
mutate "a subdomain is not the host" 's/ \|\| host\.hasSuffix\("\." \+ \$0\)//'

[[ $fail -eq 0 ]] || { echo "share-home-selftest: ✗ mutation check failed"; exit 1; }
echo "share-home-selftest: OK — assertions, guards and mutations all pass."
