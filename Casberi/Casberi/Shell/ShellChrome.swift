import SwiftUI
import Observation

/// Shell chrome state — scrolling down minimizes the bottom bar (labels fold,
/// the glass tightens); scrolling up blooms it back. Chrome yields to content;
/// the glass visibly reforms (iOS 26 grammar).
@Observable
final class ShellChrome {
    /// Read by `AgentBar` (its words fold, the glass hugs its two controls) and
    /// by `SourceChips` + the strip's top padding (56→48 chips, s6→s2 of air).
    ///
    /// This was written by every feed page and read by NOBODY from the day the
    /// tab bar it was built for was dropped (2026-07-13) until 2026-07-30 — the
    /// doc comment above described a behaviour the app hadn't had in months,
    /// while each page still paid for the scroll observer that computed it.
    var minimized = false
    /// When `minimized` last flipped — see `minimizesChrome`'s settle window.
    /// Observation-ignored on purpose: it is written from a scroll callback,
    /// and an observable write there would invalidate every reader of this
    /// object on every fold.
    @ObservationIgnored var chromeSettledAt: TimeInterval = 0

    /// The one transient message surface — the glass toast above the bar.
    /// Any screen can flash an outcome ("On your list", "Copied", a denial);
    /// the shell renders it, so feedback looks the same everywhere.
    var toast: String?
    /// An optional action riding the toast ("Undo" on a drop-capture). Cleared
    /// with the toast.
    var toastAction: ToastAction?

    struct ToastAction {
        let label: String
        let run: () -> Void
    }

    /// The capture flight (§1 polish): a proxy card flies from the capture
    /// point to the Feed tab. RootShell renders it; saves set it.
    struct Flight: Identifiable {
        let id = UUID()
        let kind: ThingKind
        let title: String
    }
    var flight: Flight?

    /// The "All" chip's frame in global space, reported by SourceChips so the
    /// flight knows where to land.
    var feedTabFrame: CGRect = .zero

    /// Bumped when the active chip is tapped again — the surface pops
    /// everything (pushed screens, sheets) back to its root (the tab era's
    /// "re-tap to pop" habit, now the "re-tap the active chip" habit).
    /// **WHICH FOLDER IS OPEN (prd §591 amendment, 2026-09-03, user: "maybe
    /// you should be able to tap the active category chip to make the second
    /// row go away, so that it really behaves like a dock" — "with folders").**
    ///
    /// A chip in the dock is a folder and the row above the strip is what is
    /// inside it: a category's venue switcher and face rail, or — for the
    /// octopus, which is the dock's first chip — the four doors that are not a
    /// feed. One row, one folder, so the two can never stack.
    ///
    /// **A FOLDER TAP DOES NOT CHANGE THE ROOM (user, 2026-09-03: "if you tap
    /// a folder on mac dock for example it doesn't switch what is on your
    /// screen").** Tapping a category chip opens its sources above the strip
    /// and leaves the feed exactly where it was; tapping it again closes them;
    /// only picking one of those sources moves you. "All" is not a folder and
    /// still switches on its own tap, because there is nothing inside it to
    /// open.
    ///
    /// I argued for the opposite first — that a category chip is a room you
    /// have been in and the app already knows which venue (§351's landing
    /// rule), so making you re-pick costs a tap and throws that knowledge away.
    /// The user's answer is the one recorded above, twice, and it is the
    /// stronger reading of the metaphor the whole dock is built on: a folder
    /// that launches something when you open it is not a folder.
    ///
    /// **The room's own folder OPENS ON ARRIVAL and closes on a re-tap.** The first cut
    /// defaulted closed, reasoning that a folded chip already wears its active
    /// venue's mark (§351) so the row was a picker rather than a label. A
    /// second session's user read the missing switcher as the app being broken,
    /// and the user's own correction settled it: *"you can't get to kalshi
    /// without first tapping markets anyways"* — the tap that takes you into a
    /// category is the tap that shows its contents, so nobody reaches a venue
    /// without having seen the row it lives in. `MainSurface` resets this to
    /// `.room` on every source change; only a deliberate re-tap on the chip you
    /// are standing on closes it, and only until you leave.
    ///
    /// **§357 is NOT overturned** — it is enforced one level up, in
    /// `MainSurface.roomControlsShown`: a live person scope forces the room's
    /// row open whatever this says, because a filter you are standing in must
    /// show you that you are in it and must show its own exit.
    enum OpenFolder: Equatable {
        /// A category's own sources, by category name. The row shows THAT
        /// category's venues whether or not you are standing in it, which is
        /// what makes a folder a folder: you can look inside Social from
        /// Kalshi without leaving Kalshi.
        case category(String)
        /// The octopus's four doors (`DoorsStrip`).
        case doors
    }

    var openFolder: OpenFolder? = nil

    var popHome = 0


