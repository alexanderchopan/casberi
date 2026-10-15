#!/bin/zsh
# Casberi Spotify plays self-test (prd §1158) — the pure half of the seat's
# `spclient` reads, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/SpotifyPlays.swift
#
# UNMEASURED AGAINST SPOTIFY: `recently-played/v3` is the web player's own,
# undocumented answer, and no build host here holds a session to read it, so
# every fixture below pins THIS PARSER'S READING, never Spotify's shape.
# `-spotifyProbe` logs the answer's keys; that is the first measurement.
#
# Every failure here is silent on a device:
#
#   · a 200 that is not a `playContexts` answer read as an empty history is a
#     seat that says "up to date" over a body nobody understood
#   · a play with no time dated by the sweep lands an old album as today's
#   · a ref without the day lands an album once, ever; a ref with the clock
#     lands it every pass
#   · a URI this seat cannot open landed as a row is a door to nothing (§912)
#   · the ingest reading `api.spotify.com` again is §711b's wall: signed in,
#     reading nothing, for every person at once
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PLAYS="Casberi/Casberi/Model/SpotifyPlays.swift"
BRIDGE="Casberi/Casberi/Model/SpotifyBridge.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$PLAYS" "$BRIDGE" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The ingest reads `spclient`, never the throttled host (§711b, §1158).
INGEST="$(sed -n '/^enum SpotifyIngest/,$p' "$BRIDGE")"
if print -r -- "$INGEST" | grep -vE '^[[:space:]]*//' | grep -qF 'api.spotify.com'; then
  echo "✗ SpotifyIngest reads api.spotify.com — every web-player token is throttled there (§711b)"; exit 1
fi
grep -qF 'presence-view/v1/buddylist' "$BRIDGE" \
  || { echo "✗ the friend feed no longer reads presence-view/v1/buddylist"; exit 1; }
grep -qF 'recently-played/v3/user/' "$BRIDGE" \
  || { echo "✗ your plays no longer read recently-played/v3"; exit 1; }
for host in spclient.wg.spotify.com api-partner.spotify.com clienttoken.spotify.com; do
  grep -qF "\"$host\"" "$REACH" || { echo "✗ $host is not in Spotify's reach entry"; exit 1; }
done
# A row names who made it off the page head, and the rows landed before do too (§1305).
grep -qF 'title: TitleSeam.join(name, byline ?? play.kindWord)' "$BRIDGE" \
  || { echo "✗ your plays no longer name the artist (§1305)"; exit 1; }
grep -qF 'await healBylines(context: context)' "$BRIDGE" \
  || { echo "✗ the rows landed before §1305 are no longer healed"; exit 1; }
echo "spotify-plays-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

// ── The answer ───────────────────────────────────────────────────────────
let answer = json("""
{"playContexts":[
 {"uri":"spotify:album:3mH6qwIy9crq0I9YQbOuDf","lastPlayedTime":1759800000000,
  "lastPlayedTrackUri":"spotify:track:7eqoqGkKwgOaWNNHx90uEZ"},
 {"uri":"spotify:playlist:37i9dQZEVXcJZyENOWUFo7","lastPlayedTime":"1759900000000"},
 {"uri":"spotify:user:anna:collection","lastPlayedTime":1759700000000},
 {"uri":"spotify:user:anna:playlist:1A2b3C","lastPlayedTime":1759600000000},
 {"uri":"spotify:artist:2h93pZq0e7k5yf4dywlkpM"},
 {"uri":"spotify:station:album:x","lastPlayedTime":1759500000000},
 {"uri":"spotify:show:5CfCWKI5pZ28U0uOzXkDHe","lastPlayedTime":1759400000000}
],"total":7}
""")
let plays = SpotifyPlays.contexts(answer) ?? []
check(plays.count == 5, "five contexts read; a timeless one and an unopenable one dropped (\(plays.count))")
check(plays.first?.uri == "spotify:playlist:37i9dQZEVXcJZyENOWUFo7",
      "newest first, a time sent as a string included")
check(plays.first?.page == "https://open.spotify.com/playlist/37i9dQZEVXcJZyENOWUFo7",
      "a playlist opens its page")
let album = plays.first { $0.uri.hasPrefix("spotify:album:") }
check(album?.lastTrackPage == "https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ",
      "the last song played inside it is carried")
check(album?.playedAt == Date(timeIntervalSince1970: 1_759_800_000),
      "milliseconds read as milliseconds")
let liked = plays.first { $0.uri.hasSuffix(":collection") }
check(liked?.fixedName == "Liked Songs" && liked?.page == "https://open.spotify.com/collection/tracks",
      "Liked Songs is named here; oEmbed has no page for it")
check(plays.contains { $0.page == "https://open.spotify.com/playlist/1A2b3C" },
      "the older user-scoped playlist URI opens the playlist")
check(plays.contains { $0.page == "https://open.spotify.com/show/5CfCWKI5pZ28U0uOzXkDHe" },
      "a show opens its page")

