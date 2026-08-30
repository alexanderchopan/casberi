import SwiftUI
import SwiftData

/// "What should I start with?" — the onboarding fork (prd §217, 2026-07-25).
///
/// The problem it solves: onboarding was one greeting straight into a catalog
/// of ~40 apps, so a new person had to PICK something, CONNECT it, and WAIT
/// for a sync before the app did anything. Three steps and a wait before any
/// evidence it was worth having — while the brief, the themes map, the wallet
/// hero and the whole continuity memory stayed invisible until a corpus
/// existed.
///
/// **Why more than one, and why these.** Casberi has more than one audience,
/// and forcing a single first source means half of new users get a demo of
/// something they didn't come for (user, 2026-07-25: "we have users that are
/// here for crypto wallets, what if they don't care about photos"). A short
/// fork is one you answer in a second; forty is a wall you have to survey.
///
/// It covered THREE audiences until §527 — your own files (a folder), money (a
/// wallet), reading (someone to follow) — and covers two, because the third
/// answer is now "Show me all the apps" rather than a card. The reading arm was
/// the one to go and the reasoning is on §527 below; the short version is that
/// it was the least "my own things" of the three, on a screen reached by
/// tapping "Start with my own things", and its audience is the one the catalog
/// serves best (Bluesky, Farcaster, Nostr, RSS, Substack, YouTube, Podcasts and
/// Telegram are all seats, where the arm offered a three-segment form).
///
/// **Why a folder, not screenshots (2026-07-28).** The first card used to be
/// "Show me my screenshots" (Photos permission → the screenshot library).
/// Swapped for "Show me my files" — the system folder picker (`Model/
/// FilesBridge.swift`) — because it's a stronger first proof: one tap on a
/// folder like Downloads or an iCloud Drive folder lands real, personally
/// meaningful files (PDFs, docs, whatever's actually in there) rather than
/// just screenshots, and it reads as evidence the app can hold ANYTHING, not
/// one narrow category. Screenshots ingest is unchanged and still reachable
/// from the catalog — this only changes which door onboarding opens first.
///
/// **Why this is not the connect screen that died (prd §96).** That screen was
/// a LIST of sources with toggles — four simultaneous standing asks, all
/// abstract, none of them showing you anything, which is exactly why it read as
/// invasive. These are three VERBS with visible outcomes, phrased in the first
/// person, and one tap produces real rows from your own life. The old screen
/// asked for a relationship; this asks for an outcome. The tripwire, if this is
/// ever redesigned: **the moment a card grows a toggle it is a settings page
/// again** and should be deleted a second time.
///
/// Pick-ONE, not do-any: a screen where you can do several things is a screen
/// you can get stuck on, and the whole point is to be out of onboarding looking
/// at your own things. The last answer is "Show me all the apps" rather than
/// "Skip" — skip lands you nowhere, this lands you where the old CTA went, so
/// nothing is lost for someone who came to browse.
///
/// **What §527 changed (2026-08-29): the screen reads as ONE question again.**
/// Reported as a menu — "it kind of presents a bunch of options: connect 1-3
/// things, show demo, browse catalogue … instead of feeling like 5 total
/// things it is 3". The count was real and none of it was in the fork's own
/// design; it was drift, two locally-correct changes each adding a competing
/// object. The demo card had the SAME `card(…)` shape as the three arms, so it
/// read as a fourth answer (which §217's own amendment ruled out), and the
/// catalog link was promoted from bare text to a full-width prominent pill on
/// 2026-08-23 to fix a real legibility bug, landing it in primary-CTA grammar.
///
/// The changes, and the fork's grammar is untouched by all of them:
///
///   • **The arms are ONE SLAB**, not separate cards. A grouping, never a
///     merge — every arm is still drawn, same shape, same weight, in
///     `StartAppetite`'s order. Collapsing them into a single "connect
///     something" card would either pick one arm for everybody (the thing
///     §217 exists to refuse) or defer the identical choices to a second
///     screen, which is more taps for the same menu.
///   • **The demo card is DELETED.** It only ever rendered for somebody who,
///     one screen earlier, was shown "Try a demo" as the primary CTA and
///     tapped the small secondary link instead — so it re-asked a question
///     they had just answered. (Its copy was the best-written demo line in
///     the app; if the greeting's CTA ever needs to name the outcome rather
///     than the object, that wording is in this file's history.)
///   • **The FOLLOW card is deleted too**, and `StartFollowScreen` with it —
///     an unreachable screen that three drift guards still watched would be
///     worse than a removed one. Its measured placeholders (theverge.com,
///     vitalik.eth, the NASA feed) are recorded in §527 and in git; re-measure
///     rather than re-typing them if that form ever returns.
///   • **The exit moved INSIDE the slab as the last answer**, saying "Show me
///     all the apps" in the arms' own voice. Pinned below as chrome it was a
///     peer of the demo the person had just declined rather than part of the
///     question they had just said yes to — which is what made the screen feel
///     like five things. It belongs in the slab because it is the same KIND of
///     answer as the arms (your own things, longer route), which is exactly
///     what the demo card was not; that asymmetry is why one was folded in and
///     the other deleted.
///
/// The result is ONE object on the screen — a question and its answers — and
/// the two onboarding screens no longer wear the same "stacked cards plus a
/// bottom CTA" layout, which was itself part of why the second one didn't
/// announce that it was asking something rather than explaining something.
///
/// **What §422 changed (2026-08-20), and what it deliberately didn't.** Three
/// things, none of them structural: the subline names the hand-over for
/// somebody arriving from the demo (which, since the greeting's CTA became
/// "Try the demo", is most people — and the screen greeted them as if the last
/// few minutes had not happened); the cards are ORDERED by what they opened in
/// the demo (`StartAppetite`, never hidden and never re-weighted); and the one
/// arm that acts in place hands back to the feed BEFORE its walk rather than
/// after it, so the rows are watched arriving instead of being revealed
/// already landed. The card shape, the wording, the cost lines, the figures
/// and the pick-one rule are all untouched, and the toggle tripwire above
/// still stands.
///
struct StartHereScreen: View {
    /// Ends onboarding. A non-nil node is where to land afterwards (the wallet
    /// manager, the catalog); nil means the feed, which is the right answer
    /// whenever the tap already produced something to look at.
    var onStart: (HomeRoute.Node?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    /// False until a moment after the slab has landed, when the figures draw
    /// themselves (prd §527). SEPARATE from `arrived` on purpose: keyed to the
    /// same flag the marks would animate WITH the slab's own entrance, and two
    /// things moving at once reads as one busy frame rather than as a card that
    /// arrives and then fills in.
    @State private var figuresAlive = false
    /// The files card is the one option that does its work HERE rather than
    /// handing off to a screen, so it needs its own in-place state — the
    /// system picker is a hop, not an instant.
    ///
    /// Since §422 the folder WALK no longer happens under this card (the
    /// screen hands back first and the walk lands into the feed), so
    /// `connectingFolder` is chiefly a re-entrancy guard; the spinner it
    /// still drives covers only the frames of the leaving transition, which
    /// is the right amount of acknowledgement for a tap that is already on
    /// its way somewhere.
    @State private var pickingFolder = false
    @State private var connectingFolder = false
    /// Which arm leads (prd §422). Read ONCE, as this screen is first made,
    /// rather than per body pass — a fork whose cards reshuffle under
    /// somebody's thumb is worse than one that never reorders at all.
    @State private var order: [StartAppetite.Arm] =
        StartAppetite.order(visits: DemoMode.roomVisits,
                            category: BridgeCatalog.category(forSource:))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // A question about THEM, not a configuration step — the
                    // difference between this screen and the one that died.
                    Text("What should I start with?")
                        .dsText(.heading34).fontWeight(.heavy)
                        .foregroundStyle(DS.textPrimary)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    // The subline names the HAND-OVER for somebody arriving
                    // from the demo (prd §422). Since 2026-08-07 that is this
                    // screen's main audience — the greeting's own CTA enters
                    // the demo — and it was greeting them with the words
                    // written for a first-timer, as if the last few minutes
                    // had not happened. The question above is unchanged and
                    // right for both; only the answer's framing moves.
                    Group {
                        if DemoMode.hasSeen {
                            Text("That was sample data. Now with your own things.")
                        } else {
                            Text("Pick one. The rest can wait.")
                        }
                    }
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.Space.s2)
                .startArrive(arrived, delay: 0.05)