    /// Which watched wallet the Wallet CATEGORY is scoped to — nil = all of
    /// them (prd §356, 2026-08-11). Holds the RESOLVED-or-watched spelling the
    /// user's own list carries; matched through `WalletStore.scopeMatches`,
    /// never a raw compare (things are stamped with resolved hex while the
    /// scope is the watched spelling).
    ///
    /// **It lives here rather than on `FeedScreen` because it has to survive a
    /// room change.** `MainSurface` renders one `FeedScreen(source:)` carrying
    /// `.id(filter.source)`, so every move between Wallets / Peer / Privacy
    /// Pools / Gnosis Pay / Railgun DESTROYS the screen and its `@State` with
    /// it — which is exactly why scoping used to be possible in the balance
    /// room alone and evaporated the moment you left it. A scope is a property
    /// of the category, not of one room in it.
    ///
    /// Cleared when the watched list can no longer honour it (a scoped wallet
    /// removed, or the list falling back to one) — a scope pointing at a gone
    /// wallet is a feed with no rows and no way to explain itself.
    var walletScope: String?

    /// Which READING of the wallet room is on screen (prd §483, 2026-08-26) —
    /// nil until the room resolves one, then whatever was last picked.
    ///
    /// **Here rather than on `FeedScreen` for `walletScope`'s reason exactly**:
    /// the screen carries `.id(filter.source)`, so its `@State` dies on every
    /// room change, and the control that sets this is shell-mounted (§357) so
    /// it would outlive the state it drives. The two properties are separate
    /// because they answer different questions — `walletScope` is WHOSE money,
    /// this is WHICH reading of it — and either can change without the other.
    ///
    /// **It is NOT persisted across launches, unlike `MarketsRoom.landing`.**
    /// That room remembers because its venues are separate watchlists and
    /// reopening on Tokens for somebody who lives in Kalshi costs a tap on the
    /// very first tap. These are facets of ONE subject and `activity` is the
    /// room's front door — every other room in this app opens on its feed, and
    /// a wallet that reopened on Permissions three days after you last looked
    /// at an approval would be answering a question nobody asked.
    ///
    /// Not cleared on a room change on purpose: the wallet CATEGORY spans
    /// several rooms (§356) and a reading survives moving between them, the
    /// same span `walletScope` keeps. `WalletSection.resolve` handles the case
    /// where the remembered scope's content has since gone.
    var walletSection: WalletSection?

    /// Which scopes the wallet room currently HAS something for, published by
    /// that room and read by the shell-mounted switcher (prd §483).
    ///
    /// **The shell cannot compute this and must not try.** Presence is decided
    /// by `GenStream` contents, `WalletLiveState` and the NFT shelf — all of
    /// them `FeedScreen`'s, none of them reachable from here. So the room
    /// publishes and the control consumes, exactly the way `marketVenues`
    /// carries the Markets fold's membership up to the same inset.
    ///
    /// It doubles as the switcher's own GATE: only the wallet room ever writes
    /// it and it is cleared on the way out, so the toggle cannot appear over a
    /// Vibenet- or Social-scoped room by mistake — a rule that holds by
    /// construction rather than by a source-name test in two files that could
    /// drift apart.
    var walletSections: [WalletSection] = []

    /// Which of those scopes hold something that wants answering — the dot on
    /// the strip. Published beside `walletSections` for the same reason and
    /// cleared with it.
    var walletSectionAttention: Set<WalletSection> = []

    /// The vibenet room's scope, and the two lists behind its switcher (prd
    /// §482, 2026-08-26) — `walletSection`'s trio one room over, deliberately
    /// SEPARATE properties rather than a shared generic pair.
    ///
    /// **Why not one `sections: [any DSSectionScope]`.** The two rooms publish
    /// different enums and only one of them may draw at a time; separate
    /// properties make "these can never both be non-empty" a thing the gates
    /// enforce by construction, where a shared list would need a discriminator
    /// and a cast at the mount point. It also keeps each room's clear-on-exit
    /// honest: whoever writes it owns it.
    ///
    /// Same lifetime rules as Wallet's, for the same reasons: the scope
    /// survives a room change within the category, `VibenetSection.resolve`
    /// handles a remembered scope whose content has since gone, and neither
    /// persists across launches — these are facets of one subject, and Holdings
    /// is the front door (§482).
    /// The Hegotá room's scope, the two lists behind its switcher, and which
    /// account its rail has scoped to.
    ///
    /// **Shell-held, exactly as Wallet's and vibenet's are** — because the
    /// figure, the rail and the switcher are three separate sections of the
    /// room rather than children of one card, and three sections cannot share
    /// a card's `@State`. Holding it in the card was what left this room's
    /// rails carrying the card's padding instead of the room's.
    var hegotaSection: HegotaSection?
    var hegotaSections: [HegotaSection] = []
    var hegotaScope: String?