// ── Not this answer ──────────────────────────────────────────────────────
check(SpotifyPlays.contexts(json(#"{"items":[]}"#)) == nil, "a 200 of another shape is nil, not empty")
check(SpotifyPlays.contexts(json(#"{"playContexts":[]}"#)) == [], "an empty history is empty, not nil")
check(SpotifyPlays.contexts(nil) == nil, "no body is nil")

// ── Doors ────────────────────────────────────────────────────────────────
check(SpotifyPlays.page("spotify:track:7eqoqGkKwgOaWNNHx90uEZ")
      == "https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ", "a track opens its page")
check(SpotifyPlays.page("spotify:local:Artist:Album:Song:180") == nil, "a local file opens nothing")
check(SpotifyPlays.page("spotify:track:../../evil") == nil, "an id that is not an id opens nothing")
check(SpotifyPlays.page("https://open.spotify.com/track/x") == nil, "a URL is not a URI")

// ── Times ────────────────────────────────────────────────────────────────
check(SpotifyPlays.millis(0) == nil && SpotifyPlays.millis("x") == nil && SpotifyPlays.millis(nil) == nil,
      "zero, words and nothing are no time")

// ── The ref: one per thing played from, per local day ────────────────────
var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
var tokyo = utc; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let lateUTC = Date(timeIntervalSince1970: 1_759_791_600)   // 2025-10-06 23:00 UTC
check(SpotifyPlays.dayKey(lateUTC, calendar: utc) == "2025-10-06", "the day in UTC")
check(SpotifyPlays.dayKey(lateUTC, calendar: tokyo) == "2025-10-07", "the day where the person is")
let morning = SpotifyPlays.Play(uri: "spotify:album:a", page: "p", fixedName: nil, kindWord: nil,
                                playedAt: Date(timeIntervalSince1970: 1_759_740_000), lastTrackPage: nil)
let evening = SpotifyPlays.Play(uri: "spotify:album:a", page: "p", fixedName: nil, kindWord: nil,
                                playedAt: Date(timeIntervalSince1970: 1_759_760_000), lastTrackPage: nil)
// The binary runs under TZ=UTC, so `ref`'s current calendar is UTC here.
let tomorrow = SpotifyPlays.Play(uri: "spotify:album:a", page: "p", fixedName: nil, kindWord: nil,
                                 playedAt: Date(timeIntervalSince1970: 1_759_840_000), lastTrackPage: nil)
check(morning.ref == evening.ref, "the same album twice in a day is one row")
check(morning.ref != tomorrow.ref, "the same album the next day is a new row")
check(morning.ref.hasPrefix("spotify:played:spotify:album:a:"), "the ref names the context")

// ── Who made it (prd §1305): heads as measured 2026-10-14 ────────────────
func head(_ tags: [(String, String, String)]) -> String {
    "<html><head><meta charSet=\"utf-8\"/>" + tags.map { "<meta \($0.0)=\"\($0.1)\" content=\"\($0.2)\"/>" }.joined() + "</head><body>"
}
let albumHead = head([("property", "og:title", "Bridge Over Troubled Water - Album by Simon &amp; Garfunkel | Spotify"),
                      ("property", "og:description", "Simon &amp; Garfunkel · album · 1970 · 11 songs")])
check(SpotifyPlays.byline(head: albumHead, page: "https://open.spotify.com/album/0JwHz5SSvpYWuuCNbtYZoV")
      == "Simon & Garfunkel", "an album's artist leads its description, entities decoded")
let germanAlbum = head([("property", "og:description", "Drake · Album · 2018 · 25 Songs")])
check(SpotifyPlays.byline(head: germanAlbum, page: "https://open.spotify.com/album/1ATL5GLyefJaxhQzSPVrLX")
      == "Drake", "a localized album head still leads with the artist")
let songHead = head([("property", "og:description", "ザ・キラーズ · Hot Fuss · 曲 · 2004"),
                     ("name", "music:musician_description", "Drake, Wizkid, Kyla")])
check(SpotifyPlays.byline(head: songHead, page: "https://open.spotify.com/track/1zi7xx7UVEFkmKfv06H8x0")
      == "Drake, Wizkid, Kyla", "a song names every artist from music:musician_description")
let bareSong = head([("property", "og:description", "The Killers · Hot Fuss · Song · 2004")])
check(SpotifyPlays.byline(head: bareSong, page: "https://open.spotify.com/track/3n3Ppam7vgaVa1iaRUc9Lp")
      == "The Killers", "a song without the musician tag falls back to the description's lead")
let showHead = head([("property", "og:description", "Podcast · Joe Rogan · The official podcast of comedian Joe Rogan.")])
check(SpotifyPlays.byline(head: showHead, page: "https://open.spotify.com/show/4rOoJ6Egrf8K2IrywzwOMk")
      == "Joe Rogan", "a podcast names its publisher second")
let playlistHead = head([("property", "og:description", "The hottest 50. Cover: ASHE")])
check(SpotifyPlays.byline(head: playlistHead, page: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M") == nil,
      "a playlist's description is its blurb, never a maker")
let stock = head([("property", "og:description", "Spotify is a digital music service that gives you access to millions of songs.")])
check(SpotifyPlays.byline(head: stock, page: "https://open.spotify.com/album/x1") == nil,
      "the web player's stock head names nobody")
check(SpotifyPlays.byline(head: albumHead, page: "https://open.spotify.com.evil.example/album/x1") == nil,
      "only Spotify's own host is read")
check(SpotifyPlays.pageType("https://open.spotify.com/intl-de/album/abc") == "album",
      "a localized page keeps its type")
check(SpotifyPlays.hasByline("https://open.spotify.com/album/a") && !SpotifyPlays.hasByline("https://open.spotify.com/playlist/a")
      && !SpotifyPlays.hasByline("https://open.spotify.com/collection/tracks"),
      "only albums, songs and podcasts are asked")
check(SpotifyPlays.kindWord("album") == "Album" && SpotifyPlays.kindWord("station") == nil,
      "the kind word stays the line where no maker is named")

print(failures == 0 ? "spotify-plays-selftest: all checks ✓" : "spotify-plays-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$PLAYS" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ spotify-plays-selftest: compile failed"; exit 1; }
TZ=UTC "$TMP/run"
