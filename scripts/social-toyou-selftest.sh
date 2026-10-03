#!/bin/zsh
# Casberi social to-you self-test — what leads the Social room as "To you"
# and who Follow suggests (prd §1086):
#
#   Casberi/Casberi/Model/SocialScope.swift   (compiled whole)
#
# WHY A HARNESS. The user's case: follow a starter pack and yourself, and the
# reply someone sent you sits under forty people's posts. Both failures render
# as a calm room. Too loose, and "New post from mia" — a notice about someone
# you follow — leads as if it were to you; too tight, and a reply or a mention
# of your handle never reaches the top. Which rows are to you is a table of
# stable signals per network, and only a case-by-case statement says it is
# right.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SCOPE="Casberi/Casberi/Model/SocialScope.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+SocialRoom.swift"
SHEET="Casberi/Casberi/Screens/SocialFollowSheet.swift"
for f in "$SCOPE" "$ROOM" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q 'SocialToYou.leading(' "$ROOM" \
  || { echo "✗ All no longer leads with what is to you"; exit 1; }
grep -q 'SocialToYou.isToYou(' "$ROOM" \
  || { echo "✗ the To you tile no longer reads SocialToYou.isToYou"; exit 1; }
grep -q 'leadIDs.contains' "$ROOM" \
  || { echo "✗ a row leading All is no longer lifted out of its day — it would stand twice"; exit 1; }
grep -q 'SocialToYou.suggestions(' "$SHEET" \
  || { echo "✗ Follow no longer reads SocialToYou.suggestions"; exit 1; }
