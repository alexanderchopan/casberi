#!/bin/zsh
# Casberi Mail-location self-test — the SHIPPED pure logic behind the message
# door on a mail thing (2026-09-15, prd §735):
#
#   Casberi/Casberi/Model/MailLocation.swift
#     — normalizedID  (the Message-ID, fenced)
#     — messageURL    (where pressing the sheet's From row lands)
#     — appName       (the words the verb says)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no copy. Every assertion below is about the
# bytes the app runs. `files-location-selftest.sh`'s shape one bridge over,
# because it is the same feature: a row that STATES a place, pressed.
#
# WHY A HARNESS. Nothing on this side can be seen from a build, a screen sweep
# or a simulator, and each failure renders as a perfectly ordinary row:
#
#   • a `NIL` atom or a truncated envelope reaching the URL, so the door exists
#     on every mail in the corpus and opens nothing on any of them;
#   • an unencoded `/` in a Message-ID, which turns Gmail's one search into a
#     PATH — a door that opens the wrong page rather than none, which is the
#     only failure here worse than no door;
#   • angle brackets left on for `rfc822msgid:`, which Gmail refuses, or taken
#     off for `message:`, which Mail needs;
#   • the two providers' arms crossed, which reads as "the door just doesn't
#     work" for exactly one of the two mailboxes.
#
# The `message:` SCHEME itself cannot be proven here and this harness does not
# pretend to: Apple documents it only in an archived URL-scheme reference, so
# it is unmeasured at the same grade as `shareddocuments://` one file over, and
# `-mailOpenProbe` is what measures it. What the drift guards below prove is
# that the door is GATED — declared in Info.plist, probed by HandOffState, and
# offered only when something claims the scheme — because an unclaimed scheme
# is refused asynchronously and reports success, which is the dead control §83
# bans. Gmail's arm is deliberately UNgated and the guards prove that too: an
# `https` URL always opens something, and gating it on the Gmail app would
# delete the door for everyone reading Gmail over IMAP without it.
#
# Pure, local, deterministic — no network, no simulator, no mailbox. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

LOC="Casberi/Casberi/Model/MailLocation.swift"
BRIDGE="Casberi/Casberi/Model/MailBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
VERBS="Casberi/Casberi/Model/Verbs.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
THING="Casberi/Shared/Thing.swift"
PLIST="Casberi/Casberi/Info.plist"
CKDB="docs/cloudkit-schema.ckdb"
for f in "$LOC" "$BRIDGE" "$SUPPORT" "$VERBS" "$SHEET" "$THING" "$PLIST" "$CKDB"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions can't prove on their own. A perfect URL builder
# is worthless if nothing fills the field it reads, or if nothing offers it.

# The column. Without it every mail row answers nil forever and the door
# silently stops existing for the whole corpus.
grep -q 'var mailMessageID: String? = nil' "$THING" \
  || { echo "✗ Thing.mailMessageID is gone — MailLocation has nothing to build from"; exit 1; }
# …and it must be in the deployed CloudKit schema, or it syncs NOWHERE and the
# door exists on the device that landed the mail and on no other (the partial-
# sync failure `cloudkit-schema-audit.py` was written for).
grep -q 'CD_mailMessageID' "$CKDB" \
  || { echo "✗ CD_mailMessageID is not in the checked-in CloudKit schema — the"; \
       echo "  field would fail its export to Production, silently"; exit 1; }
# The ingest must FILL it, normalized — a raw envelope value would put `NIL`
# and truncations into a URL.
grep -q 'thing.mailMessageID = MailLocation.normalizedID(m.messageID)' "$BRIDGE" \
  || { echo "✗ MailIngest no longer stamps a normalized Message-ID — every mail"; \
       echo "  landing from now on would have no door"; exit 1; }
# …and it must BACKFILL, or every mail already in the corpus stays doorless
# forever while the envelope carrying the fact is fetched and discarded on
# every single foreground.
grep -q 'IngestSupport.mailIDlessThings' "$BRIDGE" \
  || { echo "✗ MailIngest no longer backfills already-landed mail — the rows the"; \
       echo "  request was made about would never get a door"; exit 1; }
grep -q 'static func mailIDlessThings' "$SUPPORT" \
  || { echo "✗ IngestSupport.mailIDlessThings is gone"; exit 1; }
