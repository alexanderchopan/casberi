import SwiftUI
import SwiftData

// Row dispatch: the row entrance, the run backgrounds, the shaped list row,
// the social row and the shaped row, and the row's long-press verbs, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// Every feed row's entrance, from ONE place (prd §600, 2026-09-04).
    ///
    /// Twenty call sites spelled `RowEntrance(index:wave:style:)` by hand, so
    /// adding the swipe suppression below would have meant twenty identical
    /// edits and twenty places for the next one to drift. The index is the only
    /// thing that ever differed.
    ///
    /// `rowBudget != nil` IS "a swipe is landing in this room": `MainSurface`
    /// sets it in the same transaction as `filter.source` and releases it once
    /// the slide has settled, so the rows that mount during the transition
    /// arrive at rest and every later row keeps its entrance. Nothing
    /// re-animates when the budget lifts — `reveal()` runs on appear and on a
    /// `wave` change, and this is neither.
    func rowEntrance(_ index: Int) -> RowEntrance {
        RowEntrance(index: index, wave: shapeWave, style: entranceStyle,
                    instant: rowBudget != nil, waveAt: shapeWaveAt)
    }

    /// How this shape's rows arrive: the agenda slides in from the leading
    /// edge like a day filling, photos scale in like the grid, transactions
    /// rise like entries posting, everything else lifts gently.
    private var entranceStyle: RowEntrance.Style {
        switch shape {
        case .calendar: .init(dx: -28, dy: 0, scale: 1, step: 0.045)
        case .wallet, .tokens: .init(dx: 0, dy: 16, scale: 1, step: 0.04)
        case .photos:   .init(dx: 0, dy: 0, scale: 0.92, step: 0.03)
        case .music:    .init(dx: 0, dy: 10, scale: 1, step: 0.035)
        // Frames settle in like the music room's covers — a touch of scale so
        // the art reads as arriving, not sliding.
        case .media:    .init(dx: 0, dy: 10, scale: 0.97, step: 0.035)
        case .social, .x, .instagram, .tiktok: .init(dx: 0, dy: 12, scale: 0.98, step: 0.035)
        default:        .init(dx: 0, dy: 8, scale: 1, step: 0.028)
        }
    }

    /// Live right now, from the source's own current-live set (Twitch
    /// refreshes it every foreground) — never inferred from row age.
    func isLive(_ thing: Thing) -> Bool {
        thing.source == "Twitch"
            && thing.sourceRef.map { TwitchIngest.liveRefs.contains($0) } ?? false
    }

    /// Float any live rows to the top of the NEWEST group (2026-07-21) — a
    /// stream on right now isn't a chronological row. Scoped to Twitch (the
    /// one source with a live set) and to the first group only, so history
    /// below stays in time order. A no-op everywhere else.
    func liveFirst(_ groups: [(String, [Thing])]) -> [(String, [Thing])] {
        guard source == "Twitch", let first = groups.first,
              first.1.contains(where: isLive) else { return groups }
        let rows = first.1
        var out = groups
        out[0] = (first.0, rows.filter(isLive) + rows.filter { !isLive($0) })
        return out
    }

    // MARK: - Row dispatch (the shape decides what a row leads with)

    /// The swipe's hand-off target, when the thing has one — shared by both
    /// swipe edges so they agree on what counts as "has a destination".
    private func openVerb(for thing: Thing) -> Verb? {
        VerbDerivation.verbs(for: thing).first {
            if case .openURL = $0.action { return true } else { return false }
        }
    }

    /// Where a row sits in its day's shared card (ruling 2026-07-21,
    /// superseding 2026-07-13's gap-only clustering): a contiguous run of
    /// row-shaped things within a day merges into ONE card — the §61
    /// section-lift mechanic brought to the plain list — while the
    /// rhythm-breakers (`standsAlone`) keep free-standing cards between
    /// runs, and the new-since seam splits a day's card in two.
    enum RunPosition { case only, first, middle, last }

    /// Positions for a section's rows, index-based so All's FeedRow bundles
    /// and plain Thing arrays share one derivation. A run breaks at a
    /// free-standing row on either side, and at the new-since boundary
    /// (the divider renders BEFORE the boundary row, so the row above it
    /// closes its run and the boundary row opens a fresh one).
    func cardRunPositions(count: Int,
                                  isBreaker: (Int) -> Bool = { _ in false },
                                  isBoundary: (Int) -> Bool = { _ in false }) -> [RunPosition] {
        (0..<count).map { i -> RunPosition in
            let starts = i == 0 || isBreaker(i) || isBreaker(i - 1) || isBoundary(i)
            let ends = i == count - 1 || isBreaker(i) || isBreaker(i + 1) || isBoundary(i + 1)
            switch (starts, ends) {
            case (true, true):   return .only
            case (true, false):  return .first
            case (false, true):  return .last
            case (false, false): return .middle
            }
        }
    }

    /// The anatomies that earn a free-standing card — shapedRow's
    /// rhythm-breakers. Everything else (band, check, excerpt, reading,
    /// music) merges into its day's run.
    ///
    /// `thing.modelContext == nil` is the crash guard (2026-07-24, live
    /// TestFlight crash on 125/126, upgrade-only — never a fresh install):
    /// `bundledSections`' `visible` array is captured once per render, but
    /// the delete-sync heal passes (Calendar/Reminders/Contacts/HomeKit/
    /// Bluesky/Farcaster, added §prd 121) run as `Task { @MainActor in }` —
    /// correctly serialized with the UI, but still able to land BETWEEN this
    /// render's capture and this closure's evaluation inside the `ForEach`.
    /// A `Thing` SwiftData deletes gets its `modelContext` niled out first;
    /// reading that one property is documented-safe on a deleted model, but
    /// `thing.kind`/`thing.mark` below fault-resolve against the store and
    /// crashed (`_assertionFailure` inside SwiftData, real device only — a
    /// fresh install has no synced Calendar/Reminders/etc. yet to delete).
    func standsAlone(_ thing: Thing) -> Bool {
        guard thing.modelContext != nil else { return false }
        if thing.kind == .approval && thing.mark != .done { return true }  // consent card
        // A POST CARD NEVER MERGES, IN ANY OF THE SEVEN ROOMS THAT DRAW ONE
        // (2026-08-26, prd §489) — and the answer is DERIVED from the same
        // `rowKind` that picks the anatomy, never spelled beside it.
        //
        // That derivation is the fix. §396a happened because `shapedRow` and
        // this function answered "is this a post" in two places and drifted; it
        // was then repaired for X alone, and Instagram and Telegram went on
        // drawing post cards squeezed into a merged run of bare rows — a card
        // by anatomy with no card under it — in rooms nobody had reported.
        // Two more instances of one bug, in a registry the two new cases never
        // joined. There is now nothing to join: if `rowKind` says card, this
        // says card.
        if SocialRoom.drawsPosts(thing.source) {
            return SocialRoomSource.standsAlone(thing)
        }
        if shape == .chat && thing.mark == .doing { return true }          // TakeawayCard
        if TokenPulse.shared.pulse(for: thing) != nil { return true }      // TokenRow fat anatomy
        if StockWatch.symbol(of: thing) != nil { return true }             // its twin for a stock
        return false
    }

    /// The run-aware card surface: first/last rows carry the card's rounded
    /// shoulders and the s1 breathing edge; middle rows run square and
    /// GAPLESS, so a row's shadow falls on the adjacent same-color fill and
    /// vanishes (§61's measured mechanic) — only the run's outer silhouette
    /// casts, one lifted card instead of a stack of shadowed rows.
    /// `shadowed: false` for a source-skinned row. §61's mechanic is that a
    /// RUN casts one silhouette because its middle rows are gapless and their
    /// shadows fall on an identical fill — a skinned row is always `.only`, so
    /// every row in the feed would cast its own, which is both forty offscreen
    /// blurs per screenful on the app's hottest scroll and a lift the colour
    /// has already done: a card that differs from the page in HUE does not
    /// need to differ from it in height as well.
    private func dayCardBackground(_ position: RunPosition,
                                   fill: Color = DS.surfaceSheet,
                                   shadowed: Bool = true) -> some View {
        let r = DS.Radius.card
        let top = position == .first || position == .only
        let bottom = position == .last || position == .only
        return UnevenRoundedRectangle(topLeadingRadius: top ? r : 0,
                                      bottomLeadingRadius: bottom ? r : 0,
                                      bottomTrailingRadius: bottom ? r : 0,
                                      topTrailingRadius: top ? r : 0,
                                      style: .continuous)
            .fill(fill)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, top ? DS.Space.s1 : 0)
            .padding(.bottom, bottom ? DS.Space.s1 : 0)
            .shadow(color: shadowed ? DS.cardShadow : .clear,
                    radius: shadowed ? 18 : 0, x: 0, y: shadowed ? 6 : 0)
    }

    /// Lists are AIR; parcels are for the reads (user ruling 2026-07-22,
    /// superseding the same-day "card is a group" cut). The day card failed
    /// at both extremes — one row wearing a full card was chrome around
    /// nothing, and a GitHub day's dozens made one giant slab — which means
    /// the card was never doing group-work at all: the DAY HEADER is the
    /// grouping. Apple Music is the named model: songs never sit in cards;
    /// surfaces are spent on featured content. So ordinary rows render bare
    /// on the ink, every shape, every run length. What keeps a surface: the
    /// designed-card anatomies (consent card, post, takeaway, fat token row
    /// — cards by anatomy, their surface IS this background) and the head
    /// reads (map, chart, mosaic, lede), which stay §160 parcels.
    ///
    /// `selected` is the keyboard walk's position (Mac, 2026-07-31) and is
    /// painted HERE rather than as a `.background` on the row's content,
    /// because this function already owns row-surface geometry. The first cut
    /// drew its own `RoundedRectangle` at `DS.Radius.widget` inside the row's
    /// `listRowInsets`, which put a smaller, rounder, differently-inset rect
    /// floating inside the card it was meant to be selecting — and mid-run it
    /// could not take the square shoulders a merged run demands, so the
    /// selected row visibly broke the run's silhouette. Inheriting the shape
    /// makes selection a state of the surface instead of a second surface. A
    /// FILL and never a stroke: "no hairlines — zero exceptions" makes an
    /// outline the wrong vocabulary, and `DS.tintDim` is already how this app
    /// says "this one".
    /// The row's card fill when the room mixes sources — nil everywhere else,
    /// and that nil is the ruling rather than an optimization (2026-08-15,
    /// user: "what if each row was a colored card from it's source").
    ///
    /// **Colour here says WHICH SOURCE, so it may only appear where the answer
    /// varies.** In the All room a screenful of hues tells you at a glance what
    /// your day was made of. Inside a source room every row would be the same
    /// hue — a permanent colour that says nothing, which is §297's own argument
    /// for draining the crown pour in exactly that room, and §8's colour law
    /// (identity, state, or nothing) reaching the row surface.
    ///
    /// Guards liveness FIRST, `standsAlone`'s reason verbatim: this is read in
    /// the argument list of the row builder, so it runs before `shapedRow`'s
    /// own guard, and `thing.source` is a stored property that fault-resolves
    /// against the store (corollary 3, build 176).
    /// NIL like its sibling below — see that function's note for the ruling.
    /// Kept (rather than deleted with its call sites) for the same
    /// dormant-not-deleted reason, and because its one historical lesson is
    /// worth the lines: when the rows DID wear colour, the first cut skinned
    /// only `shapedListRow` and missed this path entirely — the bundle and
    /// strip rows are most of what the All room actually draws, and a
    /// feature keyed off "a row" has to reach every row BUILDER, of which
    /// this screen has three.
    func rowSkin(forSource source: String) -> DS.RowSkin? { nil }

    /// NIL, ALWAYS, AND ON PURPOSE (2026-08-15, the user's final ruling of
    /// the colour night: "i now feel like they all looked better solid
    /// black, including the all feed"). The row-colour experiment ran its
    /// full arc in one evening — raw brand fills, a solved uniform register,
    /// a 14% wash — and every strength was worse than the black it replaced,
    /// which is the 2026-07-22 "lists are air" ruling re-earned with three
    /// builds of evidence instead of taste. Rows are content on ink;
    /// provenance is the source name (`legibleInk`) and the icon; the app's
    /// colour budget is spent on ONE bright object per screen (the wallet
    /// hero, the brief's lede card) and on selection.
    ///
    /// The machinery stays (`DS.rowSkin`, the `skin:` plumbing through
    /// `runBackground`) — dormant-not-deleted, because the full arc is
    /// recorded in `computeRowSkin`'s own doc and deleting the plumbing would
    /// orphan that record. DO NOT re-enable without reading it: three
    /// strengths were built, shipped and rejected the same night.
    func rowSkin(_ thing: Thing) -> DS.RowSkin? { nil }

    /// Rooms that hold more than one source. "All" is the one that always
    /// does; Pinboard is selected by `pinnedAt` rather than by source, so it
    /// mixes too. A folded category (Markets) resolves to a real seat before
    /// it reaches here, so it is correctly NOT in this set.
    private var roomMixesSources: Bool {
        source == "All" || source == Pinboard.room
    }

    @ViewBuilder
    func runBackground(_ position: RunPosition, bare: Bool,
                               selected: Bool = false,
                               skin: DS.RowSkin? = nil) -> some View {
        if selected {
            selectionWash(position, bare: bare)
        } else if let skin {
            // A COLOURED ROW IS ALWAYS ITS OWN CARD — the run position is
            // deliberately ignored rather than threaded through. A run's whole
            // mechanic is that middle rows go square and GAPLESS so one
            // silhouette casts one shadow (§61), which is only true while every
            // row in it shares a fill; with a hue per source, a merged run
            // renders as butted stripes of different colours and the shadow
            // falls across the seam. Forcing `.only` here keeps that geometry
            // in the one function that owns it, instead of making five call
            // sites pass a breaker predicate they have no reason to know about.
            dayCardBackground(.only, fill: skin.fill, shadowed: false)
        } else {
            // ROWS ARE BARE AGAIN (prd §749, 2026-09-15, user: "i made a
            // mistake by adding cards to rows i think it makes the app look
            // worse"). §743's per-row plate is withdrawn for every row,
            // cards by anatomy included: the day header groups, the ink is
            // the ground, and the only surface a list row may wear is the
            // Mac walk's selection wash below.
            Color.clear
        }
    }

    /// The walk's position, wearing the run's own corners and insets. A bare
    /// row gets the wash alone; a card row keeps its surface with the wash over
    /// it, so a consent card or a post still reads as the card it is.
    private func selectionWash(_ position: RunPosition, bare: Bool) -> some View {
        // `position` and `bare` are unread since prd §743: the wash takes
        // one `.only` shape and inset. Since §749 there is no plate under
        // it — the row is bare, so the wash is the whole surface.
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(DS.tintDim)
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s1)
    }

    /// The row inside a list section, with the standard list plumbing attached.
    func shapedListRow(_ thing: Thing, index: Int = 0, nextEventID: UUID?,
                               position: RunPosition = .only,
                               imageOnly: Bool = false,
                               wideArt: Bool = false,
                               replies: [String: [Thing]] = [:]) -> some View {
        // AnyView: same metadata-depth insurance as GenRender (crash fix).
        // A Button since 2026-08-04 (the microanimation pass), not an
        // `onTapGesture`: the tap gesture gave no touch-down feedback, so a
        // press read as nothing until the sheet arrived. `RowPress` is the
        // dim-plus-settle a listRowBackground slab allows (its doc explains
        // why not `PressSpring`'s dip). Same single choke point, same one
        // gesture — tap opens the sheet, everything else stays long-press.
        // Zoom source removed with the thing-open zoom (prd 232, 2026-07-30).
        let skin = rowSkin(thing)
        return Button {
            openThing(thing)
        } label: {
            AnyView(shapedRow(thing, nextEventID: nextEventID, index: index,
                              imageOnly: imageOnly, wideArt: wideArt,
                              replies: replies))
                .modifier(rowEntrance(index))
                .contentShape(Rectangle())
                // THE INK FOLLOWS ITS CARD. Every text token in this app is a
                // `Color.adaptive` resolved against the trait, so overriding
                // the scheme for the subtree re-points the WHOLE ramp —
                // primary, secondary, tertiary, glyphs — in one line, instead
                // of teaching a dozen row anatomies about a foreground colour
                // they have never taken. Nil (the neutral fills) keeps the
                // page's own ramp; see `DS.RowSkin.ink`.
                .environment(\.colorScheme, skin?.ink ?? colorScheme)
        }
        .buttonStyle(RowPress())
            // Mac/pointer polish (2026-07-31): the feed rendered bare rows
            // over `onTapGesture` until 2026-08-04 (now the Button above),
            // and this was the one surface a Mac cursor crossed with nothing
            // lighting up. One call, one place — every shape (`shapedRow`'s
            // dozen anatomies) inherits it.
            .dsHover()
            // …and the lift on top of the highlight (Mac delight, 2026-08-03,
            // user: "I like the rows lifting and shadow deepening"): the row
            // rises 1pt with a deepened shadow under the cursor. Same one
            // call site, so every row anatomy inherits it; compiles away off
            // Catalyst.
            .macHoverLift()
            // V3b (2026-07-07, supersedes the kind-color wash): rows are
            // NEUTRAL cards — the translucent kind wash read as murk. Color
            // moved into the tag text: the project's own stable hue.
            // `walkSelected` is only ever written on Mac, and `DS.isMac`
            // short-circuits ahead of the comparison — so no phone row ever
            // observes it (see `ShellChrome.canWalk`).
            .listRowBackground(runBackground(position, bare: !standsAlone(thing),
                                             selected: DS.isMac
                                                && chrome.walkSelected == thing.id.uuidString,
                                             skin: skin))
            // Feed rhythm: `rowAir` (prd §900, see its doc). A card that
            // stands alone keeps s2 — it has no padding of its own inside.
            .listRowInsets(.init(top: standsAlone(thing) ? DS.Space.s2 : Self.rowAir,
                                 leading: DSRoomChassis.rowInset,
                                 bottom: standsAlone(thing) ? DS.Space.s2 : Self.rowAir,
                                 trailing: DSRoomChassis.rowInset))
            .listRowSeparator(.hidden)
            // A row is draggable OUT of the window on Mac (prd §631) — its
            // link where it has one, its words otherwise. `macRowDrag` is
            // `self` everywhere else, and its doc records why touch is a
            // deliberate omission rather than an oversight.
            .macRowDrag(thing)
            // One gesture, one meaning: TAP opens the sheet — tags and verbs
            // live there. The row's OTHER verbs ride a long-press (ruling
            // 2026-07-16, supersedes the both-edge swipe of 2026-07-15): the
            // feed pages between sources now, and a horizontal pan can only
            // belong to one thing. Measured before ruling — a `TabView(.page)`
            // pan claims 100% of horizontal drags, at every drag length, even
            // at the last page where it merely rubber-bands and the row still
            // never opens. So the swipe wasn't degraded, it was unreachable;
            // long-press is what's left, and it's what the Home board has used
            // for Open/Unpin all along (`GenRenderer.pinnedRowActions`).
            .contextMenu {
                // THE MENU IS BUILT WHEN IT RISES, NOT WHEN THE ROW DOES (PERF
                // 2026-09-09, user: "it's not great on scrolling"; prd §661).
                // `contextMenu(menuItems:)` takes a NON-ESCAPING builder, so
                // everything once written inline here ran on every row body
                // build — and the first thing it did was
                // `VerbDerivation.verbs(for:)`, which reads `thing.content`.
                // The All room's query leaves that column unfetched on
                // purpose (`lightColumns`), so every row that scrolled into
                // view paid a SwiftData fault and an `NSDataDetector` pass on
                // the main thread, inside the scroll, to fill a menu nobody
                // had pressed. `perf-spec.md` P3 named it first and declined
                // to memoise it. A View's body is lazy — `RowVerbMenu` holds
                // the thing and derives when the press raises it — so this is
                // work that no longer runs, not a cache over it.
                RowVerbMenu(thing: thing, room: source, run: { run($0, on: $1) }, onDelete: askDeleteNote,
                            onFile: fileThing, onNewFolder: { folderPrompt = .make(filing: $0) })
            } preview: {
                // What the band could not fit (prd §412a) — the full title, the
                // picture at a size worth looking at, the opening words. Until
                // this landed the menu had no `preview:` at all, so the system
                // lifted a snapshot of the 44pt row: a bigger copy of what your
                // finger was already on. `RowPeek` is one stored property, so
                // building it per visible row is free; its body — which is what
                // touches `content` and `previewImageData` — runs only when a
                // press actually raises it.
                RowPeek(thing: thing)
            }
    }

    /// One row in any of the seven post rooms (2026-08-26, prd §489).
    ///
    /// The anatomy is `SocialRoom.rowKind`'s answer and nothing else — this
    /// function has no rules of its own, and that is the contract. Adding a
    /// branch here re-opens the drift the table closed: the rule belongs in
    /// `SocialRoom`, where a harness can reach it and where `standsAlone` reads
    /// the same answer.
    ///
    /// `thing` is already liveness-guarded by `shapedRow`, which is the only
    /// caller.
    @ViewBuilder
    private func socialRow(_ thing: Thing, replies: [String: [Thing]],
                           index: Int, nextEventID: UUID?,
                           imageOnly: Bool, wideArt: Bool) -> some View {
        let kids = replies[thing.id.uuidString] ?? []
        switch SocialRoomSource.rowKind(thing, hasReplies: !kids.isEmpty) {
        case .band:
            BandRow(thing: thing,
                    emphasized: thing.id == nextEventID,
                    live: false,
                    imageOnly: imageOnly,
                    wideArt: wideArt)
        case .excerpt(let lines):
            ExcerptRow(thing: thing, lines: lines)
        case .reading:
            ReadingRow(thing: thing)
        case .post(let whole):
            PostCard(thing: thing, whole: whole)
        case .thread(let whole):
            SocialThreadCard(head: thing, replies: kids, whole: whole)
        }
    }

    @ViewBuilder
    private func shapedRow(_ thing: Thing, nextEventID: UUID?, index: Int = 0,
                           imageOnly: Bool = false,
                           wideArt: Bool = false,
                           replies: [String: [Thing]] = [:]) -> some View {
        // Dead-model guard first (corollary 3, build 176 — see
        // `ThingRowKeying`). This is where build 176 trapped: `thing.kind`,
        // one frame after a heal deleted the row, reached from a correctly
        // KEYED `ForEach` whose content closure SwiftUI re-ran against the
        // array it still held. Callers guard too — reads in their argument
        // lists happen before this line — but the funnel guards itself so a
        // future caller can't reintroduce the same crash. Costs no view-tree
        // depth: it is another arm of a `@ViewBuilder` chain that already
        // branches here.
        if !thing.isLive {
            EmptyView()
        // Approval is the one rhythm-breaker everywhere: the consent card.
        } else if thing.kind == .approval, thing.mark != .done {
            ApprovalCard(thing: thing,
                         onApprove: { perform(Verb(label: "Approve", icon: "checkmark.circle", action: .approve), on: thing) },
                         onDeny: { perform(Verb(label: "Deny", icon: "xmark.circle", action: .deny), on: thing) })
        } else {
            // B2b (ruling 2026-07-06): ONE row anatomy — the band — for every
            // kind and every shape. The wash carries the kind; per-kind row
            // shapes retired. One earned exception: the doing chat takeaway.
            // Reminders are the band too — read-only (ruling 2026-07-25), so
            // no check circle: a done reminder is just struck through, its
            // state grouped by section, never a control that does nothing.
            switch rowShape(thing) {
            case .calendar:  BandRow(thing: thing, emphasized: thing.id == nextEventID)
            case .reminders: BandRow(thing: thing)
            // A CardPointers offer is three facts, not one (prd §487): who it
            // is with, what it gives, and when it runs out. `BandRow` could
            // draw one of them — the title — and did, while the terms sat on
            // `summary` (which it never reads) and the deadline on `dueAt`
            // (which only the head drew, for a single offer). `WalletRow` is
            // the app's three-slot anatomy and already the shape the wallet's
            // own "Coming up" deadlines wear, which is what these rows are.
            //
            // The mark is the CARD's initials, and that is what paid for
            // deleting the head's card-by-card tally: the grouping it counted
            // is legible down the left edge of the room instead. Never
            // `AssetMark` — this app bundles no card artwork, and matching
            // "Amex Gold" against a token brand would put somebody else's logo
            // on their credit card.
            //
            // Bare, with no tap of its own: `shapedListRow` already wraps every
            // row in the single Button that opens the sheet, and a second one
            // here would be a button inside a button.
            case .cardPointers:
                // ONE ANATOMY (prd §744): the card's initials at the 26pt lead,
                // not `WalletRow`'s 36, so this room's column matches every other.
                DSFeedRow(name: CardPointers.merchant(title: thing.title,
                                                      card: thing.authorHandle),
                          // Their words for what the offer gives, never a
                          // number we made (§420's no-total refusal, on the row
                          // this time).
                          line: DSFeed.line(thing.summary)) {
                    WalletMarkView(mark: CardPointers.initials(card: thing.authorHandle).isEmpty
                                     ? .kind(thing.kind)
                                     : .monogram(CardPointers.initials(card: thing.authorHandle),
                                                 tint: DS.textSecondary),
                                   size: DS.Mark.row)
                } trailing: {
                    if let due = thing.dueAt {
                        Text(FeedLedeFace.dueLine(due))
                            .dsText(.subhead12)
                            .foregroundStyle(FeedLedeFace.isOverdue(due)
                                             ? DS.attentionInk : DS.textTertiary)
                    }
                }
            case .music:     MusicRow(thing: thing)
            // The medium's own proportions (prd §219) — a still arrives as a
            // still, a Steam header as a capsule, a pin as a pin. One row
            // height across all of them, so the feed keeps a single rhythm.
            case .media where MediaShape.art(for: thing.source) != nil:
                MediaRow(thing: thing,
                         art: MediaShape.art(for: thing.source) ?? .cover,
                         live: isLive(thing))
            case .chat where thing.mark == .doing:
                TakeawayCard(thing: thing)
            // Native anatomies (2026-07-13): in its own room a note leads
            // with its text, a conversation with its opening line, a post
            // with its author and media, a link with where it's from. All
            // keeps the band — these relax only inside the source's shape.
            // The wallet room reads as a ledger (prd §157): the band, with the
            // moved amount pulled out of the sentence into a right-aligned
            // figure. Same anatomy as every other row — one opt-in flag.
            // An app wallet folded into the Wallet (prd §1048, step 4) keeps
            // its own row: its logo, when it was last used, what it holds.
            case .wallet where thing.sourceRef?.hasPrefix(PrivyHomeFeed.refPrefix) == true:
                PrivyAppRow(thing: thing)
            case .wallet: BandRow(thing: thing, moneyColumn: true, rippleIndex: index)
            // The same ledger reading for the wallet-riding money rooms
            // (prd §485, 2026-08-26) — one flag, one anatomy. See `Shape.init`.
            case .ledger: BandRow(thing: thing, moneyColumn: true, rippleIndex: index)
            case .notes:  ExcerptRow(thing: thing, lines: 3)
            case .chat:   ExcerptRow(thing: thing, lines: 2)
            // THE SEVEN POST ROOMS, ONE BRANCH (2026-08-26, prd §489).
            //
            // This was five hand-rolled branches — `.social`, `.x`,
            // `.telegram`, `.instagram`, and `.plain` standing in for TikTok
            // and Nostr because neither had a case at all — each re-spelling
            // the same four decisions in its own dialect. The rules moved to
            // `SocialRoom.rowKind`, which is Foundation-only and therefore the
            // first time any of them can be compiled and mutation-proved by a
            // harness; nothing inside this file could ever be reached by one.
            //
            // Every row's own reasoning travelled with it — a follower is a
            // person, a comment is not a post, an archive draws its words
            // whole — and is now written once in `SocialRoom` beside the source
            // it governs, rather than four times in four places that agreed
            // only by accident.
            case .social, .x, .telegram, .instagram, .tiktok:
                socialRow(thing, replies: replies, index: index,
                          nextEventID: nextEventID,
                          imageOnly: imageOnly, wideArt: wideArt)
            case .appStoreConnect:
                if thing.tags.contains("Review") {
                    AppReviewRow(thing: thing)
                } else {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                }
            case .cursor:
                // Our own note about the sync keeps its plain band, the way
                // the X room treats its own — it is not a run.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else {
                    CursorRow(thing: thing)
                }
            case .walletbeat:
                // Three shapes in one room: a watched wallet is a standing report
                // card, an incident and a revision are dated news, and our own note
                // about the sync keeps its plain band the way every other room does.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else if WalletbeatWatch.isWatchRef(thing.sourceRef) {
                    WalletbeatWalletRow(thing: thing)
                } else {
                    WalletbeatNewsRow(thing: thing,
                                      watchedWallets: walletbeatWatchedIDs)
                }
            case .l2beat:
                // Three shapes in one room: a watched chain is a standing assessment,
                // a milestone and a revision are dated news, and our own note about
                // the sync keeps its plain band the way every other room does.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else if L2beatWatch.isChainRef(thing.sourceRef) {
                    L2beatChainRow(thing: thing)
                } else {
                    L2beatNewsRow(thing: thing, watchedChains: l2beatWatchedIDs)
                }
            case .bookmarks: ReadingRow(thing: thing)
            default:
                // Perishables show their clock everywhere (ruling 2026-07-09):
                // the next event's countdown and a stream's Live state ride
                // the row in All too, not just in their source's shape. A
                // watched token whose pulse has landed wears the fat anatomy
                // (TokenRow, prd §102) everywhere too; until it lands, the
                // plain band + timestamp — never a faked price.
                if let pulse = TokenPulse.shared.pulse(for: thing) {
                    TokenRow(thing: thing, pulse: pulse)
                } else if let symbol = StockWatch.symbol(of: thing) {
                    // A stock watched in Markets: a pack's row, on Nasdaq's
                    // quote (`CompanyQuotes`), read when the row appears and
                    // held ten minutes. Values only — the leaf holds no
                    // `Thing`, so it needs no liveness guard of its own.
                    let company = CompanyPacks.Company(name: TokensAsk.name(of: thing.title),
                                                       listing: .stock(symbol),
                                                       seats: [TokenWatch.source])
                    CompanyRow(company: company,
                               quote: CompanyQuotes.shared.quote(company.listing),
                               imageURL: thing.previewImageURL)
                        .task(id: symbol) { await CompanyQuotes.shared.load([company]) }
                } else if thing.sourceRef?.hasPrefix(PrivyHomeFeed.refPrefix) == true {
                    // An app wallet (prd §803e): its own logo, when it was last
                    // used, and what it holds — in the room and in All alike.
                    PrivyAppRow(thing: thing)
                } else if thing.sourceRef?.hasPrefix(PrivyHomeFeed.txPrefix) == true {
                    // What moved in an app wallet (prd §803f): the wallet
                    // room's money column, under the app's own logo.
                    BandRow(thing: thing, moneyColumn: true)
                } else {
                    // The source badge (2026-08-09): a CROSS-SOURCE room asks
                    // for it, a single-source room doesn't — there the room
                    // itself already says the source and a badge would
                    // double-tell it. `.all` is this same `default` arm's
                    // OTHER tenant (a single-source room with no shape case of
                    // its own, e.g. Instagram/TikTok, falls here too as
                    // `.plain`), which is why the test is on the room and not
                    // on the row.
                    //
                    // The pinned room is the second cross-source room and was
                    // missing from this test (user ruling 2026-08-11: "pinned
                    // rows definitely need a source badge"). It renders as
                    // `.plain` — "Pinned" is not a source, so `Shape` has
                    // nothing to match and every row lands in this arm — so it
                    // read as a single-source room to the one line that
                    // decides this, and a pinned note sat next to a pinned
                    // import row with nothing on either saying where it came
                    // from. It is in fact the room where the badge matters
                    // MOST: All is at least chronological, so a row's
                    // neighbours date it, while this list is ordered by when
                    // you pinned and its rows can come from anywhere.
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: isLive(thing),
                            // The Notes room has no day dividers, so the
                            // row carries its own time (prd §969).
                            stamp: Pinboard.isPinnedRoom(source) ? Pinboard.stamp(thing) : nil,
                            // What a note of yours says (prd §983).
                            notePreview: Pinboard.isPinnedRoom(source) && Pinboard.isNote(thing),
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                }
            }
        }
    }
}