                // The order is the PERSON'S whenever the demo gave them a
                // chance to say (prd §422) — every card is still drawn, in
                // the same shape and at the same weight, so §217's "one
                // decision, not three offers of different weight" holds. Only
                // which one is read first moves, and only on evidence they
                // produced themselves. `StartAppetite.defaultOrder`, i.e. the
                // screen exactly as §217 shipped it, whenever there is no
                // signal — which is most people.
                // ONE SLAB, EVERY answer inside it (prd §527, 2026-08-29). The
                // arms used to be separate `dsWidgetSurface` cards with the
                // catalog exit pinned below as chrome, and the screen read as
                // a MENU rather than as one question — reported exactly that
                // way ("it kind of presents a bunch of options … maybe we
                // should make it feel like it is one, not a menu of three").
                //
                // **A grouping, never a merge.** Every arm is still drawn, in
                // the same shape, at the same weight, in `StartAppetite`'s
                // order — §217's audience reasoning is untouched, and
                // collapsing them into a single "connect something" card would
                // either pick one arm for everybody or defer the identical
                // choices to a second screen. What changes is that the eye
                // meets ONE object.
                //
                // **The exit is INSIDE, as the last answer.** It was pinned
                // chrome (`safeAreaInset`) and therefore a peer of the demo the
                // person had just declined rather than part of the question
                // they had just said yes to — which is what made the screen
                // feel like five things. It belongs here because it is the same
                // KIND of answer as the arms (your own things, by a longer
                // route), which is exactly what the demo card was not; that
                // asymmetry is the whole reason one was folded in and the other
                // deleted.
                //
                // **The trade, stated rather than discovered later**: it stops
                // being pinned, so at large Dynamic Type it can scroll out of
                // sight and somebody who cannot answer the question has to
                // scroll to find the way out. That cost was weighed and refused
                // while the fork had THREE tall arms; at two the screen is
                // short enough to fit without scrolling at the default size,
                // which is what changed the answer. If a third arm ever
                // returns, re-weigh this before adding it.
                //
                // **It arrives as one element**, deliberately: a slab whose
                // rows staggered in would be several arrivals wearing one edge,
                // which says the opposite of what the grouping is for. The
                // per-row `startArrive` stagger went with the separate cards.
                //
                // No divider between rows — the design law's no-hairlines rule
                // has zero exceptions, so the rows are separated by air alone,
                // which is what a grouped list looks like here anyway.
                VStack(spacing: 0) {
                    ForEach(order, id: \.self) { arm in
                        armCard(arm)
                    }
                    catalogRow
                }
                .padding(DS.Space.s2)
                .dsWidgetSurface()
                .startArrive(arrived, delay: 0.15)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        // Added 2026-08-10 because the cards scrolled UNDER a pinned catalog
        // link and put gray text on top of a moving tile. **That link is inside
        // the slab since §527, so nothing is pinned and nothing can scroll
        // beneath anything** — this stays as the app-wide treatment every other
        // scrolling screen wears, not as a fix for a bug that no longer has a
        // way to happen.
        //
        // Worth keeping the history: the 2026-08-23 answer to that same bug was
        // to promote the link to a full-width prominent pill, which fixed the
        // legibility by giving an escape hatch primary-CTA weight. The soft
        // edge was always the right half of that fix and the pill the wrong
        // one; §527 kept the first and undid the second.
        .dsSoftScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if FilesStore.shared.setFolder(url: url) {
                connectFolder()
            } else {
                chrome.flash("Couldn't keep access to that folder — try again from the catalog")
                onStart(nil)
            }
        }
        .tint(DS.tint)
        .onAppear {
            if reduceMotion {
                // No entrance at all: the slab and its figures are simply
                // there. `StartFigureMark` also refuses its own animations
                // under Reduce Motion, so this is belt and braces rather than
                // the only guard — but it matters, because without it the
                // figures would sit at their resting scale forever.
                arrived = true
                figuresAlive = true
            } else {
                withAnimation(DS.Motion.standard) { arrived = true }
                // One beat behind the slab, so the card arrives and THEN fills
                // in. Unstructured and parentless like every other fire-once
                // task here; if the screen goes first, the flag it would have
                // set goes with it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    figuresAlive = true
                }
            }
        }
        #if DEBUG
        // `-startPick folder|wallet|follow|catalog` fires one card after a
        // beat, so each arm of the fork verifies headlessly. The folder arm
        // can only OPEN the system picker (`fileImporter`, like every other
        // document-picker/sign-in hop in this app, can't be driven headless)
        // — pair with `-startFolder <path>` below to land files without
        // touching the picker at all.
        .onAppear {
            guard let pick = UserDefaults.standard.string(forKey: "startPick"),
                  !pick.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                NSLog("[Casberi] startPick: %@", pick)
                switch pick {
                case "folder":  pickingFolder = true
                case "wallet":  onStart(.bridge(.wallet))
                // `follow` and `demo` are deliberately GONE (§527) rather than
                // silently falling through to the catalog: neither has a door
                // on this screen any more, and a probe arm for a door that does
                // not exist is a check that certifies nothing. The demo's own
                // doors — the greeting's CTA and the Settings row — keep
                // `-howItWorksCTA` and `-demoEnter`; following a handle is now
                // the Bluesky / Farcaster / RSS seats' own setup screens, with
                // their own hooks (`-bskyHandle`, `-fcName`, `-rssFeed`).
                // falling through to the catalog: the demo has no door on this
                // screen any more, and a probe arm for a door that does not
                // exist is a check that certifies nothing. The demo's own
                // doors — the greeting's CTA and the Settings row — keep
                // `-howItWorksCTA` and `-demoEnter`.
                default:        onStart(.apps)
                }
            }
        }
        // `-startFolder <path>` connects a folder by path directly, bypassing
        // the picker entirely — the only way to exercise the landing path
        // (setFolder → FilesIngest.refresh → registerConnected) headlessly.
        .onAppear {
            guard let path = UserDefaults.standard.string(forKey: "startFolder"),
                  !path.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                NSLog("[Casberi] startFolderProbe: %@", path)
                if FilesStore.shared.setFolder(url: URL(fileURLWithPath: path)) {
                    connectFolder()
                } else {
                    NSLog("[Casberi] startFolderProbe: couldn't bookmark %@", path)
                }
            }
        }
        #endif
    }

    /// Each arm's card. One `card(…)` shape for all three, so the fork still
    /// reads as one decision however `StartAppetite` orders them.
    @ViewBuilder
    private func armCard(_ arm: StartAppetite.Arm) -> some View {
        switch arm {
        case .files:
            card(figure: .treemap, hue: .blue,
                 title: "Show me my files",
                 line: "Pick any folder — Downloads, iCloud Drive, anywhere.",
                 cost: "Opens the Files picker",
                 busy: connectingFolder) {
                DSHaptic.tap()
                pickingFolder = true
            }
        case .wallet:
            card(figure: .curve, hue: .green,
                 title: "Watch a wallet",
                 line: "Enter an ENS, paste an address, or connect your wallet app.",
                 cost: "No account needed") {
                // The wallet manager already IS all three doors (§202's
                // roster and §188's "Connect a wallet app" button), so this
                // hands off rather than growing a fourth address field. It
                // is also the arm that already had §422's one-tap example,
                // and has since §202: the manager's own "Peek at
                // vitalik.eth" chip.
                DSHaptic.tap()
                onStart(.bridge(.wallet))
            }
        }
    }

    /// The one card that acts in place — and it now leaves FIRST and lets
    /// the folder walk land rows into a feed that is already on screen
    /// (prd §422).
    ///
    /// **Why the order flipped.** It used to hold the card on a spinner for
    /// the whole walk and then hand back a feed that was already full, which
    /// reads as a screenshot rather than as an app that just did something.
    /// That is the exact failure `DemoMode.pourIfNeeded` exists to prevent
    /// one screen earlier — "lifting first and pouring after lets them watch
    /// the app fill … the one moment that shows what this product actually
    /// does rather than describing it" — and the fork's own arms never got
    /// that treatment, so the single most persuasive second of a new install
    /// was happening off-screen behind a spinner.
    ///
    /// **The environment values are copied into locals BEFORE the hand-off.**
    /// `onStart` tears this screen down, and an `@Environment` wrapper read
    /// afterwards is reading a dead view's storage. The `Task` is
    /// unstructured and has no parent task, so nothing cancels it when the
    /// view goes — the same reasoning `WalletConnect`'s detached teardown
    /// records ("it must not inherit the screen's cancellation").
    ///
    /// A folder that can't be read is still NOT a dead end: the person is
    /// already in the feed, where the catalog door is, and the flash says
    /// what happened rather than leaving the tap unexplained.
    private func connectFolder() {
        guard !connectingFolder else { return }
        connectingFolder = true
        let context = modelContext
        let bridges = store
        let shell = chrome
        onStart(nil)
        Task { @MainActor in
            let added = await FilesIngest.refresh(context: context)
            NSLog("[Casberi] startFolder: %@", added.map { "\($0) in" } ?? "unreadable")
            guard let added else {
                FilesStore.shared.disconnect()
                shell.flash("Couldn't read that folder — try again from the catalog",
                            tone: .failure)
                return
            }
            let proof = added > 0
            ? String(localized: "\(added) files in")
            : String(localized: "Synced just now")
            _ = bridges.registerConnected(id: "files", name: "Files", proof: proof,
                                          can: ["Reads the folder you picked.",
                                                "Read-only — never edits a file."])
            // The greeting wears the source's own mark (prd §384) — whose
            // things these are, said before a word is read. It reuses the
            // seat's own `proof` string rather than composing a second one,
            // so the toast and the catalog row can never disagree about how
            // much arrived.
            shell.flash(proof, tone: .success, mark: "Files")
        }
    }

    /// The last answer: everything the arms don't shortcut to.
    ///
    /// **Why it is a row and not a card, and why it is last.** It is the same
    /// KIND of answer as the arms — your own things, by a longer route — which
    /// is what earned it a place inside the slab where the demo card did not
    /// (sample data is a different kind of thing entirely). But it is the
    /// broadest and slowest answer, so it takes no figure mark, no `cost:` line
    /// and no `heading22`: VOICE says it belongs to this question, WEIGHT says
    /// it is not the headline. Leading with it would make the catalog the first
    /// thing a new person meets, which is precisely the wall §217 exists to
    /// avoid ("forty is a wall you have to survey"), and would also put a fixed
    /// row above arms that `StartAppetite` took trouble to order.
    ///
    /// **It goes through `card(…)`, the arms' own builder** (user, 2026-08-29:
    /// "it should have the same styling … it should have the app catalogue icon
    /// and same indentation and font sizes as the other two"). The first cut of
    /// this row was bare `callout15` text with no mark, and that was an
    /// inconsistency in this file's own argument: folding it into the slab was
    /// justified by its being the SAME KIND of answer as the arms, and then it
    /// was drawn as a different kind of thing. A markless row inside a slab of
    /// marked ones also just reads as an afterthought — or as a layout bug,
    /// since its text starts where nothing else's does.
    ///
    /// **A FULL PEER, hue included** (user, 2026-08-29). The first cut drew it
    /// neutral so the colour could still whisper "this one is different"; that
    /// was the last residue of treating it as a lesser exit, which is the thing
    /// this whole pass exists to stop. It is one of three answers and it looks
    /// like one. Purple is the free slot — blue is the folder, green the wallet,
    /// and purple was the deleted follow arm's — so nothing had to be invented
    /// or re-tuned to make room for it.
    ///
    /// `start-fork-selftest.sh` therefore expects `StartAppetite.Arm.allCases`
    /// PLUS ONE `card(figure:` call site — the +1 is this row and nothing else,
    /// so a card belonging to no answer still fails the build, which is the
    /// shape both deleted cards had.
    ///
    /// **The wording, and three retired alternatives.** "Show me all the apps"
    /// since §527 (user, 2026-08-29: "even if we change 'browse the catalogue'
    /// to 'show me all the apps' that alone is clearer"). It replaced "Browse
    /// the catalog", which was wrong twice over — and the 2026-07-16 naming
    /// ruling is untouched by the change: the catalog is still the catalog
    /// everywhere inside the app, never a store.
    ///
    ///   1. It named OUR SURFACE rather than the outcome, on the second screen
    ///      of a first run. Step 1 of the greeting does teach the word, but the
    ///      common path here is via the DEMO — whose whole design intent is that
    ///      people tap the CTA rather than study three step cards — so the
    ///      teaching is routed around for most arrivals. It is also a shopping
    ///      word (a catalog is what a store mails you), an odd frame for an app
    ///      whose pitch is that nothing costs anything.
    ///   2. It was in a DIFFERENT VOICE from the answers above it, so it read as
    ///      a peer of the demo the person had just declined rather than as part
    ///      of the question they had just said yes to. That was the real
    ///      complaint ("so now user is thinking there is demo option, browse
    ///      catalogue, and these three other things").
    ///
    /// Retired, each for a stated reason: **"…instead"** (deleted 2026-08-07 —
    /// it framed a deliberate choice as a way out of the real one, and that
    /// reasoning survives the rewording); **a COUNT**, "See all 96 apps" (user,
    /// 2026-08-11 — the number becomes the argument, and a number is a claim to
    /// survey rather than a destination to go to; only the NOUN moved back, the
    /// count must not); and **"Just show me the apps"** (weighed 2026-08-29 —
    /// "all" is load-bearing, since completeness is the whole reason to tap this
    /// rather than an arm, and "my files"/"all the apps" is the contrast).
    ///
    /// **First person is deliberate, and an earlier objection to it was wrong.**
    /// It was ruled out on the grounds that matching the arms' voice would make
    /// this another answer — the thing deleting the demo card fixed. That does
    /// not transfer: the demo card was an answer of a different kind, this one
    /// is not, so belonging to the list is honest here and was not there.
    private var catalogRow: some View {
        card(figure: .catalog, hue: .purple,
             title: "Show me all the apps",
             line: "Everything you can connect, in one list.",
             // **"Get started" is a DELIBERATE relaxation of this slot's rule,
             // ruled by the user (2026-08-29), and it is recorded rather than
             // quietly taken so the next reader does not mistake it for the new
             // contract.** Everywhere else `cost:` is a FACT ABOUT THE NEXT TAP
             // — "Opens the Files picker", "No account needed" — and it exists
             // so somebody can tell at a glance which answer wants a system
             // permission. The standing objection is not that a CTA is vague
             // but that it makes the slot UNSCANNABLE: once one entry is not a
             // cost, a reader cannot tell whether the next one means "this asks
             // nothing of you" or "the author had nothing to say".
             //
             // The reading that makes it right here, and it is the one the
             // rule-bound alternatives all missed: **a cost line for this row
             // keeps landing in the DEMO's territory.** Every truthful "this
             // asks nothing of you" phrasing — "Just a look", "Nothing to
             // connect yet" — describes browsing without committing, which is
             // what the demo IS ("Just show me what it looks like", one screen
             // back). The catalog is the opposite: it is where somebody stops
             // looking and starts connecting. So the honest tag is what KIND of
             // act this is rather than what it costs, and the kind is "this is
             // where you begin properly" (user: "it's not just a look, just a
             // look was the demo"). The two arms above are shortcuts with one
             // specific ask each; this is the whole list.
             //
             // Two phrasings were rejected on the way here and one is worth
             // keeping as a trap: **"Nothing to set up" is FALSE** (user: "it's
             // a list of things to set up"). It read as a claim about the
             // DESTINATION when the slot describes the TAP — and the general
             // lesson is that a cost line phrased as an ABSENCE drifts into
             // making claims about what is on the other side of the door.
             //
             // TRIPWIRE: this is the ONE row allowed a non-cost here. A second
             // one means the slot has stopped being a cost line and the two
             // arms' entries should be re-read as decoration.
             cost: "Get started") {
            DSHaptic.tap()
            onStart(.apps)
        }
    }

    /// One shape for every arm, so the fork reads as one decision rather than
    /// three offers of different weight. No chevron and no toggle: each of
    /// these is a button that DOES something (see the tripwire above).
    /// `cost` is the three-word answer to "what will this ask of me?" — a
    /// picker, a paste, a sign-in. It exists because the cards were four
    /// identically-weighted offers with no way to tell which one wanted a
    /// system permission and which wanted nothing, and that ambiguity is
    /// exactly what makes someone back out to the previous screen rather than
    /// tap. It is a FACT about the next tap, never a reassurance.
    private func card(figure: StartFigure, hue: Color, title: LocalizedStringKey,
                      line: LocalizedStringKey, cost: LocalizedStringKey? = nil,
                      busy: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: DS.Space.s4) {
                ZStack {
                    if busy {
                        ProgressView().tint(hue)
                    } else {
                        StartFigureMark(figure: figure, hue: hue, alive: figuresAlive)
                    }
                }
                .frame(width: 54, height: 54)
                .background(hue.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                 style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cost {
                        Text(cost)
                            .dsText(.subhead13)
                            .foregroundStyle(hue)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            // NO surface of its own since §527 — the slab this sits in owns
            // the one edge, and a card inside a card is two claims to the same
            // elevation rung. The press affordance is `PressSpring` alone,
            // which is what a row inside a grouped container gets everywhere
            // else in the app.
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control,
                                           style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(busy)
    }
}

/// What a card's tap PRODUCES, drawn as the figure that room will wear.
enum StartFigure { case treemap, curve, faces, sparkle, catalog }

/// The mark on a fork card — the figure the source becomes, not a glyph for
/// the category it belongs to.
///
/// **Why it changed (2026-08-07).** Four cards wearing four tinted SF Symbols
/// read as four equal-weight menu items: the glyph names the KIND of thing
/// ("a folder", "a wallet") and says nothing about what you get. That was
/// tolerable while the fork ran before anyone had seen the app. It is wasteful
/// now that the fork runs AFTER the demo, because the person arriving here has
/// just watched a treemap tile itself, a balance curve draw and a roster fill —
/// so a card can answer "how do I get that?" by simply showing the figure
/// again, at card scale, in the card's own hue.
///
/// **Two rules, both load-bearing.**
///
/// The figures are GENERIC SHAPE ONLY — no number, no label, no plausible
/// data. A mark that carried "$12,480" or a real-looking file name would be a
/// claim about what YOUR wallet holds or what YOUR folder contains, made on
/// the screen where trust is being established and before a single thing has
/// been read. That is §83 at its most expensive. A rising line says "this
/// becomes a curve"; it must never say "your curve rises".
///
/// And they have NO ENTRANCE OF THEIR OWN. The cards already arrive on
/// `startArrive`'s stagger, so an animated figure would be a second entrance
/// on the same element — which the design-motion audit would flag, and would
/// be right to.
struct StartFigureMark: View {
    let figure: StartFigure
    let hue: Color
    /// False = the figure at rest · true = it has drawn itself (prd §527).
    ///
    /// **This overturns this type's own "NO ENTRANCE OF THEIR OWN" rule, and
    /// the reason is that the rule's PREMISE stopped being true.** It read: "the
    /// cards already arrive on `startArrive`'s stagger, so an animated figure
    /// would be a second entrance on the same element". Since §527 the cards do
    /// not arrive individually at all — the SLAB arrives, as one element — so
    /// there is no per-card entrance for this to be a second of, and the figures
    /// were the one thing on the screen that stayed inert.
    ///
    /// It is ONE beat, fired once, a moment AFTER the slab lands so the two read
    /// as a single arc rather than as two entrances competing. Nothing loops,
    /// nothing repeats, nothing is triggered by data: this is a drawing showing
    /// how it was made, which is what makes it delight rather than decoration —
    /// and §83 is untouched, since a generic shape drawing itself still claims
    /// nothing about what YOUR wallet holds or YOUR folder contains.
    var alive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One curve for the whole beat, so no figure can drift out of step with
    /// another. `delay` staggers the parts WITHIN a figure, never between cards.
    private func beat(_ delay: Double) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72).delay(delay)
    }

    var body: some View {
        switch figure {
        case .treemap:
            // The Files room's own hero, at card scale: one dominant cell and
            // a smaller tail, which is what a real folder's treemap looks like.
            //
            // It TILES ITSELF: each cell grows from its own bottom edge, in the
            // order a treemap really packs them — the big one first, then the
            // tail — so the mark performs the thing the room does rather than
            // sitting there as a picture of it.
            HStack(spacing: 2.5) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(hue)
                    .frame(width: 16, height: 27)
                    .scaleEffect(y: alive ? 1 : 0.05, anchor: .bottom)
                    .animation(beat(0), value: alive)
                VStack(spacing: 2.5) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(hue.opacity(0.62))
                        .scaleEffect(y: alive ? 1 : 0.05, anchor: .bottom)
                        .animation(beat(0.07), value: alive)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(hue.opacity(0.36))
                        .scaleEffect(y: alive ? 1 : 0.05, anchor: .bottom)
                        .animation(beat(0.13), value: alive)
                }
                .frame(width: 10, height: 27)
            }
        case .curve:
            // The balance line, with its endpoint emphasised the way the real
            // sparkline emphasises the latest sample.
            //
            // It DRAWS ITSELF left to right, and the dot lands only once the
            // stroke has reached it — a sparkline's endpoint marks the latest
            // sample, so a dot sitting there before the line arrives is marking
            // a sample that has not been drawn yet.
            StartCurveShape()
                .trim(from: 0, to: alive ? 1 : 0)
                .stroke(hue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                                lineJoin: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: alive)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(hue).frame(width: 6.5, height: 6.5)
                        .offset(x: 1.5, y: -1.5)
                        .scaleEffect(alive ? 1 : 0)
                        .animation(beat(0.46), value: alive)
                }
                .frame(width: 30, height: 24)
        case .faces:
            // A roster: people, overlapping, the way every follow room draws
            // them. The ring is the CARD's fill, so the stack reads as lifted
            // off the surface rather than as three flat discs.
            //
            // They ARRIVE ONE AFTER ANOTHER, which is what a roster filling
            // looks like. (No arm draws this today — the follow card went with
            // §527 — but the case is kept whole so a future arm inherits the
            // beat rather than being the one inert figure on the screen.)
            HStack(spacing: -5) {
                ForEach(Array([1.0, 0.72, 0.46].enumerated()), id: \.offset) { index, dose in
                    Circle()
                        .fill(hue.opacity(dose))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(DS.surfaceSheet, lineWidth: 2.5))
                        .scaleEffect(alive ? 1 : 0)
                        .animation(beat(Double(index) * 0.07), value: alive)
                }
            }
        case .sparkle:
            // The demo is not one figure — it is all of them — so it keeps a
            // glyph rather than pretending to preview a single room.
            Image(systemName: "sparkles")
                .dsGlyph(24)
                .foregroundStyle(hue)
        case .catalog:
            // THE REAL APPS-DOOR GLYPH, not a figure (§527). Every other case
            // here previews the shape a room becomes, and this one deliberately
            // does not: the catalog is not a room and has no figure to show, so
            // the honest mark is the door's own — `TopDoors`' `square.grid.2x2`,
            // which `HowItWorksSheet`'s step 1 already wears for exactly this
            // reason ("so they recognize it in the shell later"). A figure here
            // would preview a reading the catalog never draws.
            //
            // It is the one mark that must NOT be taken apart to animate: four
            // hand-drawn squares popping in would look better and would stop
            // being `TopDoors`' actual symbol, which is the whole reason this
            // case exists. So it takes the beat as a whole — a scale, no more.
            Image(systemName: "square.grid.2x2.fill")
                .dsGlyph(24)
                .foregroundStyle(hue)
                .scaleEffect(alive ? 1 : 0.4)
                .opacity(alive ? 1 : 0)
                .animation(beat(0.05), value: alive)
        }
    }
}

/// A rising line with one dip, normalised to its rect. Hand-placed rather than
/// random: a figure that reshuffles between launches reads as data.
private struct StartCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.82), CGPoint(x: 0.19, y: 0.58),
            CGPoint(x: 0.35, y: 0.68), CGPoint(x: 0.52, y: 0.30),
            CGPoint(x: 0.68, y: 0.44), CGPoint(x: 0.85, y: 0.12),
            CGPoint(x: 1.00, y: 0.20),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: rect.minX + point.x * rect.width,
                                 y: rect.minY + point.y * rect.height)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        return path
    }
}

private extension View {
    /// The fork's entrance — the same one-curve stagger the greeting's steps
    /// use, so the two screens read as one arc.
    func startArrive(_ on: Bool, delay: Double) -> some View {
        modifier(StartArrive(on: on, delay: delay))
    }
}

private struct StartArrive: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on || reduceMotion ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : DS.Motion.standard.delay(delay), value: on)
    }
}
