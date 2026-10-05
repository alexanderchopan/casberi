#!/bin/zsh
# Casberi social-people self-test — the Social room's faces, one per PERSON
# across Farcaster and Bluesky (prd §1079):
#
#   Casberi/Casberi/Model/FollowedPeople.swift   (compiled whole)
#
# WHY A HARNESS. Both failures render as an ordinary row of faces. Keyed on a
# bare handle, "alice" on Farcaster and "alice" on Bluesky become one face and a
# pick shows a stranger's posts under her picture; keyed on a display name, two
# people called Alex merge (§632's rule, which `ContactIndex` keeps and this
# must not undo). Only a link in the Addresses index joins two accounts.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PEOPLE="Casberi/Casberi/Model/FollowedPeople.swift"
[[ -f "$PEOPLE" ]] || { echo "✗ $PEOPLE not found"; exit 1; }

# The room reads it: the row, the scope and the rings.
SCOPE="Casberi/Casberi/Screens/FeedScreen+RoomScope.swift"
DERIV="Casberi/Casberi/Screens/FeedScreen+Derivations.swift"
ACTIONS="Casberi/Casberi/Screens/FeedScreen+Actions.swift"
grep -q 'FollowedPeople.group(' "$SCOPE" || { echo "✗ the Social room no longer groups its faces into people"; exit 1; }
grep -q 'ContactIndexSources.contact(forKey:' "$SCOPE" \
  || { echo "✗ the faces no longer join through the Addresses index — a person on two networks is two faces"; exit 1; }
grep -q 'personScopeAllows(thing, people: people)' "$DERIV" \
  || { echo "✗ a person pick no longer narrows the Social room's rows"; exit 1; }
grep -q 'FollowedPeople.index(' "$ACTIONS" \
  || { echo "✗ the faces' rings no longer count posts by person"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$PEOPLE" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
func account(_ source: String, _ key: String, _ title: String, avatar: String? = nil) -> FollowedPeople.Account {
    let prefix = ["Farcaster": "fc:", "Bluesky": "bsky:"][source] ?? ""
    return .init(source: source, key: key, title: title, subtitle: "@\(key)", avatarURL: avatar,
                 identity: prefix + key)
}

let accounts = [
    account("Farcaster", "alice", "Alice"),
    account("Farcaster", "bob", "Alex"),
    account("Bluesky", "alice.bsky.social", "Alice B", avatar: "https://a/alice.png"),
    account("Bluesky", "alice", "alice"),
    account("Bluesky", "alex.bsky.social", "Alex"),
]
// The index joins Alice's Farcaster and Bluesky accounts. Nothing else.
let links = ["fc:alice": "c1", "bsky:alice.bsky.social": "c1"]
let people = FollowedPeople.group(accounts) { links[$0] }

check(people.count == 4, "four people: joined Alice, Bob-as-Alex, Bluesky alice, Bluesky Alex (got \(people.count))")
let alice = people.first { $0.id == "contact:c1" }
check(alice?.members.count == 2, "a linked person is one face over both networks")
check(alice?.title == "Alice", "the face takes its first account's name")
check(alice?.avatarURL == "https://a/alice.png", "a face with no picture borrows the person's other account's")
check(alice?.source == "Bluesky", "the stand-in mark follows the account the picture came from")
check(alice?.subtitle == "Farcaster · Bluesky", "a joined face says the networks it spans")
check(people.first?.id == "contact:c1", "faces keep the order their first account came in")
check(people.contains { $0.id == "Bluesky:alice" },
      "the same handle on another network is a stranger until a link says otherwise")
check(people.filter { $0.title == "Alex" }.count == 2, "two people with one display name stay two")

let index = FollowedPeople.index(people)
check(index[.init(source: "Farcaster", handle: "alice")] == "contact:c1", "a Farcaster post by alice is Alice's")
check(index[.init(source: "Bluesky", handle: "alice")] == "Bluesky:alice", "a Bluesky post by alice is the Bluesky alice's")

let picked = FollowedPeople.members(of: "contact:c1", in: people)
check(picked == [.init(source: "Farcaster", handle: "alice"), .init(source: "Bluesky", handle: "alice.bsky.social")],
      "a pick keeps the person's accounts on every network, and only theirs")
check(FollowedPeople.members(of: "gone", in: people) == nil, "a pick naming nobody here says so")

// Your own accounts are one face, whatever the index says.
var own = accounts
own.append(.init(source: "Farcaster", key: "me", title: "You", subtitle: "@me", avatarURL: nil,
                 identity: "fc:me", mine: true))
own.append(.init(source: "Bluesky", key: "me.bsky.social", title: "You", subtitle: "@me", avatarURL: nil,
                 identity: "bsky:me.bsky.social", mine: true))
let withYou = FollowedPeople.group(own) { links[$0] }
check(withYou.filter { $0.title == "You" }.count == 1, "your own accounts on two networks are one face")
check(withYou.first { $0.id == FollowedPeople.yours }?.members.count == 2, "your face keeps both your accounts")

let twice = FollowedPeople.group([accounts[0], accounts[0]]) { _ in nil }
check(twice.count == 1 && twice[0].members.count == 1, "an account listed twice is one member")

if failures > 0 { print("✗ followed people: \(failures) failing"); exit(1) }
print("✓ followed people self-test passed")
SWIFT

swiftc -O -o "$TMP/people" "$TMP/FollowedPeople.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/people" ]] || { echo "✗ followed people harness did not compile"; exit 1; }
"$TMP/people"
