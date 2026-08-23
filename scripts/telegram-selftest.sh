#!/bin/zsh
# Casberi Telegram self-test — the SHIPPED parse behind the live half of the
# Telegram seat (prd §429):
#
#   Casberi/Casberi/Model/TelegramChannel.swift   (compiled WHOLE and unmodified)
#
# It is Foundation-only BY DESIGN, so it is compiled as shipped rather than
# extracted — the strongest form this harness takes. The only stub is
# `IngestSupport`, whose two functions are pulled OUT OF THE REAL FILE by name
# (never copied), so drift there breaks this harness rather than passing it.
#
# WHY A HARNESS AND NOT A LIVE CHECK. `scripts/live-integrations.sh` watches the
# PAGE nightly — that the markers are still there. It cannot watch the PARSE, and
# the parse is where every failure of this feature lives, because none of them
# looks like a failure:
#
#   · nineteen of twenty posts landing, the missing one being the NEWEST
#     (rule 3: a lookahead-matched wrapper drops the final element, and the page
#     publishes oldest-first — so the room fills and never with today)
#   · every video post dated "now", because the first `<time>` in the fragment
#     is a clip's running time with no `datetime` (15 of 20 measured on
#     @telegram), which files a four-month-old broadcast as this morning's news
#   · an emoji sprite landing as the post's photograph — every emoji on the page
#     is a `background-image`, so the naive read files 99 of them as pictures
#   · a post truncated mid-sentence, because the text container nested a `<div>`
#     and the scan stopped at the first `</div>`
#   · a row whose words are "Please open Telegram to view this post" — Telegram's
#     own chrome, read as the author's sentence
#   · a group and a real channel with its preview off reported identically, so
#     an empty room can never say why it is empty
#
# Every one of those renders as an ordinary, plausible feed. Nothing in a build,
# a screen sweep or a nightly host check can see any of them.
#
# The export half (`Model/TelegramExport.swift`) is deliberately NOT covered
# here — it is its own file with its own shapes.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CHANNEL="Casberi/Casberi/Model/TelegramChannel.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
FOLLOW="Casberi/Casberi/Model/FeedFollowBridges.swift"
THING="Casberi/Shared/Thing.swift"
for f in "$CHANNEL" "$SUPPORT" "$FOLLOW" "$THING"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guard below. This file DOCUMENTS the
# rules it follows by naming the very thing it must not do — rule 7 refuses the
# view count and says so by naming `Thing.viewCount` — so a guard grepping raw
# source fires against the prose explaining the refusal. That is the
# Obsidian/Cursor lesson, and this repo has now paid for it six times.
strip_comments() {
  python3 - "$1" > "$2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
out = []
for line in src.split("\n"):
    s = line.lstrip()
    if s.startswith("//") or s.startswith("///"):
        continue
    out.append(line)
print("\n".join(out))
PY
}
strip_comments "$CHANNEL" "$TMP/channel.nc"

# --- drift guards -----------------------------------------------------------
# Each is a wiring fact the compiled parse cannot prove about itself: a perfect
# `Post` is worthless if the ingest maps it backwards, and a perfect `ref` is
# worthless if nothing lets that namespace into the feed.

# (1) THE REF NAMESPACE, spelled in two files that cannot see each other.
# `Corpus.liveRefPrefixes` is what distinguishes a row that ARRIVED from one
# that was imported out of a file, and it is what lets a followed channel's
# posts reach the All feed. If the two spellings drift, every post still lands
# and none of them is ever seen — the room fills, All stays empty, and nothing
# anywhere reports an error.
grep -qF 'static let refPrefix = "telegram:post:"' "$CHANNEL" \
  || { echo "✗ TelegramChannel.refPrefix moved — it must be the literal \"telegram:post:\""; exit 1; }
grep -qF '"telegram:post:"' "$THING" \
  || { echo "✗ \"telegram:post:\" is not in Corpus.liveRefPrefixes — followed-channel posts land and never reach the All feed"; exit 1; }

