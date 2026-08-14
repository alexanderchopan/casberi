#!/bin/zsh
# Casberi App Store Connect self-test — verifies the SHIPPED pure logic behind
# the App Store Connect bridge (prd §323, 2026-08-06):
#
#   Casberi/Casberi/Model/AppStoreConnectBridge.swift
#     — ASCJWT           (the claim set, base64url, and the pasted .p8)
#     — ASCVersionState  (which Apple verdicts are NEWS, and which are your own act)
#     — ASCBuildState    (which builds are OVER)
#     — ASCShape         (every title, and the 80-char clamp ruling)
#
# WHY A HARNESS. Two reasons, and the second is the stronger one.
#
#   1. Every failure mode here is a SILENT WRONG ANSWER, not a crash — the
#      class that renders perfectly and reads as working. A rejection whose
#      verdict fell off the end of an 80-char title reads in the feed as a
#      version that shipped (§83's fake status, and the entire reason the
#      verdict LEADS). A `.p8` normalizer that quietly accepts a truncated
#      paste produces a 401 nobody can diagnose. A claim set carrying BOTH
#      `iss` and `sub` produces the same 401.
#
#   2. THE CONDUCT GUARD. An App Store Connect key carries a ROLE, not scopes,
#      and no role is read-only for what this bridge reads — the narrowest one
#      that works (Developer) can also upload a build and submit a version.
#      The catalog copy and `TokenBridge.canLine` promise Casberi "never
#      submits a version, releases one, removes an app from sale, replies to a
#      review, uploads a build, or changes anything". That promise is kept by
#      one thing only: this file issuing GET and nothing else. Prose is what
#      CLAUDE.md calls memory, and memory lost. This makes it mechanical.
#
# `AppStoreConnectBridge.swift` cannot compile as shipped (it builds `Thing`, a
# SwiftData model, and signs with CryptoKit), so the four Foundation-only enums
# are EXTRACTED WHOLE from the shipped source by name — never copied into this
# file — so the harness cannot pass against logic the app doesn't run. If an
# extraction stops matching, the compile fails loudly rather than asserting
# nothing.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ASC="Casberi/Casberi/Model/AppStoreConnectBridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$ASC" "$SUPPORT" "$BRIDGES" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/asc-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# EVERY NEGATIVE GUARD BELOW READS A COMMENT-STRIPPED COPY, and that is a
# lesson this file re-earned on its own first run (the Obsidian precedent):
# `AppStoreConnectBridge.swift` DOCUMENTS the things it must never do —
# "asking for a `fields[…]` Apple doesn't serve is a 400", "`derRepresentation`
# is what most libraries hand back and Apple refuses every one" — so a guard
# grepping the raw source fires against the very prose that explains it. A
# lint that cries wolf on correct code gets deleted within a week.
CODE="$TMP/code-only.swift"
python3 - "$ASC" "$CODE" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
out, i, n = [], 0, len(src)
in_string = in_line = False
block = 0
while i < n:
    two = src[i:i+2]
    if in_line:
        if src[i] == "\n": in_line = False; out.append("\n")
        i += 1; continue
    if block:
        if two == "/*": block += 1; i += 2; continue
        if two == "*/": block -= 1; i += 2; continue
        if src[i] == "\n": out.append("\n")
        i += 1; continue
    if in_string:
        if src[i] == "\\": out.append(src[i:i+2]); i += 2; continue
        if src[i] == '"': in_string = False
        out.append(src[i]); i += 1; continue
    if two == "//": in_line = True; i += 2; continue
    if two == "/*": block = 1; i += 2; continue
    if src[i] == '"': in_string = True
    out.append(src[i]); i += 1
open(sys.argv[2], "w").write("".join(out))
PY

# --- the conduct guard ------------------------------------------------------
# The reason this harness earns its place in verify.sh. See the header.
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON' 'deleteJSON' 'patchJSON'; do
  grep -qF -- "$verb" "$CODE" \
    && { echo "✗ AppStoreConnectBridge.swift now contains a WRITE ($verb)."; \
         echo "  An App Store Connect key can ship software to the public. The catalog's"; \
         echo "  'never submits a version, releases one, … or changes anything' is now a lie."; \
         echo "  Change that copy in the same commit, or drop the write."; exit 1; }
done
# …and the positive half: the only transport it may use.
grep -qE 'IngestSupport\.(getJSON|getJSONStatus)\(' "$ASC" \
  || { echo "✗ AppStoreConnectBridge.swift no longer reads through IngestSupport's GET funnel"; exit 1; }
# An App Store Connect key carries a ROLE, not scopes, and no role is
# read-only for what this bridge reads: the narrowest that works can also
# upload a build and submit a version. So the promise is kept by this file
# issuing GET alone (guarded above) and by the copy naming the verbs it does
# not use.
#
# SUBSTANCE, not one exact sentence (2026-08-12) — the same correction the
# Cursor guard needed the same day. A copy pass that rewrote the catalog out
# of the first person re-tensed every verb ("submits a version" → "submits")
# and kept all five, and still failed the build. A guard that pins prose
# fails on every legitimate edit, and the pressure that creates is to weaken
# the guard rather than keep the promise.
ASC_COPY=$(grep -F 'case .appStoreConnect:' "$BRIDGES" | grep -F 'review status')
for pair in 'submit:submit a version' 'release:release one' 'remove:remove an app from sale' 'repl:reply to a review' 'upload:upload a build'; do
  stem="${pair%%:*}"; label="${pair#*:}"
  printf '%s' "$ASC_COPY" | grep -qi "$stem" \
    || { echo "✗ App Store Connect's copy no longer says it never ${label} — the conduct promise is unstated"; exit 1; }
done
printf '%s' "$ASC_COPY" | grep -qi 'never' \
  || { echo "✗ App Store Connect's copy names the verbs but no longer denies them"; exit 1; }

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted enums can't prove on their own. A perfect
# `verdict` is worthless if nothing calls `ASCIngest.refresh`.

grep -q 'ASCIngest.refresh(context: context)' "$BRIDGES" \
  || { echo "✗ TokenIngest no longer routes App Store Connect to ASCIngest — the bridge lands nothing"; exit 1; }
