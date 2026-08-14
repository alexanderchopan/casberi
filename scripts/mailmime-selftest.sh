#!/bin/zsh
# Casberi MIME self-test — `MailMIME.attachmentNames` (2026-08-14).
#
# WHY IT NEEDS ONE. This is a parser pointed at bytes a STRANGER wrote: anyone
# who can email you controls every header it reads. It is also the only new
# logic in the Life-bridge enrichment pass that has no other check — no build
# error, no audit and no screen can tell a filename read correctly from one
# read wrongly, because both render as a perfectly ordinary row.
#
# The failures it catches, all silent:
#
#   • an attachment named `../../etc/passwd` drawn verbatim on the sheet — this
#     app writes no file, so it is not a traversal, but a row stating an
#     arrival that did not happen is the §83 fake fact with a hostile author;
#   • a `text/plain; name="body.txt"` part read as a file somebody sent you,
#     which turns nearly every multipart mail into one carrying an attachment;
#   • the inverse — a PDF sent `Content-Disposition: inline`, extremely common,
#     silently reporting nothing attached;
#   • a nested `multipart/mixed > multipart/alternative` where the file sits
#     beside the text, so a non-recursive walk finds the words every time and
#     the file only sometimes;
#   • a filename from a non-English sender arriving as `=?UTF-8?B?…?=` and
#     being drawn as that literal gibberish;
#   • a part whose boundary equals its parent's, which walks the same bytes
#     until the process dies.
#
# `MailMIME.swift` compiles WHOLE and UNMODIFIED — never a copy — against two
# INERT stubs, which is the whole reason it can: it reaches exactly two symbols
# outside itself, `IMAPClient.decodeHeaderWord` and
# `IngestSupport.decodeHTMLEntities`, and neither is Foundation.
#
# The decoder stub does NOT decode, deliberately. It wraps its input, so the
# encoded-word assertion below proves the filename is really ROUTED through the
# shared decoder; a stub that decoded correctly would pass just as happily
# against a version that never calls it.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MIME="Casberi/Casberi/Model/MailMIME.swift"
IMAP="Casberi/Casberi/Model/IMAPClient.swift"
BRIDGE="Casberi/Casberi/Model/MailBridge.swift"
for f in "$MIME" "$IMAP" "$BRIDGE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/mailmime-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Comment-stripped, because both files DOCUMENT the behaviour this replaced
# ("Anything else (an attachment, an image) is skipped") and a guard grepping
# raw source fires on the prose explaining the fix.
python3 - "$IMAP" "$BRIDGE" "$TMP/imap.bare" "$TMP/bridge.bare" <<'PY'
import re, sys
for src_path, out_path in ((sys.argv[1], sys.argv[3]), (sys.argv[2], sys.argv[4])):
    src = open(src_path).read()
    src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
    src = re.sub(r'(?<![:/])//.*$', '', src, flags=re.M)
    open(out_path, 'w').write(src)
PY

grep -q 'MailMIME.attachmentNames' "$TMP/imap.bare" \
  || { echo "✗ IMAPClient no longer reads attachment names — every mail lands with none"; exit 1; }
# It must ride the bytes the BODY pass already fetched. A second FETCH here
# would double the cost of every refresh to learn a filename.
grep -q 'raw.map(MailMIME.attachmentNames)' "$TMP/imap.bare" \
  || { echo "✗ attachment names no longer reuse the fetched body bytes — this would cost a second FETCH"; exit 1; }
grep -q 'm.attachments' "$TMP/bridge.bare" \
  || { echo "✗ MailBridge drops the attachment names — parsed, then thrown away"; exit 1; }
# An empty list means BOTH "nothing attached" and "the body fetch failed", so
# no copy anywhere may state the first.
grep -qi 'no attachments' "$TMP/bridge.bare" \
  && { echo "✗ MailBridge states 'no attachments' — an empty list also means the fetch failed"; exit 1; }
grep -q 'decodeHeaderWord' "$TMP/imap.bare" \
  || { echo "✗ the shared RFC 2047 decoder forwarder is gone — MailMIME would need its own copy"; exit 1; }

# --- the driver -------------------------------------------------------------
cp "$MIME" "$TMP/MailMIME.swift"

# The IDENTITY stub — see the header. If `attachmentName` stops routing the
# filename through this, the encoded-word assertion fails.
cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation

enum IMAPClient {
    /// INERT for an ordinary filename, and a SENTINEL for an encoded-word.
    ///
    /// Both halves are load bearing. Returning the input unchanged is what
    /// lets every other assertion compare against a real filename — the first
    /// cut of this stub wrapped every name and broke seven fixtures that were
    /// testing the harness rather than the parser. Marking only a `=?…?=`
    /// input is what proves the filename is really ROUTED through the shared
    /// decoder: a stub that decoded nothing at all would pass just as happily
    /// against a version that never calls it.
    ///
    /// Deliberately not a second RFC 2047 implementation — the point of the
    /// shared decoder is that there is exactly one.
    static func decodeHeaderWord(_ s: String) -> String {
        s.contains("=?") ? "ROUTED-THROUGH-DECODER" : s
    }
}