# (2) THE REVERSE. `refresh` takes `items.prefix(15)` because every feed format
# on earth is newest-first, and `t.me/s/<channel>` is the one that is not. Drop
# this and the ingest is handed the fifteen OLDEST posts on the page: the room
# fills with a wall of real rows and never shows today.
grep -qF 'channel.posts.reversed().map' "$FOLLOW" \
  || { echo "✗ the Telegram mapper no longer reverses the posts — prefix(15) then takes the fifteen OLDEST and the room never shows today"; exit 1; }

# (3) THE ARM ITSELF.
grep -qE 'case telegram = "Telegram"' "$FOLLOW" \
  || { echo "✗ FeedFollowKind has no telegram case — the seat has no arm to read"; exit 1; }
grep -qF 'TelegramChannel.parse(html, handle: handle)' "$FOLLOW" \
  || { echo "✗ the feed-follow arm no longer routes a channel page through the parser"; exit 1; }

# (4) NEGATIVE — the view count stays REFUSED (rule 7). The page publishes it
# already rounded ("12.6M") and the only field that could hold it is an Int, so
# landing it turns a rounded string into a precise number nobody measured — a
# figure that looks exactly like a fact (§83). Read from the comment-stripped
# copy, because rule 7 explains itself by naming the field.
#
# Two spellings, because the refusal can be undone from either end: a FIELD to
# hold the number, or the page's own `tgme_widget_message_views` counter being
# read at all. `viewCount` is matched anywhere rather than only as a property —
# which is exactly why the stripped copy is required, since rule 7's own prose
# names `Thing.viewCount` and would satisfy a raw grep on the comment alone.
if grep -qE 'viewCounts?\b' "$TMP/channel.nc"; then
  echo "✗ TelegramChannel names a view count — the page publishes it PRE-ROUNDED (\"12.6M\") and the only field that could hold it is an Int, so landing it turns a rounded string into a precise number nobody measured (rule 7, §83)"; exit 1
fi
if grep -qE '(var|let)[[:space:]]+views\b|tgme_widget_message_views' "$TMP/channel.nc"; then
  echo "✗ TelegramChannel reads the page's view counter — see rule 7: that number is already rounded on the wire, so any precision it lands is invented"; exit 1
fi

echo "telegram-selftest: drift guards ✓"

# --- the IngestSupport stub, extracted from the real file --------------------
python3 - "$SUPPORT" "$TMP/support.swift" <<'PY'
import sys
support, out = sys.argv[1], sys.argv[2]

