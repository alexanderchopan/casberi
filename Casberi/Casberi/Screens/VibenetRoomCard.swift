import SwiftUI

/// THE VIBENET ROOM'S HEAD — the `AppStoreConnectRoomCard` shape exactly
/// (2026-08-23), and the reasoning is the same one: several watched
/// accounts are NOT mergeable the way a wallet balance is (one being
/// locked says nothing about another's key count), the same way several
/// App Store Connect apps aren't (one being rejected says nothing about
/// another's build). ASC's answer, reused whole: ONE surfaced card, a
/// LEAD promoted to the headline (`VibenetRoom.lead`, the most urgent
/// account — `ordered` already ranks locked-first), everyone else as a
/// compact row beneath it, a quiet provenance note at the bottom.
///
/// **This is what makes "All" and "one account scoped" the same code
/// path, not two.** When the rail (`VibenetScopeRail`) narrows
/// `room.items` to a single address, `drawn.count` becomes 1, so the
/// "rows beyond the lead" block has nothing left to draw — the card
/// collapses to just that account's own headline, automatically. Wallet's
/// own crown does the same thing (a merged reading when unscoped, that
/// one wallet's own reading when scoped) for the same "click all you see
/// all, click one you see one" reason.
///
/// Superseded, in order: the R3.2 anatomy (a headline sentence + hero face
/// stack + flat row list, all rolled up into one paragraph — the shape
/// that read as a contradiction the moment the hero drew every face while
/// the sentence counted only the locked ones), and R4.6's own first draft
/// (N independently-`.dsWidgetSurface()`-boxed cards, one per account,
/// always all present regardless of scope — which fought the room's own
/// floating settings gear for want of a shared surface for it to sit on,
/// and touched the screen edge because nothing gave it the cards' own
/// margin). Both are gone; this is the third and, per the ASC precedent
/// this was measured against, the last shape this card should need.
///
/// A row's tap OPENS `VibenetAccountSheet` (R3.2) — the card stays a
/// summary; the matrix, the history strip, the sync line and the
/// Explorer door all live on the real surface that has room for them.
///
/// Stores no `Thing` — only value types out of `VibenetRoom`. Corollary 5
/// has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
///
/// A ROOM-WIDE KEY SUMMARY, added 2026-08-24: no way to see how many keys
/// you're responsible for in TOTAL across the whole room
/// (`VibenetKeyAggregation.compose`) — only per account. Draws ONLY in the
/// roster shape (`room.items.count > 1`), beneath the accounts, with the
/// same "silent when empty" rule as everything else on this card: a room
/// with no keys at all says nothing rather than drawing an empty section
/// (§83). A DELEGATE-MAPPING section briefly lived here too, the same day —
/// see the paragraph below for why it moved off this card entirely.
///
/// **THE ROSTER'S TAP BEHAVIOR WAS WRONG, AND IT WAS WRONG BECAUSE IT
/// MISREAD WHAT WALLET ACTUALLY DOES (fixed 2026-08-24).** Every roster row
/// opened `VibenetAccountSheet` on a tap, modeled on the false premise that
/// Wallet's own unscoped "All" room has an equivalent per-wallet detail
/// view reachable from a tap. It doesn't: Wallet's unscoped room has ZERO
/// tap-to-open-detail rows anywhere. Per-wallet identity shows up in
/// exactly two places, both of which only SCOPE the room in place —
/// `WalletScopeRail` pinned above it, and `WalletFaceChips`
/// (`Screens/WalletFeedTiles.swift`) inside the balance card itself, a
/// horizontal strip of face+reading capsules whose tap sets `selectedWallet`
/// and nothing else. The ONE place a real per-wallet detail view exists is
/// `AddressCard`, reached only from the separate Address Book screen
/// (`WalletScreen.swift`) — a screen dedicated to MANAGING watched wallets,
/// never the feed room.
///
/// So the roster here forks on `onOpen`. Non-nil (`VibenetScreen`'s own
/// roster — the correct analog of Wallet's Address Book) keeps today's full
/// navigable rows unchanged. Nil (the feed room) does NOT navigate.
///
/// **THE FIRST CUT OF THE FEED-ROOM SIDE COPIED `WalletFaceChips` TOO
/// LITERALLY, AND WAS CORRECTED THE SAME DAY.** A face-per-account chip
/// strip is genuinely right for Wallet — but `VibenetScopeRail` is PINNED
/// directly above this very card, already showing every watched account's
/// face, and a second face inside the card read as the same avatar twice.
/// User: *"that is kinda weird to see the avatars because they will
/// literally be in the row above… i think what we want to say on the all
/// page is perhaps N accounts and balance, then the keys, then the
/// events."* So the feed room draws NO face at all: a plain stat block
/// (a native-balance crown over its own chart, plus per-symbol token
/// totals — `balanceCard`/`holdingsCard` since §467 split them onto
/// separate surfaces) stands in for the chip strip, and the mapping
/// section that briefly lived on this card moved OFF it entirely, onto
/// `VibenetAccountDetail`'s own hub diagram — the user settled on "N
/// accounts and balance, then keys, then events" as the COMPLETE list for
/// this room, having floated a room-wide relationship list and talked
/// themselves back out of it ("those show on the individual account
/// page"). Scoping still does the "same cards, just narrowed" job Wallet's
/// own scoped room does (see the doc a few lines up: room.items.count == 1
/// collapses this very card to `VibenetAccountDetail` automatically,
/// mapping and all) — a face in `VibenetScopeRail`, pinned above this
/// card, is the one door to that (2026-08-25, prd §469: this file's own
/// `onScope` closure was found unreached and deleted rather than restored,
/// since the rail already puts every account one tap away — a second door
/// to a destination the rail already reaches is not a door worth adding).
struct VibenetRoomCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// The room's balance readings — the sparkline's only source, and REAL:
    /// recorded by every composed read, never a demo-only curve.
    private var history: [VibenetValueSample] { VibenetValueStore.samples() }
    let room: VibenetRoom
    var onRemove: (String) -> Void
    /// Raised by the context menu's "Name this account…" — the alert itself
    /// lives on the SCREEN (a text-entry alert needs `@State` a card
    /// re-composed from a value type shouldn't own), so this just reports
    /// which address was asked for.
    var onRename: (String) -> Void = { _ in }
    /// nil in the FEED room — a roster row must never navigate there (see
    /// this type's own header doc), so the whole roster draws as a plain
    /// stat block instead (`stackedRoom`'s cards, no faces, no
    /// per-account rows). Non-nil in `VibenetScreen`'s OWN roster, the
    /// correct analog of Wallet's Address Book, where a tap opens
    /// `VibenetAccountSheet` exactly as before — the sheet's item is the
    /// address itself (the `L2beatScreen`/`WalletbeatScreen` shape:
    /// `String` is `Identifiable`, so no wrapper type is needed).
    var onOpen: ((String) -> Void)? = nil
    /// `onScope` IS GONE (2026-08-25, prd §469, user ruling). It once fired
    /// from a tappable soonest-expiry callout, silently unwired by `afda3c10`
    /// when the card's anatomy was rebuilt; `FeedScreen` went on passing a
    /// real closure into a prop nothing called — dead API that reads as
    /// wired end-to-end. Deleted rather than restored, on the user's own
    /// reasoning: `VibenetScopeRail` is pinned directly above this card in
    /// the only context that closure served, and its faces already scope to
    /// any account with the same toggle-back-to-All rule — "the user is
    /// moving through doors to different accounts instead of using the
    /// source avatars for the accounts above it? that seems like not
    /// needed." A second door to a destination the rail already reaches.
    /// Opens the key tray — which keys are in which permission category
    /// (prd §468, `VibenetKeyTraySheet`). nil where there is nowhere to
    /// present it, and the chevron is gated on the same nil rather than drawn
    /// unconditionally: this card's own comment has said since 2026-08-24 that
    /// a chevron pointing at a tray that does not exist is the dead control
    /// §83 bans, and that is just as true of a caller who cannot present one.
    ///
    /// A CLOSURE, never a `.sheet` of this card's own: this card lives inside
    /// `FeedScreen`'s List rows, and a `.sheet` on a row resolves to the same
    /// presenting controller as the screen's own — the half-open-then-close
    /// bug (ruling 2026-07-28, paid three times).
    ///
    /// TAKES A PERMISSION LABEL (2026-08-25, prd §471). nil opens the whole
    /// tray, which is the headline's own door and what this closure has
    /// always done; a label opens it focused on that permission's section,
    /// which is what a census row's chevron promises. The label is
    /// `VibenetPolicyCount.label`, i.e. `VibenetTraySection.id` — the tray
    /// mirrors `VibenetPolicyAggregation.compose` exactly (its own stated
    /// invariant), so a label from the card always resolves to a section in
    /// the tray and neither side needs a second vocabulary.
    var onOpenKeys: ((String?) -> Void)? = nil

    /// What moved since this device last looked at these keys — captured
    /// ONCE when the roster appears and then immediately spent (`advance`),
    /// so the marker survives the draw it was computed for and is gone by the
    /// next one. Reading and marking-as-read are two acts; computing this in
    /// the body instead would erase the answer while it was being shown.
    @State private var keyChanges: VibenetKeyChanges?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")
    /// The most rows drawn before the footnote takes over, INCLUDING the
    /// lead — the `StripeRoom`/`ASCRoom` cap shape, so a long watch list
    /// doesn't turn this into an unbounded list on a card meant to be a
    /// summary.
    private static let rowCap = 8

    private var drawn: [VibenetAccountItem] { Array(room.items.prefix(Self.rowCap)) }

    /// R4.7 (2026-08-23), reported: *"the details about the account (eg
    /// the keys) should be on a card. everything a user needs to see
    /// about this account should be present on this screen, not on some
    /// other screen… think like how we do wallet today — we have many
    /// cards and then transaction history."*
    ///
    /// So: the moment the room narrows to EXACTLY ONE account — either
    /// because the rail scoped it there, or because that's simply the
    /// only account watched — the card draws its FULL detail
    /// (`VibenetAccountDetail`: face, name, state, the real key roster,
    /// history, sync, the Explorer/Copy doors) instead of a one-line
    /// teaser you would otherwise have had to tap through to a second
    /// screen to read. That teaser survives only for the roster case
    /// (several accounts on screen at once, where one line each is the
    /// most any of them can have) — the shape "All" already had, just
    /// with the lead promoted instead of stacked into a single sentence.
    var body: some View {
        Group {
            if stacksIntoCards {
                stackedRoom
            } else {
                oneSurface
            }
        }
        // The one-account detail carries its own doors and history — its
        // remaining verbs (rename, stop watching) live on a long-press,
        // matching the roster row's own contextMenu below rather than
        // adding a second visible control competing with `RoomGear` for
        // the same corner.
        .modifier(VibenetDetailContextMenu(
            address: room.items.count == 1 ? room.lead?.address : nil,
            onRename: onRename, onRemove: onRemove))
        // READ THE LEDGER, THEN SPEND IT — in that order, and both inside one
        // task, so the answer survives exactly the draw it was computed for.
        // Keyed on the roster's own fingerprint rather than firing once:
        // a read landing while the room is open really is a new look, and a
        // card that captured its answer at mount would go on saying "2 keys
        // new" about a roster that has since changed underneath it.
        .task(id: Self.rosterFingerprint(room.items)) {
            keyChanges = VibenetKeysSeen.changes(in: room.items)
            VibenetKeysSeen.advance(room.items)
        }
    }

    /// A stable, cheap identity for "which keys are on screen right now" —
    /// `.task(id:)` wants something `Equatable` and `[VibenetAccountItem]`
    /// carries histories, balances and policy uses that change on every
    /// composed read without any KEY having moved. Fingerprinting the key ids
    /// alone means a balance ticking over does not re-fire the ledger and
    /// erase a marker somebody is still reading.
    private static func rosterFingerprint(_ items: [VibenetAccountItem]) -> String {
        items.flatMap { item in
            item.actors.map { VibenetKeySeenDiff.keyID(address: item.address, actorId: $0.actorId) }
        }
        .sorted()
        .joined(separator: ",")
    }

    /// **THE FEED ROOM IS SEVERAL CARDS, NOT ONE (prd §467, 2026-08-25 —
    /// direction B of three the user picked from).**
    ///
    /// It was one `dsWidgetSurface` wrapping a crown, a chart, a holdings
    /// block, six permission rows, a delegate spine and a provenance note.
    /// Reported as "some hodge podge put together view… we need more
    /// separation between things, needs to look less jumbled", and the
    /// diagnosis is in the container rather than in any of its contents:
    /// six unrelated readings inside one box read as one object that will
    /// not parse, however well each is drawn.
    ///
    /// So the box is what changes. Each reading gets its OWN surface with
    /// real air between them — separation by surface, which is the
    /// direction chosen over separation by space (no cards at all) and by
    /// tap (three summary rows that open their own screens). One card, one
    /// job, one header.
    ///
    /// Scoped to the feed room's aggregate shape ONLY: `VibenetScreen`'s
    /// roster (`onOpen != nil`) is a management list where one surface is
    /// right, and the single-account branch hands off to
    /// `VibenetAccountDetail`, which owns its own anatomy.
    private var stacksIntoCards: Bool {
        onOpen == nil && room.lead != nil && room.items.count > 1
    }

    @ViewBuilder
    private var stackedRoom: some View {
        // **s6, NOT s3 (2026-08-25, prd §471).** §467 answered "some hodge
        // podge put together view" by giving each reading its own surface,
        // and the surfaces were the right call — but they were stacked 14pt
        // apart, and at that distance two 20pt-radius `surfaceSheet` cards on
        // the page do not read as two objects with air between them, they
        // read as one slab with seams in it. Reported again as "a bit messy
        // and looks unrefined". Separation by surface only works once the gap
        // is wide enough to be seen as a gap; the contents of all four cards
        // are untouched.
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            // **THE HERO IS BARE (2026-08-25, prd §475).** Reported: "the
            // sparkline and balance are in one card in the vibenet room, but
            // in the wallet room neither are in a card."
            //
            // Wallet's own hero carries the ruling in its source
            // (`walletTilesSection`, 2026-08-16): "NO GROUND AT ALL — Apple
            // has never shipped a balance inside a coloured card… a container
            // around them was the app claiming emphasis the content already
            // had." A figure, its move and its curve ARE the hero; the card
            // was this room claiming an emphasis they already carry, and it
            // made the one reading both rooms share the one element that
            // looked different in each.
            balanceHero
            holdingsCard
            // SECTION HEADERS, Wallet's own (`walletGroupHeader`): "What you
            // hold" / "What it's doing" are `heading22` in PRIMARY ink,
            // OUTSIDE the card they introduce, at the same margin as the bare
            // hero above. This room said the same kind of thing in `label12`
            // tertiary INSIDE each card — a caption, which is a different
            // object from a section title, and the reason the two rooms read
            // as different products at a glance.
            sectionHeader(String(localized: "What's authorized"))
            keysCard
            sectionHeader(String(localized: "Linked accounts"))
            linkedCard
            // OUTSIDE the cards, and quieter for it. Provenance is a fact
            // about the whole room rather than about any one reading, so a
            // card of its own would make a section out of a footnote.
            //
            // NO horizontal padding of its own — the outer margin below now
            // does that job for the footnote and every card alike, uniformly.
            // Giving it a SECOND s4 here (on top of the outer one) is the
            // over-correction that would put it back out of alignment with
            // the cards' own text, the opposite direction from the bug this
            // whole modifier exists to fix.
            if let note = VibenetRoom.note(room, drawn: drawn.count) {
                Text(note)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        // **THE MARGIN FROM THE SCREEN EDGE (2026-08-25, prd §474).** Reported:
        // "the margins aren't the same consistency as on the wallet, so it
        // looks like they are touching the screen." Correct, and measurable:
        // this room is presented through `insightSection`, which is
        // DELIBERATELY edge-to-edge ("the card owns its own padding" — every
        // sibling room-head card, `GnosisPayRoomCard`/`StripeRoomCard`/
        // `SafeRoomCard` among them, applies `.padding(.horizontal, DS.Space
        // .s4)` after its own `dsWidgetSurface()` for exactly that reason —
        // the same rung `WalletCardStyle.rowInsets` gives every Wallet card via
        // `listRowInsets`. This card never did, on either of its two shapes
        // (this one and `oneSurface` below), so its `surfaceSheet` background
        // ran flush to both edges of the phone while every neighbouring room's
        // card sat 18pt in from them — the exact inconsistency reported, and
        // the fix is the one line every sibling already carries.
        .padding(.horizontal, DS.Space.s4)
    }

    /// The surface every stacked card wears — one definition, so four cards
    /// cannot drift into four slightly different boxes.
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
            // CLIPPED TO ITS OWN SHAPE, because one card deliberately bleeds
            // its chart past the padding (`balanceCard`). `dsWidgetSurface`
            // paints a rounded background but does not clip what is drawn on
            // top of it, so without this the sparkline ran out through the
            // card's rounded corners to the screen edge — the fill squaring
            // off exactly where the card curves.
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    /// Everything that is NOT the stacked feed room, exactly as it was.
    private var oneSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lead = room.lead, room.items.count == 1 {
                // `room` reaching this branch may be SCOPED to just this
                // one account (the face rail narrowed it) or genuinely be
                // the only account watched — either way, a delegate
                // relationship can name an account that's currently OUT
                // of scope, so links are derived from the FULL watch list
                // rather than this card's own (possibly narrowed) `room`.
                // The same deliberate bypass `VibenetAccountSheet` already
                // makes, for the identical reason — see that file's own
                // doc. Falling back to `room.items` when the full read
                // isn't cached yet can only UNDER-report a link, never
                // invent one that isn't real.
                let fullItems = VibenetRoomSource.card()?.items ?? room.items
                // THE HERO'S FACE, only when the rail is not already drawing
                // it (user, 2026-08-25 — see `VibenetAccountDetail.showsFace`).
                // The condition is `VibenetScopeRail.shows`' own, spelled
                // against the same two facts it reads: the rail exists in the
                // FEED room (`onOpen == nil`) and only above one watched
                // account (`fullItems.count > 1`). `fullItems`, never
                // `room.items` — this branch is reached precisely because the
                // rail narrowed the room to one, so the scoped count is always
                // 1 here and would hide the rail from itself.
                let railDrawsTheFace = onOpen == nil
                    && VibenetScopeRail.shows(source: VibenetIdentity.source, watched: fullItems.count)
                VibenetAccountDetail(
                    item: lead,
                    links: VibenetAccountMapping.links(fullItems),
                    sharedKeys: VibenetKeyReuse.sharing(lead, in: fullItems),
                    showsFace: !railDrawsTheFace)
            } else if let lead = room.lead {
                if let onOpen {
                    // `VibenetScreen`'s OWN roster (see this type's header
                    // doc) — every account is a full navigable row,
                    // promoted lead included, and UNCAPPED (2026-08-24,
                    // found reading the code rather than reported): this
                    // is the dedicated screen for MANAGING every watched
                    // account, the Wallet-Address-Book analog, not the
                    // "keep it short" summary `rowCap`/`drawn` exist for.
                    // Sharing that cap with the feed card meant anything
                    // past the 8th watched address had no row, no context
                    // menu and no way to rename or stop watching it —
                    // reachable only by unwatching blind from the note's
                    // own "N more watched" count, or not at all.
                    let roster = Array(room.items.dropFirst())
                    row(lead, isLead: true, onOpen: onOpen)
                    // Only the accounts BEYOND the lead get a row — the lead
                    // IS the headline, and repeating it directly underneath
                    // would be the card arguing with itself (ASC's own
                    // ruling, reused).
                    if !roster.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            // The roster is what this card draws from data —
                            // one row per watched account beyond the lead —
                            // so it wears the same staged arrival every other
                            // room's ranked rows do, Reduce Motion included.
                            ForEach(Array(roster.enumerated()), id: \.element.id) { index, item in
                                row(item, onOpen: onOpen)
                                    .chartArrival(index: index, reduceMotion: reduceMotion)
                            }
                        }
                        .padding(.top, DS.Space.s3)
                    }
                }
                // NO `else`. The feed room's aggregate shape is the STACKED
                // one now (§467) — `stacksIntoCards` catches exactly
                // `onOpen == nil && count > 1`, so the branch that used to
                // draw a single combined stat block here is unreachable, and
                // the block itself is gone rather than left as a second
                // definition of the same reading for someone to find and
                // wire back up.
                //
                // THE KEYS CARD IS GONE FROM THIS BRANCH (user, 2026-08-25:
                // "the address book shows a card for keys that duplicates
                // what is on the all aggregate screen. we don't need it in
                // address book"). It was real duplication, not a lookalike —
                // this branch is reached ONLY when `onOpen != nil` now (the
                // feed room's own `count > 1` shape routes through
                // `stacksIntoCards` above and never reaches here), so the
                // roster screen was drawing `keysAggregateSection` right
                // underneath its own per-account rows, composing the exact
                // same `keysBody(aggregate)` the feed's `keysCard` already
                // shows on "All". `keysAggregateSection` had no other caller
                // and is deleted rather than left as a second definition for
                // someone to find and wire back up (this file's own standing
                // rule, one paragraph up). `linkedAccountsSection` stays —
                // not asked for removal, and the roster is exactly where
                // "who can act for whom" belongs when you're managing who's
                // watched, rather than reading a summary of it.
                linkedAccountsSection
                    .padding(.top, DS.Space.s4)
            } else {
                Text(VibenetRoom.headline(room, now: .now))
                    .dsText(.heading17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The bottom-of-card provenance note (2026-08-23, moved off
            // the top of the room's scrollable content — it used to sit
            // directly under the room's own floating settings gear with
            // no surface behind it, reported as "look at it touching the
            // walls"). Gated on having a lead: an empty room's headline
            // already says "Nothing watched on vibenet yet", and a
            // provenance line under that says nothing new.
            //
            // `onOpen != nil` (the management screen) draws every account
            // now, so nothing is hidden there — `room.items.count` tells
            // `note` so, rather than the `rowCap`-limited `drawn.count`
            // that's still correct for the feed card's own summary.
            if room.lead != nil, let note = VibenetRoom.note(room, drawn: onOpen != nil ? room.items.count : drawn.count) {
                Text(note)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s4)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        // Same fix, same reason as `stackedRoom` — this is the room's OTHER
        // shape (a single account, or the roster on `VibenetScreen`/the
        // address book), and it had the identical gap: no outer margin, so
        // its surface ran to both screen edges while every sibling room-head
        // card sits 18pt in from them.
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - The four stacked cards (prd §467, direction B)

    /// THE CROWN, BARE — Wallet's own hero recipe (prd §475, 2026-08-25).
    ///
    /// Reported: *"the sparkline and balance are in one card in the vibenet
    /// room, but in the wallet room neither are in a card."* Wallet's own
    /// source carries the ruling (`walletTilesSection`, 2026-08-16): "NO
    /// GROUND AT ALL… a container around them was the app claiming emphasis
    /// the content already had."
    ///
    /// **ONE margin, not two.** `stackedRoom`'s own `.padding(.horizontal,
    /// DS.Space.s4)` (§474) is the whole inset now, which is exactly what
    /// `WalletCardStyle.rowInsets` gives Wallet's bare hero. A card here would
    /// add a SECOND `s4` and put this room's figure 36pt from the edge while
    /// the section headers below it sat at 18 — the two-margin mismatch §474
    /// just fixed, reintroduced by the container rather than by the padding.
    ///
    /// The chart no longer bleeds: a full-bleed was the right answer INSIDE a
    /// card (the line's whole job is its shape, and a card's own padding was
    /// stealing width from it), and with the card gone there is nothing left
    /// to cancel — negative insets would now push the curve off the screen.
    @ViewBuilder
    private var balanceHero: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            VStack(alignment: .leading, spacing: 0) {
                // The MODEL's heading, never a literal: "Across your
                // accounts" is only true when the total below really covers
                // all of them, and `compose` silently drops every account
                // whose balance read failed. See `nativeHeading`.
                Text(aggregate.nativeHeading)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                if let nativeTotal = aggregate.nativeTotal {
                    // `price48`, Wallet's crown rung — not `price40`. The two
                    // rooms state the same kind of reading and were stating it
                    // two sizes apart.
                    Text("\(VibenetBalanceFormat.line(nativeTotal)) ETH")
                        .dsText(.price48)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)
                }
                // THE MOVE, WITH ITS AMOUNT (§475). Wallet states the move as
                // "▲ $224.51 (1.8%) today" — the figure FIRST, the percent in
                // parentheses — and its own note says why: the percent alone
                // cannot say how much, and the amount is what the reader is
                // actually looking at on the line above.
                if let change = VibenetValueHistory.delta(history),
                   let move = VibenetValueHistory.move(history) {
                    HStack(spacing: 5) {
                        Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .dsGlyph(9)
                        Text("\(VibenetBalanceFormat.line(abs(move))) ETH (\(VibenetBalanceFormat.percent(change)))")
                            .dsText(.callout15).fontWeight(.semibold)
                            .monospacedDigit()
                        Text(String(localized: "since watching"))
                            .dsText(.callout15)
                            .foregroundStyle(DS.textTertiary)
                    }
                    .foregroundStyle(TokenChartStyle.accent(change: change, scheme: scheme))
                    .padding(.top, 2)
                }
                Text(aggregate.plainLine)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                // What the room could not see, said plainly and only when it
                // happened — the figure above stays useful, and stops being a
                // claim about accounts nobody read.
                if let missing = aggregate.unreachedLine {
                    Text(missing)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if let series = VibenetValueHistory.series(history) {
                    TokenChartPlot(chart: TokenChart(closes: series,
                                                     price: series.last ?? 0,
                                                     change: VibenetValueHistory.delta(history) ?? 0),
                                   accent: TokenChartStyle.accent(
                                       change: VibenetValueHistory.delta(history) ?? 0, scheme: scheme),
                                   // 120, Wallet's own height for this figure.
                                   height: 120, pulses: false,
                                   lineWidth: 2.6, fillOpacity: 0.24, endpointDot: true)
                        .padding(.top, DS.Space.s3)
                }
                accountChips
            }
        }
    }

    /// WHOSE THE NUMBER IS — `WalletFaceChips`' shape, and the reading this
    /// room had the data for and never drew (prd §475).
    ///
    /// Reported: *"it shows the account icons and what their performance is
    /// below the sparkline."* `VibenetValueStore.samples(for:)` has kept a
    /// REAL per-account history since §467 — recorded on every sweep, on every
    /// device — and nothing on any screen read it back except the scoped
    /// account's own chart. So the aggregate stated one total and could not
    /// say which account it came from.
    ///
    /// **Gated exactly as Wallet gates its own**: more than one account, and
    /// only unscoped. Scoped, the rail above has ringed one face and this card
    /// describes that account alone — a strip of three would be the one
    /// element still talking about all of them.
    ///
    /// A change is drawn ONLY where a real one exists: an account watched
    /// since this morning has one sample, and `VibenetValueHistory.delta`
    /// returns nil rather than a zero — a flat 0.0% beside a face claims a
    /// reading nobody took.
    @ViewBuilder
    private var accountChips: some View {
        if room.items.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(room.items) { item in
                        if let native = item.nativeBalance {
                            accountChip(item, native: native)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, DS.Space.s3)
        }
    }

    private func accountChip(_ item: VibenetAccountItem, native: Double) -> some View {
        let samples = VibenetValueStore.samples(for: item.address)
        let change = VibenetValueHistory.delta(samples)
        return HStack(spacing: 6) {
            WalletFace(address: item.address, size: DS.Face.badge, circular: true)
            Text("\(VibenetBalanceFormat.line(native)) ETH")
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            if let change {
                Text(VibenetBalanceFormat.percent(change))
                    .dsText(.label12)
                    .foregroundStyle(TokenChartStyle.accent(change: change, scheme: scheme))
                    .monospacedDigit()
            }
        }
        // A face sits tight to the leading edge — `WalletFaceChips`' own
        // measurement, so the two strips are the same object in two rooms.
        .padding(.leading, 4)
        .padding(.trailing, DS.Space.s3).padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(DS.fillFaint))
    }

    /// A room-level section title — `walletGroupHeader`'s recipe (prd §475):
    /// `heading22` in PRIMARY ink, outside the card it introduces, on the
    /// same margin as the bare hero.
    ///
    /// `s8` above and `s1` below is Wallet's own measured spacing, and its
    /// note says why: at an even gap the header "read as floating between the
    /// two" rather than belonging to the card beneath it. The stack's own
    /// `s6` spacing is cancelled above to make room for it.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, DS.Space.s2)
            .padding(.bottom, -DS.Space.s3)
    }

    /// WHAT THE ACCOUNTS HOLD. Silent for a single asset — the crown above
    /// already states it, and `VibenetBalanceTreemap` returns nothing there
    /// for exactly that reason, so this card never draws an empty box.
    @ViewBuilder
    private var holdingsCard: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            let cells = VibenetBalanceTreemap.cells(aggregate)
            if !cells.isEmpty {
                card {
                    Text(String(localized: "Holdings"))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    VibenetHoldingsBlock(cells: cells, reduceMotion: reduceMotion)
                        .padding(.top, DS.Space.s3)
                }
            }
        }
    }

    /// THE KEYS. Header grammar matched to its three neighbours (prd §471):
    /// an eyebrow carrying the SCOPE, then the count alone as the headline.
    /// The old objection — "Keys" over "8 keys authorized across 3 accounts"
    /// says the word twice — was right, and putting the scope in the eyebrow
    /// instead of the noun answers it while leaving this card the only one of
    /// the four that opened with a `heading17` where the others open with a
    /// `label12` (see `VibenetKeyAggregate.scopeEyebrow`).
    @ViewBuilder
    private var keysCard: some View {
        if let aggregate = VibenetKeyAggregation.compose(room.items, now: .now) {
            card { keysBody(aggregate) }
        }
    }

    /// THE KEYS BLOCK, ONE DEFINITION.
    ///
    /// It was written twice — once inside `keysCard` (the stacked feed room)
    /// and once inside a now-deleted `keysAggregateSection` (every other
    /// shape) — with identical headline, policy rows and expiry sentence,
    /// differing only in the box around them. Two copies of one reading
    /// drift, and then the same room says two different things depending on
    /// how many accounts happen to be watched; the §418 duplicate-parser
    /// lesson, one card over.
    ///
    /// `keysAggregateSection` itself is gone (2026-08-25, prd §469, user:
    /// "the address book shows a card for keys that duplicates what is on
    /// the all aggregate screen. we don't need it in address book"), and
    /// `keysTappable` went with it (prd §471): it wrapped this ENTIRE block
    /// in one Button, which cannot survive the census rows becoming doors of
    /// their own — a Button inside a Button does not resolve in SwiftUI. The
    /// headline keeps the whole-tray door; each row now opens the tray at its
    /// own permission.
    @ViewBuilder
    private func keysBody(_ aggregate: VibenetKeyAggregate) -> some View {
        if let scope = aggregate.scopeEyebrow {
            Text(scope)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            headline(aggregate)
            Spacer(minLength: DS.Space.s2)
            // WHAT MOVED, as a mark-coloured pill rather than a third caption
            // stacked under the headline. Drawn in the room's own mark and
            // never a state colour: a key added and a key revoked are both
            // merely news here and neither is graded (§295's same-weight
            // ruling, and `VibenetKeyChanges.line`'s own note).
            if let moved = keyChanges?.pillLine {
                Text(moved)
                    .dsText(.label11).fontWeight(.semibold)
                    .foregroundStyle(DS.page)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Self.mark))
                    .fixedSize()
            }
        }
        .padding(.top, aggregate.scopeEyebrow == nil ? 0 : 2)
        // Directly under the headline, because it is an apology FOR the
        // headline: the count above is a floor whenever this draws.
        if let missing = aggregate.unreachedLine {
            Text(missing)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        // THE CENSUS, AS ITS OWN GROUP AND AS DOORS (prd §471).
        //
        // Six permission rows loose in the card, at `.padding(.vertical, 5)`
        // — 36pt tall, under the 44pt hit floor — were the densest thing on
        // this screen and the reason it read as "tightly packed". They sit on
        // one `fillFaint` group now, so a census reads as a container rather
        // than as a run of sentences, and each row is its own 46pt door into
        // the tray AT THAT PERMISSION: "Send anywhere · 4" is the one shape
        // of fact you cannot act on, and the follow-up it wants is those four
        // keys, not the whole roster.
        let policies = VibenetPolicyAggregation.compose(room.items)
        if !policies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(policies.enumerated()), id: \.offset) { index, entry in
                    policyRow(entry, isLast: index == policies.count - 1)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.fillFaint))
            .padding(.top, DS.Space.s3)
        }
        // WHAT THE CENSUS COULD NOT COUNT. A footnote and never a row — see
        // `VibenetKeyAggregate.unnamedLine`. Without it the rows silently add
        // up to less than the headline and nothing says why.
        if let unnamed = aggregate.unnamedLine {
            Text(unnamed)
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
        }
        expiryFooter(aggregate)
    }

    /// The headline, as a door to the whole tray when there is one to open.
    /// The chevron is gated on the SAME nil the door is, never drawn
    /// unconditionally: a chevron pointing at a tray this caller cannot
    /// present is the dead control §83 bans.
    @ViewBuilder
    private func headline(_ aggregate: VibenetKeyAggregate) -> some View {
        if let onOpenKeys {
            Button {
                DSHaptic.selection()
                onOpenKeys(nil)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(aggregate.countHeadline)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .dsGlyph(12, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        } else {
            Text(aggregate.countHeadline)
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One permission and how many keys hold it — a door into the tray
    /// FOCUSED on that permission, or plain content where there is nowhere to
    /// present one.
    ///
    /// `s2` vertical (46pt with a `body17` line) rather than the old 5, which
    /// put every row of the densest block on the screen under the 44pt hit
    /// floor while it was not even tappable.
    @ViewBuilder
    private func policyRow(_ entry: VibenetPolicyCount, isLast: Bool) -> some View {
        if let onOpenKeys {
            Button {
                DSHaptic.selection()
                onOpenKeys(entry.label)
            } label: { policyRowBody(entry, isLast: isLast, door: true) }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            policyRowBody(entry, isLast: isLast, door: false)
        }
    }

    private func policyRowBody(_ entry: VibenetPolicyCount, isLast: Bool, door: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(entry.label)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text("\(entry.count)")
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .monospacedDigit()
            if door {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.Space.s2)
        // A separator between rows and never under the last one — a FILL at
        // the faintest rung, which is what this design system draws instead
        // of a hairline (§8: nothing strokes a line).
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(DS.fillFaint).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }

    /// WHEN KEYS LAPSE — one bar per key, on one fixed 90-day scale
    /// (`VibenetKeyShelf`, prd §471, user pick of three candidates).
    ///
    /// This replaced `WalletRunwayRail(dates: aggregate.futureExpiries)`,
    /// which had a defect on this card that no restyling could fix: every key
    /// expiry is in the FUTURE, so `WidgetRunway.positions` — which windows
    /// on `min(dates, now) … max(dates, now)` — put `now` at the minimum on
    /// every render, pinning the marker at 5% forever. See `VibenetKeyShelf`
    /// for the full argument and for the cost of no longer sharing a drawing
    /// with the "Needs you" widget.
    ///
    /// SHELF **XOR** SENTENCE, never both: the shelf's first bar IS the
    /// soonest expiry, named and counted down, so drawing the sentence under
    /// it is the card arguing with itself. The sentence survives exactly
    /// where the shelf declines — one lone expiry, or nothing inside the
    /// window — which is the behaviour this card had before any figure
    /// existed.
    @ViewBuilder
    private func expiryFooter(_ aggregate: VibenetKeyAggregate) -> some View {
        if let shelf = VibenetKeyShelf.compose(room.items, now: .now) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Keys that lapse"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(shelf.rows.enumerated()), id: \.element.id) { index, row in
                        shelfRow(row)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                }
                .padding(.top, DS.Space.s3)
                if let tail = shelf.tailLine {
                    Text(tail)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
            }
            .padding(.top, DS.Space.s4)
        } else if let soonest = aggregate.soonestExpiry {
            Text(soonest.line(now: .now))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s4)
        }
    }

    /// One key's remaining shelf life. The NAME is composed here rather than
    /// in the model for `displayName`'s own reason — resolving a nickname
    /// needs `VibenetWatch`, and `VibenetRoom.swift` is Foundation-only.
    ///
    /// Blue is spent on urgency and only on urgency: a bar inside the
    /// fortnight wears the room's mark, everything else wears `fillStrong`,
    /// so the one key you might have to act on is the one coloured thing in
    /// the block.
    private func shelfRow(_ row: VibenetKeyShelfRow) -> some View {
        let urgent = row.isUrgent(now: .now)
        return HStack(spacing: DS.Space.s3) {
            Text("\(row.actor.kind.plainTitle) · \(Self.displayName(row.address))")
                .dsText(.label11)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule()
                        .fill(urgent ? Self.mark : DS.fillStrong)
                        .frame(width: max(3, geo.size.width * row.fraction(now: .now)))
                }
            }
            .frame(height: 7)
            Text(row.countdown(now: .now))
                .dsText(.label11)
                .fontWeight(urgent ? .semibold : .regular)
                .foregroundStyle(urgent ? Self.mark : DS.textTertiary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
        // Bars are a picture and read as nothing to VoiceOver (§299, the risk
        // strip's lesson) — the row says its whole fact in words instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.actor.kind.plainTitle) on \(Self.displayName(row.address)), \(row.actor.expiryLabel(now: .now))"))
    }

    /// WHO CAN ACT FOR WHOM. Silent when there are no links, so a room
    /// where nobody delegates never grows an empty fourth card.
    @ViewBuilder
    private var linkedCard: some View {
        let links = VibenetAccountMapping.links(room.items)
        if !links.isEmpty {
            card {
                Text(String(localized: "Linked accounts"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                VibenetLinkSpine(links: links,
                                 name: { Self.displayName($0) },
                                 reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
                Text(String(localized: "Who can act for whom, read from the keystore."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    /// WHO CAN ACT FOR WHOM — the room's delegate links, as the app's own
    /// connections shape: one face-led row per link, direction stated in
    /// words. Same-weight throughout (§295's ruling, reused): this card makes
    /// no claim that one relationship matters more than another, so nothing
    /// here is sized or coloured to suggest it.
    ///
    /// Silent when there are none. Note these are WATCHED-to-WATCHED only,
    /// which is `VibenetAccountMapping.links`' own deliberate bound.
    /// A watched account's own name, or its short address — the same
    /// fallback every row on this card already makes, so the spine can never
    /// name an account differently from the roster above it.
    private static func displayName(_ address: String) -> String {
        VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }

    @ViewBuilder
    private var linkedAccountsSection: some View {
        let links = VibenetAccountMapping.links(room.items)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Linked accounts"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                // **A SPINE, not a list of sentences (2026-08-24).** Each row
                // used to read "<name> · Can act for <name>" — the same two
                // names in prose, once per link, so a reader had to parse a
                // sentence per row and hold the graph in their head. The whole
                // reason the design draws this as a figure is that a delegate
                // relationship has a SHAPE — an actor on one side, the account
                // it can act for on the other, a line between them — and the
                // shape is legible before any of the names are read.
                //
                // §295's ruling is reused wholesale and is why every ribbon is
                // the same weight and no node carries a hue: this card makes no
                // claim that one relationship matters more than another, so
                // nothing here may be sized or coloured to suggest it. The
                // caption states the direction once, in words, rather than
                // repeating it per row.
                VibenetLinkSpine(links: links,
                                 name: { Self.displayName($0) },
                                 reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
                Text(String(localized: "Who can act for whom, read from the keystore."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    /// Applies a context menu only when the card is showing ONE account's
    /// full detail — the roster rows already carry their own menu each,
    /// and a menu on the whole card in THAT shape would be ambiguous
    /// about which account it names.
    private struct VibenetDetailContextMenu: ViewModifier {
        let address: String?
        let onRename: (String) -> Void
        let onRemove: (String) -> Void
        func body(content: Content) -> some View {
            if let address {
                content.contextMenu {
                    Button {
                        onRename(address)
                    } label: {
                        Label(String(localized: "Name this account…"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onRemove(address)
                    } label: {
                        Label(String(localized: "Stop watching"), systemImage: "trash")
                    }
                }
            } else {
                content
            }
        }
    }

    // MARK: - Rows

    /// One watched account. The LEAD (`isLead: true`) is this exact same
    /// row, just promoted — a bigger face, bigger name, no vertical
    /// padding of its own (the card's outer `DS.Space.s4` already frames
    /// it) — never a separately-composed sentence, so the two can't drift
    /// apart on what one account's state is called. The subtitle keeps
    /// R2.2's precedence (unlock countdown + runway, else the urgency
    /// line, else the plain key count) because that ranking is the whole
    /// point of surfacing it here — before anyone opens anything.
    private func row(_ item: VibenetAccountItem, isLead: Bool = false,
                      onOpen: @escaping (String) -> Void) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item.address)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                // Hoisted out of the call: `face-ramp-audit` reads the first
                // token after `size:`, so a ternary of two legal tiers reads to
                // it as a bare identifier. Naming it keeps both the tier check
                // and the promoted-lead sizing.
                let faceSize = isLead ? DS.Face.list : DS.Face.rowCircle
                WalletFace(address: item.address, size: faceSize, circular: true)
                VStack(alignment: .leading, spacing: 3) {
                    // A nickname takes the title slot (not monospaced —
                    // it's a name, not hex) and the short address drops
                    // to a small line beneath. Unnamed rows are
                    // unchanged: the address alone, exactly as before.
                    if let name = VibenetWatch.shared.name(for: item.address) {
                        Text(name)
                            .dsText(isLead ? .heading22 : .heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(.label11).monospaced()
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    } else {
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(isLead ? .heading22 : .heading17)
                            .foregroundStyle(DS.textPrimary)
                            .monospaced()
                            .lineLimit(1)
                    }
                    // An account mid-unlock leads with its OWN countdown
                    // rather than its key count — "1 key" sits right
                    // beside a badge already saying "Unlocking"; the
                    // number worth a glance here is WHEN.
                    if item.hasInitiatedUnlock {
                        // TICKS (prd §472) — `VibenetAccountDetail.state`
                        // carries the full argument; this is the same clock at
                        // roster scale, so it must not be the one that freezes
                        // while the detail behind it counts down.
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            if let countdown = item.unlockLabel(now: tick.date) {
                                Text(countdown)
                                    .dsText(.label12)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                    .contentTransition(.numericText())
                                    .animation(reduceMotion ? nil : DS.Motion.standard, value: countdown)
                                // Only when BOTH endpoints are known — a bar
                                // with a guessed start is the fake status §83
                                // forbids, so this is silent rather than wrong
                                // on a build where the delay never read.
                                if let progress = item.unlockProgress(now: tick.date) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Self.mark.opacity(0.15))
                                            Capsule().fill(Self.mark)
                                                .frame(width: geo.size.width * progress)
                                        }
                                    }
                                    .frame(height: 4)
                                    .frame(maxWidth: 160)
                                    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                                }
                            } else {
                                Text(String(localized: "Ready to unlock"))
                                    .dsText(.label12)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    } else if let urgent = item.urgentLine(now: .now) {
                        // R2.2: a key's own clock outranks the plain key
                        // count on the row that's about to be affected
                        // by it. The room's one color carries urgency
                        // here (never bold-white-on-blue — that grammar
                        // stays the lock pill's alone).
                        Text(urgent)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(Self.mark)
                            .lineLimit(1)
                    } else {
                        Text(VibenetRoom.rowLine(item))
                            .dsText(.label12)
                            .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                HStack(spacing: DS.Space.s2) {
                    // The pill states the ALARM; the chevron states
                    // there's more to see.
                    if item.alarmed {
                        Text(item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked"))
                            .dsText(.label11).fontWeight(.bold)
                            .foregroundStyle(Color.fixed("#ffffff"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Image(systemName: "chevron.right")
                        .dsGlyph(12)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, isLead ? 0 : DS.Space.s2)
        .contextMenu {
            Button {
                onRename(item.address)
            } label: {
                Label(String(localized: "Name this account…"), systemImage: "pencil")
            }
            Button {
                DSHaptic.tap()
                UIPasteboard.general.string = item.address
            } label: {
                Label(String(localized: "Copy address"), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                onRemove(item.address)
            } label: {
                Label(String(localized: "Stop watching"), systemImage: "trash")
            }
        }
    }
}

/// One landed vibenet event, led by WHO it happened to (R4.2).
///
/// Reported 2026-08-23: *"i can't see which accounts they are from."* The
/// room fell to `.plain`, so every row wore one identical brand glyph and
/// the only identifying mark was a truncated `…f21f` at the END of an
/// 80-char title, in the same weight as the rest of the sentence — two
/// accounts' events were indistinguishable at a glance, in a room whose
/// entire subject is which account something happened to. Every other
/// identity room in this app leads with a face; this one now does too.
///
/// Reads `authorHandle` (the account) and `summary` (the event without
/// the address) — both stamped at landing, so nothing here parses a
/// display title back into data. A row that predates those falls back to
/// its whole title, which still says everything, just less prettily.
struct VibenetEventRow: View {
    let thing: Thing

    var body: some View {
        if thing.isLive {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                if let address = thing.authorHandle {
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(thing.summary ?? thing.title)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: DS.Space.s2)
                Text(thing.capturedAt.formatted(.relative(presentation: .named)))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1).fixedSize()
            }
            .padding(.vertical, DS.Space.s2)
        }
    }

    /// The account's nickname when it has one, else its short address —
    /// the same identity the room card and the sheet show, so one account
    /// never reads as two different things across three surfaces.
    private var title: String {
        guard let address = thing.authorHandle else { return thing.title }
        return VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}