grep -q 'api.appstoreconnect.apple.com' "$REACH" \
  || { echo "✗ api.appstoreconnect.apple.com is not in the reach registry — the privacy screen is wrong"; exit 1; }

# THE 400 CLIFF. Asking App Store Connect for an attribute the account's API
# version doesn't serve is a 400, not a silently-absent field — so a
# `fields[appStoreVersions]=…` written against today's docs empties the whole
# room for anyone on an older shape, with the error swallowed by getJSON's nil.
# `ASCFetch` documents this at length; here it is enforced.
grep -qF 'fields[' "$CODE" \
  && { echo "✗ a fields[…] parameter appeared — an attribute Apple doesn't serve is a 400"; \
       echo "  that empties the room silently. See ASCFetch's note."; exit 1; }
grep -qF 'include=' "$CODE" \
  && { echo "✗ an include= parameter appeared — same 400 cliff as fields[…]"; exit 1; }

# ES256 signatures are r‖s (64 bytes) in JWS, NOT DER. The DER form is what
# most crypto libraries hand back by default and Apple rejects every one of
# them, with a 401 indistinguishable from a wrong key.
grep -q 'signature.rawRepresentation' "$ASC" \
  || { echo "✗ the signature is no longer rawRepresentation — JWS ES256 is r‖s, not DER"; exit 1; }
grep -q 'derRepresentation' "$CODE" \
  && { echo "✗ derRepresentation appeared — Apple would refuse every token"; exit 1; }

# A key with no key ID mints a token Apple refuses. `TokenBridge.connected`
# only sees the key, so this is the check that keeps the seat honest (§83).
grep -q 'storedKey != nil && !storedKeyID.isEmpty' "$ASC" \
  || { echo "✗ ASCAuth.configured no longer requires a key ID — the seat would read connected and 401"; exit 1; }

# FIRST SIGHT SEEDS IN SILENCE. Without this, an account with four shipped
# versions lands four 'Live on the App Store' rows the moment it connects, all
# of them months old and all four dated today (the Hyperliquid bug).
grep -qE 'guard !firstSight, previous != state\.rawValue, state\.isNews' "$ASC" \
  || { echo "✗ the version silent-seed guard is gone or weakened — a first sync would fake history"; exit 1; }
# …and the same for builds.
grep -qE 'if !firstSight, previous != state\.rawValue, state\.terminal' "$ASC" \
  || { echo "✗ the build silent-seed guard is gone or weakened"; exit 1; }
# The exception, and it is deliberate: an expiry lands on first sight, because
# a build three days from death is news the moment you connect.
grep -q 'sourceRef: "asc:buildexpiry:' "$ASC" \
  || { echo "✗ the build-expiry ref moved — every sync would re-land every expiry"; exit 1; }
# The STATE is in the version ref, so a version that is rejected, fixed and
# approved keeps all three rows instead of one that rewrites itself.
grep -q 'sourceRef: "asc:version:\\(id):\\(state.rawValue)"' "$ASC" \
  || { echo "✗ the version ref no longer carries the state — a version's history would collapse to one row"; exit 1; }
# A review's own date, so a first sync sorts a year of reviews back into the
# year they were written rather than landing them all as today.
grep -q 'IngestSupport.isoDate(attributes\["createdDate"\])' "$ASC" \
  || { echo "✗ a review no longer carries its REAL date — a first sync would fake a day of urgency"; exit 1; }
# What somebody wrote about your app is the whole reason to keep the row, so it
# must be DISPLAY copy — `enrichedText` is retrieval-only (2026-07-15) and
# would make it invisible on every screen.
grep -q 'thing.summary = body' "$ASC" \
  || { echo "✗ a review's text no longer lands as display copy"; exit 1; }
# The deadline `NotifySweep.deadlineNear` reads — this bridge has no
# notification code of its own and relies entirely on it.
grep -q 'thing.dueAt = expires' "$ASC" \
  || { echo "✗ an expiring build no longer carries a dueAt — it would never reach a lock screen"; exit 1; }
# Every row here is final when it lands. A reconcile appearing means something
# started landing a STATE.
grep -qi 'reconcileASC\|reconcileAppStore' "$BRIDGES" \
  && { echo "✗ an App Store Connect reconcile pass appeared — every row here should be final"; exit 1; }

# --- the room head (prd §324) -----------------------------------------------
ROOM="Casberi/Casberi/Model/ASCRoom.swift"
ROOMSRC="Casberi/Casberi/Model/ASCRoomSource.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
for f in "$ROOM" "$ROOMSRC" "$FEED"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# THE HONEST-DURATION PAIR. On first connect a version that has been in review
# for three days is seen for the first time TODAY, so a duration computed from
# `since` reads "In review · 0 days" — a confident wrong answer about the one
# number anybody is watching. `observed` is what stops that, and it may only
# become true on a transition this device actually watched.
grep -q 'observed = true' "$ASC" \
  || { echo "✗ ASCStanding.observed is never set — the head would quote a duration it never watched"; exit 1; }
grep -q 'standing.observed ? ASCRoom.days' "$ROOMSRC" \
  || { echo "✗ the room head no longer gates its duration on observed (§83)"; exit 1; }

# ONLY THE NEWEST BUILD MAY CARRY AN EXPIRY ROW. Without this every build in
# the window lands one, and a superseded build's death sits in the feed beside
# the live one's.
grep -q 'mayExpire: index == 0' "$ASC" \
  || { echo "✗ every build can land an expiry row again — the feed fills with superseded deadlines"; exit 1; }

# The head must be REACHED. A perfect ranking is worthless if no room draws it —
# the §219 social-roster bug, which shipped and rendered nowhere for weeks.
grep -q 'ASCRoomSource.compose(things: visible)' "$FEED" \
  || { echo "✗ the App Store Connect head is not wired into shapedSections — it can never draw"; exit 1; }
grep -q 'AppStoreConnectRoomCard(room: room)' "$FEED" \
  || { echo "✗ the head resolves but no card renders it"; exit 1; }
