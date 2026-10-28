#!/bin/zsh
# Casberi X Following self-test (prd §1582) — the pure half of the Following
# timeline, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/XFollowingRead.swift
#
# The fixtures copy the structure MEASURED on a signed-in session on
# 2026-10-27 (`-xFollowingProbe shape`: keys and types only, no words). Every
# failure here is silent on a device:
#
#   · an ad lands as a post from someone you follow
#   · a reply thread lands its root, a stranger's post, instead of the reply
#     that brought it to your timeline
#   · a repost lands under the reposter's name, or your own posts come back
#     to you as news
#   · a post older than the keep window lands, is pruned, and lands again on
#     every read
#   · an opened post is pruned, or the "New post" notices come back beside
#     the posts that replace them
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

READ="Casberi/Casberi/Model/XFollowingRead.swift"
LAND="Casberi/Casberi/Model/XLiveFollowing.swift"
LIVE="Casberi/Casberi/Model/XLiveNotifications.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
for f in "$READ" "$LAND" "$LIVE" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# Code lines only, so a comment quoting a line cannot satisfy or trip these.
code() { grep -vE '^[[:space:]]*//' "$1" }
LIVE_CODE="$(code "$LIVE")"
LAND_CODE="$(code "$LAND")"
SHEET_CODE="$(code "$SHEET")"
print -r -- "$LIVE_CODE" | grep -qF 'let following = await XLiveFollowing.refresh(auth: auth, context: context)' \
  || { echo "✗ the X sweep no longer reads the Following timeline"; exit 1; }
print -r -- "$LIVE_CODE" | grep -qF 'if following != nil, let text = notificationText(entry),' \
  || { echo "✗ the 'New post' notices are no longer gated on the Following read answering — they land beside the posts, or vanish when it fails"; exit 1; }
print -r -- "$LIVE_CODE" | grep -qF 'XFollowingRead.isNewPostNotice(text) { continue }' \
  || { echo "✗ the 'New post' notices are no longer skipped while the posts land"; exit 1; }
for helper in 'XPostShape.author(result)' 'XPostShape.face(of: user)' 'XPostShape.words(result)' \
              'XPostShape.expandLinks(text, result: result)' 'XPostShape.imageURLs(result)'; do
  print -r -- "$LIVE_CODE" | grep -qF "$helper" \
    || { echo "✗ the notices read no longer shares the post parser ($helper) — two parsers for one shape drift"; exit 1; }
done
print -r -- "$LAND_CODE" | grep -qF 'XFollowingRead.prunes(at: thing.capturedAt, opened: opened.contains(ref), now: now)' \
  || { echo "✗ the prune no longer asks the pure rule (age, and never an opened post)"; exit 1; }
print -r -- "$LAND_CODE" | grep -qF 'guard XFollowingRead.isNewPostNotice(thing.title) else { continue }' \
  || { echo "✗ the landed 'New post' notices are no longer retired once the posts land"; exit 1; }
print -r -- "$LAND_CODE" | grep -qF '"includePromotedContent": false' \
  || { echo "✗ the Following request asks for ads"; exit 1; }
if print -r -- "$LAND_CODE" | grep -qF 'seenTweetIds'; then
  echo "✗ the Following request reports posts seen — the cookie seats are read-only"; exit 1
fi
# A pattern match, not `print | grep -q`: grep quits at the first hit and a
# file this long dies of SIGPIPE under `pipefail`, which reads as a miss.
[[ "$SHEET_CODE" == *'XLiveFollowing.noteOpened(thing)'* ]] \
  || { echo "✗ the thing sheet no longer records an opened Following post — it is pruned after you read it"; exit 1; }
echo "x-following-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

let now = XFollowingRead.date("Tue Oct 27 20:00:00 +0000 2026")!
let me = "999"

func user(_ handle: String, avatar: String? = nil) -> [String: Any] {
    // The newer user shape, as measured: `core.screen_name`, `avatar.image_url`.
    ["user_results": ["result": ["__typename": "User", "rest_id": "u-\(handle)",
                                 "core": ["screen_name": handle, "name": handle],
                                 "avatar": ["image_url": avatar ?? "https://pbs.twimg.com/\(handle)_normal.jpg"]]]]
}
func tweet(_ id: String, by handle: String, userID: String = "1", text: String?,
           at: String = "Tue Oct 27 19:00:00 +0000 2026",
           media: [String] = [], extra: [String: Any] = [:]) -> [String: Any] {
    var legacy: [String: Any] = ["created_at": at, "user_id_str": userID,
                                 "favorite_count": 3, "retweet_count": 1, "reply_count": 2,
                                 "entities": [:] as [String: Any]]
    if let text { legacy["full_text"] = text }
    if !media.isEmpty {
        legacy["extended_entities"] = ["media": media.map { ["media_url_https": $0, "url": "https://t.co/pic"] }]
    }
    for (k, v) in extra { legacy[k] = v }
    return ["__typename": "Tweet", "rest_id": id, "core": user(handle), "legacy": legacy]
}
func entry(_ id: String, _ result: [String: Any], promoted: Bool = false) -> [String: Any] {
    var item: [String: Any] = ["__typename": "TimelineTweet", "itemType": "TimelineTweet",
                               "tweet_results": ["result": result]]
    if promoted { item["promotedMetadata"] = ["advertiser_results": [:] as [String: Any]] }
    return ["entryId": id, "sortIndex": "1", "content": ["entryType": "TimelineTimelineItem", "itemContent": item]]
}
func conversation(_ id: String, _ results: [[String: Any]]) -> [String: Any] {
    ["entryId": id, "sortIndex": "1",
     "content": ["entryType": "TimelineTimelineModule",
                 "items": results.enumerated().map { i, r in
                     ["entryId": "\(id)-\(i)", "item": ["itemContent": ["__typename": "TimelineTweet",
                                                                       "tweet_results": ["result": r]]]]
                 }]]
}
func page(_ entries: [[String: Any]]) -> [String: Any] {
    ["data": ["home": ["home_timeline_urt": ["instructions": [["type": "TimelineAddEntries", "entries": entries]]]]]]
}

