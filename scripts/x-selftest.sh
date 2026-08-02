#!/bin/zsh
# Casberi X self-test — verifies the SHIPPED pure logic behind both halves of
# the X work (prd §280, 2026-08-02):
#
#   Casberi/Casberi/Model/OEmbed.swift
#     — blockquoteText   (the words lifted out of an X embed, the ONLY reason
#                         an X link gets a face at all)
#   Casberi/Casberi/Model/XArchiveImport.swift
#     — snowflakeDate    (the only date a liked post will ever have)
#     — parseArray       (the archive's files are JavaScript, not JSON)
#     — clean            (t.co → real link, and the entity decode)
#     — identifier       (id_str vs a numeric id past Double's exact range)
#
# WHY A HARNESS AND NOT A SIM CHECK. The archive importer was authored against
# no real X archive, and every failure mode here is a SILENT WRONG ANSWER
# rather than a crash: a liked post dated to the snowflake epoch instead of
# refused, an archive that parses to zero rows and reads as an empty account,
# a post indexed as "Q&amp;A". All of those render and look plausible. The only
# way to know they're right is to feed them inputs whose answers are known.
#
# Both files are far too entangled to compile as shipped (SwiftData models, a
# ModelContext, SpotlightIndex), so the pure functions are EXTRACTED from the
# shipped source by name — never copied into this file — so the harness cannot
# pass against logic the app doesn't run. The only transformation is stripping
# `private `. If an extraction stops matching, the compile fails loudly rather
# than asserting nothing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

OEMBED="Casberi/Casberi/Model/OEmbed.swift"
XARCH="Casberi/Casberi/Model/XArchiveImport.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
for f in "$OEMBED" "$XARCH" "$SUPPORT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Each of these is a wiring fact the extracted functions can't prove on their
# own: a perfect `blockquoteText` is worthless if `parse` stops calling it, and
# a perfect `snowflakeDate` is worthless if likes stop being dated by it.
grep -q '"https://publish.x.com/oembed' "$OEMBED" \
  || { echo "✗ OEmbed no longer carries the X endpoint"; exit 1; }
grep -q '"x.com", "twitter.com"' "$OEMBED" \
  || { echo "✗ OEmbed's X row no longer covers both hosts"; exit 1; }
grep -q 'text("title") ?? blockquoteText' "$OEMBED" \
  || { echo "✗ parse no longer falls back to the embed's blockquote"; exit 1; }
grep -q 'snowflakeDate(id)' "$XARCH" \
  || { echo "✗ likes are no longer dated from the post id"; exit 1; }
grep -q 'raw.hasPrefix("RT @")' "$XARCH" \
  || { echo "✗ reposts are no longer skipped"; exit 1; }
grep -q '"X"' Casberi/Shared/Thing.swift \
  || { echo "✗ X is not a bulk-import source — its rows would flood All"; exit 1; }