def grab(path, signature):
    """The whole function whose declaration line contains `signature`,
    brace-matched from the shipped source. Never a copy — if the real file
    renames or moves one of these, this fails loudly instead of asserting
    against a stale duplicate."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return src[start:k + 1].replace("private ", "")

pieces = [
    "import Foundation\n",
    "enum IngestSupport {",
    grab(support, "static func decodeHTMLEntities"),
    grab(support, "static func imageURL"),
    "}",
]
open(out, "w").write("\n".join(pieces) + "\n")
PY

# --- the assertions ---------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

// LINE-BUFFERED, deliberately. The mutation pass runs this binary with its
// output captured, so stdout is a pipe and therefore block-buffered — and a
// trap kills the process without flushing. That is how the single most
// important mutation here (rule 3, the dropped newest post) first reported
// itself as "caught by a TRAP, no ✗ printed" when in fact the ✗ had been
// written and thrown away. A harness whose failures can be swallowed is the
// `-O` trapping-harness lesson wearing a different hat.
setvbuf(stdout, nil, _IOLBF, 0)

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

// ---------------------------------------------------------------------------
// ONE synthetic page, built to the shapes measured on 2026-08-23. Nothing here
// is fetched: a harness that needs the network is one that cannot run in
// `verify.sh` and cannot be trusted to mean the same thing twice.
//
// Four messages, published OLDEST FIRST as t.me/s/ really does:
//   101  a VIDEO post — opens with a duration `<time>` carrying no `datetime`,
//        and whose only background-image is an emoji sprite
//   102  a PHOTO post — emoji sprite FIRST, real telesco.pe picture second,
//        forwarded, and whose text container nests a `<div>`
//   103  chrome we do not recognise: a wrapper with no words, no picture, no
//        video. It must be DROPPED rather than landed as an empty row.
//   104  the NEWEST post, and therefore the LAST element on the page
// ---------------------------------------------------------------------------
let page = """
<html><head>
<meta property="og:title" content="Du&amp;rov">
<meta property="og:description" content="Thoughts &amp; things">
<meta property="og:image" content="//cdn1.telesco.pe/file/avatar.jpg">
</head><body>
<div class="tgme_widget_message" data-post="durov/101">
<div class="tgme_widget_message_text js-message_text">A clip</div>
<time class="message_video_duration">0:42</time>
<time datetime="2026-06-09T19:33:51+00:00" class="time">Jun 9</time>
<div class="tgme_widget_message_video_wrap"><i class="emoji" style="background-image:url('//telegram.org/img/emoji/40/E28C9A.png')"><b>&#8986;</b></i></div>
</div>
<div class="tgme_widget_message" data-post="durov/102">
<div class="tgme_widget_message_forwarded_from">\
<a class="tgme_widget_message_forwarded_from_name" href="/telegram/1"><span dir="auto">Pavel Durov</span></a>\
<span class="tgme_widget_message_forwarded_from_author">(Pavel Durov)</span></div>
<div class="tgme_widget_message_text">Look at this<div class="inner">and this</div></div>
<i class="emoji" style="background-image:url('//telegram.org/img/emoji/40/E29CA8.png')"><b>&#10024;</b></i>
<a class="tgme_widget_message_photo_wrap" style="background-image:url('https://cdn4.telesco.pe/file/realphoto')"></a>
<time datetime="2026-06-11T17:54:31+00:00" class="time">Jun 11</time>
</div>
<div class="tgme_widget_message" data-post="durov/103">
<div class="tgme_widget_message_footer"></div>
</div>
<div class="tgme_widget_message" data-post="durov/104">
<div class="tgme_widget_message_text">The newest thing</div>
<div class="link_preview_title">Some Article</div>
<time datetime="2026-06-13T20:15:20+00:00" class="time">Jun 13</time>
</div>
</body></html>
"""

print("TelegramChannel")

// --- rule 3: the LAST message is the one a lookahead match drops ------------
// And by rule 2 the last message is the NEWEST, so this is the difference
// between a room that shows today and one that never does.
let frags = TelegramChannel.messageFragments(in: page)
check("every wrapper on the page yields a fragment, the LAST one included",
      frags.count == 4 && frags.map(\.0) == ["durov/101", "durov/102", "durov/103", "durov/104"])
check("…and the last fragment really carries its own contents, not an empty slice",
      (frags.last?.1 ?? "").contains("The newest thing"))

// --- the page as a whole ---------------------------------------------------
guard let channel = TelegramChannel.parse(page, handle: "Durov") else {
    print("  ✗ parse returned nil for a real channel page — nothing below can run")
    exit(1)
}
check("the channel is named off og:title, decoded", channel.title == "Du&rov")
check("…its blurb off og:description, decoded", channel.about == "Thoughts & things")
check("…and its avatar normalised to https by the shared image rule",
      channel.avatarURL == "https://cdn1.telesco.pe/file/avatar.jpg")
check("the handle comes off the PAGE, not off the typed input", channel.handle == "durov")

// The page's OWN casing, folded. This needs its own fixture and cannot ride the
// page above: everything there is already spelled `durov`, so the fold would be
// satisfied by an input that never exercised it — a fixture only tests the rule
// it names if it FAILS that rule and passes every other one. Two follows, one
// typed "Durov" and one typed "durov", must not land the same post twice under
// two refs that `sourceRef` cannot see are the same.
let capitalised = """
<div class="tgme_widget_message" data-post="Durov/900">\
<div class="tgme_widget_message_text">Same post</div></div>
"""
let folded = TelegramChannel.parse(capitalised, handle: "durov")
check("a channel the page spells with capitals is folded, so one post cannot land under two refs",
      folded?.posts.first?.channel == "durov"
      && folded?.posts.first?.ref == "telegram:post:durov/900"
      && folded?.handle == "durov")

// --- rule 2: ascending, and `newest` means it -------------------------------
check("posts arrive OLDEST FIRST, exactly as the page publishes them",
      channel.posts.map(\.id) == [101, 102, 104])
check("…so the newest post is the LAST one, not the first",
      channel.newest?.id == 104 && channel.newest?.text == "The newest thing")

// --- a wrapper that is neither words nor picture nor video is DROPPED -------
check("a message with no words, no photograph and no video is dropped rather than landed empty",
      !channel.posts.contains { $0.id == 103 })

// --- rule 5: the emoji decoy -----------------------------------------------
// Looked up BY ID, never by position: a mutation that drops a post shifts every
// index, and a subscript out of range TRAPS — which under `-O` takes the whole
// harness down mid-run and reports nothing at all, so the mutation would read
// as caught while the assertion that should have caught it never ran.
func post(_ id: Int) -> TelegramChannel.Post {
    channel.posts.first { $0.id == id }
        ?? TelegramChannel.Post(channel: "", id: -1, text: "<missing>", date: nil,
                                photoURL: nil, hasVideo: false,
                                forwardedFrom: nil, linkTitle: nil)
}
let clip = post(101)
let photo = post(102)
let newest = post(104)
check("a post whose only background-image is an emoji sprite has NO photograph",
      clip.photoURL == nil)
check("…while a post carrying a sprite AND a real picture takes the picture",
      photo.photoURL == "https://cdn4.telesco.pe/file/realphoto")
check("a video post is recorded as one", clip.hasVideo && !photo.hasVideo)

// --- rule 4: the text container can nest a div ------------------------------
check("a nested <div> inside the text container does not truncate the post",
      photo.text == "Look at thisand this")

// --- the forward, and the second span beside it ----------------------------
check("a forward names its source, and only its name — never the author span repeated beside it",
      photo.forwardedFrom == "Pavel Durov")
check("…and a post the channel wrote itself names nobody",
      clip.forwardedFrom == nil)
check("a link preview's headline is kept",
      newest.linkTitle == "Some Article" && clip.linkTitle == nil)

// --- the date, through the whole parse -------------------------------------
check("a video post is dated from the `<time>` that CARRIES a datetime, not from its clip duration",
      clip.date == Date(timeIntervalSince1970: 1781033631))

// --- refs and links ---------------------------------------------------------
check("the ref is the shared namespace plus channel/id",
      TelegramChannel.refPrefix == "telegram:post:"
      && channel.newest?.ref == "telegram:post:durov/104")
check("the permalink is the PUBLIC post URL, never the /s/ preview we read",
      channel.newest?.url == "https://t.me/durov/104"
      && TelegramChannel.previewURL(for: "durov") == "https://t.me/s/durov")
check("a post with no words of its own is wordless, and one with words is not",
      TelegramChannel.Post(channel: "durov", id: 1, text: "", date: nil, photoURL: "p",
                           hasVideo: false, forwardedFrom: nil, linkTitle: nil).isWordless
      && !(channel.newest?.isWordless ?? true))

// ---------------------------------------------------------------------------
// datetime(in:) — asserted on its own, because the whole rule is about WHICH
// `<time>` is read and a fragment with one `<time>` cannot express that.
// ---------------------------------------------------------------------------
let durationFirst = """
<time class="message_video_duration">1:12</time>\
<time datetime="2026-06-09T19:33:51+00:00" class="time">Jun 9</time>
"""
check("a <time> with no datetime attribute is SKIPPED, and the later real one is read",
      TelegramChannel.datetime(in: durationFirst) == "2026-06-09T19:33:51+00:00")
check("…and a fragment whose only <time> is a clip duration yields NO date at all",
      TelegramChannel.datetime(in: "<time class=\"message_video_duration\">1:12</time>") == nil)

// ---------------------------------------------------------------------------
// element(in:withClassContaining:) — depth, and the INFERRED tag.
// ---------------------------------------------------------------------------
let nested = """
<div class="tgme_widget_message_text">before<div class="inner">middle</div>after</div><div>outside</div>
"""
check("the element's end is found by DEPTH, so a nested div cannot close it early",
      TelegramChannel.element(in: nested, withClassContaining: "tgme_widget_message_text")
        == "before<div class=\"inner\">middle</div>after")

// Both shapes are real and were measured the same day, one channel each: a
// forward from a PUBLIC channel names its source in an `<a>` (it links back to
// the original post), a forward from a private one in a `<span>`. A caller
// passing a fixed tag reads one and silently returns nothing for the other,
// which looks exactly like a channel that never forwards anything.
let asLink = "<a class=\"tgme_widget_message_forwarded_from_name\" href=\"/x/1\">Pavel Durov</a>"
let asSpan = "<span class=\"tgme_widget_message_forwarded_from_name\">Pavel Durov</span>"
check("the tag is INFERRED, so an <a> forward reads",
      TelegramChannel.element(in: asLink, withClassContaining: "tgme_widget_message_forwarded_from_name")
        == "Pavel Durov")
check("…and a <span> forward reads through the same call",
      TelegramChannel.element(in: asSpan, withClassContaining: "tgme_widget_message_forwarded_from_name")
        == "Pavel Durov")
check("the enclosing tag is read off the markup",
      TelegramChannel.enclosingTag(in: asSpan, before: asSpan.range(of: "tgme")!.lowerBound) == "span"
      && TelegramChannel.enclosingTag(in: asLink, before: asLink.range(of: "tgme")!.lowerBound) == "a")
check("an absent class is nil rather than an empty string",
      TelegramChannel.element(in: nested, withClassContaining: "nothing_like_this") == nil)

// ---------------------------------------------------------------------------
// plainText — one fixture per rule, each of which must FAIL its own rule and
// pass every other one, or it is testing nothing.
// ---------------------------------------------------------------------------
check("<br> becomes a newline BEFORE the tags are stripped",
      TelegramChannel.plainText("a<br>b") == "a\nb"
      && TelegramChannel.plainText("a<br/>b") == "a\nb"
      && TelegramChannel.plainText("a<BR />b") == "a\nb")
check("an emoji's real character survives while its sprite does not",
      TelegramChannel.plainText(
        "<i class=\"emoji\" style=\"background-image:url('//telegram.org/img/emoji/40/E28C9A.png')\"><b>⌚️</b></i> now")
        == "⌚️ now")
check("&nbsp; folds to an ordinary space — it is not in the shared decoder and Telegram uses it constantly",
      TelegramChannel.plainText("с&nbsp;Украиной") == "с Украиной")
check("…and the shared decoder still runs for the entities that ARE its job",
      TelegramChannel.plainText("Q&amp;A") == "Q&A")
check("Telegram's own placeholder is chrome, not the author's words",
      TelegramChannel.plainText("Watch this<br>Please open Telegram to view this post") == "Watch this")

// ---------------------------------------------------------------------------
// isPhotograph — matched on the LABEL BOUNDARY, never `contains`.
// ---------------------------------------------------------------------------
check("a real picture on the media CDN is a photograph",
      TelegramChannel.isPhotograph("https://cdn4.telesco.pe/file/abc")
      && TelegramChannel.isPhotograph("//cdn1.telesco.pe/file/abc"))
check("an emoji sprite is REFUSED — every emoji on the page is a background-image",
      !TelegramChannel.isPhotograph("//telegram.org/img/emoji/40/E28C9A.png"))
check("…and so is a host that merely CONTAINS the CDN's name",
      !TelegramChannel.isPhotograph("https://telesco.pe.attacker.example/file/abc")
      && !TelegramChannel.isPhotograph("https://nottelesco.pe/file/abc"))
check("a string that is not a URL at all is refused rather than trusted",
      !TelegramChannel.isPhotograph("telesco.pe"))

// ---------------------------------------------------------------------------
// timestamp — an offset is always present, so no calendar of ours is involved.
// Asserted to the SECOND: a date that lands a day out is this parser's most
// expensive possible mistake.
// ---------------------------------------------------------------------------
check("an ISO instant parses to the exact second",
      TelegramChannel.timestamp("2026-06-09T19:33:51+00:00")
        == Date(timeIntervalSince1970: 1781033631))
check("…and a fractional-seconds form still parses through the fallback",
      TelegramChannel.timestamp("2026-06-09T19:33:51.250+00:00")
        == Date(timeIntervalSince1970: 1781033631.25))
check("something that is not a date at all is nil, never now",
      TelegramChannel.timestamp("Jun 9") == nil)

// ---------------------------------------------------------------------------
// normalizeHandle / isValidHandle — refusing here is what keeps a typo from
// becoming a request for somebody else's page.
// ---------------------------------------------------------------------------
for (raw, want) in [("@Durov", "durov"), ("https://t.me/durov", "durov"),
                    ("https://t.me/s/durov", "durov"), ("t.me/durov/523", "durov"),
                    ("DUROV", "durov"), ("  telegram.me/durov  ", "durov"),
                    ("https://t.me/durov?single", "durov")] {
    check("\(raw) names the channel \(want)", TelegramChannel.normalizeHandle(raw) == want)
}
check("a name Telegram could serve is accepted",
      TelegramChannel.isValidHandle("durov") && TelegramChannel.isValidHandle("du_rov9"))
check("…a name too short for Telegram is refused before it becomes a request",
      !TelegramChannel.isValidHandle("abcd"))
check("…a leading digit is refused (Telegram usernames start with a letter)",
      !TelegramChannel.isValidHandle("1abcd"))
check("…and a private INVITE link names no channel at all",
      !TelegramChannel.isValidHandle(TelegramChannel.normalizeHandle("t.me/+AbCdEfGh")))
check("…as does a name past 32 characters",
      !TelegramChannel.isValidHandle(String(repeating: "a", count: 33)))

// ---------------------------------------------------------------------------
// standing — three different answers where there would otherwise be one empty
// room, and only `.unknown` is a bug.
// ---------------------------------------------------------------------------
check("a landing page counting MEMBERS is a group, which has no public preview and never will",
      TelegramChannel.standing(
        "<div class=\"tgme_page_extra\">97 184 members, 4 430 online</div>") == .group)
check("…one counting SUBSCRIBERS is a real channel with its preview switched off",
      TelegramChannel.standing(
        "<div class=\"tgme_page_extra\">11 084 647 subscribers</div>") == .channelWithoutPreview)
check("…one with no counter at all is a name nobody has claimed",
      TelegramChannel.standing("<div class=\"tgme_page_wrap\"></div>") == .absent)
check("…and a body that is not a t.me page says so rather than guessing",
      TelegramChannel.standing("<html><body>hello</body></html>") == .unknown)

// ---------------------------------------------------------------------------
// parse refuses a body that is not a channel page: reporting an empty channel
// would be a CLAIM, and a redirect, an error page and an interstitial all look
// identical from here.
// ---------------------------------------------------------------------------
check("a body with no message markup is nil, never an empty channel",
      TelegramChannel.parse("<html><body>Telegram</body></html>", handle: "durov") == nil)
check("…and a malformed data-post is skipped rather than filed under a guessed channel",
      TelegramChannel.parse(
        "<div class=\"tgme_widget_message\" data-post=\"noslash\">"
        + "<div class=\"tgme_widget_message_text\">x</div></div>", handle: "durov")?.posts.isEmpty == true)

print("")
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all assertions passed")
SWIFT

echo "telegram-selftest: compiling the parser WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$CHANNEL" "$TMP/support.swift" "$TMP/main.swift" \
  || { echo "✗ TelegramChannel does not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a SILENT WRONG ANSWER that renders as an ordinary
# feed. A mutation that survives means nothing above was testing that line, and
# the assertion should be rewritten rather than shipped.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" frm="$2" to="$3"
  cp "$CHANNEL" "$TMP/TelegramChannel.swift"
  # The python exit is tested INLINE, not through `$?` on the next line: this
  # script runs under `set -e`, so a failed edit would kill the run before the
  # check could report it — a mutation that never applied would read as the
  # whole harness dying with no message at all.
  local applied=1
  FRM="$frm" TO="$to" python3 - "$TMP/TelegramChannel.swift" <<'PY' && applied=0
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if (( applied != 0 )) || ! grep -qF -- "$to" "$TMP/TelegramChannel.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$TMP/TelegramChannel.swift" "$TMP/support.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  # A TRAP and an assertion both exit non-zero, and under `-O` a trapping
  # harness prints NOTHING — so "caught" alone does not say the assertion above
  # is the thing doing the catching. Both are recorded, and the run is kept, so
  # a mutation caught only by a crash is visible rather than mistaken for
  # coverage. (retriever-selftest's own lesson, one file over.)
  local out rc
  out="$("$TMP/mut" 2>&1)" && rc=0 || rc=$?
  if (( rc == 0 )); then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  if print -r -- "$out" | grep -q '✗'; then
    echo "  ✓ $name"
  else
    echo "  ✓ $name (caught by a TRAP, not by an assertion — no ✗ printed)"
  fi
}

# RULE 3, and the most expensive line in the file. The last wrapper on the page
# is the NEWEST post, so a slice that needs a FOLLOWING wrapper to close the
# current one drops today's news and nothing else. Nineteen of twenty rows land;
# the room looks full.
mutate "the last fragment is dropped" \
  '            let end = index + 1 < starts.count ? starts[index + 1].1 : html.endIndex' \
  '            let end = index + 1 < starts.count ? starts[index + 1].1 : entry.1'

# RULE 2 inverted. `newest` is what the room and the ingest both ask for, and
# on an oldest-first page `first` is the oldest post the page still carries.
mutate "the newest post is taken as the first" \
  '        var newest: Post? { posts.last }' \
  '        var newest: Post? { posts.first }'

# RULE 5, twice. The page carries 99 emoji sprites and 40 real pictures
# (measured on @durov), so a photo read that trusts any background-image files
# an emoji as the post's photograph — on nearly every post.
mutate "the media host check is dropped entirely" \
  '        return host == "telesco.pe" || host.hasSuffix(".telesco.pe")' \
  '        return !host.isEmpty'

# …and the WEAKER version of the same mistake: a `contains` instead of a label
# match, which lets `telesco.pe.attacker.example` pass for the CDN.
mutate "the host match becomes a contains" \
  '        return host == "telesco.pe" || host.hasSuffix(".telesco.pe")' \
  '        return host.contains("telesco.pe")'

# The `datetime` REQUIREMENT — i.e. reading the first `<time>` blindly. A video
# post's first `<time>` is its clip duration, so every video post falls back to
# "now" and a four-month-old broadcast files as today (15 of 20 measured).
mutate "the datetime attribute stops being required" \
  '            if let attr = inside.range(of: "datetime=\""),' \
  '            if let attr = inside.range(of: "class=\""),'

# RULE 6. Telegram's own placeholder read as the author's sentence — the row's
# words become "Please open Telegram to view this post".
mutate "the chrome strip is removed" \
  '        s = s.replacingOccurrences(of: chrome, with: "")' \
  '        s = s.replacingOccurrences(of: chrome, with: chrome)'

# `&nbsp;` is not in the shared decoder, and Telegram uses it for typographic
# spacing constantly — "с&nbsp;Украиной" landed raw, in the middle of a sentence.
mutate "the &nbsp; fold is removed" \
  '        s = s.replacingOccurrences(of: "&nbsp;", with: " ")' \
  '        s = s.replacingOccurrences(of: "&nbsp;", with: "&nbsp;")'

# `<br>` collapsing every multi-paragraph post onto one line.
mutate "<br> stops becoming a newline" \
  '            s = s.replacingOccurrences(of: br, with: "\n", options: .caseInsensitive)' \
  '            s = s.replacingOccurrences(of: br, with: "", options: .caseInsensitive)'

# RULE 4. A nested div closing the text container early truncates exactly those
# posts mid-sentence, and only those — so most of the room is perfect.
mutate "the element scan stops counting depth" \
  '                depth += 1
                cursor = o.upperBound' \
  '                depth += 0
                cursor = o.upperBound'

# The tag INFERENCE. Hardcoding `div` reads a `<span>` forward and returns
# nothing for the `<a>` shape (or the reverse), which looks exactly like a
# channel that never forwards anything.
mutate "the enclosing tag is hardcoded rather than inferred" \
  '        guard let tag = enclosingTag(in: html, before: mark.lowerBound) else { return nil }' \
  '        let tag = "div"'

# A wrapper we could not read landing as a row with nothing in it.
mutate "an empty message is landed instead of dropped" \
  '        guard !post.text.isEmpty || post.photoURL != nil || post.hasVideo else { return nil }' \
  '        guard true else { return nil }'

# A redirect, an error page or an interstitial reported as a real channel with
# no posts — which is a CLAIM, and the wrong one.
mutate "a body that is not a channel page still parses" \
  '        guard html.contains("tgme_widget_message") || html.contains("tgme_channel_info") else {' \
  '        guard true || html.contains("tgme_channel_info") else {'

# The 302 discriminator collapsed: a group reported as a channel whose owner
# turned the preview off, so the app tells somebody to go and switch on a
# setting that does not exist for what they followed.
mutate "a group is reported as a channel with its preview off" \
  '        if extra.contains("member") { return .group }' \
  '        if extra.contains("member") { return .channelWithoutPreview }'

# The date read with a formatter that cannot parse what the page serves —
# every post undated, and an undated post falls back to now.
mutate "the ISO formatter stops accepting the page's own format" \
  '        f.formatOptions = [.withInternetDateTime]' \
  '        f.formatOptions = [.withFullDate]'

# A follow typed "Durov" and one typed "durov" landing the SAME post under two
# refs — a duplicate row, with `sourceRef` unable to see it.
mutate "the post keeps the page's own casing instead of folding it" \
  '            channel: channel.lowercased(),' \
  '            channel: channel,'

# `t.me/s/<name>` is the preview URL somebody pastes back in. Left unstripped it
# follows a channel literally called "s".
mutate "the /s/ preview prefix is no longer stripped from a pasted URL" \
  '        if s.lowercased().hasPrefix("s/") { s = String(s.dropFirst(2)) }' \
  '        if s.lowercased().hasPrefix("zzz/") { s = String(s.dropFirst(2)) }'

# A leading digit accepted, i.e. a name Telegram will never serve becoming a
# request that answers 302 and reads as "not a channel".
mutate "a handle may start with a digit" \
  '        guard let first = handle.first, first.isLetter else { return false }' \
  '        guard let first = handle.first, first.isLetter || first.isNumber else { return false }'

echo ""
echo "telegram-selftest: OK"