    /// The Frames devnet room's scope, held on the SHELL rather than the card
    /// for `hegotaSection`'s reason one chain over: the figure, the rail and
    /// the switcher are three sections of the room rather than children of one
    /// card, and three sections cannot share a card's `@State`.
    var framesSection: FramesSection?
    var framesSections: [FramesSection] = []
    var framesScope: String?

    /// The Ethrex Privacy room's scope strip and face-rail pick (prd §593).
    /// Held here rather than on the screen for §357's reason: the room is
    /// rendered under an `.id(filter.source)`, so anything mounted on it dies
    /// with every room change — and a control that outlives the interaction it
    /// drives belongs on the shell.
    var privacyDevnetSections: [PrivacyDevnetSection] = []
    var privacyDevnetScope: String?
    var privacyDevnetSection: PrivacyDevnetSection?

    var vibenetSection: VibenetSection?

    /// Which scopes the vibenet room currently HAS something for. The shell
    /// cannot compute this — presence needs the composed `VibenetRoom` and the
    /// landed event rows, neither reachable from here — so the room publishes
    /// and the control consumes. Doubles as the switcher's GATE: only that room
    /// writes it and it clears on the way out, so this and `walletSections`
    /// cannot both be non-empty.
    var vibenetSections: [VibenetSection] = []

    /// Which of those wear a dot — `VibenetAttention`'s ranking, one layer
    /// down (see `VibenetSection.attention`). Published beside
    /// `vibenetSections` and cleared with it.
    var vibenetSectionAttention: Set<VibenetSection> = []

    /// The Privacy Pools room's scope (prd §486, 2026-08-26) — Wallet's and
    /// Vibenet's third instance, and the smallest: ONE property rather than a
    /// trio, because that room's card draws its own strip and derives its own
    /// presence from the composed room. There is no shell-mounted control to
    /// feed, so a published list and attention set would be state nothing ever
    /// reads.
    ///
    /// Same lifetime rules as the other two: not persisted across launches
    /// (`activity` is the front door, and every room in this app opens on its
    /// feed), not cleared on a room change (the wallet category spans several
    /// rooms and a reading survives moving between them), and
    /// `PrivacyPoolsSection.resolve` handles a remembered scope whose content
    /// has since gone.
    var privacyPoolsSection: PrivacyPoolsSection?

    /// Which watched account a SOCIAL room is scoped to — nil = all of them
    /// (prd §362, 2026-08-11). The handle as the account's own store spells it
    /// (`SocialAccount.key`), matched against `Thing.authorHandle`.
    ///
    /// **It lives here for the same reason `walletScope` does and clears for the
    /// opposite one.** Here because `FeedScreen` is destroyed on every room
    /// change (`.id(filter.source)`), so a scope held in its `@State` cannot
    /// survive the shell-mounted rail that sets it. Cleared on every source
    /// change — unlike the wallet scope, which spans its whole category —
    /// because a person belongs to ONE network: a Farcaster handle carried into
    /// the Bluesky room matches no row there, and the room would render empty
    /// with nothing on screen able to explain why. Your wallets are the same
    /// wallets in every Wallet room; @dwr is not on Bluesky.
    var personScope: String?

    /// The vibenet room's scoped account, or nil for all of them
    /// (2026-08-23) — its own property rather than reusing `walletScope`,
    /// because these are two different address SETS and sharing one
    /// would mean a wallet pick silently scoping the vibenet room to an
    /// address it has never heard of.
    var vibenetScope: String?

    /// Who has posted in the room you're looking at since you last opened it —
    /// the face rail's attention ring (prd §362).
    ///
    /// Published BY `FeedScreen` and read by the shell, which is the inverse of
    /// how the rail's membership flows (the shell reads the social stores
    /// directly). The split is deliberate: membership must be on screen in the
    /// first frame, so it comes from a synchronous store read, while the ring is
    /// a fact about the CORPUS measured against this room's own last-visit stamp
    /// — both of which live in the feed. A ring that is one frame late is a ring
    /// that is late; a rail that is one frame late is a rail that blinks.
    var freshHandles: Set<String> = []

    /// A person's own room, asked for from outside the feed (prd §362). Set by
    /// re-tapping the lit face in the social rail — which lives on the shell,
    /// while the destination it wants lives on `FeedScreen`.
    ///
    /// It takes this hop rather than the rail pushing for itself, and NOT for
    /// the usual "the shell owns the stack" reason: `RootShell` can already
    /// present a person, but it presents `SocialProfileCard` — the quick-glance
    /// tray — where the roster has always pushed the fuller `PersonRoomScreen`.
    /// Routing through the nearest available presenter would have silently
    /// downgraded the one door this change had to keep intact, so the request
    /// goes to the screen that owns the right destination.
    var personRequest: SocialProfile?