let original = tweet("500", by: "ana", text: "the original")
let entries: [[String: Any]] = [
    ["entryId": "cursor-top-1", "content": ["entryType": "TimelineTimelineCursor"]],
    entry("tweet-100", tweet("100", by: "bob", text: "hello https://t.co/abc",
                             extra: ["entities": ["urls": [["url": "https://t.co/abc",
                                                            "expanded_url": "https://example.com/a"]]]])),
    entry("promoted-tweet-200", tweet("200", by: "brand", text: "buy this")),
    entry("tweet-201", tweet("201", by: "brand", text: "sneaky ad"), promoted: true),
    conversation("home-conversation-300", [tweet("301", by: "stranger", text: "root"),
                                           tweet("302", by: "cat", text: "middle"),
                                           tweet("303", by: "dan", text: "the reply")]),
    entry("tweet-400", tweet("400", by: "eve", text: "repost wrapper", at: "Tue Oct 27 18:00:00 +0000 2026",
                             extra: ["retweeted_status_result": ["result": original]])),
    entry("tweet-600", tweet("600", by: "me", userID: me, text: "my own post")),
    entry("tweet-601", tweet("601", by: "me", userID: me, text: "RT",
                             extra: ["retweeted_status_result": ["result": tweet("602", by: "zed", text: "x")]])),
    entry("tweet-700", tweet("700", by: "old", text: "four days old", at: "Fri Oct 23 19:00:00 +0000 2026")),
    entry("tweet-800", ["__typename": "TweetWithVisibilityResults",
                        "tweet": tweet("800", by: "fay", text: "limited replies")]),
    entry("tweet-900", tweet("900", by: "gus", text: nil, media: ["https://pbs.twimg.com/media/a.jpg"])),
    entry("tweet-901", tweet("901", by: "hal", text: nil)),
    entry("tweet-1000", {
        var t = tweet("1000", by: "ivy", text: "quoting this")
        t["quoted_status_result"] = ["result": tweet("1001", by: "jo", text: "the quoted words")]
        return t
    }()),
    entry("tweet-303", tweet("303", by: "dan", text: "the reply")),
    ["entryId": "cursor-bottom-1", "content": ["entryType": "TimelineTimelineCursor"]],
]

let posts = XFollowingRead.posts(page(entries), me: me, now: now)
check(posts != nil, "the measured page shape parses")
let byID = Dictionary(uniqueKeysWithValues: (posts ?? []).map { ($0.restID, $0) })
check((posts ?? []).map(\.restID) == ["100", "303", "500", "800", "900", "1000"],
      "posts in X's order: ads, own posts, stale, empty and repeated entries dropped")
check(byID["200"] == nil && byID["201"] == nil, "a promoted entry never lands, by id or by metadata")
check(byID["301"] == nil && byID["302"] == nil && byID["303"]?.handle == "dan",
      "a reply thread lands the reply that brought it, not its root")
check(byID["100"]?.text == "hello https://example.com/a", "t.co links are expanded")
check(byID["100"]?.avatarURL == "https://pbs.twimg.com/bob_400x400.jpg", "the face is read off the newer user shape, upgraded")
check(byID["100"]?.permalink == "https://x.com/bob/status/100", "the permalink names the author")
check(byID["100"]?.likes == 3 && byID["100"]?.reposts == 1 && byID["100"]?.replies == 2, "counts ride along")
check(byID["500"]?.handle == "ana" && byID["500"]?.repostedBy == "eve" && byID["500"]?.text == "the original",
      "a repost lands the original under its author, marked reposted")
check(byID["500"]?.at == XFollowingRead.date("Tue Oct 27 18:00:00 +0000 2026"),
      "a repost is dated when it was reposted")
check(byID["400"] == nil, "the repost wrapper is not a post of its own")
check(byID["600"] == nil && byID["602"] == nil, "your own posts and reposts are not news")
check(byID["700"] == nil, "a post older than the keep window is never landed, so a prune is never undone")
check(byID["800"]?.text == "limited replies", "a visibility-wrapped post is unwrapped")
check(byID["900"]?.text == nil && byID["900"]?.imageURLs == ["https://pbs.twimg.com/media/a.jpg"],
      "a picture with no words is a post")