grep -q 'socialRoomSections(' Casberi/Casberi/Screens/FeedScreen+ShapedSections.swift \
  || { echo "✗ the Social room no longer draws its own sections"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$SCOPE" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let now = Date(timeIntervalSince1970: 2_000_000_000)
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
let me: Set<String> = ["alex.bsky.social", "alex"]
func row(_ source: String, _ context: String? = nil, ref: String? = nil,
         title: String = "x", text: String? = nil) -> SocialToYou.Row {
    .init(source: source, socialContext: context, sourceRef: ref, title: title, text: text)
}
func to(_ r: SocialToYou.Row) -> Bool { SocialToYou.isToYou(r, myHandles: me) }

// ── To you ───────────────────────────────────────────────────────────
check(to(row("Bluesky", "reply")), "a reply to you is to you")
check(to(row("Farcaster", "follow")), "a new follower is to you")
check(to(row("Instagram", "follow", ref: "ig-live:notif:1")), "an Instagram follow is to you")
check(to(row("Bluesky", "mention", text: "nice one @alex.bsky.social!")), "a mention of your handle is to you")
check(to(row("Farcaster", "mention", text: "cc @Alex")), "a mention matches without case")
check(!to(row("Bluesky", "mention", text: "thanks @maya.bsky.social")), "a mention of someone else is not")
check(!to(row("Farcaster", "liked")), "what someone you follow liked is not")
check(!to(row("Farcaster", "recast")), "what someone you follow recast is not")
check(!to(row("Bluesky")), "a post by someone you follow is not")
check(to(row("TikTok", ref: "tiktok:live:notif:3", title: "rui liked your video")), "a TikTok notice is to you")
check(to(row("Instagram", ref: "ig-live:notif:2", title: "lena liked your photo.")), "an Instagram notice is to you")
check(to(row("X", ref: "x-live:notif:1", title: "sam reposted your post")), "an X notice about your post is to you")
check(!to(row("X", ref: "x-live:notif:2", title: "New post from mia")), "X's new-post notice is about mia, not you")
check(!to(row("X", ref: "x-live:notif:3", title: "New post notifications for mia and 6 others")), "X's digest is not to you")
check(!to(row("X", ref: "x-archive:1")), "an archived post is not")
check(!SocialToYou.isToYou(row("Bluesky", "mention", text: "@"), myHandles: [""]), "an empty handle matches nothing")

// ── What leads All ───────────────────────────────────────────────────
let rows: [(row: SocialToYou.Row, at: Date)] = [
    (row("Bluesky"), ago(0.1)),
    (row("Bluesky", "reply"), ago(0.5)),
    (row("Farcaster", "follow"), ago(1)),
    (row("Bluesky", "reply"), ago(2)),
    (row("Bluesky", "reply"), ago(3)),
    (row("Farcaster", "reply"), ago(9)),
    (row("Farcaster", "reply"), now.addingTimeInterval(3_600)),
]
let lead = SocialToYou.leading(rows, myHandles: me, now: now)
check(lead == [1, 2, 3], "the week's three newest rows to you lead, newest first")
check(!lead.contains(0), "a post by someone you follow never leads as to you")
check(!lead.contains(5), "a reply older than a week does not lead")
check(!lead.contains(6), "a row dated ahead does not lead")

// ── Mentions ─────────────────────────────────────────────────────────
check(SocialToYou.mentions(in: "hi @maya.bsky.social and @Jon.") == ["maya.bsky.social", "jon"], "handles, lower-cased, without the sentence's full stop")
check(SocialToYou.mentions(in: "mail me at a@b.com") == [], "an email address is not a mention")

// ── Suggestions ──────────────────────────────────────────────────────
let s = SocialToYou.suggestions(
    talkers: [("Bluesky", "@Nikhil.bsky.social", ago(1)), ("Farcaster", "sam", ago(2)),
              ("Bluesky", "nikhil.bsky.social", ago(3)), ("X", "kim", ago(1)),
              ("Bluesky", "alex.bsky.social", ago(1))],
    posts: [("Bluesky", "great thread by @eva.bsky.social", ago(1)),
            ("Bluesky", "+1 @eva.bsky.social @eva.bsky.social", ago(2)),
            ("Bluesky", "@once.bsky.social", ago(2)),
            ("Bluesky", "@old.bsky.social", ago(10)), ("Bluesky", "@old.bsky.social", ago(11)),
            ("Bluesky", "@nikhil.bsky.social @nikhil.bsky.social", ago(1)),
            ("Bluesky", "@mia.bsky.social", ago(1)), ("Bluesky", "@mia.bsky.social", ago(2))],
    watched: ["Farcaster": ["sam"], "Bluesky": ["mia.bsky.social"]], mine: me, now: now)
check(s.first == .init(source: "Bluesky", handle: "nikhil.bsky.social", why: .talksToYou), "who talks to you leads, once, normalised")
check(!s.contains { $0.handle == "sam" }, "someone you follow is never suggested")
check(!s.contains { $0.handle == "kim" }, "a network Follow cannot land on is never suggested")
check(!s.contains { $0.handle == "alex.bsky.social" }, "you are never suggested to yourself")
check(s.contains(.init(source: "Bluesky", handle: "eva.bsky.social", why: .mentioned(2))), "two posts naming someone make a suggestion, counted once a post")
check(!s.contains { $0.handle == "once.bsky.social" }, "one mention is not enough")
check(!s.contains { $0.handle == "old.bsky.social" }, "mentions older than a week do not count")
check(!s.contains { $0.handle == "mia.bsky.social" }, "a mention of someone you follow is not a suggestion")
check(s.filter { $0.handle == "nikhil.bsky.social" }.count == 1, "someone who talks to you and is named stands once")

// ── The tiles ────────────────────────────────────────────────────────
check(SocialScope.allCases == [.all, .toYou, .follow], "All, To you, then Follow")
check(SocialScope.allCases.filter(\.isVerb) == [.follow], "Follow is the verb")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
print("✓ social to-you: what is to you, what leads All, mentions, suggestions, tiles")
SWIFT
swiftc -O -o "$TMP/run" "$TMP/SocialScope.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
"$TMP/run"
