#!/bin/zsh
# Casberi feed-fold self-test — the All feed's fold decisions (prd §377/§378/§379):
#
#   Casberi/Casberi/Model/FeedFold.swift
#     — tier              (provenance: made / concerns / arrived)
#     — bundleable        (may a run collapse into a SENTENCE about it)
#     — stripCandidate    (may it be drawn as its MEMBERS, and by which door)
#     — tileChoices       (door priority, the dedupe asymmetry, the cap)
#     — decide            (strip beats sentence; the two-tile floor)
#     — carriesAClock     (the next event and live rows never fold)
#     — ambient           (a fold recedes only if every member would)
#
# WHY A HARNESS. Every failure here is a SILENT WRONG ANSWER — the class that
# renders perfectly and reads as working, which no build and no screen sweep can
# see:
#
#   • a screenshot run collapsing into "Photos · 4 screenshots", destroying the
#     only thing a screenshot has;
#   • five songs off ONE record drawn as four identical covers, which reads as a
#     rendering fault rather than as volume;
#   • the next-up calendar event folded away, so the one row carrying a
#     countdown stops existing (§35 ruled this must never happen, and until
#     §377 nothing enforced it);
#   • a transaction inside a mixed run receding to 0.68 because the fold was
#     scored on its first member instead of all of them;
#   • the tail-coarsening gate disagreeing with the renderer about how many rows
#     a day draws — §255, which was wrong for a month and found by eye.
#
# `FeedFold.swift` is compiled WHOLE and UNMODIFIED against an inert `Thing`
# stub. Nothing is copied into this file: if the shipped source stops compiling
# against these stubs, the harness fails loudly rather than asserting nothing.
# Its two view-layer dependencies are injected (`faceSources`, `isLive`), which
# is what keeps the file free of SwiftUI/SwiftData — the drift guards below are
# what keep the injected values honest.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FOLD="Casberi/Casberi/Model/FeedFold.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
ROWS="Casberi/Casberi/Screens/ShapedRows.swift"
for f in "$FOLD" "$FEED" "$ROWS"; do
  [[ -f "$f" ]] || { print -u2 "feed-fold-selftest: missing $f"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- stubs
# Inert by design: a `Thing` that is a plain class with the stored properties
# `FeedFold` reads, and nothing else. `ObjectIdentifier` needs a class; the
# fold's own reads need no behaviour at all.
cat > "$WORK/Stubs.swift" <<'SWIFT'
import Foundation

enum ThingKind {
    case note, screenshot, chat, event, link, reminder, mail, file, voice
    case job, run, output, skill, approval, transaction, contact, product, accessory
}

final class Thing {
    var id: UUID
    var kind: ThingKind
    var source: String
    var dueAt: Date?
    var isFlagged: Bool
    var authorAvatarURL: String?
    var previewImageURL: String?
    var previewImageData: Data?

    init(kind: ThingKind = .link, source: String = "RSS", dueAt: Date? = nil,
         isFlagged: Bool = false, authorAvatarURL: String? = nil,
         previewImageURL: String? = nil, previewImageData: Data? = nil) {
        self.id = UUID()
        self.kind = kind
        self.source = source
        self.dueAt = dueAt
        self.isFlagged = isFlagged
        self.authorAvatarURL = authorAvatarURL
        self.previewImageURL = previewImageURL
        self.previewImageData = previewImageData
    }
}
SWIFT

# ---------------------------------------------------------------- assertions
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ok   \(what)") }
    else { print("  FAIL \(what)"); failures += 1 }
}

let FACES: Set<String> = ["Bluesky", "Farcaster", "Nostr", "Stocktwits", "GitHub"]
func post(_ avatar: String) -> Thing {
    Thing(kind: .link, source: "Bluesky", authorAvatarURL: avatar)
}
func shot() -> Thing { Thing(kind: .screenshot, source: "Photos") }
func song(_ cover: String) -> Thing {
    Thing(kind: .link, source: "Music", previewImageURL: cover)
}

// ---- tier ---------------------------------------------------------------
check(FeedFold.tier(shot()) == .made, "a screenshot is something you made")
check(FeedFold.tier(Thing(kind: .voice, source: "Voice")) == .made, "a voice note is made")
check(FeedFold.tier(Thing(kind: .link, source: "You")) == .made, "anything from You is made")
check(FeedFold.tier(Thing(kind: .transaction, source: "Wallet")) == .concerns,
      "money moving concerns you")