    /// The crown pour's hue override (prd §159, 2026-07-21). nil = Casberi's
    /// own tint, the permanent field; the Wallet feed sets a scoped wallet's
    /// face tint here while you stand in that wallet, so the whole crown —
    /// chips included — re-tints to the identity you're inside. Written by
    /// the active feed page, rendered by MainSurface; always reset by the
    /// next page's landing, so a stale hue can't outlive its room.
    var pourHue: Color?

    /// How much of the crown pour this room actually gets (prd §297,
    /// 2026-08-03, user: "would the app also be better without the crown pour
    /// on the source feeds? i want it to look sleek").
    ///
    /// The pour is ONE owned colour everywhere (§159, §204), which is exactly
    /// what makes it identity on the rooms that are yours — All, and a wallet
    /// you're standing inside, where it re-tints to that wallet's own face. On
    /// a SOURCE room it is the one thing on screen saying nothing: the room
    /// belongs to Bluesky or Photos or Files, its identity already lives in the
    /// chip and the icon (the 2026-07-18 full-ink ruling that killed the
    /// per-source wash), and a permanent 500pt field over it is the borrowed
    /// decoration that ruling removed, wearing our colour instead of theirs.
    ///
    /// So it drains to nothing there and comes back when you return — which
    /// also gives the pager something it never had: the crown breathing out as
    /// you leave home and back in as you arrive. Written by the active feed
    /// page's landing beside `pourHue`, so the two can never disagree.
    var pourDose: Double = 1

    /// Which rooms keep the pour — the rule, next to the reasoning above.
    ///
    /// It lives here rather than at the write site in `FeedScreen.land()`
    /// because the doc IS the rule: a predicate one file away from the fifteen
    /// lines explaining it is a predicate the next person edits without ever
    /// reading them. Deliberately NOT derived from `FeedScreen.Shape`, which
    /// looks like the same question and isn't — that's a row-RENDERING
    /// taxonomy (it folds Cal.com and Calendly together, Farcaster and
    /// Bluesky together), and hanging the crown off it would mean a future
    /// rendering merge silently moved the pour.
    ///
    /// "You" — your own notes and voice — is a source room and takes the
    /// drain, on purpose. It reads as an exception to "the rooms that are
    /// yours", but it wears its own chip in the strip exactly like Photos or
    /// Files, and the pour is the HOME field: All is where it belongs.
    static func pourDose(for source: String) -> Double {
        source == "All" || source == "Wallet" ? 1 : 0
    }

    /// A surface asked the composer to run an ask (the weekend cover's week
    /// synthesis, prd 54) — RootShell opens the bubble on set; the composer
    /// consumes the query and sends it through the real answer path.
    var askRequest: String?
    /// The requested ask should run on the person's own key, not just on
    /// device (2026-08-06). Consumed by the composer alongside `askRequest`,
    /// which sets its existing `pendingKeyedFollowUp` — so the free on-device
    /// answer still runs first and the keyed one follows it, exactly as a tap
    /// on "Ask <agent>" already behaves. A surface asking for a keyed answer
    /// is asking for the same arc, not a different one.
    ///
    /// Reset by the composer on consumption so a later plain `ask` can never
    /// inherit somebody else's request to spend money.
    var askWithKey = false
    /// Prior turns to CARRY IN before the keyed answer runs (2026-08-20) — an
    /// imported conversation being picked back up, so a follow-up lands in the
    /// chat it belongs to rather than in an empty one.
    ///
    /// Consumed by `RootShell.keyedAnswerDocument`, which is the only place a
    /// keyed answer is composed and therefore the only place `keyedHistory` can
    /// be seeded exactly once. Emptied on consumption for the same reason
    /// `askWithKey` is: one surface's request to spend must never be inherited
    /// by the next question somebody types.
    var askSeedHistory: [AgentTurn] = []
    /// What to tell the model about the conversation it is joining — that it is
    /// mid-conversation, and (when true) that the transcript is clamped. Kept
    /// beside the turns rather than derived from them, because the fact that
    /// turns are MISSING cannot be recovered from the turns that survived.
    var askSeedSystem: String?
    func ask(_ query: String, withKey: Bool = false,
             seedHistory: [AgentTurn] = [], seedSystem: String? = nil) {
        askRequest = query
        askWithKey = withKey
        askSeedHistory = seedHistory
        askSeedSystem = seedSystem
    }

    /// The agent rose to be TYPED IN, not to deliver something (2026-07-30) —
    /// set by the bar's magnifier, consumed by the composer, which focuses the
    /// field on open instead of landing on the day brief. Deliberately not an
    /// `askRequest` of its own: there is no query yet, and the whole point of
    /// the Find door is that nothing runs until the person says what they want.
    var focusDraftOnOpen = false