check(byID["901"] == nil, "nothing to show, nothing landed")
check(byID["1000"]?.quoted?.handle == "jo" && byID["1000"]?.quoted?.text == "the quoted words",
      "a quote carries the quoted post")
// ── A post of no words of its own ────────────────────────────────────────
check(byID["900"]?.title == "Photo from @gus", "a picture with no words and no alt is named by whose it is")
check(byID["100"]?.title == "hello https://example.com/a", "a post with words is titled by them")
var quoteOnly = tweet("1100", by: "kim", text: "https://t.co/q",
                      extra: ["entities": ["urls": [["url": "https://t.co/q",
                                                     "expanded_url": "https://x.com/jo/status/1101"]]]])
quoteOnly["quoted_status_result"] = ["result": tweet("1101", by: "jo", text: "the quoted words")]
let q = XFollowingRead.post(quoteOnly, me: me, now: now)
check(q?.text == nil && q?.quoted?.restID == "1101",
      "a quote's address to the post it quotes is dropped from its words")
check(q?.title == "Quoting @jo", "a quote of no words is named by whom it quotes, never by the link")
var withWords = quoteOnly
withWords["legacy"] = (quoteOnly["legacy"] as! [String: Any]).merging(["full_text": "so true https://t.co/q"]) { $1 }
check(XFollowingRead.post(withWords, me: me, now: now)?.text == "so true", "a quote keeps its own words")
// A quoted PICTURE: the card has no words, so no card; the address still goes.
var quotesPicture = tweet("1300", by: "max", text: "https://t.co/p",
                          extra: ["quoted_status_id_str": "1301",
                                  "entities": ["urls": [["url": "https://t.co/p",
                                                         "expanded_url": "https://x.com/ned/status/1301"]]]])
quotesPicture["quoted_status_result"] = ["result": tweet("1301", by: "ned", text: nil,
                                                         media: ["https://pbs.twimg.com/media/c.jpg"])]
let qp = XFollowingRead.post(quotesPicture, me: me, now: now)
check(qp != nil && qp?.text == nil && qp?.quoted == nil && qp?.title == "Quoting @ned",
      "a quoted picture drops its address and is named by whom it quotes")
let quotesGone = tweet("1400", by: "ola", text: "look https://t.co/g",
                       extra: ["quoted_status_id_str": "1401",
                               "entities": ["urls": [["url": "https://t.co/g",
                                                      "expanded_url": "https://twitter.com/pat/status/1401?s=20"]]]])
check(XFollowingRead.post(quotesGone, me: me, now: now)?.text == "look",
      "a quoted post that did not come back still loses its address")
let alt = tweet("1200", by: "lee", text: nil, media: ["https://pbs.twimg.com/media/b.jpg"],
                extra: ["extended_entities": ["media": [["media_url_https": "https://pbs.twimg.com/media/b.jpg",
                                                         "ext_alt_text": "A cat on a keyboard"]]]])
check(XFollowingRead.post(alt, me: me, now: now)?.title == "A cat on a keyboard", "a picture's alt text names it")

check(XFollowingRead.posts(["data": ["viewer": [:] as [String: Any]]], me: me, now: now) == nil,
      "a page that is not the measured shape reads nil, never an empty success")
check(XFollowingRead.posts(page([]), me: me, now: now) == [], "an empty page is an empty list")
check(XFollowingRead.posts(page(entries), me: nil, now: now)?.contains { $0.restID == "600" } == true,
      "with no known account id, nothing is taken for yours")

// ── The prune ────────────────────────────────────────────────────────────
let day: TimeInterval = 86_400
check(!XFollowingRead.prunes(at: now.addingTimeInterval(-2 * day), opened: false, now: now), "two days unopened stays")
check(XFollowingRead.prunes(at: now.addingTimeInterval(-3 * day - 60), opened: false, now: now), "past three days unopened goes")
check(!XFollowingRead.prunes(at: now.addingTimeInterval(-30 * day), opened: true, now: now), "an opened post stays")

// ── The notices it replaces ──────────────────────────────────────────────
check(XFollowingRead.isNewPostNotice("New post notifications for Bob and 9 others"), "the digest is a new-post notice")
check(XFollowingRead.isNewPostNotice("New post from mia"), "a single new-post notice")
check(!XFollowingRead.isNewPostNotice("Ana liked your post"), "a like is not")
check(!XFollowingRead.isNewPostNotice("Ana followed you"), "a follow is not")

// ── X's date ─────────────────────────────────────────────────────────────
check(XFollowingRead.date("Wed Oct 10 20:19:24 +0000 2018") == Date(timeIntervalSince1970: 1_539_202_764),
      "created_at reads in the measured format")
check(XFollowingRead.date("2018-10-10T20:19:24Z") == nil && XFollowingRead.date(nil) == nil, "anything else is no date")

print(failures == 0 ? "x-following-selftest: all checks ✓" : "x-following-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$READ" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ x-following-selftest: compile failed"; exit 1; }
"$TMP/run"