check(FeedFold.tier(Thing(kind: .approval, source: "Wallet")) == .concerns,
      "consent waiting on you concerns you")
check(FeedFold.tier(Thing(kind: .event, source: "Calendar")) == .concerns, "your calendar concerns you")
check(FeedFold.tier(Thing(kind: .reminder, source: "Reminders")) == .concerns, "a reminder concerns you")
check(FeedFold.tier(Thing(kind: .link, source: "Stripe", dueAt: Date())) == .concerns,
      "a deadline concerns you whatever its kind")
check(FeedFold.tier(Thing(kind: .link, source: "Wallet", isFlagged: true)) == .concerns,
      "a flagged row concerns you")
check(FeedFold.tier(post("a")) == .arrived, "a post merely arrived")
check(FeedFold.tier(Thing(kind: .link, source: "RSS")) == .arrived, "an article merely arrived")

// ---- ambient ------------------------------------------------------------
check(FeedFold.ambient([post("a"), post("b")]), "a run of posts recedes")
check(!FeedFold.ambient([post("a"), Thing(kind: .transaction, source: "Wallet")]),
      "ONE transaction in a mixed run keeps the whole fold at full weight")
check(!FeedFold.ambient([post("a"), shot()]), "one thing you made keeps the fold at full weight")

// ---- bundleable ---------------------------------------------------------
check(!FeedFold.bundleable(shot()), "a screenshot never collapses into a sentence")
check(!FeedFold.bundleable(Thing(kind: .voice, source: "Voice")), "a voice note never does")
check(!FeedFold.bundleable(Thing(kind: .approval, source: "Wallet")), "an approval never does")
check(!FeedFold.bundleable(Thing(kind: .link, source: "Tokens")), "a watched token never does")
check(!FeedFold.bundleable(Thing(kind: .link, source: "Bitrefill")), "a Bitrefill order never does")
check(!FeedFold.bundleable(Thing(kind: .link, source: "1Claw")), "a 1Claw grant never does")
check(FeedFold.bundleable(Thing(kind: .transaction, source: "Wallet")),
      "a wallet transaction does — machine bulk is what the sentence is for")
check(FeedFold.bundleable(post("a")), "a post does, since 2026-08-09")

// ---- the three doors, in priority order ---------------------------------
check(FeedFold.stripCandidate(shot(), faceSources: FACES), "a screenshot is drawable as itself")
check(FeedFold.stripCandidate(post("a"), faceSources: FACES), "a post with a face is")
check(FeedFold.stripCandidate(song("c"), faceSources: FACES), "a song with a cover is")
check(FeedFold.stripCandidate(Thing(kind: .file, source: "Files",
                                    previewImageData: Data([0x1])), faceSources: FACES),
      "a healed file image is — stored pixels are a picture too")
check(!FeedFold.stripCandidate(Thing(kind: .transaction, source: "Wallet"), faceSources: FACES),
      "a bare transaction is not")
check(!FeedFold.stripCandidate(Thing(kind: .link, source: "Bluesky"), faceSources: FACES),
      "a post with NO avatar is not — a strip can't draw an identity the row lacks")
check(FeedFold.identityLeader(Thing(kind: .link, source: "RSS", authorAvatarURL: "logo"),
                              faceSources: FACES) == nil,
      "RSS's publisher mark is NOT a strip identity (it rides the own-art door)")

// A post carrying BOTH a face and a photo is drawn as WHO — the user's ruling.
let both = Thing(kind: .link, source: "Farcaster",
                 authorAvatarURL: "face", previewImageURL: "photo")
check(FeedFold.tileChoices([both, both, both], faceSources: FACES).first?.remote == "face",
      "the face door outranks the art door")

// ---- the dedupe asymmetry ----------------------------------------------
let threePeople = [post("a"), post("b"), post("c"), post("a"), post("b")]
check(FeedFold.tileChoices(threePeople, faceSources: FACES).count == 3,
      "five posts from three people draw THREE faces")