    /// The day, for the detail pane's RESTING state (2026-07-31), and since
    /// prd §550 the only reader of `DayBrief` on this path — the capsule above
    /// the bar stopped carrying the day. Published UNGATED.
    ///
    /// The capsule is once-a-day by ruling (§165: it's a delivery, and a
    /// delivery that repeats is noise). The pane is not a delivery — it is up
    /// to 560pt of the widest column in the app, standing empty for the whole
    /// session behind one placeholder sentence, and §249 already ruled that
    /// the agent's room leads with the day. So the pane at rest leads with it
    /// too, every open, and simply says nothing on a day with nothing to say
    /// (`DayBrief.whisper` composes nil — the honesty law: no manufactured
    /// news). `RootShell.refreshWhisper` writes it from the corpus walk it
    /// already pays for; the once-a-day stamp still gates the capsule alone.
    var paneBrief: DayBrief.Whisper?

    /// The FAB lives on MainSurface's root now (it belongs to Home/Feed, not
    /// to pushed rooms or forms) — bumping this asks RootShell, which still
    /// owns the sheet, to open the composer.
    var composerRequest = 0
    func openComposer() { composerRequest += 1 }

    /// The sources tray, asked for without the hold (2026-07-31). The tray's
    /// only trigger was a 0.45s press on the agent bar — a gesture with no
    /// visible affordance, which a phone can teach through repetition and a
    /// mouse simply cannot: click-and-wait is not something anyone tries. So
    /// the same tray hangs off the bar's right-click menu and off the View
    /// menu (⌘0, continuing the ⌘1–⌘9 chip run), and the hold is unchanged.
    var sourcesRequest = 0
    func openSources() { sourcesRequest += 1 }

    /// Find — the composer raised straight into a typed search, nothing
    /// running until the person types (§215). One verb because three doors now
    /// reach it: the bar's magnifier, the bar's right-click menu, and Mac's
    /// ⌘F. The two-statement spelling was already drifting into copies.
    func openFind() {
        focusDraftOnOpen = true
        openComposer()
    }

    /// Hold the bar's magnifier → the composer rises with the mic already
    /// live (prd §384) — one gesture from anywhere to speaking, the most
    /// physical form of the app's existing voice verb. Deliberately the SAME
    /// verb the composer's own mic button starts, never a new one: what
    /// speaking means (a capture, stop-and-keep) is unchanged, only the
    /// distance to it. Consumed on read like `focusDraftOnOpen`, so an
    /// ordinary later open never inherits a live microphone — a mic that
    /// starts itself unasked is the one thing this flag must never cause.
    var voiceOnOpen = false
    func openVoice() {
        voiceOnOpen = true
        openComposer()
    }

    /// Bumped by every pull-to-refresh on the main surface (Home board or
    /// feed alike — the per-tab distinction died with the tabs). MainSurface
    /// hangs the refresh delight off it: the avatar door's spin (TopDoors,
    /// restored 2026-07-14 — the tab-drop rewire had orphaned it) and the
    /// berry rain (BerryRain, user ask same day).
    var refreshPulse = 0

    /// True for the half-second between tapping Exit in the demo and the rows
    /// actually going. The shell fades its content on this, so leaving reads
    /// as the app LETTING GO rather than as a hard cut to somewhere else.
    ///
    /// It is a single opacity on one container, deliberately — the obvious
    /// version of this effect animates the rows out individually, and that
    /// means deleting ~400 `Thing`s while a live `@Query` feed re-renders
    /// between each batch, which is precisely the crash class CLAUDE.md's six
    /// liveness corollaries document. The fade is indistinguishable to the
    /// eye and touches no model at all: the delete still happens once, in one
    /// transaction, after the content is already invisible.
    var demoLeaving = false
    /// LIVE overscroll (points past the top) while a pull is in progress —
    /// written by FeedScreen's own scroll observer, read by the avatar door,
    /// which WINDS UP proportionally before the release spin fires
    /// (microanimation pass 2026-08-04): the pull gets tension instead of a
    /// silent threshold. Value-driven, no animation — it follows the finger.
    /// Zero whenever the list is at rest, and never written under Reduce
    /// Motion (the writer gates, so the door simply never winds).
    var pullTension: CGFloat = 0
    /// The hue the NEXT `refreshPulse` bump should rain in — a specific
    /// source's own brand hue when the pull happened inside its feed (set by
    /// FeedScreen's `performPull`, cleared to nil for "All"). nil rains the
    /// app's default berry blue (delight pass 2026-07-21). The pull is the
    /// only writer since 2026-08-11, and since 2026-08-19 the only thing that
    /// rains at all — the moment bus that used to set this is gone.
    var refreshHue: Color? = nil

    /// Mac's ⌘R (Mac polish, 2026-07-28): a trackpad's overscroll gesture is
    /// the only trigger `.refreshable` gives Catalyst, and unlike a real
    /// finger pull it isn't reliably discoverable with a mouse — this is the
    /// guaranteed-reachable twin. FeedScreen observes it and runs the exact
    /// same refresh `.refreshable` runs (not just the delight half of it).
    var refreshRequest = 0
    func requestRefresh() { refreshRequest += 1 }

