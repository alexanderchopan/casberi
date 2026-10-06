import SwiftUI
import SwiftData

// The shaped sections (one source in force = its native shape) and the
// room-lead helpers they share, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - Shaped sections (one source in force = its native shape)

    /// Takes the render's one `visible` derivation (and the hint/next-event
    /// ids computed alongside it) and threads them into every shape branch —
    /// none of the branches below re-derive `visible` themselves.
    @ViewBuilder
    func shapedSections(_ allVisible: [Thing], nextEventID: UUID?) -> some View {
        // THE LANE STRIP SCOPES EVERYTHING BELOW IT, head included (2026-08-06).
        let visible = allVisible
        // ABOVE THE HEAD, deliberately (2026-08-23, prd §455). This is not a
        // reading about the room, it is a statement about whether the room is
        // COMPLETE — and every reading below it (a board ranking publishers, a
        // count of stories, a year grid) is computed over rows that a dead feed
        // stopped contributing to weeks ago. A correction printed under those
        // claims is a correction printed after the claim.
        feedHealthNote
        // The new-since divider rides every chronological shape now
        // (2026-07-13) — each source's feed keeps its own last-visit stamp.
        // Photos (a grid), Calendar (future-first) and Reminders (state
        // groups) aren't chronological top-to-bottom, so no line there.
        //
        // A per-source feed overview leads the rows — derived from THIS feed's
        // own things (the same `visible`), above whatever shape they take below.
        // Each source qualifies for at most one: a habit heatmap, a distribution
        // bar, or a thumbnail mosaic. All render only when the real data is
        // there (guards live in FeedHeatmap / FeedInsight). A room that
        // qualifies for none draws the newest thing as a card instead — see
        // `heroShown` (prd §723).
        // Derived once and reused: `heroShown` lets a shape's own lede
        // (a room's cover, Gmail's "waiting") yield so a feed never stacks two
        // overview cards — the lede's records still ride the rows below.
        //
        // Live outranks every aggregate (§164's one exception, cashed in by
        // prd §219): a stream that is ON RIGHT NOW takes the head at frame
        // size. `thing.isLive` here is the SwiftData liveness guard (COROLLARY
        // 2 — the hero holds this reference across renders and a heal pass can
        // delete under it); `isLive(_:)` is the Twitch broadcast set. Both,
        // in that order.
        let liveStream = visible.first { $0.isLive && isLive($0) }
        // The social room's own head (item 5, 2026-07-27) — faces, ringed on
        // fresh activity, beat `FeedHeatmap`'s pre-existing "Casting
        // activity"/"Posting activity" density grid for Farcaster/Bluesky
        // (corrected 2026-07-27: the grid was winning this exact priority
        // chain silently, so the roster built for item 5 had never actually
        // rendered — a density grid says nothing a face with a ring doesn't
        // already say better).
        // ONE DISPATCH (2026-08-26, prd §489). This was a
        // `source == "Farcaster" ? … : BlueskyStore…` ternary, which is not a
        // lookup but a coin flip with two faces: any third network reaching it
        // would have been handed Bluesky's watched accounts. See
        // `SocialRoomSource.accounts(for:)`, which `MainSurface` now reads too,
        // so the rail above the room and the roster inside it can never name
        // two different sets of people.
        let rosterAccounts: [SocialAccount] = liveStream == nil
            ? SocialRoomSource.accounts(for: source)
            : []
        // THE PER-SOURCE HEADS — the rooms whose lede can only come from that
        // room's own model, because the registries below are pure over `Thing`
        // and these facts aren't in the corpus: Cloudflare's certificate dates,
        // Stripe's balance, PostHog's metric readings all live in bridge state.
        //
        // Gathered into ONE term rather than one `let` per card (2026-08-04).
        // Each gate below re-states every predecessor by hand, so three
        // separate lets would mean editing five gates to add a card and
        // silently mis-ranking it if you missed one. They can never compete
        // with each other — each claims exactly one source — so one term is
        // also the honest shape.
        //
        // These sit directly under the live exception because nothing else can
        // claim these rooms: no registry below names any of the three, so the
        // chain would fall through to a blank head. Cloudflare's is also the
        // one card here that renders on an EMPTY room, which is the whole
        // reason it exists — see `CloudflareRunway`.
        // THE ANNIVERSARY — a real thing from this exact day in an earlier year.
        //
        // It sits ABOVE `sourceHead` since 2026-08-17 (prd §398), which is a
        // promotion, and the reason is the one `OnThisDayHero`'s own doc has
        // always given: it is worth more than any STANDING fact the room can
        // state, and it is nil on nearly every day, so it takes the head rarely
        // rather than owning it. Until that pass nothing above it could claim
        // these rooms, so the rank was untested; the journal head landing the
        // same day is what made the order a real question, and a card about how
        // many years you have kept a journal must not cover what you wrote on
        // this date in one of them.
        //
        // SCOPED, and the scope is the whole safety of the promotion: this is
        // non-nil only for the two journals, which have no ALARM head. (The
        // memories room had one too and lost it in prd §832, for §817's reason:
        // an anniversary is a claim about the archive, and it was covering the
        // thing that just landed.) Widen it to a room whose head is a dispute
        // deadline or a Safe awaiting your signature and a nostalgia card would
        // cover something time-critical — so a new source belongs here only
        // after that question is asked about its head.
        let anniversary: OnThisDay.Echo? = liveStream == nil
            ? journalAnniversary(visible: visible)
            : nil
        // READ, NOT COMPUTED (PERF 2026-08-21). The five registry answers below
        // come from `heads`, filled by this screen's own `.task(id: headKey)`;
        // the GATES stay here, unchanged, because `liveStream` and `anniversary`
        // hold `Thing`s and so can never be cached — and because one place for
        // the ranking is the whole reason these were gathered into a chain of
        // re-stated conditions rather than five independent lets (2026-08-04).
        // A nil `heads` is a head that has not been computed yet and draws
        // exactly what a head that DECLINED draws.
        // In a merged room an app pick shows that app's own head, or none —
        // never the room's, which describes every app (prd §1048d, §1052).
        // The Wallet draws the picked app's head in its own box (`walletRoom`'s
        // crown), so here it would be the same card twice (prd §1060).
        let roomHead = selectedSeat != nil
            ? (shape == .wallet ? nil : heads?.seatHead)
            : heads?.sourceHead
        let sourceHead = liveStream == nil && anniversary == nil ? roomHead : nil
        // (The All feed's cross-source "thread" head lived here for one day and
        // was DELETED, prd §333. It ranked a shared WORD as a subject, so its
        // headline read "Wallet" over a Files row, an x402 blurb containing
        // "wallet flow", and two of the person's own commit messages about
        // building the Apple Wallet bridge. That is the deterministic
        // co-occurrence card §36c already removed once for manufacturing
        // connections — see `HomeInsightStore`, whose doc says a real version
        // "would be a fresh build, not a revival of this." The All feed leads
        // with the themes treemap again, which claims only what it measures.)
        // The OCR/text treemap (2026-07-30) — what the screenshots are ABOUT,
        // and since 2026-07-31 what an Instagram export's own captions and
        // comments are about. When there's too little text to say anything it
        // returns nil and the next card down takes the head.
        // X, Instagram and TikTok lead with their newest thing and nothing
        // else (prd §821, `SocialRoom.leadsWithNewest`): neither registry
        // figure below may claim them. Their registry entries are
        // deleted too; this keeps a re-added one from taking the slot back.
        let figuresMayLead = !SocialRoom.leadsWithNewest(source)
        let topicMap = figuresMayLead && liveStream == nil && sourceHead == nil && anniversary == nil
            && rosterAccounts.isEmpty
            ? heads?.topicMap : nil
        let distribution = figuresMayLead && liveStream == nil && sourceHead == nil && anniversary == nil
            && topicMap == nil && rosterAccounts.isEmpty
            ? heads?.distribution : nil
        // The art wall (`FeedInsight.mosaic`) and the year heatmap
        // (`FeedHeatmap`) stood here and were DELETED in prd §832: every room
        // they led now leads with its newest thing, the one template (user:
        // "we really want that to be our template we use on all screens").
        // The heatmap had a second defect: its label set `heroShown` before
        // the grid's own four-active-days floor, so a thin room drew no grid
        // AND no cover.
        // **A ROOM THAT DRAWS NO HEAD GETS THE NEWEST THING AS A CARD**
        // (prd §723) — `memo.lede` is gated on exactly this flag, so the
        // fifteen rooms the deleted board used to head now fall through to
        // `FeedLedeCard`, the All feed's own cover, on the All feed's own
        // terms (`ledeThingID`: newest row, under `ledeMaxAge`, at least
        // `ledeMinRows` deep, never a row that `standsAlone`). Nothing new was
        // built for it; the board was standing in the slot.
        //
        // **`rosterAccounts` IS NOT A HEAD, AND HAS NOT BEEN SINCE §362 (prd
        // §755, user: "we want the most recent post to be big, like it is on
        // the all screen and that pattern should be on every screen").** It
        // belongs in every gate ABOVE — it suppresses the topic map, the
        // mosaic, the distribution and the heatmap, which is the whole job the
        // branch below keeps doing — but it draws NOTHING, so a term meaning
        // "a head card is on the page" may not carry it. It did, and the cost
        // was that every social room with two or more accounts drew no head
        // AND no cover: the suppression was written when the faces were a card
        // in the feed, and they left for the shell in §362, then for the dock's
        // own capsule in §753. The room went a month with an empty slot.
        let heroShown = liveStream != nil || anniversary != nil || topicMap != nil
            || sourceHead != nil || distribution != nil
        if let liveStream {
            insightSection { LiveStreamHero(thing: liveStream) { openThing(liveStream) } }
        } else if let sourceHead {
            // Each card holds no `Thing` — it hands back its own value and the
            // lookup happens HERE, against the live corpus, in the view that
            // owns the sheet.
            insightSection {
                sourceHeadCard(sourceHead, visible: visible)
            }
        } else if let anniversary {
            insightSection {
                OnThisDayHero(echo: anniversary) { feedSheet = .thing(anniversary.thing, walk: .none) }
            }
        } else if let topicMap {
            insightSection { TopicMapHero(map: topicMap) }
        } else if let distribution {
            insightSection { DistributionHero(dist: distribution) }
        }
        switch shape {
        case .snapchat:
            // The memories whose pictures actually came back tile; everything
            // else — saved chats, videos (never fetched, see `SnapchatImport`),
            // and memories whose 7-day download window closed before anyone
            // pressed Get pictures — reads as rows. The split is the honest
            // one: a tile promises a picture, so a row with no pixels stays a
            // dated entry rather than a grey well pretending to be a photograph.
            //
            // The newest thing leads, above everything (prd §832, X's rule §821),
            // and the split is PER DAY (prd §910): a day's memories tile under its
            // header, its other things row beneath them. Kind used to stand
            // above time here — every picture in the export first, then the
            // rest by day.
            let (cover, uncovered) = newestLead(visible, heroShown: heroShown)
            if let cover { Section { ledeListRow(cover) } }
            let days = chronoGroups(uncovered)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days),
                            isTile: Self.isMemoryTile, tileShape: .square)
        case .telegram:
            // The mixed room's fourth instance, and the widest: a followed
            // channel's wordless pictures tile, while its captioned posts, your
            // Saved Messages and whole imported conversations read as rows —
            // per day, under the day's header (prd §910).
            // The newest thing leads, above the grid (prd §832, X's rule §821).
            let (cover, uncovered) = newestLead(visible, heroShown: heroShown)
            if let cover { Section { ledeListRow(cover) } }
            let telegramDays = chronoGroups(uncovered)
            groupedSections(telegramDays, nextEventID: nextEventID,
                            boundary: boundaryThingID(in: telegramDays),
                            isTile: Self.isTelegramPhotoTile, tileShape: .square)
        case .x:
            // The mixed room's third instance (2026-08-13, prd §375), and the
            // one that had to wait for the importer: until a wordless picture
            // post landed as a PICTURE rather than as the t.co shortlink
            // standing in for it, this room had no tiles to draw — every
            // photograph in it was a row whose words were a shortened URL.
            //
            // Same honesty rule as Snapchat's and Files': a tile promises a
            // picture, so only a post with pixels and nothing to say becomes
            // one. A photograph with a caption stays a post card, because the
            // caption is the post — extracting its picture into a grid would
            // separate the two halves of one thing.
            // THE NEWEST THING LEADS, above the grid (prd §821): the cover is
            // lifted out of the room first, so a picture wall never declines it.
            let (cover, uncovered) = newestLead(visible, heroShown: heroShown)
            if let cover { Section { ledeListRow(cover) } }
            // A THREAD READS AS A THREAD (2026-08-18, prd §396). The archive
            // has named a self-reply's parent since §308, and until this pass
            // the only place that fact reached was `enrichedText` — retrieval
            // text, drawn by nothing — so a twelve-post thread was one
            // findable argument and twelve unreadable rows. Same fold the
            // social rooms have used since 2026-07-27, on the same field.
            //
            // Instagram deliberately does NOT fold below: only X's archive
            // names a parent post, which is §309's standing split between what
            // generalises across the import rooms and what is one export's own
            // fact.
            //
            // The fold runs BEFORE the tile split since prd §910 (it used to
            // run on the rows the split left), so a wordless picture you posted
            // into your own thread folds under the thread, which is where it
            // was said, rather than tiling on its own.
            let (roomThings, threadReplies) = foldThreadReplies(uncovered)
            let days = chronoGroups(roomThings)
            groupedSections(days, nextEventID: nextEventID,
                            boundary: boundaryThingID(in: days), replies: threadReplies,
                            isTile: Self.isXPhotoTile, tileShape: .square)
        case .instagram:
            // The mixed room's fourth instance (2026-08-18, prd §395), on
            // Snapchat's, Files' and X's terms: what has pixels AND nothing to
            // say tiles, everything else reads as rows — per day (prd §910).
            // The newest thing leads, above the grid (prd §821) — X's rule.
            let (cover, uncovered) = newestLead(visible, heroShown: heroShown)
            if let cover { Section { ledeListRow(cover) } }
            let days = chronoGroups(uncovered)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days),
                            isTile: Self.isInstagramPhotoTile, tileShape: .square)
        case .wallet:
            // The reads first, then the stream (2026-07-20, the surface split):
            // balance + warnings side by side, the holdings treemap, DeFi, and
            // only then the transactions — capped, with a door to all of them.
            // Everything above the rows is live state, never a landed thing.
            // (The wallet switcher isn't here: it PINS over the stream via
            // safeAreaInset — a scoping control has to stay reachable when
            // you're deep in the transactions it scopes.)
            // The stream's rows, gathered ONCE at the top of the case
            // (2026-08-18): the newest few now LEAD the room from inside the
            // balance card (`walletTodayCard`) and the rest read below, so
            // both halves have to be cut from one list — computed twice, a
            // row would show up in both.
            let upcoming = walletUpcoming(visible)
            // Promoted rows leave the stream, or the same deadline would be
            // read twice on one screen — once as what's coming and once as
            // whenever it happened to land.
            // A bill that repeats lives on Subscriptions (prd §1105), so it
            // leaves the stream the same way.
            let promoted = Set(upcoming.map(\.id))
                .union(visible.filter { SubscriptionsSource.isBill($0) }.map(\.id))
            // **HOME IS EVERYTHING THAT HAPPENED, ACROSS EVERY APP THE WALLET
            // FOLDED IN (prd §1048, step 4).** The history screen behind its
            // door reads the same sources (`RoomAccounts.roomSources`), so its
            // count opens the list it counts (§837). An app pick (§1048b)
            // narrows both to that app.
            let seatPicked = selectedSeat != nil
            let all = visible.live.filter { !promoted.contains($0.id) }
            // WHICH READING IS ON SCREEN (prd §483). Resolved rather than read
            // raw: a scope remembered from a wallet that has since closed its
            // last position falls back to the feed instead of rendering an
            // empty page that claims to be a section.
            // An app pick dims the scopes with nothing for that app (prd
            // §1078), and a remembered one of them resolves to Home.
            let inert = seatPicked ? walletInertSections(visible: visible, upcoming: upcoming) : []
            let section = WalletSection.resolve(
                chrome.walletSection,
                present: walletSectionPublication.sections.filter { !inert.contains($0) })
            // The crown's own newest-few (§208, added 2026-08-18) exist for one
            // reason: "the room's transactions used to begin after ten standing
            // cards, so on a busy wallet the one thing a wallet app gets opened
            // for was two screens down." In `.activity` they are no longer two
            // screens down — they are the next thing on the page — so leading
            // with three of them and then repeating them below is §208's own
            // "never say one thing twice", committed by the fix for it.
            //
            // Every other scope KEEPS them, and that is the half worth stating:
            // standing in Holdings or Permissions, the transactions are not on
            // screen at all, and three of them in the crown is the only place
            // that room still says what just happened.
            // HOME'S LIST IS THE LAST FEW MOVES (prd §483). Every scope is one
            // drawing and one list; Home's list is these three rows, so they
            // draw here and nowhere else. In `.activity` the full stream is
            // directly below and repeating three of it at the top is §208's own
            // "never say one thing twice"; in every other scope the room is
            // answering a different question entirely.

            // **BOX · TILES · MENU, THEN THE LIST (prd §1039).** The crown is
            // the chrome's box on Home, the scope's figure off it; the tiles
            // and the account menu sit under it; the scope's list follows.
            // THE TOGGLE SITS BELOW THE SPARKLINE, IN THE CONTENT (user ruling,
            // 2026-08-26: *"we need to have those toggles be below the
            // sparkline"*, and *"we cannot have four rows of chips"*).
            //
            // It mounted in `MainSurface.roomControls` for one build, which put
            // it FOURTH in a stack of pinned strips — source chips, venue rail,
            // face rail, then this — and pushed the crown to about 45% down the
            // screen. Moving it into the scroll is the fix for both complaints
            // at once, and it makes the structure honest rather than merely
            // shorter: **the crown and its chart belong to no scope.** They are
            // the room's identity, so they sit ABOVE the control that scopes
            // everything else, and §482's "crown and holdings are one reading"
            // now holds by construction instead of by ordering things carefully.
            //
            // KNOWN, and the next thing to fix rather than something to pretend
            // is solved: a control inside the scroll scrolls away, which is
            // §357's own complaint one level down — a scope control you cannot
            // reach while deep in the rows it scopes. The answer is a pinned
            // `Section` header (those stick in a plain `List` for free), not a
            // return to `safeAreaInset`.
            // ONE DRAWING PER SCOPE, ABOVE THE CONTROL (prd §483). Home's is
            // the sparkline, which the crown draws itself; every other scope's
            // steps into the same slot, so the room always opens on a figure
            // and the toggle always sits between that figure and its list.
            // **THE BAR MUST LAND IN THE SAME PLACE ON EVERY SCOPE** (user
            // ruling, prd §483: *"this bar of avatars and toggles below it
            // should be in a fixed position on each page, it should not
            // move"*). The only way that is true is if everything ABOVE it is
            // one height — so the visual slot is fixed rather than fitted, and
            // each scope's drawing sits in it top-aligned.
            //
            // A `maxHeight` as well as a `minHeight`, which is the half that
            // makes it a promise: without it the flow band's own card (a header,
            // three lines of reading and a 138pt band) ran to roughly three
            // times the sparkline's height and pushed the bar a third of a
            // screen down.
            // **NOT EMITTED AT ALL ON HOME** — the counterpart of the crown's
            // own gate above, and the actual reason the bar kept moving.
            //
            // Both were emitted always and collapsed with `maxHeight: 0`, which
            // collapses the VIEW and not the SECTION: a `List` still gives an
            // empty section its own spacing. So Home drew ONE MORE SECTION than
            // every other scope — its crown plus an empty visual — and the bar
            // sat that spacing higher there. Two zero-height boxes, each
            // invisible, and the difference between them was the bug.
            // Off Home the chrome draws the scope's figure in the box Home's crown
            // takes, then the tiles under it (prd §752, §765). The figure is not
            // a Section of its own here any more: as a sibling it took its own
            // row insets and the List's section spacing, and the tiles landed
            // at a different height than on Home.
            walletScopeChromeSection(section, visible: visible,
                                     upcoming: upcoming, inert: inert,
                                     streamTotal: all.count)
            // THE FOUR `walletGroupHeader` GROUPS BECOME SCOPES (prd §483).
            // Renamed to short nouns and split twice — NFTs out of "What you
            // hold", and "What it's doing" into Positions and Risk — so the
            // mapping from card to scope is IDENTITY: every section below is
            // the one that shipped, moved and not redrawn.
            //
            // The headers themselves are gone rather than kept inside their
            // scopes, because the chrome says the same words in the same place
            // — the scope's own row on Home, its own title inside it (§747) —
            // and two of them would be §208's rule broken by the very pass
            // that cites it. They come back the day a scope holds two unlike
            // kinds of thing.
            switch section {
            case .home:
                // **HOME'S LIST IS THE ACTIVITY, AND ONLY WHAT HAPPENED (prd
                // §1039, §1041).** Home drew nothing under the chrome since
                // §747 — its list was the Overview rows, the tiles said twice
                // — and the moves lived one tile over, under Activity. The
                // Activity tile is deleted and its list is Home's: the moves
                // under the feed's day headers (§942), then the door to all of
                // them.
                //
                // **WHAT'S AHEAD LEADS IT (prd §1111, user: "coming up moved to
                // activity", "'needs you' becomes a section in home").** Coming
                // up became Subscriptions, so Needs you and the dated rows
                // stand at the head of Home, above what happened.
                walletComingUpSections(upcoming, nextEventID: nextEventID)
                let stream = walletStream(all)
                walletStreamSections(stream.rows, ownMoves: stream.ownMoves, nextEventID: nextEventID)
                walletSeeAllSection(total: all.count)
                // **AN EMPTY LIST DRAWS ITS ROWS EMPTY (prd §769).** Watch a
                // wallet, at the head of the Accounts pill's list, is the
                // remedy, one tap away (§1107).
                if all.isEmpty {
                    walletSkeletonRowsSection
                }
            case .subscriptions:
                // **SUBSCRIPTIONS AND NOTHING ELSE (prd §1111).** Add first,
                // the person builds the list up, then every plan.
                walletSubscriptionsSections
            case .holdings:
                let apps = walletAppRows(all)
                if portfolio?.isEmpty ?? true, !hasLendingCard, walletLive.uniswap.isEmpty,
                   walletLive.hyperliquid.positions.isEmpty, apps.isEmpty {
                    walletSkeletonRowsSection
                }
                // **TOKENS, THEN POSITIONS (prd §1107, user: "tokens then
                // positions").** Positions' tile folded in, the loan risk with
                // it; then the apps that hold a wallet for you (§1124); NFTs
                // still read under them (prd §1048).
                walletTokenListSection
                walletStaleReadingsSection
                walletPositionsSections
                walletAppsSection(apps, nextEventID: nextEventID)
                // An app the menu picked holds no collections (prd §1048b).
                if !seatPicked {
                    if nftShelfEntry == nil {
                        walletNFTDoorSection
                    }
                    walletNFTListSection
                }
            case .security:
                // **WHO CAN ACT FOR YOU, THEN WHAT IS TRYING TO FOOL YOU (prd
                // §947, §1107).** Signatures, Delegations, Approvals, then
                // Address poisoning, Fake tokens, Fake transfers — the box's
                // six cells, in the box's order.
                if walletScopeIsEmpty(.security) {
                    walletSkeletonRowsSection
                }
                walletSecuritySections
            }
        case .tokens:
            // The Watchlist, or a catalogue category's company pack
            // (`CompanyPacks`), picked on the tiles.
            if chrome.tokensScope.isPack {
                marketsIndexSections(chrome.tokensScope, visible: visible)
            } else if chrome.tokensScope == .alerts {
                marketsAlertsSections(visible, nextEventID: nextEventID)
            } else {
                marketsWatchlistSections(visible, nextEventID: nextEventID)
            }
        default:
            if Pinboard.isPinnedRoom(source) {
                notesSections(visible, nextEventID: nextEventID)
            } else if filter.tag != "All" && shape == .all {
                daySection(filterLabel, visible, nextEventID: nextEventID, dated: false)
            } else if shape == .all {
                // The Themes treemap no longer renders here — it moved ABOVE
                // the shape chain entirely (prd §385, see the call site in
                // `feedList`): it must precede every hero this switch's
                // preamble draws, or the fold-settle scroll would hide a live
                // hero above the fold along with the map.
                // All is where volume floods — bundles + the new-since
                // divider live here. A single source's shape IS that source;
                // bundling there would collapse the whole screen into one row.
                bundledSections(visible, nextEventID: nextEventID,
                                heroShown: heroShown)
                corpusFloorSection(visible)
            } else if source == RoomAccounts.workRoom {
                workRoomSections(visible, nextEventID: nextEventID, heroShown: heroShown)
            } else if source == RoomAccounts.dayRoom {
                dayRoomSections(visible, nextEventID: nextEventID, heroShown: heroShown)
            } else if source == RoomAccounts.readingRoom {
                readingRoomSections(visible, nextEventID: nextEventID, heroShown: heroShown)
            } else if source == RoomAccounts.mediaRoom {
                mediaRoomSections(visible, nextEventID: nextEventID, heroShown: heroShown)
            } else if source == RoomAccounts.socialRoom {
                socialRoomSections(visible, nextEventID: nextEventID, heroShown: heroShown)
            } else if agentRoomShown {
                agentRoomSections(visible, nextEventID: nextEventID, heroShown: heroShown)
            } else {
                // Threads fold BEFORE day-grouping (item 6, 2026-07-27): a
                // person's own consecutive replies collapse into one card in
                // their room, so `roomThings` (fewer rows than `visible`)
                // feeds the existing day/ForEach pipeline unchanged, and
                // `threadReplies` rides beside it for `shapedRow` to render
                // inline. Scoped to `.social` — every other shape's `visible`
                // passes through untouched.
                // (The merged Social and Reading rooms draw their own
                // sections since prd §1086 and §1085.)
                let rows = visible
                let (roomThings, threadReplies): ([Thing], [String: [Thing]]) =
                    SocialRoom.foldsThreads(source) ? foldThreadReplies(rows) : (rows, [:])
                // Live-first in a source's own room (2026-07-21): a stream
                // that's on RIGHT NOW is the one row whose relevance isn't
                // chronological, so it leads its group. No-op for sources
                // with no live set.
                let days = chronoDays(roomThings)
                // A room with no head covers its newest thing (prd §732). A
                // post or thread card declines it (`standsAlone`): the newest
                // post already draws at card size.
                // Pinterest's pins tile under their day at 2:3 (the picture
                // rooms' grid, prd §910); a pin with no image stays a row.
                let pins = source == "Pinterest"
                // Media is one square grid (§1055): every picture tiles.
                let media = source == RoomAccounts.mediaRoom
                groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days),
                                replies: threadReplies,
                                cover: heroShown ? nil : ledeThingID(in: days),
                                isTile: media ? Self.isMediaTile : (pins ? Self.isPinTile : nil),
                                tileShape: pins ? .pin : .square,
                                scopeControl: true)
            }
        }
    }

    /// **THE LEAD SLOT, HELD WHEN THERE IS NOTHING TO COVER (prd §862).**
    ///
    /// A room whose tiles stand over an EMPTY list had nothing above them, so
    /// the tiles landed at the top of the screen — the one thing §752 bans
    /// outright, and the half of §841 that pass did not finish: it gave the
    /// Chat tile a thread to sit under and left All with nothing to sit under
    /// when the room holds no rows. Reported on Bankr's room the day after
    /// §845 finally made that room reachable with zero conversations in it.
    ///
    /// So the room's own empty state holds the lead instead — the rows that
    /// would fill it, drawn empty (§769, §771) — in `FeedLedeCard`'s exact
    /// geometry (`leadHeight - 2 × s4` inside `dsRoomHeadBlock`), so the box
    /// is the cover's to the point and the tiles below land where they land
    /// in every other room. It also REPLACES the skeleton rows those rooms
    /// drew under the tiles: one empty state per empty room, not two.
    ///
    /// **Only over an empty list.** A room with rows but nothing coverable —
    /// every row of its newest day declines the cover (§763) — keeps its lead
    /// unheld, because an empty state over a full list is the §83 lie. The
    /// honest fix for that case is a cover, not a skeleton.
    func emptyLeadRow(headline: Text, words: Text,
                              figure: DSSkeleton.Figure? = nil) -> some View {
        DSEmptyState(headline: headline, words: words,
                     scale: figure.map { .room($0) } ?? .list(rows: 3))
            .frame(maxWidth: .infinity,
                   minHeight: DSRoomChassis.leadBox,
                   maxHeight: DSRoomChassis.leadBox)
            .dsRoomHeadBlock()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The cover row's own insets (`ledeListRow`), so an empty room's
            // tiles stand where a full room's do (prd §1102).
            .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
    }

    /// THE NEWEST THING, LIFTED OUT OF A MIXED ROOM (prd §821).
    ///
    /// X's and Instagram's rooms draw a picture grid above their days, and a
    /// grid used to decline the cover — so the room led with a wall of
    /// photographs, never with what just arrived. Here the cover is chosen over
    /// the WHOLE room (`ledeThingID`, §389's positional rule: the newest
    /// coverable thing) and lifted out before the grid and the days are split,
    /// so it draws once, first. `SocialRoom.leadsWithNewest` names these rooms.
    private func newestLead(_ visible: [Thing], heroShown: Bool) -> (cover: Thing?, rest: [Thing]) {
        let live = visible.live
        guard !heroShown, let id = ledeThingID(in: chronoGroups(live)),
              let cover = live.first(where: { (thing: Thing) -> Bool in thing.id == id }) else {
            return (nil, live)
        }
        return (cover, live.filter { (thing: Thing) -> Bool in thing.id != id })
    }

    /// An agent's room (prd §840): the cover, the two tiles, then either the
    /// conversations you have had or the one you are having.
    ///
    /// It follows `DSRoomChassis.Head`'s geometry exactly rather than inventing
    /// its own — cover, `contentGap`, tiles, `leadGap`, content — because the
    /// tiles are one control in one place in every room that has them (§752,
    /// user: *"that is a template. we follow it in all rooms, so the buttons
    /// can't be in different places on each screen"*).
    ///
    /// **The cover stands on BOTH tiles, so the tiles never move** (user,
    /// 2026-09-19: *"i think when you chat the buttons shouldn't have
    /// moved"*). §840's first build drew it on All only, reasoning that on
    /// Chat the room IS the conversation — which put the tiles at two
    /// different heights depending on which one was picked, the exact thing
    /// §752's template rule exists to prevent. The cost is that a
    /// conversation's opening question reads twice on Chat, as a title card and as the first turn. That is the
    /// cheaper of the two, because one is a repetition and the other is
    /// furniture that walks.
    @ViewBuilder
    private func agentRoomSections(_ visible: [Thing], nextEventID: UUID?,
                                   heroShown: Bool) -> some View {
        let chatting = chrome.agentScope == .new && roomAgent != nil
        // The thread and the entry are the agent's own: its source, not the
        // Agents room's (prd §1054).
        let agentSource = roomAgent?.agent ?? source
        let days = chronoDays(visible)
        let coverID = heroShown ? nil : ledeThingID(in: days)
        let coverThing: Thing? = coverID.flatMap { id in
            visible.first(where: { (thing: Thing) -> Bool in thing.isLive && thing.id == id })
        }
        // THE LEAD SLOT. On Chat the thread fills it; on All the cover does,
        // or — with no conversation to cover — the room's own empty state
        // (§862). One slot, one height, so the tiles below never move (§841).
        let leadHeld = chatting || coverThing != nil || visible.isEmpty
        if chatting, roomAgent != nil {
            Section {
                AgentChatThread(source: agentSource)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.leadGap,
                                              trailing: DSRoomChassis.inset))
            }
        } else if let coverThing {
            Section {
                ledeListRow(coverThing)
            }
        } else if agentRoomShown, visible.isEmpty {
            // AN EMPTY ROOM STILL HOLDS THE LEAD SLOT (user, 2026-09-20: "the
            // buttons are on the top until you press chat"). With no cover the
            // tiles rode up to the top edge on All and dropped 316pt on Chat —
            // §841's walking furniture and §752's banned top control, through
            // the one state §841 never drew. Same well, same height as the
            // thread, holding what would fill it (§769).
            //
            // Through `emptyLeadRow` since §862, for the height: this arm
            // spelled the box as `leadHeight` INSIDE `dsRoomHeadBlock`, which
            // adds `2 × s4` of its own — so the empty lead stood 30pt taller
            // than the cover it stands in for, and the tiles still moved,
            // by less. `FeedLedeCard` subtracts that padding; the helper is
            // the one place either of them says so.
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing asked yet"),
                             words: Text("Your conversations appear here"))
            }
        }
        if let agentTiles {
            Section {
                agentTiles
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: leadHeld ? 0 : DS.Space.s2,
                                              leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.leadGap,
                                              trailing: DSRoomChassis.inset))
            }
        }
        // Under the tiles, as every merged room's menu is (prd §1054).
        roomScopeSection
        if chatting, let roomAgent {
            // The composer row, BELOW the tiles — where the list would be.
            Section {
                AgentChatEntry(source: agentSource, provider: roomAgent)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                              bottom: DS.Space.s3, trailing: DSRoomChassis.inset))
            }
        } else if !visible.isEmpty {
            // The tiles STAY over an empty list — `keepsChromeWhenEmpty`
            // (§538, §769): the Chat tile is how this room stops being empty,
            // so hiding it exactly when there is nothing here would take away
            // the one control that helps. What is NOT here any more is the
            // skeleton that used to draw under them: the lead above the tiles
            // carries the empty state, and drawing it twice said the same
            // nothing on both sides of one control.
            let rest: [(String, [Thing])] = coverID.map { id in
                days.map { label, rows in
                    (label, rows.filter { (thing: Thing) -> Bool in !(thing.isLive && thing.id == id) })
                }
                .filter { !$0.1.isEmpty }
            } ?? days
            groupedSections(rest, nextEventID: nextEventID, boundary: boundaryThingID(in: rest))
        }
    }

    /// The live thing behind a cover id, against this render's rows — liveness
    /// inside the filter, before any stored read (corollary 3).
    func coverThing(_ id: UUID?, in visible: [Thing]) -> Thing? {
        id.flatMap { id in
            visible.first(where: { (thing: Thing) -> Bool in thing.isLive && thing.id == id })
        }
    }

    /// The groups with the covered thing lifted out, so it draws once (prd
    /// §763) — for a room that draws its cover by hand because something
    /// (tiles, a waiting section) must stand between the cover and the days.
    func liftingCover(_ groups: [(String, [Thing])], id: UUID?) -> [(String, [Thing])] {
        guard let id else { return groups }
        return groups.map { label, rows in
            (label, rows.filter { (thing: Thing) -> Bool in !(thing.isLive && thing.id == id) })
        }
        .filter { !$0.1.isEmpty }
    }

    /// THE STANDALONE LEAD, WHERE NO HEAD IS DRAWN (prd §815, §862, §911): the
    /// cover when there is one, the room's own empty state when the tiles
    /// stand over nothing, then the tiles. The Notes room's since the kind-tile
    /// rooms folded into their categories (prd §1059).
    ///
    /// THE LEAD SLOT is held wherever the tiles stand (§862): without it the
    /// tiles sat at the top of the screen — §752's one outright ban — on any
    /// room emptied by its own pick.
    @ViewBuilder
    func standaloneLead<Scope: DSTileScope>(
        cover: Thing?, tiles: DSScopeTiles<Scope>?,
        listEmpty: Bool,
        // What the held lead says over an empty list (Notes, prd §969).
        emptyWords: Text) -> some View {
        let leadHeld = cover != nil || (tiles != nil && listEmpty)
        if let cover {
            Section {
                // One y for the tiles in every room (prd §1102): the cover row
                // keeps its own insets whether tiles follow or not.
                ledeListRow(cover)
            }
        } else if tiles != nil, listEmpty {
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing here yet."),
                             words: emptyWords)
            }
        }
        if let tiles {
            Section {
                tiles
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: leadHeld ? 0 : DS.Space.s2,
                                              leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.leadGap,
                                              trailing: DSRoomChassis.inset))
            }
        }
    }

    /// The door to a room's own share card — a week on GitHub, a streak on
    /// Duolingo (`RoomShareCard.doorLabel`). One row in the rows' column,
    /// under the tiles, never at the top of the screen (prd §752). The tap
    /// copies the rows' bare facts out, so the sheet never holds a `Thing`.
    @ViewBuilder func roomShareDoor(_ visible: [Thing]) -> some View {
        if let label = RoomShareCard.doorLabel(source: source), !visible.isEmpty,
           roomShareCanDraw(visible) {
            Section {
                DSDoorRow(icon: "square.and.arrow.up", label: LocalizedStringKey(label)) {
                    // The ROOM's rows, read on the tap: most rooms lift their
                    // newest thing out of the day groups to draw it as the
                    // cover, so the groups this door stands in are missing
                    // exactly the row a week card most needs.
                    let rows = self.visible.filter(\.isLive)
                        .map { RoomShareCard.Input.Row(at: $0.capturedAt, title: $0.title, facts: $0.facts) }
                    roomShare = RoomShareCard.Input(source: source, rows: rows)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                          bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
            }
        }
    }

    /// Apple Health also holds sleep and steps, so its door stands only over
    /// a workout among the newest rows (a week's worth, bounded — the scan is
    /// a head's, once per body, never per row). The riders' rooms are
    /// workouts only.
    private func roomShareCanDraw(_ visible: [Thing]) -> Bool {
        guard source == "Apple Health" else { return true }
        return visible.prefix(60).contains { $0.isLive && RoomShareCard.isWorkout(facts: $0.facts) }
    }

    /// A SOURCE room's day grouping, memoized (PERF 2026-08-01, prd §263).
    ///
    /// The All room's grouping has been memoized since §258; every OTHER room
    /// recomputed `chronoGroups` from scratch on each body evaluation, and every
    /// mounted page re-evaluates whenever `filter.source` changes — i.e. on
    /// every swipe. Measured with `sample` (the only instrument here that sees
    /// row-closure work at all): `chronoGroups` 165 samples + `dayGroups` 124
    /// on a 4,000-row corpus.
    ///
    /// This was tried once before and recorded as "neutral", which was a
    /// measurement artifact: it was judged with a `perfAccum` timer wrapped
    /// around a view-building property, and SwiftUI evaluates the `ForEach`
    /// content closure AFTER that property returns, so the timer could not see
    /// the work either way. Same change, real instrument, different answer.
    ///
    /// Shares `DerivationMemo` with `bundledSections` safely: a given
    /// `FeedScreen` has a fixed `source` and takes one branch or the other
    /// consistently, and `filter.tag` — the one input that moves it between
    /// them — is part of the key.
    func chronoDays(_ roomThings: [Thing]) -> [(String, [Thing])] {
        let key = derivationKey(roomThings)
        if memo.key != key {
            memo.key = key
            memo.days = liveFirst(chronoGroups(roomThings))
            memo.groups = []        // this path renders things, not bundled rows
        }
        return memo.days
    }

    /// The first thing at-or-past the last-visit boundary in a shaped feed's
    /// day groups — the Thing twin of `boundaryID(in:)` (which speaks FeedRow,
    /// All's bundled currency). Same freeze semantics: computed ONCE per
    /// render by the caller and passed down, never re-derived per row.
    func boundaryThingID(in groups: [(String, [Thing])]) -> UUID? {
        guard let newSince else { return nil }
        let all = groups.flatMap(\.1)
        guard let first = all.first, first.capturedAt > newSince else { return nil }
        return all.first(where: { $0.capturedAt <= newSince })?.id
    }

    /// A source's own head card (prd §298 onward), for its room — and, since
    /// the Wallet folded its apps in, for the Wallet's box when the menu picks
    /// one of them (prd §1048d: the precedent §1049 set for Work's Stripe).
    /// Each card holds no `Thing` — it hands back its own value and the lookup
    /// happens HERE, against the live corpus, in the view that owns the sheet.
    @ViewBuilder
    func sourceHeadCard(_ sourceHead: SourceHead, visible: [Thing]) -> some View {
        switch sourceHead {
        case .runway(let runway):
            CloudflareRunwayCard(runway: runway) { item in
                openBySourceRef(item.id, in: visible)
            }
        case .stripe(let room):
            StripeRoomCard(room: room) { item in
                openBySourceRef(item.id, in: visible)
            }
        case .polar(let room):
            PolarRoomCard(room: room) { item in
                openBySourceRef(item.id, in: visible)
            }
        case .dodoPayments(let room):
            DodoPaymentsRoomCard(room: room) { currency in
                // A currency owns many payments, so the honest landing
                // is its most recent one — the Gnosis Pay rule, matched
                // on the same `priceCurrency` field the room groups by.
                openNewest(source: DodoPaymentsRoomSource.source, in: visible) { thing in
                    thing.priceCurrency == currency.code
                }
            } onOpenRetry: { retry in
                openBySourceRef(retry.id, in: visible)
            }
        case .posthog(let room):
            PostHogRoomCard(room: room) { event in
                openBySourceRef(PostHogWatch.metricRef(event), in: visible)
            }
        case .cardPointers(let room):
            // No callback since §487: the head stopped naming a single
            // offer, so it has nothing to open — every offer is its own
            // row a scroll below, and each of those is its own door.
            CardPointersRoomCard(room: room)
        case .walletbeat(let room):
            WalletbeatRoomCard(room: room) { ref in
                // The card names a real row's `sourceRef`, so this lands
                // exactly — the card itself holds no `Thing` (corollary 5)
                // and the lookup happens here, against the live corpus.
                openBySourceRef(ref, in: visible)
            } onBrowse: {
                // Pushed, not raised: this is navigation to a place, not a
                // connect act (§219 — Connect raises, Open pushes). Straight to
                // the directory, never via the connect screen: §234's ruling is
                // that a browse is mounted by the room, and routing through the
                // setup screen made reading the list a trip into the catalog
                // plus a second tap (prd §421).
                route.path.append(.walletbeatDirectory)
            }
        case .l2beat(let room):
            L2beatRoomCard(room: room) { ref in
                openBySourceRef(ref, in: visible)
            } onBrowse: {
                // Pushed, not raised (§219 — Connect raises, Open pushes), and
                // straight to the directory rather than via the connect screen
                // (§234 — a browse is mounted by the room).
                route.path.append(.l2beatDirectory)
            }
        case .peer(let room):
            PeerRoomCard(room: room) { rail in
                // A rail owns many fills, so the honest landing is its
                // most recent one, matched on the funding rail §311
                // stamps on `authorHandle` (the Cursor repo rule).
                openNewest(source: PeerRoomSource.source, in: visible) { thing in
                    thing.authorHandle == rail.name
                }
            }
        case .privacyPools(let room):
            // Drawn in the Wallet's box when its menu picks 0xBow (prd
            // §1048d), every reading at once: the Wallet's tiles are the ones
            // under it (prd §1060).
            PrivacyPoolsRoomCard(room: room) { slice in
                // Matched on the DEPOSIT ref as well as the tag: an
                // alert row about a cleared deposit carries no state
                // tag, but a future one might, and landing on the
                // announcement instead of the deposit it announces
                // is the wrong row by one hop.
                //
                // The UNKNOWN slice is the same match with the test
                // inverted — a deposit wearing none of the bridge's
                // state tags (prd §486). It is a real door rather
                // than a label for the same reason every other
                // legend row is one: these are deposits you can go
                // and look at, and the one thing this card cannot
                // say about them is on the row itself.
                openNewest(source: PrivacyPoolsRoomSource.source, in: visible) { thing in
                    guard thing.sourceRef?.hasPrefix(PrivacyPoolsRoom.depositPrefix) ?? false
                    else { return false }
                    switch slice {
                    case .state(let state): return thing.tags.contains(state.rawValue)
                    case .unknown: return PrivacyPoolsRoom.state(tags: thing.tags) == nil
                    }
                }
            }
        case .cardSpend(let room, let seat):
            CardSpendRoomCard(room: room, seat: seat) { currency in
                // A currency owns many spends, so the honest landing is
                // its most recent one — and it must be a SPEND, asked
                // through the same rule the head composed with (prd
                // §868). Matching on `priceCurrency` alone was right
                // only by coincidence: ether.fi's room also holds
                // unstake and risk rows, and none of them happens to
                // carry a currency today.
                openNewest(source: seat, in: visible) { thing in
                    CardSpendSeat.isSpend(thing, seat: seat)
                        && thing.priceCurrency == currency.code
                }
            }
        case .privy(let room):
            PrivyRoomCard(room: room) { ref in
                openBySourceRef(ref, in: visible)
            }
        case .railgun(let room):
            RailgunRoomCard(room: room) { token in
                // A token owns many moves, so the honest landing is
                // its most recent one, matched on the same
                // `priceCurrency` field the room groups by (the
                // Gnosis Pay currency rule, one field over).
                openNewest(source: RailgunRoomSource.source, in: visible) { thing in
                    thing.priceCurrency == token.symbol
                }
            }
        case .safe(let room):
            // `fallbackRef` is what the card opens when nothing is
            // pending and only a module warning stands — without it
            // that card announced a door and had none (2026-08-17).
            SafeRoomCard(room: room,
                         fallbackRef: SafeRoomSource.fallbackRef(things: visible)) { ref in
                // Unlike its siblings, a Safe entry OWNS a single row
                // — the tracking snapshot is keyed by the pending
                // thing's own `sourceRef` — so this is a direct
                // lookup, not a newest-of-many match.
                openBySourceRef(ref, in: visible)
            }
        }
    }

}
