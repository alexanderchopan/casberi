# Reading — the sheet draws the words the app holds

**Ruling: prd §645.** Related and load-bearing: §632 (nothing on the sheet is a
guess), §644 (the app does not compete for the lock screen), §455 / §320 /
§366 / §367 (the four carve-outs this replaces), §282 (screenshot OCR reads
structure), §399 (the journal's neighbour doors).

**Grade: PASS 1 BUILT, 2-5 SPEC ONLY (2026-09-08).** Pass 1 shipped as A.1
wrote it — see the §645 amendment for the two things it did not say and for
the eleven-page measurement of what the drawn text actually reads like. **That
measurement redirects the order: pass 5 goes next, not pass 3**, because three
of the five pages that drew anything drew chrome. Everything else below is
unbuilt. Every file, line and constant is read off the tree at 2026-09-08 and
is cited so the next session can check rather than trust.

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
| 1 | A saved link's text — **BUILT 2026-09-08** | stored | — | — |
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

---

# Appendix A — the build handoff

**Written for a session that has Xcode, a simulator and `scripts/verify.sh`.**
This spec was authored on Linux with no Swift toolchain, so nothing in it has
been compiled. §426 is the precedent for what that is worth: every constant in
that spec survived contact, and two real things moved anyway — a flag that
governed nothing, and five fixtures that could not catch two transpositions.
**Expect something here to move. When it does, amend the entry rather than
working around it.**

## A.0 Rules for every pass

- **One pass per commit.** Each is independently shippable and independently
  revertable; a combined commit hides which one broke a launch.
- **`scripts/verify.sh`, not the audits you remember.** The standing rule
  (CLAUDE.md): a build shipped an undisclosed host because three audits were
  run by hand and green and the fourth was never invoked.
- **Read `$OUT/step-times.tsv` before aiming any work at the suite.**
- **The liveness corollaries apply to every view added here.** A `View` struct
  storing a `Thing` guards its own body (corollary 5); a `ForEach` content
  closure re-checks inside itself (corollary 3); an array is filtered `.live`
  at the boundary that hands it out (corollary 4). `swiftdata-liveness-audit.py`
  will say so, but the whole point of that audit's history is that it was
  written after each crash, not before.
- **A new harness is discovered by `verify.sh`** if it is named
  `scripts/*-selftest.sh`, and **must have a `--self-test`** — a check that
  cannot demonstrate it catches anything certifies nothing.
- **Any negative guard reads a comment-stripped copy.** Every file here
  documents its rule by naming the thing it must no longer do; a raw grep fires
  on the prose explaining the rule. This repo has paid for that four times.

## A.1 — A saved link draws the text it already has

**Files:** `Casberi/Casberi/Screens/ThingContent.swift` (one branch).

**The edit.** In `kindSwitch`'s `.link` case, the article arm currently reads

```
} else if FeedArticleText.sources.contains(thing.source),
          FeedArticleText.hasBody(thing)
            || FeedArticleText.readableURL(for: thing) != nil {
```

Split it. The DRAW test is source-independent; only the FETCH test keeps the
source list:

```
} else if FeedArticleText.hasBody(thing)
            || FeedArticleText.readableURL(for: thing) != nil {
```

`readableURL` already gates on `sources` internally (`FeedArticleText.swift:105`),
so the fetch arm is unchanged by this edit and stays two sources wide until A.5.
`hasBody` reads nothing but `enrichedText`, so every row that has words now
draws them.

**One thing to add, which the old condition made unnecessary.** The two sets
never overlapped before, so nothing tested the body against `summary`. Give
`ArticleBody` the duplicate test `summaryBlock` already carries
(`ThingContent.swift:198`): if the trimmed `enrichedText` equals the trimmed
`summary`, draw nothing — otherwise a row whose publisher summary WAS the
scrape shows the same paragraph twice.

**Harness:** a drift guard in a new `scripts/reading-draw-selftest.sh` — the
`.link` branch's draw condition must not name `FeedArticleText.sources`,
read from a comment-stripped copy. Mutation: restore the old condition, assert
the guard fires.

**Verify:** `scripts/verify.sh`. Then, on the simulator, with a pasted link in
the corpus: `-openThing "<title prefix>"` and read the sheet. A link saved
before this build already has its words, so no re-ingest is needed — which is
also the fastest proof the pass did what it claims.

**Commit boundary:** this alone. It is the smallest change in the spec and it
reaches the most rows.

## A.2 — A screenshot draws its own transcript

**Files:** `ThingContent.swift` (`ScreenshotContent`, and its call site at
line 232), plus one new Foundation-only model file.

**Measure first.** Run `-photoHealProbe YES` against a real library and read the
`photoHealRow|` lines: each carries an OCR character count and the current
title. **The word floor is set from that distribution, not guessed** — you are
looking for the number that separates a recipe from a home screen. Record the
number you measured and what you measured it on; a floor with no measurement
behind it is the thing §632 cut.

**The model.** `Model/ScreenshotText.swift`, Foundation-only:

```
enum ScreenshotText {
    static let wordFloor = <measured>
    /// nil when there is nothing worth a row.
    static func reading(_ transcript: String) -> (words: Int, text: String)?
}
```

Pure by contract so `scripts/screenshot-text-selftest.sh` can compile it whole.

**The view.** `ScreenshotContent` takes `assetID` and `stored` today; it needs
the transcript, so pass `thing.content` at the call site rather than reaching
for the model inside a leaf. Under the image, a `DisclosureGroup`-shaped row in
the sheet's existing grammar — title `heading17`, trailing `subhead13` count —
**collapsed by default**, drawing at `reading20` with `textSelection(.enabled)`
when open.

**Harness:** `scripts/screenshot-text-selftest.sh`. Fixtures: a recipe (clears),
a home screen's chrome (does not), a wordless photo (nil), a settings pane
(does not). Mutations that matter: the floor removed (every picture grows a
row), and the nil case turned into an empty row (a row that says nothing).

**Verify:** `verify.sh`, then `-openThing` on a screenshot with real text and
one without. **The second is the check** — the wordless one must draw no row at
all, not an empty one.

## A.3 — Next and previous, past the journal

**Files:** `Model/NoteSheetSource.swift` (or a new `Model/SheetNeighbours.swift`
if it outgrows that file), `Screens/FeedScreen.swift` (`FeedSheetRoute`, and its
six construction sites), `Screens/ThingSheetView.swift`, `NoteSheetViews.swift`
(`NoteNeighbourDoors`, which is already generic and only needs renaming).

**The scope type.** A value, and this is the part the compiler will have
opinions about:

```
enum WalkScope: Hashable {
    case source(String)
    case kind(String)
    case none          // no doors
}
```

**`FeedSheetRoute.thing` carries it.** `case thing(Thing, walk: WalkScope)`.
Its `id` (`FeedScreen.swift:621`) must fold the scope in, or two opens of the
same thing from different rooms are one identity to SwiftUI. **Never a
`[Thing]`** — corollary 4, build 177.

Six construction sites (`FeedScreen.swift` 6376, 8469, 9347, 9494, 11490 and the
`OnThisDay` pair). The two anniversary doors and anything opened from a hero
take `.none`: they are not a list.

**`neighbours` generalises.** Same two `FetchDescriptor`s, same
`fetchLimit = 2`, same `.live` and `Corpus.isImportReceipt` skip
(`NoteSheetSource.swift:434`) — the predicate comes from the scope instead of
being hardcoded to `source ==`.

**Harness:** the scope→predicate mapping is pure. Two mutations, both of which
render perfectly and are silent: the scope dropped on the way into the route
(doors that walk the whole corpus), and the receipt filter lost (the case §399
paid for — a door onto our own sync note from inside somebody's diary).

**Verify:** `verify.sh`, then open a thing from an All feed, from a source room,
and from a search result. The third is the one to watch: it must show no doors
unless its scope is expressible.

## A.4 — Listen

**Decide before you build.** The `AVAudioSession` question is not a detail of
this pass, it is the pass. If background audio is in, the target gains the
capability, `ArticleSpeech` gains `MPNowPlayingInfoCenter`, and
`ArticleListenButton`'s `onDisappear` stop is **replaced** rather than removed
— a voice that outlives its sheet needs a control that also does. If background
audio is out, say so in the entry and keep Listen on articles only; a Listen
control on nine surfaces that all die on dismiss is one half-feature copied
nine times.

**Then:** rename the type out of `ArticleBody.swift` (it stops being about
articles), mount it wherever a body is drawn.

**Unverifiable here and on a simulator both.** A sim does not lock, does not
route to AirPods, and does not show a now-playing card worth trusting. Device
check, and the entry says so.

## A.5 — The cap

**This pass opens with a measurement, not an edit, and skipping it is how it
goes wrong.** `contentRegion` (`LinkTitle.swift:103`) looks for `<main`,
`<article`, an id or `role="main"`, and **returns the whole page when it finds
none**. Raising the paragraph limit makes that miss WORSE: on a page with no
marker, paragraph 40 is the footer. So:

1. Run `-linkBodyProbe <url>` across a spread of real pages — a blog, a news
   site, a docs page, a paywall, a page with no `<main>`. Record the miss rate.
2. Only then raise `maxParagraphs` and the 1,200 cap
   (`LinkTitle.swift:101`). Both are read by three call sites and move together.
3. Reconsider `thinSummary = 400` (`FeedArticleText.swift:77`) — its reasoning
   is a retrieval argument, and for reading an opening is not the piece.
4. Then widen `FeedArticleText.sources` (`:53`). **Keep the three abstentions
   and their reasons** (§5.3), and answer in writing the question §455 never
   had to: which hosts a scrape is fair on.
5. **Every widened call site names its service to
   `NetworkLedger.record(host:as:)`** before the fetch, as `fetchOnOpen` already
   does. These are the person's own publishers, so `NetworkReach` structurally
   cannot name them (§289) — the call site is the only disclosure, and an
   undisclosed reach is build 214.

**Harness:** `parseReadable` is pure and reachable. The fixture that matters is
an article longer than the cap, asserting the text does **not** end in `…`.

## A.6 — When each pass lands

Append an amendment under §645 naming the pass, what moved from this spec, and
what was measured (the word floor, the miss rate, the audio decision). The
standing lesson from the §643 amendment applies: **where a ruling's outcome is
a file's contents, the commit that carries the entry carries the file.**