# A backfill that never saves is a backfill that runs every launch and lands
# nothing.
grep -q 'if added > 0 || backfilled > 0 { context.saveHonestly() }' "$BRIDGE" \
  || { echo "✗ MailIngest saves only on NEW mail — a pass that backfilled and"; \
       echo "  added nothing would throw the backfill away"; exit 1; }
# The envelope's field 10 is where the fact comes from. If the parser stops
# reading it, everything above is filling a column with nil.
grep -q 'let messageID = items.count > 9 ? header(items\[9\]) : nil' \
  Casberi/Casberi/Model/IMAPClient.swift \
  || { echo "✗ the IMAP envelope parser no longer reads Message-ID (field 10)"; exit 1; }

# The hand-off is gated three ways on the Apple side, and all three are
# load-bearing.
grep -q '<string>message</string>' "$PLIST" \
  || { echo "✗ message is not in LSApplicationQueriesSchemes — canOpenURL always"; \
       echo "  answers false and the Mail door could never appear"; exit 1; }
grep -q '"shareddocuments", "message"' "$VERBS" \
  || { echo "✗ message is not in HandOffState.candidates — nothing ever probes"; \
       echo "  it, so installedSchemes can never contain it"; exit 1; }
grep -q 'schemes.contains(openScheme)' "$LOC" \
  || { echo "✗ the Apple Mail arm is ungated — an unclaimed scheme is refused"; \
       echo "  asynchronously and reports success, so it would be a door that does nothing"; exit 1; }

# The door lives in the DIAL, and only there (prd §736). §735 drew it twice —
# once on the dial, once on the sheet's "From" row — and the row is deleted,
# because the disc below it was always saying the same thing with a destination
# in its word. The guard runs both ways: the builder must still be wired, and
# the row must not come back.
grep -q 'MailLocation.messageURL(source: thing.source,' "$VERBS" \
  || { echo "✗ the dial no longer builds its mail door through MailLocation — with"; \
       echo "  the From row deleted (§736) this is the only door a mail has"; exit 1; }
grep -q 'MailLocation.appName(source: thing.source)' "$VERBS" \
  || { echo "✗ the mail verb no longer names the app it opens"; exit 1; }
# COMMENT-STRIPPED, for the reason the `mailto` guard below gives: the sheet
# carries a tombstone naming `fromRow` and what it drew, so a guard grepping
# raw source fires on the prose explaining the deletion.
python3 - "$SHEET" <<'ROWGONE' || exit 1
import sys
sheet = "\n".join(l for l in open(sys.argv[1]).read().splitlines()
                  if not l.strip().startswith("//"))
if "fromRow" in sheet:
    print("✗ the sheet's From row is back (prd §736 deleted it)")
    sys.exit(1)
if "MailLocation" in sheet:
    print("✗ the thing sheet builds a mail door of its own again — §736 left the")
    print("  dial as the single door, so a second one can only drift from it")
    sys.exit(1)
ROWGONE
# Two discs a millimetre apart, one landing on the message and one on the
# inbox, is the menu brief §12 bans — so the front door stands down for a mail
# that has a real one.
grep -q '(thing.source == "Gmail" \&\& mailDoor == nil)' "$VERBS" \
  || { echo "✗ the Gmail front-door exception no longer stands down when the"; \
       echo "  message door exists — the dial would carry both"; exit 1; }

# NEGATIVE, and read from a COMMENT-STRIPPED copy: this file's own doc explains
# the rule by naming what it must not do, so a guard grepping raw source fires
# on the prose explaining it (the Obsidian/Cursor lesson).
#
# `mailto:` must never appear in MailLocation. It is a COMPOSER: a door that
# opens a blank draft while the row above it says "in your inbox" is §83's dead
# control wearing a destination, and it is the specific mistake the ruling this
# feature replaced was right to refuse.
python3 - "$LOC" <<'PY' || exit 1
import sys
src = open(sys.argv[1]).read()
code = "\n".join(l for l in src.splitlines()
                 if not l.strip().startswith("//") and not l.strip().startswith("///"))
if "mailto" in code:
    print("✗ MailLocation reaches for mailto: — that is a composer, not the message")
    sys.exit(1)
if "urlFragmentAllowed" in code or "urlQueryAllowed" in code:
    print("✗ MailLocation encodes with a permissive character set — a Message-ID")
    print("  may hold `/`, and an unencoded one turns Gmail's search into a path")
    sys.exit(1)
PY