TMP=$(mktemp -d /tmp/x-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped functions -----------------------------------------
python3 - "$OEMBED" "$XARCH" "$SUPPORT" "$TMP/extracted.swift" <<'PY'
import re, sys
oembed, xarch, support, out = sys.argv[1:5]

def grab(path, signature):
    """The whole function whose declaration line contains `signature`,
    brace-matched from the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

def grabvar(path, signature):
    """A computed/lazy `static let` initialised with a closure."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    end = src.index("\n", k)
    return src[start:end].replace("private ", "")

pieces = [
    "import Foundation\n",
    "enum IngestSupport {",
    grab(support, "static func decodeHTMLEntities"),
    "}\n",
    "enum OEmbed {",
    grab(oembed, "static func blockquoteText"),
    "}\n",
    "enum XArchiveImport {",
    grab(xarch, "static func snowflakeDate"),
    grab(xarch, "static func parseArray"),
    grab(xarch, "static func clean"),
    grab(xarch, "static func identifier"),
    grab(xarch, "static func created"),
    grabvar(xarch, "static let twitterDateFormatter"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func iso(_ d: Date?) -> String {
    guard let d else { return "nil" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

print("blockquoteText — the words out of an X embed")
// The exact payload publish.x.com returned for x.com/jack/status/20 (measured
// 2026-08-02), reproduced byte for byte.
let jack = "<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">just setting up my twttr</p>&mdash; jack (@jack) <a href=\"https://x.com/jack/status/20?ref_src=twsrc%5Etfw\">March 21, 2006</a></blockquote>\n\n"
check("lifts the post's own words", OEmbed.blockquoteText(jack) == "just setting up my twttr")

// The @XDevelopers payload — <br><br> paragraphing and a trailing t.co anchor.
let devs = "<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">API Posting will increase to $0.015 per post from $0.01.<br><br>More details: <a href=\"https://t.co/vdqTnQxJil\">https://t.co/vdqTnQxJil</a></p>&mdash; Developers (@XDevelopers) <a href=\"https://x.com/XDevelopers/status/2044919377544261979\">April 16, 2026</a></blockquote>"
let devText = OEmbed.blockquoteText(devs)
check("<br> becomes a space, not a join",
      devText == "API Posting will increase to $0.015 per post from $0.01. More details: https://t.co/vdqTnQxJil")
check("the attribution line is left out",
      !(devText ?? "").contains("XDevelopers") && !(devText ?? "").contains("April 16"))

// ORDER: entities are decoded AFTER tags are stripped. If that flips, an
// escaped tag somebody actually typed becomes a real tag and gets eaten.
let escaped = "<blockquote><p>use &lt;b&gt;bold&lt;/b&gt; sparingly &amp; well</p></blockquote>"
check("an escaped tag survives as text",
      OEmbed.blockquoteText(escaped) == "use <b>bold</b> sparingly & well")

check("no <p> at all (an iframe embed) → nil", OEmbed.blockquoteText("<iframe src=\"x\"></iframe>") == nil)
check("an empty <p> → nil", OEmbed.blockquoteText("<blockquote><p></p></blockquote>") == nil)
check("nil in → nil out", OEmbed.blockquoteText(nil) == nil)
check("a page-sized payload is refused",
      OEmbed.blockquoteText("<p>" + String(repeating: "a", count: 70_000) + "</p>") == nil)

print("snowflakeDate — the only date a like will ever have")
// LIVE-VERIFIED: publish.x.com independently reports "April 16, 2026" for this
// same post. If this assertion ever fails, the epoch or the shift is wrong and
// every imported like is silently misdated.
check("2044919377544261979 → 2026-04-16",
      iso(XArchiveImport.snowflakeDate("2044919377544261979")) == "2026-04-16")
// To the MILLISECOND, and deliberately so: the day alone is far too coarse to
// hold the epoch constant honest. A first pass of this harness asserted only
// the date, and a mutation that moved the epoch by 657ms passed it clean —
// the constant could have been meaningfully wrong with nothing to catch it.
check("…and to the exact millisecond (the epoch constant itself)",
      XArchiveImport.snowflakeDate("2044919377544261979")?.timeIntervalSince1970 == 1_776_381_747.028)
check("1738963372425732512 → 2023-12-24",
      iso(XArchiveImport.snowflakeDate("1738963372425732512")) == "2023-12-24")
// id 20 decodes to the epoch itself (2010-11-04) — a confident wrong answer,
// which is exactly why anything pre-snowflake is refused instead.
check("the first tweet (id 20) is refused, not dated to the epoch",
      XArchiveImport.snowflakeDate("20") == nil)
check("a pre-snowflake id just under the floor is refused",
      XArchiveImport.snowflakeDate("29999999999") == nil)
check("the first snowflake id is accepted",
      XArchiveImport.snowflakeDate("30000000000") != nil)
check("garbage → nil", XArchiveImport.snowflakeDate("not-an-id") == nil)
check("empty → nil", XArchiveImport.snowflakeDate("") == nil)

print("parseArray — the files are JavaScript, not JSON")
let js = "window.YTD.tweets.part0 = [{\"tweet\":{\"id_str\":\"1\"}}]"
check("the assignment prefix is cut",
      XArchiveImport.parseArray(Data(js.utf8))?.count == 1)
check("plain JSON still reads",
      XArchiveImport.parseArray(Data("[{\"a\":1}]".utf8))?.count == 1)
check("a multi-part file's own name doesn't matter",
      XArchiveImport.parseArray(Data("window.YTD.like.part17 = [{\"like\":{}},{\"like\":{}}]".utf8))?.count == 2)
check("not an archive file → nil",
      XArchiveImport.parseArray(Data("hello".utf8)) == nil)
check("empty → nil", XArchiveImport.parseArray(Data()) == nil)

print("clean — t.co expansion and the entity decode")
let entities: [String: Any] = ["urls": [["url": "https://t.co/abc",
                                         "expanded_url": "https://example.com/real-page"]]]
check("t.co is swapped for the real destination",
      XArchiveImport.clean("read this https://t.co/abc", entities: entities)
        == "read this https://example.com/real-page")
check("&amp; is decoded",
      XArchiveImport.clean("Q&amp;A tonight", entities: nil) == "Q&A tonight")
check("a link with no expansion is left, not dropped",
      XArchiveImport.clean("see https://t.co/zzz", entities: entities) == "see https://t.co/zzz")
check("whitespace is trimmed", XArchiveImport.clean("  hi  ", entities: nil) == "hi")
check("empty stays empty", XArchiveImport.clean("", entities: nil) == "")

print("identifier — a snowflake is past Double's exact range")
check("id_str is preferred",
      XArchiveImport.identifier(["id_str": "2044919377544261979", "id": 1]) == "2044919377544261979")
check("a string id is read when id_str is absent",
      XArchiveImport.identifier(["id": "123456789012345678"]) == "123456789012345678")
check("no id at all → nil", XArchiveImport.identifier(["full_text": "hi"]) == nil)

print("created — created_at, then the id")
check("X's own date format parses",
      iso(XArchiveImport.created(["created_at": "Wed Mar 21 20:50:14 +0000 2006"], id: "20")) == "2006-03-21")
check("a missing created_at falls back to the id",
      iso(XArchiveImport.created([:], id: "2044919377544261979")) == "2026-04-16")
check("neither → nil", XArchiveImport.created([:], id: "20") == nil)

print("")
if failures > 0 { print("x-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("x-selftest: OK — every assertion passed against the shipped source.")
SWIFT

if ! swiftc -O -o "$TMP/x-selftest" "$TMP/extracted.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/x-selftest"