    /// The chip strip's CURRENT order, mirrored here so Mac's ⌘1–⌘9 can read
    /// it (2026-07-28) — `MainSurface.chipLabels` depends on the live corpus
    /// (`@Query`) and `ChipMemory`'s tap-learning, neither of which the
    /// Commands layer (outside the view hierarchy) can reach directly.
    /// Position-based like Safari/Chrome's numbered tabs, not identity-based:
    /// ⌘3 is "whatever's third right now", so a re-sort doesn't strand the
    /// shortcut on a chip that moved. "All" is always first, so ⌘1 is always
    /// valid; MainSurface keeps this in sync via `.onChange(of: chipLabels)`.
    var chipOrder: [String] = ["All"]

    /// Bumped when the person rearranges the category chips in Settings
    /// (prd §533) — `MainSurface` re-freezes the strip on it.
    ///
    /// A pulse rather than the order itself, and rather than reading
    /// `CategoryOrder.current` per body pass: the strip's order is frozen for
    /// the session on purpose (see `MainSurface.chipLabels` — a strip that
    /// re-sorts under a thumb is the thing the freeze exists to prevent), and
    /// a rearrangement is the one change to it the person made deliberately
    /// and is waiting to see. Settings is PUSHED inside the same scene, so no
    /// foreground fires on the way back and without this the new order would
    /// not appear until the app was next backgrounded — which reads exactly
    /// like a control that did nothing (§83).
    var chipOrderPulse = 0
    // `sourceOrder` (the UNFOLDED chip order) was DELETED in §591. It existed
    // for exactly one reader — the sources tray, the screen that claimed to
    // show every source and therefore could not be handed the folded list. The
    // tray is gone (`DoorsPanel`), the strip at the bottom edge is the only
    // enumeration of sources left, and it is `chipOrder`'s by definition. A
    // published property with a writer and no reader is state that looks
    // load-bearing to the next person to read this file.

    /// Every FOLDED category's present member seats this session, in learned
    /// order, keyed by category name (prd §351, 2026-08-11 — generalizes what
    /// was `marketVenues`, a single array only Markets ever filled).
    ///
    /// Published here rather than recomputed in a room because the answer is
    /// the STRIP's: "which seats are present" is exactly what
    /// `MainSurface.computedChipLabels` walks the corpus and the bridge list to
    /// decide, and it is deliberately frozen for the session (see `chipLabels`).
    /// A second derivation in a room would pay that cost again per page and
    /// could disagree with the strip about which venues exist — which, since the
    /// fold hides the individual chips, would leave a venue with no door at all.
    ///
    /// A category missing from this dictionary means it isn't folded (no
    /// members present) — which cannot happen for a real member, since the fold
    /// is now unconditional the moment ≥1 member is present. `categoryVenues["Markets"]`
    /// is what `MarketsRoom`'s own switcher screens still read: they are the one
    /// category with a dedicated switcher UI, so their ≥2-member gate
    /// (`MarketsRoom.switcherFloor`) reads this exactly as before.
    var categoryVenues: [String: [String]] = [:]

    /// A room switch asked for from INSIDE a room — today only the folded
    /// Markets room's venue switcher (2026-08-10).
    ///
    /// Routed through `MainSurface.go(to:)` rather than letting the switcher
    /// write `FeedFilter.source` itself, because `go` is the one door every
    /// chip tap and swipe already walks through (§265) and it does three things
    /// a direct write would silently skip: it clears a kind filter that would
    /// otherwise empty the room you land in, it decides which edge the incoming
    /// room slides from, and it is where the fold resolves a label to a seat.
    /// A second writer would drift from all three the first time one changed.
    ///
    /// Cleared by the reader, so a repeat request for the same venue still
    /// fires rather than being swallowed as "no change".
    var sourceRequest: String?

    // MARK: - The keyboard walk (Mac, 2026-07-31)

    /// The rows the ACTIVE feed page is showing, as ids only — the list half
    /// of list+detail, walkable from the keyboard (↑/↓ move, Return opens,
    /// Escape closes the pane). A two-pane app you cannot arrow through reads
    /// as a port however good its chrome is; this is the gap the 2026-07-28
    /// Mac pass left.
    ///
    /// **Ids, never models.** A `[Thing]` parked on a long-lived object is the
    /// 2026-07-24 crash class by construction — every bridge heal deletes rows
    /// on the main context while this is held. A `String` can't trap, so the
    /// walk carries row ids and the feed page (which has live models anyway)
    /// resolves one only at the moment it opens it. They are ROW ids, matching
    /// `FeedScreen.FeedRow.id` and every `ForEach` key in the feed, so the
    /// scroll target and the list's identity are one value — see
    /// `FeedScreen.walkRowIDs` for why the order is the rendered rows and not
    /// the corpus.
    ///
    /// Written by the active `FeedScreen`, which only compiles this on Mac.
    var walkOrder: [String] = []

