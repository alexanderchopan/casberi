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
    /// **READ ONCE PER COMPOSE, NEVER PER BODY PASS (2026-08-25, prd §476).**
    ///
    /// It was a computed property — `VibenetValueStore.samples()` — so every
    /// evaluation of this card's body did a `UserDefaults` data read and a
    /// full `JSONDecoder` pass over the whole history. `accountChips` then did
    /// the same again PER CHIP, decoding the entire per-account book once for
    /// each face on screen: four decodes on a three-account room, on every
    /// pass, while a List is asking for a body on every scroll frame.
    ///
    /// That is the jitter reported as "it is jittery when scrolling to the
    /// bottom" — not an animation at all. `.task(id:)` reads both books once
    /// when the roster's fingerprint changes and holds the result, which is
    /// the same shape the key-changes ledger beside it already uses.

    @State private var history: [VibenetValueSample] = []
    /// Every watched account's own curve, keyed by lowercased address — one
    /// decode for the whole strip rather than one per chip.
    @State private var accountHistories: [String: [VibenetValueSample]] = [:]
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
    ///
    /// TAKES THE NEW-KEY SET (2026-08-25, prd §479): this card reads the
    /// seen-ledger and SPENDS it in its own `.task`, so the tray cannot read
    /// it again — a second read returns empty, and the tray would mark
    /// nothing while the card beside it says "1 new". The answer travels with
    /// the request.
    var onOpenKeys: ((Set<String>) -> Void)? = nil
    /// OPEN A KEY'S SHEET (2026-08-25, prd §478) — the scoped account's key
    /// rows present `VibenetKeySheet` instead of expanding in place, and this
    /// card cannot own the presentation for `onOpenKeys`'s own reason: it
    /// lives inside `FeedScreen`'s List rows, where a `.sheet` on a row is
    /// the half-open-then-close class. Carries the actor, the account it acts
    /// for, and the room-wide shared-key facts the sheet's "Also on" line
    /// needs — all value types, captured at tap time.
    var onOpenKey: ((VibenetActor, VibenetAccountItem, [VibenetSharedKey]) -> Void)? = nil
    /// Scope the room to one account (2026-08-25, prd §476).
    ///
    /// **§469 deleted an `onScope` and it was right to.** That one fired from
    /// a soonest-expiry callout, and its reasoning was that
    /// `VibenetScopeRail` — pinned directly above this card — already reaches
    /// every account with the same toggle-back-to-All rule, so a second door
    /// to the same destination was not worth adding.
    ///
    /// What changed is that there is now an ACCOUNTS card: a row per account
    /// carrying its state, which the rail cannot show (it is faces alone). A
    /// row that states "2 keys" or "Deploys with its first transaction" and
    /// does nothing when tapped is the dead control §83 bans, and the
    /// destination it wants is the one the rail happens to share. The rail is
    /// the shortcut; this is the list.
    var onScope: ((String) -> Void)? = nil

    /// WHICH READING IS ON SCREEN (prd §482, 2026-08-26), or nil for the
    /// whole room in one scroll.
    ///
    /// nil is not a legacy path — it is what `VibenetScreen`'s management
    /// roster and the single-account branch want, and both are surfaces where
    /// a scope strip would be a control over one thing (§83). Only the FEED
    /// room, which is the one that ran long, is scoped.
    var section: VibenetSection? = nil

    /// The scope strip's own inputs, so the control can be drawn INSIDE this
    /// card rather than pinned above the room (prd §482 amendment, 2026-08-26
    /// — user: *"we can' hta ve the positions risk etc at the top"*, then
    /// *"needs to be below the sparkline"*).
    ///
    /// Handed in rather than read from `ShellChrome` here: this card is also
    /// drawn by `VibenetScreen`, which has no scope state and wants none, and
    /// a card that reaches into the shell for it would need a stand-down rule
    /// on every other caller. Empty `scopes` draws no strip, which is what
    /// every non-feed caller gets for free.
    var scopes: [VibenetSection] = []
    var scopeAttention: Set<VibenetSection> = []
    var onPickScope: ((VibenetSection) -> Void)? = nil

    /// Which account the room is scoped to, and the door to the book — the
    /// two halves of the face rail this card ABSORBED (prd §482 amendment,
    /// 2026-08-26, user: *"we cannot have four rows of chips"*).
    ///
    /// The rail and the value chips under the sparkline were both a strip of
    /// this room's accounts, one above the crown and one below it, and only
    /// one of them showed what each account was worth. Folding the scoping
    /// into the chips that already carry the numbers costs a row of chrome
    /// and loses nothing: it is the same faces, the same order, now saying
    /// what they are worth as well as which one you are in.
    var scopedAddress: String? = nil
    var onOpenBook: (() -> Void)? = nil

    /// What moved since this device last looked at these keys — captured
    /// ONCE when the roster appears and then immediately spent (`advance`),
    /// so the marker survives the draw it was computed for and is gone by the
    /// next one. Reading and marking-as-read are two acts; computing this in
    /// the body instead would erase the answer while it was being shown.
    @State private var keyChanges: VibenetKeyChanges?
    /// Whether the folded delegate spine is open (prd §477). `@State`, so it
    /// shuts when you leave the room — it is a look, not a preference.
    @State private var linksOpen = false
    /// How far back the curve looks (prd §479). `@State`, so it dies with the
    /// room — it is a look, not a preference, and a chart that reopened
    /// windowed would state a move over a span nobody chose this session.
    @State private var range: VibenetChartRange = .all
    /// Whether the crown has counted up yet this mount (prd §479). ONE SHOT:
    /// the fill is a greeting, and a figure that re-counted on every re-compose
    /// would be a number that never settles while you read it.

    @State private var counted = false

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
        // The curves, read ONCE per roster rather than per body pass — see
        // `history`'s own note for the jitter this fixes (prd §476). Keyed on
        // the ADDRESSES rather than the key fingerprint above: a balance
        // landing does not change which curves exist, and re-decoding both
        // books every time a reading ticks would put the cost straight back.
        .task(id: room.items.map(\.address).joined(separator: ",")) {
            history = VibenetValueStore.samples()
            accountHistories = VibenetValueStore.accountSamples()
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
            // **THE CROWN AND ITS CHART ARE ALWAYS ON, ABOVE THE CONTROL
            // (prd §482 amendment).** They belong to no scope: they are the
            // room's identity rather than one of its readings, and a strip
            // that could scope them away would let you open vibenet and not
            // be told the balance.
            //
            // It also settles §482's own ruling permanently instead of by
            // careful ordering. That entry moved the attention strip below
            // the holdings because *"holdings and sparkline are together"* —
            // with the crown pinned above the control, nothing can ever get
            // between the two again.
            // **THE CROWN AND ITS CHART ARE ALWAYS ON, ABOVE THE CONTROL.**
            // They belong to no scope: they are the room's identity rather
            // than one of its readings, and a strip that could scope them away
            // would let you open vibenet and not be told the balance.
            //
            // **HOME'S CHART IS ITS DRAWING; every other scope gets one of its
            // own in the SAME FIXED SLOT** (prd §482 amendment, Wallet's §483
            // contract). The bar must land in the same place on every scope,
            // and the only way that is true is if everything above it is one
            // height — so the slot is fixed rather than fitted and each
            // drawing sits in it top-aligned. Fitted, the runway and the spine
            // are different heights and the toggle walks up and down the
            // screen as you use it.
            balanceHero
            // **NOT EMITTED ON HOME** — the crown's own chart already fills
            // this height there, so drawing an empty 210pt box as well would
            // push the bar a third of a screen lower on the one scope the room
            // opens to. Wallet paid for the subtler half of this: collapsing
            // to `maxHeight: 0` is NOT the same as not emitting, because a
            // container still gives an empty child its spacing.
            if (section ?? .home) != .home {
                scopeVisual
                    .frame(minHeight: Self.visualSlot, maxHeight: Self.visualSlot,
                           alignment: .top)
                    .clipped()
            }
            accountChips
            scopeStrip
            if shows(.holdings) { holdingsCard }
            // **THE ATTENTION STRIP IS GONE (2026-08-26, prd §482).** It was
            // added by §479 and re-grammared and re-titled twice in one
            // afternoon before it was deleted the same day, and the churn was
            // the diagnosis: the thing had no stable identity. It grouped four
            // unlike facts — a key's deadline, an account's lock, an unlock's
            // countdown, our own failed read — by nothing except "you might
            // want to look", which is why no name (Needs you → Worth a look →
            // Risk) ever fitted all four.
            //
            // **Scoping dissolves it, and NOTHING IS LOST — checked row type
            // by row type before deleting, because that is the test that bit
            // the wallet session twice today.** A key expiring is the Keys
            // scope's own runway (`shelfRow`, same blue, same countdown); a
            // locked account is its roster row's pill; an unlocking one is
            // that row's ticking subtitle and progress bar; an unreached read
            // is that row's subtitle in words (`VibenetRoom` line ~1155,
            // "Couldn't reach the chain"). The strip existed only because all
            // four were buried in one long scroll, and a scope strip is a
            // better answer to burial than a summary of it.
            //
            // `VibenetAttention` survives with its ranking intact, one layer
            // down: it decides which CHIP wears a dot
            // (`VibenetSection.attention`). The work is kept, the surface that
            // could not be named is gone.
            if shows(.accounts) {
                // The header is dropped when the strip is naming the scope —
                // a chip reading "Accounts" above a heading reading "Accounts"
                // says one thing twice, and the heading is the one that can go
                // because the chip is also the control.
                if section == nil { sectionHeader(String(localized: "Accounts")) }
                accountsCard
            }
            if shows(.keys) {
                if section == nil { sectionHeader(String(localized: "Keys")) }
                keysCard
            }
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
            // Provenance follows the ROSTER it describes ("N more watched",
            // and where the config was read) rather than trailing whichever
            // scope happens to be last — in `.keys` it would be a footnote
            // about accounts under a census of keys.
            if shows(.accounts), let note = VibenetRoom.note(room, drawn: drawn.count) {
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

    /// The scope strip, BELOW the crown (prd §482 amendment, 2026-08-26).
    ///
    /// **It was pinned in `MainSurface.roomControls` for one build and that
    /// was wrong**, reported the moment it was seen: *"o wait no way… we
    /// can' hta ve the positions risk etc at the top"*. Mounted at the shell
    /// it was the FOURTH stacked chrome row — source chips, venue rail, face
    /// rail, then this — and the crown started roughly halfway down the
    /// screen. §357's reasoning (a control destroyed by the transition it
    /// commands) is what put it up there, and that reasoning is sound about
    /// `safeAreaInset` and silent about how many rows a reader will accept
    /// before the first fact.
    ///
    /// **STATED COST, so nobody has to rediscover it:** in the content it
    /// SCROLLS AWAY, which is §357's complaint one level down — a scope
    /// control you cannot reach while deep in the rows it scopes. The fix is
    /// a pinned `Section` header rather than a return to the inset, and it is
    /// deliberately not done here: the user asked to see this shape first.
    @ViewBuilder
    private var scopeStrip: some View {
        if onPickScope != nil, VibenetSection.shows(present: scopes) {
            DSSectionSwitcher(
                sections: scopes,
                active: section ?? .holdings,
                attention: scopeAttention) { picked in
                    onPickScope?(picked)
                }
                .padding(.top, DS.Space.s4)
        }
    }

    /// Whether a scope's content draws. nil `section` means the whole room in
    /// one scroll, which is what the management roster and the single-account
    /// branch want — so the scoped feed room narrows and every other caller is
    /// untouched by construction rather than by a flag each has to pass.
    private func shows(_ candidate: VibenetSection) -> Bool {
        section == nil || section == candidate
    }

    /// The surface every stacked card wears — one definition, so four cards
    /// cannot drift into four slightly different boxes.
    @ViewBuilder
    /// **NO OUTLINE (prd §482 amendment, 2026-08-26, user: "we don't have card
    /// outlines").** Wallet's §483 pass took the same step and the reasoning
    /// carries: once each scope shows ONE reading, the card is drawing a
    /// boundary around the only thing on screen. §467 gave every reading its
    /// own surface to fix "some hodge podge put together view" — six unrelated
    /// readings in one box — and scoping solved that problem at the root, so
    /// the surface is now separating a thing from nothing.
    ///
    /// The padding STAYS: it is what keeps content off the screen edge (§474's
    /// reported bug), and it was never the card doing that job.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The clip went with the surface: it existed to stop the chart
            // bleeding through a rounded CORNER, and there is no corner now.
    }

    /// Everything that is NOT the stacked feed room.
    ///
    /// **THE DETAIL BRANCH NO LONGER TAKES THE SLAB (2026-08-25, prd §477).**
    /// Reported with screenshots: *"the All screen in vibenet is good, but the
    /// individual account screens are not in the same format… you have one
    /// giant slab that contains all the components in it."* Exactly so — this
    /// property wrapped its WHOLE body in one `.padding(s4)` +
    /// `.dsWidgetSurface()`, and for the single-account branch that body is
    /// the entire `VibenetAccountDetail`: hero, crown, chart, holdings, every
    /// key, the links, the history, the sync line and the doors, inside one
    /// rounded rectangle.
    ///
    /// §467 fixed precisely this shape for the aggregate ("six unrelated
    /// readings inside one box read as one object that will not parse") and
    /// §475/§476 gave it section headers — and the scoped view, which is the
    /// SAME room narrowed to one account, kept the pre-§467 anatomy the whole
    /// time. So `VibenetAccountDetail` owns its own cards now and this branch
    /// hands it the bare page, while the ROSTER branch below keeps the single
    /// surface that is right for a list of one-line rows.
    private var oneSurface: some View {
        Group {
            if let lead = room.lead, room.items.count == 1 {
                detailBranch(lead)
            } else {
                rosterBranch
            }
        }
    }

    /// The scoped account — bare, so the detail's own cards are the surfaces.
    @ViewBuilder
    private func detailBranch(_ lead: VibenetAccountItem) -> some View {
        // `room` reaching this branch may be SCOPED to just this one account
        // (the face rail narrowed it) or genuinely be the only account
        // watched — either way, a delegate relationship can name an account
        // that's currently OUT of scope, so links are derived from the FULL
        // watch list rather than this card's own (possibly narrowed) `room`.
        let fullItems = VibenetRoomSource.card()?.items ?? room.items
        let shared = VibenetKeyReuse.sharing(lead, in: fullItems)
        VStack(alignment: .leading, spacing: 0) {
            // **THE STRIP STAYS WHEN YOU SCOPE (prd §482 amendment,
            // 2026-08-26).** Picking an account used to swap the whole card
            // for this detail and the chips vanished with the hero — the
            // control deleted itself on use, reported directly: "if you
            // click one of the accounts, it should still keep the row in the
            // same place so user can navigate back, and right now it
            // doesn't". Same strip, same place, picked chip filled; re-tap
            // or All to come back. Only for the feed room (`onScope` is nil
            // on the setup screen, where scoping was never offered).
            if onScope != nil {
                accountChips
                    .padding(.bottom, DS.Space.s3)
            }
            VibenetAccountDetail(
                item: lead,
                links: VibenetAccountMapping.links(fullItems),
                sharedKeys: shared,
                // ALWAYS, since the rail folded into the chips (prd §482
                // amendment): the old gate hid this face while the shell
                // rail drew a matching one above — with that rail gone the
                // gate would hide the scoped account's identity entirely,
                // and a 26pt chip is a mark, not a portrait.
                showsFace: true,
                onOpenKey: onOpenKey.map { open in { actor in open(actor, lead, shared) } },
                // The card read the ledger and spent it; the detail draws the
                // answer (prd §479). Reading it there instead would erase the
                // marker while it was being shown.
                newKeyIDs: keyChanges?.added ?? [])
        }
        .padding(.horizontal, DS.Space.s4)
    }

    private var rosterBranch: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lead = room.lead {
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
                // rule, one paragraph up).
                //
                // **AND `linkedAccountsSection` FOLLOWED IT (2026-08-25, prd
                // §476).** §469 kept it here on the reasoning that "the roster
                // is exactly where 'who can act for whom' belongs when you're
                // managing who's watched" — and the user's answer is that it
                // does not: *"the 'linked accounts' section in address book
                // doesn't belong there."* The address book is the screen for
                // deciding WHICH accounts you watch; the delegate graph is a
                // reading ABOUT them, and it already has two homes that are
                // about reading — the room's own Linked accounts card and each
                // account's own detail. This was the third, on the one screen
                // whose job is management.
                //
                // The function survives with one caller (the account detail's
                // own section, which is scoped to that account and is a
                // different reading from this room-wide one).
            } else {
                // THE EMPTY ROOM OFFERS A WAY OUT OF ITSELF (prd §479).
                // "Nothing watched on vibenet yet" was a dead end on the one
                // screen where somebody has arrived wanting to see something:
                // the only route on was to leave, find the catalog, and open
                // the setup screen. The discovery list that setup screen
                // already draws works anywhere — it is keyless, needs no
                // account, and watching from here lands rows in this very
                // room.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text(VibenetRoom.headline(room, now: .now))
                        .dsText(.heading17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VibenetDiscoverySection(onWatched: {})
                }
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
                // **NO "Across N of M accounts" (prd §482 amendment,
                // 2026-08-26, user: "we don't have 'across 2 accounts'").**
                // Wallet cut its own twin the same day for a reason that
                // holds here exactly: the lit chip in the account strip
                // below already says whose money this is — "All", or one
                // account's own face — so the caption restated a control
                // sitting six points away.
                //
                // The half that was load-bearing SURVIVES, moved: when a
                // balance read fails the total silently stops covering
                // everything, and `unreachedLine` below says so in words.
                // That was always the honest part of this caption; the
                // count was chrome.
                if let nativeTotal = aggregate.nativeTotal {
                    // `price48`, Wallet's crown rung — not `price40`. The two
                    // rooms state the same kind of reading and were stating it
                    // two sizes apart.
                    //
                    // IT COUNTS UP ON ARRIVAL (prd §479). Watching your first
                    // account drops you straight into this room (§465) and the
                    // figure simply appeared — the one moment the room is
                    // certain to be watched, spent on nothing. `numericText`
                    // is the transition the app already owns (the unlock
                    // countdown's own), so this is the house grammar rather
                    // than a new effect: the crown mounts at zero and lands on
                    // the real reading one runloop later.
                    //
                    // ONE SHOT and Reduce-Motion-aware: `counted` latches, so
                    // a re-compose while somebody is reading never re-rolls
                    // the number, and with Reduce Motion on the figure is
                    // simply correct from the first frame.
                    Text("\(VibenetBalanceFormat.line(counted ? nativeTotal : 0)) ETH")
                        .dsText(.price48)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)
                        .contentTransition(.numericText())
                        .task {
                            guard !counted else { return }
                            if reduceMotion { counted = true; return }
                            // A runloop turn, so the zero really renders and
                            // the change is a transition rather than the
                            // initial value.
                            try? await Task.sleep(nanoseconds: 40_000_000)
                            withAnimation(.easeOut(duration: 0.55)) { counted = true }
                        }
                }
                // THE MOVE, WITH ITS AMOUNT (§475). Wallet states the move as
                // "▲ $224.51 (1.8%) today" — the figure FIRST, the percent in
                // parentheses — and its own note says why: the percent alone
                // cannot say how much, and the amount is what the reader is
                // actually looking at on the line above.
                if let change = VibenetValueHistory.delta(windowed),
                   let move = VibenetValueHistory.move(windowed) {
                    HStack(spacing: 5) {
                        Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .dsGlyph(9)
                        Text("\(VibenetBalanceFormat.line(abs(move))) ETH (\(VibenetBalanceFormat.percent(change)))")
                            .dsText(.callout15).fontWeight(.semibold)
                            .monospacedDigit()
                        // **NO WINDOW NAME BESIDE THE MOVE (prd §482
                        // amendment, user: "we don't have… 'since watching'").**
                        // §479 put it here so a 1W delta could not read as an
                        // all-time one — a real hazard, and the range chips
                        // under the chart now answer it: the lit chip IS the
                        // window, in the same eyeful. Wallet states its move
                        // with no window word for the same reason.
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
                if let series = VibenetValueHistory.series(windowed) {
                    TokenChartPlot(chart: TokenChart(closes: series,
                                                     price: series.last ?? 0,
                                                     change: VibenetValueHistory.delta(windowed) ?? 0),
                                   accent: TokenChartStyle.accent(
                                       change: VibenetValueHistory.delta(windowed) ?? 0, scheme: scheme),
                                   // 120, Wallet's own height for this figure.
                                   height: 120, pulses: false,
                                   lineWidth: 2.6, fillOpacity: 0.24, endpointDot: true)
                        .padding(.top, DS.Space.s3)
                    rangeStrip
                }
            }
        }
    }

    /// What sits in the fixed slot for the scope on screen.
    ///
    /// Home's is the sparkline, which the crown draws itself — so this is
    /// empty there rather than a second drawing. Every other scope steps into
    /// the same box, which is what makes the toggle land in one place.
    @ViewBuilder
    private var scopeVisual: some View {
        switch section ?? .home {
        case .home, .activity: EmptyView()
        case .holdings:        EmptyView()
        case .accounts:        EmptyView()
        case .keys:            EmptyView()
        }
    }

    /// Fixed, not fitted — see `stackedRoom`. Spelled rather than measured,
    /// because measuring it would settle the bar a frame LATE, which is the
    /// same jump arriving slower (Wallet's `walletVisualSlot`, same reason).
    private static let visualSlot: CGFloat = 210

    /// The samples the crown, the delta and the line all read (prd §479) —
    /// ONE derivation, so the figure, its move and its curve can never
    /// describe different windows.
    private var windowed: [VibenetValueSample] {
        VibenetValueHistory.windowed(history, range: range, now: .now)
    }

    /// HOW FAR BACK (prd §479) — drawn only where the book can actually
    /// answer more than one span (`options` returns empty otherwise), so this
    /// is never a row of chips redrawing one identical line.
    ///
    /// A neutral fill for the selection, never the room's mark: blue here
    /// means a key is about to expire, and which window you are looking at is
    /// not urgent.
    @ViewBuilder
    private var rangeStrip: some View {
        let options = VibenetValueHistory.options(history, now: .now)
        if options.count > 1 {
            HStack(spacing: DS.Space.s2) {
                ForEach(options, id: \.self) { option in
                    let on = option == range
                    Button {
                        DSHaptic.selection()
                        withAnimation(reduceMotion ? nil : DS.Motion.standard) { range = option }
                    } label: {
                        Text(option.label)
                            .dsText(.label12).fontWeight(.semibold)
                            .foregroundStyle(on ? DS.textPrimary : DS.textTertiary)
                            .padding(.horizontal, DS.Space.s3)
                            .padding(.vertical, 6)
                            .background(Capsule(style: .continuous)
                                .fill(on ? DS.fillStrong : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressSpring())
                    .dsHover()
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.top, DS.Space.s2)
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
    /// Every watched account, however the room in hand is scoped — so picking
    /// one cannot collapse the rail to a single face and hide it (the §475
    /// amendment; the control must never delete itself on use).
    private static func fullItems(fallback room: VibenetRoom) -> [VibenetAccountItem] {
        let full = VibenetRoomSource.card()?.items ?? []
        return full.count > 1 ? full : room.items
    }

    /// **WALLET'S OWN RAIL, NOT A LOOKALIKE (prd §482 amendment, 2026-08-26,
    /// user: "you need to do home like wallet has, and it's icons aren't like
    /// that and it also has an address book" — then "it has silouheete icons
    /// and now text to the right, and the name below the icon").**
    ///
    /// This was a hand-rolled strip of capsules: a face with its BALANCE to
    /// the right. Wallet's rail is a face with its NAME BELOW, an "All" word in
    /// a circle the same size, and a book slot — and the difference was not
    /// styling, it was that I rebuilt a component instead of calling it. Three
    /// things came back for free by calling it: the caption Wallet's §483
    /// restored (amending §450), the selection grammar (opacity and weight,
    /// never a ring — §351), and the book door in its own slot.
    ///
    /// The balance moved OUT of the chip with no loss: the crown states the
    /// scoped account's total the moment you pick one, which is the same number
    /// one line up and in the room's largest type.
    @ViewBuilder
    private var accountChips: some View {
        let strip = Self.fullItems(fallback: room)
        if strip.count > 1, let onScope {
            FaceScopeRail(
                items: VibenetScopeRail.items(strip.map(\.address)),
                scope: scopedAddress,
                // Never folded: `compact` existed for a PINNED strip that had
                // to yield height to content scrolling under it. In the content
                // there is nothing to yield to (Wallet's own note, same move).
                compact: false,
                // FALSE, so the names DRAW. The flag means "the room below
                // already names these", which was true when a roster sat under
                // the rail — on Home the list is three events, so nothing else
                // says which account is which.
                namesInRoom: false,
                matches: VibenetScopeRail.matches,
                onPick: { picked in onScope(picked ?? "") },
                onReTap: nil,
                // ONE slot, not two (§465): watching another account and seeing
                // the whole list are the same screen here, so a "+" beside the
                // book would point at the same place twice.
                addTitle: nil,
                onAdd: nil,
                bookTitle: String(localized: "Address Book"),
                onOpenBook: onOpenBook)
        }
    }

    /// The unscoped state, as a chip of its own.
    @ViewBuilder
    private var allChip: some View {
        let on = scopedAddress == nil
        Button {
            DSHaptic.selection()
            onScope?("")
        } label: {
            Text(String(localized: "All"))
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(on ? DS.textPrimary : DS.textSecondary)
                .padding(.horizontal, DS.Space.s3)
                // ONE HEIGHT FOR THE WHOLE STRIP, and it is `DS.Hit.min`
                // (prd §482 amendment): an account chip is a 36pt face plus
                // its 4pt padding, which lands on exactly 44 — so matching it
                // is both the tap-target floor and the reason the three chip
                // species read as one row rather than three sizes.
                .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min)
                .background(Capsule(style: .continuous)
                    .fill(on ? DS.fillStrong : DS.fillFaint))
        }
        .buttonStyle(.plain)
        .dsHover()
    }

    /// The book door the rail used to carry. Kept rather than dropped: it is
    /// the only way to the full list from this room, and §465's ruling that
    /// vibenet has ONE tier (watching another account and seeing the whole
    /// list are the same screen) is what makes one slot enough.
    private func bookChip(_ open: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            open()
        } label: {
            Image(systemName: "person.text.rectangle")
                .accessibilityHidden(true)
                .dsGlyph(13, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.Space.s3)
                // 27pt before this — the smallest thing in the strip and the
                // one the accessibility audit caught (§482 amendment). Same
                // 44 as its neighbours.
                .frame(minWidth: DS.Hit.min, minHeight: DS.Hit.min)
                .background(Capsule(style: .continuous).fill(DS.fillFaint))
        }
        .buttonStyle(.plain)
        .dsHover()
        .accessibilityLabel(Text(String(localized: "Address Book")))
    }

    private func accountChip(_ item: VibenetAccountItem, native: Double?) -> some View {
        // From the ONE book read in `.task`, never a fresh decode per chip.
        let samples = accountHistories[item.address.lowercased()] ?? []
        let change = VibenetValueHistory.delta(samples)
        let on = scopedAddress?.caseInsensitiveCompare(item.address) == .orderedSame
        return Button {
            DSHaptic.selection()
            // RE-TAP RETURNS TO ALL, the rail's own toggle rule — otherwise
            // the only way out of a scope is to find the All chip again,
            // which on a long strip is a scroll.
            onScope?(on ? "" : item.address)
        } label: {
            HStack(spacing: 6) {
                // **`DS.Face.list` (36) — THE AVATAR TIER, and the same size
                // this face wore in the rail this strip replaced** (prd §482
                // amendment, 2026-08-26, user: "make the account circles the
                // same size then that we have for social avatars… should
                // always be consistent"). As a passive read the `badge` mark
                // tier was right; as the room's SCOPING control it was easy
                // to miss, which was the report.
                //
                // Measured rather than assumed, because the request named two
                // sizes that are NOT the same: `FaceScopeRail` draws 36 here
                // (it passes `namesInRoom`, which pins `.list`), while the
                // source chips are 40 folded / 46 expanded. They differ
                // because a source chip is a bridge mark in a chip SLOT and
                // this is a face on the ramp — matching 46 would make account
                // faces the largest faces in the app. 36 is the tier every
                // other avatar in this app already wears.
                WalletFace(address: item.address, size: DS.Face.list, circular: true)
                // The NAME when the balance could not be read: a chip with a
                // face and nothing beside it is unidentifiable, and "couldn't
                // read" is a fact this strip can state in one word.
                if let native {
                    Text("\(VibenetBalanceFormat.line(native)) ETH")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                } else {
                    Text(Self.displayName(item.address))
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                if let change, native != nil {
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
            .background(Capsule(style: .continuous)
                .fill(on ? DS.fillStrong : DS.fillFaint))
        }
        .buttonStyle(.plain)
        .dsHover()
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

    /// THE ACCOUNTS, each with its own state (2026-08-25, prd §476).
    ///
    /// **The room had no accounts section at all**, which is the gap the goal
    /// "quickly see the accounts and keys" exposes: an account existed only as
    /// a face in the rail and a figure in a hero chip, and neither says what
    /// STATE it is in. So the one question this room is opened with — is
    /// anything locked, unlocking, undeployed, or unreadable — could only be
    /// answered by scoping to each account in turn.
    ///
    /// One row each: face, name, its state in the room's own words
    /// (`VibenetRoom.rowLine`, the same sentence the roster screen has always
    /// used, so an account never reads as two different things across two
    /// surfaces), and a tap that scopes.
    ///
    /// **An UNDEPLOYED account gets the explainer and the faucet here**, not
    /// only on its detail. Reported: *"for addresses followed but not yet
    /// deployed they are just empty."* True on this card by construction — an
    /// undeployed account has no balance, no keys and no links, so it
    /// contributed to nothing and appeared nowhere. It has one thing to say
    /// and one thing to do, and both were a tap away on a screen you had no
    /// reason to open.
    @ViewBuilder
    private var accountsCard: some View {
        let links = VibenetAccountMapping.links(room.items)
        card {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(drawn.enumerated()), id: \.element.id) { index, item in
                    // The last ROW is only the last thing in the card when
                    // there are no links folded under it — otherwise its
                    // separator is what joins the roster to the disclosure.
                    accountRow(item)
                }
                if !links.isEmpty { linkedDisclosure(links) }
            }
        }
    }

    /// **WHO CAN ACT FOR WHOM, FOLDED INTO ACCOUNTS (2026-08-25, prd §477,
    /// user's own suggestion).**
    ///
    /// §476 gave it a third section of its own, on the user's ruling that the
    /// spine is "a figure worth its own frame". They then read it in place and
    /// reversed themselves: *"i agree with you now about linked accounts is
    /// kind of placed in a weird spot after keys, what is an alternative…? we
    /// could have it be a part of the first section but is a tap to expand."*
    ///
    /// That is the right answer and it is better than either previous one. A
    /// delegate link is a fact ABOUT the accounts listed directly above it, so
    /// it belongs to that card — and after KEYS it read as a third subject
    /// because the thing between it and its own subject was a different one.
    /// Folded as a disclosure it keeps the figure (open it and the spine is
    /// exactly as it was) while costing one row when shut, which is what a
    /// relationship most people do not have should cost.
    ///
    /// Shut by default: `VibenetAccountMapping.links` is watched-to-watched
    /// only, so on most rooms this is empty and never draws at all; where it
    /// does, the count is the headline and the graph is the tap.
    @ViewBuilder
    private func linkedDisclosure(_ links: [VibenetDelegateLink]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                DSHaptic.selection()
                withAnimation(reduceMotion ? nil : DS.Motion.standard) {
                    linksOpen.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(links.count == 1
                         ? String(localized: "1 linked account")
                         : String(localized: "\(links.count) linked accounts"))
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .dsGlyph(11, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                        .rotationEffect(.degrees(linksOpen ? 90 : 0))
                }
                .padding(.vertical, DS.Space.s2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
            if linksOpen {
                VibenetLinkSpine(links: links,
                                 name: { Self.displayName($0) },
                                 onPick: onScope,
                                 reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
                // The direction moved INTO the figure as column heads
                // (prd §482), so this says only what the heads cannot: where
                // the reading came from. "Who can act for whom" was carrying
                // the whole direction from 60pt below, in tertiary ink, and
                // was the reason the drawing read backwards.
                Text(String(localized: "Read from the keystore."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
            }
        }
        // NO RULE ABOVE IT (user, 2026-08-25: *"do NOT USE HAIRLINES"*). This
        // one drew a line across the whole card to mark where the roster ended
        // and the disclosure began; `s2` of air says the same thing, and §8
        // says it is the only thing allowed to.
        .padding(.top, DS.Space.s2)
    }

    @ViewBuilder
    private func accountRow(_ item: VibenetAccountItem) -> some View {
        if let onScope {
            Button {
                DSHaptic.selection()
                onScope(item.address)
            } label: { accountRowBody(item, door: true) }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            accountRowBody(item, door: false)
        }
    }

    private func accountRowBody(_ item: VibenetAccountItem, door: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: item.address, size: DS.Face.rowCircle, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.displayName(item.address))
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // The room's OWN state sentence, never a second wording.
                    Text(VibenetRoom.rowLine(item))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if door {
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .dsGlyph(11, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            // WHAT AN UNDEPLOYED ACCOUNT HAS TO SAY, and the one thing it can
            // do about it. `undeployedExplainer` is nil for every other state
            // — an unreached account is never told why it is undeployed when
            // the truth is that we could not look (§83) — so this block is
            // silent on a healthy row rather than gated by hand.
            if let why = VibenetRoom.undeployedExplainer(item) {
                Text(why)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
                // The faucet, only where the live config actually named one —
                // an account deploys on its first transaction and a devnet
                // address needs funds to make one. A hand-off to the
                // explorer, never a write.
                if let faucet = VibenetConfig.cached()?.faucetAddress,
                   let url = URL(string: VibenetExplorer.address(faucet)) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Devnet faucet"))
                            Image(systemName: "arrow.up.right")
                        }
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                        .lineLimit(1)
                        .fixedSize()
                    }
                    .padding(.top, DS.Space.s2)
                }
            }
        }
        // NO SEPARATOR (user, 2026-08-25: *"do NOT USE HAIRLINES"*) — §8's
        // no-line rule has zero exceptions, and a one-point `fillFaint`
        // rectangle is a hairline whatever the comment beside it called it.
        // `s3` in its place: air is what this design system separates rows
        // with, and at `s2` the rows were relying on the line to be a list.
        .padding(.vertical, DS.Space.s3)
        .contentShape(Rectangle())
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
        // THE CENSUS SITS ON THE CARD, NOT IN A BOX ON IT (2026-08-25, prd
        // §478, reported: "cards in cards").
        //
        // §471 put these six rows on their own `fillFaint` radius-14 group,
        // and its reasoning was about DOORS: each row was "its own 46pt door
        // into the tray AT THAT PERMISSION", so the group was the container
        // those six destinations sat in. **§476 then deleted the doors** —
        // "they all go to the same place" — and the container outlived the
        // thing it was containing: a rounded fill inside a rounded card,
        // holding six plain reads, indented from the headline they belong to.
        //
        // A card IS a container. These rows are what this card is about, so
        // they sit on it directly, at the same left edge as the headline
        // above them, separated by the faint fill every other row group in
        // this room already uses. Nothing is lost but the second box: the
        // rows, their order and their separators are untouched.
        //
        // The 44pt hit floor §471 cites is not a claim on this block any
        // more either — these rows are reads, not targets.
        let policies = VibenetPolicyAggregation.compose(room.items)
        if !policies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(policies.enumerated()), id: \.offset) { index, entry in
                    policyRow(entry)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
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
                onOpenKeys(keyChanges?.added ?? [])
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

    /// One permission and how many keys hold it — a PLAIN READ (2026-08-25,
    /// prd §476), superseding §471's per-row door.
    ///
    /// §471 made every census row its own door into the tray, focused on that
    /// permission, on the reasoning that "a count is the one shape of fact you
    /// cannot act on" and the follow-up "Send anywhere · 4" wants is those
    /// four keys. The follow-up was right; the affordance was not. Reported:
    /// *"if you tap the card you go to a list of keys, yet each policy has a
    /// chevron which is dumb bc they all go to the same place."*
    ///
    /// And that is literally true — the tray SHOWS EVERY SECTION whatever it
    /// is handed (its own invariant: its grouping mirrors this census exactly,
    /// and a reader can only check that against a list showing all of it), so
    /// the focus was a scroll position and nothing more. Six chevrons promised
    /// six destinations that were one, which is the §83 shape wearing a
    /// disclosure glyph rather than a fake status.
    ///
    /// ONE DOOR NOW: the card's headline. These rows are what the door is
    /// ABOUT, and a census reads as a census rather than a menu.
    private func policyRow(_ entry: VibenetPolicyCount) -> some View {
        policyRowBody(entry)
    }

    private func policyRowBody(_ entry: VibenetPolicyCount) -> some View {
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
        }
        // NO SEPARATOR (user, 2026-08-25: *"do NOT USE HAIRLINES"*) — §8 has
        // zero exceptions and a one-point fill is a line.
        .padding(.vertical, DS.Space.s2)
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
                Text(String(localized: "Keys expiring"))
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
            // `ShareBar` — the app's one bar object, which this row rolled
            // its own copy of until 2026-08-26 (prd §488). Altana's key list
            // draws the same figure for the same reason, and two keystore
            // rooms drawing one figure two ways is the thing `DSSectionSwitcher`
            // was made generic on day one to avoid. The fill override is what
            // let the shared bar take this row without giving up §471's rule
            // that blue is spent on urgency and only on urgency.
            ShareBar(fraction: row.fraction(now: .now),
                     fill: urgent ? Self.mark : DS.fillStrong,
                     reduceMotion: reduceMotion)
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


    /// A watched account's own name, or its short address — the same
    /// fallback every row on this card already makes, so the spine can never
    /// name an account differently from the roster above it.
    private static func displayName(_ address: String) -> String {
        VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
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
