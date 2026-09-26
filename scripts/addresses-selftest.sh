#!/bin/zsh
# Addresses self-test (prd §916, 2026-09-24) — the contact index and the link
# ledger, the pure half of the unified contacts list:
#
#   Casberi/Casberi/Model/ContactIndex.swift   compiled WHOLE and unmodified
#   Casberi/Casberi/Model/ContactLinks.swift   compiled WHOLE and unmodified
#
# WHY A HARNESS. Every wrong answer here draws a perfectly normal row:
#
#   • TWO PEOPLE WITH ONE NAME BECOME ONE (§632). A name-only merge compiles,
#     runs, and files a stranger's wallet under your friend.
#   • A SUGGESTION MERGES. "Looks like the same person" is a question, and a
#     guess that merges is a claim nobody made.
#   • A "NO" THAT DOES NOT STICK, or one that blocks a later FACT.
#   • A MIXED-CASE ADDRESS THAT MISSES ITS OWN LOWERCASED KEY (§857's trap).
#   • A CONTACT EDGE IN THE MIRROR PAYLOAD. `CNContact.identifier` is
#     device-local, and the mirror is addresses, not a phone book (§169).
#   • A LEAD THAT MOVES when a later identity joins, so the id changes and
#     a row jumps.
#   • A TYPED NAME LOSING TO A SEAT'S DISPLAY NAME (§169: naming is free).
#   • A GITHUB NOTIFICATION FILED UNDER THE REPO OWNER (`GitHubRowTag`).
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

INDEX="Casberi/Casberi/Model/ContactIndex.swift"
LINKS="Casberi/Casberi/Model/ContactLinks.swift"
SUGGEST="Casberi/Casberi/Model/ContactSuggest.swift"
for f in "$INDEX" "$LINKS" "$SUGGEST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/addresses-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
let t0 = Date(timeIntervalSince1970: 1_000_000)
let t1 = Date(timeIntervalSince1970: 2_000_000)
let t2 = Date(timeIntervalSince1970: 3_000_000)

// ── Keys ────────────────────────────────────────────────────────────────
check(Identity.key(.wallet, "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045") == "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
      "a wallet key is lowercased")