enum IngestSupport {
    /// Inert. Only the HTML body path reaches it, which no assertion here
    /// exercises — the identity keeps that path compiling without giving the
    /// harness a second implementation to drift from.
    static func decodeHTMLEntities(_ s: String) -> String { s }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
/// Messages are written with real CRLF, because that is what a server sends
/// and because this decoder has already been bitten once by Swift fusing
/// "\r\n" into one Character (its own 2026-07-23 lesson).
func mail(_ lines: [String]) -> Data { Data(lines.joined(separator: "\r\n").utf8) }

print("attachmentNames — a file somebody sent you")
let simple = mail([
    "Subject: Contract",
    "Content-Type: multipart/mixed; boundary=\"BOUND\"",
    "",
    "--BOUND",
    "Content-Type: text/plain; charset=utf-8",
    "",
    "Signed copy attached.",
    "--BOUND",
    "Content-Type: application/pdf; name=\"contract.pdf\"",
    "Content-Disposition: attachment; filename=\"contract.pdf\"",
    "Content-Transfer-Encoding: base64",
    "",
    "JVBERi0xLjQK",
    "--BOUND--",
])
check("the attachment is named", MailMIME.attachmentNames(from: simple) == ["contract.pdf"])
// The body must still decode from the same bytes — this pass must not have
// changed what the sheet shows.
check("the body still decodes",
      MailMIME.plainText(from: simple)?.contains("Signed copy attached") == true)

print("what is NOT an attachment")
let textOnly = mail([
    "Content-Type: multipart/alternative; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: text/plain; name=\"body.txt\"",
    "",
    "Hello.",
    "--B",
    "Content-Type: text/html; name=\"body.html\"",
    "",
    "<p>Hello.</p>",
    "--B--",
])
// Without the text exclusion nearly every multipart mail reports a file.
check("a named text part is not a file", MailMIME.attachmentNames(from: textOnly).isEmpty)
let plain = Data("Subject: Hi\r\n\r\nNo parts here.".utf8)
check("a non-multipart mail has none", MailMIME.attachmentNames(from: plain).isEmpty)
check("empty bytes yield none", MailMIME.attachmentNames(from: Data()).isEmpty)

print("the INLINE case — a PDF sent without saying 'attachment'")
let inlinePDF = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: text/plain",
    "",
    "See below.",
    "--B",
    "Content-Type: application/pdf; name=\"invoice.pdf\"",
    "Content-Disposition: inline; filename=\"invoice.pdf\"",
    "",
    "%PDF",
    "--B--",
])
check("an inline PDF is still a file", MailMIME.attachmentNames(from: inlinePDF) == ["invoice.pdf"])
// The older spelling, alone — plenty of senders never write a Disposition.
let nameOnly = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: text/plain",
    "",
    "hi",
    "--B",
    "Content-Type: image/png; name=\"shot.png\"",
    "",
    "PNG",
    "--B--",
])
check("Content-Type name alone is enough", MailMIME.attachmentNames(from: nameOnly) == ["shot.png"])

print("nesting — the file sits beside the text, one level down")
let nested = mail([
    "Content-Type: multipart/mixed; boundary=\"OUT\"",
    "",
    "--OUT",
    "Content-Type: multipart/alternative; boundary=\"IN\"",
    "",
    "--IN",
    "Content-Type: text/plain",
    "",
    "Body text.",
    "--IN",
    "Content-Type: text/html",
    "",
    "<p>Body text.</p>",
    "--IN--",
    "--OUT",
    "Content-Type: application/zip; name=\"deck.zip\"",
    "Content-Disposition: attachment; filename=\"deck.zip\"",
    "",
    "PK",
    "--OUT--",
])
check("a file beside a nested multipart is found",
      MailMIME.attachmentNames(from: nested) == ["deck.zip"])
// AND THE ONE THAT ACTUALLY NEEDS THE RECURSION. The fixture above puts the
// file at the OUTER level, so a flat walk finds it too — it passed against a
// version with the recursion deleted, caught by this harness's own mutation
// pass. Here the file is INSIDE the nested part, which is the `mixed >
// related > image` shape every mail with an inline image uses.
let deeplyNested = mail([
    "Content-Type: multipart/mixed; boundary=\"OUT\"",
    "",
    "--OUT",
    "Content-Type: multipart/related; boundary=\"IN\"",
    "",
    "--IN",
    "Content-Type: text/plain",
    "",
    "See the chart.",
    "--IN",
    "Content-Type: image/png; name=\"chart.png\"",
    "Content-Disposition: inline; filename=\"chart.png\"",
    "",
    "PNG",
    "--IN--",
    "--OUT--",
])
check("a file INSIDE a nested multipart is found",
      MailMIME.attachmentNames(from: deeplyNested) == ["chart.png"])

print("hostile and malformed input")
// Drawn on the sheet, so a name that claims a path claims an arrival that
// never happened.
let traversal = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: application/octet-stream",
    "Content-Disposition: attachment; filename=\"../../etc/passwd\"",
    "",
    "x",
    "--B--",
])
check("a path is reduced to its last component",
      MailMIME.attachmentNames(from: traversal) == ["passwd"])
