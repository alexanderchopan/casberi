#!/bin/zsh
# Casberi reading-room self-test — Reading's Follow (prd §1085), and Media's
# tiles since Reading folded into Media (prd §1204; Highlights is deleted):
#
#   Casberi/Casberi/Model/ReadingScope.swift   (compiled whole)
#   Casberi/Casberi/Model/MediaScope.swift     (compiled whole)
#
# WHY A HARNESS. Both failures render as a calm list. Highlights that miss the
# passages you kept yourself, or that take a Readwise article for a passage,
# look like a short list; Follow suggestions that offer a site you already
# follow, a social network, or a rating board's own home page look like
# advice. Which rows are highlights and which saves make a habit are rules,
# and only a case-by-case statement of them says they are right.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SCOPE="Casberi/Casberi/Model/ReadingScope.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+MediaRoom.swift"
MEDIA="Casberi/Casberi/Model/MediaScope.swift"
SHEET="Casberi/Casberi/Screens/ReadingFindSheet.swift"
for f in "$SCOPE" "$ROOM" "$SHEET" "$MEDIA"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
# The wiring the pure rules rely on.
grep -q 'RoomAccounts.readSources' "$ROOM" \
  || { echo "✗ Media no longer tells its Read half from Play — articles would tile"; exit 1; }
grep -q '!read.contains($0.source) && Self.isMediaTile' "$ROOM" \
  || { echo "✗ an article with a picture tiles in All — only Play's apps tile (prd §1204)"; exit 1; }
grep -q 'followingSections(.reading' "$ROOM" \
  || { echo "✗ Media's Subscriptions no longer lists the sites you follow"; exit 1; }
grep -q 'ReadingRoom.saveSources.contains' "$SHEET" \
  || { echo "✗ Follow counts every row as a save — a feed's own rows would suggest its own site"; exit 1; }
grep -q 'ReadingRoom.suggestions(' "$SHEET" \
  || { echo "✗ Follow no longer reads ReadingRoom.suggestions"; exit 1; }
grep -q 'mediaRoomSections(' Casberi/Casberi/Screens/FeedScreen+ShapedSections.swift \
  || { echo "✗ the Media room no longer draws its own sections"; exit 1; }
! grep -q 'readingRoomSections(' Casberi/Casberi/Screens/FeedScreen+ShapedSections.swift \
  || { echo "✗ a Reading room draws again — it folded into Media (prd §1204)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$SCOPE" "$MEDIA" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let now = Date(timeIntervalSince1970: 2_000_000_000)
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

// ── Hosts ────────────────────────────────────────────────────────────
check(ReadingRoom.host(of: "https://www.stratechery.com/2026/x") == "stratechery.com", "www. is dropped")
check(ReadingRoom.host(of: "Stratechery.com") == "stratechery.com", "a bare address is a site, lower-cased")
check(ReadingRoom.host(of: "not a link") == nil, "words are no site")
check(ReadingRoom.covered("blog.example.com", by: ["example.com"]), "a feed covers its subdomains' saves")
check(ReadingRoom.covered("example.com", by: ["feeds.example.com"]), "a feeds. host covers its site")
check(!ReadingRoom.covered("notexample.com", by: ["example.com"]), "a suffix is not a subdomain")

// ── Suggestions ──────────────────────────────────────────────────────
let saves: [ReadingRoom.Save] = [
    .init(url: "https://stratechery.com/a", at: ago(1)),
    .init(url: "https://stratechery.com/b", at: ago(5)),
    .init(url: "https://www.stratechery.com/c", at: ago(9)),
    .init(url: "https://nadia.substack.com/p/1", at: ago(2)),
    .init(url: "https://nadia.substack.com/p/2", at: ago(3)),
    .init(url: "https://once.example/a", at: ago(2)),
    .init(url: "https://old.example/a", at: ago(70)),
    .init(url: "https://old.example/b", at: ago(80)),
    .init(url: "https://x.com/a/status/1", at: ago(1)),
    .init(url: "https://x.com/a/status/2", at: ago(1)),
    .init(url: "https://en.wikipedia.org/wiki/A", at: ago(1)),
    .init(url: "https://en.wikipedia.org/wiki/B", at: ago(1)),
    .init(url: "https://followed.blog/a", at: ago(1)),
    .init(url: "https://followed.blog/b", at: ago(1)),
    .init(url: "https://future.example/a", at: now.addingTimeInterval(86_400)),
    .init(url: "https://future.example/b", at: now.addingTimeInterval(86_400)),
]
let s = ReadingRoom.suggestions(saves: saves, followed: ["followed.blog"], now: now)
check(s.first == .init(host: "stratechery.com", count: 3), "the most-saved site leads, www. counted with it")
check(s.contains(.init(host: "nadia.substack.com", count: 2)), "two saves make a habit")
check(!s.contains { $0.host == "once.example" }, "one save is not a habit")
check(!s.contains { $0.host == "old.example" }, "saves older than sixty days do not count")
check(!s.contains { $0.host == "x.com" }, "a social network is never offered")
check(!s.contains { $0.host.hasSuffix("wikipedia.org") }, "an encyclopedia is never offered")
check(!s.contains { $0.host == "followed.blog" }, "a site you follow is never offered")
check(!s.contains { $0.host == "future.example" }, "a save dated ahead does not count")
let many = (0..<8).flatMap { i in [ReadingRoom.Save(url: "https://s\(i).example/a", at: ago(1)),
                                   ReadingRoom.Save(url: "https://s\(i).example/b", at: ago(1))] }
check(ReadingRoom.suggestions(saves: many, followed: [], now: now).count == ReadingRoom.suggestionCap, "at most five")
check(ReadingRoom.suggestions(saves: many, followed: [], now: now).map(\.host)
      == ["s0.example", "s1.example", "s2.example", "s3.example", "s4.example"], "ties read A to Z")
check(ReadingRoom.saveSources == ["Bookmarks", "Raindrop", "Readwise"], "only saving apps count as saves")

// ── A typed site ─────────────────────────────────────────────────────
check(ReadingRoom.site(in: "stratechery.com") == "stratechery.com", "an address names a site")
check(ReadingRoom.site(in: "https://www.platformer.news/p/1") == "platformer.news", "a pasted link names its site")
check(ReadingRoom.site(in: "rollups") == nil, "a word is a search")
check(ReadingRoom.site(in: "v1.2") == nil, "a version is no site")
check(ReadingRoom.site(in: "two words.com") == nil, "words with a dot are a search")
check(ReadingRoom.site(in: "x.com") == nil, "a social network is never a site to follow")

// ── The tiles ────────────────────────────────────────────────────────
check(MediaScope.allCases == [.all, .play, .read, .subscriptions], "Media's tiles are All, Play, Read, Subscriptions, A–Z after All (prd §1204); no verb: Follow is the Subscriptions list's first row (prd §1118)")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
print("✓ reading room: hosts, suggestions, typed sites, Media's tiles")
SWIFT
swiftc -O -o "$TMP/run" "$TMP/ReadingScope.swift" "$TMP/MediaScope.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
"$TMP/run"