let oneAlbum = [song("cover"), song("cover"), song("cover"), song("cover"), song("cover")]
check(FeedFold.tileChoices(oneAlbum, faceSources: FACES).count == 1,
      "five songs off one record draw ONE cover")
check(FeedFold.tileChoices([shot(), shot(), shot(), shot(), shot()],
                           faceSources: FACES).count == 4,
      "five screenshots draw four DIFFERENT pictures — stored pixels never dedupe")
check(FeedFold.tileChoices(Array(repeating: 0, count: 9).map { _ in post(UUID().uuidString) },
                           faceSources: FACES).count == FeedFold.stripCap,
      "the cap holds")

// A choice names its member by index, and the indices must be real.
let choices = FeedFold.tileChoices(threePeople, faceSources: FACES)
check(choices.allSatisfy { $0.index >= 0 && $0.index < threePeople.count },
      "every tile choice indexes a real member")
check(choices.first?.circular == true, "a face is a circle")
check(FeedFold.tileChoices(oneAlbum, faceSources: FACES).first?.circular == false,
      "a cover is a squircle")

// ---- decide: strip beats sentence, and the two-tile floor ---------------
if case .strip(let s)? = FeedFold.decide([shot(), shot(), shot()], faceSources: FACES) {
    check(s.count == 3, "three screenshots strip")
} else { check(false, "three screenshots strip") }

if case .bundle(let art)? = FeedFold.decide(oneAlbum, faceSources: FACES) {
    check(art == ["cover"], "one record falls under the two-tile floor and lands as ONE cover")
} else { check(false, "one record lands as a bundle with one cover") }

if case .strip? = FeedFold.decide(threePeople, faceSources: FACES) {
    check(true, "three distinct people strip")
} else { check(false, "three distinct people strip") }

let txns = (0..<5).map { _ in Thing(kind: .transaction, source: "Wallet") }
if case .bundle(let art)? = FeedFold.decide(txns, faceSources: FACES) {
    check(art.isEmpty, "pictureless machine bulk lands as a bare sentence")
} else { check(false, "transactions land as a sentence") }

check(FeedFold.decide([shot(), shot()], faceSources: FACES) == nil,
      "two of anything is under the threshold — no fold at all")
// A run that cannot strip AND holds an exemption must not be swallowed.
let mixed = [shot(), Thing(kind: .link, source: "Photos"), Thing(kind: .link, source: "Photos")]
check(FeedFold.decide(mixed, faceSources: FACES) == nil,
      "an unstrippable run holding a screenshot never becomes a sentence")

// ---- the clock carve-out ------------------------------------------------
let next = Thing(kind: .event, source: "Calendar")
check(FeedFold.carriesAClock(next, nextEventID: next.id, isLive: false),
      "the next upcoming event never folds")
check(!FeedFold.carriesAClock(Thing(kind: .event, source: "Calendar"),
                              nextEventID: next.id, isLive: false),
      "its siblings still fold")
check(FeedFold.carriesAClock(Thing(kind: .link, source: "Twitch"),
                             nextEventID: nil, isLive: true),
      "a live row never folds")

