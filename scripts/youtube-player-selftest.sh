#!/bin/zsh
# Casberi YouTube player self-test (prd §1092):
#
#   YouTubeShorts.videoID / plausible   (sliced out whole and compiled)
#   + guards on the sheet's video arm and the embed
#
# WHY A HARNESS. Every failure renders as an ordinary sheet: a link shape the
# parser misses plays nothing and shows a card; a video tested AFTER the
# article arm draws its page's words instead of the player; an embed that
# loads before the press reaches YouTube for every sheet opened; a persistent
# data store keeps YouTube's cookies across plays; a host not in the reach
# registry breaks the privacy screen's promise.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHORTS="Casberi/Casberi/Model/YouTubeShorts.swift"
CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
EMBED="Casberi/Casberi/Design/YouTubeEmbedView.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$SHORTS" "$CONTENT" "$EMBED" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# ── Guards ───────────────────────────────────────────────────────────
python3 - "$CONTENT" <<'PY' || exit 1
import sys, re
src = open(sys.argv[1]).read()
fn = src[src.index("private static func linkShape(for thing: Thing)"):]
fn = fn[:fn.index("\n    }\n")]
a = fn.find(".article(door:")
for arm in (".youtube(id:", ".telegramVideo(post:"):
    v = fn.find(arm)
    if v < 0: print(f"✗ the sheet no longer has the {arm} arm"); sys.exit(1)
    if a >= 0 and v > a: print(f"✗ the {arm} arm is tested after the article arm — a video's page would draw as words"); sys.exit(1)
tg = src[src.index("private struct TelegramVideoContent"):]
tg = tg[:tg.index("\n}\n")]
if "TelegramChannel.videoSource(in:" not in tg or "DemoMode.isActive" not in tg:
    print("✗ a Telegram video no longer reads its file fresh, or the demo's press reaches out"); sys.exit(1)
if "VideoPlayer(" not in tg:
    print("✗ a Telegram video no longer plays in Apple's player"); sys.exit(1)
if "YouTubeVideoContent(" not in src: print("✗ the video arm no longer draws YouTubeVideoContent"); sys.exit(1)
body = src[src.index("private struct YouTubeVideoContent"):]
body = body[:body.index("\n}\n")]
if "if playing {" not in body or "YouTubeEmbedView(" not in body:
    print("✗ the embed is no longer built only after the press"); sys.exit(1)
if "DemoMode.isActive" not in body:
    print("✗ the demo's press no longer refuses to reach YouTube"); sys.exit(1)
PY
grep -q 'www.youtube-nocookie.com/embed/' "$EMBED" \
  || { echo "✗ the embed is not YouTube's privacy-enhanced player"; exit 1; }
grep -q 'websiteDataStore = .nonPersistent()' "$EMBED" \
  || { echo "✗ the player keeps cookies between plays"; exit 1; }
grep -q 'NetworkLedger.shared.record(host: "www.youtube-nocookie.com"' "$EMBED" \
  || { echo "✗ a play no longer leaves a receipt"; exit 1; }
grep -q '"www.youtube-nocookie.com"' "$REACH" \
  || { echo "✗ the player's host is not in the reach registry"; exit 1; }

# ── The id parser, sliced whole ──────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$SHORTS" > "$TMP/parse.swift" <<'PY'
import sys
src = open(sys.argv[1]).read()
a = src.index("    static func videoID(in link: String)")
b = src.index("    private static func plausible(_ id: String)")
b = src.index("\n    }\n", b) + len("\n    }\n")
print("import Foundation\nenum YouTubeShorts {\n" + src[a:b] + "}\n")
PY
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("✗ \(what)") } }
let id = "dQw4w9WgXcQ"
for link in ["https://www.youtube.com/watch?v=\(id)", "https://youtube.com/watch?v=\(id)&t=42s",
             "https://m.youtube.com/watch?v=\(id)", "https://music.youtube.com/watch?v=\(id)",
             "https://youtu.be/\(id)", "https://youtu.be/\(id)?si=abc",
             "https://www.youtube.com/shorts/\(id)", "https://www.youtube.com/live/\(id)",
             "https://www.youtube.com/embed/\(id)", "  https://youtu.be/\(id)  "] {
    check(YouTubeShorts.videoID(in: link) == id, "finds the id in \(link)")
}
for link in ["https://vimeo.com/\(id)", "https://notyoutube.com/watch?v=\(id)",
             "https://www.youtube.com/watch?v=short", "https://www.youtube.com/shorts/about",
             "https://www.youtube.com/@channel", "https://www.youtube.com/watch?v=\(id)!x",
             "not a link"] {
    check(YouTubeShorts.videoID(in: link) == nil, "finds no id in \(link)")
}
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("✓ youtube player self-test")
SWIFT
swiftc -O -o "$TMP/t" "$TMP"/*.swift 2>&1 | grep -v "warning:" || true
[[ -x "$TMP/t" ]] || { echo "✗ the harness did not compile"; exit 1; }
"$TMP/t"
