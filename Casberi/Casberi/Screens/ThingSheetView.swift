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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var confirmingVerb: Verb?
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
    /// The person behind a tapped face — the profile card.
    @State private var profileTarget: SocialProfile?
    /// An approval thing's prepare card (prd §112) — the grant's LIVE state,
    /// the fee to revoke, the doors out. Fetched on open like replies; the
    /// section renders only when the check answered.
    @State private var approvalCheck: WalletPrepare.Check?
    @State private var safeCheck: SafeBridge.Check?
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
    /// Walking into a linked note (2026-07-28) — a plain re-presentation of
    /// this same sheet over the target, the recursive shape already used
    /// elsewhere in this app (e.g. `-agentThingProbe`'s Stack push).
    @State private var walkingToNote: KeyedThing?
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
    /// Stamped at construction, before the zoom-in transition starts — the
    /// clock `dismissWhenSettled` reads to tell a fast tap from a settled one.
    private let presentedAt = Date()

    init(thing: Thing, onBack: (() -> Void)? = nil) {
        self.thing = thing
        self.onBack = onBack
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
            hasMedia || bodyLength > 280 ? .large : .medium)
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Back"))
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
                let walletStage = self.walletStage
                let framedShot = walletStage == nil && thing.kind == .screenshot
                if let walletStage {
                    stageView(for: walletStage)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s6)
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
                    VerbDial(thing: thing, verbs: walletVerbs,
                             onVerb: runVerb,
                             // A Moved leg's counterparty IS your own watched
                             // wallet — it already has a name (via the Wallet
                             // screen's rename), so the Name disc would just
                             // offer to relabel it through the wrong flow.
                             onName: isMoved(walletStage) ? nil : nameCounterpartyAction)
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
                    ThingContentView(thing: thing)
                        .shadow(color: DS.cardShadow, radius: 18, y: 10)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                    Text(thing.title)
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s2)
                        .settleIn(delay: 0.1)
                    VerbDial(thing: thing, verbs: VerbDerivation.verbs(for: thing),
                             onVerb: runVerb, onName: nil)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.14)
                    dialResult
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
                let contentShown = walletStage == nil && !framedShot
                    && (isSocialPost || (thing.kind != .event
                    && thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        != thing.title.trimmingCharacters(in: .whitespacesAndNewlines)))
                if contentShown {
                    ThingContentView(thing: thing)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.12)
                }
                // The stage already shows the counterparty (with its pencil),
                // so its spec table drops the Who row instead of repeating it.
                specTable(contentShown: contentShown, showsWho: walletStage == nil)
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
                if walletStage == nil && !framedShot {
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
                    VerbDial(thing: thing, verbs: VerbDerivation.verbs(for: thing),
                             onVerb: runVerb, onName: nil)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.2)
                    dialResult
                }
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
                if !liveLinkedNotes.isEmpty {
                    noteLinksSection
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        // Only when pushed (`onBack` set): the eyebrow carries its own back
        // chevron now, so the system's default pushed-view nav bar (and the
        // back button it would ALSO draw) is redundant chrome on top of it.
        .toolbar(onBack != nil ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            streamRelated()
            Task { replies = await SocialThread.replies(for: thing) }
            // `CrossSourceEcho.find` itself gates on `.link` (returns nil
            // instantly otherwise), but checking here too skips even
            // constructing the Task for the common non-link case.
            if thing.kind == .link {
                crossSourceEcho = CrossSourceEcho.find(for: thing, context: modelContext)
            }
            if thing.source == "Obsidian", !thing.wikilinks.isEmpty {
                linkedNotes = NoteLinks.resolve(thing.wikilinks, context: modelContext).keyed
            }
            // The gate is a string check — non-approval things spend nothing.
            if WalletPrepare.applies(to: thing) {
                Task { approvalCheck = await WalletPrepare.check(for: thing) }
            }
            if SafeBridge.applies(to: thing) {
                Task { safeCheck = await SafeBridge.check(for: thing) }
            }
        }
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
            Text("Your name for this address rides every future transfer with it. A blank name clears it.")
        }
        // Walking the thread in-app (2026-07-16) — the parent this post
        // answers, or a reply under it. A read: no consent gate, the standing
        // rule for the thread section it grew out of.
        .sheet(item: $walkingTo) { card in
            SocialPostSheet(post: card, source: thing.source)
        }
        // The person behind a tapped face — theirs to watch from here.
        .sheet(item: $profileTarget) { p in
            SocialProfileCard(profile: p)
        }
        // Walking a vault's own wikilink graph (2026-07-28) — a plain
        // re-presentation of this same sheet over the linked note.
        .sheet(item: $walkingToNote) { note in
            ThingSheetView(thing: note.thing)
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
    /// The size follows the length, the way every social client's does: a
    /// one-liner gets the full display size and the drama that comes with it,
    /// a paragraph steps down to a size you can actually read a paragraph in.
    /// Both are the type ramp — hierarchy by size, no other trick (design law).
    @ViewBuilder private var titleBlock: some View {
        if isSocialPost {
            let words = postWords
            Text(words)
                .dsText(words.count > 100 ? .heading22 : .heading34)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(thing.title)
                .dsText(.heading34).foregroundStyle(DS.textPrimary)
        }
    }

    /// The post's own words — the full text when the record carries it, else
    /// the title (posts landed before `postText` existed, until a refresh heals
    /// them). Never a permalink.
    private var postWords: String {
        let full = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? thing.title : full
    }

    /// The post this one answers — "Replying to @alice", above the words, where
    /// every client puts it. A tap walks into the parent in-app.
    private func replyingToRow(_ parent: SocialCard) -> some View {
        Button {
            walkingTo = parent
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "arrowshape.turn.up.left")
                    .accessibilityHidden(true)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Text("Replying to @\(SocialThread.shortHandle(parent.handle))")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eyebrow (source icon · kind · age)

    private var eyebrow: some View {
        HStack(spacing: DS.Space.s2) {
            // A social post leads with the PERSON who said it — their face and
            // handle, not the network's mark (the hue wash already names the
            // network). The feed rows lead with faces; the sheet should too
            // (2026-07-14). Everything else keeps the source mark + kind tag.
            if isSocialPost, let avatar = thing.authorAvatarURL, !avatar.isEmpty {
                // The face is a door to the person (2026-07-16) — tap it and
                // you can watch them, wherever you met them.
                Button {
                    profileTarget = SocialProfile(
                        source: thing.source, handle: thing.authorHandle ?? "",
                        displayName: nil, bio: nil, avatarURL: avatar)
                } label: {
                    RemoteThumb(urlString: avatar, size: 18, fallback: thing.source, circular: true)
                        .coinFlip(trigger: thing.id)
                }
                .buttonStyle(.plain)
                // A bare face: the only control here with no word in it.
                .accessibilityLabel(Text("Open profile"))
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
                Button {
                    DSHaptic.tap()
                    dismissWhenSettled {
                        if let url = URL(string: "casberi://feed/source/\(sourcePathComponent)") {
                            openURL(url)
                        }
                    }
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        BridgeIcon(name: thing.source, size: 18, circular: true)
                            // The mark coin-flips as the sheet opens (delight, 2026-07-12).
                            .coinFlip(trigger: thing.id)
                        Text("\(thing.kind.typeTag) · \(shortTime(thing.capturedAt)) ago")
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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

    /// A social post with a known author — the eyebrow and thread treatment
    /// key off this, never a hardcoded source name.
    private var isSocialPost: Bool {
        SocialThread.isSocial(thing.source)
            && !(thing.authorHandle ?? "").isEmpty
    }

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
        let hasEvent = thing.kind == .event && !thing.content.isEmpty
        let hasDue = thing.kind == .reminder && thing.dueAt != nil
        let hasSite = thing.kind == .link && thing.source != "Tokens"
            && !(contentShown && ThingContentView.showsLinkPreview(thing))
            && Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content)?.host() != nil
        let hasEcho = crossSourceEcho != nil
        let hasAgent = thing.provenance.agent != nil
        let hasFrom = showsWho
        let hasCounterparty = showsWho && thing.source == "Wallet"
            && !(thing.counterpartyAddress ?? "").isEmpty
        let anyRow = hasEvent || hasDue || hasSite || hasEcho || hasAgent || hasFrom || hasCounterparty

        if anyRow {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if hasEvent {
                    specRow("When", thing.content)
                }
                if hasDue, let due = thing.dueAt {
                    specRow("Due", due.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
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
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.leading, DS.Space.s2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.destructive)
            Text(text)
                .dsText(.callout15).foregroundStyle(DS.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The three shapes a wallet thing's stage can take — Sent/Received earns
    /// the full party/arrow/signed-amount treatment; Moved and Swapped
    /// (2026-07-21) each earn their own, since neither is a single signed
    /// amount between "you" and a counterparty.
    private enum WalletStageKind {
        case transfer(TransferStage)
        case moved(MovedStage)
        case swapped(SwapStage)
    }

    /// The ONE decision point every wallet-stage branch reads — first match
    /// wins, since a thing can only ever satisfy one of the three title
    /// grammars.
    private var walletStage: WalletStageKind? {
        if let t = TransferStage(thing) { return .transfer(t) }
        if let m = MovedStage(thing) { return .moved(m) }
        if let s = SwapStage(thing) { return .swapped(s) }
        return nil
    }

    private func isMoved(_ stage: WalletStageKind?) -> Bool {
        if case .moved = stage { return true }
        return false
    }

    @ViewBuilder
    private func stageView(for stage: WalletStageKind) -> some View {
        switch stage {
        case .transfer(let t):
            TransferStageView(thing: thing, stage: t)
        case .moved(let m):
            MovedStageView(thing: thing, stage: m)
        case .swapped(let s):
            SwapStageView(thing: thing, stage: s)
        }
    }

    /// A wallet transfer's dial verbs: Open (the explorer link, when the
    /// record carries one) and Copy. Name and Share ride the dial's own slots.
    private var walletVerbs: [Verb] {
        var out: [Verb] = []
        if let url = Capture.detectURL(in: thing.content) {
            out.append(Verb(label: "Open", icon: "arrow.up.right", action: .openURL(url)))
        }
        out.append(Verb(label: "Copy link", icon: "doc.on.doc", action: .copyText))
        return out
    }

    /// The one verb gate, both layouts: reads pass, writes confirm.
    private func runVerb(_ verb: Verb) {
        if verb.isWrite {
            confirmingVerb = verb
        } else {
            Task { await perform(verb) }
        }
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

    // MARK: - Note links (a vault's own wikilink graph, 2026-07-28)

    /// `linkedNotes` filtered to still-live models, read ONCE at the top —
    /// the corollary-2 guard (see `ThingRowKeying.swift`): a delete-sync
    /// heal landing while this sheet is open must not leave the `ForEach`
    /// below reading a stored property off a tombstoned model.
    private var liveLinkedNotes: [KeyedThing] {
        linkedNotes.filter { $0.thing.isLive }
    }

    private var noteLinksSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Links to")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            ForEach(liveLinkedNotes) { note in
                // `liveLinkedNotes` filters when this view VALUE is made; this
                // runs again each time the closure is re-evaluated, which is
                // when the delete actually lands (corollary 3, build 176 —
                // see `ThingRowKeying`).
                if let linked = note.live {
                    Button {
                        walkingToNote = note
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: "arrow.up.right")
                                .accessibilityHidden(true)
                                .font(.system(size: 11, weight: .semibold))
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
                }
            }
        }
    }

    // MARK: - Related shelf (streams last)

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !relatedStream.els.isEmpty {
                Text(LocalizedStringKey(relatedTitle))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
            }
            GenRender(id: "root", els: relatedStream.els)
        }
    }

    private func streamRelated() {
        // A thing that can't have related items costs no fetch — the old
        // invariant, kept: only a watched token (mentions) or a tagged thing
        // (overlap) has anything to look for.
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let myTags = Set(thing.tags).subtracting(typeTags)
        let isToken = thing.source == "Tokens"
        guard isToken || !myTags.isEmpty else { return }

        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300   // relatedness lives in the recent past
        let all = (try? modelContext.fetch(descriptor)) ?? []

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
            guard !myTags.isEmpty else { return }
            // Meaning first (2026-07-14): rank the recent corpus by semantic
            // similarity to this thing, so a GitHub PR reaches the Linear
            // ticket, the chat, the note that share NO tag — the cross-source
            // weaving tag overlap can't find (a feed tag like "Stars" only ever
            // reaches other GitHub things). Tag overlap stays the fallback when
            // the on-device embedding is unavailable or this thing isn't
            // embedded yet.
            related = semanticRelated(in: all)
                ?? Array(all.filter { other in
                    other.id != thing.id && !myTags.isDisjoint(with: other.tags)
                }.prefix(6))
        }
        guard !related.isEmpty else { return }

        var doc = ["root = Shelf([\(related.indices.map { "c\($0)" }.joined(separator: ", "))])"]
        for (i, t) in related.enumerated() {
            let title = t.title.replacingOccurrences(of: "\"", with: "")
            doc.append("c\(i) = Chip(\"\(t.source)\", \"\(title)\")")
        }
        relatedStream.stream(doc)
    }

    /// The recent corpus ranked by on-device semantic similarity to this thing
    /// — the meaning-based Related set (EmbeddingIndex, the same vectors the
    /// answer path scores). Cross-source by nature: it scores by meaning, not
    /// source or tag. nil when the model is unavailable, this thing can't be
    /// embedded, or nothing clears the floor — the caller then falls back to
    /// tag overlap. The 0.5 cosine floor keeps it to genuine relations (looser
    /// than the answer path's 0.62 qualify floor — "related", not "answers").
    private func semanticRelated(in all: [Thing]) -> [Thing]? {
        guard EmbeddingIndex.isAvailable,
              let query = EmbeddingIndex.vector(for: EmbeddingIndex.indexText(for: thing))
        else { return nil }
        let qNorm = EmbeddingIndex.norm(query)
        guard qNorm > 0 else { return nil }
        let scored = all.compactMap { other -> (Thing, Double)? in
            guard other.id != thing.id, let data = other.embedding, !data.isEmpty else { return nil }
            let sim = EmbeddingIndex.similarity(query: query, queryNorm: qNorm, packed: data)
            return sim >= 0.5 ? (other, sim) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(6)
        .map(\.0)
        return scored.isEmpty ? nil : Array(scored)
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
                verbResult = "On your calendar"
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .addToReminders:
            do {
                try await HandOff.addToReminders(thing)
                verbResult = "On your list"
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .copyText:
            UIPasteboard.general.string = thing.content.isEmpty ? thing.title : thing.content
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