let backslash = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: application/octet-stream",
    "Content-Disposition: attachment; filename=\"C:\\\\Windows\\\\evil.exe\"",
    "",
    "x",
    "--B--",
])
check("a Windows path is reduced too",
      MailMIME.attachmentNames(from: backslash) == ["evil.exe"])
// ROUTING, not decoding — the stub wraps rather than decodes, so this fails
// if the filename stops going through the shared RFC 2047 decoder.
let encoded = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: application/pdf",
    "Content-Disposition: attachment; filename=\"=?UTF-8?B?cmHEjXVu?=\"",
    "",
    "x",
    "--B--",
])
check("the filename is routed through the shared decoder",
      MailMIME.attachmentNames(from: encoded) == ["ROUTED-THROUGH-DECODER"])
// A part that re-declares its parent's boundary. Without the equality check
// and the depth fuse this never returns.
let recursive = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: application/pdf; name=\"a.pdf\"",
    "",
    "x",
    "--B--",
])
check("a self-referential boundary terminates",
      MailMIME.attachmentNames(from: recursive).count <= 8)

print("bounds")
var many = ["Content-Type: multipart/mixed; boundary=\"B\"", ""]
for i in 1...20 {
    many += ["--B", "Content-Type: application/pdf; name=\"f\(i).pdf\"",
             "Content-Disposition: attachment; filename=\"f\(i).pdf\"", "", "x"]
}
many.append("--B--")
let flood = MailMIME.attachmentNames(from: mail(many))
check("a row never becomes a file listing", flood.count == 8)
check("the ones it keeps are the first", flood.first == "f1.pdf")
// Same file referenced twice reads as two files.
let dupes = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: image/png; name=\"logo.png\"",
    "Content-Disposition: inline; filename=\"logo.png\"",
    "",
    "x",
    "--B",
    "Content-Type: image/png; name=\"LOGO.PNG\"",
    "Content-Disposition: inline; filename=\"LOGO.PNG\"",
    "",
    "x",
    "--B--",
])
check("the same name twice counts once", MailMIME.attachmentNames(from: dupes).count == 1)
let longName = String(repeating: "a", count: 400) + ".pdf"
let huge = mail([
    "Content-Type: multipart/mixed; boundary=\"B\"",
    "",
    "--B",
    "Content-Type: application/pdf",
    "Content-Disposition: attachment; filename=\"\(longName)\"",
    "",
    "x",
    "--B--",
])
check("a hostile 400-character name is capped",
      (MailMIME.attachmentNames(from: huge).first?.count ?? 0) <= 120)

if failures > 0 { print("\n\(failures) failed"); exit(1) }
print("\nall checks passed")
SWIFT

swiftc -O -o "$TMP/run" "$TMP/MailMIME.swift" "$TMP/stub.swift" "$TMP/main.swift" 2>&1 \
  | grep -v '^ *$' || true
[[ -x "$TMP/run" ]] || { echo "✗ MailMIME.swift no longer compiles Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
echo "\nmutations (each must FAIL the harness):"
mutate() {
  local label="$1" sedexpr="$2"
  local dir="$TMP/mut"; rm -rf "$dir"; mkdir -p "$dir"
  sed "$sedexpr" "$MIME" > "$dir/MailMIME.swift"
  cmp -s "$dir/MailMIME.swift" "$MIME" \
    && { echo "  ✗ $label — the mutation matched NOTHING (stale after a refactor)"; return 1; }
  if ! swiftc -O -o "$dir/run" "$dir/MailMIME.swift" "$TMP/stub.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✗ $label — the mutation does not compile, so it tests nothing"; return 1
  fi
  if "$dir/run" >/dev/null 2>&1; then
    echo "  ✗ $label — the harness PASSED against broken logic"; return 1
  fi
  echo "  ✓ $label is caught"
}

mutate "the path-component reduction removed (../../etc/passwd is drawn whole)" \
  's@let leaf = decoded.split(whereSeparator: { $0 == "/" || $0 == "\\\\" }).last@let leaf: Substring? = Substring(decoded)@'
mutate "the text exclusion removed (a text part reads as a file)" \
  's@guard isAttachment || !isText else { return nil }@guard true else { return nil }@'
mutate "the inline case dropped (a PDF sent inline reports nothing)" \
  's@guard isAttachment || !isText else { return nil }@guard isAttachment else { return nil }@'
mutate "the recursion removed (a file beside nested text is missed)" \
  's@collectAttachments(in: partBody, boundary: nested, into: \&names, depth: depth + 1)@_ = nested@'
mutate "the shared decoder bypassed (an encoded filename is drawn raw)" \
  's@let decoded = IMAPClient.decodeHeaderWord(raw)@let decoded = raw@'
mutate "the name cap removed" \
  's@private static let nameCap = 120@private static let nameCap = 4000@'
mutate "the count cap removed" \
  's@private static let attachmentCap = 8@private static let attachmentCap = 400@'
mutate "the dedupe removed (one file referenced twice reads as two)" \
  's@return names.filter { seen.insert($0.lowercased()).inserted }@return names.filter { _ in true }@'

echo "\n✓ MIME self-test passed"