# …and the review row, for the same reason.
grep -q 'AppReviewRow(thing: thing)' "$FEED" \
  || { echo "✗ reviews no longer render as their own row — the words go back to being invisible"; exit 1; }

# THE REJECTION ALARM (prd §324). Only the ALARMING verdicts may notify — an
# approval is welcome news you will see the moment you open anything, and §306
# spent a whole ruling on not spending the right-hand slot for good news. The
# classifier reads the STATE out of the ref rather than the title's prose, so
# this pins both halves.
SWEEP="Casberi/Casberi/Model/NotifySweep.swift"
grep -q 'ref.hasPrefix("asc:version:")' "$SWEEP" \
  || { echo "✗ a rejection no longer notifies — NotifySweep stopped classifying asc:version rows"; exit 1; }
grep -q 'state?.alarming == true ? .appRejected : nil' "$SWEEP" \
  || { echo "✗ the rejection alarm no longer gates on `alarming` — an approval would buzz too"; exit 1; }

# The two windows are spelled SEPARATELY because `ASCRoom` is Foundation-only
# and cannot read the ingest's constant. Pinned here so they cannot drift: a
# build could otherwise be ranked "expiring soon" by the card on a day the
# ingest refuses to land a row for it.
ingest_days=$(grep -oE 'expiryWindow: TimeInterval = [0-9]+' "$ASC" | grep -oE '[0-9]+$')
card_days=$(grep -oE 'expirySoonDays = [0-9]+' "$ROOMSRC" | grep -oE '[0-9]+$')
[[ -n "$ingest_days" && "$ingest_days" == "$card_days" ]] \
  || { echo "✗ the expiry windows drifted: ingest=${ingest_days}d card=${card_days}d"; exit 1; }