print(failures == 0 ? "feed-fold-selftest: OK" : "feed-fold-selftest: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$WORK/run" "$WORK/Stubs.swift" "$FOLD" "$WORK/main.swift" 2>&1 \
  || { print -u2 "feed-fold-selftest: FeedFold.swift no longer compiles against the inert stubs"; exit 1; }
"$WORK/run"

# ---------------------------------------------------------------- mutations
# A check that cannot fail proves nothing. Each mutation is a silent wrong
# answer this harness must catch.
mutate() {
  local name="$1" from="$2" to="$3"
  local dir="$WORK/mut"; rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$FOLD" "$dir/FeedFold.swift" "$from" "$to" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if s.count(a) != 1:
    sys.stderr.write("MUTATION STALE (matched %d times): %s\n" % (s.count(a), a[:60]))
    sys.exit(2)
open(dst, "w").write(s.replace(a, b))
PY
  if ! swiftc -O -o "$dir/run" "$WORK/Stubs.swift" "$dir/FeedFold.swift" "$WORK/main.swift" >/dev/null 2>&1; then
    print -u2 "  MUTATION DID NOT COMPILE: $name"; return 1
  fi
  if "$dir/run" >/dev/null 2>&1; then
    print -u2 "  MUTATION SURVIVED: $name"; return 1
  fi
  print "  caught: $name"
}

print "mutations:"
mutate "remote images stop deduping (one album draws four identical covers)" \
       'guard seenRemote.insert(art).inserted else { continue }' \
       'if false { continue }'
mutate "stored pixels start deduping (screenshots collapse to one tile)" \
       '} else if t.kind == .screenshot || t.previewImageData != nil {
                choices.append(TileChoice(index: index, remote: nil, circular: false))' \
       '} else if t.kind == .screenshot || t.previewImageData != nil {
                guard seenRemote.insert("pixels").inserted else { continue }
                choices.append(TileChoice(index: index, remote: nil, circular: false))'
mutate "the two-tile floor drops to one (a lone face becomes a strip)" \
       'if choices.count >= 2 { return .strip(choices) }' \
       'if choices.count >= 1 { return .strip(choices) }'
mutate "screenshots become bundleable (a run becomes a sentence)" \
       't.kind != .screenshot && t.kind != .voice && t.kind != .approval' \
       't.kind != .voice && t.kind != .approval'
mutate "the clock carve-out is removed (the next event folds away)" \
       'if let nextEventID, t.id == nextEventID { return true }' \
       'if let nextEventID, t.id == nextEventID, false { return true }'
mutate "a live row folds away" \
       'return isLive' \
       'return false'
mutate "the art door outranks the face door (a post is drawn as its photo)" \
       'if let face = identityLeader(t, faceSources: faceSources) {' \
       'if let face: String? = nil, false {'
mutate "RSS becomes a strip identity (a feed logo repeats four times)" \
       'faceSources.contains(t.source) else { return nil }' \
       'true else { return nil }'
mutate "ambient scores the first member instead of all of them" \
       'members.allSatisfy { tier($0) == .arrived }' \
       'members.first.map { tier($0) == .arrived } ?? true'
mutate "a transaction stops concerning you" \
       't.kind == .approval || t.kind == .transaction' \
       't.kind == .approval'
mutate "the strip cap is ignored" \
       'guard choices.count < stripCap else { break }' \
       'guard choices.count < 999 else { break }'
mutate "an unstrippable run swallows its exemptions" \
       'guard members.allSatisfy(bundleable) else { return nil }' \
       'if false { return nil }'

# ---------------------------------------------------------------- drift guards
# What the compiled functions cannot prove: that the app still HANDS them the
# right values. Comment-stripped, because this file documents its own rules by
# naming them (the Obsidian/Cursor lesson).
strip_comments() { sed -E 's://.*$::' "$1"; }
guard() {
  local what="$1" file="$2" pat="$3"
  if strip_comments "$file" | grep -Eq "$pat"; then print "  ok   $what"
  else print -u2 "  DRIFT: $what"; return 1; fi
}

print "drift guards:"
guard "FeedScreen injects BandRow.faceSources into the fold" \
      "$FEED" 'FeedFold\.(decide|stripCandidate)\([^)]*faceSources: BandRow\.faceSources'
# Two guards, not one spanning both: the call wraps across two lines and
# `grep -E` is line-based, so a single pattern reaching from `carriesAClock` to
# `isLive:` matches NOTHING and certifies nothing — caught on this harness's
# own first validation, which is the whole reason every guard here is checked
# against the real tree rather than assumed.
guard "the clock carve-out is called at all" \
      "$FEED" 'FeedFold\.carriesAClock\('
guard "and is fed the bridge's own live set" \
      "$FEED" 'isLive: isLive\(t\)'
guard "the coarsening gate asks the SAME decision the renderer does (§255)" \
      "$FEED" 'where FeedFold\.decide\('
guard "BandRow still declares the face registry the fold is handed" \
      "$ROWS" 'static let faceSources'
guard "a fold's weight is asked of every member (§378)" \
      "$FEED" 'FeedFold\.ambient\(members\)'
guard "FeedFold imports no SwiftUI or SwiftData — the whole reason it compiles here" \
      "$FOLD" '^import Foundation$'
if strip_comments "$FOLD" | grep -Eq '^import (SwiftUI|SwiftData)'; then
  print -u2 "  DRIFT: FeedFold gained a UI/store import and is no longer harnessable"; exit 1
fi

print "feed-fold-selftest: OK"
