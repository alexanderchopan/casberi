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
    /// An address was just watched from THIS card's empty state — the
    /// discovery list §479 put there so an empty room is not a dead end.
    ///
    /// It shipped as a no-op (`onWatched: {}`), which made that list a dead
    /// control (§83) in the one place it was added to be a way out: the card
    /// is composed from a `VibenetRoom` VALUE its parent holds, so watching an
    /// account changed nothing on screen — the headline went on saying
    /// "Nothing watched on vibenet yet" over an account that was now watched,
    /// and every further tap on the list looked equally inert. Reported as
    /// both "after you follow one address you can't choose any of the others"
    /// and "it says it's not connected after i do connect it".
    ///
    /// The parent re-reads; this card never does, because a card recomposing
    /// its own source is how the two get to disagree.
    var onWatched: () -> Void = {}

    /// Raises the WATCH sheet (`VibenetWatchSheet`) — the lookup §517 made a
    /// sheet, restored to the surface §545 moved the roster to.
    ///
    /// **IT WENT MISSING, AND NOTHING COULD SEE IT.** §545 deleted
    /// `VibenetAddressBookScreen` and moved this roster onto the room's own
    /// Accounts scope — correctly — but the sheet's only presenter went with
    /// the deleted screen, so `VibenetWatchSheet` sat in the tree with no
    /// caller and the room grew a roster you could rename and unwatch from
    /// and could not ADD to. That is §472's exact regression back again: the
    /// discovery list §479 put in this card is in the EMPTY branch, so the
    /// moment you watch one account the only route to a second is to leave,
    /// find the catalog and open the setup screen — which §479's own ruling
    /// names as the dead end it exists to close.
    ///
    /// **Routed, not presented** (the reason the deleted `onRequestCreate`
    /// carried, which outlives it):
    /// this card lives inside `FeedScreen`'s List rows, and a `.sheet` on a
    /// row resolves to the same presenting controller as the screen's own
    /// single sheet — the half-open-then-close bug this codebase has now paid
    /// for four times. `FeedSheetRoute.vibenetWatch`.
    var onRequestWatch: () -> Void = {}
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

    /// **THE BOOK, BACK IN THE RAIL (prd §570, user: "one thing to make sure
    /// is that all the devnets have the book in their rails").**
    ///
    /// §545 deleted an `onOpenBook` from here and said so in a comment two
    /// hundred lines up — correctly, because the screen it opened was going
    /// away with it. This is a different destination: the SHARED address book
    /// §498 made the app's one people surface, which a vibenet address is a
    /// row in like any other. Passed from the feed rather than read from an
    /// environment, because this card takes every other destination the same
    /// way and one route here would be the only one.
    var onOpenBook: (() -> Void)? = nil

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
    // `onOpenBook` was HERE and is deleted with the screen it opened
    // (prd §545) — the roster's verbs are on the rows in this card now.

    /// The naming alert — a text-entry alert needs its text in `@State`.
    @State private var renamingAddress: String?
    @State private var renameText = ""
    /// Set only when the address being unwatched is the LAST one, which is
    /// what raises the confirm. See `unwatch`.
    @State private var removingLast: String?

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

    /// THE SCRUB (prd §501) — the sample under the finger, or nil at rest.
    ///
    /// **Wallet has had this since §297 and this room did not**, on a crown
    /// §475 built to be Wallet's crown. Both draw a `TokenChartPlot` over real
    /// samples; only one of them let you ask the line what it was worth on a
    /// given day. The plot owns the whole gesture (`ChartScrubSurface`, press
    /// then drag, a `nil` on release) — so this is a handler, not a new
    /// interaction, and the drawing is untouched.
    ///
    /// It snaps to samples that were actually recorded and never interpolates
    /// between two looks, which is `VibenetChartRange`'s own rule one layer
    /// down: the windows this room offers exist because the readings do.
    @State private var scrubIndex: Int?

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
        // **SCOPED, THE CURVE IS THAT ACCOUNT'S** (prd §495). `history` fed
        // the crown's sparkline AND its delta pill, and was loaded unscoped —
        // so narrowing the room to one account drew that account's balance
        // beside the WHOLE ROOM's change: on the device, "0.014 ETH" over
        // "▲ 0.7039 ETH (38.9%)", a rise of fifty times the stated holding.
        //
        // §83 where it is most expensive, and the data to be right has existed
        // since §467: `VibenetValueStore.samples(for:)` records a real
        // per-account history on every sweep, and `VibenetAccountDetail` has
        // read it back since §477. Only the room's own crown never did.
        //
        // The task is keyed on the SCOPE as well as the roster, or picking a
        // face leaves the previous account's curve on screen until something
        // else happens to invalidate it.
        .task(id: "\(scopedAddress ?? "")|\(room.items.map(\.address).joined(separator: ","))") {
            history = scopedAddress.map { VibenetValueStore.samples(for: $0) }
                ?? VibenetValueStore.samples()
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
    /// **ONE ACCOUNT TAKES THE CHASSIS TOO (prd §491).** This required
    /// `count > 1`, so narrowing to a single account — by the rail, or simply
    /// by watching one — swapped the whole page for `VibenetAccountDetail` and
    /// left the chassis behind: no fixed slot, no scope switcher, none of the
    /// four figures. Every drawing built for this room was invisible to a
    /// single-account user, which is the ordinary case, and the branch made it
    /// look intentional.
    ///
    /// The detail is not deleted — it draws the section the scope asks for
    /// (see its own `section` parameter), so scoping now NARROWS the room the
    /// way Wallet's does rather than replacing it.
    private var stacksIntoCards: Bool {
        onOpen == nil && room.lead != nil
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
        // **THE CHASSIS IS ITS OWN STACK, AND ITS GAPS ARE POSITIVE NUMBERS**
        // (2026-09-02 — reported as *"clipping on vibenet"*, with the scope
        // switcher cut in half along the bottom edge of the fused slab).
        //
        // The two chassis gaps were spelled as NEGATIVE bottom paddings against
        // this stack's own `s6` — `railGap - s6` and `contentGap - s6` — which
        // is only a spacing correction while something follows. On the Home
        // scope with several accounts nothing does: every branch below the slab
        // is gated on a scope this one is not, so `railSlab` is the LAST child
        // and its `-14` is not a correction, it is 14pt of the slab drawn BELOW
        // the stack. This card is one `List` row (`FeedScreen.insightSection`,
        // `listRowInsets(EdgeInsets())`) and a list cell clips to its bounds, so
        // those 14 points were cut — which lands on the switcher, the last thing
        // in the slab, and takes its bottom padding and half its picked fill
        // with it. **Measured off the screenshot**: the glass ran 96.7pt against
        // an ideal 110.7, and the difference is exactly `contentGap - s6`.
        //
        // The other three chain rooms never had it: Wallet, Hegotá and Frames
        // each mount the slab as its own `Section` with a POSITIVE
        // `listRowInsets(bottom: DSRoomChassis.contentGap)`, so there is nothing
        // to draw outside. This is that shape, expressed in a stack: the chassis
        // is one child holding the slot and the slab `railGap` apart, the room
        // it scopes is the other, and the outer stack's own spacing IS
        // `contentGap`. No view draws outside its frame, so no clip can reach
        // one — which is the point rather than the 14pt: a negative trailing
        // padding is a bet on there always being a next child, and this stack
        // has eight optional ones.
        VStack(alignment: .leading, spacing: DSRoomChassis.contentGap) {
            VStack(alignment: .leading, spacing: DSRoomChassis.railGap) {
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
                // **ONE FIXED BOX HOLDS THE CROWN *OR* THE SCOPE'S FIGURE — never
                // both stacked** (prd §491, matching Wallet's §483 spec exactly;
                // reported as *"the home toggle bar is in the wrong place, so it's
                // not like Wallet"*).
                //
                // MEASURED: Wallet's chip bar sits at 579pt and this room's sat at
                // 745 — 166pt lower — and the cause was structural rather than
                // spacing. Wallet's 210pt box contains the crown AND its chart, and
                // on any other scope the crown is REPLACED: its Positions scope
                // opens "Deposited $61,000", not the wallet total. This room kept
                // its crown on every scope and then added a 210pt box beneath it,
                // so the room was crown + 210 where Wallet is 210.
                //
                // Which means each scope owes its own headline, because it no
                // longer inherits the crown's — see `scopeFigure`.
                // **THE SLOT HOLDS ITS HEIGHT EVEN WHEN THE FIGURE DECLINES.**
                //
                // Reported as *"clicking in accounts makes the bar move around"*,
                // and measured: picking an account with no sub-accounts and no
                // links moved the chip bar from 575pt to 355pt — exactly this
                // slot's height. `.frame(minHeight:)` DOES NOT hold an `EmptyView`
                // open: a `@ViewBuilder` that produces nothing has no layout
                // presence at all, so the frame collapsed and everything below
                // jumped up a third of a screen the moment you used the control.
                //
                // The `Color.clear` underneath is what gives the frame something
                // to be applied to. It is the same class §483 recorded for Wallet
                // ("collapsing to `maxHeight: 0` is NOT the same as not emitting")
                // arriving from the opposite direction — there an empty Section
                // still took spacing, here a non-empty frame took none.
                // **ONE SLOT, AND IT IS `DSRoomSlot`** (prd §495, user: "one
                // template"). This wrapped its own `ZStack` + fixed frame + clip
                // around figures that now go through `DSRoomSlot`, which applies
                // exactly those three things — a box inside a box, and the second
                // copy of the rule Wallet was also keeping.
                //
                // Home draws the crown, which names itself at the headline rung, so it
                // passes no headline; the row is still RESERVED, which is what
                // keeps its first pixel level with every other scope's and what
                // clears the settings gear.
                Group {
                    if (section ?? .home) == .home {
                        // The crown IS the headline here too — see Wallet's
                        // own Home slot and `reservesHeadline`.
                        DSRoomSlot(headline: nil, reservesHeadline: false) { balanceHero }
                    } else {
                        scopeVisualDissolving
                    }
                }
                // **ONE SLAB, WHERE THERE WERE TWO STRIPS** (prd §547) — and the
                // `switcherGap` correction between them goes with the pair it
                // separated. `DSRoomRailSlab` owns the distance now, and it is the
                // same distance in all three rooms rather than a negative padding
                // against this card's own `s6` stack spacing.
                railSlab
            }
            // Everything the chassis scopes, in one child so the gap above it is
            // the outer stack's `contentGap` and the gaps BETWEEN these cards
            // stay `s6` — §471's ruling ("separation by surface only works once
            // the gap is wide enough to be seen as a gap"), untouched.
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                // THE SCOPED ACCOUNT'S OWN DETAIL, under the scope that owns each
                // part of it (prd §491) — keys under Permissions, links and
                // sub-accounts under Accounts, the record under Activity.
                if scopedToOneAccount, let lead = room.lead {
                    let fullItems = Self.fullItems(fallback: room)
                    VibenetAccountDetail(
                        item: lead,
                        links: VibenetAccountMapping.links(fullItems),
                        sharedKeys: VibenetKeyReuse.sharing(lead, in: fullItems),
                        // The chassis draws the face in the rail above.
                        showsFace: false,
                        section: section ?? .home,
                        onScope: onScope,
                        onOpenKey: onOpenKey.map { open in
                            { actor in open(actor, lead, VibenetKeyReuse.sharing(lead, in: fullItems)) }
                        },
                        newKeyIDs: keyChanges?.added ?? [])
                }
                if shows(.holdings) { holdingsCard }
                // **THE AMOUNTS THE MAP GAVE UP (prd §491).** Stripping the figures
                // out of the treemap is only honest where a list carries them, and
                // Wallet has had `walletTokenListSection` under its map all along
                // while this scope had NOTHING below the drawing — so the same cut
                // that merely de-duplicated Wallet would have deleted this room's
                // amounts outright.
                //
                // Same source as the map, never a second derivation: one call to
                // `VibenetBalanceTreemap.cells` would otherwise become two, and a
                // list that disagrees with the picture above it is worse than
                // either alone.
                if promoted(.holdings) { holdingsList }
                // **WHO THESE ACCOUNTS MOVE TOKENS WITH (prd §507).** The room
                // could say what an account HOLDS and never what MOVED — there
                // was not one `Transfer` topic in the bridge — so Holdings was a
                // number with no motion behind it and Activity was key changes
                // only. Under the list rather than in the figure slot: the
                // treemap answers "what", this answers "with whom", and the two
                // are one reading at two grains, the same relation the amounts
                // list above already has to the map.
                if promoted(.holdings) { movesList }
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
                if shows(.permissions) {
                    if section == nil { sectionHeader(String(localized: "Keys")) }
                    // THIS PHONE'S OWN KEY LEADS THE SCOPE (prd §522).
                    //
                    // Above the census rather than inside it, because the census
                    // answers "what can act for these accounts" and this answers
                    // "what can THIS DEVICE do" — the second question is the one
                    // somebody opens Permissions with once they have a key, and
                    // burying it in a list of other people's authenticators is how
                    // §386p's panel lost its own subject.
                    //
                    // Drawn in every shape of this scope, scoped or not: the key
                    // belongs to the phone and not to whichever account happens to
                    // be selected, so narrowing the room must not narrow it away.
                    VibenetThisPhoneRow()
                        .padding(.horizontal, DSRoomChassis.contentInset)
                    // The census card stands down under its own scope — the
                    // capability rungs ARE that census, drawn in the slot above.
                    if !promoted(.permissions) { keysCard }
                }
                // EVERY KEY, GROUPED BY THE ACCOUNT IT CAN ACT FOR (user pick of
                // two mocked lists, prd §491).
                //
                // **NOT WHEN THE DETAIL IS ALREADY DRAWING THEM** (prd §495).
                // Scoped to one account with Permissions picked, this room drew
                // the SAME KEY TWICE in two different row designs, one under the
                // other: `VibenetAccountDetail` above renders its own key list
                // under `wants(.permissions)`, and then this ran as well. Found by
                // walking the screen — every check in the tree is green over it,
                // because two correct lists of one key is not a wrong number, it
                // is a wrong page.
                //
                // The room's list stands down rather than the detail's, and the
                // reason is in this list's own title: it groups keys BY THE
                // ACCOUNT they act for, which over a single account is a heading
                // above the only group. The detail's list groups by CAPABILITY
                // ("Limited keys"), which is the reading that still says something
                // once the account is fixed.
                if promoted(.permissions), !scopedToOneAccount { permissionsList }
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
                // scope happens to be last — in `.permissions` it would be a footnote
                // about accounts under a census of keys.
                if shows(.accounts), let note = VibenetRoom.note(room, drawn: drawn.count) {
                    // **INDENTED TO THE ROW'S TEXT COLUMN** (prd §495, user: *"the
                    // indentation issues here should maybe be where the
                    // transactions start or middle aligned w/ the icon? i dunno
                    // looks weird"*).
                    //
                    // It read as a footnote on the whole LIST because it sat flush
                    // with the faces, while what it actually explains is the one
                    // row above it — the account that is "Not established yet".
                    // Aligning it with that row's TEXT is what says so, and it
                    // uses the row's own leading column so the two can never
                    // drift apart.
                    Text(note)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.leading, DS.Face.rowCircle + DS.Space.s2)
                }
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
    /// **THE FUSED RAIL** (prd §547, 2026-09-01) — what `accountChips` and
    /// `scopeStrip` were, as one slab.
    ///
    /// `scopeStrip` is gone as a property: `DSRoomRailSlab` owns the switcher
    /// for all three rooms, so a per-room copy of it could only be a place for
    /// the three to drift apart again. Its two live rulings moved here intact —
    /// the `.home` default below, and its "no top padding of its own", which
    /// the slab now enforces structurally rather than by comment (there is no
    /// gap left to state, the container owns it).
    ///
    /// The STATED COST it carried is unchanged and worth repeating: in the
    /// content this SCROLLS AWAY, which is §357's complaint one level down — a
    /// scope control you cannot reach while deep in the rows it scopes. Fusing
    /// does not fix that; it makes the eventual fix cheaper, since there is one
    /// view to pin instead of two.
    @ViewBuilder
    private var railSlab: some View {
        let strip = Self.fullItems(fallback: room)
        let showsSwitcher = onPickScope != nil && VibenetSection.shows(present: scopes)
        if showsRailDeck(strip) || showsSwitcher {
            DSRoomRailSlab(
                showsRail: showsRailDeck(strip),
                showsSwitcher: showsSwitcher,
                sections: scopes,
                // `.home`, not `.holdings` — §491's amendment, and the same
                // default `resolve` has always fallen back to. Left at
                // `.holdings` this lights the wrong chip on the room's own
                // opening screen, which is a control disagreeing with what is
                // drawn above it.
                active: section ?? .home,
                attention: scopeAttention,
                onPick: { picked in onPickScope?(picked) }
            ) {
                accountChips
            }
        }
    }

    /// The rail deck's gate, spelled once so `railSlab` cannot ask it and
    /// `accountChips` answer differently — the failure that leaves a slab with
    /// a deck-shaped hole in it.
    private func showsRailDeck(_ strip: [VibenetAccountItem]) -> Bool {
        strip.count > 1 && onScope != nil
    }

    /// Whether a scope's content draws. nil `section` means the whole room in
    /// one scroll, which is what the management roster and the single-account
    /// branch want — so the scoped feed room narrows and every other caller is
    /// untouched by construction rather than by a flag each has to pass.
    private func shows(_ candidate: VibenetSection) -> Bool {
        section == nil || section == candidate
    }

    /// Whether this scope's figure has been PROMOTED into the slot above, and
    /// so must not be drawn a second time in the card below it (prd §491).
    ///
    /// `shows(_:)` is true for a scope's own card AND for the unscoped room,
    /// which is exactly right for the card and exactly wrong for the figure:
    /// standing in Holdings, the treemap is in the slot AND `holdingsCard`
    /// still holds one, so the room drew the same picture twice on one screen
    /// — §208's "never say one thing twice", committed by the fix for the gap
    /// above it. Unscoped, nothing is promoted and every card keeps its own
    /// figure, which is the behaviour the room had before scopes existed.
    private func promoted(_ candidate: VibenetSection) -> Bool {
        section == candidate
    }

    /// Whether the face rail has narrowed this room to ONE account — in which
    /// case `VibenetAccountDetail` is on screen above, drawing that account's
    /// own readings, and any room-wide list of the same thing is the second
    /// copy (prd §495).
    ///
    /// The same test `stackedRoom` uses to decide whether to draw the detail
    /// at all, spelled once so the two can never disagree about which of them
    /// owns a reading.
    private var scopedToOneAccount: Bool {
        room.lead != nil && room.items.count == 1
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
                    VibenetDiscoverySection(onWatched: onWatched)
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
    /// The crown's figure while a finger is on the line (prd §501).
    ///
    /// Falls back to the count-up's own value at rest, so §479's arrival roll
    /// is untouched: the two never run at once, because the count-up latches
    /// on the first pass and the scrub cannot begin before the chart exists.
    private func scrubbedTotal(_ nativeTotal: Double) -> Double {
        guard let scrubIndex,
              let series = VibenetValueHistory.series(windowed),
              series.indices.contains(scrubIndex) else { return counted ? nativeTotal : 0 }
        return series[scrubIndex]
    }

    /// The move sentence's pair while scrubbing — (amount, percent).
    ///
    /// Returns the resting pair untouched when nothing is under the finger, so
    /// a room at rest states exactly what it has always stated.
    private func scrubbedMove(resting: (Double, Double)) -> (Double, Double) {
        guard let scrubIndex,
              let series = VibenetValueHistory.series(windowed),
              series.indices.contains(scrubIndex),
              let first = series.first else { return resting }
        let move = series[scrubIndex] - first
        // A zero start has no percentage, and inventing one ("+∞%") over
        // somebody's balance is the §83 confident-wrong-answer this room
        // spends its honesty rails avoiding.
        return (move, first == 0 ? 0 : move / abs(first) * 100)
    }

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
                    // **`stat24` — the rung every scope headline in this room
                    // takes (prd §551).** It was `price48` to match Wallet's
                    // crown, and Wallet's has come down here with it: the two
                    // rooms still state the same kind of reading at the same
                    // size, which was the whole point of pinning them
                    // together, and they now also state it at the same size as
                    // the four scopes one chip away. Using the strip used to
                    // change the type scale of the screen.
                    //
                    // DOWN rather than up, and measured — see `DSRoomSlot`'s
                    // own note: at `price40` this room's own "Nothing is
                    // shared" and "Nothing deployed yet" overflow the line and
                    // get shrunk to whatever their string allows.
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
                    Text("\(VibenetBalanceFormat.line(scrubbedTotal(nativeTotal))) ETH")
                        .dsText(.stat24)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        // **0.9, not 0.6 (prd §491).** Both rooms set the same
                        // rung — `stat24` since §551 — and on the device this rendered
                        // at about 55% of Wallet's, which reads as two different
                        // type scales rather than one. The cause was not the
                        // tier but this floor: "2.514 ETH" is a longer string
                        // than "$33K", so a permissive floor let it shrink far
                        // below the rung it declares. A crown that silently
                        // renders at 29pt where its neighbour renders at 48 is
                        // not the same crown, whatever the source says.
                        //
                        // It still needs SOME give — an unlucky balance can run
                        // long — but the give is now a nudge rather than a
                        // different size class.
                        .minimumScaleFactor(0.9)
                        .padding(.top, 2)
                        // Tabular, because it rolls — see `LiveTimeText` (prd §586).
                        .monospacedDigit()
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
                if let resting = VibenetValueHistory.delta(windowed),
                   let restingMove = VibenetValueHistory.move(windowed) {
                    // WHILE SCRUBBING IT DESCRIBES THE SCRUBBED SAMPLE
                    // (prd §501, Wallet's `moveLine` rule, same reasoning):
                    // the figure above has rolled to a past reading, so a
                    // sentence still stating the whole window's move puts two
                    // different moments one line apart. Measured from the
                    // window's first sample to the one under the finger — the
                    // same measurement with a different end point, so there is
                    // no second derivation to disagree with the first.
                    let scrubbed = scrubbedMove(resting: (restingMove, resting))
                    let move = scrubbed.0
                    let change = scrubbed.1
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
                // **NO "4 accounts · 2 locked" (prd §491).** Two reasons and
                // they point the same way. It is the same class of line the
                // user cut from Wallet's crown on 2026-08-26 (*"remove
                // 'watched' and 'mostly eth'"*) — a standing fact restating
                // what the strip below already shows, since the account rail
                // IS the account count and a locked account wears its own pill
                // there. And it is what made this crown overflow: the box is a
                // hard 210pt shared with the chart, so a third line pushed the
                // range chips off the bottom, clipped.
                //
                // `unreachedLine` below is NOT this and stays: it appears only
                // when a read failed, and it is what keeps the total from
                // being a silent claim about accounts nobody could see.
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
                // The chart sits INSIDE the crown, inside the one fixed box —
                // Wallet's shape exactly, where the crown and its chart are one
                // figure sharing the slot. It travelled out to `scopeVisual`
                // for a few minutes on the way to this and left Home with no
                // chart at all; it is drawn here and nowhere else.
                homeFigure
            }
        }
    }

    /// What sits in the fixed slot for the scope on screen.
    ///
    /// Home's is the sparkline, which the crown draws itself — so this is
    /// empty there rather than a second drawing. Every other scope steps into
    /// the same box, which is what makes the toggle land in one place.
    /// **EVERY SCOPE'S DRAWING ALREADY EXISTED — none of these is new**
    /// (2026-08-26, prd §491, Wallet's §483 move applied here).
    ///
    /// The slot was `EmptyView()` on all five while the treemap, the shelf and
    /// the spine sat in cards a scroll BELOW the strip that names them. So the
    /// room asked "which reading?" and then answered with the same wall of
    /// cards whichever chip you picked — a control that scoped the list and
    /// left the picture behind.
    ///
    /// The promotion is the whole change, and it is deliberately not a
    /// redrawing: each figure is the component that was already there, bare
    /// (§483: *"we don't do cards"*), with its own eyebrow dropped because the
    /// chip one row down already says the word. What stays below is the DETAIL
    /// the drawing summarises — the same overview→detail pair Wallet's Risk
    /// scope keeps with its lending cards.
    @ViewBuilder
    private var scopeVisual: some View {
        switch section ?? .home {
        // Home's is the crown's own sparkline, which is why the slot is not
        // emitted there at all rather than emitted empty (see `stackedRoom`).
        //
        // **Activity has no drawing YET, and empty is the honest state.** Its
        // events are `VibenetKeyMoment`s — a grant or a revocation at a block
        // — not money moving, so Wallet's flow band is a borrowed shape that
        // would say nothing here. What the data supports is a timeline of
        // authorizations against revocations, which is a figure this app does
        // not have; inventing one to fill the box is how a slot gets a
        // drawing that means less than the rows beneath it.
        // Home's box is the crown itself (`balanceHero`), so it never
        // reaches here — see `stackedRoom`.
        case .home:            EmptyView()
        case .activity:        activityFigure
        case .holdings:        holdingsFigure
        case .accounts:        accountsFigure
        case .permissions:     permissionsFigure
        }
    }

    /// `scopeVisual` with §501's arrival on it.
    ///
    /// Wrapped here rather than inside each case so the four figures cannot
    /// disagree about the beat — the `DSRoomChassis` lesson one layer in: the
    /// PARTS were already shared and the timing between them was not.
    @ViewBuilder
    private var scopeVisualDissolving: some View {
        scopeVisual.roomFigureDissolve(section ?? .home)
    }

    /// THE VALUE OVER TIME — Home's figure, and it goes through the SLOT
    /// rather than living inside the crown (prd §491).
    ///
    /// It was nested in `balanceHero`, which put the bar in a different place
    /// on Home than on every other scope in two separate ways. Suppressing it
    /// off Home fixed the gross case (the chart AND a scope's drawing, stacked)
    /// and pinning it to `visualSlot` fixed most of the rest — but a nested
    /// figure still misses the inter-element spacing the sibling slot gets, so
    /// Home stayed about 24pt high. Two fixes for one guarantee is a sign the
    /// guarantee is being defended in the wrong place: Home is not a special
    /// case, it is the scope whose figure happens to be a chart.
    ///
    /// So `stackedRoom` emits the slot on EVERY scope now and this is what
    /// fills it on Home. One code path, one geometry, and the bar cannot walk.
    @ViewBuilder
    private var homeFigure: some View {
        if let series = VibenetValueHistory.series(windowed) {
            VStack(alignment: .leading, spacing: 0) {
                TokenChartPlot(chart: TokenChart(closes: series,
                                                 price: series.last ?? 0,
                                                 change: VibenetValueHistory.delta(windowed) ?? 0),
                               accent: TokenChartStyle.accent(
                                   change: VibenetValueHistory.delta(windowed) ?? 0, scheme: scheme),
                               // **THE BOX, NOT 120 (prd §588)** — the same
                               // EXPRESSION Wallet and Hegotá draw, with this
                               // room's own two terms. The box is the whole
                               // `visualSlot` because Home passes
                               // `reservesHeadline: false`; the chrome is 78,
                               // being `stat24` 30 + the delta row 22 + the
                               // card's own `.padding(.vertical, s2)` 20 + the
                               // 6 above the plot. It is 30 LESS than Wallet's
                               // because §491 took the range strip off this
                               // room and not that one — which is exactly why
                               // this is not a shared constant.
                               height: DSRoomChassis.crownLine(box: DSRoomChassis.visualSlot,
                                                               chrome: 78),
                               pulses: false,
                               lineWidth: 2.6, fillOpacity: 0.24, endpointDot: true,
                               // THE SCRUB (prd §501) — Wallet's own handler,
                               // on Wallet's own plot. The cursor and the
                               // gesture are the plot's; this room only says
                               // which sample is under it.
                               cursorIndex: scrubIndex,
                               onScrub: { scrubIndex = $0 })
                // **NO RANGE STRIP (user ruling, prd §491: "you still have this
                // on vibenet but not on wallet remove it please").**
                //
                // Wallet has the same control — `WalletRange.offered(for:)`,
                // gated on having enough history to offer a window — and this
                // room's own gate (`VibenetValueHistory.options`) is the same
                // shape. They diverged on DATA, not design: the demo wallet has
                // too few samples to offer a range, this room's demo has a long
                // series, so one showed chips and the other did not. The two
                // rooms are meant to read identically, and identical is now the
                // ruling rather than an accident of what each corpus holds.
                //
                // **What is given up is real and is Wallet's own trade**
                // (§482 added this strip so a 1W delta could not be misread as
                // an all-time one): the delta above no longer names its window
                // anywhere. `range` stays `.all` — the whole record — which is
                // the one window that cannot be mistaken for a shorter one.
            }
        }
    }

    /// Every holding with its amount, under the map that shows their shares.
    ///
    /// Ordered by the map's own ranking (`cells` is already sorted), so the
    /// biggest cell and the top row are the same token — a list re-sorted by
    /// name would make the reader re-find in the list what they just saw in
    /// the picture.
    @ViewBuilder
    private var holdingsList: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            let cells = VibenetBalanceTreemap.cells(aggregate)
            if !cells.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.element.symbol) { index, cell in
                        HStack(spacing: DS.Space.s3) {
                            AssetMark(name: cell.symbol, size: DS.Face.list)
                            Text(cell.symbol)
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Text(cell.amount)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textSecondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .padding(.vertical, DS.Space.s2)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, DSRoomChassis.contentInset)
            }
        }
    }

    /// WHO THE TOKENS MOVED WITH (prd §507) — ranked by how many moves, and
    /// deliberately never by amount.
    ///
    /// Two tokens with no shared unit and no price cannot be compared by
    /// size: ordering by amount would silently rank 500 USDV against 12 NFV,
    /// the comparison `VibenetBalanceAggregate` refuses one card up and
    /// `PrivacyPoolsRoom` refuses in its own room. The count is a real
    /// ordering over a mixed ledger; a total is not.
    ///
    /// Silent with nothing to show, like every other list here — and the
    /// footnote is not decoration: the transfer read is BOUNDED
    /// (`VibenetRead.transferChunks`), so on a busy account this is a ranking
    /// over what we could read rather than over everything that ever
    /// happened, and a ranking that does not say so is the §307 truncation
    /// wearing a leaderboard.
    @ViewBuilder
    private var movesList: some View {
        let moves = VibenetLedger.counterparties(room.allTransfers)
        if !moves.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(String(localized: "Who it moves with"))
                ForEach(Array(moves.enumerated()), id: \.element.id) { index, party in
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: party.address, size: DS.Face.list, circular: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.displayName(party.address))
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Text(party.line)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: DS.Space.s2)
                    }
                    .padding(.vertical, DS.Space.s2)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                if room.items.contains(where: \.transfersCapped) {
                    Text(String(localized: "Ranked over the transfers this device could read"))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.Space.s2)
                }
            }
            .padding(.horizontal, DSRoomChassis.contentInset)
        }
    }

    /// WHAT THE ACCOUNTS HOLD — the treemap, lifted out of `holdingsCard`.
    @ViewBuilder
    private var holdingsFigure: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            let cells = VibenetBalanceTreemap.cells(aggregate)
            if cells.isEmpty {
                // **AN EMPTY HOLDINGS IS AN ANSWER (2026-08-27).** This is
                // §495's own ruling — *"for empty states or when there is
                // only one item we need to fill it better"* — reaching the
                // one scope that pass missed. Accounts and Permissions each
                // got a figure that says what the silence means; Holdings
                // drew nothing at all, so scoping the room to an account
                // with nothing to report opened a blank 210pt box.
                holdingsEmptyFigure(aggregate)
            } else {
                // **NO HEADLINE ON HOLDINGS (user, prd §491: "wallet doesn't
                // show the total").** Every other scope needs one because it
                // replaced the crown and would otherwise open on a picture
                // with nothing naming its magnitude — but this drawing names
                // itself: each cell carries its token and its amount, so a
                // total above it is the figure said twice, once in a form that
                // cannot be broken down and once in the form that can.
                //
                // Wallet's Holdings scope has no headline for the same reason,
                // while its Positions ("Deposited $61,000") and Risk ("Room to
                // move") both do. A headline is per-scope, not per-slot.
                scopeFigure(headline: nil) {
                    // **THE BOX, NOT 120 (prd §588).** The `maxHeight` below
                    // was doing nothing for HEIGHT: the block pinned its own
                    // frame at 120, so that modifier only decided where a
                    // 120pt drawing sat inside the box — which is why growing
                    // the box to 256 would have read as 136pt of dead air
                    // under the treemap rather than as a bigger treemap. The
                    // height is handed IN now; the alignment is kept for the
                    // case it really governs, a block that declines to fill.
                    VibenetHoldingsBlock(cells: cells, reduceMotion: reduceMotion,
                                         drawnHeight: DSRoomChassis.figureSlot)
                        // **CLEARS THE GEAR, and fills what is left.** The room's
                        // settings button is an overlay on the trailing top of
                        // this whole block, and a figure with no headline starts
                        // at the very top — so the treemap's top-right cell drew
                        // UNDER it (measured: the gear sat on the NFV cell).
                        // Every other scope's figure is pushed down by its own
                        // headline; this one has none by ruling (§491: Wallet
                        // shows no total here either), so it takes the same
                        // clearance explicitly.
                        // The 44pt gear-clearance padding is GONE (§495):
                        // `scopeFigure` reserves the headline row for every
                        // scope now, which is the clearance, and doing it
                        // there means Holdings' drawing starts at the same y
                        // as every other scope's instead of 44pt lower.
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    /// WHAT AN EMPTY HOLDINGS MEANS — and the three causes it separates.
    ///
    /// A scope with no cells renders identically whatever the reason, and the
    /// reasons are not equally interesting: an account the chain did not
    /// answer for is a fact about the READ, an account that has not deployed
    /// is a fact about the ACCOUNT, and an account that answered and holds
    /// nothing is a real reading. Saying "nothing" for all three is the
    /// difference between "we could not look" and "we looked and there is
    /// nothing" — the same distinction `VibenetAccountSheet` already draws,
    /// in the same order, which is why this mirrors that function rather than
    /// inventing a second ranking of the same three states.
    ///
    /// Scoped it speaks about ONE account; unscoped about the set.
    @ViewBuilder
    private func holdingsEmptyFigure(_ aggregate: VibenetBalanceAggregate) -> some View {
        scopeFigure(headline: holdingsEmptyHeadline(aggregate)) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                // The treemap that is not there, drawn as its own outline —
                // the dashed circle `accountsEmptyFigure` uses for a missing
                // counterpart, in the shape this scope would have drawn.
                RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                    .strokeBorder(DS.fillLine,
                                  style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    .frame(height: 76)
                    .opacity(0.6)
                Text(holdingsEmptyLine(aggregate))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// The empty figure's headline. Never a number: there is nothing to count.
    private func holdingsEmptyHeadline(_ aggregate: VibenetBalanceAggregate) -> String {
        if aggregate.unreachedCount == aggregate.accountCount {
            return String(localized: "Couldn't be read")
        }
        if let one = scopedItem, !one.established {
            return String(localized: "Nothing deployed yet")
        }
        return String(localized: "Holds nothing")
    }

    /// The sentence under it, in `VibenetAccountSheet.detailLine`'s own cause
    /// order — unread before undeployed before genuinely empty.
    ///
    /// `locked` is deliberately NOT a cause here, unlike in that function: a
    /// locked account still HOLDS what it holds (the demo's own locked
    /// fixture carries a native balance), so the lock says nothing about why
    /// this box is empty and naming it would answer a question nobody asked.
    private func holdingsEmptyLine(_ aggregate: VibenetBalanceAggregate) -> String {
        if let one = scopedItem {
            if !one.reached {
                return String(localized: "This account could not be read on the last refresh.")
            }
            if !one.established {
                return String(localized: "The account deploys with its first transaction — until then there's nothing to read.")
            }
            return String(localized: "The chain answered, and this account holds nothing yet.")
        }
        if aggregate.unreachedCount == aggregate.accountCount {
            return String(localized: "None of these accounts could be read on the last refresh.")
        }
        return String(localized: "The chain answered, and none of these accounts holds anything yet.")
    }

    /// The one account this room is scoped to, or nil when it shows the set.
    ///
    /// Reads the ROOM rather than `scopedAddress`, so it can never disagree
    /// with what the figure above it was composed from: the room is already
    /// filtered by `VibenetRoom.scoped(to:)` before it reaches this card.
    private var scopedItem: VibenetAccountItem? {
        guard scopedAddress != nil, room.items.count == 1 else { return nil }
        return room.items.first
    }

    /// A scope figure's frame: its own headline, then the drawing.
    ///
    /// **The headline is what the crown used to lend it.** Every scope but Home
    /// now REPLACES the crown rather than sitting under it (see `stackedRoom`),
    /// so a figure with no headline opens on a picture with nothing naming its
    /// magnitude — which would be worse than the stacking it fixed.
    ///
    /// `stat24` — the rung the crown itself takes since §551. Every scope
    /// states ONE reading of the room and the crown states another, so they
    /// are peers; they were two rungs apart, and picking a chip changed the
    /// type scale of the screen.
    @ViewBuilder
    private func scopeFigure<Figure: View>(headline: String?,
                                           @ViewBuilder figure: @escaping () -> Figure) -> some View {
        // **`DSRoomSlot` IS THE TEMPLATE NOW** (prd §495, user: "one
        // template"). Everything this function used to spell — the reserved
        // headline row, the inset, the fixed height, the top alignment, the
        // clip — lives in one type that Wallet draws through as well. This
        // stays as a name the room's own call sites already read, and adds
        // nothing of its own; a room that re-adds a rule here is a room
        // building its sixth template.
        DSRoomSlot(headline: headline, figure: figure)
    }

    /// WHERE THE CHANGES LANDED — the Activity scope's drawing (prd §491,
    /// user pick of three).
    ///
    /// The slot was empty here and empty was the honest state: Wallet's flow
    /// band is money and these events are not, so borrowing it would have been
    /// a shape saying nothing. This is the pairing the data really carries —
    /// event kind and the account it landed on, both stamped on every
    /// `VibenetKeyMoment` — and it says the one thing a chronological list
    /// cannot: which account is churning.
    @ViewBuilder
    private var activityFigure: some View {
        let flow = VibenetChangeFlow.flow(room.items.map {
            (address: $0.address, moments: $0.history, locked: $0.locked)
        })
        if let flow {
            // Through `scopeFigure` like every other scope (prd §495) — the
            // card drew its own headline, which is what made this scope's
            // drawing start at a different y from the rest.
            scopeFigure(headline: VibenetChangeFlow.headline(flow)) {
                VibenetChangeFlowCard(flow: flow,
                                      name: { Self.displayName($0) },
                                      onPick: onScope,
                                      reduceMotion: reduceMotion)
            }
        } else {
            activityEmptyFigure
        }
    }

    /// WHAT AN EMPTY ACTIVITY MEANS — and why the toggle bar was walking
    /// again (2026-08-29, reported: *"the toggle bar moves to different
    /// spaces on the screen when you click it"*).
    ///
    /// **This is the fourth instance of ONE class, and the first three are
    /// already written down two hundred lines up: a `@ViewBuilder` that
    /// produces nothing has no layout presence at all.** `scopeVisual`
    /// emitted NO SLOT on Activity whenever `VibenetChangeFlow.flow` returned
    /// nil, so `DSRoomChassis.visualSlot` — a fixed 210pt — simply was not in
    /// the stack, and the account rail, the scope strip and every row under
    /// them jumped a third of a screen the moment that chip was picked. The
    /// box never moved; it stopped existing.
    ///
    /// And nil is the ORDINARY case, not an edge: `flow` needs an authorized
    /// or revoked moment or a lock somewhere in the roster, so an account
    /// whose keys have never changed — every freshly watched one — takes this
    /// branch. Holdings (§495) and Accounts (§495) were each given an empty
    /// figure when they had exactly this fault, in the same pass; Activity was
    /// the one figure that pass missed, for the reason its own doc gives — it
    /// had been legitimately empty by ruling until §491 gave it a drawing, so
    /// it did not read as a scope that was declining.
    ///
    /// The three causes are separated in `holdingsEmptyLine`'s own order —
    /// unread, then never deployed, then genuinely quiet — because "we could
    /// not look" and "we looked and nothing has happened" are different
    /// answers, and this is the room whose whole subject is who can act for
    /// your accounts (§83).
    @ViewBuilder
    private var activityEmptyFigure: some View {
        let subject = scopedAddress ?? room.items.first?.address
        scopeFigure(headline: activityEmptyHeadline) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                // The band that is not there, drawn as its own outline — the
                // grammar `holdingsEmptyFigure` states ("the treemap that is
                // not there") in the shape THIS scope would have drawn: one
                // flow row, its account's real face and the ribbon's outline
                // with nothing running through it.
                //
                // The ribbon is dashed and EMPTY rather than absent, and it
                // carries no kind: a ribbon in `authorized`'s colour would
                // draw a change that never happened, which on this screen is
                // the §83 failure `accountsEmptyFigure` refuses a connector
                // for.
                HStack(spacing: DS.Space.s3) {
                    if let subject {
                        WalletFace(address: subject, size: DS.Face.rowCircle, circular: true)
                    }
                    Capsule(style: .continuous)
                        .strokeBorder(DS.fillLine,
                                      style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                        .frame(height: 22)
                        .opacity(0.6)
                }
                Text(activityEmptyLine)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// The empty figure's headline. Never a number — `VibenetChangeFlow
    /// .headline` counts events and there are none to count.
    ///
    /// "Nothing has changed" is `VibenetChangeFlow.spoken`'s own sentence for
    /// this state, reused rather than reworded so the drawing and its spoken
    /// form cannot say two different things about one reading.
    private var activityEmptyHeadline: String {
        if !room.items.isEmpty, room.items.allSatisfy({ !$0.reached }) {
            return String(localized: "Couldn't be read")
        }
        if let one = scopedItem, !one.established {
            return String(localized: "Nothing deployed yet")
        }
        return String(localized: "Nothing has changed")
    }

    /// The sentence under it. Scoped it speaks about ONE account; unscoped
    /// about the roster, `holdingsEmptyLine`'s own split.
    private var activityEmptyLine: String {
        if let one = scopedItem {
            if !one.reached {
                return String(localized: "This account could not be read on the last refresh.")
            }
            if !one.established {
                return String(localized: "The account deploys with its first transaction — until then there's no history to read.")
            }
            return String(localized: "The chain answered: no key has been granted or revoked on this account.")
        }
        if !room.items.isEmpty, room.items.allSatisfy({ !$0.reached }) {
            return String(localized: "None of these accounts could be read on the last refresh.")
        }
        return String(localized: "The chain answered: no keys have been granted or revoked on these accounts.")
    }

    /// WHO CAN ACT FOR WHOM — the delegate spine, lifted out of its
    /// disclosure.
    ///
    /// **It was folded behind a chevron** (`linkedDisclosure`, §477) because it
    /// was one figure among many in a long card and had to earn its height.
    /// As the scope's lead it IS the height — a spine you must open to see is
    /// a drawing that loses to the list under it, and this scope exists to put
    /// the picture first.
    @ViewBuilder
    private var accountsFigure: some View {
        // **THE SUB-ACCOUNT WEB LEADS, the delegate spine is the fallback**
        // (prd §491, user pick of three drawings).
        //
        // The spine draws watched↔watched links, so it says NOTHING for
        // somebody watching one account — the ordinary case — and its subject
        // is the same relationship the web covers more completely: a
        // sub-account is an account that authorized you. The web also carries
        // the half the spine structurally cannot, an account you can act for
        // and do NOT watch, which is the only row here that can offer to do
        // anything.
        //
        // The spine survives where the web declines and links exist — two
        // watched accounts that delegate to each other but expose no
        // sub-account read.
        // **PER ACCOUNT, and unscoped that means the first account that HAS
        // any** — not the lead unconditionally. A sub-account is an account
        // that authorized ONE address, so the drawing has exactly one owner
        // and aggregating several owners' nodes into one web would attribute
        // a relationship to an account that does not hold it (§83, on the
        // screen where the whole reading is who can act for whom).
        //
        // Scoped, it is the scoped account's own web or nothing — never
        // another account's, which is what makes picking a face narrow the
        // reading rather than change the subject.
        let owner = scopedAddress.flatMap { scoped in
            room.items.first { $0.address.caseInsensitiveCompare(scoped) == .orderedSame }
        } ?? room.items.first { !$0.subAccounts.isEmpty }
        let web = owner.flatMap {
            VibenetAccountWeb.web(owner: $0.address, subAccounts: $0.subAccounts)
        }
        // **THE LINKS COME FROM THE FULL ROOM, never `room.items`** (prd
        // §495). A link relates TWO accounts, so a scoped room — one item —
        // can never produce one, and reading the scoped list made this figure
        // answer "nothing is shared" directly above a list saying "…9a0b ·
        // you can act for them". Two answers to one question, one scroll
        // apart, on the screen whose whole subject is who can act for whom
        // (§83). `VibenetAccountDetail` is handed `links(fullItems)` at both
        // of its call sites for exactly this reason; the figure had been
        // reading the narrower list since it was written.
        let links = VibenetAccountMapping.links(Self.fullItems(fallback: room))
        if let web {
            scopeFigure(headline: VibenetAccountWeb.headline(web)) {
                VibenetAccountWebCard(web: web,
                                      name: { Self.displayName($0) },
                                      onWatch: nil,
                                      reduceMotion: reduceMotion)
            }
        } else if !links.isEmpty {
            scopeFigure(headline: VibenetBalanceAggregation.compose(room.items)?.plainLine) {
                VibenetLinkSpine(links: links,
                                 name: { Self.displayName($0) },
                                 onPick: onScope,
                                 reduceMotion: reduceMotion)
            }
        } else {
            // **AN EMPTY SCOPE STILL DRAWS** (prd §495, user: *"even if there
            // are no accounts we need an empty state image"*).
            //
            // This was the one scope that could render NOTHING: no web and no
            // links left a 210pt reserved box empty, which reads as a drawing
            // that failed to load rather than as an answer. And it is the
            // ORDINARY case — a sub-account is Base's own "Spending Account"
            // shape and most accounts have never made one.
            accountsEmptyFigure
        }
    }

    /// NOTHING IS SHARED — the Accounts scope with no relationship to draw.
    ///
    /// **It is a real reading, not an apology.** "No other account can act for
    /// this one" is the answer somebody opens a permissions room hoping for,
    /// so it is stated in the room's own headline tier rather than as grey
    /// fine print under a blank box.
    ///
    /// The drawing is the web's own vocabulary with one end missing: the
    /// account's face, and beside it the dashed empty ring
    /// `VibenetAccountWebCard` uses for an account that exists and is not
    /// being followed. Here the ring stands for an account that does not
    /// exist — which is why the connector between them is absent rather than
    /// dashed. A line to nothing would be a relationship drawn where there is
    /// none (§83, on the screen whose whole subject is who can act for whom).
    ///
    /// **THE SENTENCE IS GONE AND THE PAIR TOOK THE BOX (prd §551, user:
    /// *"this screen looks like shit and we shouldn't need subtext"*).** It
    /// was a headline, then two small faces pinned to the top of a 210pt box,
    /// then two grey lines — three tiers of text and a drawing, arranged so
    /// that the drawing was the smallest thing in it. The subtext said in
    /// prose exactly what the headline says in four words and what the pair
    /// says in two shapes, so it was the third telling of one fact.
    ///
    /// What replaced it is not a smaller version of the same thing: the pair
    /// steps up a rung to `DS.Face.profile` — the size a face takes when it
    /// is alone on a screen rather than one of several — and takes the MIDDLE
    /// of the slot, which is `permissionsFigure`'s own ruling for a figure
    /// with one thing to say ("air distributed is a margin, air pooled at the
    /// bottom is a gap").
    ///
    /// **The headline KEEPS its reserved row** rather than moving down beside
    /// the faces, which was the other option weighed. On the icons' own line
    /// it would read as one object — but it would start 40pt lower than every
    /// other scope's headline, breaking the one guarantee the reserved row
    /// exists to give (§495: every scope's first pixel at the same y), and it
    /// would have to shrink below its own rung to fit beside two 76pt faces,
    /// one day after §551 spent a pass making every scope headline one size.
    ///
    /// **It never says the chain is empty**, only that nothing was read: the
    /// sub-account read answers for the accounts this app watches, so "no
    /// sub-accounts" is a fact about the roster and not about Base.
    @ViewBuilder
    private var accountsEmptyFigure: some View {
        let subject = scopedAddress
            ?? room.items.first?.address
        scopeFigure(headline: String(localized: "Nothing is shared")) {
            HStack(spacing: DS.Space.s4) {
                if let subject {
                    WalletFace(address: subject, size: DS.Face.profile, circular: true)
                }
                Circle()
                    .strokeBorder(DS.fillLine,
                                  style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    .frame(width: DS.Face.profile, height: DS.Face.profile)
                    .opacity(0.6)
                Spacer(minLength: 0)
            }
            // `.leading` is `Alignment(horizontal: .leading, vertical:
            // .center)`, which is the whole point: the pair is the only
            // content, so it sits where a lone figure sits everywhere else in
            // this card — centred in what the headline left, never pinned to
            // the top with the air pooled below it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel(emptyAccountsLine)
        }
    }

    /// What the empty pair MEANS, for VoiceOver alone.
    ///
    /// **It is no longer drawn** (§551) — the pair and the headline say it on
    /// screen — but a reader who cannot see two circles gets the sentence,
    /// which is the one audience the drawing genuinely cannot serve. Scoped it
    /// speaks about ONE account; unscoped about the roster, because "no other
    /// account can act for this one" is a claim the unscoped view has not
    /// checked for every account.
    private var emptyAccountsLine: String {
        if let scopedAddress {
            return String(localized:
                "No other account can act for \(Self.displayName(scopedAddress)), and it can act for none.")
        }
        return room.items.count == 1
            ? String(localized: "No other account can act for this one, and it can act for none.")
            : String(localized: "None of the accounts you watch can act for another.")
    }

    /// EVERY KEY, UNDER THE ACCOUNT IT CAN ACT FOR (prd §491).
    ///
    /// **This replaces a filter strip, and that is the point.** The tray listed
    /// keys A–Z with `All / Admin 1 / Send anywhere 5` chips above them — a
    /// second row of toggles directly under the scope switcher, which is the
    /// control the switcher exists to be the only one of. Grouping answers the
    /// same question the filter did without a control: standing in a room that
    /// is already scoped by account, "what can act on THIS account" is the
    /// grouping, not a filter over it.
    ///
    /// **NOT the per-permission sections §478 deleted.** That shape listed one
    /// heading per permission and the same key appeared under each permission
    /// it held, so "8 keys" opened fourteen rows. A key belongs to exactly one
    /// account, so grouping by account cannot do that — the one exception is a
    /// key shared across accounts, which appears under each, and that is the
    /// single-point-of-failure this room already computes (`VibenetKeyReuse`)
    /// and is worth seeing twice.
    ///
    /// Accounts in the room's own order; keys within an account in the tray's
    /// A–Z, which is §478's settled ruling ("then we aren't making some
    /// judgement call") and is left exactly as it was.
    @ViewBuilder
    private var permissionsList: some View {
        let byAccount = room.items.filter { !$0.actors.isEmpty }
        if !byAccount.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                ForEach(byAccount, id: \.address) { item in
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        // **THE HEADER AND ITS KEYS SHARE ONE LEADING COLUMN**
                        // (prd §495, user: *"the letters here have different
                        // indentations. the …0b1c and secp256k1 for example.
                        // they need to be the same"*).
                        //
                        // The header led with a `rowCircle` face (28) and
                        // `s2`, the key rows with a `Mark.list` mark (36) and
                        // `s3` — so their text started ten points apart, one
                        // line under the other. Same size, same gap now, which
                        // is also `VibenetEventRow`'s column: three lists in
                        // this room, one edge.
                        HStack(spacing: DS.Space.s2) {
                            WalletFace(address: item.address, size: DS.Face.rowCircle, circular: true)
                            Text(Self.displayName(item.address))
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Text(item.actors.count == 1
                                 ? String(localized: "1 key")
                                 : String(localized: "\(item.actors.count) keys"))
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                            Spacer(minLength: 0)
                        }
                        ForEach(VibenetKeyTray.ordered(item.actors.map {
                            VibenetTrayKey(address: item.address, actor: $0)
                        })) { key in
                            permissionRow(key)
                        }
                    }
                }
            }
            .padding(.horizontal, DSRoomChassis.contentInset)
        }
    }

    /// One key: its type and id, when it lapses, and what it can do as chips.
    ///
    /// The chips are `grantedPlainLabels` — the room's ONE list of permission
    /// wording, so a chip here and a rung in the slot above can never disagree
    /// about either the words or their order.
    @ViewBuilder
    private func permissionRow(_ key: VibenetTrayKey) -> some View {
        // **NO MARK ON A KEY ROW** (prd §495, user: *"do you think having the
        // key icon makes the entry crowded? it makes it harder to separate and
        // makes it all become a wall. i don't think we need the key icon"* —
        // and earlier, the argument that settled it: *"if we use key then it
        // would be like why aren't we using it in places we use a + sign"*).
        //
        // The rule the app follows is that a row's mark is its own SUBJECT — a
        // holding's token, an account's face, an event's change. A key's
        // subject is a key, and no glyph reads as one, so any mark here is
        // invented rather than read. Drawn beside the account face above it,
        // two mark columns turn a short list into a wall.
        //
        // The row indents to the header's TEXT column instead, which is what
        // it did before the mark and is why the two were aligned.
        let body = VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(key.actor.kind.shortLabel)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(VibenetKeyIdentity.short(key.actor.actorId))
                    .dsText(.label11).monospaced()
                    .foregroundStyle(DS.textTertiary)
                Spacer(minLength: DS.Space.s2)
                if let clock = key.actor.expiryClock(now: .now) {
                    Text(clock)
                        .dsText(.label12)
                        .foregroundStyle(key.actor.expiryStanding(now: .now) == .soon
                                         ? DS.tint : DS.textTertiary)
                        .fixedSize()
                }
            }
            // **CHIPS, and ADMIN IS ONE OF THEM (user ruling, prd §493:
            // *"for Admin it doesn't need a sentence. Admin is the chip"*).**
            //
            // `grantedPlainLabels` already returns exactly `["Admin"]` for an
            // unrestricted key — `isAdmin` is `raw == 0`, so there are no bits
            // to list — which means the chip row needs no admin branch and no
            // gloss beside it. It says what the key can do in the room's own
            // one list of permission wording, so a chip here and a rung in the
            // slot above can never disagree about either the words or their
            // order.
            //
            // `FlowLayout` and the chip recipe are the TRAY's, reused rather
            // than re-drawn: two chip styles for one fact is how a room comes
            // to disagree with the sheet it opens.
            FlowLayout(spacing: 6) {
                ForEach(key.actor.scope.grantedPlainLabels, id: \.self) { label in
                    let admin = key.actor.scope.isAdmin
                    Text(label)
                        .dsText(.label11)
                        .fontWeight(admin ? .semibold : .regular)
                        .foregroundStyle(admin ? DS.attention : DS.tint)
                        .padding(.horizontal, DS.Space.s2)
                        .padding(.vertical, 3)
                        .background((admin ? DS.attention : DS.tint).opacity(0.14),
                                    in: Capsule(style: .continuous))
                }
            }
        }
        let padded = body
            .padding(.leading, DS.Face.rowCircle + DS.Space.s2)
            .padding(.vertical, DS.Space.s1)
        if let onOpenKey {
            Button {
                DSHaptic.selection()
                onOpenKey(key.actor,
                          room.items.first { $0.address == key.address } ?? room.items[0],
                          [])
            } label: { padded.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            padded
        }
    }

    /// WHAT CAN ACT, COUNTED BY WHAT IT CAN DO (prd §491).
    ///
    /// Wallet's Permissions anatomy in this room's words, and built on the
    /// census this room ALREADY computes: `VibenetPolicyAggregation.compose`
    /// has produced exactly these rows — admin counted apart, then the five
    /// named bits in `Scopes.sol`'s own declared order — since §463. It fed a
    /// filter strip; now it is the drawing.
    ///
    /// **Counted by CAPABILITY, so the shape never grows.** Eight keys and
    /// forty draw the same cells, which is the property that let this replace a
    /// filter strip rather than sit beside one: the strip existed because a
    /// long list needed narrowing, and a figure that says what there is to
    /// narrow TO answers the same need without a second row of chips under the
    /// scope switcher.
    ///
    /// **§551 made that true of the SMALL end as well.** "The shape never
    /// grows" held for eight keys and forty and not for one: what was drawn
    /// was `compose`'s own list, which is as long as the account is
    /// interesting, so a single kind of key drew a single rung in a box built
    /// for four. The census is drawn whole now — see
    /// `VibenetPolicyAggregation.census` for why the figure needs a different
    /// list from the rows below it.
    ///
    /// **Admin is called "Admin"** (user ruling, prd §491) — the word the app
    /// already used on the key rows, not a paraphrase. `isAdmin` is `raw == 0`:
    /// a key with no scope bits set is unrestricted, which is why it is counted
    /// apart from the five rather than as another bit among them.
    @ViewBuilder
    private var permissionsFigure: some View {
        let counts = policyRows
        let keys = VibenetKeyAggregation.compose(room.items, now: .now)
        if (keys?.unreachedCount ?? 0) > 0 && counts.isEmpty {
            // **THE ONE REAL EXCEPTION, and it is a safety one** (prd §551).
            // A census of dashes over accounts the chain never answered for
            // would say "nothing can act for you" — the most reassuring
            // possible way to be wrong, on the one screen somebody reads to
            // find out who can spend their money (§83). An unread account
            // keeps a glyph and a sentence.
            permissionsEmptyFigure
        } else {
            // **THE WHOLE CENSUS, ALWAYS — granted and not** (prd §551, user:
            // *"i like how it looks with four rungs, but not how it looks with
            // 1 rung"*).
            //
            // The figure used to draw only what was held, ranked by count and
            // capped at four, with the type GROWING and the rows SPREADING
            // when there were few — three separate compensations for one
            // problem, which is that a variable-length list cannot fill a
            // fixed box. An account with a single kind of key still ended up
            // as one number adrift beside a headline saying the same count.
            //
            // Six cells, one order, every time. Nothing ranks, nothing is
            // capped, nothing resizes — so the drawing looks the same on an
            // account with one key and an account with forty, and the "and N
            // more" tail disappears because nothing is ever cut (§307 is
            // satisfied by construction rather than by a footnote).
            //
            // And it says more than the counts did: an UNGRANTED permission is
            // a real reading on this screen — "no key here can send anywhere"
            // is the answer somebody opens this scope hoping for, and only a
            // census that includes absences can give it.
            let census = VibenetPolicyAggregation.census(counts)
            scopeFigure(headline: keys.map {
                $0.total == 1 ? String(localized: "1 key") : String(localized: "\($0.total) keys")
            } ?? String(localized: "No keys")) {
                LazyVGrid(columns: Self.censusColumns,
                          alignment: .leading,
                          spacing: DS.Space.s2) {
                    ForEach(Array(census.enumerated()), id: \.element.label) { index, row in
                        policyCensusCell(row)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// ONE PERMISSION, HELD OR NOT.
    ///
    /// **An absence is an OUTLINE and a dash, never a filled "0".** A zero
    /// drawn in the same well as a count reads as a measurement — the same
    /// object, a smaller number — when what it means is that this permission
    /// is not in play at all. The dash is the app's own grammar for a fact
    /// that has no value (`holdingsEmptyFigure`'s dashed treemap, the empty
    /// ring on the Accounts scope), and the hollow well is the well saying
    /// the same thing.
    ///
    /// **Admin, and only Admin, wears the alarm colour** — it is the one rung
    /// that is unbounded (`scope == 0` is unrestricted, prd §463), and
    /// colouring the others would be this app grading permissions somebody set
    /// on purpose. It is tinted only when it is actually held: an attention
    /// hue over a dash is an alarm about something that is not there.
    @ViewBuilder
    private func policyCensusCell(_ row: VibenetPolicyCount) -> some View {
        let held = row.count > 0
        let isAdmin = row.label == Self.adminLabel
        VStack(alignment: .leading, spacing: 4) {
            Text(held ? "\(row.count)" : "—")
                // **`price16`, ONE RUNG UNDER THE HEADLINE** (2026-09-02) —
                // the ramp's own "a row's figure", which is what a cell in a
                // well is. It was `stat24`, the same rung as the "3 keys"
                // directly above it, so the figure read as seven numbers of
                // equal standing when six of them are that seventh one's
                // breakdown. It is also what makes the cell FIT: at `stat24` a
                // two-line cell wants 83pt of the 78 `censusCell` derives.
                //
                // **The knowing divergence from `HegotaRoomCard.stat`**, which
                // this cell otherwise copies: that grid is ONE row of three in
                // the same slot, so it can spend 88pt on a cell and the whole
                // rung with it. Two rows cannot, and the rung is what gives.
                .dsText(.price16)
                .foregroundStyle(held ? (isAdmin ? DS.attention : DS.textPrimary)
                                      : DS.textTertiary)
                .monospacedDigit()
            Text(row.label)
                // **TWO lines, not three** (2026-09-02). Three was
                // `HegotaRoomCard.stat`'s measurement, and it was measured
                // against THAT box: three across a 342pt slot leave ~60pt of
                // text, where "On the ordinary nonce" really does want three.
                // This grid is wider — three across the room's own 376pt, less
                // this cell's `s2` insets, is ~99pt — and the longest label
                // here ("Send to one contract") sets in two. The third line was
                // never drawn and was still PAID FOR: every cell in the grid
                // takes the tallest cell's height, so one label's unused third
                // line made all six 14pt taller, which is most of what pushed
                // the second row past the slot's clip.
                .dsText(.label12)
                .foregroundStyle(held ? DS.textTertiary : DS.textQuaternary.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 0)
        }
        // **PINNED, NOT FLOORED** (2026-09-02) — see `censusCell`. A floor is
        // what a label's own wrapping walks straight through, and the grid it
        // grows is clipped rather than scrolled.
        //
        // TWO modifiers, and that is forced rather than stylistic: SwiftUI has
        // `frame(width:height:alignment:)` and the `min/ideal/max` family, and
        // NO overload mixing `maxWidth:` with `height:` — so the obvious
        // single-call reading of "full width, pinned height" does not compile
        // at all. Pinning the height first and widening after says the same
        // thing. Deliberately NOT `minHeight:`, which is the floor this
        // room's own guard bans and which a label's wrapping walks through.
        .frame(height: Self.censusCell, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s2)
        // A well, so six facts read as six facts rather than as a sentence
        // that lost its words — `HegotaRoomCard.stat`'s grammar, which is what
        // the Nonces figure one devnet over already uses for exactly this job.
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(held ? DS.surfaceWell : Color.clear)
        }
        .overlay {
            if !held {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.fillLine, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(held
                            ? (row.count == 1
                               ? String(localized: "1 key · \(row.label)")
                               : String(localized: "\(row.count) keys · \(row.label)"))
                            : String(localized: "No keys · \(row.label)"))
    }

    /// Three across, two down — the six permissions in one screenful.
    ///
    /// THREE and not two: at two columns the six cells need three rows, and
    /// three rows do not fit `DSRoomChassis.figureSlot` at any cell height a
    /// number and a label can be read at.
    private static let censusRows: CGFloat = 2
    private static let censusColumns = Array(
        repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .topLeading),
        count: 3)

    /// **A CENSUS CELL'S HEIGHT, DERIVED FROM THE BOX IT MUST FIT** (2026-09-02
    /// — reported as clipping on the Permissions scope, the second row of cells
    /// cut in half along the top edge of the fused slab).
    ///
    /// It was a FLOOR of 72 with a note doing the arithmetic by hand, and every
    /// term of that arithmetic was wrong by the time it was read. The floor
    /// never bound — a cell is a number over a label, and the label's own
    /// wrapping decides the height, so the six cells came out at ~92 each; the
    /// note allowed "~158pt under a `price40` headline" when §551 had taken the
    /// headline to `stat24` and its row to 30 + `s3`; and it compared against a
    /// number that could not be reached from here anyway, since `headlineRow`
    /// was a static on a generic type. Two rows of 92 plus their gap is ~193pt
    /// of the 166 there are, and `DSRoomSlot` clips — so the bottom row lost a
    /// quarter of itself with nothing anywhere saying so.
    ///
    /// Derived, the arithmetic cannot go stale: the slot changes, the cell
    /// changes with it. **The cell is PINNED to this rather than floored by
    /// it** (see `policyCensusCell`), so a longer label can never grow the grid
    /// past the box again — it is the cell's own text that gives, which is
    /// visible, rather than the row below it, which is not.
    private static let censusCell: CGFloat =
        (DSRoomChassis.figureSlot - DS.Space.s2 * (censusRows - 1)) / censusRows

    /// NOTHING WAS READ — the Permissions scope for an account the chain did
    /// not answer for.
    ///
    /// **The only state that does not take the census** (prd §551). "No keys"
    /// is drawn as six hollow cells, because that IS the reading and it is a
    /// true one. "Not read yet" cannot be: six dashes would say nothing can
    /// act for you, which is a SAFETY claim, and making it over a read that
    /// never reached the chain is the most reassuring possible way to be
    /// wrong (§83, on the screen where it costs most).
    ///
    /// So this branch keeps a glyph and a sentence, and both name the READ
    /// rather than the account. The glyph is the app's own `key.slash` symbol
    /// through `dsGlyph`, so it scales with Dynamic Type like every other mark
    /// here.
    @ViewBuilder
    private var permissionsEmptyFigure: some View {
        scopeFigure(headline: String(localized: "Not read yet")) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .accessibilityHidden(true)
                    .dsGlyph(30, weight: .regular)
                    .foregroundStyle(DS.attention)
                Text(String(localized: "The chain did not answer, so this room cannot say what can act for you."))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// The census, composed ONCE for both readers (prd §468's guard, honoured
    /// rather than loosened).
    ///
    /// §491 gave the Permissions scope a figure built on the same rows
    /// `keysBody` draws, which made two call sites of one pure function. That
    /// is not the drift the guard exists to stop — the drift would be two
    /// DERIVATIONS — but a second call is one edit away from becoming one, and
    /// the card and its slot figure disagreeing about what can act on your
    /// accounts is exactly the failure §468 named. One `let`, two readers.
    private var policyRows: [VibenetPolicyCount] {
        VibenetPolicyAggregation.compose(room.items)
    }

    /// The census's own word for an unrestricted key, so the colour test above
    /// can never drift from the label it is testing.
    private static let adminLabel = String(localized: "Admin")

    /// WHEN KEYS LAPSE — the shelf, lifted out of `expiryFooter`.
    ///
    /// Its eyebrow ("Keys expiring") is dropped for the reason every other
    /// figure here drops one: the chip below says Keys, and the rows say
    /// expiring. `tailLine` is KEPT — it is not a label, it is the count of
    /// what the shelf could not draw, which §307's silent-truncation rule
    /// says must survive wherever the drawing goes.
    @ViewBuilder
    private var keysFigure: some View {
        if let shelf = VibenetKeyShelf.compose(room.items, now: .now) {
            let keys = VibenetKeyAggregation.compose(room.items, now: .now)
            scopeFigure(headline: keys.map {
                $0.total == 1 ? String(localized: "1 key")
                              : String(localized: "\($0.total) keys")
            }) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(shelf.rows.enumerated()), id: \.element.id) { index, row in
                        shelfRow(row)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                            // A KEY LANDS ON THE RUNWAY (prd §501). §479 gave
                            // a new key a chip and a wash on the card and the
                            // tray; the runway that says WHEN it dies had
                            // neither, so the one drawing that places a key in
                            // time could not say which key was the new one.
                            //
                            // It reads `keyChanges.added` — the same set the
                            // chip spends — so the runway, the chip and the
                            // count cannot disagree about what is new.
                            .arrivalWash(keyChanges?.added.contains(row.id) == true,
                                         hue: Self.mark)
                    }
                    if let tail = shelf.tailLine {
                        Text(tail)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }
        }
    }

    /// Fixed, not fitted — see `stackedRoom`. Spelled rather than measured,
    /// because measuring it would settle the bar a frame LATE, which is the
    /// same jump arriving slower (Wallet's `walletVisualSlot`, same reason).
    private static var visualSlot: CGFloat { DSRoomChassis.visualSlot }

    // **The local `headlineRow` copy is GONE** (2026-09-02). It was a second
    // spelling of `DSRoomChassis.headlineRow` that nothing here read — kept, by
    // the look of it, because the real one was unreachable as a static on a
    // generic type — while the census sized itself against a hand-written
    // guess at the same number and lost a row to the clip. The number is on the
    // chassis, with `figureSlot` derived from it; anything in this card that
    // needs it reads it there.

    /// The samples the crown, the delta and the line all read (prd §479) —
    /// ONE derivation, so the figure, its move and its curve can never
    /// describe different windows.
    private var windowed: [VibenetValueSample] {
        VibenetValueHistory.windowed(history, range: range, now: .now)
    }

    /// HOW FAR BACK (prd §479) — drawn only where the book can actually

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
                // A deck of `railSlab`, not a strip of its own (prd §547).
                embedded: true,
                matches: VibenetScopeRail.matches,
                onPick: { picked in onScope(picked ?? "") },
                onReTap: nil,
                // ONE slot, not two (§465): watching another account and seeing
                // the whole list are the same screen here, so a "+" beside the
                // book would point at the same place twice.
                addTitle: nil,
                onAdd: nil,
                bookTitle: onOpenBook == nil ? nil : String(localized: "Address book"),
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
        .accessibilityLabel(Text(String(localized: "Address book")))
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
        accountsCardBody
            // The roster's two presentations, on the card that owns the rows
            // (prd §545). ONE alert and ONE dialog for the whole list rather
            // than per row: a presentation declared inside a `ForEach` resolves
            // to the same presenting controller for every row, which is the
            // half-open-then-close bug this file's own `onOpenKeySheet` comment
            // records paying for three times.
            .alert(String(localized: "Name this account"),
                   isPresented: Binding(get: { renamingAddress != nil },
                                        set: { if !$0 { renamingAddress = nil } })) {
                TextField(String(localized: "Name"), text: $renameText)
                Button(String(localized: "Save")) {
                    if let address = renamingAddress {
                        VibenetWatch.shared.setName(renameText, for: address)
                    }
                    renamingAddress = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { renamingAddress = nil }
            }
            .confirmationDialog(String(localized: "Stop watching this account?"),
                                isPresented: Binding(get: { removingLast != nil },
                                                     set: { if !$0 { removingLast = nil } }),
                                titleVisibility: .visible) {
                Button(String(localized: "Stop watching"), role: .destructive) {
                    if let address = removingLast { commitUnwatch(address) }
                    removingLast = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { removingLast = nil }
            } message: {
                Text(String(localized: "It's the last one here, so the vibenet room and its chip go with it. Watching it again brings them back."))
            }
    }

    private var accountsCardBody: some View {
        let links = VibenetAccountMapping.links(room.items)
        return card {
            VStack(alignment: .leading, spacing: 0) {
                // MAKING ONE LEADS THE LIST (user ruling, 2026-08-29: create
                // goes "above the existing accounts, not below the list b/c
                // user may have many"). A verb under a roster of twenty is a
                // verb nobody finds.
                //
                // In the ROOM rather than the address book, also on the user's
                // ruling: that book's names ledger is SHARED with the real one,
                // so a devnet account created there would land beside mainnet
                // wallets — a confusion built in on purpose for renaming and
                // exactly wrong for making.
                // **CREATE MOVED TO HOME (2026-09-04, user ruling).** All four
                // chain acts live on the Home panel now — *"folks testing won't
                // want to just send, the others are just as important"* — and
                // the corollary the same ruling carried is that they MOVE
                // rather than being duplicated: a door here as well would make
                // three places instead of one, which is the scattering the
                // ruling was about.
                //
                // **WATCH STAYS, and the line between them is what to keep.**
                // Create WRITES to the chain; watching changes what this roster
                // SHOWS. The rail is for viewing, so an act that changes the
                // view belongs with the view — and unlike Create it has no
                // subject on Home, since watching an address is the one act
                // here that is not about an account you can sign for.
                watchAccountRow
                ForEach(Array(drawn.enumerated()), id: \.element.id) { index, item in
                    // The last ROW is only the last thing in the card when
                    // there are no links folded under it — otherwise its
                    // separator is what joins the roster to the disclosure.
                    accountRow(item)
                }
                // Not when the spine is the scope's own lead — see `promoted`.
                if !links.isEmpty, !promoted(.accounts) { linkedDisclosure(links) }
                // **THE ONE FACT A REDEPLOYING CHAIN OWES A ROSTER (prd
                // §507).** `AccountCreated` carries a `codeHash`, which was
                // read by nothing: two accounts sharing it run the same
                // account implementation and two that do not are two
                // different builds of it — invisible to every other read
                // here, and on vibenet the thing most likely to be true
                // without anybody noticing.
                //
                // Drawn ONLY when they really differ. On a healthy roster
                // they never do, and a line reading "1 implementation" is a
                // line saying nothing — the always-lit marker this room
                // deleted once already (§493).
                if let drift = room.implementationDrift {
                    Text(drift)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.Space.s2)
                        .padding(.horizontal, DSRoomChassis.contentInset)
                }
            }
        }
    }


    /// The other way an account gets into this list: one you did not make.
    ///
    /// **IT SITS BESIDE CREATE, ABOVE THE ROSTER, FOR §538'S OWN REASON** —
    /// *"create account should be indented same as the list items below it"*,
    /// and the ruling one line up from that: a verb under a roster of twenty
    /// is a verb nobody finds. So it reads off `createAccountRow`'s tokens
    /// rather than spelling its own, and the two are one pair: change that
    /// row's geometry and this one has to follow.
    ///
    /// **The tap is a SHEET and never an unfold (prd §517).** The lookup this
    /// opens is `VibenetDiscoverySection` — up to eight strangers' addresses —
    /// and inline it would land BETWEEN this row and the accounts below it,
    /// pushing the one account you actually watch down the page. That is the
    /// reported "this whole thing is gross", and §472 → §476 → §517 is three
    /// rulings spent arriving at the surface that makes it structurally
    /// impossible. Unfolding it here would be the fourth.
    ///
    /// Second, not first: creating is the room's own act and watching is
    /// somebody else's account, so the primary verb keeps the lead.
    @ViewBuilder
    private var watchAccountRow: some View {
        Button {
            DSHaptic.selection()
            onRequestWatch()
        } label: {
            HStack(spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(Self.mark.opacity(0.18))
                        .frame(width: DS.Face.rowCircle, height: DS.Face.rowCircle)
                    Image(systemName: "magnifyingglass")
                        .dsGlyph(12, weight: .semibold)
                        .foregroundStyle(Self.mark)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Watch an account"))
                        .dsText(.heading17)
                        .foregroundStyle(Self.mark)
                        .lineLimit(1)
                    // Says what the tap ASKS FOR, `createAccountRow`'s rule:
                    // one of these two rows wants an address you already have
                    // and the other does not, and that is the whole of how
                    // somebody picks between them.
                    Text(String(localized: "Paste an address, or pick a new one"))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(Self.mark.opacity(0.6))
            }
            .padding(.vertical, DS.Space.s3)
            .padding(.horizontal, DSRoomChassis.contentInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
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

    /// ONE ROW GRAMMAR FOR AN OBJECT (prd §495).
    ///
    /// Reported as *"the list items are not consistent design"*, and measured
    /// across the room's seven row builders before anything was changed: the same
    /// KIND of row — a thing with a face, a name and one clause under it — was
    /// drawn at `body17`, `heading17`, `callout15` and `label11` depending on
    /// which file it lived in, with faces at both `rowCircle` and `list`.
    ///
    /// The settled shape, and the axis is what a row IS rather than where it sits:
    /// an OBJECT row (an account, a linked account, a sub-account, a key) leads
    /// with a face or mark at `DS.Face.rowCircle`, names itself at `heading17`,
    /// and carries one clause at `label11`. A CENSUS rung (a permission count) is
    /// not an object and keeps its own shape — it is a number and a label, and
    /// giving it a row's type would make eight keys look like eight things.
    /// **THE ROW CARRIES THE VERBS NOW (prd §545, 2026-08-31).**
    ///
    /// `VibenetAddressBookScreen` is deleted and this is where its two account
    /// verbs went. The screen existed because §465 moved the roster off the
    /// SETUP page — which was right — but it moved it to a pushed screen while
    /// this room already had an Accounts scope drawing the same roster. Two
    /// surfaces listing one set of accounts is §533's "Latest 3" duplication
    /// with a door instead of a truncation, and the app has a general
    /// `AddressBookScreen` besides, so the devnet copy was the third list of
    /// one fact.
    ///
    /// §465's ruling is KEPT, not reversed: what you do repeatedly lives in the
    /// room, not on setup. It just lives in the scope named after it rather
    /// than one tap further out.
    ///
    /// A CONTEXT MENU, exactly as the deleted screen had it — not swipe
    /// actions: these rows are not in a `List`, and the row's own tap is
    /// already the scope pick, so a long-press is the only gesture left that
    /// does not fight it.
    private func accountRow(_ item: VibenetAccountItem) -> some View {
        Group {
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
        .contextMenu {
            Button {
                renameText = VibenetWatch.shared.name(for: item.address) ?? ""
                renamingAddress = item.address
            } label: {
                Label(String(localized: "Name this account"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                unwatch(item.address)
            } label: {
                Label(String(localized: "Stop watching"), systemImage: "minus.circle")
            }
        }
    }

    /// **AND THAT IS WHY THE LAST ONE ASKS (prd §472, carried over whole).**
    /// Every other unwatch removes a row; this one tears down the seat and
    /// drops the chip out of the strip, so it is a different act wearing the
    /// same word and it confirms.
    private func unwatch(_ address: String) {
        if VibenetWatch.shared.addresses.count <= 1 {
            removingLast = address
        } else {
            commitUnwatch(address)
        }
    }

    /// The one place the removal actually happens, so the ordinary path and the
    /// confirmed last-one path can never drift into two different removals.
    private func commitUnwatch(_ address: String) {
        DSHaptic.tap()
        VibenetWatch.shared.remove(address)
    }

    private func accountRowBody(_ item: VibenetAccountItem, door: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: item.address, size: DS.Face.rowCircle, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.displayName(item.address))
                        .dsText(.heading17)
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
                if VibenetConfig.cached()?.faucetAddress != nil,
                   let url = URL(string: VibenetExplorer.faucet) {
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
    /// already states it, so a lone rectangle here would be the same figure
    /// twice, once in a form that cannot be broken down.
    ///
    /// **THIS CARD OWNS THAT RULE NOW (2026-08-27).** It used to come free
    /// from `VibenetBalanceTreemap.cells` returning nothing for one cell —
    /// but that is a fact about THIS card's layout, and the model applied it
    /// to every caller, which blanked the promoted Holdings scope for any
    /// single-asset account (see that function's own note). The rule is
    /// unchanged; it is simply asked by the view that has a crown above it.
    @ViewBuilder
    private var holdingsCard: some View {
        if let aggregate = VibenetBalanceAggregation.compose(room.items) {
            let cells = VibenetBalanceTreemap.cells(aggregate)
            if cells.count > 1, !promoted(.holdings) {
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
                // A WORD, NOT A PILL (prd §584, 2026-09-03). This was a
                // SOLID capsule in the room's mark with `DS.page` knocked out
                // of it — the only treatment in the app that looks exactly
                // like a filled button while being news you cannot tap. §583
                // took the fill off `DSStamp` for that reason; this is the
                // same object, hand-rolled in three files, so the sweep of
                // that component never reached it.
                //
                // The mark colour is UNTOUCHED and is what carries it. §295's
                // same-weight ruling still holds: a key added and a key
                // revoked are both merely news and neither is graded.
                Text(moved)
                    .dsText(.label11).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
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
        let policies = policyRows
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
        // Not when the shelf is the scope's own lead — see `promoted`. The
        // SENTENCE half survives either way: `expiryFooter` draws it exactly
        // where the shelf declines, and that fallback is what the card had
        // before any figure existed.
        if !promoted(.permissions) { expiryFooter(aggregate) }
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
                            // A KEY LANDS ON THE RUNWAY (prd §501). §479 gave
                            // a new key a chip and a wash on the card and the
                            // tray; the runway that says WHEN it dies had
                            // neither, so the one drawing that places a key in
                            // time could not say which key was the new one.
                            //
                            // It reads `keyChanges.added` — the same set the
                            // chip spends — so the runway, the chip and the
                            // count cannot disagree about what is new.
                            .arrivalWash(keyChanges?.added.contains(row.id) == true,
                                         hue: Self.mark)
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
                                // THE LAST TEN SECONDS (prd §501). §479 landed
                                // the crossing and left the approach flat — a
                                // countdown ten seconds out looked exactly
                                // like one ten minutes out, on the one moment
                                // in this room somebody might sit and watch.
                                //
                                // **Tabular digits, and only at the end.** A
                                // proportional "9" is narrower than a "0", so
                                // a per-second label REFLOWS under the eye
                                // exactly when the eye is on it. Applied for
                                // the whole run instead, this would change how
                                // every unlock row has always been set; inside
                                // ten seconds it is the fix for a defect that
                                // only exists there.
                                let closing = item.unlockClosing(now: tick.date)
                                Text(countdown)
                                    .dsText(.label12)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                    .dsTabularDigits(closing)
                                    // Tabular, because it rolls — see `LiveTimeText` (prd §586).
                                    .monospacedDigit()
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
                                            // THE LEADING EDGE BRIGHTENS ON
                                            // THE SECOND, inside ten (prd
                                            // §501). It rides the SAME mark
                                            // rather than a second colour —
                                            // this room spends blue on urgency
                                            // and only on urgency, and an
                                            // unlock about to land is exactly
                                            // that. Off under Reduce Motion,
                                            // where the bar's own fill already
                                            // says how far along it is.
                                            if closing, !reduceMotion {
                                                Capsule().fill(.white)
                                                    .frame(width: 4)
                                                    .offset(x: max(0, geo.size.width * progress - 4))
                                                    .opacity(Int(tick.date.timeIntervalSince1970) % 2 == 0 ? 0.9 : 0.35)
                                                    .animation(.easeInOut(duration: 0.5), value: countdown)
                                            }
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

/// One landed vibenet event, led by WHAT HAPPENED (2026-08-26).
///
/// **The history.** R4.2 (2026-08-23) made this row face-led after a report
/// — *"i can't see which accounts they are from"* — because the room had
/// fallen to `.plain`, so every row wore one identical brand glyph and the
/// only identifying mark was a truncated `…f21f` at the END of an 80-char
/// title. That fix was right about the problem and overcorrected on the
/// remedy: it promoted the ACCOUNT to the title, so a stream of one
/// account's events repeated the same word ten times down the screen and
/// the news — what actually happened — sat demoted in the subtitle.
///
/// **The shape now.** The event leads, the account names itself in the line
/// beneath, and the leading slot carries the event's KIND as a tinted mark.
/// R4.2's complaint stays fixed: the account is still in its own slot in
/// its own weight, and by its NICKNAME where it has one, which is a
/// stronger identity than either a face or a hex tail.
///
/// The mark is this app's own row grammar rather than a new vocabulary —
/// every Wallet row leads with a tinted glyph in exactly this position.
///
/// **The kind comes off the §308 FACETS**, never a parsed title: the
/// landing stamps `Key` / `Revoked` / `Locked` / `Unlocking` on `tags`
/// (`VibenetEventKind.facetTags`), so this reads data rather than prose,
/// and a localized title can never change what the row draws. `Revoked` is
/// tested BEFORE `Key` because a revoke carries both by design.
///
/// Reads `authorHandle` (the account) and `summary` (the event without the
/// address) — both stamped at landing. A row that predates those falls back
/// to its whole title, which still says everything, just less prettily.
struct VibenetEventRow: View {
    let thing: Thing

    /// **EVERY KIND THIS ROOM LANDS, each with the mark it draws (prd §538,
    /// 2026-08-31; user: "on vibenet activity all of these should have
    /// icons").**
    ///
    /// This table knew FOUR of the eight `VibenetEventKind` cases, so half the
    /// room drew no mark at all — an account creation, a transfer either way
    /// and a policy run are the ones a person actually sees most, and a feed
    /// where some rows have a leading slot and some do not reads as a list
    /// that failed to load rather than as a considered absence.
    ///
    /// **AND `Policy` WAS DRAWING THE WRONG MARK, which is worse than none.**
    /// `.policyRun.facetTags` is `["Key", "Policy"]` — it carries `Key` for
    /// the same reason a revoke does — so it fell through this chain's `Key`
    /// arm and wore the NEW-KEY plus. A key running under its gate and a new
    /// key being authorized are not the same event, and on a security row the
    /// second one is the alarming one: the room was reporting an authorization
    /// that never happened. `Policy` is therefore tested BEFORE `Key`, exactly
    /// as `Revoked` already is and for exactly the same reason.
    ///
    /// The nil case SURVIVES and its reasoning is unchanged: a row landed by a
    /// build before §308 stamped these facets says nothing about its kind, and
    /// a guessed glyph on a security row is the §83 fake status in the one
    /// room where believing it is expensive. What changed is that seven kinds
    /// are no longer being treated as if they were that row.
    private enum Kind {
        case authorized, revoked, locked, unlocking
        case created, receivedIn, sentOut, policy

        var glyph: String {
            switch self {
            case .authorized: return "plus"
            case .revoked:    return "minus"
            case .locked:     return "lock.fill"
            case .unlocking:  return "lock.open.fill"
            // The account itself coming into existence — the same `faceid`
            // mark its create sheet leads with, because it is the same act
            // seen afterwards.
            case .created:    return "faceid"
            case .receivedIn: return "arrow.down"
            case .sentOut:    return "arrow.up"
            // A gate that ran, not a key that was granted — the slider glyph
            // the permissions block uses for a scoped key, never a plus.
            case .policy:     return "slider.horizontal.3"
            }
        }

        var hue: Color {
            switch self {
            // A new key is not GOOD news, it is news — so the room's own
            // tint, never `confirm`. Green here would read as "this was
            // fine", which is precisely the judgement this row must not
            // make on somebody's behalf.
            case .authorized: return DS.tint
            case .revoked:    return DS.destructive
            case .locked, .unlocking: return DS.attention
            // Money ARRIVING is the one event in this room that green is
            // honest about: it is the direction, not a verdict — the same
            // reading every ledger row in the app gives a received amount.
            case .receivedIn: return DS.confirm
            // Sent and created are news of the room's own kind, so they take
            // its tint. Deliberately NOT `destructive` for a send: leaving is
            // not a fault, and red on an ordinary outgoing transfer is the
            // judgement `authorized` above refuses to make.
            case .sentOut, .created, .policy: return DS.tint
            }
        }
    }

    /// **ORDER IS THE RULE HERE, not a formality.** Several kinds stamp more
    /// than one facet by design (`["Key", "Revoked"]`, `["Key", "Policy"]`,
    /// `["Transfer", "Sent"]`), so the narrower word must be asked first or
    /// the broader one answers for it — which is precisely how a policy run
    /// came to wear a new key's mark.
    private var kind: Kind? {
        let tags = thing.tags
        if tags.contains("Revoked")   { return .revoked }
        if tags.contains("Locked")    { return .locked }
        if tags.contains("Unlocking") { return .unlocking }
        if tags.contains("Policy")    { return .policy }
        if tags.contains("Received")  { return .receivedIn }
        if tags.contains("Sent")      { return .sentOut }
        if tags.contains("Created")   { return .created }
        if tags.contains("Key")       { return .authorized }
        return nil
    }

    /// **THE MARK, AND A ROW WITH NO KIND STILL HAS ONE (prd §588).**
    ///
    /// The tile drew only when `kind` resolved, so a pre-§308 row had no mark
    /// AND no placeholder — the column collapsed and that one row started
    /// 48pt left of every other. `WalletRow.Mark.kind` is the honest fallback
    /// rather than an invented glyph: it draws the `Thing`'s own `KindGlyph`,
    /// the mark that thing already wears in every other feed in the app.
    private var mark: WalletRow.Mark {
        guard let kind else { return .kind(thing.kind) }
        return .symbol(kind.glyph, tint: kind.hue)
    }

    var body: some View {
        if thing.isLive {
            // **ONE ANATOMY WITH THE OTHER THREE ROOMS (prd §588).** This was
            // a hand-rolled `HStack`, and it differed from `WalletRow` in
            // three ways, NONE of them a type size — which is why these four
            // lists read as four different fonts while a grep of the ramp
            // found nothing wrong. The mark was a rounded SQUARE where every
            // other room's is a circle; the second line was `label12` (12
            // MEDIUM, secondary) against the shared row's `subhead13` (12
            // regular, tertiary); and the title was `lineLimit(2)` against a
            // clamped one, so this room's rows stood at two heights.
            //
            // **THE CLOCK'S GRAMMAR IS KEPT WHOLE** (prd §495, user: *"would
            // it be better if the alert went the whole way across and the
            // timestamp was on line two?"* — neither, as it turned out: the
            // layout was fine and the FORMAT was the outlier). This row said
            // "23 hours ago", ~110pt of a 402pt screen, where every `BandRow`
            // says "23h" through `LiveTimeText`. Same component, still
            // ticking on the minute.
            //
            // Its `.dsText(.label11)` is GONE rather than moved: it was dead
            // code, since `LiveTimeText` carries its own `subhead13` and the
            // innermost font wins. Both resolve to 12pt, so the drift was
            // invisible — and now it is one rung, said once.
            WalletRow(mark: mark,
                      title: thing.summary ?? thing.title,
                      subtitle: accountLabel) {
                LiveTimeText(date: thing.capturedAt, color: DS.textTertiary)
                    .lineLimit(1).fixedSize()
            }
        }
    }

    /// The account's nickname when it has one, else its short address —
    /// the same identity the room card and the sheet show, so one account
    /// never reads as two different things across three surfaces.
    private var accountLabel: String {
        guard let address = thing.authorHandle else { return thing.title }
        return VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}


#if DEBUG
/// WHERE THE ROOM'S PIECES ACTUALLY ARE, measured by the layout system
/// itself (prd §495).
///
/// **Built after four rounds of measuring screenshots and getting it wrong.**
/// A pixel scan cannot tell the scope strip from any other wide faint bar,
/// and a settled screenshot cannot see a transient at all — so every "it does
/// not move" I reported was a claim about my probe, not about the room. This
/// asks SwiftUI where the frames are and NSLogs them, which is the only
/// answer that is checkable.
///
/// `vibenetLayout|<scope>|slotTop|figureTop|stripTop` on every layout pass
/// that changes any of them. Switch scopes and diff the lines: if `stripTop`
/// differs the bar moves; if only `figureTop` differs the DRAWING moves
/// inside a fixed box, which reshapes everything above the bar and is what
/// three reports of "the toggle bar jumps" actually were.
struct VibenetLayoutKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's global top edge under `name`.
    func vibenetLayoutMark(_ name: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: VibenetLayoutKey.self,
                                       value: [name: geo.frame(in: .global).minY])
            }
        }
    }
}
#endif
