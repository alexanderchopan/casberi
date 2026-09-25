# Social — the people in your inbox, and what you can do about them

**JOINT SPEC, half A (2026-09-24).** This file is half A — share and act —
and its §0 binds both halves. **Half B is `docs/addresses-spec.md`** — the
record — `Contact` with a `kind`, `ContactIndex`, `PeopleBook`. Neither session edits the other's file;
disagreements go in the seam sections (§5 here, §2.5 there). §1 here is a
pointer and the facts the seam needs. Rulings referenced: §83 (honesty), §239 (social's inbound half),
§434 (map / list / card), §701 (the cookie-session read), §736 (a row that
names a place is a button), §746 (a verb is a row), §756 (the cover draws a
post as a post), §867 (every disc presses).

**Grade: SPEC (2026-09-24).** Nothing below is built yet. Each pass says
what it draws, what it writes, and what it will not do.

---

## 0. The rules

> Social is the people who already show up in your inbox — a sender, a
> reviewer, an attendee, a poster — not a network's graph.

More people will use GitHub, Gmail, Calendar and Messages than Farcaster or
Bluesky (user, 2026-09-24). The person primitive is therefore keyed on what
those seats carry — an email address, a Contacts card, a GitHub login — and a
Farcaster or Bluesky handle is one more alias on that person, not the key.

> A seat reads through whatever door it has; it writes only through a
> sanctioned one.

The cookie-session seats — X (§701, §737), Instagram (§726), TikTok (§731),
Spotify (§703), Duolingo (§776), Acorns and Rocket Money (§780b) — **stay, and
stay read-only** (user, 2026-09-24: "we keep the x door and others but we
want that to be read only not write"). No reply, like, repost, post or DM may
ever leave through a browser-session cookie. Writes go through:

- the system composers (`MFMessageComposeViewController`,
  `MFMailComposeViewController`): the person taps Send, the app never does;
- `tel:` / `facetime:` for a call;
- SMTP with the same app-specific password the IMAP read already holds;
- a provider's own published write API behind a sign-in the person made
  (GitHub's `repo` token, Slack's PKCE OAuth, Bluesky's app password).

> The app never sends on its own. Every act ends in a composer or a confirm.

---

## 1. The person — see `docs/addresses-spec.md`

The design is there. What this half needs from it is one call
(`ContactIndex.contact(for:)`, §5) and the facts below, read off the tree so
the seam points at something real. What a `Thing` names today:

| Seat | Field | Shape |
|---|---|---|
| Mail | `authorHandle` (`MailBridge.swift:166`) | display name when there is one, else `mailbox@host` (`IMAPClient.swift:541–550`); to/cc in `enrichedText` only |
| GitHub | `authorHandle` (`GitHubFeeds.swift:1012`) | the login; on a notification it is the repo OWNER, not the actor (`GitHubRowTag.swift:36–47`) |
| Calendar | `enrichedText` + an `Organizer` fact (`ScheduleIngest.swift:486, 640`) | attendees are a roster string, not a field |
| Social | `authorHandle`, `authorAvatarURL` (`Thing.swift:834–838`) | handle; `SocialRoomSource.author(of:)` |
| Contacts | a `.contact` thing, `facts` (`ContactsIngest.swift:319–365`) | up to 3 phones (`.call`), 3 emails (`.mail`); no lookup helper by email exists |

The stored detector results `detectedTel` / `detectedMailto`
(`Thing.swift:1163, 1171`) are what the dial's Call and Email verbs read
(`Verbs.swift:443–450`). A mail thing whose sender has a display name has a
nil `detectedMailto`, so its Email door is missing today.

Answered by `addresses-spec.md`: a `Contact` (kind: person, organization,
contract, safe, smartAccount, key, publication) carries `identities`
(`Identity.Kind` includes `email`; the lead order is contact, email, GitHub
login, wallet, social), so a mail sender is a person with one identity even
with no card. The `.contact` identity carries the contact's facts, which is
where a phone comes from; an email comes from the `email` identity. Two
traps half B recorded from the table above: a GitHub notification's
`authorHandle` is the repo owner, so it resolves only through the actor or
not at all; and a mail row whose sender set a display name holds no address
anywhere — adding `authorEmail: String?` to `Thing` (additive, but a
CloudKit Production deploy) is half B's decision.

---

## 2. The share card (share-card session)

**What.** One image of a thing, drawn in the app's own hand, that a person
sends out — to Messages, Mail, or the system share sheet. The app's first
outward-facing surface, so it is also the app's face.

**Shape.** Portrait 4:5 (360×450pt, rendered at 3× → 1080×1350), the size
every messaging and social surface previews whole. One frame, no scroll.

**Anatomy, top to bottom.**

1. The seat: `BridgeIcon(name: thing.source, size: 26, circular: true)`, the
   source's name in `label12`, the day in `subhead12` tertiary. A post leads
   with its author instead — face and handle, per §756 — because a post's
   row leads with the person.
2. The picture, if the thing has one (`StoredPixels.cached(for:)` for a
   screenshot or photo; `previewImageURL` when already cached). Art over
   words, never beside (§915). `DS.Radius.widget`, aspect-fill, clipped.
3. The words: title in `heading24` (or `heading40` when short and there is
   no picture — the rung is chosen by fit, never by character count, §766a),
   then `postText` / the lede / `content` in `body17`, capped by the box,
   never a count.
4. The foot, pinned to the bottom: `CasberiMark(size: 20)` and the word
   "Casberi" in `DS.brandInk`. This is the one place the brand hue lands on a
   card — the foot is the app's voice, the words above are the thing's
   (§742).

**Ground.** The person's own theme: `DS.surface` under `DS.textPrimary`. Every
`UIColor`-backed token is RESOLVED against a trait collection before it
reaches `ImageRenderer` (`TileDrop.swift:419–425` is the precedent, and the
reason: an unresolved dynamic colour renders as the light variant on a dark
ground). `dynamicTypeSize` is pinned to `.large` on the rendered tree so a
person's accessibility size does not change what they send.

**What it will not do.** No accent rails, bars or stripes on any edge —
emphasis is ink, never a rule beside the content (the infographic rule,
general since 2026-09-07). No counting in the copy. No balance, no wallet
figure, no address (a wallet move shares its words, not the number — §83's
stale-price rule applied outward). No avatar it has not already cached: a
face with no picture is the handle's first letter in a circle (§753). No
model-written text, ever (§645).

**Files.** `Model/ShareCard.swift` (`ShareCard.Model`, pure, built on main
from a live `Thing`; `ShareCard.render(_:traits:) -> UIImage`),
`Design/ShareCardView.swift` (the drawing), a `Transferable` with a PNG
`DataRepresentation` first and a `ProxyRepresentation` of the thing's URL
second, so a target that takes a link gets the link.

---

## 3. The doors: Text, Email, Call, Share (share-card session)

**Where.** The Share disc on the dial (`ThingStage.swift:166–173`) stops
being a bare `ShareLink` and raises a `DSTray`: the card, drawn at width, then
rows (§746 — a verb is a row):

| Row | Glyph | Opens | Prefilled |
|---|---|---|---|
| Send in Messages | `message` | `MFMessageComposeViewController` | the card as a PNG attachment, the thing's link as the body; the recipient from §5 |
| Send in Mail | `envelope` | `MFMailComposeViewController` | subject = title, the card attached, the link in the body; recipient from §5 |
| Share… | `square.and.arrow.up` | `ShareLink` (`.plain`, per `sharelink-style-audit.py`) | the card, then the link |

**Call** stays a dial disc, because it is one tap and needs no card: it reads
`detectedTel` today and the person's phone from §5 tomorrow. **Email** as a
dial disc (a reply to the sender) is unchanged; the tray's Mail row is a
different act — sending the thing ON, not answering it.

**The words.** "Text" is a noun in four catalogs ("Texto", "テキスト"), so the
row says `Send in Messages`; `Send in Mail`; `Share…`. New String Catalog keys
for all three.

**Fallbacks (§83).** `canSendText()` / `canSendMail()` false — the simulator,
a Mac with no Messages account, an iPad with no SIM — hides that row rather
than drawing a dead one; there is always `Share…`. The composer's own Cancel
and Send end it; the app reads only the result to dismiss.

**Not in scope.** No recipient search of its own (that is §1's). No group
send. No scheduling. Nothing is sent without the composer's own Send.

---

## 4. Acts by seat (share-card session, LATER — not in the first pass)

Each is an official write behind a sign-in the person already made. Listed
so the seam in §5 is designed for them; none is built until ruled.

| Seat | Act | Door | Cost |
|---|---|---|---|
| GitHub | React, Comment, Approve / Request changes | REST, the existing `repo` token (`GitHubDeviceFlow.swift:37`) | none new; Approve needs a confirm |
| Mail | Reply in thread | SMTP, same app-specific password | an SMTP client beside `IMAPClient` |
| Calendar | Accept / Decline; Text everyone | EventKit; the Messages composer | attendees become a field |
| Slack | Reply to a mention | OAuth, add `chat:write` (`SlackBridge.swift:14`) | one scope, re-consent |
| Bluesky | DM | `chat.bsky.convo.*`, app password | a new read + write seat |
| Farcaster | Direct cast | Warpcast API key, per user | a key the person fetches |

**Declined on purpose.** Any write on a cookie-session seat (§0). DMs with
no published API (Instagram, TikTok, X, WhatsApp). A following timeline
(`SocialFollows.swift` doc: it would turn a corpus into a timeline). NFC or
QR follow (parked 2026-09-19).

---

## 5. The seam (edited by agreement)

One call, owned by `addresses-spec.md`, read by §3:

```swift
/// The contact a thing is from or about, resolved through the unified
/// address book. nil when the app holds none for it.
ContactIndex.contact(for thing: Thing) -> Contact?
```

§3 takes a phone and an email from the `Contact`'s `.contact` identity's
facts (the `.call` / `.mail` facts `ContactsIngest.facts(for:)` already
writes) when present, and from `detectedTel` / `detectedMailto` when not.
Until `ContactIndex` lands, §3 ships with the detector fallback alone; the
tray's rows do not change shape when the person arrives, only their prefill.
The planned `ThingStage.swift` hunk on the people side is in `MovedStage`,
not `VerbDial`, so the two hunks do not meet.

**Add to Addresses** (half B §2.6, user 2026-09-24; the room is named Addresses, never People) is a dial VERB
(`Verb.Action.addToPeople`, reading `Open person` once the person exists),
built in `Verbs.swift` by half B. The share tray adds no second door for it:
a "Save sender" row here would be the same act behind a different word.

Paths, so neither session's `git add` takes the other's work:

- §1: `Model/Contacts*`, `Model/AddressBook*`, `Model/Person*`,
  `Screens/PersonRoomScreen.swift`, `Model/SocialRoomSource.swift`, and
  `Shared/Thing.swift` if a field is added.
- §3: `Model/ShareCard.swift`, `Design/ShareCardView.swift`,
  `Screens/ShareTray.swift`, `Screens/MessageCompose.swift`, one hunk in
  `Screens/ThingStage.swift` (`VerbDial`'s Share disc), three keys in
  `Localizable.xcstrings`.

Both commit through a temp index scoped to their own paths (memory:
`shared-index-swallows-your-changes`).

---

## 6. Order of work

1. §2 + §3 with the detector fallback — one sheet, the card, three rows.
   Verified on the simulator for the card and the tray; the composers cannot
   run there (`canSendText()` is false), so their proof is a device.
2. §1 lands; §5's `reach(for:)` wires in as one line per row.
3. Card sources beyond a thing: a week on GitHub, a run, a streak — each a
   `ShareCard.Model` built by its room, same drawing.
4. §4, one seat at a time, each behind a ruling.