TMP=$(mktemp -d /tmp/mail-location-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
/// Every real call site passes `HandOffState.installedSchemes`; these two are
/// the device with Mail set up and the device without it.
let withMail: Set<String> = ["message", "shareddocuments"]
let noMail: Set<String> = ["shareddocuments"]

// ── normalizedID — the fence ───────────────────────────────────────────────
print("normalizedID — what we hold is a Message-ID, or it is nothing")
check("the envelope's bracketed form unwraps",
      MailLocation.normalizedID("<abc123@mail.example.com>") == "abc123@mail.example.com")
check("an already-bare id passes through",
      MailLocation.normalizedID("abc123@mail.example.com") == "abc123@mail.example.com")
check("surrounding whitespace is trimmed",
      MailLocation.normalizedID("  <abc@x.com>  ") == "abc@x.com")
check("a local part with dots and plus survives",
      MailLocation.normalizedID("<a.b+c-d_e@x.co.uk>") == "a.b+c-d_e@x.co.uk")
// The fence. Each of these would build a door onto nothing.
check("nil → nil", MailLocation.normalizedID(nil) == nil)
check("empty → nil", MailLocation.normalizedID("") == nil)
check("whitespace only → nil", MailLocation.normalizedID("   ") == nil)
check("a `NIL` atom that slipped through → nil", MailLocation.normalizedID("NIL") == nil)
check("no `@` → nil", MailLocation.normalizedID("<abc123>") == nil)
check("two `@` → nil", MailLocation.normalizedID("<a@b@c.com>") == nil)
check("an empty local part → nil", MailLocation.normalizedID("<@x.com>") == nil)
check("an empty domain → nil", MailLocation.normalizedID("<abc@>") == nil)
check("an inner space → nil", MailLocation.normalizedID("<abc def@x.com>") == nil)
check("a newline → nil", MailLocation.normalizedID("<abc@x.com>\nSubject: no") == nil)
check("a stray bracket → nil", MailLocation.normalizedID("<abc@x.com") == nil)
check("a nested bracket → nil", MailLocation.normalizedID("<<abc@x.com>>") == nil)
check("longer than a header line → nil",
      MailLocation.normalizedID("<" + String(repeating: "a", count: 1200) + "@x.com>") == nil)

// ── messageURL — where the press lands ─────────────────────────────────────
print("\nmessageURL — Gmail's search, Mail's scheme")
check("Gmail lands on the one message",
      MailLocation.messageURL(source: "Gmail", messageID: "<abc@x.com>", schemes: noMail)?
        .absoluteString
        == "https://mail.google.com/mail/u/0/#search/rfc822msgid:abc%40x.com")
check("Gmail strips the angle brackets (rfc822msgid: refuses them)",
      MailLocation.messageURL(source: "Gmail", messageID: "<abc@x.com>", schemes: noMail)?
        .absoluteString.contains("%3C") == false)
check("Gmail's door needs no app installed",
      MailLocation.messageURL(source: "Gmail", messageID: "<abc@x.com>", schemes: [])  != nil)
check("Apple Mail keeps the brackets, encoded",
      MailLocation.messageURL(source: "iCloud Mail", messageID: "<abc@x.com>",
                              schemes: withMail)?.absoluteString
        == "message:%3Cabc%40x.com%3E")
check("Apple Mail's URL is opaque, never an authority",
      MailLocation.messageURL(source: "iCloud Mail", messageID: "<abc@x.com>",
                              schemes: withMail)?.host == nil)
check("the scheme is Apple Mail's own",
      MailLocation.messageURL(source: "iCloud Mail", messageID: "<abc@x.com>",
                              schemes: withMail)?.scheme == MailLocation.openScheme)
check("the source match is case-insensitive",
      MailLocation.messageURL(source: "GMAIL", messageID: "<abc@x.com>", schemes: noMail) != nil)
// Encoding. Each of these is a legal Message-ID and each breaks the URL
// unencoded — i.e. the door opens the WRONG page for whoever has one.
check("a `/` is encoded (it would otherwise become a Gmail path)",
      MailLocation.messageURL(source: "Gmail", messageID: "<a/b@x.com>", schemes: noMail)?
        .absoluteString.hasSuffix("rfc822msgid:a%2Fb%40x.com") == true)
check("a `#` is encoded (it would otherwise end the URL)",
      MailLocation.messageURL(source: "Gmail", messageID: "<a#b@x.com>", schemes: noMail)?
        .absoluteString.hasSuffix("rfc822msgid:a%23b%40x.com") == true)
check("a `?` is encoded",
      MailLocation.messageURL(source: "Gmail", messageID: "<a?b@x.com>", schemes: noMail)?
        .absoluteString.hasSuffix("rfc822msgid:a%3Fb%40x.com") == true)
check("a `+` is encoded (Gmail's search would read it as a space)",
      MailLocation.messageURL(source: "Gmail", messageID: "<a+b@x.com>", schemes: noMail)?
        .absoluteString.hasSuffix("rfc822msgid:a%2Bb%40x.com") == true)
check("a `%` is encoded",
      MailLocation.messageURL(source: "Gmail", messageID: "<a%b@x.com>", schemes: noMail)?
        .absoluteString.hasSuffix("rfc822msgid:a%25b%40x.com") == true)
check("a non-Latin id still builds a URL",
      MailLocation.messageURL(source: "Gmail", messageID: "<読書@x.com>", schemes: noMail) != nil)
// Failures are nil, never a door onto the wrong place.
check("Apple Mail with nothing claiming the scheme → nil",
      MailLocation.messageURL(source: "iCloud Mail", messageID: "<abc@x.com>",
                              schemes: noMail) == nil)
check("no Message-ID → nil",
      MailLocation.messageURL(source: "Gmail", messageID: nil, schemes: withMail) == nil)
check("a fenced Message-ID → nil",
      MailLocation.messageURL(source: "Gmail", messageID: "NIL", schemes: withMail) == nil)
check("another bridge's source → nil",
      MailLocation.messageURL(source: "Files", messageID: "<abc@x.com>",
                              schemes: withMail) == nil)
check("an empty source → nil",
      MailLocation.messageURL(source: "", messageID: "<abc@x.com>", schemes: withMail) == nil)

// ── appName — the words the verb says ──────────────────────────────────────
print("\nappName — the app you are about to be looking at")
check("iCloud Mail's app is Mail", MailLocation.appName(source: "iCloud Mail") == "Mail")
check("Gmail's app is Gmail", MailLocation.appName(source: "Gmail") == "Gmail")
check("anything else has no door", MailLocation.appName(source: "Dropbox") == nil)
// The two must agree: a name with no URL draws a disc that opens nothing, and
// a URL with no name draws nothing at all.
for source in ["iCloud Mail", "Gmail", "Files", "Dropbox", ""] {
    let named = MailLocation.appName(source: source) != nil
    let built = MailLocation.messageURL(source: source, messageID: "<abc@x.com>",
                                        schemes: withMail) != nil
    check("\(source.isEmpty ? "(empty)" : source): a name exactly when there is a URL",
          named == built)
}

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. This harness traps nowhere and has
# no mutations that could, which is the condition `harness-opt-probe.sh` checks
# for — re-probe before trusting it again after adding one.
if ! swiftc -Onone -o "$TMP/run" "$LOC" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped MailLocation.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$LOC" "$WORK/MailLocation.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/MailLocation.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/MailLocation.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/MailLocation.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The fence dropped — `NIL`, truncations and header injections reach the URL.
mutate "the Message-ID shape fence removed" \
  'guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty,' \
  'guard true ||  halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty,'

# 2. Whitespace accepted — a folded header becomes a URL that ends early.
mutate "whitespace accepted inside the id" \
  's.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,' \
  'true,'

# 3. The brackets left on for Gmail, which `rfc822msgid:` refuses.
mutate "the angle brackets left on" \
  'if s.hasPrefix("<"), s.hasSuffix(">"), s.count >= 3 {' \
  'if false, s.hasSuffix(">"), s.count >= 3 {'

# 4. The permissive encoder — a `/` in a Message-ID becomes a Gmail path.
mutate "a permissive character set" \
  '"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")' \
  '"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/#?+%")'

# 5. The scheme gate dropped — a disc that does nothing on every device with
#    no Mail account.
mutate "the Apple Mail scheme gate removed" \
  'guard schemes.contains(openScheme),' \
  'guard true,'

# 6. The two arms crossed — one mailbox's door silently stops working.
mutate "the providers' arms crossed" \
  'case "gmail":' \
  'case "gmail-disabled":'

# 7. `appName` and `messageURL` disagree — a named app with no URL is a disc
#    that opens nothing.
mutate "appName answers for a source with no door" \
  'case "gmail":       return "Gmail"' \
  'case "dropbox":     return "Dropbox"'

echo
echo "✓ mail-location self-test: assertions and mutations all passed"
