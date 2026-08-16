import SwiftUI
import SwiftData
import Translation

/// The thing sheet (M4, redesigned 2026-07-07 — "Ink with Gallery grafted
/// in", user's pick): ink-black ground, no cards. The source's hue washes
/// down from the top (2026-07-10 ruling — wash + icon, the dot died), an
/// eyebrow (source icon · kind · age), the title large, the thing's media,
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
    /// shelf holds the corpus things that mention it (2026-07-14).
    @State private var relatedTitle = "Related"
    /// Naming a wallet transaction's counterparty (2026-07-15) — the address
    /// being named, and the draft. The label enriches every FUTURE transfer
    /// with that counterparty (CounterpartyLabels).
    @State private var counterpartyTarget: String?
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

    /// The second-encounter naming nudge, when this sheet earns one.
    private var namePrompt: (address: String, count: Int, kind: AddressBook.Kind)? {
        guard !nudgeDeclined else { return nil }
        return AddressNudge.prompt(for: thing, context: modelContext)
    }
    @State private var counterpartyDraft = ""
    /// A post/cast's thread (2026-07-14) — fetched live from the source's
    /// public API when the sheet opens a social thing (Bluesky or Farcaster);
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

        var id: String {
            switch self {
            case .person(let profile): return "person:\(profile.id)"
            case .address(let entry):  return "address:\(entry.id)"
            }
        }
    }
    /// An approval thing's prepare card (prd §112) — the grant's LIVE state,
    /// the fee to revoke, the doors out. Fetched on open like replies; the
    /// section renders only when the check answered.
    @State private var approvalCheck: WalletPrepare.Check?
    @State private var safeCheck: SafeBridge.Check?
    /// The money receipt (prd §369) and what the app says about it. Held in
    /// state rather than computed per body evaluation because the commentary
    /// FETCHES — a merchant board walks that source's rows — and a body can be
    /// re-evaluated many times per open. Recomputed when `safeCheck` answers,
    /// since a Safe receipt's stamp and its signer sentence both read it.
    @State private var moneyReceipt: MoneyReceipt?
    @State private var moneySays: MoneyCommentary?
    /// Mirrors `MoneyActivityDriver.isTracking` for this record, so the control
    /// re-labels itself the moment it is used.
    @State private var tracking = false
    /// The same link, saved earlier from a different source (2026-07-21) —
    /// `CrossSourceEcho` was built for this and briefly wired into a row
    /// anatomy (`ThingRow.swift`) nothing actually rendered, which would
    /// have run its SwiftData fetch on every link row in every feed. Once
    /// per sheet open, like `replies`/`approvalCheck` below, is the honest
    /// place to pay that cost.
    @State private var crossSourceEcho: String?
    /// An Obsidian note's own `[[wikilink]]` targets, resolved against notes
    /// already landed (2026-07-28) — fetched once on open, like `replies`
    /// above. Held as `KeyedThing` (see `ThingRowKeying.swift`) rather than
    /// raw `Thing`s: this is a snapshot taken at `onAppear`, not a live
    /// `@Query`, so a delete-sync heal landing while the sheet is open could
    /// otherwise leave a stale row that traps on read — `liveLinkedNotes`
    /// filters to `.isLive` at render time before anything reads through it.
    @State private var linkedNotes: [KeyedThing] = []
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
    /// The earlier copy of this thing, when there is one (prd §282) — keyed,
    /// not raw, because it is a `Thing` held in `@State` and a heal landing
    /// under this open sheet must never leave the row reading a dead model.
    @State private var keptBefore: KeyedThing?
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

    init(thing: Thing, onBack: (() -> Void)? = nil, inlineRest: Bool = false) {
        self.thing = thing
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
            || !(thing.previewImageURL ?? "").isEmpty
            // Any charted link — token, Kalshi, stock, PostHog metric. This
            // read Token and Stock only, so a KALSHI market has been opening
            // half-height with its verbs below the fold (found 2026-07-27 when
            // the three copies of this chain were folded into ThingChart).
            || ThingChart.kind(for: thing) != nil
            // A quoted post is a card the height of a small paragraph — the
            // same "tall thing" the detent rule was written for, so it opens
            // full-height rather than starting its verbs below the fold.
            || thing.quote != nil
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
                // Sequenced entrance (delight 2026-07-14): the sheet composes
                // itself over the pouring wash — eyebrow, then title, then
                // media, then spec — each a beat behind the last, one-shot.
                HStack(spacing: DS.Space.s3) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .dsGlyph(13)
                                .foregroundStyle(DS.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(DS.fillLine))
                        }
                        .buttonStyle(.plain)
                        .dsHover()
                        .accessibilityLabel(Text("Back"))
                        // A bare chevron: the tooltip names it on Mac with the
                        // same word VoiceOver reads, so the two can't drift.
                        .dsTooltip(String(localized: "Back"))
                    }
                    eyebrow
                }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .settleIn()
                if let parent = thing.parent {
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
                let framedShot = moneyReceipt == nil
                    && (thing.kind == .screenshot
                        || FilesIngest.isStoredPicture(thing.sourceRef))
                if let moneyReceipt {
                    // The subject face is a door (prd §369 amendment): the
                    // history this sheet already draws belongs to that address,
                    // and the gesture people try first is a tap on the face.
                    // The dial keeps its own verbs at parity, so nothing here
                    // is reachable ONLY by tapping a picture.
                    MoneyReceiptCard(receipt: moneyReceipt,
                                     onSubject: openAddressCard)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                        .settleIn(delay: 0.06)
                    // The poisoning flag rides EVERY wallet stage now, not just
                    // Sent/Received — a spoofed-address warning on a Swap or a
                    // Moved leg is exactly as real, and used to be invisible
                    // (those never earned a stage before 2026-07-21, and the
                    // warning only ever rendered inside one).
                    if thing.isFlagged {
                        securityWarning
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                            .settleIn(delay: 0.08)
                    }
                    // What the app has to say about it — a sentence that has
                    // already read the evidence under it. nil is the healthy
                    // answer for most rows (a first transfer, a one-off
                    // merchant), and then the receipt simply stands alone.
                    if let moneySays {
                        MoneyCommentaryCard(commentary: moneySays)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                            .settleIn(delay: 0.1)
                    }
                    // A record still in the machine can be watched from the
                    // lock screen (prd §369 amendment). THE FLAT EDGE EARNS THE
                    // CONTROL: it appears only while `finality == .open`, and
                    // it is the tear that ends it.
                    if moneyReceipt.finality == .open {
                        trackRecordControl(moneyReceipt)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, DS.Space.s3)
                            .settleIn(delay: 0.11)
                    }
                    VerbDial(thing: thing, verbs: walletVerbs,
                             onVerb: runVerb,
                             // A Moved leg's counterparty IS your own watched
                             // wallet — it already has a name (via the Wallet
                             // screen's rename), so the Name disc would just
                             // offer to relabel it through the wrong flow.
                             onName: MovedStage(thing) == nil ? nameCounterpartyAction : nil)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.12)
                    dialResult
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
                    ThingContentView(thing: thing)
                        .shadow(color: DS.cardShadow, radius: 18, y: 10)
                        .padding(.top, DS.Space.s3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if thing.sourceRef != nil { zoomingPhoto = true }
                        }
                        .dsHover()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Opens the photo full screen"))
                        // The picture carries no word saying it's a door, and
                        // on a pointer surface a cursor is the only thing that
                        // can ask. Same sentence as the hint above it.
                        .dsTooltip(String(localized: "Opens the photo full screen"))
                        .settleIn(delay: 0.06)
                    Text(thing.title)
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s2)
                        .settleIn(delay: 0.1)
                    VerbDial(thing: thing, verbs: sheetVerbs,
                             onVerb: runVerb, onName: nil)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.14)
                    dialResult
                } else if socialShape == .person {
                    // A PERSON, not a link to one (prd §363). The title slot
                    // held "@alice started following you" at display size and
                    // the body held a link preview of their profile page; the
                    // face and the handle were on the record the whole time.
                    SocialPersonContent(
                        handle: thing.authorHandle ?? "",
                        displayName: nil,
                        avatarURL: thing.authorAvatarURL,
                        source: thing.source,
                        recent: personPosts,
                        onOpenProfile: {
                            faceTarget = .person(SocialProfile(
                                source: thing.source, handle: thing.authorHandle ?? "",
                                displayName: nil, bio: nil,
                                avatarURL: thing.authorAvatarURL))
                        },
                        onOpenThing: { walkingToNote = KeyedThing($0) })
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                } else if let purchaseReading {
                    // The purchase receipt / watched-product card (prd §364).
                    // It REPLACES the title block for the same reason the Work
                    // receipt does: the headline it draws IS the subject, and
                    // on a receipt that subject is the merchant the title's
                    // own head was already saying.
                    PurchaseStageView(thing: thing, reading: purchaseReading,
                                      recurrence: purchaseRecurrence)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                } else if let workReading {
                    // The Work receipt (2026-08-12) — the §302 ledger's
                    // grammar one category over. It REPLACES the title block
                    // rather than sitting above it: the headline it draws IS
                    // the title, minus the clause the status line is already
                    // saying, so keeping both would print the row twice.
                    WorkStageView(thing: thing, reading: workReading,
                                  detail: WorkStage.statusDetail(
                                    workRow, clause: workReading.statusWord))
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                } else if let agentGrant {
                    // A PERMISSION, not a bookmark (prd §367). The title slot
                    // held "personal · openai/* · read, list" — three facts
                    // joined and clamped at 80 — over a preview card of the
                    // same dashboard every other grant links to, while the
                    // expiry sat on `dueAt` with no route to any screen.
                    AgentGrantView(grant: agentGrant)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                } else if let agentConversation {
                    AgentConversationHead(reading: agentConversation)
                        .padding(.horizontal, DS.Space.s4)
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
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                } else {
                    titleBlock
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
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
                // A note draws NOTHING here (prd §366) and that is the point:
                // the generic content view is where a journal entry's prose was
                // set at `callout15` in `textSecondary` and cut at twelve
                // lines. `noteHead` above sets the same words at `reading20` in
                // primary ink with a real disclosure, so leaving this on would
                // print every entry twice, the second time worse.
                //
                // A GRANT draws nothing here (prd §367): its `content` is the
                // 1Claw dashboard URL — the same string on every grant in the
                // corpus — so the preview card it drew could not tell anyone
                // anything about the grant they opened.
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
                let contentShown = moneyReceipt == nil && !framedShot
                    && socialShape != .person && noteShape == nil
                    && agentShape != .grant && purchaseReading == nil
                    && (isSocialPost || agentShape == .conversation
                    || (!linkOnlyBody && thing.kind != .event
                    && thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        != thing.title.trimmingCharacters(in: .whitespacesAndNewlines)))
                if contentShown {
                    ThingContentView(thing: thing, agent: agentConversation)
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
                if let reception {
                    SocialReceptionCard(reception: reception)
                        .padding(.horizontal, DS.Space.s4)
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
                specTable(contentShown: contentShown, showsWho: moneyReceipt == nil)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .settleIn(delay: 0.18)
                if let check = approvalCheck {
                    ApprovalPrepareCard(thing: thing, check: check)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                }
                if let check = safeCheck {
                    SafeQueueCard(check: check)
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
                if moneyReceipt == nil && !framedShot {
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
                             onVerb: runVerb, onName: nil)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.2)
                    dialResult
                }
                askAboutThis
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
                            walkingToNote = KeyedThing($0)
                        }
                        .padding(.horizontal, DS.Space.s4)
                    }
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
                if !liveLinkedNotes.isEmpty {
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
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
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
                if shape == .entry {
                    sameDayThings = NoteSheetSource
                        .sameDay(as: thing, context: modelContext).keyed
                }
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
            }
            // What points AT this, for every thing rather than only a note
            // (prd §340). Its own fetches are scoped and skipped where they
            // can't answer — a thing with no link and no distinctive title
            // costs nothing here.
            pointingAt = ThingLinksSource.ties(for: thing, context: modelContext)
            // The gate is a string check — non-approval things spend nothing.
            if WalletPrepare.applies(to: thing) {
                Task { approvalCheck = await WalletPrepare.check(for: thing) }
            }
            if SafeBridge.applies(to: thing) {
                Task { safeCheck = await SafeBridge.check(for: thing) }
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
            Text("It rides every future transfer with this address. Blank clears it.")
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
            }
        }
        // Walking a vault's own wikilink graph (2026-07-28) — a plain
        // re-presentation of this same sheet over the linked note.
        .sheet(item: $walkingToNote) { note in
            ThingSheetView(thing: note.thing)
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
    /// display tier altogether for `reading20` — SF Pro Text, REGULAR weight,
    /// open leading.
    ///
    /// That third step is the fix. `heading22` had no upper bound, so a
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
        if isSocialPost {
            let words = postWords
            if words.count > Self.readingLength {
                Text(linkedWords(words))
                    .dsText(.reading20)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Self.readingMeasure, alignment: .leading)
                    // A post's words are what people copy a phrase out of. The
                    // framed-photo title already allowed it; this didn't.
                    .textSelection(.enabled)
            } else {
                Text(linkedWords(words))
                    .dsText(words.count > 100 ? .heading22 : .heading34)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else {
            Text(thing.title)
                .dsText(.heading34).foregroundStyle(DS.textPrimary)
                .textSelection(.enabled)
        }
    }

    /// Past this many characters a post is a paragraph, not a statement, and
    /// is set in `reading20` instead of the display tier. 280 is deliberate:
    /// it's the same length `init` uses to decide the sheet opens full-height,
    /// so a post tall enough to need the whole sheet is exactly the post that
    /// gets read-type — one threshold, two consequences that agree.
    private static let readingLength = 280
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
            if let shape = socialShape, shape != .transcript,
               !authorShortHandle.isEmpty {
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
                        dismissWhenSettled {
                            if let url = URL(string: "casberi://feed/source/\(sourcePathComponent)") {
                                openURL(url)
                            }
                        }
                    } label: {
                        sourceLine
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                faceTarget = .person(SocialProfile(
                    source: thing.source, handle: thing.authorHandle ?? "",
                    displayName: nil, bio: nil, avatarURL: thing.authorAvatarURL))
            } label: {
                faceMark
            }
            .buttonStyle(.plain)
            .dsHover()
            // A bare face: the only control here with no word in it.
            .accessibilityLabel(Text("Open profile"))
            .dsTooltip(String(localized: "Open profile"))
        } else {
            faceMark
        }
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
            Text("\(thing.kind.typeTag) · \(shortTime(thing.capturedAt)) ago")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    /// `thing.source` as a URL path component — a source name can carry
    /// spaces ("Apple Music", "iCloud Mail"), so the eyebrow's door needs
    /// this before handing it to `casberi://feed/source/…`.
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

    // MARK: - The note anatomies (prd §366)

    /// Which of the three note anatomies this thing wears, or nil for none.
    /// A DATA test — does the record quote somebody else's work, and is its
    /// title a name the person gave it or a line we cut out of its own body.
    private var noteShape: NoteSheet.Shape? {
        NoteSheetSource.shape(for: thing)
    }

    /// The head each shape leads with, in place of the title block.
    @ViewBuilder
    private func noteHead(_ shape: NoteSheet.Shape) -> some View {
        let tags = NoteSheetSource.tags(for: thing)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            switch shape {
            case .entry:
                NoteDateline(dateline: NoteSheet.dateline(
                    thing.capturedAt, act: NoteSheetSource.act(for: thing), now: .now))
                // A voice note's words belong to its recording, and
                // `VoiceContent` below draws the two together — player, real
                // amplitude envelope, transcript. Setting the transcript here
                // as well would print it twice and separate it from the audio
                // it transcribes.
                if thing.kind != .voice {
                    NoteProse(text: NoteSheetSource.body(for: thing).text)
                }
            case .note:
                // A vault note's title IS a name the person chose, so unlike
                // an entry's it leads and is not a repetition of anything.
                Text(thing.title)
                    .dsText(.heading28)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                NoteProse(text: NoteSheetSource.body(for: thing).text)
            case .passage:
                NotePassageContent(
                    passage: NoteSheetSource.passage(for: thing),
                    citation: NoteSheetSource.citation(for: thing) ?? thing.source,
                    locator: thing.summary)
            }
            if !tags.isEmpty {
                NoteTagRow(tags: tags)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @ViewBuilder
    private func specTable(contentShown: Bool, showsWho: Bool = true) -> some View {
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
        // A 1Claw grant's `content` is the dashboard root — the same URL on
        // every grant in the corpus (prd §367), so "Site: 1claw.xyz" is a row
        // that is true of the seat and says nothing about the thing. The dial's
        // Open disc already goes there.
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
        let hasLanded = isWork
        let hasEcho = crossSourceEcho != nil
        let hasAgent = thing.provenance.agent != nil
        // "From" stands down where the reception block's own sentence already
        // says where this came from (prd §363) — and it says it better, in
        // words rather than behind an 80pt label column. Gated on the block
        // having actually composed a sentence, never on the shape alone: a
        // social thing whose reception is nil (nothing honest to say) keeps
        // the row it always had rather than losing the fact entirely.
        // …and "From: in your things", the row that says nothing, on every
        // Work sheet in the app. The eyebrow already names the source.
        // …and "From: written by you", which was the ENTIRE spec table on
        // every note in the corpus (prd §366) — one row, behind an 80pt label
        // column, saying less than the eyebrow directly above it. Same gate as
        // the social one and for the same reason: the note reception block has
        // to have actually composed a sentence, or the fact is lost rather
        // than moved.
        // …and on every purchase and watched product (prd §364), where the
        // card above ends on a sentence saying exactly where this came from —
        // and saying the TRUE one per seat, which this row could not: it read
        // "from a store you follow" over a deal (which comes from a feed
        // publisher) and over a barcode scan (which came from your own hand).
        // …and on an agent sheet (prd §367): a conversation's receipt ends on
        // "From your ChatGPT export", and a grant's own card says which vault
        // it is in. "From — from your session" was this table's whole
        // contribution to a chat, and it is the phrase the user called a
        // database field.
        let hasFrom = showsWho && !isWork && purchaseReading == nil
            && agentShape == nil
            && reception?.provenance == nil
            && noteReception?.provenance == nil
        let hasCounterparty = showsWho && thing.source == "Wallet"
            && !(thing.counterpartyAddress ?? "").isEmpty
        let anyRow = hasSite || hasEcho || hasAgent || hasFrom
            || hasCounterparty || hasLanded

        if anyRow {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
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
                    specRow("Also", "Saved from \(crossSourceEcho)")
                }
                // "You wrote · Linked on X, Apr 2019" retired here 2026-08-08
                // (prd §340): the read is unchanged and better placed. It named
                // only the EARLIEST post carrying this link and could not be
                // tapped; the "Points at this" shelf below lists every one of
                // them and walks into it.
                if hasAgent, let agent = thing.provenance.agent {
                    specRow("By", "\(agent)\(thing.provenance.machine.map { " on \($0)" } ?? "")")
                }
                // "From" (2026-07-23): only off a stage layout now — a stage
                // already depicts both parties, so "in your wallet" here was
                // the redundant row (user: "one-row table saying nothing").
                if hasFrom {
                    specRow("From", PlaceWords.line(for: thing))
                }
                // A wallet transfer's counterparty — the other side of the
                // trade, nameable ("this is Mom"). Only when the hex was
                // captured (native sends have none) (2026-07-15).
                if hasCounterparty, let cp = thing.counterpartyAddress {
                    counterpartyRow(cp)
                }
            }
            // One quiet card (2026-07-13 polish): the bare rows floated in
            // the sheet's field; the same faint fill the link preview wears
            // gathers them into one readable spec block.
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(LocalizedStringKey(label))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 80, alignment: .leading)
            // Callout, not body — the values were the loudest type on the
            // sheet ("saved by you" outweighed the title's own facts).
            Text(LocalizedStringKey(value))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// The counterparty's name (yours if set, else a known contract / watched
    /// handle, else the short hex) with a pencil — tap to name it. What you name
    /// it here rides every future transfer with this address.
    private func counterpartyRow(_ address: String) -> some View {
        Button {
            nameCounterpartyAction?()   // the one entry into the naming flow
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Who")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .frame(width: 80, alignment: .leading)
                Text(WalletIngest.knownLabel(for: address) ?? WalletStore.shortAddress(address))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Image(systemName: "square.and.pencil")
                    .accessibilityHidden(true)
                    .dsGlyph(12, weight: .regular)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.leading, DS.Space.s2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // No tooltip: the row already says "Who" and shows the name, so the
        // pencil is never the only thing a cursor has to go on.
        .dsHover()
    }

    // MARK: - The dial's wiring (stage sheets — B1, 2026-07-16)

    /// The safety flag(s) on this transfer, as a real alert BANNER on the
    /// detail screen (2026-07-23; user: the screen read as "vibe coded").
    /// §160's "a one-line flag, not a card" rule was written for the FEED,
    /// where the warning is a heads-up you scroll past; here it's the whole
    /// reason you tapped in, and a thin red line under the amount lost that
    /// fight to a routine "Name this address?" card sitting right below it.
    /// A tinted red panel with the triangle gives the danger the weight the
    /// screen's own hierarchy owes it — and fills the dead space the sheet
    /// used to leave below the fold. A transfer can wear more than one flag
    /// (a lookalike address sending a lookalike token is one scam, but each
    /// half needs saying), so each is its own line inside the one banner.
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
        .padding(DS.Space.s3)
        .background(DS.destructive.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
                .dsGlyph(15)
                .foregroundStyle(DS.destructive)
            Text(text)
                .dsText(.callout15).foregroundStyle(DS.destructive)
                .fixedSize(horizontal: false, vertical: true)
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
    /// ("Settled", "Deal") must not be read by the other's table. The whole
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
    /// anatomy. Cursor is the case that matters — its runs are in the Agents
    /// category and are drawn by the Work receipt, which is right, and asking
    /// this first would take that away from them.
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

    private var agentGrant: AgentSheet.Grant? {
        guard agentShape == .grant else { return nil }
        return AgentSheetSource.grant(for: thing)
    }

    /// The primitives `WorkStage` reads. Built once so the reading and the
    /// clause detail below can't be derived from two different snapshots.
    private var workRow: WorkStage.Row {
        WorkStage.Row(source: thing.source,
                      sourceRef: thing.sourceRef,
                      title: thing.title,
                      tags: thing.tags,
                      mark: thing.mark.rawValue,
                      projectField: thing.authorHandle,
                      hasPrice: thing.priceValue != nil && thing.priceCurrency != nil)
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
        if let url = Capture.detectURL(in: thing.content) {
            out.append(Verb(label: Self.explorerLabel(url), icon: "arrow.up.right",
                            action: .openURL(url)))
        }
        out.append(Verb(label: "Copy link", icon: "doc.on.doc", action: .copyText))
        return out
    }

    /// "Etherscan" from `etherscan.io`, "mempool" from `mempool.space`. Falls
    /// back to the generic word rather than inventing a name for a host we
    /// don't recognize — a disc reading "Explorer" is honest everywhere.
    static func explorerLabel(_ url: URL) -> String {
        let host = (url.host() ?? "").lowercased()
            .replacingOccurrences(of: "www.", with: "")
        let known = ["etherscan.io": "Etherscan", "basescan.org": "Basescan",
                     "gnosisscan.io": "Gnosisscan", "optimistic.etherscan.io": "Etherscan",
                     "mempool.space": "mempool", "solscan.io": "Solscan",
                     "app.0xbow.io": "0xBow", "app.safe.global": "Safe",
                     "app.morpho.org": "Morpho", "app.hyperliquid.xyz": "Hyperliquid"]
        if let name = known[host] { return name }
        return String(localized: "Explorer")
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
    /// several fillers now — a Reddit post's first outbound body link, a TikTok
    /// row's video link, a Cal.com meeting URL, a Snapchat memory's download
    /// link — and a Reddit row must never grow a listen verb. For these two
    /// feed sources it has exactly ONE writer (`FeedFollowBridges` and
    /// `RSSIngest` both fill it only from `item.mediaURL`), which is what makes
    /// the field's meaning unambiguous here and nowhere else. RSS is in because
    /// a podcast followed through the generic feed door is the same episode
    /// wearing a different seat; Reddit, YouTube and Substack ride the same
    /// ingest and are out.
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

    /// The dial's verbs: derivation, plus the episode hand-off derivation can't
    /// gate (above). FIRST, on the Obsidian ruling — for an episode the file is
    /// the strongest thing you can do with the row, and the page below it is the
    /// notes — and re-capped at four, so adding one can never turn a sheet into
    /// a menu; the verb that loses is the last derivation ranked, not this one.
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
        }
        let extras = [joinVerb, episodeVerb].compactMap { $0 }
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
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: tracking ? "bell.badge.slash" : "bell.badge")
                        .accessibilityHidden(true)
                        .dsGlyph(14, weight: .regular)
                    Text(tracking
                         ? "Stop watching it"
                         : "Watch it from the lock screen")
                        .dsText(.label12)
                }
                .foregroundStyle(tracking ? DS.textTertiary : DS.textPrimary)
                .padding(.horizontal, DS.Space.s3)
                .frame(minHeight: 32)
                .background(DS.fillFaint, in: Capsule(style: .continuous))
            }
            .buttonStyle(PressSpring())
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

    /// The verb outcome, honesty-styled — ONE text both layouts place, so a
    /// bridge's no reads the same wherever the verb lived.
    @ViewBuilder private var verbOutcome: some View {
        if let verbResult {
            Text(verbResult)
                .dsText(.subhead13)
                .foregroundStyle(verbResultIsError ? DS.attention : DS.confirm)
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
    private func copyAsContext() {
        guard thing.isLive else { return }
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 300   // the shelf's own window
        let corpus = ((try? modelContext.fetch(descriptor)) ?? []).filter(\.isLive)
        let related = RelatedThings.neighbours(of: thing, in: corpus)
        DSPasteboard.copy(AgentContext.render(thing, related: related))
        verbResult = String(localized: "Copied as context")
        verbResultIsError = false
    }

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
    @ViewBuilder
    private var askAboutThis: some View {
        if thing.isLive {
            let subject = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !subject.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    Button {
                        DSHaptic.tap()
                        // Dismiss first: the composer rises over the shell, and
                        // a sheet still up would sit between them.
                        dismiss()
                        chrome.ask("What else do I have about \(subject)?",
                                   withKey: AgentKey.isConfigured)
                    } label: {
                        Chip(text: AgentKey.active.map {
                                String(localized: "Ask \($0.agent) about this")
                             } ?? String(localized: "Ask about this"),
                             style: .neutral, glyph: "sparkles")
                    }
                    .buttonStyle(.plain)
                    // The door for every agent this app will never have an API
                    // for (2026-08-06, `AgentContext`) — a browser chat, a
                    // terminal agent, whatever shipped last week. No key, no
                    // network, no provider list.
                    Button {
                        DSHaptic.tap()
                        copyAsContext()
                    } label: {
                        Chip(text: "Copy as context", style: .neutral, glyph: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    // PIN (2026-08-10). A chip and not a disc, on the rule the
                    // dial already states: it is capped at four so that adding
                    // a verb can never turn a sheet into a menu, and a fifth
                    // disc would evict a derived verb that is more specific to
                    // this row than pinning is. It belongs in the sheet as well
                    // as the row's long-press because reading a thing is when
                    // you learn it is worth keeping.
                    Button {
                        DSHaptic.tap()
                        let pinned = Pinboard.toggle(thing)
                        chrome.pinPulse += 1
                        verbResult = pinned ? String(localized: "Pinned")
                                            : String(localized: "Unpinned")
                        verbResultIsError = false
                    } label: {
                        Chip(text: Pinboard.isPinned(thing)
                                ? String(localized: "Unpin")
                                : String(localized: "Pin"),
                             style: .neutral,
                             glyph: Pinboard.isPinned(thing) ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, DS.Space.s4)
            }
        }
    }

    // MARK: - Note links (a vault's own wikilink graph, 2026-07-28)

    /// `linkedNotes` filtered to still-live models, read ONCE at the top —
    /// the corollary-2 guard (see `ThingRowKeying.swift`): a delete-sync
    /// heal landing while this sheet is open must not leave the `ForEach`
    /// below reading a stored property off a tombstoned model.
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
                            .dsGlyph(11)
                            .foregroundStyle(DS.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tie.title)
                                .dsText(.callout15)
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
                .buttonStyle(.plain)
                .dsHover()
            }
        }
    }

    /// Walks into a tie's real row. Resolved at TAP time, not held — and a row
    /// deleted since the shelf was drawn simply doesn't open, rather than
    /// opening a sheet over a tombstone.
    private func walkTo(_ tie: ThingLinks.Tie) {
        guard let target = ThingLinksSource.resolve(tie, context: modelContext) else { return }
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
                        walkingToNote = note
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: icon)
                                .accessibilityHidden(true)
                                .dsGlyph(11)
                                .foregroundStyle(DS.textTertiary)
                            Text(linked.title)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                }
            }
        }
    }

    // MARK: - Related shelf (streams last)

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            factRows
            keptBeforeRow
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
                        .dsGlyph(11)
                        .foregroundStyle(DS.textTertiary)
                    Text("\(fact.label) · \(fact.date.formatted(date: .abbreviated, time: .shortened))")
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
            .padding(.horizontal, DS.Space.s4)
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
                walkingToNote = earlier
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .accessibilityHidden(true)
                        .dsGlyph(11)
                        .foregroundStyle(DS.textTertiary)
                    Text("You kept this \(copy.capturedAt.formatted(.relative(presentation: .named))) · \(copy.source)")
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
    }

    private func streamRelated() {
        // A thing that can't have related items costs no fetch. A watched token
        // has mentions and a tagged thing has overlap — the old invariant — and
        // since 2026-08-02 an EMBEDDED thing has neighbours, which is most of
        // the corpus once the sweep has run. That third arm is the fix for a
        // real gap: a note or screenshot with no tags got no shelf at all, even
        // though its vector could always have found company.
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let myTags = Set(thing.tags).subtracting(typeTags)
        let isToken = thing.source == "Tokens"
        let isEmbedded = thing.embedding.map { !$0.isEmpty } ?? false
        guard isToken || !myTags.isEmpty || isEmbedded else { return }

        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300   // relatedness lives in the recent past
        let all = (try? modelContext.fetch(descriptor)) ?? []

        // Have you kept this exact thing before? Deterministic, and asked over
        // the same fetch — so the answer costs nothing extra.
        if let earlier = RelatedThings.keptBefore(thing, in: all) {
            keptBefore = KeyedThing(earlier)
        }

        // A watched token's relatedness is MENTION, not tags (2026-07-14) —
        // every watchlist thing shares the Watchlist tag, so tag overlap only
        // ever surfaced the other watched tokens. The saves, chats, and
        // screenshots that name this token answer the question a watchlist
        // can't: why am I watching this? Tag overlap stays as the fallback.
        let mentions = isToken ? tokenMentions(in: all) : []
        let related: [Thing]
        if !mentions.isEmpty {
            relatedTitle = "In your things"
            related = mentions
        } else {
            // Meaning first (2026-07-14): rank the recent corpus by semantic
            // similarity to this thing, so a GitHub PR reaches the Linear
            // ticket, the chat, the note that share NO tag — the cross-source
            // weaving tag overlap can't find (a feed tag like "Stars" only ever
            // reaches other GitHub things). Tag overlap stays the fallback when
            // the on-device embedding is unavailable or this thing isn't
            // embedded yet — and where there are no tags either, the shelf
            // simply stays empty, as it did before it could be reached at all.
            let near = RelatedThings.neighbours(of: thing, in: all)
            related = near.isEmpty
                ? Array(all.filter { other in
                    other.isLive && other.id != thing.id
                        && !myTags.isEmpty && !myTags.isDisjoint(with: other.tags)
                }.prefix(6))
                : near
        }
        guard !related.isEmpty else { return }

        var doc = ["root = Shelf([\(related.indices.map { "c\($0)" }.joined(separator: ", "))])"]
        for (i, t) in related.enumerated() {
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
        guard thing.source == "Tokens" else { return [] }
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
            guard other.id != thing.id, other.source != "Tokens" else { return false }
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
            verbResult = "Copied"
        case .markDone:
            // Rung-1 local mark only — app-owned things (a note turned to-do,
            // demo seeds). A real reminder's done-state is READ-ONLY, mirrored
            // from the Reminders app (ruling 2026-07-25), so it never offers
            // this verb; nothing here writes back to any external record.
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            verbResult = "Done"
        case .translate:
            verbResult = nil
            translateText = thing.postText ?? thing.content
            showTranslate = true
        case .viewImage:
            verbResult = nil
            zoomingPhoto = true
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