    /// The row the keyboard has landed on. nil = nothing selected yet, which
    /// is the resting state — the first ↓ selects the first row rather than
    /// the app pre-selecting something the person didn't ask for.
    var walkSelected: String?

    /// Bumped by the Open command; the active feed page opens `walkSelected`
    /// through its own `openThing` (so the pane/sheet split stays in one
    /// place). A counter rather than a flag, for the same reason
    /// `composerRequest` is one: two Returns in a row are two opens.
    var walkOpenPulse = 0

    /// Someone pinned or unpinned something (2026-08-10). The chip strip caches
    /// its label set and refreshes it from mount, foreground and a corpus COUNT
    /// change — and a pin changes no count, so without this the Pinned chip
    /// would not appear until the next foreground, i.e. the one moment the
    /// person is looking for proof the verb worked. A counter, not a flag, for
    /// `walkOpenPulse`'s reason: the first pin and the first unpin are two
    /// distinct events and both change whether the room exists.
    var pinPulse = 0

    /// Something is raised over the shell — the risen agent, the sources tray,
    /// a deep-linked thing or person, the onboarding cover. Written by
    /// `RootShell` only, as one expression over every presentation it owns.
    var walkModalOpen = false

    /// THE ASK SURFACE IS BLUE, AND THE ROOT IS WHAT PAINTS IT (prd §577b,
    /// user: "the top and bottom of the screen are black and should be blue").
    ///
    /// The tint began as a `.background` on the composer's own content, and
    /// `ignoresSafeArea()` there could not reach: that content is laid out
    /// INSIDE the agent layer's safe-area insets, so the fill expanded to its
    /// own container and stopped at the status bar and the home indicator —
    /// a blue card on a black screen rather than a screen that turned blue.
    ///
    /// Published here instead, so `RootShell`'s agent ZStack — which already
    /// paints `DS.page.ignoresSafeArea()` for exactly this reason — paints the
    /// tint in its place. One ground, one owner, every edge.
    var askOnTint = false

    /// A sheet raised by the feed itself (a thing, a token, a market book).
    /// Written by the active `FeedScreen` only. Separate from `walkModalOpen`
    /// because it has a different owner, not because it means anything
    /// different — and it matters most exactly where the pane doesn't exist: a
    /// Mac window under `PadLayout.minWidthForPane` opens every row as a sheet.
    var walkSheetOpen = false

    /// A pushed room stands on top of the feed. Written by `MainSurface` only.
    /// Settings and every bridge setup form are full of text fields, and a menu
    /// item holding a bare Return or ↓ would take those keys away from them — a
    /// disabled menu item's key equivalent falls through to the responder
    /// chain, an enabled one does not. Three flags with one writer each rather
    /// than one Bool three views race to set.
    var walkInPushedRoom = false

    /// Nothing is raised over the shell and nothing is pushed on top of it —
    /// i.e. the shell's own chrome (the strip, the room switcher, the wallet
    /// rail) is what the person is actually looking at.
    ///
    /// Extracted from `canWalk` (2026-08-11) because the room-control shortcuts
    /// need exactly this and nothing else: `walkOrder` is about feed ROWS, which
    /// is a real requirement for ↑/↓ and irrelevant to changing venue. Sharing
    /// the three flags rather than restating them keeps one writer each.
    ///
    /// **A shortcut for a control that isn't on screen is a dead control the
    /// person can't even see to distrust.** `MainSurface.roomControls` mounts
    /// its two controls INSIDE the NavigationStack precisely so a pushed room
    /// covers them (§357 — "a scope control above a screen it does not scope is
    /// a dead control"); a key equivalent that kept working there would reopen
    /// that hole through the menu bar.
    var shellChromeClear: Bool {
        !walkModalOpen && !walkSheetOpen && !walkInPushedRoom
    }

    /// Whether the walk commands are live at all. Mac-only (there is no menu
    /// bar to hold them elsewhere), never over anything raised or pushed, and
    /// never with nothing to walk. This is the single gate — when it is false
    /// the menu items disable, which is what actually hands ↑/↓/Return back to
    /// whatever should have had them.
    var canWalk: Bool {
        DS.isMac && shellChromeClear && !walkOrder.isEmpty
    }

    /// Move the selection by `delta`, clamped at both ends — a walk that
    /// wrapped would silently jump a reader from the newest thing to the
    /// oldest. With nothing selected, the first step lands on the first row
    /// going down and the last going up.
    func walkStep(_ delta: Int) {
        guard canWalk else { return }
        guard let current = walkSelected,
              let index = walkOrder.firstIndex(of: current) else {
            walkSelected = delta > 0 ? walkOrder.first : walkOrder.last
            return
        }
        let next = index + delta
        guard walkOrder.indices.contains(next) else { return }
        walkSelected = walkOrder[next]
    }