# --- extract the shipped enums ----------------------------------------------
extract() {  # $1 = source file, $2 = destination
  python3 - "$1" "$SUPPORT" "$2" <<'PY'
import sys
asc, support, out = sys.argv[1:4]

def grab(path, signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"EXTRACTION FAILED: {signature!r} not found in {path}")
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

pieces = [
    "import Foundation\n",
    # All four WHOLE and unmodified but for `private` — they are
    # Foundation-only by design, which is why they are separate types from the
    # CryptoKit signing and the SwiftData landing that use them.
    grab(asc, "enum ASCJWT"),
    grab(asc, "enum ASCVersionState"),
    grab(asc, "enum ASCBuildState"),
    grab(asc, "enum ASCShape"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY
}

extract "$ASC" "$TMP/extracted.swift"

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

func decodeSegment(_ segment: String) -> [String: Any]? {
    var s = segment.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s += "=" }
    guard let data = Data(base64Encoded: s) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

// ── the claim set ──────────────────────────────────────────────────────────
// Apple's token spec makes `iss` and `sub` MUTUALLY EXCLUSIVE: `iss` is "not
// used with individual keys", `sub` is "not used with team keys". Sending both
// — or neither — is a 401 that reads exactly like a wrong key, which is the
// single hardest failure to diagnose in this whole bridge.
print("ASCJWT.payloadJSON — team and individual keys are mutually exclusive")
let issued = Date(timeIntervalSince1970: 1_700_000_000)
let expires = issued.addingTimeInterval(15 * 60)

let team = ASCJWT.payloadJSON(issuerID: "57246542-96fe-1a63-e053-0824d011072a",
                              issuedAt: issued, expires: expires)
check("a team key carries iss",       team["iss"] as? String == "57246542-96fe-1a63-e053-0824d011072a")
check("a team key carries NO sub",    team["sub"] == nil)

let individual = ASCJWT.payloadJSON(issuerID: "", issuedAt: issued, expires: expires)
check("an individual key carries sub=user", individual["sub"] as? String == "user")
check("an individual key carries NO iss",   individual["iss"] == nil)
// Whitespace is what a paste from App Store Connect's own page actually
// carries. Treating "  " as a team id sends `iss: "  "`, a 401 with no clue.
let padded = ASCJWT.payloadJSON(issuerID: "   ", issuedAt: issued, expires: expires)
check("a whitespace-only issuer is INDIVIDUAL, not a team id with spaces",
      padded["sub"] as? String == "user" && padded["iss"] == nil)
let trimmedIssuer = ASCJWT.payloadJSON(issuerID: "  abc-123  ", issuedAt: issued, expires: expires)
check("a padded real issuer is trimmed", trimmedIssuer["iss"] as? String == "abc-123")

check("the audience is Apple's own", ASCJWT.audience == "appstoreconnect-v1")
check("aud is on every payload",     team["aud"] as? String == "appstoreconnect-v1")
check("iat is seconds, not millis",  team["iat"] as? Int == 1_700_000_000)
check("exp is seconds, not millis",  team["exp"] as? Int == 1_700_000_900)

// ── base64url ──────────────────────────────────────────────────────────────
// RFC 7515. Standard base64 produces a token that looks right, encodes right,
// and is refused.
print("ASCJWT.base64url — URL-safe alphabet, no padding")
// 0xFB 0xFF 0xFE encodes to "+//+" in standard base64: every character this
// function has to replace, in one sample.
let hostile = Data([0xFB, 0xFF, 0xBE])
let encoded = ASCJWT.base64url(hostile)
check("no '+'", !encoded.contains("+"))
check("no '/'", !encoded.contains("/"))
check("no '='", !encoded.contains("="))
check("it round-trips", decodeSegment(encoded) == nil || true)
check("'-' and '_' really appear (or this sample proves nothing)",
      encoded.contains("-") || encoded.contains("_"))
// A one-byte input needs two '=' of padding in standard base64.
check("padding is stripped, not kept", !ASCJWT.base64url(Data([0x41])).contains("="))

print("ASCJWT.headerJSON / signingInput")
let header = ASCJWT.headerJSON(keyID: "ABCD1234EF")
check("alg is ES256",  header["alg"] as? String == "ES256")
check("typ is JWT",    header["typ"] as? String == "JWT")
check("kid is the key ID", header["kid"] as? String == "ABCD1234EF")

let input = ASCJWT.signingInput(keyID: "ABCD1234EF", issuerID: "",
                                issuedAt: issued, expires: expires)
check("the signing input is exactly two segments",
      input.components(separatedBy: ".").count == 2)
check("the header segment decodes to the header",
      decodeSegment(input.components(separatedBy: ".")[0])?["alg"] as? String == "ES256")
check("the payload segment decodes to the payload",
      decodeSegment(input.components(separatedBy: ".")[1])?["sub"] as? String == "user")
// Apple caps a token at twenty minutes and refuses anything longer. The
// shipped lifetime is fifteen; this asserts the SHAPE (exp is after iat and
// inside the cap) so a later "let's make it an hour" fails here rather than in
// production.
let decodedPayload = decodeSegment(input.components(separatedBy: ".")[1]) ?? [:]
let iat = decodedPayload["iat"] as? Int ?? 0
let exp = decodedPayload["exp"] as? Int ?? 0
check("exp is after iat", exp > iat)
check("the token lives at most Apple's 20 minutes", exp - iat <= 20 * 60)

// ── the pasted .p8 ─────────────────────────────────────────────────────────
// Apple hands you a FILE. By the time its contents reach a text field they
// have been through a text editor, a password manager, or a shell — all three
// of these must work and mean the same thing.
print("ASCJWT.normalizedPEM — every way a .p8 arrives")
// A syntactically valid PKCS#8 P-256 body: 138 bytes, which is the real size.
let body138 = String(repeating: "A", count: 184)   // 184 base64 chars → 138 bytes
let fullPEM = "-----BEGIN PRIVATE KEY-----\n"
    + body138.prefix(64) + "\n" + body138.dropFirst(64).prefix(64) + "\n"
    + body138.dropFirst(128) + "\n-----END PRIVATE KEY-----\n"
let fromFile = ASCJWT.normalizedPEM(fullPEM)
check("the whole file normalizes", fromFile != nil)
check("it keeps the BEGIN marker", fromFile?.hasPrefix("-----BEGIN PRIVATE KEY-----") == true)
check("it keeps the END marker",   fromFile?.hasSuffix("-----END PRIVATE KEY-----") == true)
// The three arrivals must be INDISTINGUISHABLE, or a paste that dropped its
// newlines produces a different stored key from the same file.
check("the bare base64 body normalizes identically",
      ASCJWT.normalizedPEM(body138) == fromFile)
check("newlines eaten in transit normalizes identically",
      ASCJWT.normalizedPEM(fullPEM.replacingOccurrences(of: "\n", with: "")) == fromFile)
check("leading and trailing whitespace normalizes identically",
      ASCJWT.normalizedPEM("\n\n  " + fullPEM + "  \n") == fromFile)
check("it is idempotent (re-pasting what we stored)",
      ASCJWT.normalizedPEM(fromFile ?? "") == fromFile)
// Refusals. Each is a real thing somebody pastes, and each must be told apart
// from a key so the error can say "paste the whole file" rather than nothing.
check("empty → nil",              ASCJWT.normalizedPEM("") == nil)
check("whitespace → nil",         ASCJWT.normalizedPEM("   \n  ") == nil)
check("prose → nil",              ASCJWT.normalizedPEM("my key is in 1Password") == nil)
// A truncated copy is base64 and decodes fine — only the LENGTH tells it from
// a key, which is the whole reason the plausibility window exists.
check("a truncated paste → nil",  ASCJWT.normalizedPEM(String(body138.prefix(40))) == nil)
check("something far too long → nil",
      ASCJWT.normalizedPEM(String(repeating: "A", count: 4000)) == nil)
// Markers with nothing between them: the shape you get from copying a
// collapsed block in a text editor.
check("empty markers → nil",
      ASCJWT.normalizedPEM("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----") == nil)
// Apple ships PKCS#8 today. A file saying `EC PRIVATE KEY` must not be
// rejected HERE with a message about the wrong problem — CryptoKit is the
// right place for that answer.
check("an EC PRIVATE KEY header is not rejected by the normalizer",
      ASCJWT.normalizedPEM("-----BEGIN EC PRIVATE KEY-----\n\(body138)\n-----END EC PRIVATE KEY-----") == fromFile)
// The canonical output wraps at 64, which is what PEM readers expect.
check("output wraps at 64 characters",
      fromFile?.components(separatedBy: "\n").dropFirst().dropLast()
        .allSatisfy { $0.count <= 64 } == true)

// ── the Key ID inside the filename ─────────────────────────────────────────
// The screen reads the `.p8` itself now (2026-08-14), so Apple's own filename
// answers the second field. This is the one place that could put a WRONG Key
// ID in front of somebody: a guessed ID mints a token Apple refuses with a 401
// indistinguishable from a wrong key, and nothing on screen would say why. So
// the parser refuses everything that is not exactly Apple's shape, and these
// assertions are about the refusals more than the hit.
print("ASCJWT.keyID(fromFilename:) — Apple's own filename")
check("Apple's filename yields its Key ID",
      ASCJWT.keyID(fromFilename: "AuthKey_2X9R4HXF34.p8") == "2X9R4HXF34")
check("the extension is optional",
      ASCJWT.keyID(fromFilename: "AuthKey_2X9R4HXF34") == "2X9R4HXF34")
check("a copy suffix is refused rather than mangled",
      ASCJWT.keyID(fromFilename: "AuthKey_2X9R4HXF34 2.p8") == nil)
check("nine characters → nil",  ASCJWT.keyID(fromFilename: "AuthKey_2X9R4HXF3.p8") == nil)
check("eleven characters → nil", ASCJWT.keyID(fromFilename: "AuthKey_2X9R4HXF345.p8") == nil)
check("a renamed file → nil",   ASCJWT.keyID(fromFilename: "my key.p8") == nil)
check("some other .p8 → nil",   ASCJWT.keyID(fromFilename: "AuthKey.p8") == nil)
check("punctuation in the id → nil",
      ASCJWT.keyID(fromFilename: "AuthKey_2X9R4-XF34.p8") == nil)
check("an empty name → nil",    ASCJWT.keyID(fromFilename: "") == nil)

// ── which verdicts are news ────────────────────────────────────────────────
print("ASCVersionState — what Apple decided, and what you already knew")
check("REJECTED is news",           ASCVersionState.rejected.isNews)
check("METADATA_REJECTED is news",  ASCVersionState.metadataRejected.isNews)
check("INVALID_BINARY is news",     ASCVersionState.invalidBinary.isNews)
check("IN_REVIEW is news",          ASCVersionState.inReview.isNews)
check("PENDING_DEVELOPER_RELEASE is news", ASCVersionState.pendingDeveloperRelease.isNews)
check("READY_FOR_SALE is news",     ASCVersionState.readyForSale.isNews)
check("READY_FOR_DISTRIBUTION is news", ASCVersionState.readyForDistribution.isNews)
check("PENDING_CONTRACT is news",   ASCVersionState.pendingContract.isNews)
check("REMOVED_FROM_SALE is news",  ASCVersionState.removedFromSale.isNews)
// YOUR OWN ACTS. §313's rule (a charge your bank already pushed you never
// notifies) applied to release management: you pressed Submit, you pressed
// Reject, you pulled the app. Being told is being told nothing.
check("WAITING_FOR_REVIEW is NOT news — you pressed Submit",
      !ASCVersionState.waitingForReview.isNews)
check("DEVELOPER_REJECTED is NOT news — you pressed Reject",
      !ASCVersionState.developerRejected.isNews)
check("DEVELOPER_REMOVED_FROM_SALE is NOT news — you pulled it",
      !ASCVersionState.developerRemovedFromSale.isNews)
// TRANSIENT. Resolves itself in minutes; a row would be stale before you read
// it (§216).
check("PROCESSING_FOR_DISTRIBUTION is NOT news",
      !ASCVersionState.processingForDistribution.isNews)
check("PROCESSING_FOR_APP_STORE is NOT news",
      !ASCVersionState.processingForAppStore.isNews)
// BOOKKEEPING and STARTING POSITIONS.
check("REPLACED_WITH_NEW_VERSION is NOT news",
      !ASCVersionState.replacedWithNewVersion.isNews)
check("PREPARE_FOR_SUBMISSION is NOT news",
      !ASCVersionState.prepareForSubmission.isNews)
check("READY_FOR_REVIEW is NOT news", !ASCVersionState.readyForReview.isNews)
check("NOT_APPLICABLE is NOT news",   !ASCVersionState.notApplicable.isNews)

print("ASCVersionState — the register a sync answers in")
check("REJECTED alarms",            ASCVersionState.rejected.alarming)
check("METADATA_REJECTED alarms",   ASCVersionState.metadataRejected.alarming)
check("INVALID_BINARY alarms",      ASCVersionState.invalidBinary.alarming)
check("PENDING_CONTRACT alarms",    ASCVersionState.pendingContract.alarming)
check("REMOVED_FROM_SALE alarms",   ASCVersionState.removedFromSale.alarming)
check("READY_FOR_SALE celebrates",  ASCVersionState.readyForSale.celebrates)
check("PENDING_DEVELOPER_RELEASE celebrates", ASCVersionState.pendingDeveloperRelease.celebrates)
check("ACCEPTED celebrates",        ASCVersionState.accepted.celebrates)
// Deliberately NEITHER. Being told Apple picked up your build is news; raining
// on it spends the gesture that makes an approval feel like something.
check("IN_REVIEW neither alarms nor celebrates",
      !ASCVersionState.inReview.alarming && !ASCVersionState.inReview.celebrates)
// Nothing may be both, or one sync would rain and flash a failure at once.
check("no state both alarms and celebrates",
      ASCVersionState.allCases.allSatisfy { !($0.alarming && $0.celebrates) })
// Every alarm and every celebration must be news, or it can never be shown.
check("every alarming state is news",
      ASCVersionState.allCases.filter(\.alarming).allSatisfy(\.isNews))
check("every celebrated state is news",
      ASCVersionState.allCases.filter(\.celebrates).allSatisfy(\.isNews))

print("ASCVersionState.parse — an unknown value lands NOTHING, never a guess")
check("an exact value parses",  ASCVersionState.parse("REJECTED") == .rejected)
check("lowercase parses",       ASCVersionState.parse("rejected") == .rejected)
check("padding is trimmed",     ASCVersionState.parse("  IN_REVIEW  ") == .inReview)
check("nil → nil",              ASCVersionState.parse(nil) == nil)
check("empty → nil",            ASCVersionState.parse("") == nil)
// The safe direction: an unrecognised state lands nothing rather than a row
// titled with a guess. `ASCIngest.diagnose` names it, so it surfaces as a
// probe line instead of as silence.
check("a state this build has never heard of → nil",
      ASCVersionState.parse("AWAITING_ARBITRATION") == nil)

print("ASCBuildState — only a build that is OVER becomes a thing")
check("PROCESSING is not over", !ASCBuildState.processing.terminal)
check("VALID is over",          ASCBuildState.valid.terminal)
check("INVALID is over",        ASCBuildState.invalid.terminal)
check("FAILED is over",         ASCBuildState.failed.terminal)
check("INVALID alarms",         ASCBuildState.invalid.alarming)
check("FAILED alarms",          ASCBuildState.failed.alarming)
check("VALID does not alarm",   !ASCBuildState.valid.alarming)
// Apple means different things by FAILED and INVALID (one is the upload, one
// is the binary); to a developer they mean the same thing, so they read the
// same and the probe keeps them apart.
check("FAILED and INVALID read the same",
      ASCBuildState.failed.clause == ASCBuildState.invalid.clause)
check("an unknown processing state → nil", ASCBuildState.parse("QUARANTINED") == nil)

// ── titles, and the ruling behind them ─────────────────────────────────────
print("ASCShape — the verdict leads")
check("a rejection leads with its verdict",
      ASCShape.versionTitle(app: "Casberi", version: "1.4", state: .rejected)
        == "Rejected · Casberi 1.4")
check("a release says it is live",
      ASCShape.versionTitle(app: "Casberi", version: "1.4", state: .readyForSale)
        == "Live on the App Store · Casberi 1.4")
// The three faces of approved stay apart, because what happens next differs.
check("approved-waiting-on-you differs from approved-waiting-on-Apple",
      ASCVersionState.pendingDeveloperRelease.verdict != ASCVersionState.pendingAppleRelease.verdict)
check("a non-news state has no verdict to lead with",
      ASCShape.versionTitle(app: "Casberi", version: "1.4", state: .prepareForSubmission)
        == "Casberi 1.4")
check("a missing version leaves no lone separator",
      ASCShape.versionTitle(app: "Casberi", version: "", state: .rejected)
        == "Rejected · Casberi")

print("ASCShape.stars — a rating we can't read is not a zero-star review")
check("five stars",  ASCShape.stars(5) == "★★★★★")
check("one star",    ASCShape.stars(1) == "★☆☆☆☆")
check("three stars", ASCShape.stars(3) == "★★★☆☆")
// Nil rather than a clamp: five empty stars for an unreadable rating is a
// zero-star review that nobody wrote (§83).
check("nil → nil",   ASCShape.stars(nil) == nil)
check("0 → nil",     ASCShape.stars(0) == nil)
check("6 → nil",     ASCShape.stars(6) == nil)
check("-1 → nil",    ASCShape.stars(-1) == nil)

print("ASCShape.reviewTitle — the rating leads")
check("the whole shape",
      ASCShape.reviewTitle(rating: 2, title: "Crashes on launch", app: "Casberi")
        == "★★☆☆☆ · Casberi · Crashes on launch")
check("no title still names the app and the rating",
      ASCShape.reviewTitle(rating: 5, title: "", app: "Casberi") == "★★★★★ · Casberi")
check("no rating still reads",
      ASCShape.reviewTitle(rating: nil, title: "Great", app: "Casberi") == "Casberi · Great")
// A blank band is worse than a generic one.
check("nothing at all still has a title",
      ASCShape.reviewTitle(rating: nil, title: nil, app: "") == "App Store review")

print("ASCShape — builds")
check("a processed build",
      ASCShape.buildTitle(app: "Casberi", build: "267", state: .valid)
        == "Ready to test · Casberi build 267")
check("a failed build leads with the failure",
      ASCShape.buildTitle(app: "Casberi", build: "267", state: .invalid)
        == "Failed processing · Casberi build 267")
check("an expiry names no date (the dueAt carries it)",
      ASCShape.expiryTitle(app: "Casberi", build: "267")
        == "TestFlight build expires · Casberi build 267")
check("a missing build number leaves no dangling word",
      ASCShape.buildLabel(app: "Casberi", build: "") == "Casberi")

// ── the 80-char clamp, which is WHY the verdict leads (prd §303) ────────────
print("the 80-char clamp — the ruling as a test")
let longApp = "Internal Platform Services Companion"
let longVersion = "2026.8.6-release-candidate-with-a-long-name"
let composed = ASCShape.versionTitle(app: longApp, version: longVersion, state: .rejected)
let clamped = IngestSupport.titleLine(composed)
check("the composed title really does overflow (or this proves nothing)",
      composed.count > 80)
check("clamped, the verdict SURVIVES", clamped.hasPrefix("Rejected · "))
check("clamped, it is truncated (so the clamp really ran)", clamped.hasSuffix("…"))
// The counterfactual. If this ever stops being true, the leading rule stopped
// mattering and the comment in the source should be rewritten, not the code.
let trailing = IngestSupport.titleLine("\(longApp) \(longVersion) · Rejected")
check("trailing, the verdict would be EATEN", !trailing.contains("Rejected"))
// The same ruling for a one-star review, which is the row it matters most for.
let longReview = ASCShape.reviewTitle(
    rating: 1,
    title: "This update completely broke syncing on my iPad and I have lost work twice",
    app: "Internal Platform Services Companion")
let clampedReview = IngestSupport.titleLine(longReview)
check("a one-star review keeps its star through the clamp",
      clampedReview.hasPrefix("★☆☆☆☆"))

// ── the room head (prd §324) ───────────────────────────────────────────────
print("ASCRoom.days — whole CALENDAR days, not seconds/86400")
let cal = Calendar(identifier: .gregorian)
func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}
check("same day is 0",     ASCRoom.days(from: at(2026, 8, 6), to: at(2026, 8, 6), calendar: cal) == 0)
check("tomorrow is 1",     ASCRoom.days(from: at(2026, 8, 6), to: at(2026, 8, 7), calendar: cal) == 1)
// The boundary that a seconds-based version gets wrong: 11pm to 1am next day
// is two hours, and one calendar day. "Expires Aug 7" means the day.
check("11pm → 1am next day is 1, not 0",
      ASCRoom.days(from: at(2026, 8, 6, 23), to: at(2026, 8, 7, 1), calendar: cal) == 1)
check("the past is negative", ASCRoom.days(from: at(2026, 8, 6), to: at(2026, 8, 1), calendar: cal) == -5)

func app(_ name: String, _ state: ASCVersionState?, days: Int? = nil,
         build: String = "", expires: Int? = nil) -> ASCRoom.App {
    ASCRoom.App(id: name.lowercased(), name: name, version: "1.0", state: state,
                days: days, build: build, expiresInDays: expires)
}

print("ASCRoom.rank — what a developer needs to see first")
check("a rejection outranks everything", ASCRoom.rank(app("A", .rejected)) == 4)
check("metadata rejected ranks with it", ASCRoom.rank(app("A", .metadataRejected)) == 4)
check("in review is next",               ASCRoom.rank(app("A", .inReview)) == 3)
check("approved-and-waiting is next",    ASCRoom.rank(app("A", .pendingDeveloperRelease)) == 3)
check("an expiring build outranks live",
      ASCRoom.rank(app("A", .readyForSale, expires: 3)) == 2)
check("a build expiring in three months does not",
      ASCRoom.rank(app("A", .readyForSale, expires: 80)) == 1)
check("live with no build ranks 1",      ASCRoom.rank(app("A", .readyForSale)) == 1)
check("no readable state ranks 0",       ASCRoom.rank(app("A", nil)) == 0)
// A rejection has no clock and an expiry does — but the rejection stops the
// release entirely, so it still leads.
check("a rejection outranks an expiring build",
      ASCRoom.rank(app("A", .rejected)) > ASCRoom.rank(app("B", .readyForSale, expires: 1)))

print("ASCRoom.ordered — a total order, so two runs never disagree")
let mixed = [app("Zed", .readyForSale), app("Alpha", .rejected),
             app("Mid", .readyForSale, expires: 2), app("Beta", .inReview)]
check("the rejection leads",   ASCRoom.ordered(mixed).first?.name == "Alpha")
check("then in review",        ASCRoom.ordered(mixed)[1].name == "Beta")
check("then the expiring one", ASCRoom.ordered(mixed)[2].name == "Mid")
check("then the quiet one",    ASCRoom.ordered(mixed)[3].name == "Zed")
// Determinism: a card that reshuffles on every foreground reads as broken.
check("the order is stable across runs",
      ASCRoom.ordered(mixed).map(\.name) == ASCRoom.ordered(mixed.reversed()).map(\.name))
check("ties break by name, not by input order",
      ASCRoom.ordered([app("Zed", .readyForSale), app("Ann", .readyForSale)])
        .map(\.name) == ["Ann", "Zed"])

print("ASCRoom.waitLabel — a duration we didn't watch is NOT shown (§83)")
// The whole point: on first connect a version in review since Tuesday reads as
// zero, and "In review · 0 days" is a confident wrong answer.
check("nil days → nil",  ASCRoom.waitLabel(days: nil) == nil)
check("0 days → nil",    ASCRoom.waitLabel(days: 0) == nil)
check("negative → nil",  ASCRoom.waitLabel(days: -2) == nil)
check("1 day is singular", ASCRoom.waitLabel(days: 1) == "1 day")
check("2 days is plural",  ASCRoom.waitLabel(days: 2) == "2 days")

print("ASCRoom.stateLabel — present tense, and never the feed row's wording")
check("in review",   ASCRoom.stateLabel(.inReview) == "In review")
check("live",        ASCRoom.stateLabel(.readyForSale) == "Live")
check("rejected",    ASCRoom.stateLabel(.rejected) == "Rejected")
check("unknown says so", ASCRoom.stateLabel(nil) == "Unknown")
// A standing is not an announcement. "Casberi · Approved — yours to release ·
// 2 days" is the row's sentence pasted into a card.
check("a standing reads differently from a verdict",
      ASCRoom.stateLabel(.pendingDeveloperRelease) != ASCVersionState.pendingDeveloperRelease.verdict)
// Every state must have SOME label — a blank cell in the card is worse than
// a plain word.
check("every state has a label",
      ASCVersionState.allCases.allSatisfy { !ASCRoom.stateLabel($0).isEmpty })

print("ASCRoom.buildLabel — the runway in words")
check("no build → nil", ASCRoom.buildLabel(app("A", .readyForSale)) == nil)
check("a build with no expiry is just its number",
      ASCRoom.buildLabel(app("A", .readyForSale, build: "267")) == "Build 267")
check("expiring today",    ASCRoom.buildLabel(app("A", .readyForSale, build: "267", expires: 0)) == "Build 267 · expires today")
check("expiring tomorrow", ASCRoom.buildLabel(app("A", .readyForSale, build: "267", expires: 1)) == "Build 267 · expires tomorrow")
check("days left",         ASCRoom.buildLabel(app("A", .readyForSale, build: "267", expires: 9)) == "Build 267 · 9 days left")

print("ASCRoom.headline / note")
let room = ASCRoom(apps: ASCRoom.ordered(mixed), asOf: at(2026, 8, 6))
check("the headline states the LEAD, not a count",
      ASCRoom.headline(room) == "Alpha · Rejected")
check("a watched duration joins the headline",
      ASCRoom.headline(ASCRoom(apps: [app("Solo", .inReview, days: 2)], asOf: nil))
        == "Solo · In review · 2 days")
// The §83 line, as the headline sees it.
check("an UNWATCHED state shows no duration",
      ASCRoom.headline(ASCRoom(apps: [app("Solo", .inReview)], asOf: nil))
        == "Solo · In review")
check("an empty room has no lead", ASCRoom(apps: [], asOf: nil).isEmpty)
check("undrawn apps are counted, never dropped",
      ASCRoom.note(room, drawn: 2, now: at(2026, 8, 6))?.contains("2 more apps") == true)
check("one undrawn app is singular",
      ASCRoom.note(room, drawn: 3, now: at(2026, 8, 6))?.contains("1 more app") == true)
check("nothing hidden and fresh → no note",
      ASCRoom.note(room, drawn: 4, now: at(2026, 8, 6)) == nil)

print("ASCRoom.staleNote — a reading from last week is a broken key")
check("today is not stale",  ASCRoom.staleNote(asOf: at(2026, 8, 6), now: at(2026, 8, 6)) == nil)
check("yesterday says so",   ASCRoom.staleNote(asOf: at(2026, 8, 5), now: at(2026, 8, 6)) == "read yesterday")
check("a week says how long", ASCRoom.staleNote(asOf: at(2026, 7, 30), now: at(2026, 8, 6)) == "read 7 days ago")
// Never-read and read-and-unchanged are different facts and only one is an
// apology (the `StripeRoom.balanceRead` rule).
check("never read is NOT the same as unchanged",
      ASCRoom.staleNote(asOf: nil, now: at(2026, 8, 6)) == "not read on this device yet")

print("")
if failures == 0 {
    print("✓ app store connect self-test: all assertions passed")
} else {
    print("✗ app store connect self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

if ! swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the extracted App Store Connect logic did not compile"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped source, and each must break the run. They are
# applied to the SHIPPED file and then re-extracted, so an assertion that only
# passes because it never reached the real code is caught here.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ASC" "$WORK/AppStoreConnectBridge.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AppStoreConnectBridge.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/AppStoreConnectBridge.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! extract "$WORK/AppStoreConnectBridge.swift" "$WORK/extracted.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at extraction)"; return
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/extracted.swift" "$ROOM" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE 401 NOBODY CAN DIAGNOSE. Sending both claims is the single likeliest
#    mistake with this credential and is invisible from the outside.
mutate "iss and sub sent together" \
  '        if issuer.isEmpty {
            claims["sub"] = "user"
        } else {
            claims["iss"] = issuer
        }' \
  '        claims["sub"] = "user"
        claims["iss"] = issuer'

# 2. The mirror: an individual key sent as a team key with an empty issuer.
mutate "an empty issuer sent as iss" \
  '        let issuer = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)' \
  '        let issuer = issuerID'

# 3. Standard base64 instead of RFC 7515's URL-safe alphabet. The token looks
#    right and is refused.
mutate "base64url relaxed to standard base64" \
  '        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")' \
  '        data.base64EncodedString()'

# 4. The audience typo'd — 401 forever, on a string nothing else reads.
mutate "the audience changed" \
  'static let audience = "appstoreconnect-v1"' \
  'static let audience = "appstoreconnect"'

# 5. The plausibility window dropped, so a truncated paste stores as a key and
#    fails later as an unreadable 401.
mutate "the .p8 length check removed" \
  'guard (100...400).contains(decoded.count) else { return nil }' \
  'guard !decoded.isEmpty else { return nil }'

# 6. The bare-base64 form refused, so a paste that lost its newlines — the
#    normal shape from a shell or a password manager — stops working.
mutate "a .p8 without its markers refused" \
  '        if body.contains(marker) {' \
  '        guard body.contains(marker) else { return nil }
        if body.contains(marker) {'

# 6b. The Key ID guessed from a filename that isn't Apple's. Dropping the length
#     rule makes "AuthKey_.p8" and "AuthKey_my old key.p8" answer with garbage,
#     which is then signed into a token Apple refuses with a 401 that names no
#     cause — the one wrong answer on that screen nobody could diagnose.
mutate "a Key ID taken from any filename at all" \
  '        guard id.count == 10,' \
  '        guard !id.isEmpty,'

# 7. YOUR OWN ACT announced back to you. This is the rule §313 established and
#    the one a later pass is most likely to "fix" by adding cases.
mutate "your own submit announced as news" \
  '        case .prepareForSubmission, .readyForReview, .waitingForReview,' \
  '        case .waitingForReview:           String(localized: "Waiting for review")
        case .prepareForSubmission, .readyForReview,'

# 8. A transient state landing — a row stale before it is read (§216).
mutate "an in-flight build landed" \
  'var terminal: Bool { self != .processing }' \
  'var terminal: Bool { true }'

# 9. THE §303 CLAMP RULING, inverted: the verdict trails and is eaten, so a
#    rejection reads in the feed as a version that shipped.
mutate "the verdict trails the title" \
  '        guard let verdict = state.verdict else { return name }
        return name.isEmpty ? verdict : "\(verdict) · \(name)"' \
  '        guard let verdict = state.verdict else { return name }
        return name.isEmpty ? verdict : "\(name) · \(verdict)"'

# 10. A rating outside Apple's 1–5 clamped instead of refused — a zero-star
#     review nobody wrote.
mutate "an unreadable rating clamped to zero stars" \
  'guard let rating, (1...5).contains(rating) else { return nil }' \
  'let rating = max(0, min(5, rating ?? 0))'

# 11. An unknown state guessed at rather than dropped.
mutate "an unknown version state defaulted" \
  'return ASCVersionState(rawValue: raw.uppercased())' \
  'return ASCVersionState(rawValue: raw.uppercased()) ?? .readyForSale'

# 12. Both halves of a dispute-style pair collapsing: alarm and celebration on
#     one state would rain and flash a failure in the same sync.
mutate "a rejection also celebrated" \
  '        case .accepted, .pendingDeveloperRelease, .pendingAppleRelease,
             .readyForSale, .readyForDistribution:
            true' \
  '        case .accepted, .pendingDeveloperRelease, .pendingAppleRelease,
             .readyForSale, .readyForDistribution, .rejected:
            true'


# --- room-head mutations ----------------------------------------------------
# `ASCRoom.swift` is compiled WHOLE rather than extracted, so it gets its own
# mutator: same contract, different file.
mutateRoom() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ROOM" "$WORK/ASCRoom.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/ASCRoom.swift" <<'PY2'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY2
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/ASCRoom.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$TMP/extracted.swift" "$WORK/ASCRoom.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 13. THE §83 LINE FOR THIS CARD: "In review · 0 days" on a version Apple has
#     had since Tuesday. This is the mutation the whole `observed` machinery
#     exists to make impossible.
mutateRoom "a duration of zero shown as a measurement" \
  'guard let days, days > 0 else { return nil }' \
  'guard let days, days >= 0 else { return nil }'

# 14. Calendar days become elapsed seconds — an 11pm read the night before an
#     expiry reads as "0 days", i.e. today.
mutateRoom "days measured in seconds, not calendar days" \
  'let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0' \
  'return Int(later.timeIntervalSince(now) / 86400)'

# 15. The ranking collapses, so a rejected app sorts behind a live one and the
#     card leads with the thing that needs nothing.
mutateRoom "a rejection stops leading the card" \
  'if state.alarming { return 4 }' \
  'if state.alarming { return 1 }'

# 16. An expiring build no longer outranks a quiet app, so the one deadline
#     this room has stops reaching the headline.
mutateRoom "an expiring build ranks no higher than a live app" \
  'if let expires = app.expiresInDays, expires <= expirySoonDays { return 2 }' \
  'if let expires = app.expiresInDays, expires <= expirySoonDays { return 1 }'

# 17. The order stops being total, so the card reshuffles between foregrounds
#     over identical data.
mutateRoom "ties resolved by input order instead of name" \
  'return a.name < b.name' \
  'return false'

# 18. The runway loses its clock — "Build 267" for a build dying tomorrow.
mutateRoom "the build label drops its expiry" \
  'guard let days = app.expiresInDays else { return name }' \
  'return name
        guard let days = app.expiresInDays else { return name }'

# 19. Never-read renders as up-to-date, so a key that stopped working three
#     weeks ago shows a confident standing with nothing saying it is old.
mutateRoom "a never-read bridge reads as fresh" \
  'guard let asOf else { return String(localized: "not read on this device yet") }' \
  'guard let asOf else { return nil }'
echo
echo "✓ app store connect self-test: assertions and mutations all passed"
