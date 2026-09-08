# Reading — the sheet draws the words the app holds

**Ruling: prd §645.** Related and load-bearing: §632 (nothing on the sheet is a
guess), §644 (the app does not compete for the lock screen), §455 / §320 /
§366 / §367 (the four carve-outs this replaces), §282 (screenshot OCR reads
structure), §399 (the journal's neighbour doors).

**Grade: SPEC ONLY.** Nothing below is built. Every file, line and constant is
read off the tree at 2026-09-08 and is cited so the next session can check
rather than trust.

---

## 0. The rule, and its one exception

> If the app fetched the words, the sheet draws them.

`Thing.enrichedText` stops being retrieval-only. Storing text a person cannot
read is what now needs an argument.

**The exception, which is the whole reason the rule can be this wide:
nothing a MODEL wrote.** The digest sweep's summaries stay invisible on every
screen (`-digestProbe`'s own note). Every pass below draws text with a human
author — the publisher's, the person's, or what is on their own screen.

Order of work, and it is not the order of size:

| | Pass | Draws | Fetches | Schema |
|---|---|---|---|---|
| 1 | A saved link's text | stored | — | — |
| 2 | A screenshot's transcript | stored | — | — |
| 3 | Next / previous | — | two bounded reads | — |
| 4 | Listen, everywhere | — | — | — |
| 5 | The 1,200-character cap | | changes what is fetched | — |

No pass adds a `Thing` property, so **no CloudKit deploy** (the 2026-08-01
rule). Pass 5 is the only one that changes what the app asks a publisher's
server for, and therefore the only one with a `NetworkReach` question — see
§5.4.

---

## 1. A saved link draws the text it already has

### What is true now

- `LinkTitle.enrich` runs `fetchPage` (title + readable body) on every pasted
  link and has for a year. `FeedArticleText`'s own doc: *"It is the same
  `LinkTitle.fetchReadable` pass a link YOU paste has had for a year; feed rows
  simply never got it, because they arrive named and `LinkTitle.enrich` bails
  on anything already wearing a real title."*
- So a saved link's lede is **already in `enrichedText`**.
- `ThingContent.kindSwitch`'s `.link` branch (`ThingContent.swift:262`) gates
  the `ArticleBody` mount on `FeedArticleText.sources.contains(thing.source)`.
- `FeedArticleText.sources` (`FeedArticleText.swift:53`) is `["RSS",
  "Substack"]`.

Two of ninety-seven seats. Everything else falls to `LinkPreviewCard` and a
door out to Safari.

### The change

Split the branch's condition in two, because the two halves answer different
questions:

- **Has a body?** → draw it. Source-independent. `FeedArticleText.hasBody`
  already answers this and reads nothing but `enrichedText`.
- **Could get one?** → mount `ArticleBody`'s fetch. Stays gated on the source
  list until pass 5.

`ArticleBody` already handles both states — it draws a stored body immediately
and fetches when there is none — so this is a widened mount condition, not a
new view.

### Rules

1. **The preview card stays ABOVE the body**, as it does today: *"the article's
   own art and its door out to the site are not replaced by its text."*
2. A row whose `enrichedText` merely repeats `summary` or `title` draws nothing
   extra. `summaryBlock` already carries this test (`ThingContent.swift:198`);
   the body needs the same one against `summary`, which it does not have today
   because the two sets never overlapped.
3. Membership for the FETCH stays a named list with reasons (§5.3). Membership
   for the DRAW is "there are words".

### Harness

`ThingContent` is a view and cannot be compiled Foundation-only. What is
provable statically: the `.link` branch must not name `FeedArticleText.sources`
in the draw condition. A drift guard reading a **comment-stripped** copy — this
file documents the rule by naming the thing it must no longer do, which is the
Obsidian/Cursor lesson, paid for four times in this repo.

### Ceiling

A saved link's stored lede was written by an extractor tuned for retrieval. It
can be a nav scrap on a page that defeated `contentRegion`. Pass 5 is where
that gets better; pass 1 ships whatever is there, which is more than nothing
and is what the person can already ask questions about.

---

## 2. A screenshot draws its own transcript

### What is true now

- `ScreenshotOCR.text(for:)` prefers `RecognizeDocumentsRequest` on iOS 26,
  returning a **reading-ordered transcript** — paragraphs held together, table
  cells kept in their rows — falling back to `VNRecognizeTextRequest` below 26
  (§282). Stored as a capped `String` on `content`.
- That text titles the row (`ScreenshotTitle.from`, first line with 3+ words,
  §218), grounds the model's proposed name (`ScreenshotNaming.grounded`, two
  thirds of the words must appear in the OCR), is searched by the answer path,
  and feeds the facts row's dates (`NSDataDetector`, §282).
- `ScreenshotContent` (`ThingContent.swift:551`) takes `assetID` and `stored`
  and draws an image at `maxHeight: 280`.

**The words are never on screen.** Reading a screenshot means pinch-zooming it
in `PhotoViewer`.

### The change

Under the picture, one row in the sheet's existing row grammar:

```
Text in this picture                          212 words  ⌄
```

Tapping it discloses the transcript at `reading20` in `textSelection(.enabled)`.

### Rules — these are what keep it off the §632 shelf

1. **Closed by default.** A picture stays a picture; the row is a door.
2. **A word floor.** Below it, no row at all — not a row saying "no text". The
   OCR of a home screen is nav chrome, and §218 already records what that looks
   like (three different home-screen shots all retitled "Fitness"). The floor
   is a number to MEASURE against a real corpus, not to guess; `readTimeFloor`
   (100) is the app's existing precedent for "a count under the floor is a
   glance, not a reading" (§632 item 5).
3. **Selectable**, which is most of the point — an address, an error string or
   a line of a recipe you can copy out.
4. The transcript is **never** offered as a caption or a description. It is
   what is written in the picture, labelled as that.

### Harness

The floor and the row's own decision are pure: a function from
`(transcript, wordCount) -> Row?` compiles Foundation-only, takes fixtures
(a recipe, a home screen, a wordless photo, a settings pane) and mutates.
`ScreenshotContent` gaining the row is a drift guard.

### Ceiling

**Unmeasured on a real screenshot corpus.** Every number here — the floor, what
fraction of shots clear it — needs `-photoHealProbe`'s `photoHealRow|` lines
read against a real library before the row ships. The simulator's corpus is
seeded and proves nothing about this.

---

## 3. Next and previous, past the journal

### What is true now

`NoteSheetSource.neighbours(of:context:)` (`NoteSheetSource.swift:434`) is the
model, and it is a good one:

- two `FetchDescriptor<Thing>`s, predicated `source == … && capturedAt < …`
  and `> …`, sorted in opposite directions
- `fetchLimit = 2`, not 1 — *"an import receipt shares the room and would
  otherwise be offered as the next entry — a door onto our own note about a
  sync, from inside somebody's diary"*
- `.live`, then first non-self, non-receipt
- drawn by `NoteNeighbourDoors` (`NoteSheetViews.swift:681`), which re-checks
  `row?.live` inside itself (corollary 3)

Mounted for `.entry` rows only — vault notes are excluded because *"a vault
note's `capturedAt` is a file modification time, so its 'next' would be
whatever you last edited."*

### The change

Every reading room gets the doors. §399 said why in a sentence that is true of
all of them: *"so a journal can be read AS a journal instead of one sheet at a
time."*

### The constraint that makes it honest

**The walk follows the order of the list you opened from.**

`FeedSheetRoute.thing(Thing)` (`FeedScreen.swift:469`) is reached from a feed
that may be scoped to a source, filtered by kind (`casberi://feed/type/…`), or
narrowed by a search. Neighbours computed on a global `capturedAt` within a
source would hand back a row the list behind you does not contain. That reads
as a bug and is one.

So:

1. `FeedSheetRoute.thing` carries the scope it was opened from.
2. That scope is a **VALUE** — source, kind, query — and **never a `[Thing]`**.
   CLAUDE.md corollary 4 is exactly this shape: a held `[Thing]` handed onward
   is build 177. The array is never carried; the predicate is rebuilt.
3. `neighbours` takes the scope and builds the same pair of bounded fetches.
4. **Where a scope cannot be reconstructed — a sheet opened from the agent, a
   room head, a "that day" shelf, a search result whose predicate is not
   expressible — draw NO doors.** An absent door is honest. A door onto a row
   the list does not hold is not.
5. `capturedAt` stays the ordering key only where it is the LIST's key. A room
   sorted some other way needs its own, or it gets no doors (rule 4).

### Exclusions inherited

Import receipts (`Corpus.isImportReceipt`), retired sources
(`Corpus.retiredSources`), and anything the room itself filters out.

### Harness

The scope→predicate mapping is pure and takes fixtures. Two mutations worth
pinning up front, because both fail silently and render perfectly: a scope
dropped on the way into the route (doors appear that walk the whole corpus),
and the receipt filter lost (the `fetchLimit = 2` case §399 paid for).

---

## 4. Listen, everywhere — after the audio session is settled

### What is true now

`ArticleListenButton` (`ArticleBody.swift:114`) and `ArticleSpeech.shared` are
**already generic**: `id: String`, `text: String`, one `AVSpeechSynthesizer`
app-wide, a `speakingID` so a second article's button does not read "Stop", and
an `onDisappear` stop so *"a sound the person cannot turn off"* cannot happen.

Mounted from `ArticleBody` and nowhere else, so it exists on RSS and Substack
articles only.

### The decision that comes first

The voice **dies with the sheet**. You cannot start something and put the phone
in your pocket, which is most of what listening is for. Fixing that means an
`AVAudioSession` category, background audio in the target's capabilities, and
`MPNowPlayingInfoCenter` so the lock screen and AirPods can pause it.

**Settle this before the button spreads.** A Listen control on nine surfaces
that all stop on dismiss is one half-feature copied nine times, and the
`onDisappear` rule above has to be REPLACED rather than removed — a voice that
survives its sheet needs a control that also survives it, which is what the now-
playing card is.

### Then the surfaces

Notes, Obsidian notes, Kindle passages, chat transcripts, long social posts,
and whatever pass 1 and pass 5 produce. Rename the type out of
`ArticleBody.swift` when it stops being about articles.

### Ceiling

Nothing here is verifiable on this machine beyond compiling: a simulator does
not lock, does not route to AirPods, and does not show a now-playing card
worth trusting. Device check.

---

## 5. The 1,200-character cap — the finding that outranks the four

### What is true now

`LinkTitle.parseReadable` (`LinkTitle.swift:82`) is **not a readability
extractor**:

- the meta description, plus
- at most **6** paragraphs from `contentRegion`, plus
- de-dupe, flatten, drop pieces under 24 characters, and
- **`text.count > 1200 ? String(text.prefix(1200)) + "…" : text`**
  (`LinkTitle.swift:101`)

Its own doc says so: *"Capped so it stays a lede, not a mirror of the page."*
That was the right bound when the text existed to be searched.

`ArticleBody` draws that output at `reading20`, under a comment reading *"on an
article the body IS the thing."* **The app has never drawn an article.**

Beside it, `FeedArticleText.thinSummary = 400`: an article whose publisher
summary reaches 400 characters is never fetched at all, on the reasoning that
the publisher already gave us its opening. Also lede-sized.

### Why this is last in the order and first in importance

Widening the source gate (§5.3) before raising the cap spreads a 1,200-
character excerpt across ninety-five seats and calls it reading. Passes 1–3
draw text that already exists; this one changes what the app goes and gets.

### 5.1 The extractor

- Raise the paragraph limit and the character cap. Both are one constant each,
  and both are read by three call sites (`fetchReadable`, `fetchPage`, and
  `-linkBodyProbe`), so they move together.
- The fetch is 512KB / 8s (`LinkTitle.swift:53-60`). An article that does not
  fit in 512KB of HTML is rare; one that does not fit in 8 seconds is a slow
  server, and the placeholder already says it is reading.
- `contentRegion`'s marker list (`<main`, `<article`, `role="main"`, …) is what
  decides whether paragraphs are prose or nav. Raising the paragraph limit
  makes a MISS worse, not better — a page with no marker returns the whole body
  and paragraph 40 is the footer. Measure the miss rate before raising the
  limit, or the cap's removal ships nav scraps at `reading20`.

### 5.2 `thinSummary`

Reconsider 400. Its reasoning — *"the publisher gave us the article's opening,
and a scrape would mostly repeat it"* — is a retrieval argument. For reading,
an opening is not the piece.

### 5.3 Then the source list

Widen `FeedArticleText.sources` past `["RSS", "Substack"]`.

**The three abstentions stay, with their reasons.** Membership stays a NAMED
list, never "any http URL":

- **YouTube** — the link is a watch page; a scrape adds player chrome and
  recommendation titles, i.e. other people's video names in this video's text.
- **Reddit** — the selftext is already in `summary`; the page's prose is the
  COMMENTS, *"strangers' words filed under a row that is not theirs"* (§83's
  shape).
- **Podcasts** — an episode page is usually the show notes the feed already
  handed us, and often a player with no prose at all.

A fourth question this pass has to answer and §455 never had to: **which hosts
is a scrape fair on.** A followed feed is a publisher the person chose. A link
pasted from anywhere is not necessarily. Whatever the answer, it belongs here
as a written rule, not in a regex.

### 5.4 `NetworkReach`

A host the app reaches must be declared or the privacy screen is quietly wrong
— build 214's failure, and the standing ship gate. These reaches are the
PERSON's own publishers, so the registry structurally cannot name them (§289);
`fetchOnOpen` already names the service to `NetworkLedger.record(host:as:)`
before the fetch and every widened call site must do the same.

### Harness

`parseReadable` is pure and already reachable. Fixtures: a page with `<main>`,
a page with none, a paywall teaser, a page whose article is 40 paragraphs.
The mutation that matters is the cap itself — a fixture whose article is longer
than the cap, asserting the text does NOT end in `…`.

---

## 6. What is NOT in this spec, and why

- **A generated summary of a thing.** §645's stated exception. §632 and §644
  both turned on the same finding about on-device inference here.
- **Read / unread, or a "needs you" lane.** §455 declined the first, §644 the
  second. Reading richer is the opposite kind of feature: it pays off only when
  somebody has already chosen to open something.
- **A reader mode for the whole feed.** The sheet is the reading surface; the
  feed is the corpus (§182, §236).
- **Anything on the row.** Every pass here is inside `ThingSheetView`. A row
  is a read with ONE gesture (2026-07-16), and a row that grew a transcript
  would be the §632 shelf at feed scale.

---

## 7. Build order

1. Pass 1 — the draw gate. Smallest, and it makes the corpus's own text visible
   on the largest number of rows.
2. Pass 2 — the transcript row. Needs the floor measured on a real library
   first.
3. Pass 3 — the scope through the route, then the doors.
4. The audio-session decision, then pass 4's surfaces.
5. Pass 5 — the extractor, `thinSummary`, the source list, the fairness rule.

Passes 1–3 are drawing and plumbing over stored text. 4 is a capability
decision. 5 is the only one that changes the app's own reads, and it is the one
that makes the word "article" true.