/// The compact Feed treemap — 5 cells, areas "a a b c / a a d e", 140pt tall,

/// A feed row's long-press verbs, derived when the menu RISES (PERF
/// 2026-09-09, prd §661).
///
/// This body used to be the inline content of `shapedListRow`'s
/// `.contextMenu`, and that builder is non-escaping: SwiftUI evaluates it
/// while the ROW is built, so the verb derivation — a `content` fault in the
/// All room plus a detector pass — ran per row per body evaluation, for a menu
/// that is raised on a fraction of rows. A View's body runs when the view is
/// drawn, and a menu's content is drawn when the menu is; nothing here costs
/// the scroll anything.
///
/// The verbs are derived ONCE for the whole menu, as before. READS ONLY, which
/// the swipe ruling settled and this menu inherits: writes confirm in the
/// sheet, Copy is sheet-only, and Approve/Deny are consent — a consent action
/// fired from a right-click menu is the one-slip yes S10 exists to prevent.
/// Pin is the stated exception (2026-08-10): it reaches no network, tells no
/// service, its undo is the identical gesture on the identical row, and the
/// long-press is the only verb surface a row has.
///
/// Guarded on `isLive` at the top of the body, like `ThingShareLink` below
/// it: a menu can be up when a heal's delete lands, and SwiftUI re-evaluates
/// a leaf's body on the model's own observation (liveness corollary 5).
struct RowVerbMenu: View {
    let thing: Thing
    /// The room the row is drawn in — the `perfAccum` bracket only. The rooms
    /// differ in the one way that matters: All faults `content` per row, a
    /// source room has it hydrated already.
    let room: String
    let run: (Verb, Thing) -> Void
    /// Asks to delete a note of yours (user: "i don't see a way to delete a
    /// note … long press to delete"). The screen raises the confirmation: a
    /// menu item's content is gone once it fires, and a delete reaches every
    /// device through iCloud, so it is never one slip away.
    var onDelete: ((Thing) -> Void)? = nil
    /// Files the row in a folder, or unfiles it with nil (prd §980) — any
    /// row in the Notes room, a pin as much as a note.
    var onFile: ((Thing, String?) -> Void)? = nil
    /// Asks for a new folder's name, then files the row in it.
    var onNewFolder: ((Thing) -> Void)? = nil
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if thing.isLive { menu }
    }

    @ViewBuilder private var menu: some View {
        // A NOTE OF YOURS HOLDS FIVE (prd §983): Pin, Move to folder, Lock,
        // Share, Delete — the note's own sheet keeps only Share, Lock and
        // Edit, and Copy and Translate are the system's on selected words.
        // Nothing to open in another app, so no Open in app either.
        let note = Pinboard.isNote(thing)
        let verbs = note ? [] : perfAccum("rowVerbs[\(room)]") {
            VerbDerivation.verbs(for: thing)
        }
        if let openVerb = verbs.first(where: {
            if case .openURL = $0.action { return true } else { return false }
        }) {
            Button {
                run(openVerb, thing)
            } label: {
                Label("Open in app", systemImage: "arrow.up.right")
            }
        }
        // The row's OTHER derived reads (2026-07-31): Translate is a read over
        // the thing's own text, and this menu is the only place a row can
        // reach it.
        if let translate = verbs.first(where: {
            if case .translate = $0.action { return true } else { return false }
        }) {
            Button {
                run(translate, thing)
            } label: {
                Label(translate.label, systemImage: translate.icon)
            }
        }
        Button {
            let pinned = Pinboard.toggle(thing)
            // Saved now, as filing is: a pin left to autosave was lost when
            // the app closed within seconds of it.
            modelContext.saveHonestly()
            chrome.pinPulse += 1
            DSHaptic.tap()
            chrome.flash(pinned ? String(localized: "Pinned")
                                : String(localized: "Unpinned"))
        } label: {
            Label(Pinboard.isPinned(thing) ? "Unpin" : "Pin",
                  systemImage: Pinboard.isPinned(thing) ? "pin.slash" : "pin")
        }
        if !note {
            ThingShareLink(thing: thing) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        // Anything the Notes room holds files (user: "anything in the
        // room"); one folder at most, so a pick MOVES it. Built when the
        // press raises the menu (§661), so the store read is not per row.
        if let onFile, Pinboard.inRoom(thing) {
            let current = thing.folder
            Menu {
                ForEach(NoteFolderName.list(stored: NoteFolderStore.shared.names,
                                            filed: [current]), id: \.self) { name in
                    Button {
                        onFile(thing, name)
                    } label: {
                        if current.map(NoteFolderName.key) == NoteFolderName.key(name) {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: name)
                        }
                    }
                }
                if let onNewFolder {
                    Button {
                        onNewFolder(thing)
                    } label: {
                        Label("New folder…", systemImage: "folder.badge.plus")
                    }
                }
                if current != nil {
                    Button {
                        onFile(thing, nil)
                    } label: {
                        Label("Remove from folder", systemImage: "folder.badge.minus")
                    }
                }
            } label: {
                Label("Move to folder", systemImage: "folder")
            }
        }
        // Lock a note of yours (prd §982): the person's own write over their
        // own note, reaching nothing outside the app and undone by Remove
        // lock on its sheet — which is what makes it legal in this menu.
        if NoteLock.canLock(thing) {
            Button {
                chrome.lockNote(thing, context: modelContext)
            } label: {
                Label("Lock", systemImage: "lock")
            }
        }
        if note {
            ThingShareLink(thing: thing) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        // Only a note of yours: a bridge's row would land again on its next
        // sweep, so deleting it here would be a control that does not hold.
        if let onDelete, Pinboard.isNote(thing) {
            Button(role: .destructive) {
                onDelete(thing)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Rows arrive the way their shape moves (ruling 2026-07-07): a per-shape
/// offset/scale revealed with a small stagger, replayed when the chip
/// changes. One animation per moment — this IS the shape's moment.
struct RowEntrance: ViewModifier {
    struct Style {
        var dx: CGFloat
        var dy: CGFloat
        var scale: CGFloat
        var step: Double
    }

    let index: Int
    let wave: Int
    let style: Style
    /// Skip the stagger and appear at rest (PERF 2026-09-04, prd §600).
    ///
    /// A room change is a REMOUNT (§265's `.id(filter.source)`), so every swipe
    /// played this cascade on the first thirteen rows — thirteen animation
    /// transactions, each with its own delay — *inside* the frames the page's
    /// own move transition needed. Two motions on one row, competing for the
    /// same main actor.
    ///
    /// It is also a design point, not only a cost: the row is already arriving,
    /// carried by the page it sits on. Lifting it again on top of that is the
    /// second animation on one moment that this file's own rule ("one animation
    /// per moment — this IS the shape's moment") exists to forbid.
    ///
    /// Scoped to the swipe alone. A scroll into a new row and a room entered
    /// from a chip tap while standing still both keep the entrance, because
    /// there is no page move underneath them to carry the row in.
    var instant: Bool = false
    /// When the wave this row belongs to began — `FeedScreen.shapeWaveAt`,
    /// stamped at the screen's mount and beside every `shapeWave` bump (PERF
    /// 2026-09-09, user: "it's not great on scrolling"; prd §661).
    ///
    /// The stagger is `min(index, 12) × step`, and a row deep in a room never
    /// has an index under twelve — so every row that SCROLLED into view sat
    /// invisible for the whole cascade's length (0.34s at the default step,
    /// 0.54s in the calendar) before its fade even began, and the room's
    /// content arrived a third of a second behind the finger on every flick,
    /// for as long as the room was scrolled. The cascade is the ROOM's
    /// arrival; a row met by scrolling arrives at rest. Past `cascadeWindow`
    /// from the wave, `reveal()` sets `shown` with no animation at all — not a
    /// delay of zero, which would still run three animated modifiers per
    /// entering row for the length of the scroll, on the main actor (the
    /// BerryRain lesson, one row at a time).
    ///
    /// Nil means no window: the entrances outside the feed (a shelf card's
    /// section) are not scrolled into by the row they decorate.
    var waveAt: TimeInterval? = nil
    /// Longer than the longest cascade (12 × 0.045 + `DS.Motion.standard`),
    /// shorter than any scroll that reaches a thirteenth row.
    static let cascadeWindow: TimeInterval = 1.0
    @State private var shown = false
    /// Added 2026-08-04 (prd §299). This is the entrance EVERY feed row in the
    /// app wears, and it ignored Reduce Motion from the day it shipped —
    /// exactly the gap `SettleIn` had, found by the same audit on the same day.
    /// A person who has asked the system for less motion was getting a fully
    /// staggered offset-and-scale cascade on every scroll into a new room.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : style.dx, y: shown ? 0 : style.dy)
            .scaleEffect(shown ? 1 : style.scale)
            .onAppear { reveal() }
            .onChange(of: wave) {
                shown = false
                reveal()
            }
    }

    private func reveal() {
        // `instant` is checked beside `reduceMotion` rather than replacing it:
        // both mean "arrive at rest", and the Reduce Motion path must keep
        // working whether or not a swipe is in flight.
        guard !reduceMotion, !instant else { shown = true; return }
        // A row met by scrolling, after the room's cascade — see `waveAt`.
        if let waveAt, Date.timeIntervalSinceReferenceDate - waveAt >= Self.cascadeWindow { shown = true; return }
        withAnimation(DS.Motion.standard.delay(Double(min(index, 12)) * style.step)) {
            shown = true
        }
    }
}
