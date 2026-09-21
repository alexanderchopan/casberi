# Granola — the four doors, measured on paper

> **NOTHING HERE IS BUILT, AND NOTHING HERE WAS MEASURED AGAINST GRANOLA.**
> Written 2026-09-21 in a Linux container with no Xcode, no simulator and no egress to
> `*.granola.ai` (every host answered `CONNECT tunnel failed, 403` through the proxy).
> Every fact below is read off Granola's published docs, its own MCP listing and two
> reverse-engineering write-ups — none of it off the wire. Anything marked **UNMEASURED**
> has not been run by anyone here. A session with a Mac closes that in an afternoon; §6
> is the list of what to curl first.
> No prd ruling has been written. When one is, the next free number is **§865**.

Granola is an AI notepad for meetings: it records the room from the machine's own audio
(no bot joins the call), keeps the handwritten notes you typed, and writes a summary and
a transcript afterwards. Desktop app plus iOS/Android; the web side is a viewer.

---

## 1. What a seat would hold

A meeting is a thing the app already has a shape for: it happens at a time, it names
people, and it leaves words. One note → one `.note` row dated at the **meeting**, not at
the sync; the attendees are its cast (§772's `ThingCast` shelf, which the lead already
draws); folders are the room's scopes (§815 kind tiles, `All · <folder> · …`, and fewer
than two folders draws no tiles).

The seat's honest promise is one line: **the summary of every meeting you sat in.** Not
the audio — Granola serves none — and not, on a free plan, the transcript.

---

## 2. Door A — the official public API (the Wise/Splits pattern)

Shipped by Granola in February 2026 and the only door with a contract behind it.

| | |
|---|---|
| base | `https://public-api.granola.ai/v1` |
| auth | `Authorization: Bearer grn_…`, a key the person makes in Granola's own Settings → Connectors → API keys |
| reads | `GET /notes` (`created_after`, cursor pagination) · `GET /notes/{id}` · `GET /folders` |
| writes | none published |
| limits | 25 burst, 5 requests/second sustained |
| events | no webhooks — polling is the stated pattern |
| **gate** | **Business or Enterprise plan.** On Enterprise an admin must enable key scopes for members. |

Two disclosures the seat must carry, because they make an empty read look like a broken
one (§83): the API returns **only notes that already have an AI summary and a transcript**
— anything still processing or never summarised is absent — and there are **no webhooks**,
so the freshest a row can be is the last sweep.

This is exactly the Wise (§778) and Splits (§820) shape: a personal read-only key, saved
in `TokenVault`, one host in `NetworkReach`, one `AccountPage`. It is the cheapest seat
of the four **if the plan gate is open**, and worth nothing if it is not — a seat whose
key nobody on this phone can mint is a dead control one layer down (§723).

**Measure the gate before building.** Docs say Business/Enterprise; docs have been wrong
about plan gates before. The one-minute test is in §6.

---

## 3. Door B — the official MCP server (open to individuals, and expensive here)

`https://mcp.granola.ai/mcp`, Streamable HTTP, **browser OAuth 2.0 with Dynamic Client
Registration** — no key to mint, so **no plan gate on connecting**. Granola's own listing
says a **Basic (free)** account can query the **last 30 days** of notes, and that raw
transcripts are paid. Tools: search notes, fetch a meeting with its notes and attendees,
fetch a transcript.

This is the only door a person on a free plan can open, and the app cannot walk through
it today. `Model/MCPServer.swift` + `MCPTools.swift` make Casberi an MCP **server** — the
door external agents come in by (§34). There is no MCP **client**: no Streamable HTTP
transport, no OAuth with dynamic client registration, no token refresh. That is a
subsystem, not a seat, and it would be the app's first.

Build it only if Door A's gate is shut and the seat is still wanted. It pays for itself
twice if it does get built — every other MCP-published service becomes a seat afterwards.

---

## 4. Door C — the desktop app's token — REFUSED

The pre-API path, still written up in archived repos: the Mac app caches a WorkOS refresh
token at `~/Library/Application Support/Granola/supabase.json`, which is exchanged for an
hour-long Bearer and spent on `POST https://api.granola.ai/v2/get-documents`.