    /// Open whatever is selected. The "Open Item" command disables itself when
    /// nothing is (so Return falls through to the responder chain in exactly
    /// that state), which is why this guards rather than selecting a fallback.
    func walkOpen() {
        guard canWalk, walkSelected != nil else { return }
        walkOpenPulse += 1
    }

    /// A thing ARRIVED while the person watched (a bridge sync, a pull, a
    /// share landing) — the source's chip does one catch bob: the capture
    /// flight's landing beat, generalized to everything that lands (delight
    /// pass 2026-07-13). First-ever thing from a source also blooms its hue
    /// across the header — the moment a new pipe actually flows.
    var arrivedChip: String?
    var arrivedTick = 0
    /// Per-label bloom counters — monotonic per chip, so one source's bloom
    /// never reverts another's coin-flip trigger (review catch 2026-07-13:
    /// a single shared bloomChip made chip X's trigger string change when
    /// chip Y bloomed later).
    var bloomTicks: [String: Int] = [:]
    func chipCaught(_ label: String, firstEver: Bool = false) {
        arrivedChip = label
        arrivedTick += 1
        if firstEver {
            bloomTicks[label, default: 0] += 1
        }
    }

    /// A toast's outcome — `.success`/`.failure` fire the matching haptic
    /// (§ Haptics: the buzz rides WITH the words, never alone) so a call site
    /// can't buzz success and forget to say so, or fail silently. `.neutral`
    /// (the default) is for toasts that aren't reporting a write's outcome
    /// (an informational note, a read, a reversible toggle) — those keep
    /// whatever haptic their own gesture already fired, if any.
    enum Tone { case neutral, success, failure }

    /// The SOURCE whose mark rides the current toast (prd §384) — a moment's
    /// toast wears the brand it's about ("New high" beside the Wallet mark),
    /// so a rare arrival reads as whose it is before a word is read. nil for
    /// ordinary toasts; set and cleared with `toast` so the mark can never
    /// outlive the words it belongs to.
    var toastMark: String?

    func flash(_ text: String, tone: Tone = .neutral, action: ToastAction? = nil,
               mark: String? = nil, seconds: Double = 2) {
        switch tone {
        case .neutral: break
        case .success: DSHaptic.success()
        case .failure: DSHaptic.failure()
        }
        // Replacing an in-flight toast crossfades (id change), never stacks.
        withAnimation(DS.Motion.standard) {
            toast = text
            toastAction = action
            toastMark = mark
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(DS.Motion.standard) {
                if toast == text {
                    toast = nil
                    toastAction = nil
                    toastMark = nil
                }
            }
        }
    }
}

/// Mac menu bar commands (2026-07-28) live at the App/Scene level, outside
/// the view hierarchy RootShell's `chrome` (a per-window `@State`, not a
/// `.shared` singleton like `HomeRoute`/`FeedFilter`) is injected into — a
/// `FocusedValue` is the correct bridge back down to it, rather than making
/// transient UI state a global singleton just for this.
private struct ShellChromeFocusedKey: FocusedValueKey {
    typealias Value = ShellChrome
}
extension FocusedValues {
    var shellChrome: ShellChrome? {
        get { self[ShellChromeFocusedKey.self] }
        set { self[ShellChromeFocusedKey.self] = newValue }
    }
}

extension View {
    /// Attach to a screen's ScrollView: reports scroll direction to the shell.
    /// `active: false` mutes the observer without unmounting it — the feed
    /// pager keeps neighbour pages alive (2026-07-16), and three scroll
    /// observers writing one shared `chrome.minimized` means an off-screen
    /// page settling at offset 0 can un-minimize the chrome while you scroll
    /// the visible one.
    func minimizesChrome(_ chrome: ShellChrome, active: Bool = true) -> some View {
        onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y
        } action: { old, new in
            guard active else { return }
            guard abs(new - old) > 4 else { return }   // ignore jitter
            // A fold CHANGES the top inset, and changing a scroll view's inset
            // reports back here as motion. The 60pt floor already prevents the
            // pathological case (a fold can only happen mid-content, where the
            // offset isn't re-clamped), but this settle window makes it
            // structural rather than incidental: for one animation's length
            // after a toggle, the chrome ignores what its own toggle did.
            let now = Date.timeIntervalSinceReferenceDate
            guard now - chrome.chromeSettledAt > DS.Motion.duration + 0.1 else { return }
            let down = new > old && new > 60
            if chrome.minimized != down {
                chrome.chromeSettledAt = now
                withAnimation(DS.Motion.standard) { chrome.minimized = down }
            }
        }
    }
}
