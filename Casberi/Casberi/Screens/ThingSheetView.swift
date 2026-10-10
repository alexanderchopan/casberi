import SwiftUI
import SwiftData
import Translation

/// The thing sheet (M4, redesigned 2026-07-07 — "Ink with Gallery grafted
/// in", user's pick): ink-black ground, no cards. The source's hue washed
/// down from the top from 2026-07-10 (wash + icon, the dot died) until
/// 2026-07-18, when it was pulled for reading as borrowed identity over
/// content (see the ruling further down, where `.dsInk()` is applied) — the
/// one exception since 2026-08-12 is a MONEY thing, whose own receipt pours
/// its source's hue at the card's own scale (`MoneyReceiptCard`, prd §369),
/// never the sheet itself. An eyebrow (source icon · kind · age), the
/// title large, the thing's media,
/// then a quiet spec table (WHEN/SITE/BY/FROM/TAGS — labels change per
/// kind). Verbs are the disc dial everywhere now (standardized 2026-07-23 —
/// was B1-only; derived, capped, writes confirm), Share always its last
/// disc. The TAGS row is read-only provenance (prd §178 — the
/// filing surface retired; renaming a cluster lives in project detail).
/// Related streams last. Spacing does the separating — no hairlines.
struct ThingSheetView: View {
    @Bindable var thing: Thing
    /// Set only when this sheet is PUSHED inside another sheet's own
    /// NavigationStack (2026-07-23) — the Worth-a-look tray's flagged rows,
    /// so far. A plain `.sheet(item:)` presentation (every other call site)
    /// leaves this nil and the sheet looks exactly as it always has: no
    /// system nav bar reserved above the eyebrow, dismiss is the grabber.
    /// When set, the system nav bar is hidden and the back chevron rides
    /// the eyebrow's own line instead of a separate ~44pt bar above it —
    /// the "dead top zone" a pushed presentation otherwise leaves (2026-07-23,
    /// user critique of the Worth-a-look detail screen).
    /// Which list this sheet was opened from (prd §645 pass 3). `.none` — the
    /// default — draws no next/previous doors, which is the honest answer for
    /// every caller that has no list behind it: a deep link, a Spotlight
    /// hand-off, a search result, an agent's citation, a room head.
    var walk: WalkScope = .none
    var onBack: (() -> Void)? = nil
    /// True when this view is rendered IN PLACE rather than presented — the
    /// detail pane at rest, which holds the newest record with no selection
    /// behind it (`MainSurface.paneRest`, 2026-08-02). It carries no back
    /// handler because there is nowhere to go back TO, which is exactly why it
    /// can't ride `onBack != nil` for the toolbar rule below: without this it
    /// would take the `.automatic` branch and hand the shell's own
    /// NavigationStack a nav bar over the FEED, which is not even the column
    /// this view is in.
    var inlineRest: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(ShellChrome.self) private var chrome
    /// For the Track tray a repeating charge raises (prd §1181); optional, since a
    /// Catalyst sheet may not carry it (§872), and then Track is not offered.
    @Environment(BridgeStore.self) private var bridges: BridgeStore?

    @State private var confirmingVerb: Verb?
    /// The screenshot, opened full screen and zoomable (2026-08-02) — the Zoom
    /// disc, and a tap on the framed shot itself.
    @State private var zoomingPhoto = false
    @State private var verbResult: String?
    /// A bridge's no must READ as a no — green success styling on a failure
    /// would claim a write that didn't happen (honesty rule).
    @State private var verbResultIsError = false
    @State private var relatedStream = GenStream()
    /// "Related" for tag overlap; "In your things" when a watched token's
    /// The shelf's only title since prd §632 — the token case, the one
    /// relatedness the app can prove: things whose own words name this token.
    @State private var relatedTitle = "In your things"
    /// Naming a wallet transaction's counterparty (2026-07-15) — the address
    /// being named, and the draft. The label enriches every FUTURE transfer
    /// with that counterparty (CounterpartyLabels).
    @State private var counterpartyTarget: String?
    /// The non-wallet identity the Name disc is naming (prd §916): a sender,
    /// a poster, a login — saved into `ContactBook`, never the wallet book.
    @State private var identityTarget: Identity?
    /// Flipped by "Not now" so the nudge leaves immediately — the decline is
    /// also persisted, so it never returns for this address (prd §169).
    @State private var nudgeDeclined = false

    // MARK: - The note anatomies (prd §366)

    /// "How it landed" for a note — words, read time, where it came from.
    @State private var noteReception: NoteReception?
    /// The other passages already landed from the same book, and the total
    /// (which includes this one). Read once on open, never held as a promise.
    @State private var siblingPassages: [KeyedThing] = []
    @State private var siblingTotal = 0
    /// What else the corpus holds from the day this entry describes.
    @State private var sameDayThings: [KeyedThing] = []
    /// The same date in the other years of this journal, and the entries either
    /// side of this one (prd §399). Read once on open, never persisted — the
    /// `replies`/`approvalCheck` shape this sheet already uses.
    @State private var otherYears: [KeyedThing] = []
    @State private var previousEntry: KeyedThing?
    @State private var nextEntry: KeyedThing?

    /// The second-encounter naming nudge, when this sheet earns one.
    private var namePrompt: (address: String, count: Int, kind: AddressBook.Kind)? {
        guard !nudgeDeclined else { return nil }
        return AddressNudge.prompt(for: thing, context: modelContext)
    }
    @State private var counterpartyDraft = ""
    /// A post/cast's thread (2026-07-14) — fetched live from the source's
    /// public API when the sheet opens a social thing (Bluesky);
    /// the section renders only when replies exist (no dead section, no
    /// spinner theater).
    @State private var replies: [SocialReply] = []
    /// Walking the thread in-app (2026-07-16) — the parent this post answers,
    /// opened as a post sheet rather than kicked out to the browser.
    @State private var walkingTo: SocialCard?
    /// Whoever is behind a tapped face — a person's profile card, or the
    /// address card for a wallet (prd §369 amendment).
    ///
    /// **One route, not two states, and deliberately so.** The money receipt's
    /// subject face became a door in the same pass, and its destination is
    /// `AddressCard`. Giving it a `.sheet` of its own would have made a FOURTH
    /// sibling presentation on this view — the exact count the standing
    /// one-screen-one-`.sheet` rule exists to prevent, and which the
    /// `fullScreenCover` below already went out of its way not to become. A
    /// tapped face has one destination whichever kind of face it is, so the
    /// two share the slot that already existed for the question.
    @State private var faceTarget: FaceTarget?

    /// Where a tapped face leads.
    enum FaceTarget: Identifiable {
        case person(SocialProfile)
        case address(AddressBook.Entry)
        /// A held checklist item's reminder tray (prd §1022). A CASE on the
        /// existing face route rather than a `.sheet` of its own: this view
        /// already carries three sibling `.sheet` modifiers and a fourth is the
        /// half-open-then-close failure the file's own `fullScreenCover`
        /// comment goes out of its way to avoid — caught by
        /// `money-receipt-selftest`'s own guard when one was first added.
        case remind(ordinal: Int, text: String)
        /// Track a subscription, filled in from a charge that repeats (prd
        /// §1181) — a case here for the reason `remind` is one.
        case track(String)
        /// Follow this page's site, the Reading tray opened on its host (§1184).
        case followSite(String)
        /// Follow a video's channel, Media's tray opened on it (§1186).
        case followChannel(seat: String, name: String)

        var id: String {
            switch self {
            case .person(let profile): return "person:\(profile.id)"
            case .address(let entry):  return "address:\(entry.id)"
            case .remind(let ordinal, _): return "remind:\(ordinal)"
            case .track(let name): return "track:\(name)"
            case .followSite(let host): return "followSite:\(host)"
            case .followChannel(let seat, let name): return "followChannel:\(seat):\(name)"
            }
        }
    }
    /// An approval thing's prepare card (prd §112) — the grant's LIVE state,
    /// the fee to revoke, the doors out. Fetched on open like replies; the
    /// section renders only when the check answered.
    @State private var approvalCheck: WalletPrepare.Check?
    /// The ENS renew quote and the term it priced (prd §540). The term is held
    /// HERE rather than in the card so re-pricing doesn't tear the card down
    /// and rebuild it mid-interaction.
    @State private var ensRenewTerm: ENSRenew.Term = .oneYear
    @State private var ensRenewQuote: ENSRenewPrepare.Quote?
    @State private var ensRenewIsYours = false
    @State private var safeCheck: SafeBridge.Check?
    /// The money receipt (prd §369) and what the app says about it. Held in
    /// state rather than computed per body evaluation because the commentary
    /// FETCHES — a merchant board walks that source's rows — and a body can be
    /// re-evaluated many times per open. Recomputed when `safeCheck` answers,
    /// since a Safe receipt's stamp and its signer sentence both read it.
    @State private var moneyReceipt: MoneyReceipt?
    @State private var moneySays: MoneyCommentary?
    /// The last three with this party and how many there are in all (prd
    /// §1181), read with the receipt, never in a body (§628).
    @State private var moneyHistory: [Thing] = []
    @State private var moneyHistoryTotal = 0
    /// This year with this party (prd §1181): sent and received, in dollars
    /// and counts, this transfer included.
    @State private var moneyYear = MoneyYear()
    /// A card spend's visits this month, this one included, and their total
    /// (prd §1182).
    @State private var moneyMonth: [Thing] = []
    @State private var moneyMonthTotal: String?
    /// The event's day around it (prd §1182): this event and its neighbours
    /// in a four-hour window, read on the sheet's task (§628).
    @State private var dayBlocks: [EventDaySlice.Block] = []
    /// More from this artist or channel (prd §1186), read on the task (§628).
    @State private var mediaMore: [Thing] = []
    struct MoneyYear { var sentUSD = 0.0, sentCount = 0, receivedUSD = 0.0, receivedCount = 0 }
    /// Mirrors `MoneyActivityDriver.isTracking` for this record, so the control
    /// re-labels itself the moment it is used.
    @State private var tracking = false
    /// The Subscriptions list this mail is on, once read (prd §1115): its
    /// door to the list, or Track a subscription when it is on none.
    @State private var mailList: MailSubscriptions.Item?
    @State private var mailListRead = false
    /// The same link, saved earlier from a different source (2026-07-21) —
    /// `CrossSourceEcho` was built for this and briefly wired into a row
    /// anatomy (`ThingRow.swift`) nothing actually rendered, which would
    /// have run its SwiftData fetch on every link row in every feed. Once
    /// per sheet open, like `replies`/`approvalCheck` below, is the honest
    /// place to pay that cost.
    @State private var crossSourceEcho: String?
    /// When this transfer's counterparty was FIRST met across every watched
    /// wallet (prd §1025) — nil until read, read once per sheet open in the
    /// counterparty's own `.task`, never in a body (§628). `firstSeenIsThis`
    /// says the earliest transfer is this one.
    @State private var firstSeen: Date?
    @State private var firstSeenIsThis = false
    /// An Obsidian note's own `[[wikilink]]` targets, resolved against notes
    /// already landed (2026-07-28) — fetched once on open, like `replies`
    /// above. Held as `KeyedThing` (see `ThingRowKeying.swift`) rather than
    /// raw `Thing`s: this is a snapshot taken at `onAppear`, not a live
    /// `@Query`, so a delete-sync heal landing while the sheet is open could
    /// otherwise leave a stale row that traps on read — `liveLinkedNotes`
    /// filters to `.isLive` at render time before anything reads through it.
    @State private var linkedNotes: [KeyedThing] = []
    /// A locked note's words while this sheet has them open (prd §982) —
    /// opened by device-owner authentication, held here only, never written
    /// back. nil is the locked face.
    @State private var openedLock: NoteLock.Sealed?
    /// Why the last Open did not open, when it was not the person declining.
    @State private var lockFailure: NoteLock.Failure?
    /// The body after a tick (prd §982). The model write lands at once, but
    /// the sheet's body does not observe `content` (measured: the circle
    /// filled only on the next open), so the ticked text is held here and
    /// drawn in its place.
    @State private var tickedBody: String?
    /// WHAT POINTS AT THIS (2026-08-08, prd §340) — the incoming half, for any
    /// thing rather than only an Obsidian note: the notes that wikilink here,
    /// and the posts and notes whose own text carries this thing's link.
    /// Replaces the Obsidian-only `backlinks` shelf and the dead "You wrote"
    /// spec row, which said one of these facts and could not be tapped.
    ///
    /// Plain VALUES, not `KeyedThing`s — a `ThingLinks.Tie` carries an id and
    /// display strings, so a delete-sync heal landing under the open sheet
    /// leaves nothing model-shaped here to tombstone (the liveness class is
    /// avoided by construction rather than guarded, as in `writtenAbout` before
    /// it). The walk pays one equality fetch at tap time instead.
    @State private var pointingAt: [ThingLinks.Tie] = []
    /// Walking into a linked note (2026-07-28) — a plain re-presentation of
    /// this same sheet over the target, the recursive shape already used
    /// elsewhere in this app (e.g. `-agentThingProbe`'s Stack push).
    @State private var walkingToNote: KeyedThing?
    /// The page a highlight was kept from (prd §1020), read once on appear.
    @State private var highlightOrigin: Thing?
    /// A highlight's card tray (prd §1020).
    @State private var sharingHighlight = false
    /// The scope a walked-to sheet inherits, so next/previous keeps following
    /// the SAME list two doors in. Only the neighbour doors set it; every
    /// other walk in this file (a quote, a parent, a vault link, an "on this
    /// date" row) leaves it `.none`, because those leave the list.
    @State private var walkingToScope: WalkScope = .none
    /// The earlier copy of this thing, when there is one (prd §282) — keyed,
    /// not raw, because it is a `Thing` held in `@State` and a heal landing
    /// under this open sheet must never leave the row reading a dead model.
    @State private var keptBefore: KeyedThing?
    /// The other rows about the same object (prd §1079): a PR's earlier
    /// events, an article's other saves. The merged room folds them under its
    /// newest row, so this is where they stay reachable. Newest first.
    @State private var sameObject: [KeyedThing] = []
    /// Upcoming moments this thing's own text names (prd §282). Plain values,
    /// not model references — read once off a live `Thing` and safe to hold.
    @State private var facts: [ScreenshotFacts.Fact] = []
    /// Translate verb (2026-07-17): the system Translation sheet, shown over
    /// the thing's own words — no custom UI, Apple's picker does the rest.
    @State private var showTranslate = false
    @State private var translateText = ""
    /// Seeded by the record's shape (2026-07-13 polish): a TALL thing (media
    /// or a long body) still opens FULL-height so its verbs never start
    /// below the fold — the original `.large` ruling, kept for the case that
    /// earned it. A short record opens `.medium` instead of one card of
    /// content over a screen of black. Both detents stay a drag away.
    @State private var detent: PresentationDetent
    /// The content's measured height (prd §886) — the sheet opens exactly this
    /// tall, capped by the system at its full height. nil until measured.
    @State private var fittedHeight: CGFloat?
    /// HOW IT LANDED (prd §363, 2026-08-12) — the block that replaced the spec
    /// table's one social row. Composed on open and again when the live
    /// engagement read answers, so the numbers are the freshest the app has.
    @State private var reception: SocialReception?
    /// This person's posts already in the corpus — the `.person` shape's
    /// second half, and the thing a profile card structurally cannot know.
    /// Keyed, not raw (`ThingRowKeying.swift`): a snapshot held in `@State`.
    @State private var personPosts: [KeyedThing] = []
    /// How often you've paid this merchant (prd §364). Held in `@State` and
    /// read once on open rather than computed in `body`: it is a corpus fetch,
    /// and a computed property here would run it on every graph update the
    /// sheet takes — which on a live `@Query` is a lot of them.
    @State private var purchaseRecurrence: PurchaseStageSource.Recurrence?
    /// Stamped at construction, before the zoom-in transition starts — the
    /// clock `dismissWhenSettled` reads to tell a fast tap from a settled one.
    private let presentedAt = Date()

    init(thing: Thing, walk: WalkScope = .none,
         onBack: (() -> Void)? = nil, inlineRest: Bool = false) {
        self.thing = thing
        self.walk = walk
        self.onBack = onBack
        self.inlineRest = inlineRest
        // The same crash guard `FeedScreen.standsAlone` earned (2026-07-24,
        // live TestFlight crash): a `Thing` a concurrent delete-sync heal
        // pass (SyncReconcile, BridgeRefresh) removes between the row's tap
        // and this sheet's construction has its `modelContext` niled first —
        // reading that is documented-safe, but every other property below
        // fault-resolves against the gone store and crashes. Transactions
        // are the kind most exposed to this race (this sheet only started
        // opening them directly today — 139f4fb dropped the old "Wallet rows
        // push the management screen instead" special case — and a wallet
        // bridge's own re-sync is the most common source of a same-tick
        // delete). `body` carries the matching guard for the render side.
        guard thing.modelContext != nil else {
            _detent = State(initialValue: .medium)
            return
        }
        let hasMedia = thing.kind == .screenshot
            // A folder-picked image opens at the same height as a screenshot
            // now that it draws in the same frame (prd §365).
            || FilesIngest.isStoredPicture(thing.sourceRef)
            // A folder-picked VIDEO for the height, and only the height
            // (2026-08-17). It is deliberately absent from the `framedShot`
            // test below — a video draws its own player, and the floating
            // frame's tap opens the PHOTO viewer, which would freeze it into
            // the one still we happened to poster it with.
            || FilesIngest.isVideoRef(thing.sourceRef)
            || !(thing.previewImageURL ?? "").isEmpty
            // Any charted link — token, stock, PostHog metric. This read
            // Token and Stock only, so a Kalshi market (a seat since deleted)
            // opened half-height with its verbs below the fold (found 2026-07-27 when
            // the three copies of this chain were folded into ThingChart).
            || ThingChart.kind(for: thing) != nil
            // A quoted post is a card the height of a small paragraph — the
            // same "tall thing" the detent rule was written for, so it opens
            // full-height rather than starting its verbs below the fold.
            || thing.quote != nil
            // An article opens near-full like the page it is (prd §882): its
            // head is the room's cover and its words start under it.
            || ThingContentView.readsAsArticle(thing)
        // A social post's `content` is its permalink — always short — so the
        // length test has to read the POST, else a 900-character cast opened
        // half-height with its own words below the fold (2026-07-16).
        let bodyLength = max(thing.content.count, (thing.postText ?? "").count)
        _detent = State(initialValue:
            hasMedia || bodyLength > Self.readingLength ? .large : .medium)
    }