check(Identity.key(.farcaster, "@Jesse") == "fc:jesse", "a Farcaster key drops the @ and folds case")
check(Identity.key(.farcaster, "fc:jesse") == "fc:jesse", "a key already prefixed is not double-prefixed")
check(Identity.key(.github, "Torvalds") == "gh:torvalds", "a GitHub login folds case")
check(Identity.key(.email, "Jesse@Example.com") == "mail:jesse@example.com", "an email folds case")
check(Identity.key(.contact, "contact:ABC-123") == "contact:abc-123", "a contact key keeps its prefix once")
check(Identity.parse(key: "fc:jesse")?.kind == .farcaster, "a key parses back to its kind")
check(Identity.parse(key: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045")?.kind == .wallet, "a bare address parses as a wallet")
check(Identity.parse(key: "jesse.base.eth")?.kind == .basename, "a basename parses by shape")
check(Identity.parse(key: "nonsense") == nil || Identity.parse(key: "nonsense")?.kind == .worldApp,
      "a bare word is at most a World App name")
check(Identity.make(.wallet, "0xd8da6bf26964af9d7eed9e03e53415d37aa96045").label == "…6045", "a wallet's label is its tail")
check(Identity.make(.farcaster, "jesse").label == "@jesse", "a handle's label wears the @")
check(Identity.Kind.classify(primaryName: "@vitalik") == .farcaster, "classify: @ is Farcaster")
check(Identity.Kind.classify(primaryName: "jesse.base.eth") == .basename, "classify: .base.eth")
check(Identity.Kind.classify(primaryName: "x.linea.eth") == .linea, "classify: .linea.eth")
check(Identity.Kind.classify(primaryName: "vitalik.lens") == .lens, "classify: .lens")
check(Identity.Kind.classify(primaryName: "vitalik.eth") == .ens && Identity.Kind.classify(primaryName: "vitalik.wei") == .ens,
      "classify: any other dotted name files as ENS")
check(Identity.Kind.classify(primaryName: "laary") == .worldApp, "classify: a bare word is a World App name")
check(Identity.Kind.classify(primaryName: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045") == nil, "classify: an address is not a name")
check(Identity.Kind.contact.precedence < Identity.Kind.email.precedence
      && Identity.Kind.email.precedence < Identity.Kind.github.precedence
      && Identity.Kind.github.precedence < Identity.Kind.wallet.precedence
      && Identity.Kind.wallet.precedence < Identity.Kind.farcaster.precedence,
      "lead precedence: contact, email, GitHub, wallet, then social")

// ── The ledger ──────────────────────────────────────────────────────────
let A = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
let B = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
let J = "fc:jesse"
let sugg = ContactLink(A, J, tier: .suggested, source: "corpus.email", at: t0)
check(sugg.a == A && sugg.b == J && ContactLink(J, A, tier: .suggested, source: "x").pairKey == sugg.pairKey,
      "a pair is stored sorted, one key per pair")
check(!sugg.merges && sugg.suggests, "a suggestion suggests and does not merge")
check(ContactLink(A, J, tier: .verified, source: "you").merges, "a verified edge merges")
check(ContactLink(A, "contact:1", tier: .stated, source: "contact.card").merges, "a stated edge merges")
check(!ContactLink(A, "contact:1", tier: .stated, source: "contact.card").isPublic, "a contact edge is private")
check(ContactLink(A, J, tier: .verified, source: "you").isPublic, "an address–handle edge is public")

var ledger = LinkLedger().recording(sugg)
check(ledger.link(A, J)?.tier == .suggested, "recorded")
ledger = ledger.declining(J, A)
check(ledger.link(A, J)?.declined == true && ledger.link(A, J)?.suggests == false, "declined sticks and stops suggesting")
ledger = ledger.recording(ContactLink(A, J, tier: .suggested, source: "corpus.email", at: t1))
check(ledger.link(A, J)?.declined == true, "a re-suggestion does not clear a No")
ledger = ledger.recording(ContactLink(A, J, tier: .verified, source: "farcaster.verifications", at: t2))
check(ledger.link(A, J)?.tier == .verified && ledger.link(A, J)?.declined == false,
      "a later VERIFIED edge replaces a declined suggestion — a fact beats an opinion")
ledger = ledger.recording(ContactLink(A, J, tier: .suggested, source: "x", at: t2))
check(ledger.link(A, J)?.tier == .verified, "a verified edge never downgrades")
let confirmed = LinkLedger().recording(sugg).confirming(A, J)
check(confirmed.link(A, J)?.tier == .verified && confirmed.link(A, J)?.source == "you", "Yes, same person is a verified edge you made")
let declinedFresh = LinkLedger().declining(A, B)
check(declinedFresh.link(A, B)?.declined == true, "a No on a pair nobody recorded is remembered too")
let mixed = LinkLedger()
    .recording(ContactLink(A, J, tier: .verified, source: "you"))
    .recording(ContactLink(A, "contact:abc", tier: .stated, source: "contact.card"))
check(mixed.mirrorable.count == 1 && mixed.mirrorable.values.first?.b == J,
      "the mirror payload carries the public edge and never the contact edge")
let merged = LinkLedger().merging(remote: [sugg.pairKey: ContactLink(A, J, tier: .suggested, source: "x", at: t0, declined: true)])
check(merged.link(A, J)?.declined == true, "a remote No lands as a No")

// ── Build: no name merge ────────────────────────────────────────────────
let alexWallet = ContactIndex.Seed(Identity.make(.wallet, A), name: "Alex", typed: true, since: t0)
let alexFC = ContactIndex.Seed(Identity.make(.farcaster, "alexx"), name: "Alex")
var contacts = ContactIndex.build(seeds: [alexWallet, alexFC], links: [])
check(contacts.count == 2, "two seeds called Alex with no edge are two contacts")

// ── Build: verified merges, suggested does not ──────────────────────────
contacts = ContactIndex.build(seeds: [alexWallet, alexFC], links: [ContactLink(A, "fc:alexx", tier: .suggested, source: "x")])
check(contacts.count == 2, "a suggested edge does not merge")
contacts = ContactIndex.build(seeds: [alexWallet, alexFC], links: [ContactLink(A, "fc:alexx", tier: .verified, source: "farcaster.verifications")])
check(contacts.count == 1, "a verified edge merges")
let alex = contacts[0]
check(alex.id == A && alex.lead.kind == .wallet, "the lead is the wallet (precedence over social)")
check(alex.name == "Alex", "the typed name")
check(alex.identities.count == 2 && alex.identities[1].tier == .verified && alex.identities[1].source == "farcaster.verifications",
      "the joined identity carries the edge's tier and source")

// ── Build: declined cut, verified still merges ──────────────────────────
var l = LinkLedger().recording(ContactLink(A, "fc:alexx", tier: .suggested, source: "x")).declining(A, "fc:alexx")
check(ContactIndex.build(seeds: [alexWallet, alexFC], links: l.all).count == 2, "a declined pair stays apart")
l = l.recording(ContactLink(A, "fc:alexx", tier: .verified, source: "farcaster.verifications", at: t2))
check(ContactIndex.build(seeds: [alexWallet, alexFC], links: l.all).count == 1, "…until a verified edge arrives")

// ── Build: a link end that is no seed becomes an identity ───────────────
contacts = ContactIndex.build(seeds: [alexWallet], links: [ContactLink(A, "jesse.base.eth", tier: .verified, source: "web3.bio")])
check(contacts.count == 1 && contacts[0].identities.map(\.kind) == [.wallet, .basename],
      "a verified name with no seed joins the wallet as a basename identity")
contacts = ContactIndex.build(seeds: [alexWallet], links: [ContactLink(A, "garbage key", tier: .verified, source: "x")])
check(contacts.count == 1 && contacts[0].identities.count == 1 || contacts[0].identities.count == 2,
      "an unparseable link end never crashes the build")

// ── Build: lead precedence and id stability ─────────────────────────────
let card = ContactIndex.Seed(Identity.make(.contact, "contact:c1"), name: "Alex Chopan", typed: true, since: t2)
let mail = ContactIndex.Seed(Identity.make(.email, "alex@example.com"), name: "alex", since: t1)
let links = [ContactLink(A, "mail:alex@example.com", tier: .verified, source: "you"),
             ContactLink("contact:c1", "mail:alex@example.com", tier: .stated, source: "contact.card")]
let before = ContactIndex.build(seeds: [alexWallet, mail], links: Array(links.prefix(1)))
check(before.count == 1 && before[0].id == "mail:alex@example.com", "email leads a wallet")
let after = ContactIndex.build(seeds: [alexWallet, mail, card], links: links)
check(after.count == 1 && after[0].id == "contact:c1", "a contact card, once linked, leads")
check(after[0].identities.map(\.kind) == [.contact, .email, .wallet], "identities are ordered by precedence")
check(after[0].name == "Alex Chopan", "the contact card's name (typed) wins")
// A typed name on a LOWER-precedence identity still beats a display name
// on the lead: the email leads, the wallet's typed name names the contact.
let mailDisplay = ContactIndex.Seed(Identity.make(.email, "ac@example.com"), name: "ac", since: t0)
let walletTyped = ContactIndex.Seed(Identity.make(.wallet, B), name: "Alex Chopan", typed: true, since: t1)
let typedWins = ContactIndex.build(seeds: [mailDisplay, walletTyped],
                                   links: [ContactLink(B, "mail:ac@example.com", tier: .verified, source: "you")])
check(typedWins.count == 1 && typedWins[0].id == "mail:ac@example.com" && typedWins[0].name == "Alex Chopan",
      "a typed name beats the lead's display name")
// Two wallets, both typed: the OLDER entry leads, whatever its key.
let w1 = ContactIndex.Seed(Identity.make(.wallet, B), name: "Cold", typed: true, since: t0)
let w2 = ContactIndex.Seed(Identity.make(.wallet, A), name: "Hot", typed: true, since: t1)
let two = ContactIndex.build(seeds: [w1, w2], links: [ContactLink(A, B, tier: .verified, source: "you")])
check(two.count == 1 && two[0].id == B, "the oldest entry leads at equal precedence")

// ── Name precedence ─────────────────────────────────────────────────────
let fcOnly = ContactIndex.Seed(Identity.make(.farcaster, "jesse"), name: "Jesse Pollak")
let jw = ContactIndex.Seed(Identity.make(.wallet, B), name: nil, typed: false)
var jc = ContactIndex.build(seeds: [jw, fcOnly], links: [ContactLink(B, "fc:jesse", tier: .verified, source: "farcaster.verifications"),
                                                         ContactLink(B, "jesse.base.eth", tier: .verified, source: "web3.bio")])
check(jc.count == 1 && jc[0].name == "jesse.base.eth", "with no typed name, a verified name-service name beats a display name")
jc = ContactIndex.build(seeds: [jw, fcOnly], links: [ContactLink(B, "fc:jesse", tier: .verified, source: "farcaster.verifications")])
check(jc[0].name == "Jesse Pollak", "then the seat's display name")
jc = ContactIndex.build(seeds: [ContactIndex.Seed(Identity.make(.farcaster, "jesse"))], links: [])
check(jc[0].name == "@jesse", "then the lead's own label")

// ── Kind ────────────────────────────────────────────────────────────────
let safeSeed = ContactIndex.Seed(Identity.make(.wallet, A), name: "Treasury", typed: true, kind: .safe)
check(ContactIndex.build(seeds: [safeSeed, alexFC], links: [ContactLink(A, "fc:alexx", tier: .verified, source: "you")])[0].kind == .safe,
      "a Safe stays a Safe when a social seat joins")
let pub = ContactIndex.Seed(Identity.make(.feed, "https://x.substack.com/feed"), name: "X", kind: .publication)
check(ContactIndex.build(seeds: [pub], links: [])[0].kind == .publication, "a feed alone is a publication")
check(ContactIndex.build(seeds: [pub], links: [])[0].lead.kind == .feed, "keyed on its feed")

// ── Determinism and order ───────────────────────────────────────────────
let manyA = ContactIndex.build(seeds: [alexFC, alexWallet, card, mail, pub], links: links)
let manyB = ContactIndex.build(seeds: [pub, mail, card, alexWallet, alexFC], links: links.reversed())
check(manyA == manyB, "the same inputs in another order build the same list")
check(manyA.first?.lead.kind == .contact && manyA.last?.lead.kind == .feed, "ordered by lead precedence")

// ── keys(for:) — the seam's pure half ───────────────────────────────────
func keys(source: String, kind: String = "link", ref: String? = nil, handle: String? = nil,
          wallet: String? = nil, counterparty: String? = nil, email: String? = nil, notif: Bool = false) -> [String] {
    ContactIndex.keys(source: source, kind: kind, sourceRef: ref, authorHandle: handle,
                      walletAddress: wallet, counterpartyAddress: counterparty,
                      authorEmail: email, isNotification: notif)
}
check(keys(source: "Wallet", counterparty: A.uppercased().replacingOccurrences(of: "0X", with: "0x")) == [A],
      "a transfer resolves its counterparty, case folded")
check(keys(source: "Farcaster", handle: "jesse") == ["fc:jesse"], "a cast resolves its author")
check(keys(source: "GitHub", handle: "torvalds") == ["gh:torvalds"], "a GitHub event resolves its actor")
check(keys(source: "GitHub", handle: "tokio-rs", notif: true) == [], "a GitHub NOTIFICATION resolves nobody — its handle is the repo owner")
check(keys(source: "Gmail", handle: "jesse@example.com") == ["mail:jesse@example.com"], "a mail row resolves its sender address")
check(keys(source: "Gmail", handle: "Jesse Pollak") == [], "a mail row with only a display name resolves nobody")
check(keys(source: "Gmail", handle: "Jesse Pollak", email: "jesse@example.com") == ["mail:jesse@example.com"],
      "…unless authorEmail carries the address")
check(keys(source: "Contacts", kind: "contact", ref: "contact:ABC") == ["contact:abc"], "a contact thing resolves itself")
check(keys(source: "Wallet", wallet: A, counterparty: B) == [B, A], "the counterparty is tried before your own wallet")

// ── Suggestions: a look-alike is a question, never a merge ──────────────
let cardJ = ContactSuggest.Card(key: "contact:j1", name: "Jesse Pollak",
                                lines: ["Farcaster: jesse", "Twitter: jessepollak"], emails: ["jesse@example.com"])
let fcJ = ContactIndex.Seed(Identity.make(.farcaster, "jesse"), name: "Jesse Pollak")
let bskyJ = ContactIndex.Seed(Identity.make(.bluesky, "jesse.bsky.social"), name: "Jesse Pollak")
let ghJ = ContactIndex.Seed(Identity.make(.github, "jesse"), name: "jesse")
let statedLinks = ContactSuggest.stated(cards: [cardJ], seeds: [fcJ, bskyJ, ghJ])
let handleStated = statedLinks.filter { !$0.a.hasPrefix("mail:") && !$0.b.hasPrefix("mail:") }
check(handleStated.count == 1 && handleStated[0].tier == .stated && handleStated.contains { $0.b == "fc:jesse" || $0.a == "fc:jesse" },
      "a card line naming a handle you follow is a STATED edge to that handle")
// The card's own emails (2026-09-25): stated, so a mail from that address is
// from this person — and it needs no roster, the card said it.
let mailStated = statedLinks.filter { $0.a.hasPrefix("mail:") || $0.b.hasPrefix("mail:") }
check(mailStated.count == 1 && mailStated[0].tier == .stated && mailStated[0].pairKey.contains("mail:jesse@example.com"),
      "a card's email is a STATED edge from the card")
let withMail = ContactIndex.build(seeds: [ContactIndex.Seed(Identity.make(.contact, "contact:j1"), name: "Jesse Pollak", typed: true)],
                                  links: mailStated)
check(withMail.count == 1 && withMail[0].identities.contains { $0.kind == .email && $0.tier == .stated },
      "the card's email joins the card as an identity")

// ── Activity (2026-09-25): the row's line and Recent ───────────────────
let actRows: [ContactIndex.ActivityRow] = [
    .init(keys: [A], title: "old transfer", at: t0, acted: true),
    .init(keys: [A], title: "newest post", at: t2, acted: false),
    .init(keys: [A], title: "middle transfer", at: t1, acted: true),
    .init(keys: ["fc:alexx"], title: "a cast", at: t1, acted: false),
]
let act = ContactIndex.activity(rows: actRows)
check(act[A]?.lastThing == "newest post" && act[A]?.lastAt == t2, "the newest thing wins the line regardless of order")
check(act[A]?.actedAt == t1, "only a thing WITH you moves the acted stamp, and the newest of those wins")
check(act["fc:alexx"]?.actedAt == nil, "a thing merely from them never counts as dealt with")
let acted = ContactIndex.build(seeds: [alexWallet, alexFC],
                               links: [ContactLink(A, "fc:alexx", tier: .verified, source: "farcaster.verifications")],
                               activity: act)
check(acted.count == 1 && acted[0].lastThing == "newest post" && acted[0].lastActedAt == t1,
      "a contact folds every identity's activity: the line from the newest, Recent from the newest dealing")
let quiet = ContactIndex.build(seeds: [alexWallet, alexFC], links: [])
check(quiet.allSatisfy { $0.lastThing == nil && $0.lastActedAt == nil }, "no activity, no line, no Recent")
let kw = ContactIndex.build(seeds: [ContactIndex.Seed(Identity.make(.contact, "contact:k1"), name: "Ana", typed: true, keywords: ["Stripe", "", "Designer"])], links: [])
check(kw[0].keywords == ["Stripe", "Designer"], "keywords ride the contact, blanks dropped")
check(ContactSuggest.identity(fromCardLine: "Twitter: x") == nil, "a service with no roster yields nothing")
check(ContactSuggest.identity(fromCardLine: "GitHub: Torvalds")?.key == "gh:torvalds", "a GitHub line folds case")
let sugg2 = ContactSuggest.suggested(cards: [cardJ], seeds: [fcJ, bskyJ, ghJ])
check(sugg2.allSatisfy { $0.tier == .suggested }, "every look-alike is SUGGESTED, never verified")
check(sugg2.contains { $0.pairKey == ContactLink.pairKey("contact:j1", "fc:jesse") }
      && sugg2.contains { $0.pairKey == ContactLink.pairKey("contact:j1", "bsky:jesse.bsky.social") },
      "a card's full name matching a seat's display name is suggested")
check(sugg2.contains { $0.pairKey == ContactLink.pairKey("fc:jesse", "bsky:jesse.bsky.social") },
      "two seats sharing a display name are suggested to each other")
check(sugg2.contains { $0.pairKey == ContactLink.pairKey("contact:j1", "gh:jesse") && $0.source == "corpus.email" },
      "a card email's mailbox matching a watched login is suggested")
let builtS = ContactIndex.build(seeds: [fcJ, bskyJ, ghJ, ContactIndex.Seed(Identity.make(.contact, "contact:j1"), name: "Jesse Pollak", typed: true)],
                                links: statedLinks + sugg2)
check(builtS.count == 3, "stated merges the handle into the card; suggestions merge nothing")
var sl = LinkLedger()
for l in sugg2 { sl = sl.recording(l) }
let firstPick = ContactSuggest.next(in: sl, known: { _ in true })
check(firstPick != nil && firstPick!.suggests, "the list is offered one live suggestion")
sl = sl.declining(firstPick!.a, firstPick!.b)
check(ContactSuggest.next(in: sl, known: { _ in true })?.pairKey != firstPick!.pairKey, "a declined one is never offered again")
check(ContactSuggest.next(in: sl, known: { _ in false }) == nil, "a suggestion whose ends are not in the index is not offered")
check(ContactSuggest.suggested(cards: [], seeds: [ContactIndex.Seed(Identity.make(.farcaster, "a"), name: "Al"),
                                                  ContactIndex.Seed(Identity.make(.bluesky, "b"), name: "Al")]).isEmpty,
      "a two-letter name is too short to suggest on")

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("✓ addresses self-test: every assertion held")
SWIFT

echo "addresses self-test — compiling $INDEX and $LINKS whole"
if ! swiftc -Onone -o "$TMP/run" "$INDEX" "$LINKS" "$SUGGEST" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ compile failed:"; sed 's/^/  /' "$TMP/build.log" | head -30; exit 1
fi
"$TMP/run" || exit 1

# --- the mutation pass ------------------------------------------------------
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  local -a others=()
  for f in "$INDEX" "$LINKS" "$SUGGEST"; do [[ "$f" == "$file" ]] || others+=("$f"); done
  local target="$TMP/mut.swift"
  cp "$file" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if cmp -s "$file" "$target"; then
    echo "  ✗ $name — the mutant is byte-identical to the source"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$target" "${others[@]}" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations — each is an index that looks completely normal:"
mutate "a suggestion merges" "$LINKS" \
  'var merges: Bool { tier != .suggested }' \
  'var merges: Bool { true }'
mutate "a No does not stick against a re-suggestion" "$LINKS" \
  '        case (.suggested, .suggested) where standing.declined:
            return self' \
  '        case (.suggested, .suggested) where standing.declined:
            next.links[key] = incoming'
mutate "a verified edge no longer beats a declined suggestion" "$LINKS" \
  '        case (_, .verified), (.suggested, .stated):
            next.links[key] = incoming' \
  '        case (_, .verified), (.suggested, .stated):
            if standing.declined { return self }; next.links[key] = incoming'
mutate "a verified edge downgrades" "$LINKS" \
  '        case (.verified, _):
            return self' \
  '        case (.verified, _):
            next.links[key] = incoming'
mutate "the mirror carries a contact edge" "$LINKS" \
  'links.filter { $0.value.isPublic }' \
  'links'
mutate "keys stop folding case" "$INDEX" \
  'return kind.prefix + body.lowercased()' \
  'return kind.prefix + body'
mutate "a display name becomes a merge key" "$INDEX" \
  '        for link in links where link.merges {' \
  '        var links = links
        var byName: [String: String] = [:]
        for s in seeds { if let n = s.name { if let o = byName[n] { links.append(ContactLink(o, s.identity.key, tier: .verified, source: "name")) } else { byName[n] = s.identity.key } } }
        for link in links where link.merges {'
mutate "the lead ignores precedence" "$INDEX" \
  '                if l.kind.precedence != r.kind.precedence { return l.kind.precedence < r.kind.precedence }
                let ls' \
  '                let ls'
mutate "the lead ignores age" "$INDEX" \
  '                if ls != rs { return ls < rs }' \
  '                if ls != rs { return ls > rs }'
mutate "a display name beats a typed one" "$INDEX" \
  '        if let typed = seeds.first(where: { $0.typed && !($0.name ?? "").isEmpty })?.name { return typed }' \
  ''
mutate "a Safe becomes a person when a social seat joins" "$INDEX" \
  '        for k in [Contact.Kind.safe, .smartAccount, .contract, .key, .organization] where kinds.contains(k) {' \
  '        for k in [Contact.Kind.safe, .smartAccount, .contract, .key, .organization] where kinds.allSatisfy({ $0 == k }) {'
mutate "a GitHub notification resolves to the repo owner" "$INDEX" \
  '            case "GitHub" where !isNotification: out.append(Identity.key(.github, h))' \
  '            case "GitHub": out.append(Identity.key(.github, h))'
mutate "a mail display name resolves as an email" "$INDEX" \
  '                if h.contains("@") { out.append(Identity.key(.email, h)) }' \
  '                out.append(Identity.key(.email, h))'
mutate "a name match becomes a verified edge" "$SUGGEST" \
  '            out.append(ContactLink(a, b, tier: .suggested, source: source, at: at))' \
  '            out.append(ContactLink(a, b, tier: .verified, source: source, at: at))'
mutate "a card line for a service with no roster becomes an edge" "$SUGGEST" \
  '        default:                      return nil' \
  '        default:                      return Identity.make(.farcaster, handle)'
mutate "a declined suggestion is offered again" "$SUGGEST" \
  '            .filter { $0.suggests && known($0.a) && known($0.b) }' \
  '            .filter { $0.tier == .suggested && known($0.a) && known($0.b) }'
mutate "an older thing overwrites the line" "$INDEX" \
  '                if (a.lastAt ?? .distantPast) < row.at {' \
  '                if true {'
mutate "a thing merely from them counts as dealt with" "$INDEX" \
  '                if row.acted, (a.actedAt ?? .distantPast) < row.at { a.actedAt = row.at }' \
  '                if (a.actedAt ?? .distantPast) < row.at { a.actedAt = row.at }'
mutate "a card's email stops joining the card" "$SUGGEST" \
  '            for email in card.emails where email.contains("@") {' \
  '            for email in card.emails where false {'
mutate "the joined identity forgets how it joined" "$INDEX" \
  '                    if let t = tiers[id.key] { id.tier = t.0; id.source = t.1 }' \
  ''

echo ""
echo "✓ addresses self-test passed"