It cannot be reached from this app. On iPhone there is no such file; under Mac Catalyst
the app is sandboxed out of another app's container. The one variant that could work —
signing in to WorkOS inside a `WKWebView` and lifting the token — is not §701's cookie
pattern (the credential is a Bearer held in the page, not a cookie the shared store hands
to `URLSession`), it is unmeasured, and the repo it is documented in was archived in
February 2026 with the note that the official API had shipped. Refused.

---

## 5. Door D — what already works, with no seat at all

A Granola share link is **public by default** and needs no account at the other end:
`notes.granola.ai/…`. Saved into Casberi from the share sheet it files under **Bookmarks**
(`FeedScreen` stamps every shared `.link` that way), and `FeedArticleText.sources` is
`["RSS", "Substack", "Bookmarks", "Raindrop"]` — so the reading path already fetches such
a page and draws its words (§645, §709). **UNMEASURED:** whether `notes.granola.ai`
server-renders the note or is a JS app that hands the extractor an empty title. One curl
answers it (§6).

Two more paths need nothing either: Granola's emailed summaries land through the mail
seats, and a Granola → Obsidian/Notion sync lands through the vault (§320) or the
connected-folder seat.

If the answer to "can we do anything with Granola" has to be free today, **it is D** — and
if the curl says the page is server-rendered, D is already shipped and nobody has to be
told anything but "share the note to Casberi".

---

## 6. Measure first — the four curls, in order

1. **Is the page readable?** `scripts/granola-readable-probe.py https://notes.granola.ai/<a note you shared>`
   — it walks the page the way `ReadableParse` does (same content-region markers, same
   `<p>`/`<h2>`/`<h3>` pass, same 24-character floor, prose test, 200-paragraph cap and
   8,000-character bound), prints what the sheet would draw, and says **DRAWS**,
   **EMPTY** (a JS shell — Door D is shut) or **UNREAD** (the host could not be reached,
   which is not an answer about the page). `--self-test` proves it still catches both.
   A server-rendered note makes Door D free and true today.
2. **Is the key gate real for this account?** Open Granola → Settings → Connectors → API
   keys. Either the key mints or the screen names the plan. This is the only fact that
   decides A vs B, and it takes a minute.
3. **If a key mints:** `curl -H "Authorization: Bearer grn_…" https://public-api.granola.ai/v1/notes?limit=2`
   — record the body shape verbatim (field names only, never a value, per the dev-keys
   rule) and which fields carry the meeting time, the attendees, the folder and the summary.
4. **If no key mints:** `claude mcp add --transport http granola https://mcp.granola.ai/mcp`
   on the Mac, then read what the tools return for a free account. That measures Door B's
   30-day window before a line of Swift is written.

---

## 7. Registration points, when a door is chosen

The seat is not done when it fetches. The full list, from how Duolingo (§776) and Splits
(§820) were wired:

- `Model/BridgeCatalog.swift` — one `Offer`. Group **Notes** (it is a notebook, not a
  calendar); tagline states the subject, not the mechanism.
- `Model/BridgeRouting.swift` — the row that opens the account page.
- `Screens/GranolaScreen.swift` — one `AccountPage` (§639), rows not slabs (§640),
  `BridgeSetupCard` for the trip to Granola's own settings (§640b), one `DSFootnote` at
  most (§748), and the plan gate said **before** the field, not after a failed save.
- `Model/NetworkReach.swift` — `public-api.granola.ai` (Door A) or `mcp.granola.ai`
  (Door B). `network-reach-audit.sh` is a ship gate.
- `Model/TokenVault.swift` — device-only storage; `keychain-audit.py` checks it.
- The room: a head only if it has a real figure (§751) — meetings per week is one;
  otherwise the room leads with its newest note (§749) and draws folder tiles (§815).
- Notifications: nothing stands alone here (§770) — a digest at most, if anything.
- Website: marquee tile, `#catalog` shelf cell in the **Notes** row, `.ai-granola`
  background, the `docs.html` list, then the `?v=` bump — same session, per the rule.
  `catalog-sync.sh` fails otherwise.
- `docs/hooks/bridges.md` entry, the `CLAUDE.md` index line, and the prd ruling (**§865**).
- A `-granolaProbe` launch hook that prints the chain link by link, like `-spotifyProbe`.