    @ViewBuilder
    var body: some View {
        // Mirrors the `init` guard above: a delete that lands between the
        // sheet's construction and this render (both on the main actor, but
        // not the same instant) would otherwise crash here instead — every
        // branch below reads `thing.kind`/`thing.title`/etc. unconditionally.
        // Nothing to show for a thing that's gone, so the sheet just leaves.
        if thing.modelContext == nil {
            // This item was removed by a concurrent delete-sync heal between
            // the row tap and this render. DON'T dismiss from `onAppear`:
            // that fires DURING the sheet's (zoom) present transition and
            // trips UIKit's dismiss-mid-transition assertion — a `brk 1`
            // inside `-[UIPresentationController runTransitionForCurrentState
            // Animated:]`, reached via SwiftUI's `SheetBridge.preferencesDid
            // change` (live TestFlight crash, build 142, opening a Bluesky
            // post a heal had just removed; the empty branch also drops the
            // `.presentationDetents` the sheet expects, which is what pokes
            // `preferencesDidChange`). Wait for the present transition to
            // settle, THEN dismiss — a brief empty sheet that closes itself
            // is the honest outcome for a thing that's gone, and it never
            // races the transition. `.task` is cancelled if the user swipes
            // it away first.
            Color.clear.task {
                try? await Task.sleep(for: .milliseconds(500))
                dismiss()
            }
        } else {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // EVERY SHAPE QUESTION, ANSWERED ONCE PER PASS (prd §718). Each
                // name below is a computed property that re-derives from the
                // record on every read, and three of them chain: `agentShape`
                // asks `workReading`, which asks `purchaseReading`. The body
                // read them about sixty times between the head, the content
                // gate and the trailing blocks, so one sheet present ran the
                // same derivation dozens of times per frame of its rise — the
                // §646 cost, on the sheet. Shadowing under the SAME names keeps
                // every call site and every self-test pin unchanged; the
                // helpers outside the body still read the properties.
                let socialShape = self.socialShape
                let drawsSocialBody: Bool = socialShape == .post || socialShape == .notice
                let noteShape = self.noteShape
                let walletbeatShape = self.walletbeatShape
                let l2beatShape = self.l2beatShape
                // A Privy app wallet (prd §803e) — a dictionary lookup.
                let privyApp = thing.sourceRef.flatMap { PrivyHomeStore.shared.byRef[$0] }
                // The checkups that stand in the room's frame (prd §1187) and
                // draw their own tiles.
                let framedChain: String? = l2beatShape == .chain ? L2beatWatch.chainID(from: thing) : nil
                let framedWallet: String? = walletbeatShape == .wallet ? WalletbeatWatch.walletID(from: thing) : nil
                let drawsFramedCheck: Bool = framedChain != nil || framedWallet != nil || privyApp != nil
                let isPerson: Bool = socialShape == .person
                let framesOwnTiles: Bool = drawsFramedCheck || isPerson
                    || l2beatShape != nil || walletbeatShape != nil
                let purchaseReading = self.purchaseReading
                let workReading = self.workReading
                let agentShape = self.agentShape
                let agentConversation = agentShape == .conversation ? self.agentConversation : nil
                let linkOnlyBody = self.linkOnlyBody
                let framedShot: Bool = moneyReceipt == nil
                    && (thing.kind == .screenshot
                        || FilesIngest.isStoredPicture(thing.sourceRef))
                // THE ARTICLE HEAD (prd §882) — drawn exactly where the generic
                // title block would have been, so every shape ahead of it in
                // the chain below still wins, and the content view is told to
                // leave the picture to the head.
                // MEDIA (prd §897) — a track, a video, an episode; it wins over
                // the article head, which a video with a stored description met.
                let mediaHead: Bool = MediaSheetBox.isMedia(thing) && ThingChart.kind(for: thing) == nil
                    && moneyReceipt == nil && !framedShot
                let chartHead: Bool = ThingChart.kind(for: thing) != nil
                let readsAsArticle: Bool = !mediaHead && ThingContentView.readsAsArticle(thing)
                    && moneyReceipt == nil && !framedShot && !isSocialPost
                let ownShape: Bool = socialShape == .person || purchaseReading != nil
                    || workReading != nil
                let ownReading: Bool = agentConversation != nil || l2beatShape != nil
                    || privyApp != nil || walletbeatShape != nil || noteShape != nil
                let articleHead: Bool = readsAsArticle && !ownShape && !ownReading
                // THE POST HEAD (prd §884) — a post that leads with its person
                // gets the article head's shape: who, the pink day, the words.
                let postHead: Bool = isSocialPost
                    && SocialSheetSource.eyebrowLeadsWithPerson(thing, shape: socialShape)
                    && moneyReceipt == nil && !framedShot
                // A MOMENT (prd §892): an event, a workout, a reminder — its
                // head, its title, and WHEN, which the sheet never drew.
                let momentHead = (thing.kind == .event || thing.kind == .reminder)
                    && moneyReceipt == nil
                    && ThingChart.kind(for: thing) == nil && !articleHead && !postHead
                // A CONVERSATION, A MAIL, A CHAT (prd §894): the shared head,
                // the dial under it, the words after — they are read for pages.
                let mailHead = thing.kind == .mail && moneyReceipt == nil
                    && !articleHead && !postHead && !momentHead && noteShape == nil
                let transcriptHead = socialShape == .transcript
                let talkHead = agentConversation != nil || mailHead || transcriptHead
                // ANYTHING ELSE (prd §1191): the sheet's last arm, in the
                // room's frame with its own tiles.
                let boxedByShape: Bool = moneyReceipt != nil || framedShot || isPerson
                    || purchaseReading != nil || workReading != nil || agentConversation != nil
                    || drawsFramedCheck || l2beatShape != nil || walletbeatShape != nil
                    || noteShape != nil
                let boxedByHead: Bool = chartHead || mailHead || transcriptHead || momentHead
                    || postHead || mediaHead || articleHead
                let plainHead: Bool = !boxedByShape && !boxedByHead
                let ownHead: Bool = articleHead || postHead || framedShot || moneyReceipt != nil
                    || mediaHead || chartHead
                    || workReading != nil
                    || (purchaseReading.map { $0.archetype != .watch } ?? false)
                    || momentHead || noteShape != nil || talkHead || framesOwnTiles || plainHead
                // Sequenced entrance (delight 2026-07-14): the sheet composes
                // itself over the pouring wash — eyebrow, then title, then
                // media, then spec — each a beat behind the last, one-shot.
                if !ownHead || onBack != nil {
                HStack(spacing: DS.Space.s3) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .dsGlyph(.caption)
                                .foregroundStyle(DS.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(DS.fillLine))
                                // DRAWN 30, TARGETED 44.
                                .dsTapTarget(Circle())
                        }
                        .buttonStyle(PressSpring())
                        .dsHover()
                        .accessibilityLabel(Text("Back"))
                        // A bare chevron: the tooltip names it on Mac with the
                        // same word VoiceOver reads, so the two can't drift.
                        .dsTooltip(String(localized: "Back"))
                    }
                    // The article head carries its own eyebrow (prd §882).
                    if !ownHead { eyebrow }
                }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .settleIn()
                }
                if !postHead, let parent = thing.parent {
                    replyingToRow(parent)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s2)
                        .settleIn(delay: 0.04)
                }
                // The stage (B1, 2026-07-16; extended 2026-07-21 to Moved and
                // Swapped): a wallet transfer/move/swap or a screenshot leads
                // with a HERO that depicts the thing — parties + signed
                // amount, two of your own wallets, a trade's two legs, or the
                // image in a floating frame — and its verbs become the dial.
                // Everything else keeps the title-led layout.
                // The frame is for a thing made of PIXELS, not for one
                // particular bridge (2026-08-12, prd §365) — a folder-picked
                // image is the same picture as a screenshot and used to draw
                // unframed and untappable. `FilesIngest.isStoredPicture` says
                // why the test is on the ref rather than on the bytes.
                // (`framedShot` is read above, where the article head needs it.)
                if let moneyReceipt {
                    // The subject face is a door (prd §369 amendment): the
                    // history this sheet already draws belongs to that address,
                    // and the gesture people try first is a tap on the face.
                    // The dial keeps its own verbs at parity, so nothing here
                    // is reachable ONLY by tapping a picture.
                    // NO PADDING HERE (prd §583). `dsSheetHeadBlock` inside
                    // the card carries the inset now. It used to sit outside
                    // the paper, which — since the paper insets its own
                    // content as well — indented this head one step deeper
                    // than the eyebrow above it and every row below it. The
                    // paper's edge hid that; without it the step is the first
                    // thing you see, which is how it was caught.
                    // THE ROOM'S FRAME (prd §1181): the party's name as the
                    // sheet's title, the box (its face, what happened, the
                    // amount, its worth, a row of facts), the tiles ending in
                    // the act that keeps up with it, then the last three with
                    // this party as rows — title, box, tiles, list, a room's order.
                    // The party's name is the sheet's title, a room's own row.
                    DSRoomTitleRow(title: MoneyReceiptBox.title(moneyReceipt))
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.04)
                    MoneyReceiptBox(receipt: moneyReceipt, landed: thing.capturedAt,
                                    transfer: moneyTransfer(moneyReceipt),
                                    card: moneyCard,
                                    source: thing.source, cells: moneyCells(moneyReceipt),
                                    unnamed: moneyUnnamed, onSubject: openAddressCard)
                        // Read once per open (§628), the spec row's own read.
                        .task(id: "firstSeen:\(thing.counterpartyAddress ?? "")") {
                            readFirstSeen()
                            readMoneyHistory()
                        }
                        .dsRoomBox()
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                    VerbDial(thing: thing, verbs: walletVerbs, onVerb: runVerb, onName: nil,
                             keep: moneyKeep)
                        .padding(.top, DSRoomChassis.leadGap)
                        .settleIn(delay: 0.08)
                    dialResult
                    // The poisoning flag rides EVERY wallet stage, and a record
                    // still in the machine can be watched from the lock screen
                    // (prd §369 amendment) — both under the tiles now.
                    if thing.isFlagged {
                        securityWarning
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                            .settleIn(delay: 0.1)
                    }
                    if moneyReceipt.finality == .open {
                        trackRecordControl(moneyReceipt)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                            .settleIn(delay: 0.11)
                    }
                    // What the app read around it, when it is not the history the
                    // rows already list: a Privacy Pools ladder, a swap's rate, a
                    // note. The history and merchant bars are the rows now.
                    if let moneySays, moneySays.drawsBesideRows {
                        MoneyCommentaryCard(commentary: moneySays)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s6)
                            .settleIn(delay: 0.11)
                    }
                    if moneyHasPerson, let cp = thing.counterpartyAddress {
                        MoneyYearTotals(name: moneyPartyName(moneyReceipt),
                                        sentUSD: moneyYear.sentUSD, sentCount: moneyYear.sentCount,
                                        receivedUSD: moneyYear.receivedUSD, receivedCount: moneyYear.receivedCount,
                                        onAll: { openAddressCard(cp) })
                            .padding(.top, DS.Space.s6)
                            .settleIn(delay: 0.12)
                    } else if moneyCard != nil, moneyMonth.count > 1 {
                        // This month at the shop (prd §1182): each visit as its
                        // day and what it cost, the total in the header.
                        MoneyHistoryRows(title: String(localized: "This month"),
                                         rows: moneyMonth.keyed,
                                         trailing: moneyMonthTotal,
                                         amount: Self.spendAmount,
                                         onOpen: { walkingToScope = .none; walkingToNote = KeyedThing($0) })
                            .padding(.top, DS.Space.s6)
                            .settleIn(delay: 0.12)
                    } else if moneyCard == nil {
                        MoneyHistoryRows(title: moneyHistoryTitle(moneyReceipt),
                                         rows: moneyHistory.keyed,
                                         onOpen: { walkingToScope = .none; walkingToNote = KeyedThing($0) })
                            .padding(.top, DS.Space.s6)
                            .settleIn(delay: 0.12)
                    }
                } else if framedShot {
                    // The framed exception (B1c): facts stand bare on the wash;
                    // pixels recess into a frame that floats on it — the image
                    // sits IN the source's color without the color ever touching
                    // its pixels. The title drops below at reading size: for a
                    // screenshot the picture is the identity, the words the
                    // caption.
                    //
                    // Tapping the picture opens it full screen (2026-08-02) —
                    // the gesture people try first, and the same destination
                    // the Zoom disc reaches. Not a `Button`: the frame is
                    // content, not a control, so it takes the tap without
                    // gaining a button's press styling.
                    // Big and unlifted (prd §885): the shadow floated a
                    // thumbnail; a picture the column's width is the page.
                    // THE ROOM'S FRAME (prd §1186): the title, the picture filling
                    // the box — a screenshot cropped from its top, as the picture
                    // grid crops one (§910) — a tap or the corner key to see it
                    // whole, the tiles, then what was found in it.
                    DSRoomTitleRow(title: TitleSeam.split(thing.title).name)
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.04)
                    Button {
                        if thing.sourceRef != nil || thing.previewImageData != nil { zoomingPhoto = true }
                    } label: {
                        PhotoWell(thing: thing, anchor: thing.kind == .screenshot ? .top : .center)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .dsGlyph(.caption, weight: .bold)
                                    .foregroundStyle(Color.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .padding(DS.Space.s3)
                                    .accessibilityHidden(true)
                            }
                    }
                    .buttonStyle(PressSpring())
                    .dsTapTarget()
                    .dsRoomBox(bleed: true)
                    .padding(.top, DS.Space.s3)
                    .accessibilityLabel(Text(verbatim: TitleSeam.split(thing.title).name))
                    .accessibilityHint(Text("Opens the photo full screen"))
                    .dsTooltip(String(localized: "Opens the photo full screen"))
                    .settleIn(delay: 0.06)
                    VerbDial(thing: thing, verbs: sheetVerbs,
                             onVerb: runVerb, onName: nil)
                        .padding(.top, DSRoomChassis.leadGap)
                        .settleIn(delay: 0.08)
                    dialResult
                    // What the picture names, under the tiles (§885's facts).
                    if !facts.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("Found in it").dsText(.heading20).foregroundStyle(DS.brandInk)
                                .padding(.horizontal, DSRoomChassis.inset)
                            factRows
                        }
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.12)
                    }
                } else if socialShape == .person {
                    // A PERSON, not a link to one (prd §363). The title slot
                    // held "@alice started following you" at display size and
                    // the body held a link preview of their profile page; the
                    // face and the handle were on the record the whole time.
                    personFrame
                } else if let purchaseReading {
                    // The purchase receipt / watched-product card (prd §364).
                    // It REPLACES the title block for the same reason the Work
                    // receipt does: the headline it draws IS the subject, and
                    // on a receipt that subject is the merchant the title's
                    // own head was already saying.
                    // A PURCHASE takes the money sheet's shape (prd §895, §887):
                    // the merchant leads, the amount is the head rung.
                    if purchaseReading.archetype != .watch {
                        // The merchant is the room's title (prd §1190).
                        DSRoomTitleRow(title: purchaseReading.subject)
                            .padding(.horizontal, DSRoomChassis.inset)
                            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                            .settleIn(delay: 0.04)
                    }
                    if purchaseReading.archetype != .watch {
                        // The room's frame (prd §1179): the receipt in the box.
                        PurchaseStageView(thing: thing, reading: purchaseReading,
                                          recurrence: purchaseRecurrence, headDrawn: true)
                            .dsRoomBox()
                            .padding(.top, DS.Space.s4)
                            .settleIn(delay: 0.06)
                    VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil)
                        .padding(.top, DSRoomChassis.leadGap)
                        .settleIn(delay: 0.08)
                    dialResult
                    } else {
                        PurchaseStageView(thing: thing, reading: purchaseReading,
                                          recurrence: purchaseRecurrence, headDrawn: false)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                            .settleIn(delay: 0.06)
                    }
                } else if let workReading {
                    // The Work receipt (2026-08-12) — the §302 ledger's
                    // grammar one category over. It REPLACES the title block
                    // rather than sitting above it: the headline it draws IS
                    // the title, minus the clause the status line is already
                    // saying, so keeping both would print the row twice.
                    // WORK leads with where it lives (prd §895): the source's
                    // mark and the pink day, the project on the line under it.
                    // The project is the room's title, else the app (prd §1190).
                    DSRoomTitleRow(title: workReading.project ?? thing.source)
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.04)
                    // The room's frame (prd §1179): the status in the box.
                    WorkStageView(thing: thing, reading: workReading,
                                  detail: WorkStage.statusDetail(
                                    workRow, clause: workReading.statusWord),
                                  projectInHead: true)
                        .dsRoomBox()
                        .padding(.top, DS.Space.s4)
                        .settleIn(delay: 0.06)
                    VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil)
                        .padding(.top, DSRoomChassis.leadGap)
                        .settleIn(delay: 0.08)
                    dialResult
                } else if let agentConversation {
                    agentFrame(agentConversation)
                } else if drawsFramedCheck {
                // A chain, a wallet or an app's wallet in the room's frame
                // (prd §1187), each drawing its own tiles.
                framedCheck(chain: framedChain, wallet: framedWallet, privy: privyApp)
                    .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            } else if let l2beatShape {
                l2beatHead(l2beatShape)
                    .padding(.top, DS.Space.s3)
                    .settleIn(delay: 0.06)
            } else if let walletbeatShape {
                // REPLACES the title block, like the note and receipt arms below: a
                // watched wallet's title is just the wallet's name, which its own report
                // card says better, and an incident's title is set inside the anatomy at
                // reading size rather than printed twice.
                walletbeatHead(walletbeatShape)
                    .padding(.top, DS.Space.s3)
                    .settleIn(delay: 0.06)
            } else if let noteShape {
                    // THE NOTE ANATOMIES (prd §366). Like the Work receipt
                    // above, these REPLACE the title block rather than sitting
                    // over it: an entry's title was cut out of its own first
                    // line, so drawing both printed that line twice, and a
                    // passage's title is an 80-character clamp of words the
                    // shape below sets in full.
                    noteHead(noteShape)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.06)
                } else if ThingChart.kind(for: thing) != nil {
                    // A CHARTED row draws no title (prd §369 amendment); since
                    // §897 it leads with the shared head — the asset's name, the
                    // pink day, what it is — and the price below drops its own
                    // name and symbol and takes the head rung.
                    // In the room's frame since prd §1188: the asset is the
                    // title; the content boxes the price and seats the tiles.
                    DSRoomTitleRow(title: Self.chartParts(thing.title).name)
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.04)
                } else if mailHead {
                    mailFrame
                } else if transcriptHead {
                    transcriptFrame
                } else if momentHead, thing.kind == .event,
                          !thing.factList.contains(where: { $0.action == .metric }),
                          let start = momentStart {
                    // AN EVENT AS A SLICE OF ITS DAY (prd §1182): the title a
                    // room's, the box the hours around it, the tiles, the facts.
                    DSRoomTitleRow(title: TitleSeam.split(thing.title).name)
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.04)
                    EventDaySlice(start: start, end: thing.endAt,
                                  allDay: thing.factList.contains { $0.action == .allDay },
                                  blocks: dayBlocks)
                        .dsRoomBox()
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                        .task(id: thing.id) { readDayBlocks(around: start) }
                    VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil)
                        .padding(.top, DSRoomChassis.leadGap)
                        .settleIn(delay: 0.08)
                    dialResult
                    let rows = MomentSheetBlock(start: start, end: thing.endAt,
                                                facts: thing.factList, part: .rows)
                    if rows.hasRows {
                        rows.padding(.top, DSRoomChassis.leadGap)
                    }
                } else if momentHead {
                    // THE ROOM'S FRAME (prd §1179, §1190): the title is the
                    // room's; the box is where it is from, the clock and what
                    // it measured; the tiles, then the facts.
                    DSRoomTitleRow(title: TitleSeam.split(thing.title).name)
                        .padding(.horizontal, DSRoomChassis.inset)
                        .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
                        .settleIn(delay: 0.04)
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(verbatim: momentSourceLine)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        if let start = momentStart {
                            MomentSheetBlock(start: start, end: thing.endAt,
                                             overdue: thing.kind == .reminder && start < .now,
                                             isReminder: thing.kind == .reminder,
                                             facts: thing.factList, part: .box)
                        }
                    }
                    .dsRoomBox()
                    .padding(.top, DS.Space.s4)
                    .settleIn(delay: 0.06)
                    VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil)
                        .padding(.top, DSRoomChassis.leadGap)
                        .settleIn(delay: 0.08)
                    dialResult
                    if let start = momentStart {
                        let rows = MomentSheetBlock(start: start, end: thing.endAt,
                                                    isReminder: thing.kind == .reminder,
                                                    facts: thing.factList, part: .rows)
                        if rows.hasRows {
                            rows.padding(.top, DSRoomChassis.leadGap)
                        }
                    }
                } else if postHead {
                    postFrame
                } else if mediaHead {
                    mediaFrame
                } else if articleHead {
                    articleFrame
                } else {
                    plainFrame
                }
                // Events speak through WHEN below; and when the content is
                // just the title again (a short note with no body beyond its
                // own headline), showing it twice reads as a stutter.
                // A social post always shows content — its pictures, what it
                // quotes, how it landed — and its `content` is a permalink, so
                // the title-stutter test never applied to it anyway.
                //
                // `linkOnlyBody` is bypassed for a post (prd §363): an X liked
                // post really does hold a bare permalink in `content`, and the
                // content view no longer draws that for a post shape — it
                // draws the pictures and the quote, which the bare-link test
                // would take with it.
                //
                // A NOTICE is bypassed for the same reason and needs it more
                // (prd §704): its `content` is ALWAYS a bare x.com permalink,
                // so the test caught every one of them and left the body to
                // `LinkPreviewCard` — over a host that serves no `og:` tags, so
                // the sheet was a headline with nothing under it.
                //
                // A note draws NOTHING here (prd §366) and that is the point:
                // the generic content view is where a journal entry's prose was
                // set at `body17` in `textSecondary` and cut at twelve
                // lines. `noteHead` above sets the same words at `reading17` in
                // primary ink with a real disclosure, so leaving this on would
                // print every entry twice, the second time worse.
                //
                // A CONVERSATION always draws, bypassing the title-stutter test
                // for the reason a post does: what it draws is the transcript,
                // and the test compares `content` (the opening ask) to the
                // title.
                // A PURCHASE or a WATCHED PRODUCT draws nothing here (prd
                // §364). The card above already leads with the record's own
                // art at size and states the price from the stored fields, so
                // leaving this on would re-draw both — and worse, as a
                // `LinkPreviewCard` re-scraping the page: for a Bitrefill order
                // with no gift link that page is the account's orders list,
                // the same URL on every order in the corpus.
                let shapeHasBody: Bool = moneyReceipt == nil && !framedShot
                    && socialShape != .person && noteShape == nil
                    && walletbeatShape == nil && l2beatShape == nil && privyApp == nil
                    && purchaseReading == nil
                // A reminder with a due date says it in its head (§892).
                let dueInHead: Bool = momentHead && thing.kind == .reminder && thing.dueAt != nil
                let wordsDiffer: Bool = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    != thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasWords: Bool = drawsSocialBody || agentShape == .conversation
                    || (!linkOnlyBody && thing.kind != .event && wordsDiffer)
                let contentShown: Bool = shapeHasBody && !dueInHead && hasWords
                if contentShown && !mediaHead {
                    sheetContent(articleHead: articleHead, mailHead: mailHead, chartHead: chartHead)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.12)
                }
                // What the record knows about this chat, in words — the block
                // that takes the spec table's `From — from your session` with
                // it (prd §367).
                if let agentConversation {
                    AgentReceiptCard(reading: agentConversation)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.16)
                }
                // The voice player, which is the ONE thing the generic content
                // view drew correctly for this category — kept, because a
                // recording is not prose and a transcript is not a recording.
                if noteShape == .entry, thing.kind == .voice {
                    ThingContentView(thing: thing)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.1)
                }
                // HOW IT LANDED (prd §363) — what the network reported, who
                // liked it, and one sentence saying how it got here. It stands
                // where the spec table stood and takes that table's `From` row
                // with it, so the two can never say the same thing twice.
                // A person's box already says how they came (prd §1187).
                if let reception, !isPerson {
                    // A post's counts stand in its box (prd §1188).
                    SocialReceptionCard(reception: postHead ? reception.withoutReadings : reception)
                        .padding(.horizontal, postHead ? DSRoomChassis.leadInset : DS.Space.s4)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.16)
                }
                // HOW IT LANDED, for a note (prd §366) — how long it is, how
                // long it takes to read, and one sentence saying where it came
                // from. Same position and the same job as the social block
                // above, and it takes the same `From` row with it.
                if let noteReception {
                    NoteReceptionCard(reception: noteReception)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.16)
                }
                // The stage already shows the counterparty (with its pencil),
                // so its spec table drops the Who row instead of repeating it.
                specTable(contentShown: contentShown, showsWho: moneyReceipt == nil,
                          drawn: !framesOwnTiles)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .settleIn(delay: 0.18)
                // A MAIL'S SUBSCRIPTION (prd §1115): the list it is on, or
                // the add when it is on none — the person's word puts a
                // sender with no list header on Day's Subscriptions tile.
                if mailHead {
                    mailSubscriptionDoor
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.19)
                        .task(id: thing.id) { readMailList() }
                }
                if let check = approvalCheck {
                    ApprovalPrepareCard(thing: thing, check: check)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                }
                if let quote = ensRenewQuote {
                    ENSRenewCard(thing: thing, term: $ensRenewTerm, quote: quote,
                                 isYours: ensRenewIsYours,
                                 onPickTerm: { priceENSRenewal(term: $0) })
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                }
                if let check = safeCheck {
                    let signable: Bool = {
                        guard case .pending = check.status, thing.sourceRef != nil
                        else { return false }
                        return SignerKey.presence() != .none
                    }()
                    SafeQueueCard(check: check, signable: signable)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                    // The ask (prd §425). Under the queue card because that
                    // card is what says WHO is still waiting; this is the one
                    // seat in it that is yours. Draws nothing until the chain
                    // has answered every refusal.
                    if signable, let ref = thing.sourceRef {
                        SafeSignBlock(sourceRef: ref)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                    }
                }
                // A STATEMENT waiting on this phone (prd §913) — the words
                // behind the hash and the one Sign, on the row that said
                // "your signature is needed". Only where a key exists.
                if let ref = thing.sourceRef, ref.hasPrefix("wallet:safemsg:"),
                   let safe = thing.walletAddress, !safe.isEmpty, SafeSigner.hasAnyKey {
                    SafeStatementBlock(source: .landed(ref: ref, safe: safe))
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                }
                if let nudge = namePrompt {
                    NameAddressPrompt(address: nudge.address, count: nudge.count,
                                      kind: nudge.kind) {
                        counterpartyTarget = nudge.address
                        counterpartyDraft = ""
                    } onDismiss: {
                        AddressNudge.decline(nudge.address)
                        withAnimation(DS.Motion.standard) { nudgeDeclined = true }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s3)
                }
                let headDrawsTiles: Bool = moneyReceipt != nil || framedShot || articleHead
                    || noteShape != nil || talkHead || momentHead || mediaHead
                    || workReading != nil || framesOwnTiles || postHead || chartHead || plainHead
                let purchaseAllowsDial: Bool = purchaseReading == nil || purchaseReading?.archetype == .watch
                if !headDrawsTiles && purchaseAllowsDial {
                    // The disc dial, standardized across every sheet
                    // (2026-07-23) — it was B1-only (the wallet stage, the
                    // framed screenshot) and everything else kept the older
                    // vertical text rows, a split with no reason behind it:
                    // `dialLabel` already collapses every derived verb
                    // ("Add to Reminders", "Open in Calendar") to a
                    // destination word, the same way it does for a stage's
                    // verbs, and the cap-4-plus-Share count already fits five
                    // discs. Approval is NOT special-cased out: its sheet
                    // never carried the feed row's green Approve pill in the
                    // first place (that color lives only on `ApprovalCard`,
                    // the feed's OWN consent card) — the rows here were
                    // already plain grey, so the dial changes their shape,
                    // not their weight.
                    VerbDial(thing: thing, verbs: sheetVerbs,
                             onVerb: runVerb, onName: nil, keep: sheetKeep)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.2)
                    dialResult
                }
                // The only chip left under a dial (prd §632): a saved agent
                // conversation you can carry on. "Ask about this", "Copy as
                // context" and the Pin chip are gone — the first two were the
                // agent bar and the Copy disc said twice, and Pin is a disc now.
                if !replies.isEmpty {
                    // One replies renderer (2026-07-16) — the thing sheet and
                    // the in-app walker show a reply identically, however deep
                    // you are. Here a tap OPENS the walker (this sheet has no
                    // navigation stack of its own); inside the walker the same
                    // tap pushes. The section doesn't know which — it just
                    // reports the card.
                    SocialRepliesSection(replies: replies, source: thing.source,
                                         open: { walkingTo = $0 })
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                // MORE FROM THIS BOOK (prd §366) — what makes ONE highlight
                // worth opening. A marked sentence out of context is a
                // fragment, and the others from the same work were already in
                // the corpus with nothing to reach them.
                if !siblingPassages.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("More from this book")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        NoteSiblingList(rows: siblingPassages) {
                            walkingToScope = .none
                            walkingToNote = KeyedThing($0)
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
                }
                // THAT DAY (prd §366) — the corpus answering a question the
                // journal app this entry came from structurally cannot.
                if !sameDayThings.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("That day")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .padding(.horizontal, DS.Space.s4)
                        NoteSameDayShelf(rows: sameDayThings) {
                            walkingToScope = .none
                            walkingToNote = KeyedThing($0)
                        }
                        .padding(.horizontal, DS.Space.s4)
                    }
                    .padding(.top, DS.Space.s4)
                }
                // THE SAME DATE, IN OTHER YEARS (prd §399). Under "That day",
                // which answers about the day ACROSS the corpus, because this
                // one answers about the date ACROSS the years — the wider
                // reading, and the one that only exists once a journal is deep.
                if !otherYears.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("On this date")
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        NoteOtherYearsList(rows: otherYears) {
                            walkingToScope = .none
                            walkingToNote = KeyedThing($0)
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
                }
                // THE ENTRY BEFORE AND AFTER (prd §399) — last of the note
                // shelves, because it is the way OUT of this entry and
                // everything above is about the entry itself.
                if previousEntry != nil || nextEntry != nil {
                    WalkDoors(previous: previousEntry, next: nextEntry) {
                        walkingToNote = KeyedThing($0)
                        walkingToScope = walk
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
                }
                // IN THE VAULT (prd §366) — both halves of the graph existed
                // and both were a plain list at the very bottom of the sheet.
                // Counted and led with, they are a reading: this note is a hub,
                // or this note is a leaf. The two counts are never summed — a
                // note that both links to and is linked from another would be
                // counted twice, and the directions are the information.
                if noteShape == .note, !liveLinkedNotes.isEmpty || !pointingAt.isEmpty {
                    NoteGraphCounts(linksOut: liveLinkedNotes.count,
                                    linkedFrom: pointingAt.count)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                // A highlight's one link is its "from" door (prd §1020).
                if !liveLinkedNotes.isEmpty, !Highlight.isHighlight(thing) {
                    noteLinksSection
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                if !pointingAt.isEmpty {
                    pointsAtSection
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                relatedShelf
                    .padding(.top, DS.Space.s4)
                // THE NAMES ON A THING ARE PAGES (prd §1209a): its person and
                // its app, each a door to everything with them.
                ThingPivotDoors(thing: thing) { query in
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        chrome.pivot = query
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        // A note of yours stands its three keys at the foot (prd §983).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pagedNote { keptNoteBand }
        }
        // THE SHEET FITS ITS CONTENT (prd §886). The two fixed heights left a
        // screenshot's sheet half empty: ~540pt of content is too tall for the
        // half detent and far short of the full one. The scroll view knows its
        // content's height including the safe area, so that IS the detent.
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom
        } action: { _, height in
            fitSheet(to: height)
        }
        // The source's hue wash that once poured down the crown is gone (user
        // ruling 2026-07-18: full ink, matching the feed). The wash read as
        // borrowed identity — and on a plain sheet it flooded the spec table,
        // muddying the When/From/Tags labels the "no ink depends on it" claim
        // said it wouldn't. Identity lives in the source glyph and row now; the
        // sheet is pure ink, like the photo viewer it already is below.
        // Ink: the sheet is black in both modes, like a photo viewer — its
        // controls render dark regardless of the app's theme.
        //
        // `dsInk()` (2026-07-24, user: "worth a look is ink. detail sheet is
        // not"): when this sheet is PUSHED inside the Worth-a-look tray's own
        // NavigationStack (`onBack` set), `presentationBackground` alone is a
        // preference bubbling up to that outer sheet's ONE real presentation
        // controller — and unlike `presentationDetents` (read live on every
        // push, per the fix above), it only seems to get read once at initial
        // setup and never again once something pushes on top. `dsInk()`'s
        // real `.background()` can't lose that race — it always covers.
        .dsInk()
        // The haptics this sheet has always fired, made audible (2026-08-16).
        //
        // `Haptics.swift` states the rule and this view was the standing
        // counter-example: the bus is global but the MAPPING is a view
        // modifier, and a `.sheet` covers the one `RootShell` attached — so
        // every `DSHaptic` call from in here bumped a counter nothing was
        // listening to. Six of them: two `.success` (a saved edit, a landed
        // write) and four `.tap`. None had ever been felt, and nothing about
        // that is visible from outside, which is exactly why the rule is
        // written down.
        //
        // Attached only when this view IS the presentation — `onBack` means it
        // was pushed inside the Worth-a-look tray, which carries `DSTray`'s
        // own, and `inlineRest` means it is rendered in place under the root's.
        // A second listener in one presentation buzzes twice.
        .modifier(SheetHaptics(active: onBack == nil && !inlineRest))
        // `dsReadSheet` carries the Mac twin (`dsPageSheet`) — detents are
        // inert on Catalyst, so the app's MOST-OPENED sheet was rendering at
        // the default ~540x620 form card. It is the fallback door for a thing
        // (a row tap fills the detail pane instead), but every deep link,
        // Spotlight hand-off and pane-less state still arrives here.
        .dsReadSheet(detent: $detent, fit: fittedHeight)
        // Only when pushed (`onBack` set): the eyebrow carries its own back
        // chevron now, so the system's default pushed-view nav bar (and the
        // back button it would ALSO draw) is redundant chrome on top of it.
        // `inlineRest` joins it for the same reason from the other direction —
        // rendered in place, there is no presentation for a nav bar to belong
        // to, and `.automatic` would hand one to the shell's stack instead.
        .toolbar(onBack != nil || inlineRest ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            streamRelated()
            Task { replies = await SocialThread.replies(for: thing) }
            // The note anatomies (prd §366). All of it is synchronous and
            // scoped: two bounded fetches for a passage, one bounded fetch for
            // an entry, and nothing at all for a vault note (its graph is
            // already read below). No request, no new field, no CloudKit
            // deploy — every number here is arithmetic over what we hold.
            if let shape = noteShape {
                if shape == .passage {
                    let found = NoteSheetSource.siblings(of: thing, context: modelContext)
                    siblingPassages = found.rows.keyed
                    siblingTotal = found.total
                }
                noteReception = NoteSheetSource.reception(
                    for: thing, shape: shape,
                    siblings: shape == .passage ? siblingTotal : nil)
                // What else the corpus holds from the day this entry
                // describes — the one reading a journal app can never make.
                // Only for an entry: a vault note's `capturedAt` is a file
                // modification time, so "that day" would be the day you last
                // touched the file, which is a fact about your editor.
                //
                // Not for a note of YOURS (prd §981, user: "hide it for you
                // notes"): its day is the day you wrote it, so the shelf
                // repeated the All feed's own day. It stays for an imported
                // journal, whose day is one the feed has long scrolled past.
                if shape == .entry, thing.source != NoteSheetSource.keptSource {
                    sameDayThings = NoteSheetSource
                        .sameDay(as: thing, context: modelContext).keyed
                }
                if shape == .entry {
                    // THE SAME DATE, IN OTHER YEARS (prd §399) — the room's
                    // anniversary answers today's date; this answers the
                    // entry's, which is what a journal is opened for. Bounded:
                    // one `fetchLimit = 1` read per candidate year, capped at
                    // `NoteSheetSource.yearSpan`.
                    otherYears = NoteSheetSource
                        .otherYears(of: thing, context: modelContext).keyed
                }
            }
            // THE ROWS EITHER SIDE (prd §399, widened by §645 pass 3) — two
            // bounded reads, so a room can be read AS a list instead of one
            // sheet at a time.
            //
            // §399 mounted this for `.entry` shapes ONLY, on the reasoning
            // that a vault note's `capturedAt` is a file's modification time,
            // so its "next" would be whatever you last edited. **That
            // objection does not survive the scope.** The door no longer
            // promises "the next thing you wrote"; it promises THE NEXT ROW IN
            // THE LIST YOU OPENED FROM, and that list is ordered by the very
            // same `capturedAt`. A door that matches the list behind it is
            // honest whatever the column happens to mean — and a door that
            // does not is the one thing pass 3 forbids, which is why `walk`
            // gates this rather than a shape.
            if walk.walks {
                let sides = NoteSheetSource.neighbours(of: thing, scope: walk,
                                                       context: modelContext)
                previousEntry = sides.previous.map(KeyedThing.init)
                nextEntry = sides.next.map(KeyedThing.init)
            }
            // HOW IT LANDED (prd §363), in two passes and deliberately so: the
            // stored snapshot composes in the first frame so the block never
            // pops in a beat late, and the LIVE read replaces it the moment it
            // answers. `engagement(for:)` returns nil for every source without
            // a live counts API (X, Instagram, TikTok, Snapchat), so an
            // archive costs no request and simply keeps its own numbers —
            // wearing the date that says so.
            // How often this merchant has been paid (prd §364) — a corpus read,
            // so it happens once here rather than in `body`.
            if purchaseReading?.archetype == .receipt {
                purchaseRecurrence = PurchaseStageSource.recurrence(
                    for: thing, context: modelContext)
            }
            if let shape = socialShape {
                reception = SocialSheetSource.reception(
                    for: thing, shape: shape, live: nil, context: modelContext)
                Task {
                    guard let live = await SocialThread.engagement(for: thing),
                          thing.isLive else { return }
                    reception = SocialSheetSource.reception(
                        for: thing, shape: shape, live: live, context: modelContext)
                }
                if shape == .person, let handle = thing.authorHandle, !handle.isEmpty {
                    personPosts = SocialSheetSource
                        .recentPosts(by: handle, source: thing.source,
                                     context: modelContext)
                        .keyed
                }
            }
            // The deadline hiding in a screenshot's own OCR text (prd §282).
            // Scoped to the kinds whose text is machine-read and therefore
            // never looked at by a person: a note you typed needs no help
            // finding its own date.
            if thing.kind == .screenshot {
                // The dates now, the model's words when they come (prd §885).
                facts = ScreenshotFacts.datedFacts(for: thing)
                Task { facts = await ScreenshotFacts.facts(for: thing) }
            }
            // `CrossSourceEcho.find` itself gates on `.link` (returns nil
            // instantly otherwise), but checking here too skips even
            // constructing the Task for the common non-link case.
            if thing.kind == .link {
                crossSourceEcho = CrossSourceEcho.find(for: thing, context: modelContext)
            }
            if thing.source == "Obsidian", !thing.wikilinks.isEmpty {
                linkedNotes = NoteLinks.resolve(thing.wikilinks, context: modelContext).keyed
            } else if NoteSheetSource.isKeptNote(thing), !thing.wikilinks.isEmpty {
                // A note kept here links anything you keep (prd §982).
                linkedNotes = NoteLinks.resolveKept(thing.wikilinks, from: thing,
                                                    context: modelContext).keyed
            }
            // What points AT this, for every thing rather than only a note
            // (prd §340). Its own fetches are scoped and skipped where they
            // can't answer — a thing with no link and no distinctive title
            // costs nothing here.
            pointingAt = ThingLinksSource.ties(for: thing, context: modelContext)
            if Highlight.isHighlight(thing) {
                highlightOrigin = Highlight.origin(of: thing, context: modelContext)
            }
            // The gate is a string check — non-approval things spend nothing.
            if WalletPrepare.applies(to: thing) {
                Task { approvalCheck = await WalletPrepare.check(for: thing) }
            }
            if SafeBridge.applies(to: thing) {
                Task { safeCheck = await SafeBridge.check(for: thing) }
            }
            // The gate is a string check plus a stored reading — a name that
            // isn't expiring, and every non-ENS thing, spends nothing.
            if ENSRenewPrepare.applies(to: thing) {
                ensRenewIsYours = ENSRenewPrepare.isYours(
                    name: ENSName.name(fromRef: thing.sourceRef ?? "") ?? "",
                    context: modelContext)
                priceENSRenewal(term: ensRenewTerm)
            }
            loadReceipt()
        }
        // A Safe receipt can't be complete until its queue read answers — the
        // stamp ("Your turn" vs "Pending") and the signer sentence both come
        // off it — so the receipt recomposes once, when it lands.
        .onChange(of: safeCheck == nil) { _, _ in loadReceipt() }
        }
        // Ask-before-acting: writes confirm, reads pass.
        .confirmationDialog(
            confirmingVerb.map { "\($0.label): \(thing.title)?" } ?? "",
            isPresented: Binding(get: { confirmingVerb != nil },
                                 set: { if !$0 { confirmingVerb = nil } }),
            titleVisibility: .visible
        ) {
            if let verb = confirmingVerb {
                Button(verb.label) { Task { await perform(verb) } }
                Button("Cancel", role: .cancel) { confirmingVerb = nil }
            }
        }
        // Name this counterparty — the name rides every future transfer with it.
        .alert("Name this address",
               isPresented: Binding(get: { counterpartyTarget != nil },
                                    set: { if !$0 { counterpartyTarget = nil } })) {
            TextField("Name (e.g. Mom)", text: $counterpartyDraft)
            Button("Save") { nameCounterparty() }
            Button("Cancel", role: .cancel) { counterpartyTarget = nil }
        } message: {
            Text("It rides every future transfer. Blank clears it.")
        }
        // Name anyone else a thing is from (prd §916 amendment — user: "any
        // address or whatever a person should be able to save easily"): the
        // sender, the poster, the login. Saved into `ContactBook`, and the
        // Addresses list shows them under that name from then on.
        .alert("Name this address",
               isPresented: Binding(get: { identityTarget != nil },
                                    set: { if !$0 { identityTarget = nil } })) {
            TextField("Name (e.g. Mom)", text: $counterpartyDraft)
            Button("Save") {
                if let identity = identityTarget {
                    ContactBook.shared.save(identity, name: counterpartyDraft)
                    ContactIndexSources.rebuild(context: modelContext)
                }
                identityTarget = nil
            }
            Button("Cancel", role: .cancel) { identityTarget = nil }
        } message: {
            Text("It names them everywhere in the app. Blank removes the name.")
        }
        // Walking the thread in-app (2026-07-16) — the parent this post
        // answers, or a reply under it. A read: no consent gate, the standing
        // rule for the thread section it grew out of.
        .sheet(item: $walkingTo) { card in
            SocialPostSheet(post: card, source: thing.source)
        }
        // Whoever is behind a tapped face — a person theirs to watch from
        // here, or the address card for a wallet (prd §369 amendment).
        .sheet(item: $faceTarget) { target in
            switch target {
            case .person(let profile): SocialProfileCard(profile: profile)
            case .address(let entry):  AddressCard(entry: entry)
            case .remind(_, let text):
                NoteRemindTray(note: thing, item: text)
            case .followChannel(let seat, let name):
                FollowTrackTray(room: .media, seat: seat, initialQuery: name)
                    .environment(chrome)
                    .environment(bridges)
                    .environment(\.modelContext, modelContext)
            case .followSite(let host):
                ReadingFindSheet(initialQuery: host)
                    .environment(chrome)
                    .environment(bridges)
                    .environment(\.modelContext, modelContext)
            case .track(let name):
                SubscriptionAddTray(prefill: .init(name: name, site: nil))
                    // A Catalyst sheet does not inherit the presenter's
                    // environment (prd §872).
                    .environment(chrome)
                    .environment(bridges)
                    .environment(\.modelContext, modelContext)
            }
        }
        // Walking a vault's own wikilink graph (2026-07-28) — a plain
        // re-presentation of this same sheet over the linked note.
        .sheet(item: $walkingToNote) { note in
            // `walkingToScope` rather than `walk`: the neighbour doors set it
            // to this sheet's own scope so a walk keeps following the list two
            // doors in, and every OTHER walk in this file (a quote, a parent,
            // a vault wikilink, an "on this date" row) leaves it `.none`
            // because those leave the list — a door onto a row the list does
            // not hold is exactly what §645 pass 3 forbids.
            ThingSheetView(thing: note.thing, walk: walkingToScope)
        }
        // The screenshot at full size (2026-08-02). A cover, not a sheet, for
        // two reasons: the picture IS the screen here and a detented sheet
        // would letterbox the one surface whose whole job is showing every
        // pixel — and it keeps the standing one-screen-one-`.sheet` rule
        // intact. That rule is about SIBLINGS of the same modifier (the feed's
        // five `.sheet`s, paid for three times); this is the only
        // `fullScreenCover` on the view, so it adds no fourth `.sheet` to the
        // three above it.
        //
        // Reads the model's values HERE and hands the viewer plain ones, so a
        // heal deleting this row while the viewer is open can't trap on a dead
        // reference (`ThingRowKeying.swift`, corollary 5).
        .fullScreenCover(isPresented: $zoomingPhoto) {
            if thing.isLive {
                PhotoViewer(assetRef: thing.sourceRef,
                            stored: thing.previewImageData,
                            title: thing.title)
            }
        }
        // Translate: the system sheet, over the thing's own words. Unavailable
        // on Mac Catalyst (no Translation UI presentation there).
        #if !targetEnvironment(macCatalyst)
        .translationPresentation(isPresented: $showTranslate, text: translateText)
        #endif
        }
    }

    /// Stores (or clears) the person's label for the counterparty address, then
    /// rewrites every already-landed transfer that carries it — so naming an
    /// address updates your whole history with it, not just what comes next.
    /// (Only transfers that stored the counterparty hex can be rewritten — ones
    /// landed before that field existed are left as they are.)
    private func nameCounterparty() {
        guard let address = counterpartyTarget else { return }
        counterpartyTarget = nil
        // Through the BOOK now (prd §169) — naming a counterparty adds it to
        // your address book, so the name survives, gets a card, and can be
        // upgraded to a watch later. Kind detection follows, keyless.
        AddressBook.shared.setName(counterpartyDraft, for: address)
        Task { @MainActor in await AddressKind.detect(address) }
        // The display name after the change: the user's label, else whatever
        // else resolves it (a known contract, a watched handle), else nil —
        // clearing a label reverts the historical titles to that.
        CounterpartyRetitle.applyCurrentName(for: address, in: modelContext)
        DSHaptic.success()
    }

    // The counterparty rewrite moved to `Model/CounterpartyRetitle.swift`
    // (2026-08-01). It was private here, so it ran for this one naming door
    // and not for the address card, the book's omnibox, or a star — same act,
    // same address, different outcome depending on which door you used.

    // MARK: - Title (a post's words ARE the title, 2026-07-16)

    /// Everything else leads with a headline. A post leads with the POST: its
    /// full text, in the title's slot, because a cast IS its words — and the
    /// 80-character title is a row's clamp, not the thing itself. Rendering the
    /// clamp here and the full text below would stutter; rendering only the
    /// clamp is what lost the words in the first place.
    ///
    /// The size follows the length, the way every social client's does — in
    /// THREE steps since 2026-08-02, not two. A one-liner gets the full
    /// display size and the drama that comes with it; a tweet-length post gets
    /// the pull-quote rung; and past `readingLength` the words leave the
    /// display tier altogether for `reading17` — SF Pro Text, REGULAR weight,
    /// open leading.
    ///
    /// That third step is the fix. `heading24` had no upper bound, so a
    /// 900-character cast was set end to end in bold SF Rounded — a title face
    /// doing a paragraph's job, which flattens word shapes and reads as a wall
    /// rather than as writing. Dropping the weight and the rounded face at
    /// paragraph length is the rule Typography already states (rounded/bold is
    /// the display tier, running text is SF Pro Text), and the hierarchy is
    /// still carried by size alone — no other trick (design law).
    ///
    /// Reading rungs also cap their MEASURE. At phone width the sheet's own
    /// padding gives ~45–55 characters a line, which is the band you want; on
    /// iPad and Catalyst the sheet is far wider, and a paragraph run full
    /// width makes the eye lose its place returning to each next line.
    @ViewBuilder private var titleBlock: some View {
        // The title's seam (prd §915): the object is the head, and what the
        // bridge said after ` — ` — the game, the board, the verb — is one
        // quiet line under it, never inside the head with a dash.
        let seam = TitleSeam.split(thing.title)
        let words = isSocialPost ? postWords : seam.name
        let rung = Self.titleRung(for: words)
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Group {
                if isSocialPost {
                    Text(linkedWords(words))
                } else {
                    Text(seam.name)
                }
            }
            .dsText(rung.style)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: rung == .reading ? Self.readingMeasure : .infinity,
                   alignment: .leading)
            // The words are what people copy a phrase out of — every rung.
            .textSelection(.enabled)
            if !isSocialPost, let line = seam.line {
                Text(verbatim: line)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// THE HEAD RUNG IS FOR A NAME (2026-09-06, prd §630 amendment — the
    /// head-consistency half of the type-ramp item).
    ///
    /// The ramp's own definition of `heading40`: "a head is one or two words
    /// and tight leading is what makes two lines read as one object". Every
    /// non-social thing was set at that rung regardless of length, so a
    /// stream's title ("nova live — Software and Game Development") opened
    /// as four lines of 40pt heavy that pushed its own picture under the
    /// fold — a shout where a title was wanted — while a post of the same
    /// length went through a length rule of its own and a vault note through
    /// a third. One ladder now, by SHAPE rather than by kind: a name is a
    /// head, a sentence is a title, a paragraph reads. The framed photo keeps
    /// `heading24` outright because there the picture is the head.
    ///
    /// 32 characters is two lines at the head rung on a phone — the most a
    /// head is allowed to be by its own definition. `readingLength` is the
    /// existing paragraph threshold, shared so the detent and the rung agree.
    enum TitleRung: Equatable {
        case head, title, reading
        var style: DSTextStyle {
            switch self {
            case .head: return .heading40
            case .title: return .heading24
            case .reading: return .reading17
            }
        }
    }
    static let headLength = 32
    static func titleRung(for text: String) -> TitleRung {
        let n = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if n <= headLength { return .head }
        if n <= readingLength { return .title }
        return .reading
    }

    /// Past this many characters a post is a paragraph, not a statement, and
    /// is set in `reading17` instead of the display tier. 280 is deliberate:
    /// it's the same length `init` uses to decide the sheet opens full-height,
    /// so a post tall enough to need the whole sheet is exactly the post that
    /// gets read-type — one threshold, two consequences that agree.
    static let readingLength = 280
    /// The reading measure. Wide enough to keep the phone case unchanged
    /// (nothing on a phone reaches it), narrow enough that a paragraph on iPad
    /// or Catalyst stays inside the ~45–75 characters a line that running text
    /// wants.
    private static let readingMeasure: CGFloat = 560

    /// The post's own words — the full text when the record carries it, else
    /// the title (posts landed before `postText` existed, until a refresh heals
    /// them). Never a permalink.
    /// One definition (prd §363) — `SocialSheetSource.words` is what the
    /// shape decision itself measured, so the sheet can never set as a hero
    /// something the classifier didn't count as words.
    private var postWords: String {
        SocialSheetSource.words(for: thing)
    }

    /// The post's words with their URLs live (2026-08-02). A post that says
    /// "read this: example.com/thing" was printing that address as inert
    /// characters — the one door the writer actually put in their own sentence,
    /// and the sheet's "Open" verb can only ever offer the FIRST link it finds,
    /// so a post with two carried one and swallowed the other.
    ///
    /// Only in the SHEET, never in a feed row: a row is a read with one
    /// gesture (ruling 2026-07-16), so a second tap target inside it would be
    /// the same half-open trap the sibling-`.sheet` bug was.
    ///
    /// Colour is the whole signal — no underline, which would be a hairline
    /// through running text. `openURL` comes from the environment, so an inline
    /// link inherits the same "leaving is a verb" wrapper Composer installs for
    /// the agent's Stack that every `.openURL` verb here already gets.
    ///
    /// The body moved to `ProseLinks` (2026-08-12) when the same treatment
    /// reached every other prose surface — one definition, so a post's links
    /// and a note's links can't drift apart.
    private func linkedWords(_ words: String) -> AttributedString {
        ProseLinks.rendered(words)
    }

    /// The post this one answers, above the words, where every client puts it.
    ///
    /// A CARD since prd §363, not the label it was: "Replying to @alice" names
    /// a person and withholds the sentence, so a reply read as a non sequitur
    /// unless you already remembered the conversation — and the parent's own
    /// words were on the record the whole time. A tap still walks into it.
    private func replyingToRow(_ parent: SocialCard) -> some View {
        ReplyingToCard(parent: parent, source: thing.source) { walkingTo = parent }
    }

    // MARK: - Eyebrow (source icon · kind · age)

    private var eyebrow: some View {
        HStack(spacing: DS.Space.s2) {
            // A social post leads with the PERSON who said it — their face and
            // handle, not the network's mark (the hue wash already names the
            // network). The feed rows lead with faces; the sheet should too
            // (2026-07-14). Everything else keeps the source mark + kind tag.
            // Every social shape EXCEPT a transcript: a conversation's
            // `authorHandle` is the thread's own name (Instagram's DM import
            // stamps the title there), so wearing it as "@Chat with Sarah"
            // would introduce a conversation as a person. A transcript keeps
            // the source line it always had.
            if SocialSheetSource.eyebrowLeadsWithPerson(thing, shape: socialShape) {
                // The face, and whether it is a DOOR (prd §363). It leads with
                // the person on every social source now, not just the three
                // with a profile API — an archived tweet introducing itself as
                // "Note · 3y ago" was the sheet forgetting who wrote it. Where
                // there is no avatar (an X archive stamps a handle and no
                // picture) the source's own mark stands in, so the line is
                // never a naked handle.
                socialFace
                // WHY this post is here rides the sentence when there's a
                // reason worth stating ("@dwr · in /design · 2h ago") — a
                // liked cast, a channel cast, and your own post used to read
                // identically (2026-07-16).
                Text(eyebrowLine)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            } else {
                // The source's own mark names the wash above it — the 6px dot
                // died with the hue ruling (2026-07-10). BridgeIcon falls back
                // to the glyph-on-hue circle for sources without a bundled
                // asset, so the seat is never empty.
                //
                // A door, not just a label (2026-07-21): tapping it leaves
                // for that source's own feed, the inverse of the row you
                // drilled in from — and inside the agent's pushed sheet
                // (which has no chrome of its own) it's the only way back to
                // "where does this live" that isn't the app-opening "Open in".
                //
                // `dismiss()` then `openURL(...)` is deliberate, not
                // redundant: on a plain `.sheet` presentation, `dismiss()`
                // does the whole job (openURL just re-routes the app
                // underneath). Pushed inside the agent's own Stack,
                // Composer.swift wraps `openURL` to ALSO call `onLowerAgent()`
                // — the same "leaving is a verb" contract every other
                // `.openURL` verb in this sheet already gets (ruling 9), so
                // the eyebrow correctly drops the whole agent and lands on
                // the source feed, not just pops the pushed thing-view.
                // Verified live via `-agentThingProbe` (2026-07-21).
                // …but only when there IS a room to leave for. "You" keeps its
                // stamp and lost its room (ruling 2026-08-02,
                // `Corpus.chiplessSources`), and a door onto a room that no
                // longer exists is precisely the dead control the honesty law
                // bans — so for those sources the same line renders as a plain
                // label, mark and all.
                if Corpus.earnsRoom(thing.source) {
                    Button {
                        DSHaptic.tap()
                        openSourceRoom()
                    } label: {
                        sourceLine
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                } else {
                    sourceLine
                }
            }
        }
    }

    /// The author's face, a door where a door can lead somewhere (prd §363).
    ///
    /// Split out of the eyebrow because it now has four combinations rather
    /// than one — avatar or mark, door or label — and spelling them inline
    /// made the eyebrow's own `if` unreadable.
    @ViewBuilder private var socialFace: some View {
        if facesAreDoors {
            // The face is a door to the person (2026-07-16) — tap it and you
            // can watch them, wherever you met them.
            Button {
                openAuthorProfile()
            } label: {
                faceMark
            }
            .buttonStyle(PressSpring())
            .dsHover()
            // A bare face: the only control here with no word in it.
            .accessibilityLabel(Text("Open profile"))
            .dsTooltip(String(localized: "Open profile"))
        } else {
            faceMark
        }
    }

    /// The author's profile card — the eyebrow face's door, and the post
    /// head's (prd §884).
    private func openAuthorProfile() {
        faceTarget = .person(SocialProfile(
            source: thing.source, handle: thing.authorHandle ?? "",
            displayName: nil, bio: nil, avatarURL: thing.authorAvatarURL))
    }

    @ViewBuilder private var faceMark: some View {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
            RemoteThumb(urlString: avatar, size: DS.Face.badge,
                        fallback: thing.source, circular: true)
                .coinFlip(trigger: thing.id)
        } else {
            BridgeIcon(name: thing.source, size: DS.Face.badge, circular: true)
                .coinFlip(trigger: thing.id)
        }
    }

    /// The eyebrow's mark-and-words, shared by the door and the plain-label
    /// branch above so the two can never drift on what the line SAYS — only on
    /// whether it goes anywhere.
    private var sourceLine: some View {
        HStack(spacing: DS.Space.s2) {
            BridgeIcon(name: thing.source, size: DS.Face.badge, circular: true)
                // The mark coin-flips as the sheet opens (delight, 2026-07-12).
                .coinFlip(trigger: thing.id)
            // A Privy app row is an app wallet, not an "Event" (prd §803f).
            Text(thing.sourceRef?.hasPrefix(PrivyHomeFeed.refPrefix) == true
                 ? "App wallet · made \(shortTime(thing.capturedAt)) ago"
                 : "\(thing.kind.typeTag) · \(shortTime(thing.capturedAt)) ago")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    /// `thing.source` as a URL path component — a source name can carry
    /// spaces ("Apple Music", "iCloud Mail"), so the eyebrow's door needs
    /// this before handing it to `casberi://feed/source/…`.
    /// The word under a money head's name (prd §887): "Card" for a card spend,
    /// "Dust" for a Bitcoin receipt too small to be a payment (§1097), else the
    /// kind's own tag.
    private var moneyKindWord: String {
        if thing.tags.contains("Card") { return String(localized: "Card") }
        if thing.tags.contains(BitcoinBridge.dustTag) { return String(localized: "Dust") }
        return thing.kind.typeTag
    }

    /// When a moment is (prd §892): an event's start, a reminder's due.
    private var momentStart: Date? {
        thing.kind == .reminder ? thing.dueAt : thing.capturedAt
    }

    /// "Reminders · Lisbon trip", "Health · Workout" — where it is from and
    /// what it is filed under, the kind not said again (prd §1190).
    private var momentSourceLine: String {
        let workout = thing.factList.contains { $0.action == .metric }
        let tag = workout ? String(localized: "Workout")
            : thing.tags.first(where: { $0 != thing.kind.typeTag && $0 != "Workout" })
        return [thing.source, tag].compactMap { $0 }.joined(separator: " · ")
    }

    /// Fit the sheet to its content (prd §886). It follows the content while
    /// the person has not moved it — a body that lands, a row that arrives —
    /// and never overrides a drag to full height. A change under 8pt (a line
    /// re-wrapping) does not move the sheet.
    private func fitSheet(to height: CGFloat) {
        guard onBack == nil, !inlineRest, height > 0 else { return }
        let fit = height.rounded(.up)
        if let old = fittedHeight, abs(old - fit) < 8 { return }
        let stillFitted = fittedHeight.map { detent == .height($0) } ?? true
        fittedHeight = fit
        if stillFitted { detent = .height(fit) }
    }

    /// Leave for this thing's source room — the eyebrow's door, and the
    /// article head's publication line (prd §882).
    private func openSourceRoom() {
        dismissWhenSettled {
            if let url = URL(string: "casberi://feed/source/\(sourcePathComponent)") {
                openURL(url)
            }
        }
    }

    private var sourcePathComponent: String {
        thing.source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? thing.source
    }

    /// A `dismiss()` fired while the sheet's own zoom-in transition is still
    /// running races `UIPresentationController` the same way the delete-guard
    /// above does, and trips the same `_UIZoomTransitionController` nil-
    /// unwrap (live TestFlight crash, build 167: the eyebrow's "leave for
    /// source feed" button below, tapped fast enough to still be inside the
    /// present transition). Most taps land well after the transition has
    /// settled and dismiss immediately, same as before; only a fast tap pays
    /// the wait, and only for the remainder of the 500ms window.
    private func dismissWhenSettled(then after: @escaping () -> Void = {}) {
        let remaining = 0.5 - Date().timeIntervalSince(presentedAt)
        guard remaining > 0 else {
            dismiss()
            after()
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            dismiss()
            after()
        }
    }

    /// The social anatomy this thing wears, or nil for none (prd §363).
    ///
    /// This REPLACED `isSocialPost`, which asked `SocialThread.isSocial` — a
    /// set of three source names — and so refused the treatment to X,
    /// Instagram, TikTok and Snapchat, every one of which stamps the same
    /// fields. `SocialSheet.shape` asks about the RECORD instead.
    private var socialShape: SocialSheet.Shape? {
        SocialSheetSource.shape(for: thing)
    }

    /// A thing whose words are the hero. The title slot, the reading measure
    /// and the content route all key off this.
    private var isSocialPost: Bool { socialShape == .post }

    /// A thing whose body is a social one — pictures and the card for the post
    /// (prd §704). A NOTICE joins a post here and DELIBERATELY NOT in
    /// `isSocialPost` above: its hero is the notice sentence on `title`, not
    /// the post's words, which is the whole difference between the two shapes.
    private var drawsSocialBody: Bool { socialShape == .post || socialShape == .notice }

    // MARK: - The note anatomies (prd §366)

    /// Which of the three note anatomies this thing wears, or nil for none.
    /// A DATA test — does the record quote somebody else's work, and is its
    /// title a name the person gave it or a line we cut out of its own body.
    private var noteShape: NoteSheet.Shape? {
        NoteSheetSource.shape(for: thing)
    }

    /// Which Walletbeat anatomy this thing draws (prd §419 amendment). Three genuinely
    /// different records land in that room — a standing review, an event, and somebody
    /// changing their mind — and the generic link sheet served all three as a title and
    /// a URL.
    private var walletbeatShape: WalletbeatSheet.Shape? {
        WalletbeatSheetSource.shape(for: thing)
    }

    /// Which L2BEAT anatomy this thing draws (prd §428). The same three records as
    /// Walletbeat's room one layer down — a standing assessment, an event, and somebody
    /// changing their reading — and the generic link sheet served all three alike.
    private var l2beatShape: L2beatSheet.Shape? {
        L2beatSheetSource.shape(for: thing)
    }

    /// The L2BEAT head each shape leads with, in place of the title block.
    @ViewBuilder
    private func l2beatHead(_ shape: L2beatSheet.Shape) -> some View {
        switch shape {
        case .chain:
            // The risk card itself, not a link to a website.
            if let chainID = L2beatWatch.chainID(from: thing) {
                L2beatRiskCard(chainID: chainID, showsHeader: false)
            }
        case .milestone:
            // In the room's frame (prd §1191): the chain is the title.
            let facts = L2beatMilestoneBook.facts(ref: thing.sourceRef)
            newsFrame(title: facts?.projectName ?? thing.source,
                      label: facts?.kind.label ?? thing.source,
                      urgent: thing.tags.contains(L2beatNewsParse.incidentTag),
                      headline: thing.title) {
                L2beatMilestoneHead(thing: thing, inFrame: true)
            }
        case .revision:
            if let (revision, project, risk) = L2beatSheetSource.revisionSubject(for: thing) {
                let head = L2beatRevisionHead(thing: thing, revision: revision,
                                              project: project, risk: risk, inFrame: true)
                newsFrame(title: project?.name ?? revision.projectID, label: head.label,
                          urgent: false, headline: head.headline) { head }
            }
        }
    }

    /// Review news in the room's frame (prd §1191): the chain or wallet is the
    /// title, the box what happened, the tiles, then the reviewer's detail.
    @ViewBuilder
    private func newsFrame<Detail: View>(title: String, label: String, urgent: Bool,
                                         headline: String,
                                         @ViewBuilder detail: () -> Detail) -> some View {
        DSRoomTitleRow(title: title)
            .padding(.horizontal, DSRoomChassis.inset)
        ReviewNewsBox(label: label, urgent: urgent,
                      meta: FeedScreen.dayWord(thing.capturedAt), headline: headline)
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil)
            .padding(.top, DSRoomChassis.leadGap)
        dialResult
        detail()
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s6)
    }

    /// The Walletbeat head each shape leads with, in place of the title block.
    @ViewBuilder
    private func walletbeatHead(_ shape: WalletbeatSheet.Shape) -> some View {
        switch shape {
        case .wallet:
            // The report card itself, not a link to a website. Before this the room's own
            // rows opened a generic sheet while the feature's primary surface was
            // reachable only from the setup screen and the directory.
            if let walletID = WalletbeatWatch.walletID(from: thing) {
                WalletbeatReportCard(walletID: walletID, showsHeader: false)
            }
        case .incident:
            // In the room's frame (prd §1191): the wallet is the title.
            let facts = WalletbeatIncidentBook.facts(ref: thing.sourceRef)
            let wallet = facts?.wallets.first.flatMap { id in
                WalletbeatDirectory.wallets.first { $0.id == id }?.name
            }
            newsFrame(title: wallet ?? thing.source,
                      label: facts?.status.label ?? thing.source,
                      urgent: thing.tags.contains(WalletbeatNewsParse.openTag),
                      headline: thing.title) {
                WalletbeatIncidentHead(thing: thing, inFrame: true)
            }
        case .revision:
            if let (revision, attribute) = WalletbeatSheetSource.revisionAttribute(for: thing) {
                let name = WalletbeatDirectory.wallets.first { $0.id == revision.walletID }?.name
                    ?? revision.walletID
                newsFrame(title: name, label: String(localized: "Walletbeat revised its review"),
                          urgent: false, headline: attribute?.name ?? thing.title) {
                    WalletbeatRevisionHead(thing: thing, revision: revision,
                                           attribute: attribute, inFrame: true)
                }
            }
        }
    }

    /// The head each shape leads with, in place of the title block.
    @ViewBuilder
    private func noteHead(_ shape: NoteSheet.Shape) -> some View {
        // THE NOTE HEADS (prd §893) — the shared head (`SheetPartyHead`, §892):
        // who or what it is from, the pink day, what it is; then the words,
        // with the dial under the head as an article's is (§882), because a
        // note, like an article, is read for pages.
        let tags = NoteSheetSource.tags(for: thing)
        VStack(alignment: .leading, spacing: 0) {
            switch shape {
            case .entry where !pagedNote && thing.kind != .voice && !NoteLock.isLocked(thing):
                // A JOURNAL ENTRY IN THE ROOM'S FRAME (prd §1191): its first
                // line is the title, the box its day, the time (and the place
                // and weather where the journal kept them) and its picture,
                // then the tiles, then the words after the first line.
                let body = tickedBody ?? NoteSheetSource.prose(for: thing).text
                let split = Self.keptTitleLine(Self.entrySplit(body), kept: false)
                DSRoomTitleRow(title: split.first ?? TitleSeam.name(thing.title))
                    .padding(.horizontal, DSRoomChassis.inset)
                JournalEntryBox(thing: thing, sameDay: sameDayThings.count) { zoomingPhoto = true }
                    .dsRoomBox()
                    .padding(.top, DS.Space.s3)
                noteDial
                if !split.rest.isEmpty {
                    noteProse(text: split.rest)
                        .padding(.horizontal, DSRoomChassis.leadInset)
                        .padding(.top, DS.Space.s6)
                }
            case .entry:
                // The entry's own photograph fills the lead's well (§882's
                // picture, the article's); an entry without one starts at its
                // head. The dateline is gone: the day is the pink word.
                if thing.previewImageData != nil {
                    NoteEntryPhoto(thing: thing) { zoomingPhoto = true }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.bottom, DS.Space.s6)
                }
                SheetPartyHead(name: thing.source, day: thing.capturedAt, line: entryLine,
                               onFace: Corpus.earnsRoom(thing.source) ? openSourceRoom : nil) {
                    BridgeIcon(name: thing.source, size: DS.Face.shelf, circular: true,
                               symbol: BridgeIcon.noteSymbol(for: thing))
                }
                // Where the note is filed, as a door (prd §983; §736: a row
                // that names a place is a button).
                if pagedNote, !NoteLock.isLocked(thing) {
                    // A highlight names the page it came from, as a door
                    // (prd §1020; §736).
                    if let origin = highlightOrigin {
                        highlightOriginLine(origin)
                            .padding(.horizontal, DSRoomChassis.leadInset)
                            .padding(.top, DS.Space.s2)
                    }
                    noteFolderLine
                        .padding(.horizontal, DSRoomChassis.leadInset)
                        .padding(.top, DS.Space.s2)
                }
                if NoteLock.isLocked(thing) {
                    lockedNote
                } else if thing.kind != .voice {
                    let body = tickedBody ?? NoteSheetSource.prose(for: thing).text
                    // A list's first item stays an item (prd §982): lifted
                    // into the title it would lose its circle and its tick.
                    let opening = body.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").first ?? ""
                    let listFirst = NoteSheetSource.isKeptNote(thing)
                        && NoteSheet.taskLine(opening) != nil
                    let split: (first: String?, rest: String) = listFirst
                        ? (nil, body.trimmingCharacters(in: .whitespacesAndNewlines))
                        : Self.keptTitleLine(Self.entrySplit(body),
                                             kept: NoteSheetSource.isKeptNote(thing))
                    // An entry's first line IS its title (why it had none:
                    // it would print twice) — so it leads, and the prose
                    // continues from the line after it.
                    if let first = split.first {
                        Text(first)
                            .dsText(Self.titleRung(for: first).style)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, DSRoomChassis.leadInset)
                            .padding(.top, DS.Space.s4)
                    }
                    // A note of yours has no dial (prd §983): its three keys
                    // stand at the sheet's foot (`keptNoteBand`), and the
                    // words start under the title.
                    if !pagedNote { noteDial }
                    if !split.rest.isEmpty {
                        noteProse(text: split.rest)
                            .padding(.horizontal, DSRoomChassis.leadInset)
                            .padding(.top, DS.Space.s6)
                    }
                } else {
                    noteDial
                }
            case .note:
                // A VAULT NOTE IN THE ROOM'S FRAME (prd §1191): its name is the
                // title, the box where it lives, when it was edited and its
                // tags, then the tiles and the words.
                DSRoomTitleRow(title: TitleSeam.name(thing.title))
                    .padding(.horizontal, DSRoomChassis.inset)
                VaultNoteBox(thing: thing, tags: tags)
                    .dsRoomBox()
                    .padding(.top, DS.Space.s3)
                noteDial
                // A vault note's body opens with its own title line; the head
                // just set it, so the prose starts after it (prd §893).
                noteProse(text: Self.droppingTitleLine(NoteSheetSource.prose(for: thing).text,
                                                       title: thing.title))
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s6)
            case .passage:
                // The BOOK is who it is from; the passage is the headline.
                // The locator it drew ("Marked while reading Piranesi —
                // Susanna Clarke.") restated the book where a page belonged.
                let cite = Self.citationParts(NoteSheetSource.citation(for: thing) ?? thing.source)
                // The importer's locator ("page 42") rides the line.
                let locator = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // A PASSAGE IN THE ROOM'S FRAME (prd §1191): the book is the
                // title, the passage the box, who wrote it and where under it.
                let passage = NoteSheetSource.passage(for: thing)
                DSRoomTitleRow(title: cite.work)
                    .padding(.horizontal, DSRoomChassis.inset)
                PassageBox(passage: passage, author: cite.author,
                           line: [cite.author, thing.source,
                                  locator.count <= 24 && !locator.isEmpty ? locator : nil,
                                  FeedScreen.dayWord(thing.capturedAt)]
                               .compactMap { $0 }
                               .joined(separator: " · "))
                    .dsRoomBox()
                    .padding(.top, DS.Space.s3)
                noteDial
                if PassageBox.cuts(passage) {
                    Text("\u{201C}\(passage)\u{201D}")
                        .dsText(.reading17)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, DSRoomChassis.leadInset)
                        .padding(.top, DS.Space.s6)
                }
            }
            // A vault note's tags stand in its box (prd §1191).
            if !tags.isEmpty, shape != .note {
                NoteTagRow(tags: tags)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A LOCKED note (prd §982): the lock and one door to open it, or — once
    /// opened — the words, read-only, and Remove lock. The sealed record says
    /// "Locked note" and holds nothing else, so there is nothing here to hide:
    /// the words exist on screen only after the device owner opened them.
    @ViewBuilder private var lockedNote: some View {
        if let opened = openedLock {
            if let picture = opened.picture, let image = UIImage(data: picture) {
                Color.clear
                    .frame(height: DSRoomChassis.sheetArtHeight)
                    .frame(maxWidth: .infinity)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
                    .accessibilityLabel(Text("Photo on this note"))
            }
            // The note's own title leads, as it does unlocked; a list's
            // first item stays an item.
            let listFirst = NoteSheet.taskLine(opened.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? "") != nil
            let split: (first: String?, rest: String) = listFirst
                ? (nil, opened.content) : Self.entrySplit(opened.content)
            if let first = split.first {
                Text(first)
                    .dsText(Self.titleRung(for: first).style)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s4)
            }
            if !split.rest.isEmpty {
                NoteProse(text: split.rest, tasks: true)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s6)
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Image(systemName: "lock.fill")
                    .dsGlyph(.feature, weight: .regular)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
                DSFootnote(lockFailure == .noKey
                    ? Text("This device doesn't have the key yet. It arrives with iCloud Keychain")
                    : Text("Sealed with a key in your iCloud Keychain"))
            }
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s6)
        }
    }

    /// A written note of yours is a PAGE (prd §983): no dial, the words
    /// under the title, and three keys at the sheet's foot. Copy and
    /// Translate are the system's, on selected words; Pin, Move and Delete
    /// are the room's long press. A voice note keeps its dial and player.
    private var pagedNote: Bool {
        NoteSheetSource.isKeptNote(thing) && thing.kind == .note
    }

    /// The note's three keys (prd §983) — the composer's foot: Share and Lock
    /// as discs, Edit as the wide key. Locked, the one key opens it (Face ID,
    /// Touch ID or the passcode), and once open it is Remove lock; nothing
    /// sealed is shared or edited.
    @ViewBuilder private var keptNoteBand: some View {
        HStack(spacing: DS.Space.s3) {
            if NoteLock.isLocked(thing) {
                if let opened = openedLock {
                    AgentWideKey(title: String(localized: "Remove lock"), glyph: "lock.open") {
                        DSHaptic.tap()
                        NoteLock.unlock(thing, with: opened, context: modelContext)
                        openedLock = nil
                        chrome.flash(String(localized: "Lock removed"))
                    }
                } else {
                    AgentWideKey(title: NoteLock.unlockWord, glyph: "lock.open") {
                        DSHaptic.tap()
                        Task { @MainActor in
                            switch await NoteLock.open(thing) {
                            case .success(let sealed):
                                lockFailure = nil
                                withAnimation(DS.Motion.standard) { openedLock = sealed }
                            case .failure(let why):
                                lockFailure = why
                                if why != .auth { DSHaptic.failure() }
                            }
                        }
                    }
                }
            } else {
                if Highlight.isHighlight(thing) {
                    // A highlight shares as the quote card (prd §1020), the
                    // dial's tray on the note's own key.
                    Button {
                        DSHaptic.tap()
                        sharingHighlight = true
                    } label: {
                        bandDisc("square.and.arrow.up")
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel(Text("Share the highlight"))
                    .sheet(isPresented: $sharingHighlight) { ShareTray(thing: thing) }
                } else {
                    ThingShareLink(thing: thing) {
                        bandDisc("square.and.arrow.up")
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel(Text("Share the note"))
                }
                Button {
                    chrome.lockNote(thing, context: modelContext)
                } label: {
                    bandDisc("lock")
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Lock note"))
                AgentWideKey(title: String(localized: "Edit"), glyph: "pencil") {
                    DSHaptic.tap()
                    let id = thing.id
                    dismissWhenSettled { chrome.editNote(id) }
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s4)
        .background(DS.inkGround.ignoresSafeArea(edges: .bottom))
    }

    /// One of the band's discs: the composer's disc anatomy (prd §973).
    private func bandDisc(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .dsGlyph(.feature, weight: .regular)
            .foregroundStyle(DS.textPrimary)
            .frame(width: AgentDestinationKeys.side, height: AgentDestinationKeys.side)
            .background(DS.surfaceRaised, in: Circle())
            .dsTapTarget(Circle())
            .dsHover()
    }

    /// Where the note is filed — "in Work" — and the door to move it (prd
    /// §983). The room's long press files too; this is the same move from
    /// inside the note, because a place that is named is a button (§736).
    /// Nothing filed and no folder yet draws nothing: there would be nowhere
    /// to move it.
    @ViewBuilder private var noteFolderLine: some View {
        let current = thing.folder
        let names = NoteFolderName.list(stored: NoteFolderStore.shared.names, filed: [current])
        if current != nil || !names.isEmpty {
            Menu {
                ForEach(names, id: \.self) { name in
                    Button {
                        file(in: name)
                    } label: {
                        if current.map(NoteFolderName.key) == NoteFolderName.key(name) {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: name)
                        }
                    }
                }
                if current != nil {
                    Button {
                        file(in: nil)
                    } label: {
                        Label("Remove from folder", systemImage: "folder.badge.minus")
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "folder")
                        .dsGlyph(.caption, weight: .regular)
                    Text(current.map { String(localized: "in \($0)") }
                         ?? String(localized: "Add to a folder"))
                        .dsText(.body17)
                    Image(systemName: "chevron.right")
                        .dsGlyph(.tick, weight: .semibold)
                }
                .foregroundStyle(DS.tint)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(current.map { String(localized: "Folder: \($0). Move the note") }
                                     ?? String(localized: "Add the note to a folder")))
        }
    }

    private func file(in folder: String?) {
        guard thing.isLive else { return }
        Pinboard.file(thing, in: folder)
        modelContext.saveHonestly()
        DSHaptic.tap()
        chrome.flash(folder.map { String(localized: "Moved to \($0)") }
                     ?? String(localized: "Removed from folder"))
    }

    /// The dial, under a note's head (prd §893).
    @ViewBuilder private var noteDial: some View {
        VerbDial(thing: thing, verbs: sheetVerbs,
                 onVerb: runVerb, onName: nil, keep: sheetKeep)
            .padding(.top, DS.Space.s6)
        dialResult
    }

    /// "Journal · written 9:00 PM" — what it is and when in the day (§893).
    private var entryLine: String {
        // A note you wrote is a Note, not a Journal entry (prd §981).
        let what = thing.kind == .voice ? String(localized: "Voice note")
            : Highlight.isHighlight(thing) ? String(localized: "Highlight")
            : thing.source == NoteSheetSource.keptSource ? String(localized: "Note")
            : String(localized: "Journal")
        let clock = thing.capturedAt.formatted(date: .omitted, time: .shortened)
        let act = thing.kind == .voice ? String(localized: "recorded \(clock)")
            : Highlight.isHighlight(thing) ? String(localized: "kept \(clock)")
            : String(localized: "written \(clock)")
        return "\(what) · \(act)"
    }

    // MARK: - Highlights (prd §1020)

    /// What Keep does on this page: nil for a note of yours (its words are
    /// already yours) and for a sealed note; otherwise a highlight is kept
    /// and the page's own shelf shows it at once.
    private var keepPassage: ((String) -> Void)? {
        guard !NoteSheetSource.isKeptNote(thing), !NoteLock.isLocked(thing) else { return nil }
        return { passage in keepHighlight(passage) }
    }

    private func keepHighlight(_ passage: String) {
        guard Highlight.keep(passage, from: thing, link: ShareTargetMemo.url(for: thing),
                             context: modelContext) != nil else { return }
        chrome.flash(String(localized: "Kept in Notes"), tone: .success)
        pointingAt = ThingLinksSource.ties(for: thing, context: modelContext)
    }

    /// "from <the page> ›" — the door back to what the passage came from,
    /// drawn as the folder line is, one row above it.
    private func highlightOriginLine(_ origin: Thing) -> some View {
        Button {
            DSHaptic.tap()
            walkingToScope = .none
            walkingToNote = KeyedThing(origin)
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "text.quote")
                    .dsGlyph(.caption, weight: .regular)
                Text(String(localized: "from \(TitleSeam.split(origin.title).name)"))
                    .dsText(.body17)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .dsGlyph(.tick, weight: .semibold)
            }
            .foregroundStyle(DS.tint)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(String(localized: "Kept from \(origin.title). Open it")))
    }

    /// An entry's first line and the rest of it. A markdown heading mark on
    /// the first line is not part of its words.
    static func entrySplit(_ text: String) -> (first: String?, rest: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, "") }
        let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let first = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (first.isEmpty ? nil : first, rest)
    }

    /// A kept note's title line names a linked thing, not its brackets (prd
    /// §982); the link stays a door in "Links to" under the note.
    static func keptTitleLine(_ split: (first: String?, rest: String),
                              kept: Bool) -> (first: String?, rest: String) {
        guard kept, let first = split.first else { return split }
        return (first.replacingOccurrences(of: "[[", with: "")
                    .replacingOccurrences(of: "]]", with: ""), split.rest)
    }

    /// The body without a first line that only restates the title.
    static func droppingTitleLine(_ text: String, title: String) -> String {
        let split = entrySplit(text)
        guard let first = split.first,
              first.caseInsensitiveCompare(title.trimmingCharacters(in: .whitespaces)) == .orderedSame
        else { return text }
        return split.rest
    }

    /// "Ethereum — $ETH" as the name and the symbol (prd §897; the seam since
    /// §915). A row landed before §915 ("Ethereum · $ETH") still reads.
    static func chartParts(_ title: String) -> (name: String, symbol: String?) {
        if let page = dexscreenerParts(title) { return page }
        let seam = TitleSeam.split(title)
        if let symbol = seam.line { return (seam.name, symbol) }
        let split = title.components(separatedBy: " · ")
        guard split.count >= 2 else { return (title, nil) }
        return (split[0], split.dropFirst().joined(separator: " · "))
    }

    /// A pasted Dexscreener page's own title (prd §1189): "PEPE $1.69B -
    /// Pepe / WETH on Ethereum / Uniswap - DEX Screener" is the token Pepe,
    /// symbol PEPE. Only that shape, measured off a saved page; anything else
    /// falls through untouched.
    static func dexscreenerParts(_ title: String) -> (name: String, symbol: String?)? {
        let suffix = " - DEX Screener"
        guard title.hasSuffix(suffix) else { return nil }
        let page = title.dropLast(suffix.count)
        guard let dash = page.range(of: " - ") else { return nil }
        let name = page[dash.upperBound...].components(separatedBy: " / ").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let symbol = page[..<dash.lowerBound].split(separator: " ").first.map(String.init)
        return name.isEmpty ? nil : (name, symbol)
    }

    /// A mail's sender, as `MailContentView` reads it.
    static func mailSender(_ thing: Thing) -> String? {
        if let from = thing.authorHandle, !from.isEmpty { return from }
        if thing.content.hasPrefix("From ") {
            let from = String(thing.content.dropFirst("From ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return from.isEmpty ? nil : from
        }
        return nil
    }

    /// "uma@studio.example" out of "Uma Patel <uma@studio.example>".
    static func mailAddress(_ sender: String) -> String? {
        if let open = sender.firstIndex(of: "<"), let close = sender.firstIndex(of: ">"), open < close {
            return String(sender[sender.index(after: open)..<close])
        }
        return sender.contains("@") ? sender : nil
    }

    /// "Ada" out of "Chat with Ada"; a group's own name stands as it is.
    static func chatName(_ title: String) -> String {
        let prefix = String(localized: "Chat with ")
        return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }

    /// "Telegram · 6,310 messages".
    static func chatLine(_ thing: Thing) -> String {
        guard let n = thing.messageCount, n > 0 else { return thing.source }
        return "\(thing.source) · " + String(localized: "\(n) messages")
    }

    /// "Piranesi — Susanna Clarke" as its two parts — the app's one seam
    /// (`TitleSeam`, prd §915), so a work whose own title carries a dash keeps
    /// it and the author is the tail.
    static func citationParts(_ citation: String) -> (work: String, author: String?) {
        let seam = TitleSeam.split(citation)
        return (seam.name, seam.line)
    }

    /// The body, with the two per-source facts the renderer needs (prd §399):
    /// is this really markdown, and does `[[this]]` mean anything here.
    ///
    /// A tapped wikilink walks THROUGH the sheet's existing walker rather than
    /// opening a second presentation — the standing one-screen-one-`.sheet`
    /// rule, and the same door `NoteSiblingList` and the day shelf already use.
    /// A target that no landed note resolves does nothing at all, which is
    /// honest: `NoteLinks.resolve` never invents a destination for a link whose
    /// note has not synced (or never existed).
    @ViewBuilder
    private func noteProse(text: String?) -> some View {
        let prose = NoteSheetSource.prose(for: thing)
        let kept = NoteSheetSource.isKeptNote(thing)
        return NoteProse(text: text ?? prose.text,
                  markdown: prose.markdown,
                  wikilinks: prose.wikilinks,
                  onWikilink: { target in
            let match = kept
                ? NoteLinks.resolveKept([target], from: thing, context: modelContext).first
                : NoteLinks.resolve([target], context: modelContext).first
            guard let match else { return }
            walkingToScope = .none
            walkingToNote = KeyedThing(match)
        },
                  tasks: kept || prose.markdown,
                  onToggleTask: NoteSheetSource.ticksTasks(thing) ? { ordinal in
            // The one write a kept note takes (prd §982): one marker flips,
            // every word stays where it was.
            guard thing.isLive else { return }
            let next = NoteChecklist.toggled(thing.content, ordinal: ordinal)
            // The last tick of a list is felt as a finish (prd §1193).
            if NoteChecklist.finished(before: thing.content, after: next) {
                DSHaptic.success()
                chrome.flash(String(localized: "All done"), tone: .success)
            }
            thing.content = next
            modelContext.saveHonestly()
            tickedBody = next
            // The reminder the app made for this item follows the tick
            // (prd §1022).
            if let item = NoteReminders.item(at: ordinal, in: next) {
                let done = next.components(separatedBy: "\n").compactMap(NoteChecklist.task)
                    .first { NoteReminders.key($0.text) == NoteReminders.key(item) }?.done ?? false
                NoteReminders.sync(item: item, done: done, on: thing)
            }
        } : nil,
                  taskWhen: NoteSheetSource.ticksTasks(thing) ? { ordinal in
            guard let item = NoteReminders.item(at: ordinal, in: tickedBody ?? thing.content),
                  let entry = NoteReminders.entry(for: item, on: thing) else { return nil }
            return NoteReminders.label(entry.date)
        } : nil,
                  onHoldTask: NoteSheetSource.ticksTasks(thing) ? { ordinal in
            guard let item = NoteReminders.item(at: ordinal, in: tickedBody ?? thing.content) else { return }
            faceTarget = .remind(ordinal: ordinal, text: item)
        } : nil)
    }

    /// Whether the face in the eyebrow is a DOOR. Only the three networks with
    /// a profile lookup behind them: `SocialProfileCard`'s one real verb is
    /// Watch, and on X or an Instagram export it can never succeed — a control
    /// that opens a card whose only action is impossible is the dead control
    /// the honesty law bans (the same reasoning `SocialRepliesSection` already
    /// applies to a GitHub commenter's avatar).
    private var facesAreDoors: Bool { SocialThread.isSocial(thing.source) }

    /// The author's handle without Bluesky's ".bsky.social" tail — the name
    /// the person knows.
    private var authorShortHandle: String {
        SocialThread.shortHandle(thing.authorHandle ?? "")
    }

    /// "@dwr · in /design · 2h ago" — who, why (when there's a why), when.
    private var eyebrowLine: String {
        let age = "\(shortTime(thing.capturedAt)) ago"
        guard let why = SocialThread.contextPhrase(for: thing) else {
            return "@\(authorShortHandle) · \(age)"
        }
        return "@\(authorShortHandle) · \(why) · \(age)"
    }

    // MARK: - Spec table (Gallery's graft — labels change per kind)

    /// `showsWho` doubles as "not a stage layout" now (2026-07-23) — a stage
    /// already depicts both parties 200pt above this table, so "From: in
    /// your wallet" here was a one-row card saying nothing the stage hadn't
    /// already shown better. The From row is gated by the same flag the Who
    /// row already used for the identical reason.
    /// Nothing for a sheet in the room's frame that draws its own facts (prd
    /// §1187). The gate lives here because an `if` around the call in the
    /// body tipped its builder past the type checker's budget.
    @ViewBuilder
    private func specTable(contentShown: Bool, showsWho: Bool = true, drawn: Bool) -> some View {
        if drawn { specCard(contentShown: contentShown, showsWho: showsWho) }
    }

    @ViewBuilder
    private func specCard(contentShown: Bool, showsWho: Bool) -> some View {
        // Built as a bool, not just conditionals inside the VStack, so the
        // whole card (padding, background) can be skipped when nothing
        // would render — a stage's typical wallet transfer now has zero
        // spec rows (From dropped, Who already dropped), and an empty faint
        // card floating under the stage was worse than no card at all.
        // A Work receipt has already said all three of these, better and
        // higher up (2026-08-12): the deadline as its own strip in words
        // ("Due Aug 19 · in 7 days" rather than a bare timestamp), the
        // destination under the dial's first disc, and the project on its own
        // line. This is the row set the user called "a database field", and on
        // a Work sheet it was very nearly the whole thing — "Site: vercel.com"
        // beside "From: in your things".
        let isWork = workReading != nil
        // "When" and "Due" retired here 2026-08-12 (prd §365). Both existed
        // only because the content anatomy was too thin to carry the fact —
        // and for a calendar event the result was that the sheet printed the
        // SAME string twice on one screen, once in the schedule card and once
        // behind an 80pt label column. `MomentStub` now draws the moment from
        // the real dates (`capturedAt`/`endAt`/`dueAt`), which is strictly more
        // than either row could say: a range, a duration, a relative distance,
        // and an overdue deadline that reads as overdue. Same reasoning as
        // "From" standing down below — the fact isn't lost, it's said better.
        // A purchase's `content` is the seat's own account page, not a site the
        // person browsed to — "Site: bitrefill.com" under a gift-card order is
        // the leaked plumbing the Tokens exclusion beside it was written for,
        // and the dial's first disc already names where the door goes.
        // Gated on whether a CHART drew, not on one source's name (2026-08-16).
        // `thing.source != "Tokens"` was written when Tokens was the only
        // charted source, so a GeckoTerminal trending row — same dexscreener
        // link, same chart — printed "Site  dexscreener.com" under a
        // GeckoTerminal eyebrow: a third party's name attached to a row that
        // is not from them, which is the exact plumbing leak the comment
        // above says this row exists to prevent.
        let hasSite = !isWork && purchaseReading == nil && agentShape == nil
            && thing.kind == .link && ThingChart.kind(for: thing) == nil
            && !(contentShown && ThingContentView.showsLinkPreview(thing))
            && Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content)?.host() != nil
        // What a Work row's slab says instead: when it landed, which is the
        // one fact the receipt above never states and the one every archetype
        // has. The project is NOT repeated here — `WorkStageView` draws it
        // directly under the headline, where it reads as part of the sentence
        // rather than as a field.
        // The pink day in the work head says when it landed (prd §895).
        let hasLanded = false
        let hasEcho = crossSourceEcho != nil
        let hasAgent = thing.provenance.agent != nil
        // "From" WAS COMPUTED HERE and is DELETED (2026-09-15, prd §736).
        //
        // It had stood down on seven separate conditions already — a social
        // reception's own sentence (§363), a purchase's (§364), a note's
        // (§366), an agent sheet's (§367), a Work receipt, an eyebrow that
        // leads with the person (§451), a devnet event's card (§467) — every
        // one of them a place where something else said it better, in words
        // rather than behind an 80pt label column. §634 then deleted four of
        // the phrases themselves. What was left failed the same test on the
        // same grounds, so the row goes with `PlaceWords`: the dial already
        // carries a door for every kind that named a place, and the two facts
        // the row alone still held — WHICH folder, WHICH wallet — are the
        // words on those doors now ("Show in Receipts", and the wallet's own
        // name).
        let hasCounterparty = showsWho && thing.source == "Wallet"
            && !(thing.counterpartyAddress ?? "").isEmpty
        let anyRow = hasSite || hasEcho || hasAgent
            || hasCounterparty || hasLanded

        if anyRow {
            DSSpecTable {
                // When it happened, on a Work receipt. Every archetype has
                // one and the hero above never states it — a deploy, a
                // dispute and an agent run are all "a thing that happened at
                // a time", which is exactly what a receipt is for.
                if hasLanded {
                    specRow("Landed", thing.capturedAt.formatted(
                        .dateTime.month(.abbreviated).day().hour().minute()))
                }
                // Tokens' content URL is plumbing (the chart's technical
                // dependency, not a site the person browsed to) — the native
                // TokenChartView above already carries the read; a "Site" row
                // would just leak that dependency's brand under the "Tokens"
                // eyebrow (report 2026-07-13). And when the link preview card
                // is on screen its footer already names the host — repeating
                // it here read as a stutter (2026-07-13 polish).
                if hasSite,
                   let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content),
                   let host = url.host() {
                    specRow("Site", host.replacingOccurrences(of: "www.", with: ""))
                }
                // The same link, already in the corpus from somewhere else —
                // the app recognizing its own history instead of treating a
                // re-save as new (CrossSourceEcho, 2026-07-21).
                if hasEcho, let crossSourceEcho {
                    specRow("Also saved from", crossSourceEcho)
                }
                // "You wrote · Linked on X, Apr 2019" retired here 2026-08-08
                // (prd §340): the read is unchanged and better placed. It named
                // only the EARLIEST post carrying this link and could not be
                // tapped; the "Points at this" shelf below lists every one of
                // them and walks into it.
                if hasAgent, let agent = thing.provenance.agent {
                    specRow("By", "\(agent)\(thing.provenance.machine.map { " on \($0)" } ?? "")")
                }
                // A wallet transfer's counterparty — the other side of the
                // trade, nameable ("this is Mom"). Only when the hex was
                // captured (native sends have none) (2026-07-15).
                if hasCounterparty, let cp = thing.counterpartyAddress {
                    counterpartyRow(cp)
                    // When you first dealt with them (prd §1025): a fact
                    // about your own history, read off the transfers you
                    // hold. "This transfer" is the honest form of "a
                    // stranger" — it says what the app saw, not who they are.
                    if let firstSeen {
                        DSSpecRow(label: Text("First seen"),
                                  value: firstSeenIsThis
                                      ? Text("This transfer")
                                      : Text(firstSeen.formatted(.dateTime.month(.abbreviated).day().year())),
                                  lineLimit: 1)
                    }
                    // Whether the other side is a verified human (prd §791).
                    // World Chain only: the book lists World App wallets, which
                    // live there, and an address on any other chain is not one.
                    // Only a VERIFIED mark draws — absence is not a fact about
                    // a person (§785) — and it reads the observable store.
                    if isWorldChainTransfer,
                       case .verified(let until) = WorldIDSource.shared.status(for: cp) {
                        DSSpecRow(label: Text("World ID"),
                                  value: Text("Verified human until \(until.formatted(.dateTime.month(.wide).year()))"),
                                  lineLimit: 1)
                    }
                }
            }
            // The rows stand on no plate (prd §782): the table's own column
            // gathers them, and air separates it from the blocks around it.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Opening the sheet is the intent that buys the World ID read
            // (§785's rule) — one `eth_call`, cached a week, never from a row.
            .task(id: "firstSeen:\(thing.counterpartyAddress ?? "")") {
                guard hasCounterparty else { return }
                readFirstSeen()
            }
            .task(id: thing.counterpartyAddress) {
                guard hasCounterparty, isWorldChainTransfer,
                      let cp = thing.counterpartyAddress else { return }
                await WorldIDSource.shared.fill(cp)
            }
        }
    }

    /// Fills `firstSeen` for a Wallet transfer's counterparty. A Moved leg's
    /// other side is your own wallet, and "since" says nothing about yourself.
    private func readFirstSeen() {
        guard thing.source == "Wallet", MovedStage(thing) == nil,
              let cp = thing.counterpartyAddress?.lowercased(), !cp.isEmpty else { return }
        (firstSeen, firstSeenIsThis) = Self.firstSeen(of: cp, this: thing, context: modelContext)
    }

    /// The receipt's history line (prd §1025), named the way the Who row
    /// names the other side. nil until read.
    private var counterpartyHistory: String? {
        guard let firstSeen, let cp = thing.counterpartyAddress else { return nil }
        let name = WalletIngest.knownLabel(for: cp)
        if firstSeenIsThis {
            return name.map { String(localized: "Your first transfer with \($0).") }
                ?? String(localized: "Your first transfer with this address.")
        }
        // The receipt's own day form ("Left Savings on Sep 14."): the year
        // only when it is not this one.
        let thisYear = Calendar.current.isDate(firstSeen, equalTo: .now, toGranularity: .year)
        let day = thisYear ? firstSeen.formatted(.dateTime.month(.abbreviated).day())
                           : firstSeen.formatted(.dateTime.month(.abbreviated).day().year())
        return name.map { String(localized: "With \($0) since \(day).") }
            ?? String(localized: "With this address since \(day).")
    }

    /// The earliest transfer with this counterparty across every watched
    /// wallet, and whether it is this one. One fetch of one row; a counterparty
    /// is stored lowercased (`WalletIngest`), so the predicate is equality.
    @MainActor
    static func firstSeen(of counterparty: String, this thing: Thing,
                          context: ModelContext) -> (Date?, Bool) {
        var d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" && $0.counterpartyAddress == counterparty },
            sortBy: [SortDescriptor(\Thing.capturedAt, order: .forward)])
        d.fetchLimit = 1
        guard let first = (try? context.fetch(d))?.first else { return (nil, false) }
        return (first.capturedAt, first.id == thing.id || first.capturedAt >= thing.capturedAt)
    }

    /// A transfer on World Chain, read off its explorer link — the chain the
    /// World ID address book describes.
    private var isWorldChainTransfer: Bool {
        WalletIngest.chainName(forContent: thing.content) == "World Chain"
    }

    // `fromRow` was HERE and is DELETED with the row it drew (2026-09-15,
    // prd §736). It had become a door twice — the folder on 2026-08-19 (§408:
    // "would be great to be able to press here and it takes you to folder
    // where the file is saved") and the message on 2026-09-15 (§735: "can we
    // make it so that if you tap it, it takes the user to the email in the
    // inbox") — which is two people pressing a label, and the answer to the
    // second time is not a third wiring. Both doors survive in the dial, where
    // they also were; what goes is the label column that made a row look like
    // a control.


    private func specRow(_ label: String, _ value: String) -> some View {
        // Callout, not body — the values were the loudest type on the sheet
        // ("saved by you" outweighed the title's own facts).
        DSSpecRow(label: Text(LocalizedStringKey(label)),
                  value: Text(LocalizedStringKey(value)))
    }

    /// The counterparty's name (yours if set, else a known contract / watched
    /// handle, else the short hex) with a pencil — tap to name it. What you name
    /// it here rides every future transfer with this address.
    ///
    /// No tooltip: the row already says "Who" and shows the name, so the pencil
    /// is never the only thing a cursor has to go on.
    private func counterpartyRow(_ address: String) -> some View {
        DSSpecRow(label: Text("Who"),
                  value: Text(verbatim: WalletIngest.knownLabel(for: address)
                              ?? WalletStore.shortAddress(address)),
                  lineLimit: 1,
                  glyph: "square.and.pencil",
                  action: nameCounterpartyAction)
    }

    // MARK: - The dial's wiring (stage sheets — B1, 2026-07-16)

    /// The safety flag(s) on this transfer, as red lines under the amount
    /// (2026-07-23; user: the screen read as "vibe coded"). §160's "a one-line
    /// flag, not a card" rule was written for the FEED; here the warning is the
    /// whole reason you tapped in, so each flag is a full red sentence with its
    /// triangle. It stood on a tinted red panel until prd §782 (user: "remove
    /// that red background"): the red words carry the danger, and air above
    /// them sets the block apart. A transfer can wear more than one flag (a
    /// lookalike address sending a lookalike token is one scam, but each half
    /// needs saying), so each is its own line.
    private var securityWarning: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if thing.hasSecurityFlag("poisoning") {
                warningLine(String(localized: "Looks like a copy of an address you've used — this is a different wallet."))
            }
            // The symbol's own sentence, recovered from the text the row
            // shows (`WalletSafety.spoofVerdict`) so the warning can name what
            // it imitates: "Looks like a copy of USDC — this is a different
            // token." The symbol keeps its real spelling everywhere; the app
            // never quietly rewrites what the chain said.
            if let verdict = WalletSafety.spoofVerdict(for: thing) {
                warningLine(verdict.sentence)
            }
            // Says what it ISN'T before what it is: the row above already
            // asserts "Sent", in the app's own voice, and the correction has
            // to land before any explanation of the mechanism.
            if thing.hasSecurityFlag("spam") {
                warningLine(String(localized: "You didn't send this. A spam token can announce any transfer it likes — it's advertising, not money that moved."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.Space.s2)
    }

    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
                .dsGlyph(.subhead)
                .foregroundStyle(DS.destructive)
            Text(text)
                .dsText(.body17).foregroundStyle(DS.destructiveInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Prices an ENS renewal for one term (prd §540). Reads only — it quotes
    /// what a renewal would cost and prepares the transaction; nothing here
    /// signs or sends.
    ///
    /// The quote is CLEARED before the read, not left standing: a stale price
    /// under a freshly-tapped term is a figure about a different purchase, on
    /// a card somebody is reading to decide whether to spend.
    private func priceENSRenewal(term: ENSRenew.Term) {
        guard let name = ENSName.name(fromRef: thing.sourceRef ?? "") else { return }
        ensRenewQuote = nil
        Task {
            let quote = await ENSRenewPrepare.quote(
                name: name, term: term, from: ENSRenewPrepare.sender())
            // Corollary 6 — a detached task resumes later than it was made,
            // and this row can be gone by then.
            guard thing.isLive else { return }
            // The person may have tapped another term while this was in
            // flight; the last tap wins, not the last reply.
            guard term == ensRenewTerm else { return }
            ensRenewQuote = quote
        }
    }

    /// Compose the money receipt and its commentary, once per open (prd §369).
    ///
    /// Synchronous and `@MainActor` throughout, so no `[Thing]` is ever held
    /// across a suspension (the build-250 corollary); the liveness guards live
    /// inside `MoneyReceiptSource`, at the boundary where the models are read.
    private func loadReceipt() {
        guard thing.isLive else { return }
        let next = MoneyReceiptSource.receipt(for: thing, safe: safeCheck)
        // A RE-compose is a moment; the first one is just the sheet opening
        // (prd §369 amendment). Animating only the second is what lets the
        // figure's `.numericText` roll to a settled amount and the teeth cut
        // in — while a receipt that opens already final still simply appears,
        // under `settleIn`'s own entrance.
        if moneyReceipt != nil && next != moneyReceipt {
            withAnimation(DS.Motion.standard) { moneyReceipt = next }
        } else {
            moneyReceipt = next
        }
        guard moneyReceipt != nil else { moneySays = nil; return }
        moneySays = MoneyReceiptSource.commentary(for: thing, in: modelContext,
                                                  safe: safeCheck)
    }

    // MARK: - The receipt in the room's frame (prd §1181)

    /// The party's name for the history: the receipt's party, else its lead.
    private func moneyPartyName(_ r: MoneyReceipt) -> String {
        if let party = r.party, !party.isEmpty { return party }
        return r.lead
    }

    /// The two sides of a wallet transfer, for the box's faces (prd §1181).
    private func moneyTransfer(_ r: MoneyReceipt) -> MoneyReceiptBox.Transfer? {
        guard moneyHasPerson, let cp = thing.counterpartyAddress, let mine = thing.walletAddress,
              !mine.isEmpty else { return nil }
        let mineLabel = WalletStore.shared.addresses
            .first { $0.address.caseInsensitiveCompare(mine) == .orderedSame }
            .map { $0.label.isEmpty ? WalletStore.shortAddress(mine) : $0.label } ?? WalletStore.shortAddress(mine)
        return MoneyReceiptBox.Transfer(
            mineAddress: mine, mineLabel: mineLabel,
            theirAddress: cp, theirName: moneyPartyName(r),
            sent: thing.transferDirection != "received",
            usd: thing.transferUSD,
            network: WalletIngest.chainName(forContent: thing.content))
    }

    /// This event and the others that overlap the four hours around it, as
    /// plain blocks (prd §1182). One fetch by time; the kind is read in Swift.
    private func readDayBlocks(around start: Date) {
        guard thing.isLive else { return }
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: start)?.start ?? start
        let from = cal.date(byAdding: .hour, value: -1, to: hour) ?? hour
        let to = cal.date(byAdding: .hour, value: 3, to: hour) ?? hour
        let early = cal.date(byAdding: .hour, value: -12, to: from) ?? from
        let id = thing.id
        let d = FetchDescriptor<Thing>(predicate: #Predicate { $0.capturedAt >= early && $0.capturedAt < to },
                                       sortBy: [SortDescriptor(\Thing.capturedAt)])
        let place = thing.factList.first { $0.action == .map }?.value
        let name = TitleSeam.split(thing.title).name
        dayBlocks = ((try? modelContext.fetch(d)) ?? [])
            // A neighbour with this event's own name is the same meeting from
            // a second calendar: drawn twice it reads as a duplicate.
            .filter { $0.isLive && $0.kind == .event
                && ($0.id == id || TitleSeam.split($0.title).name != name) }
            .compactMap { t -> EventDaySlice.Block? in
                let end = t.endAt ?? t.capturedAt.addingTimeInterval(3600)
                guard end > from, t.capturedAt < to,
                      !t.factList.contains(where: { $0.action == .allDay }) else { return nil }
                return EventDaySlice.Block(id: t.id.uuidString, title: TitleSeam.split(t.title).name,
                                           start: t.capturedAt, end: end, isThis: t.id == id,
                                           place: t.id == id ? place : nil)
            }
    }

    /// THE FOURTH TILE ON EVERY OTHER SHEET (prd §1184): Follow the person
    /// behind a post (the profile card's own act, `SocialPeople.watch`), or
    /// the site behind a page you do not follow yet (Reading's tray, opened on
    /// its host). Nil when you already do, or there is no one to follow.
    private var sheetKeep: VerbDial.Keep? {
        if SocialThread.isSocial(thing.source), let handle = thing.authorHandle, !handle.isEmpty,
           !SocialPeople.isWatched(handle: handle, source: thing.source) {
            let profile = SocialProfile(source: thing.source, handle: handle, displayName: nil,
                                        bio: nil, avatarURL: thing.authorAvatarURL)
            return VerbDial.Keep(label: String(localized: "Follow"), glyph: ScopeTileGlyph.watch) {
                guard SocialPeople.watch(profile) else {
                    chrome.flash(String(localized: "Already following @\(profile.shortHandle)."))
                    return
                }
                chrome.flash(String(localized: "Following @\(profile.shortHandle)."), tone: .success)
                Task { await SocialPeople.sync(source: profile.source, context: modelContext) }
            }
        }
        guard thing.kind == .link, bridges != nil,
              let page = thing.externalLink ?? (thing.content.hasPrefix("http") ? thing.content : nil),
              let host = ReadingRoom.host(of: page) else { return nil }
        let followed = Set(RSSStore.shared.feeds.compactMap { ReadingRoom.host(of: $0.url) })
        guard !ReadingRoom.covered(host, by: followed),
              RoomAccounts.roomSources(RoomAccounts.readingRoom).contains(thing.source) else { return nil }
        return VerbDial.Keep(label: String(localized: "Follow"), glyph: ScopeTileGlyph.subscriptions) {
            faceTarget = .followSite(host)
        }
    }

    /// Where a media thing plays: its page.
    private var mediaLink: URL? {
        let raw = thing.externalLink ?? thing.content
        return raw.hasPrefix("http") ? URL(string: raw) : nil
    }

    /// The media sheet's acts: a song's page is its Spotify tile, so the
    /// derived Open that lands on the same page goes (one door, one tile).
    private var mediaVerbs: [Verb] {
        guard mediaOpensInApp, let url = mediaLink else { return sheetVerbs }
        return sheetVerbs.filter {
            if case .openURL(let u) = $0.action { return u != url }
            return true
        }
    }

    private var mediaOpensInApp: Bool {
        !MediaSheetBox.isVideo(thing) && thing.source != "Podcasts" && mediaLink != nil
    }

    /// The fourth tile (prd §1186): a song opens where it plays, named for
    /// the app ("Spotify"); a video or a podcast Follows its channel, Media's
    /// tray opened on the name, while you don't follow it.
    private var mediaKeep: VerbDial.Keep? {
        if mediaOpensInApp, let url = mediaLink {
            return VerbDial.Keep(label: thing.source, glyph: ScopeTileGlyph.open) { openURL(url) }
        }
        guard MediaSheetBox.isVideo(thing) || thing.source == "Podcasts",
              let channel = thing.authorHandle?.trimmingCharacters(in: .whitespaces), !channel.isEmpty,
              bridges != nil,
              !FollowingReading.shared.items(for: .media).contains(where: {
                  $0.name.caseInsensitiveCompare(channel) == .orderedSame }) else { return nil }
        return VerbDial.Keep(label: String(localized: "Follow"), glyph: ScopeTileGlyph.subscriptions) {
            faceTarget = .followChannel(seat: thing.source, name: channel)
        }
    }

    private var mediaMoreTitle: String {
        let who = TitleSeam.split(thing.title).line ?? thing.authorHandle ?? thing.source
        return String(localized: "More from \(who)")
    }

    /// The artist's other tracks, or the channel's other videos, you have —
    /// the newest three (prd §1186).
    private func readMediaMore() {
        guard thing.isLive else { return }
        let source = thing.source, id = thing.id
        let artist = TitleSeam.split(thing.title).line
        let channel = thing.authorHandle
        guard artist != nil || channel != nil else { mediaMore = []; return }
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source },
                                       sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
        d.fetchLimit = 400
        let mine = TitleSeam.split(thing.title).name
        mediaMore = Array(((try? modelContext.fetch(d)) ?? []).filter { t in
            guard t.isLive, t.id != id, TitleSeam.split(t.title).name != mine else { return false }
            if let artist { return TitleSeam.split(t.title).line == artist }
            return t.authorHandle == channel
        }.prefix(3))
    }

    /// The card that paid, when this is a card spend (prd §1182): its name and
    /// last four off the account label the bridge stamped ("Apple Card,
    /// ending 4821").
    private var moneyCard: MoneyReceiptBox.Card? {
        let cardSources: Set<String> = ["Apple Wallet", "Gnosis Pay", "MetaMask Card", "ether.fi", "Privacy"]
        guard cardSources.contains(thing.source), moneyReceipt?.mine == nil,
              let account = thing.authorHandle, !account.isEmpty else { return nil }
        let parts = account.components(separatedBy: ", ending ")
        return MoneyReceiptBox.Card(name: parts[0],
                                    last4: parts.count > 1 ? parts[1] : nil,
                                    source: thing.source)
    }

    /// A spend's own figure, from the price the bridge stored.
    static func spendAmount(_ thing: Thing) -> String? {
        guard thing.isLive, let value = thing.priceValue else { return nil }
        return abs(value).formatted(.currency(code: thing.priceCurrency ?? "USD"))
    }

    /// An address nobody has named — the head says "Tap to name".
    private var moneyUnnamed: Bool {
        guard let receipt = moneyReceipt, receipt.party == nil || receipt.party?.isEmpty == true,
              case .address(let a) = receipt.subject, !a.isEmpty else { return false }
        return AddressBook.shared.entry(for: a) == nil && WalletIngest.knownLabel(for: a) == nil
    }

    /// Whether this is a Wallet transfer with a person on the other side:
    /// not a Moved leg (your own wallet) and not a World ID grant (a contract).
    private var moneyHasPerson: Bool {
        thing.source == "Wallet" && MovedStage(thing) == nil
            && !(thing.counterpartyAddress ?? "").isEmpty
            && !WalletIngest.isWorldGrantHolder(thing.counterpartyAddress)
    }

    /// The row of facts, each a phrase read value-then-label (user: "wtf is
    /// '2 times here'"): Settled · Status, then where it moved, then which
    /// time this is with them — "2nd · With Sam", "2nd · Visit" — and, at a
    /// merchant, when you were last there. Nothing the line above says.
    private func moneyCells(_ r: MoneyReceipt) -> [MoneyReceiptCell] {
        var out: [MoneyReceiptCell] = []
        out.append(MoneyReceiptCell(value: r.stamp?.word ?? (r.finality == .open ? String(localized: "Waiting")
                                                                                 : String(localized: "Final")),
                                    label: String(localized: "Status"), wants: r.finality == .open))
        if let network = WalletIngest.chainName(forContent: thing.content), !network.isEmpty {
            out.append(MoneyReceiptCell(value: network, label: String(localized: "Network")))
        }
        if moneyHistoryTotal > 0 {
            let ordinal = NumberFormatter.localizedOrdinal(moneyHistoryTotal + 1)
            out.append(MoneyReceiptCell(value: ordinal,
                                        label: moneyHasPerson ? String(localized: "With \(moneyPartyName(r))")
                                                              : String(localized: "Visit")))
            if !moneyHasPerson, let last = moneyHistory.first?.capturedAt {
                out.append(MoneyReceiptCell(value: last.formatted(.dateTime.month(.abbreviated).day()),
                                            label: String(localized: "Last visit")))
            }
        }
        return out
    }

    private func moneyHistoryTitle(_ r: MoneyReceipt) -> String {
        moneyHasPerson ? String(localized: "With \(moneyPartyName(r))")
                       : String(localized: "At \(moneyPartyName(r))")
    }

    /// The fourth tile: the act that keeps up with it for you. Save a person
    /// you have not, Watch one you have, Track a charge that repeats.
    private var moneyKeep: VerbDial.Keep? {
        if moneyHasPerson, let cp = thing.counterpartyAddress?.lowercased() {
            if AddressBook.shared.entry(for: cp) == nil {
                guard let name = nameCounterpartyAction else { return nil }
                return VerbDial.Keep(label: String(localized: "Save"), glyph: "person.crop.circle.badge.plus", act: name)
            }
            guard !WalletStore.shared.addresses.contains(where: { $0.address.lowercased() == cp }) else { return nil }
            return VerbDial.Keep(label: String(localized: "Watch"), glyph: ScopeTileGlyph.watch) {
                let label = AddressBook.shared.name(for: cp) ?? ""
                let added = WalletStore.shared.add(cp, label: label)
                chrome.flash(added ? String(localized: "Watching \(label.isEmpty ? WalletStore.shortAddress(cp) : label)")
                                   : String(localized: "Couldn't watch this wallet"),
                             tone: added ? .success : .failure)
            }
        }
        guard thing.source != "Wallet", moneyHistoryTotal >= 1, bridges != nil,
              let receipt = moneyReceipt else { return nil }
        let name = moneyPartyName(receipt)
        return VerbDial.Keep(label: String(localized: "Track"), glyph: SubscriptionWords.planGlyph) {
            faceTarget = .track(name)
        }
    }

    /// The last three with this party, and how many in all: a Wallet transfer
    /// by its counterparty, a card spend by its merchant in the same source.
    private func readMoneyHistory() {
        guard thing.isLive else { return }
        let id = thing.id
        var others: [Thing] = []
        if let cp = thing.counterpartyAddress?.lowercased(), !cp.isEmpty, thing.source == "Wallet" {
            let d = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == "Wallet" && $0.counterpartyAddress == cp },
                sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
            others = ((try? modelContext.fetch(d)) ?? []).filter { $0.isLive && $0.id != id }
        } else {
            let source = thing.source, title = thing.title
            let d = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source && $0.title == title },
                sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
            others = ((try? modelContext.fetch(d)) ?? []).filter { $0.isLive && $0.id != id }
        }
        moneyHistoryTotal = others.count
        moneyHistory = Array(others.prefix(3))
        // This year with them, this transfer included (prd §1181).
        var year = MoneyYear()
        let cal = Calendar.current
        for t in others + [thing] where t.isLive && cal.isDate(t.capturedAt, equalTo: .now, toGranularity: .year) {
            if t.transferDirection == "received" {
                year.receivedCount += 1; year.receivedUSD += t.transferUSD ?? 0
            } else {
                year.sentCount += 1; year.sentUSD += t.transferUSD ?? 0
            }
        }
        moneyYear = year
        // A card spend's month (prd §1182): this visit and the others in the
        // same calendar month, newest first, four at most, and their total.
        if thing.source != "Wallet" {
            let month = ([thing] + others).filter {
                $0.isLive && cal.isDate($0.capturedAt, equalTo: thing.capturedAt, toGranularity: .month)
            }.sorted { $0.capturedAt > $1.capturedAt }
            moneyMonth = Array(month.prefix(4))
            let sum = month.compactMap(\.priceValue).map(abs).reduce(0, +)
            moneyMonthTotal = sum > 0 ? sum.formatted(.currency(code: thing.priceCurrency ?? "USD")) : nil
        }
    }

    /// A transaction whose whole body is the explorer link AND carries nothing
    /// else to read — the content view would render an empty block, so skip it
    /// (2026-08-12).
    ///
    /// `ThingContentView.bareLinkBody` is the ruling and the one test (the
    /// `showsLinkPreview` precedent: a shared static so the two views can't
    /// drift); this adds only the summary check, because a `.summary` is drawn
    /// BESIDE the body by `ThingContentView` — dropping the whole view for a
    /// bare URL would take a source's own abstract with it. No wallet-riding
    /// bridge stamps one today, so this guard is for the day one does.
    private var linkOnlyBody: Bool {
        ThingContentView.bareLinkBody(thing)
            && (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The Work receipt, when this row is one (2026-08-12).
    ///
    /// Sibling to `moneyReceipt` and deliberately the same shape: nil means
    /// "we have nothing better to say than the title", and the sheet renders
    /// exactly as it did before — which is what lets this land covering some
    /// Work seats and not others without a flag day.
    ///
    /// The whole derivation is `WorkStage`, which is Foundation-only so
    /// `scripts/work-stage-selftest.sh` can compile it as shipped. Nothing
    /// about the outcome is decided here.
    private var workReading: WorkStage.Reading? {
        guard thing.isLive, moneyReceipt == nil, purchaseReading == nil else { return nil }
        return WorkStage.reading(workRow)
    }

    /// The purchase receipt / watched-product card, when this row is one
    /// (2026-08-12, prd §364).
    ///
    /// Sibling to `moneyReceipt` and `workReading`, same contract: nil means
    /// "we have nothing better to say than the title", and the sheet renders
    /// exactly as it did before.
    ///
    /// It is asked BEFORE `workReading` and that ordering is load-bearing —
    /// both types read `Thing.tags`, and a shape word one of them owns
    /// ("Settled", "Food") must not be read by the other's table. The whole
    /// derivation is `PurchaseStage`, Foundation-only so
    /// `scripts/purchase-stage-selftest.sh` can compile it as shipped.
    private var purchaseReading: PurchaseStage.Reading? {
        guard thing.isLive, moneyReceipt == nil else { return nil }
        return PurchaseStageSource.reading(for: thing)
    }

    /// The agent anatomy, when this row has one (prd §367).
    ///
    /// Sibling to `moneyReceipt` and `workReading`, and gated behind BOTH for
    /// the same reason they are gated behind each other: a row wears one
    /// anatomy. (Cursor was the case that mattered — its runs sat in the Agents
    /// category and were drawn by the Work receipt — until the seat was
    /// deleted, prd §1049.)
    private var agentShape: AgentSheet.Shape? {
        guard thing.isLive, moneyReceipt == nil, workReading == nil else { return nil }
        return AgentSheetSource.shape(for: thing)
    }

    /// The conversation reading. Computed once per body evaluation and handed
    /// to the head, the turns and the receipt, so the three can never disagree
    /// about how many turns there were.
    private var agentConversation: AgentSheet.Conversation? {
        guard agentShape == .conversation else { return nil }
        return AgentSheetSource.conversation(for: thing)
    }

    /// The primitives `WorkStage` reads. Built once so the reading and the
    /// clause detail below can't be derived from two different snapshots.
    private var workRow: WorkStage.Row {
        WorkStage.Row(thing)
    }

    // `walletStage` / `isMoved` / `stageView` retired here in the 2026-08-12
    // integration merge. §369's money receipt generalized the three wallet
    // title grammars into one anatomy covering nine sources, so these three
    // had no callers left — the gates that used to read `walletStage == nil`
    // (`workReading`, `purchaseReading`, `agentReading`) read `moneyReceipt`
    // now, which is the broader and more correct question: don't draw a work
    // or purchase receipt on ANY money row, not just on a Wallet one.

    /// A money receipt's dial verbs: the explorer link, when the record carries
    /// one, and Copy. Name and Share ride the dial's own slots.
    ///
    /// The word NAMES WHERE YOU LAND (2026-08-04's "Explorer, not Open" ruling,
    /// taken one step further): the disc's glyph already says it opens
    /// something, and "Etherscan" or "mempool" is the differentiator. The name
    /// comes off the URL's own host — never off the source — because the source
    /// doesn't decide the explorer (a Wallet row can point at Etherscan,
    /// Basescan, Gnosisscan or mempool.space), and a wrong destination word on a
    /// disc that really does open something is a small lie with no symptom.
    private var walletVerbs: [Verb] {
        var out: [Verb] = []
        // "Explorer", whichever site it opens (prd §1181, user: "just say
        // explorer"): a tile names the act, never the place.
        if let url = Capture.detectURL(in: thing.content) {
            out.append(Verb(label: String(localized: "Explorer"), icon: "arrow.up.right",
                            action: .openURL(url)))
        }
        // A World ID grant opens where the next one is claimed (prd §792) —
        // only when World App is on this phone to answer the link.
        if WalletIngest.isWorldGrantHolder(thing.counterpartyAddress),
           HandOffState.installedSchemes.contains("worldapp") {
            out.append(Verb(label: "World App", icon: "arrow.up.right",
                            action: .openURL(WalletIngest.worldAppGrantsLink)))
        }
        out.append(Verb(label: "Copy link", icon: "doc.on.doc", action: .copyText))
        return out
    }

    /// A podcast episode's own audio file, as a HAND-OFF (2026-08-06).
    ///
    /// The feed's `<enclosure>` IS the episode — a row's `content` is the
    /// episode's PAGE (the publisher's show notes), and the media file itself
    /// landed on `externalLink` with nothing on any screen reading it, so the
    /// one thing a podcast row is FOR was stored and unreachable.
    ///
    /// It is a hand-off, and the word says so by saying where you land, never
    /// what we do: this app has no audio player and is not getting one here, so
    /// a disc reading "Play" would be the fake status §83 bans. "Episode"
    /// follows `walletVerbs`' "Explorer" ruling directly above — the glyph
    /// already says it opens something, the word's job is the destination — and
    /// it is medium-neutral on purpose, because the parser accepts a `video/…`
    /// enclosure too and "Audio" would be a claim we never checked.
    ///
    /// Scoped by SOURCE, never by "there is an `externalLink`". That field has
    /// several fillers now — a TikTok row's video link, a Cal.com meeting URL,
    /// a Snapchat memory's download link — and none of those may grow a listen
    /// verb. For these two
    /// feed sources it has exactly ONE writer (`FeedFollowBridges` and
    /// `RSSIngest` both fill it only from `item.mediaURL`), which is what makes
    /// the field's meaning unambiguous here and nowhere else. RSS is in because
    /// a podcast followed through the generic feed door is the same episode
    /// wearing a different seat; YouTube and Substack ride the same ingest and
    /// are out.
    ///
    /// Three gates, each closing a way this could be a disc that does nothing
    /// or one that repeats the disc beside it:
    ///  · `canOpenURL` (prd §275) — an unclaimed scheme is refused
    ///    ASYNCHRONOUSLY by LaunchServices and NEITHER `UIApplication.open`'s
    ///    completion nor SwiftUI's `openURL` reports the refusal (measured
    ///    2026-07-16 for `wc:`), so asking first is the only way to know. That
    ///    is the whole reason "Open in Photos" could be the sheet's only
    ///    screenshot verb and do nothing at all, invisibly.
    ///  · http(s) only — the enclosure is raw third-party feed text (the parser
    ///    trusts the item's own `type` attribute and never looks at the URL), so
    ///    without this a hostile feed could put a `tel:`/`sms:` URL under this
    ///    disc, and those open without any scheme declaration. An episode is
    ///    fetched over http; anything else is not one.
    ///  · not the row's own link — when a feed declares no `<link>` the
    ///    enclosure already stood in as `content` (`openURL` in both ingests),
    ///    and "Open link" opens exactly this file. Two discs doing one thing is
    ///    the menu brief §12 bans, wearing two words.
    ///
    /// Composed here rather than in `VerbDerivation` for a reason that isn't
    /// convenience: that derivation runs OFF the main actor inside GenUI
    /// composition (see `HandOffState`'s own doc) and is called per row for the
    /// feed's swipe and context menus, while `canOpenURL` is main-actor-only and
    /// a syscall (prd §260). `HandOffState`'s cached answer can't stand in — it
    /// probes a FIXED candidate list of schemes each foreground, and this URL
    /// arrives from somebody's feed, so there is no scheme to pre-probe. The
    /// sheet is `@MainActor` and opens one thing at a time, so it can just ask.
    private var episodeVerb: Verb? {
        guard thing.isLive, thing.kind == .link,
              thing.source == "Podcasts" || thing.source == "RSS",
              let raw = thing.externalLink?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != thing.content.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http",
              UIApplication.shared.canOpenURL(url)
        else { return nil }
        return Verb(label: "Episode", icon: "arrow.up.forward.app", action: .openURL(url))
    }

    /// THE DOOR BACK TO X (2026-08-18, prd §396).
    ///
    /// An imported post is the one record in this app that is also still
    /// sitting on somebody else's site, and until this pass there was no way to
    /// go and look at it: a post's `content` is its own words, so unlike a
    /// LIKED post — whose `content` is a permalink and which has always derived
    /// "Open link" — your own writing had no link at all. `landTweets` stores
    /// one now, and `healLinks` fills it in for rows that predate it.
    ///
    /// Scoped by SOURCE and by kind, never by "there is an `externalLink`" —
    /// that field means something different in every room that fills it (a
    /// video link, a podcast enclosure, a meeting URL), and the episode
    /// verb above documents why at length.
    ///
    /// "On X", not "Open": §302's Explorer ruling — the glyph already says it
    /// opens something, so the word's job is the destination. It is also the
    /// honest answer for a VIDEO post, which this app holds one frame of and
    /// cannot play: the mp4 lives in an archive folder we deliberately never
    /// copied, so the place to watch it is the place it came from.
    /// THE DOOR TO DROPBOX (prd §912). A Dropbox row is a `.file` whose bytes
    /// are not on this device, so `Verbs`' "Show in Receipts" is scoped away
    /// from it and it had no door at all. `DropboxBridge` writes the file's
    /// page — its folder on dropbox.com, previewing it — on `externalLink`,
    /// and this opens it. Scoped by SOURCE for `episodeVerb`'s reason: that
    /// field means something different for every writer. https only, and
    /// never the row's own `content` (a `.file`'s content is its note, so the
    /// two cannot coincide, but the guard costs nothing).
    private var dropboxVerb: Verb? {
        guard thing.isLive, thing.kind == .file, thing.source == "Dropbox",
              let raw = thing.externalLink?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw), url.scheme == "https"
        else { return nil }
        return Verb(label: "Dropbox", icon: "arrow.up.forward.app", action: .openURL(url))
    }

    private var xPostVerb: Verb? {
        guard thing.isLive, thing.kind == .note,
              thing.source == XArchiveImport.source,
              let raw = thing.externalLink?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw), url.scheme == "https"
        else { return nil }
        return Verb(label: "On X", icon: "arrow.up.forward.app", action: .openURL(url))
    }

    /// The dial's verbs: derivation, plus the episode hand-off derivation can't
    /// gate (above). FIRST, on the Obsidian ruling — for an episode the file is
    /// the strongest thing you can do with the row, and the page below it is the
    /// notes — and re-capped at four, so adding one can never turn a sheet into
    /// a menu; the verb that loses is the last derivation ranked, not this one.
    /// A Privy app's two doors (prd §803e): the app itself, when Privy names
    /// where it lives, and the wallet on an explorer. Never Export keys or Add
    /// funds (user, 2026-09-17).
    private var privyVerbs: [Verb] {
        guard let ref = thing.sourceRef, let app = PrivyHomeStore.shared.byRef[ref] else { return [] }
        var out: [Verb] = []
        if let origin = app.origin.flatMap(URL.init(string:)) {
            out.append(Verb(label: String(localized: "Open in \(app.name)"),
                            icon: "arrow.up.forward.app", action: .openURL(origin)))
        }
        if let wallet = app.wallets.first,
           let explorer = URL(string: PrivyHomeFeed.explorerURL(wallet)) {
            out.append(Verb(label: String(localized: "Explorer"), icon: "arrow.up.right",
                            action: .openURL(explorer)))
        }
        return out
    }

    /// A person in the room's frame (prd §1187): the handle is the title,
    /// the face leads the box, then the tiles and what of theirs you have.
    @ViewBuilder
    private var personFrame: some View {
        // In the room's frame since prd §1187: the handle is the
        // title, the face leads the box, then the tiles and what
        // of theirs you already have.
        let handle = thing.authorHandle ?? ""
        DSRoomTitleRow(title: SocialThread.shortHandle(handle))
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        SocialPersonBox(
            handle: handle,
            displayName: nil,
            avatarURL: thing.authorAvatarURL,
            source: thing.source,
            since: thing.capturedAt,
            following: SocialPeople.isWatched(handle: handle, source: thing.source),
            onOpenProfile: {
                faceTarget = .person(SocialProfile(
                    source: thing.source, handle: handle,
                    displayName: nil, bio: nil,
                    avatarURL: thing.authorAvatarURL))
            })
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil,
                 keep: sheetKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
        if !personPosts.isEmpty {
            MoneyHistoryRows(title: String(localized: "Lately"), rows: personPosts,
                             onOpen: { walkingToScope = .none; walkingToNote = KeyedThing($0) })
                .padding(.top, DS.Space.s6)
                .settleIn(delay: 0.12)
        }
    }

    /// An agent chat in the room's frame (prd §1191): its title, the box of
    /// what you asked and the reply's first words, the tiles (Continue
    /// fourth), then the turns.
    @ViewBuilder
    private func agentFrame(_ reading: AgentSheet.Conversation) -> some View {
        DSRoomTitleRow(title: reading.hero)
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        AgentChatBox(thing: thing, reading: reading)
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil,
                 keep: continueKeep(reading))
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
    }

    /// A chat with a person in the room's frame (prd §1191): the person, the
    /// box of how much and the last exchange, the tiles, then the chat.
    @ViewBuilder
    private var transcriptFrame: some View {
        DSRoomTitleRow(title: Self.chatName(thing.title))
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        ChatTranscriptBox(thing: thing)
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: sheetKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
    }

    /// Anything else in the room's frame (prd §1191): its title, the box of
    /// the thing (its picture, or its site or app said big), the tiles.
    @ViewBuilder
    private var plainFrame: some View {
        // A file's name is whole ("Contract — joinery.pdf"): its dash is the
        // file's own, never §915's seam.
        DSRoomTitleRow(title: thing.kind == .file ? thing.title : TitleSeam.split(thing.title).name)
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        ThingSheetBox(thing: thing)
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
            // A document's first page, read once and kept (prd §1192).
            .task(id: thing.id) {
                guard FileFirstPage.applies(thing) else { return }
                _ = await FileFirstPage.readAndKeep(thing)
            }
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: sheetKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
    }

    /// The thing's own content. A charted row is handed the sheet's tiles to
    /// stand under its boxed price (prd §1188).
    @ViewBuilder
    private func sheetContent(articleHead: Bool, mailHead: Bool, chartHead: Bool) -> some View {
        ThingContentView(thing: thing, agent: agentConversation,
                         articleArt: !articleHead,
                         mailSender: !mailHead)
            .environment(\.priceHeadDrawn, chartHead)
            .environment(\.postLeadPictureDrawn, PostSheetBox.picturesTheBox(thing))
            .environment(\.priceBoxTiles, chartHead ? { keep in AnyView(chartTiles(keep: keep)) } : nil)
            .environment(\.keepPassage, keepPassage)
    }

    @ViewBuilder
    private func chartTiles(keep: VerbDial.Keep?) -> some View {
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: keep ?? sheetKeep)
        dialResult
    }

    /// A post in the room's frame (prd §1188, §1192): the person is the
    /// title, the box its picture or the person, then the tiles, what it
    /// answered, and the words whole, once.
    @ViewBuilder
    private var postFrame: some View {
        let pictured = PostSheetBox.picturesTheBox(thing)
        DSRoomTitleRow(title: PostSheetBox.title(thing))
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        PostSheetBox(thing: thing, onFace: facesAreDoors ? openAuthorProfile : nil)
            .dsRoomBox(bleed: pictured)
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: sheetKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
        if let parent = thing.parent {
            replyingToRow(parent)
                .padding(.horizontal, DSRoomChassis.leadInset)
                .padding(.top, DS.Space.s6)
        }
        Text(verbatim: SocialSheetSource.words(for: thing))
            .dsText(.heading20)
            .foregroundStyle(DS.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s6)
        // The counts stand in the person's box; with a picture there, here.
        let counts = PostSheetBox.counts(thing)
        if pictured, !counts.isEmpty {
            Text(verbatim: counts.joined(separator: " · "))
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DSRoomChassis.leadInset)
                .padding(.top, DS.Space.s2)
        }
    }

    /// A mail in the room's frame (prd §1188): the sender is the title, the
    /// subject leads the box, then the tiles (the fourth tracks the sender
    /// as a subscription while it is on no list), then the message.
    @ViewBuilder
    private var mailFrame: some View {
        let sender = Self.mailSender(thing)
        DSRoomTitleRow(title: sender.map { SenderInitial.displayName(of: $0) } ?? thing.source)
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        MailSheetBox(thing: thing, sender: sender, address: sender.flatMap(Self.mailAddress))
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: mailKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
    }

    /// Track a subscription (prd §1115, the fourth tile since §1188): only
    /// once the reading says the sender is on no list.
    private var mailKeep: VerbDial.Keep? {
        guard mailListRead, mailList == nil, let address = mailSubscriptionAddress else { return nil }
        return VerbDial.Keep(label: String(localized: "Track"), glyph: SubscriptionWords.planGlyph) {
            addMailSubscription(address)
        }
    }

    /// An article in the room's frame (prd §1188): the publication is the
    /// title, the box the picture and the headline, then the tiles, then the
    /// words.
    @ViewBuilder
    private var articleFrame: some View {
        DSRoomTitleRow(title: ArticleSheetBox.publication(thing))
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        ArticleSheetBox(thing: thing)
            .dsRoomBox()
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
        VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: sheetKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
    }

    /// A track, a video or an episode in the room's frame (prd §1186).
    @ViewBuilder
    private var mediaFrame: some View {
        // THE ROOM'S FRAME (prd §1186): the title, the box (a video's
        // frame, or the cover beside who and when), the tiles, then
        // more from the artist or the channel.
        DSRoomTitleRow(title: MediaSheetBox.title(thing))
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, onBack == nil ? DS.Space.s4 : DS.Space.s3)
            .settleIn(delay: 0.04)
        MediaSheetBox(thing: thing, onOpen: mediaOpen)
            .dsRoomBox(bleed: MediaSheetBox.isVideo(thing))
            .padding(.top, DS.Space.s3)
            .settleIn(delay: 0.06)
            .task(id: thing.id) { readMediaMore() }
        VerbDial(thing: thing, verbs: mediaVerbs, onVerb: runVerb, onName: nil,
                 keep: mediaKeep)
            .padding(.top, DSRoomChassis.leadGap)
            .settleIn(delay: 0.08)
        dialResult
        if !mediaMore.isEmpty {
            MoneyHistoryRows(title: mediaMoreTitle, rows: mediaMore.keyed,
                             onOpen: { walkingToScope = .none; walkingToNote = KeyedThing($0) })
                .padding(.top, DS.Space.s6)
                .settleIn(delay: 0.12)
        } else if MediaSheetBox.isVideo(thing),
                  let about = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !about.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("About").dsText(.heading20).foregroundStyle(DS.brandInk)
                Text(verbatim: about).dsText(.body17).foregroundStyle(DS.textSecondary)
                    .lineLimit(6)
            }
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.top, DS.Space.s6)
        }
    }

    /// A chain, a wallet or an app's wallet in the room's frame (prd §1187).
    @ViewBuilder
    private func framedCheck(chain: String?, wallet: String?, privy: PrivyHomeFeed.App?) -> some View {
        if let chain {
            L2beatChainSheet(chainID: chain) { keep in
                VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: keep)
                dialResult
            }
        } else if let wallet {
            WalletbeatWalletSheet(walletID: wallet) { keep in
                VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil, keep: keep)
                dialResult
            }
        } else if let privy {
            PrivyAppSheet(app: privy) {
                VerbDial(thing: thing, verbs: sheetVerbs, onVerb: runVerb, onName: nil)
                dialResult
            }
        }
    }

    /// Where a video's frame opens (prd §1186).
    private var mediaOpen: (() -> Void)? {
        guard let url = mediaLink else { return nil }
        return { openURL(url) }
    }

    /// The checkups and the person whose one link is their source's own page
    /// (prd §1187), so its tile says the place.
    private var landsAtSource: Bool {
        l2beatShape != nil || walletbeatShape != nil || socialShape == .person
            || isSocialPost
    }

    private var sheetVerbs: [Verb] {
        var derived = VerbDerivation.verbs(for: thing)
        // WHERE you land, never "Open" — §302's Explorer ruling, generalised
        // (prd §364). A Bitrefill order and a Privacy purchase both derived
        // the generic "Open link" from their kind, so the one disc that goes
        // anywhere named neither the place nor what you would find there.
        // Only the FIRST verb is renamed, and only when it really is the
        // record's own link, so a source hand-off derived below keeps its own
        // word.
        if let word = purchaseReading?.destination, let first = derived.first,
           case .openURL = first.action {
            derived[0] = Verb(label: word, icon: first.icon, action: first.action)
        } else if landsAtSource, let first = derived.first, case .openURL = first.action {
            // A chain, a wallet or a person in the room's frame (prd §1187):
            // the link is the reviewer's or the network's own page.
            derived[0] = Verb(label: thing.source, icon: "arrow.up.right", action: first.action)
        }
        let extras = [joinVerb, episodeVerb, xPostVerb, dropboxVerb].compactMap { $0} + privyVerbs
        guard !extras.isEmpty else { return derived }
        return Array((extras + derived).prefix(4))
    }

    /// The one tap a meeting is for (2026-08-14).
    ///
    /// `ScheduleIngest` has stored a meeting's URL on `externalLink` since
    /// 2026-08-06 and said so in its own comment — "stored data waiting on a
    /// verb" — so an event's only disc was "Open in Calendar", which opens the
    /// calendar's ROOT, not even the event. The link you actually want at the
    /// moment the row matters was in the corpus and reachable from nowhere.
    ///
    /// Scoped by CONTENT, not by source, and that is the opposite of
    /// `episodeVerb`'s ruling directly below for a reason: that one had to be
    /// source-scoped because `externalLink` means something different in every
    /// bridge that writes it, and "there is a link" is no evidence of what it
    /// is. Here the gate is `ConferenceLink.isConference` — a fixed allowlist
    /// of conference hosts — which is a claim about the link itself, so it
    /// holds for any event that has one: a Calendar meeting, a Cal.com booking,
    /// an event captured from a page. It is re-asked here rather than trusted
    /// from the store, so a link written by an older build under looser rules
    /// can never inherit a "Join" disc.
    ///
    /// `canOpenURL` for the §275 reason every verb here carries: an unclaimed
    /// scheme is refused ASYNCHRONOUSLY and neither `UIApplication.open`'s
    /// completion nor SwiftUI's `openURL` reports it — https is always claimed,
    /// so this passes in practice and costs one syscall to be sure.
    private var joinVerb: Verb? {
        guard thing.isLive, thing.kind == .event,
              let raw = thing.externalLink?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              ConferenceLink.isConference(url),
              UIApplication.shared.canOpenURL(url)
        else { return nil }
        return Verb(label: "Join", icon: "video", action: .openURL(url))
    }

    /// The one verb gate, both layouts: reads pass, writes confirm.
    private func runVerb(_ verb: Verb) {
        if verb.isWrite {
            confirmingVerb = verb
        } else {
            Task { await perform(verb) }
        }
    }

    /// The door under a mail (prd §1115). On a list: "Writes about weekly",
    /// into Day's Subscriptions tile with the list's sheet up (§1113's door,
    /// the tile's glyph). On none: Track a subscription, the Wallet's words,
    /// which files every mail from this sender, the ones already here
    /// included. Nothing while the reading has not answered, and nothing for
    /// a sender with no address to file by (§83).
    @ViewBuilder
    private var mailSubscriptionDoor: some View {
        if mailListRead, let list = mailList {
            DSDoorRow(icon: SubscriptionWords.planGlyph,
                      title: Text(verbatim: MailSubscriptions.writesWords(list))) {
                dismiss()
                chrome.open(.list(list.id))
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    /// The sender's mailbox: the envelope's address, else the one in the
    /// sender's name. Only for a mail seat the reading reads, or the add
    /// would file nothing (§83).
    private var mailSubscriptionAddress: String? {
        guard MailSubscriptionsReading.sources.contains(thing.source) else { return nil }
        return MailSubscriptions.address(thing.authorEmail, sender: Self.mailSender(thing))
    }

    /// Read once the sheet is up (prd §628): the tile's own reading.
    private func readMailList() {
        MailSubscriptionsReading.shared.refresh(modelContext)
        mailList = MailSubscriptionsReading.shared.item(holding: thing.id)
        mailListRead = true
    }

    /// The one write: the sender joins the tile. The door turns into the
    /// list's own, and the toast says where it went.
    private func addMailSubscription(_ address: String) {
        let name = MailSubscriptions.senderName(Self.mailSender(thing))
        guard MailSubscriptionStore.shared.add(address: address, name: name) != nil else { return }
        withAnimation(DS.Motion.standard) { readMailList() }
        chrome.flash(String(localized: "Tracking \(name ?? address)"))
    }

    /// Watching an unfinished record from the lock screen (prd §369
    /// amendment).
    ///
    /// **Opt-in, one record at a time, and only where there is something to
    /// wait for.** Starting an activity automatically for every pending row
    /// would hand a card user four of them they never asked for — the same
    /// "did you already know?" test that keeps §313's card charges from
    /// notifying at all. So the person picks the one they are actually waiting
    /// on, which also means this never spends attention on their behalf.
    ///
    /// Absent entirely when Live Activities are switched off for the app: a
    /// control that cannot do its job must not be drawn saying it can (§83).
    @ViewBuilder
    private func trackRecordControl(_ receipt: MoneyReceipt) -> some View {
        if MoneyActivityDriver.available {
            let id = thing.id.uuidString
            Button {
                Task {
                    if MoneyActivityDriver.isTracking(id) {
                        await MoneyActivityDriver.stop(id: id)
                    } else {
                        // The lock-screen title is the receipt's own lead and
                        // party — never its figure (see the attributes' rule 3
                        // and §374).
                        let title = [receipt.lead, receipt.party]
                            .compactMap { $0 }.joined(separator: " ")
                        MoneyActivityDriver.start(
                            id: id, title: title,
                            stamp: receipt.stamp?.word ?? "")
                    }
                    tracking = MoneyActivityDriver.isTracking(id)
                }
            } label: {
                // A verb, so the door row's face (prd §746) — it was a faint
                // capsule, the one pill on the receipt.
                DSDoorRowLabel(icon: tracking ? "bell.badge.slash" : "bell.badge",
                               title: tracking ? Text("Stop following it")
                                               : Text("Watch it from the lock screen"))
            }
            .buttonStyle(RowPress())
            .dsHover()
            .frame(maxWidth: .infinity)
            .onAppear { tracking = MoneyActivityDriver.isTracking(id) }
        }
    }

    /// Opening the address behind the receipt's subject face (prd §369
    /// amendment) — what this app knows about it: the history you share, what
    /// it can move, and the name you gave it.
    ///
    /// An address that is not in the book still opens, on a TRANSIENT entry.
    /// That is the point rather than an oversight: naming is a deliberate act
    /// (prd §169 — naming is free, watching is the capped upgrade), so a tap on
    /// a face must not quietly file a stranger's address in your book. The card
    /// reads `book.entry(for:) ?? entry`, so it upgrades itself the moment the
    /// address really is named from inside it.
    private func openAddressCard(_ address: String) {
        guard !address.isEmpty else { return }
        faceTarget = .address(
            AddressBook.shared.entry(for: address)
                ?? AddressBook.Entry(
                    address: address,
                    name: WalletIngest.knownLabel(for: address)
                        ?? WalletStore.shortAddress(address),
                    addedAt: .now))
    }

    /// The naming flow, when there's an address to name — nil keeps the
    /// stage's face plain and the Name disc absent (no dead controls).
    private var nameCounterpartyAction: (() -> Void)? {
        guard let cp = thing.counterpartyAddress, !cp.isEmpty else { return nil }
        return {
            counterpartyDraft = AddressBook.shared.name(for: cp) ?? ""
            counterpartyTarget = cp
        }
    }

    /// The Name disc for a thing whose "who" is not a wallet: the first
    /// identity the seam resolves (`ContactIndex.keys`) that is not a contact
    /// card (a card already names itself) — nil where nothing is nameable, so
    /// no disc is drawn (§83).
    private var nameIdentityAction: (() -> Void)? {
        let keys = ContactIndex.keys(
            source: thing.source, kind: thing.kind.rawValue, sourceRef: thing.sourceRef,
            authorHandle: thing.authorHandle, walletAddress: nil, counterpartyAddress: nil,
            authorEmail: thing.authorEmail,
            isNotification: thing.sourceRef?.hasPrefix("gh:notif:") ?? false)
        guard let identity = keys.compactMap(Identity.parse(key:)).first(where: { $0.kind != .contact && $0.kind != .wallet })
        else { return nil }
        return {
            counterpartyDraft = ContactBook.shared.name(for: identity.key) ?? ""
            identityTarget = identity
        }
    }

    /// The verb outcome, honesty-styled — ONE text both layouts place, so a
    /// bridge's no reads the same wherever the verb lived.
    @ViewBuilder private var verbOutcome: some View {
        if let verbResult {
            Text(verbResult)
                .dsText(.subhead12)
                .foregroundStyle(verbResultIsError ? DS.attentionInk : DS.confirmInk)
                // The line ARRIVES rather than blinking into place. The `.id`
                // is what makes that true for the second one as well: without
                // it "Pinned" → "Unpinned" reuses the same `Text`, `SettleIn`
                // never sees another `onAppear`, and only the first outcome
                // of a sheet's life would have settled.
                .settleIn()
                .id(verbResult)
        }
    }

    /// The outcome under the dial — centered, where the discs are.
    private var dialResult: some View {
        verbOutcome
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s2)
    }

    /// Renders this thing (and what it sits near) as markdown on the
    /// clipboard. The neighbours are fetched here rather than reused from the
    /// shelf's stream: that stream is a rendered document, not an array of
    /// things, and the shelf may not have finished — a copy verb that silently
    /// omits the related list depending on scroll timing is worse than one
    /// that spends a bounded fetch.

    // MARK: - Ask about this (2026-08-06)

    /// The agent, reachable from a thing (2026-08-06). Until now the keyed
    /// agent had exactly ONE door — the composer — so the moment you were most
    /// likely to have a question about something ("what else do I have on
    /// this?") was the one moment you had to leave, reopen the agent, and type
    /// the subject back in yourself.
    ///
    /// It hands the ask to `ShellChrome` rather than answering here: one
    /// answer surface, one conversation, one place a keyed answer can be kept
    /// — a second answer renderer inside a sheet would fork all three. With a
    /// key configured it runs the keyed arc (free on-device answer first, the
    /// keyed one straight after); without one it is an ordinary ask, which is
    /// still the useful verb it names.
    ///
    /// One chip, not a disc: the dial holds the verbs that DO something to
    /// this thing, and this one leaves it to go somewhere else.
    /// CARRY THIS CONVERSATION ON, on the person's own key (2026-08-20).
    ///
    /// An imported chat is the one row in this corpus that was a live
    /// conversation somewhere else and became a dead record here: §367 made the
    /// sheet finally DRAW it, and reading it is still all you can do. This is
    /// the verb that was missing — the turns become the keyed agent's history,
    /// so the next thing you say lands in the chat it belongs to rather than in
    /// an empty one.
    ///
    /// **Three conditions, and each one is the difference between a real verb
    /// and a dead control.** A key must be configured (there is no free path
    /// for this — the on-device model holds no conversation of its own). The
    /// transcript must have parsed into real exchanges, so a row whose speaker
    /// labels we cannot read never offers to continue a conversation it cannot
    /// see. And Bankr is excluded upstream by `AgentAnswer` itself, which
    /// answers from a wallet rather than from turns somebody handed it.
    ///
    /// It seeds the ask with the conversation's own PENDING question when the
    /// transcript ends on one — the clamp keeps the oldest end, so this is a
    /// question that really was left hanging — and otherwise opens the composer
    /// empty for the person to type. It never invents a question.
    @ViewBuilder
    private func continueKeep(_ reading: AgentSheet.Conversation) -> VerbDial.Keep? {
        guard thing.isLive, AgentKey.isConfigured else { return nil }
        let paired = AgentSheet.exchanges(reading.turns)
        guard !paired.history.isEmpty else { return nil }
        // Carry it on with your agent (prd §632's chip, the fourth tile since
        // §1191): the conversation so far as the agent's history.
        return VerbDial.Keep(label: String(localized: "Continue"), glyph: "arrow.turn.down.right") {
            DSHaptic.tap()
            dismiss()
            chrome.ask(
                paired.pending ?? "",
                withKey: true,
                seedHistory: paired.history.map {
                    AgentTurn(question: $0.question, answer: $0.answer)
                },
                seedSystem: AgentSheet.continuationInstructions(
                    source: thing.source, cut: reading.cut))
        }
    }

    private var liveLinkedNotes: [KeyedThing] {
        linkedNotes.filter { $0.thing.isLive }
    }

    private var noteLinksSection: some View {
        noteLinkList("Links to", notes: liveLinkedNotes)
    }

    /// The inverse graph, generalized (2026-08-08, prd §340). A thing's own
    /// outgoing links are written in its text; its incoming ones are written in
    /// everybody else's, which is the one direction a corpus can show and a
    /// single app cannot.
    ///
    /// Drawn UNDER "Links to" and with an inbound arrow, so the two can never
    /// read as one list — a note that both links to and is linked from another
    /// would otherwise appear twice with no way to tell the directions apart
    /// (`backlinksSection`'s rule, kept).
    ///
    /// Each row says WHY it is here (`Tie.detail`), because two different facts
    /// share this shelf now: somebody wrote `[[this]]`, or somebody wrote this
    /// thing's URL. An unlabelled mixed list would make the weaker one look
    /// like the stronger.
    private var pointsAtSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Points at this")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            ForEach(pointingAt, id: \.id) { tie in
                Button {
                    walkTo(tie)
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: "arrow.down.left")
                            .accessibilityHidden(true)
                            .dsGlyph(.caption)
                            .foregroundStyle(DS.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tie.title)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Text(tie.detail)
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
            }
        }
    }

    /// Walks into a tie's real row. Resolved at TAP time, not held — and a row
    /// deleted since the shelf was drawn simply doesn't open, rather than
    /// opening a sheet over a tombstone.
    private func walkTo(_ tie: ThingLinks.Tie) {
        guard let target = ThingLinksSource.resolve(tie, context: modelContext) else { return }
        walkingToScope = .none
        walkingToNote = KeyedThing(target)
    }

    @ViewBuilder
    private func noteLinkList(_ title: LocalizedStringKey, notes: [KeyedThing],
                              icon: String = "arrow.up.right") -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(title)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            ForEach(notes) { note in
                // `liveLinkedNotes` filters when this view VALUE is made; this
                // runs again each time the closure is re-evaluated, which is
                // when the delete actually lands (corollary 3, build 176 —
                // see `ThingRowKeying`).
                if let linked = note.live {
                    Button {
                        walkingToScope = .none
                        walkingToNote = note
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: icon)
                                .accessibilityHidden(true)
                                .dsGlyph(.caption)
                                .foregroundStyle(DS.textTertiary)
                            Text(linked.title)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                }
            }
        }
    }

    // MARK: - Related shelf (streams last)

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // `factRows` moved under the picture's title (prd §885).
            // The same object's other rows include the earlier copy, so the
            // one row never says it twice (prd §1079).
            if sameObject.isEmpty { keptBeforeRow } else { sameObjectRows }
            if !relatedStream.els.isEmpty {
                Text(LocalizedStringKey(relatedTitle))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
            }
            GenRender(id: "root", els: relatedStream.els)
        }
    }

    // MARK: - What this is about to make you do (prd §282, 2026-08-02)

    /// An upcoming moment this screenshot's own text names — the appointment in
    /// the confirmation you screenshotted, the time somebody sent you. The DATE
    /// is `NSDataDetector`'s, never the model's (`ScreenshotFacts` says why);
    /// the label is the model's few words, or the thing's title.
    ///
    /// The tap is a HAND-OFF, not a write: it copies the words and opens
    /// Calendar on that day, the same contract every Calendar verb in this app
    /// keeps. Nothing puts an event in anybody's calendar off the back of a
    /// picture.
    @ViewBuilder
    private var factRows: some View {
        ForEach(facts) { fact in
            Button {
                let copied = fact.label
                let when = fact.date
                Task {
                    do {
                        try await HandOff.openCalendar(at: when, copying: copied)
                    } catch {
                        verbResultIsError = true
                        verbResult = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "calendar.badge.plus")
                        .accessibilityHidden(true)
                        .dsGlyph(.caption)
                        .foregroundStyle(DS.textTertiary)
                    // THE DATE ALONE (prd §885). The row sits under the title
                    // now, so naming the moment again said the title twice —
                    // and the name is the model's, arriving seconds late, which
                    // resized the row and moved the dial. The label still rides
                    // the clipboard into Calendar; only the screen stops
                    // waiting for it. No year: a fact is within the next one.
                    Text(fact.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityHint(Text("Opens Calendar on this day"))
            .dsHover()
            // The words' column, under the title it belongs to (§885).
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.bottom, DS.Space.s2)
        }
    }

    // MARK: - Kept before (prd §282, 2026-08-02)

    /// "You kept this in April" — the earlier copy of this exact thing, saved
    /// from another app or on another day, as a door to it. Deterministic
    /// (`RelatedThings.keptBefore`): same title in the same kind, or the same
    /// link with the tracking junk off it. Never a semantic guess, because this
    /// row makes a CLAIM and §83 forbids a claim we can't stand behind.
    ///
    /// Walks through `walkingToNote`, the sheet's existing re-presentation of
    /// itself — no new `.sheet` on this screen (the one-screen-one-sheet rule).
    @ViewBuilder
    private var keptBeforeRow: some View {
        if let earlier = keptBefore, let copy = earlier.live {
            Button {
                walkingToScope = .none
                walkingToNote = earlier
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .accessibilityHidden(true)
                        .dsGlyph(.caption)
                        .foregroundStyle(DS.textTertiary)
                    Text("You kept this \(copy.capturedAt.formatted(.relative(presentation: .named))) · \(copy.source)")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .dsHover()
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
    }

    // MARK: - The same object (prd §1079)

    /// Work's and Reading's rows folded under this one: each a door to that
    /// row, saying what it said (a PR's events) or where it was kept (an
    /// article's saves), and when.
    @ViewBuilder
    private var sameObjectRows: some View {
        ForEach(sameObject) { item in
            if let other = item.live {
                let reading = ObjectFold.Room(room: RoomAccounts.host(ofSource: other.source)?.room ?? "")
                    == .reading
                Button {
                    walkingToScope = .none
                    walkingToNote = item
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: "clock.arrow.circlepath")
                            .accessibilityHidden(true)
                            .dsGlyph(.caption)
                            .foregroundStyle(DS.textTertiary)
                        Text(reading ? other.source : other.title)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(other.capturedAt.formatted(.relative(presentation: .named)))
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
            }
        }
    }

    /// The rows sharing this one's object key, out of the recent corpus the
    /// related shelf already fetched.
    private func sameObjectRows(in all: [Thing]) -> [Thing] {
        guard thing.isLive,
              let room = ObjectFold.Room(room: RoomAccounts.host(ofSource: thing.source)?.room ?? ""),
              let key = ObjectFold.key(room: room, source: thing.source, link: thing.content)
        else { return [] }
        return all.filter { other in
            guard other.isLive, other.id != thing.id,
                  let otherRoom = ObjectFold.Room(
                      room: RoomAccounts.host(ofSource: other.source)?.room ?? ""),
                  otherRoom == room
            else { return false }
            return ObjectFold.key(room: room, source: other.source, link: other.content) == key
        }
        .sorted { $0.capturedAt > $1.capturedAt }
        .prefix(8)
        .map { $0 }
    }

    private func streamRelated() {
        // NO GUESSES UNDER A THING (prd §632, 2026-09-06). The embedding
        // neighbours and the tag-overlap fallback are gone: cosine similarity
        // with no confidence floor always filled its slots, and a shelf that
        // is half right trains the eye to skip it. What survives makes a
        // claim the app can stand behind — the earlier copy of this exact
        // thing (`keptBefore`), and for a token, the things that NAME it.
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300   // relatedness lives in the recent past
        let all = (try? modelContext.fetch(descriptor)) ?? []

        if let earlier = RelatedThings.keptBefore(thing, in: all) {
            keptBefore = KeyedThing(earlier)
        }
        sameObject = sameObjectRows(in: all).map { KeyedThing($0) }

        guard TokenWatch.isWatchedToken(thing) else { return }
        let mentions = tokenMentions(in: all)
        guard !mentions.isEmpty else { return }

        var doc = ["root = Shelf([\(mentions.indices.map { "c\($0)" }.joined(separator: ", "))])"]
        for (i, t) in mentions.enumerated() {
            let title = t.title.replacingOccurrences(of: "\"", with: "")
            doc.append("c\(i) = Chip(\"\(t.source)\", \"\(title)\")")
        }
        relatedStream.stream(doc)
    }

    /// Corpus things that MENTION this watched token — a cashtag ($PEPE,
    /// boundary-checked so $PEPE never claims $PEPEX) or the token's full
    /// name as a whole word when it's distinctive (4+ characters — "Pepe"
    /// matches, a name like "Sol" would false-hit half the corpus). Other
    /// watchlist rows are excluded: they're the watchlist, not context.
    private func tokenMentions(in all: [Thing]) -> [Thing] {
        guard TokenWatch.isWatchedToken(thing) else { return [] }
        let symbol = TokensAsk.symbol(of: thing.title)
        let name = thing.title.components(separatedBy: " · $").first ?? ""
        var patterns: [String] = []
        if !symbol.isEmpty {
            patterns.append("\\$\(NSRegularExpression.escapedPattern(for: symbol))\\b")
        }
        if name.count >= 4 {
            patterns.append("\\b\(NSRegularExpression.escapedPattern(for: name))\\b")
        }
        guard !patterns.isEmpty,
              let regex = try? NSRegularExpression(pattern: patterns.joined(separator: "|"),
                                                   options: [.caseInsensitive])
        else { return [] }
        return Array(all.filter { other in
            guard other.id != thing.id, other.source != TokenWatch.source else { return false }
            let text = "\(other.title) \(other.content)"
            return regex.firstMatch(in: text, options: [],
                                    range: NSRange(text.startIndex..., in: text)) != nil
        }.prefix(6))
    }

    // MARK: - Verb execution

    private func perform(_ verb: Verb) async {
        confirmingVerb = nil
        verbResultIsError = false
        switch verb.action {
        case .openURL(let url):
            openURL(url)
        case .addToCalendar:
            do {
                try await HandOff.addToCalendar(thing)
                verbResult = String(localized: "Copied — paste it in Calendar")
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .addToReminders:
            do {
                try await HandOff.addToReminders(thing)
                // Names both halves: the app opened, and the words are on the
                // clipboard waiting to be pasted. Casberi did not file it.
                verbResult = String(localized: "Copied — paste it in Reminders")
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .copyText:
            DSPasteboard.copy(thing.content.isEmpty ? thing.title : thing.content)
            // The word and the buzz in one place, which is the property
            // `DSHaptic.success`'s "fired only by `ShellChrome.flash`" rule
            // exists to protect: no felt outcome with nothing on screen to
            // explain it. A copy's outcome is this line under the dial, not a
            // toast, so routing it through the flash would put the same word
            // on screen twice. It was also the only pasteboard write in the
            // app that was felt by nothing at all.
            verbResult = String(localized: "Copied")
            DSHaptic.success()
        case .markDone:
            // Rung-1 local mark only — app-owned things (a note turned to-do,
            // demo seeds). A real reminder's done-state is READ-ONLY, mirrored
            // from the Reminders app (ruling 2026-07-25), so it never offers
            // this verb; nothing here writes back to any external record.
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            verbResult = String(localized: "Done")
        case .translate:
            verbResult = nil
            translateText = thing.postText ?? thing.content
            showTranslate = true
        case .showInFiles:
            do {
                // No success line: the Files app is now in front of the
                // person, so a sentence in the sheet behind it is written for
                // nobody. Only the failure has a reader.
                try await HandOff.showInFiles(thing)
                verbResult = nil
            } catch {
                verbResult = error.localizedDescription
                verbResultIsError = true
            }
        case .openAddress(let address):
            // In-app, so there is nothing to report and no way to fail: the
            // card is either on screen or the address was not a watched
            // wallet, and in that second case no disc was ever drawn
            // (`displayName(forStored:)` is the verb's gate). Same silence the
            // `.showInFiles` arm keeps on success, for the same reason — the
            // destination is now in front of the person.
            verbResult = nil
            openAddressCard(address)
        case .edit:
            // The note sheet is the shell's layer, under this sheet, so this
            // one leaves and the editor rises in its place (prd §981).
            verbResult = nil
            let id = thing.id
            dismissWhenSettled { chrome.editNote(id) }
        case .approve:
            // Demo bridge: the decision lands locally; the gateway wire is M5.
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            DSHaptic.success()
            verbResult = "Approved — sent to your gateway"
        case .deny:
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            verbResult = "Denied — your gateway was told"
        }
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}

/// Minimal flow layout for tag chips (wraps like the prototype's flex-wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
