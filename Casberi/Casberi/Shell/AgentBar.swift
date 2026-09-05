import SwiftUI

/// The agent's bar (docs/agent-brief.md, ruling 6) — replaces the FAB.
/// Floating-layer glass, rides every screen (hosted in `RootShell`'s own
/// ZStack, not `MainSurface`'s, so pushed rooms — Apps, Settings, a bridge
/// setup form — never slide over it the way they used to slide over the
/// FAB). Tap raises the agent full screen.
///
/// The berry mark breathes (the same idiom `Composer.swift`'s in-flight
/// "Thinking…" state already uses) while some kept ask changed and the agent
/// hasn't been raised yet this launch — ruling 6: no number badges, ever.
///
/// Morphs into the risen surface (2026-07-20) — `morphNS` is the SAME
/// namespace `RootShell` gives `Composer`'s `glassNamespace`, and `"agentMorph"`
/// the same id both sides key on, so the bar's own frame is what the risen
/// sheet visibly grows out of (`matchedGeometryEffect`, not `glassEffectID` —
/// the risen surface is plain ink, never glass, per design law §8 "Liquid
/// Glass on the floating layer only... never on content panels"; only the
/// SHAPE morphs, the glass itself stays the bar's alone and fades out as the
/// sheet's opaque background fades in). `RootShell` hides this view entirely
/// once risen (`if !composerOpen`) so exactly one side of the pair exists at
/// a time — matchedGeometryEffect needs that alternation to interpolate.
///
/// **It rests COMPACT** (user ruling 2026-07-31). The full-width
/// "Ask your things…" invitation was the heaviest chrome in the app doing its
/// least-frequent job: this is a corpus you open and READ, and asking is
/// occasional — capture arrives through the share sheet, the paste chip and the
/// bridges. Chrome is priced by frequency of use, so the bar now wears the
/// shape it used to reach only after a scroll. ONE control (2026-08-15, §386o):
/// the magnifier is gone — the surface it opened has a text field in it, so
/// search was never a second door, just the same one with the keyboard up.
///
/// **It rests in the CORNER** (user ruling 2026-08-07). Compact chrome centred
/// on the bottom edge still sat over the middle of the reading column — the one
/// column this app exists to serve — while claiming the screen's most
/// symmetrical position for its least-frequent verb. `RootShell` now pins the
/// whole floating cluster trailing, so this hugs the bottom-right the way a FAB
/// does, the reading column runs clear beneath it, and the thumb has less
/// distance to travel on the hand most people hold a phone in. The hold belongs to the
/// whole pill again now that the pill is one control.
///
/// So `expanded` no longer means "span the screen" — it only adds the words.
/// The teaching grace survives (a bar nobody has used should still say what it
/// is once); what died is the full-width slab it used to say it from.
///
/// **THE VERBS ARE SWAPPED** (user ruling 2026-08-16, prd §390): the tap opens
/// the sources tray and the HOLD raises the agent. Chrome is priced by
/// frequency of use — the same rule that made this bar compact in the first
/// place — and this is a corpus you open and READ: moving between rooms is
/// what the thumb does all day, asking is occasional. The cheap gesture now
/// belongs to the common verb. Nothing about either destination changed; only
/// which recognizer reaches it.
///
/// One consequence worth stating, because it is the cost: the agent is now
/// behind a gesture with no visible affordance. It is not the only door —
/// `chrome.composerRequest` (the Mac menu bar's ⌘K, the whisper capsule, the
/// Daily Brief quick action, `casberi://brief`, a kept pill, any surface that
/// hands over an ask) all still raise it directly, and this bar's own
/// VoiceOver action and Mac right-click state it in words.
struct AgentBar: View {
    var hasUnseenSignal: Bool
    /// The agent noticed something today and it hasn't been seen (prd §384,
    /// `AgentNoticed`). A small STATIC tint dot — "something unread behind
    /// this" — deliberately not an animation: the breathing beside it already
    /// means "changed", and two live motions on one 20pt mark is a strobe.
    var noticeGlint: Bool = false
    /// The words. FALSE at rest (see the type's own note) — `RootShell` grants
    /// it only as a teaching grace, until the tray has been opened once on this
    /// device, and `ShellChrome.minimized` folds it away early if that
    /// first-time reader scrolls before ever tapping. It no longer carries a
    /// width: since 2026-08-07 the pill hugs its contents in the corner in
    /// BOTH states, so this adds a line of text and nothing else.
    ///
    /// It names the TAP, which is the rule that has survived every change to
    /// what this control reaches: a label on a button is a promise about what
    /// pressing it does. It read "Your sources", then "Your feeds"
    /// (2026-08-24, user: "this should say your feeds not your sources"), and
    /// says **"Everything else"** since §591 — because the panel behind the tap
    /// stopped being feeds. Every feed is in the dock beside this bar now, so
    /// what is left behind it is precisely the four destinations that are not
    /// one: the agent, the catalogue, the address book and settings.
    ///
    /// Plain words in this app's own voice, and exactly true rather than
    /// merely vague — "Menu" or "More" would name a container, and this names
    /// the complement of the row it sits in.
    var expanded: Bool = false
    /// The bar's drawn size — `DSDock.agentSize`, so it matches the chip marks
    /// it sits beside in the rail and folds with them (§591d).
    var size: CGFloat = DS.Hit.min

    var morphNS: Namespace.ID?
    /// THE MAGNIFIER IS GONE (2026-08-15, prd §386o, user: "search and the
    /// agent button are the same really, if you click it you have a field you
    /// can type in… i don't think the fab needs to be the casberi icon AND
    /// the search icon").
    ///
    /// It was added in 2026-07-30 to save an act of faith — Find used to be a
    /// chip you only met AFTER raising the agent and typing. But the surface
    /// it opens has a text field in it, so "search" was never a second door:
    /// it was the same door with the keyboard already up. Two 44pt targets a
    /// thumb-width apart, opening the same screen in two states, is the kind
    /// of choice a person has to make before they know what either one does.
    ///
    /// What is genuinely different about Find survives untouched: the Find
    /// CHIP still appears the moment there is a draft, and it still runs the
    /// deterministic engine that writes nothing (§215). You reach it by
    /// typing, which is what you were going to do anyway.
    /// Every source at once (`SourcesTray`, 2026-07-31) — the bar's TAP since
    /// §390, a hold before that. It lives HERE rather than on the chip strip's
    /// catalogue door for three reasons, all of which the promotion only
    /// strengthens: this bar is in the bottom thumb zone and the strip is at
    /// the top, which is the hardest place to reach on a phone; this bar is
    /// hosted on `RootShell`'s own ZStack, so it works from Settings, a bridge
    /// setup form, anywhere, while the strip only exists on `MainSurface`; and
    /// the catalogue door is this app's most gesture-cursed control (three
    /// reports, `highPriorityGesture` belt and braces, the
    /// safeAreaInset-over-pager arbitration), which is not a place to stack a
    /// second recognizer.
    var onSources: () -> Void = {}
    /// The room's own hue, when standing in a room that HAS one (2026-08-06) —
    /// `ShellChrome.pourHue`, which is non-nil only inside a scoped wallet.
    ///
    /// The crown said which room you're in this way through §159/§204; since
    /// the 2026-08-15 amendment (`MainSurface.crownPour`'s own doc) the crown
    /// stopped reading `pourHue` at all — the wallet room's balance card
    /// became the loud identity element there, and a per-wallet hue pouring
    /// above a fixed-blue card was two identities disagreeing on one screen.
    /// This bar is the field's ONE remaining reader now, which is exactly why
    /// killing `pourHue` at its source would have silently un-tinted it too —
    /// the bottom chrome is where "which wallet you're in" still lives. A nil
    /// here still means the same silence §297 argues for on a source room.
    var roomTint: Color? = nil
    /// Raise the agent — the bar's HOLD since §390 (its tap before that).
    var onAsk: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onSources()
            } label: {
                HStack(spacing: DS.Space.s3) {
                    if expanded {
                        Text("Everything else")
                            .dsText(.body17)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Group {
                        if hasUnseenSignal {
                            CasberiMark(size: 20).breathing()
                        } else {
                            CasberiMark(size: 20)
                        }
                    }
                    // The notice glint (prd §384): a 6pt tint dot riding the
                    // berry's shoulder while today's observation is unseen.
                    // Cleared by the rise itself (`AgentNoticed.markSeen`).
                    .overlay(alignment: .topTrailing) {
                        if noticeGlint {
                            Circle()
                                .fill(DS.tint)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                // COLLAPSED, THE BUTTON IS A SQUARE and the mark is centred by
                // its FRAME (2026-08-15). The padding below is the EXPANDED
                // layout — words on the left, berry on the right — and the
                // trailing `s4` was never the berry's right margin: it was the
                // GAP between the berry and the magnifier that used to sit
                // beside it. §386o deleted the magnifier, and the gap stayed,
                // so the collapsed button became 46pt wide with the mark 5pt
                // LEFT of centre. The comment on the glass below still says it
                // "hugs its two controls", which is the tell — there is one.
                //
                // Fixed with a frame rather than by re-tuning two paddings to
                // agree, because two paddings that must sum to the same value
                // on both sides is exactly the arrangement that just drifted;
                // 44 is also the tap target the deleted magnifier carried.
                .padding(.trailing, expanded ? DS.Space.s4 : 0)
                .padding(.leading, expanded ? DS.Space.s1 : 0)
                .padding(.vertical, expanded ? DS.Space.s3 : 0)
                .frame(width: expanded ? nil : size, height: expanded ? nil : size)
                .contentShape(Capsule())
                .dsHover()
            }
            .buttonStyle(.plain)
            // The words carried the button's name; compact, it needs its own.
            .accessibilityLabel(Text("Everything else"))
            // **THE HOLD IS GONE (prd §591, 2026-09-03, user: "and no long
            // press for it" — "that simplifies it!").**
            //
            // It existed because this one control had two destinations and a
            // tap can only reach one. §390 gave the tap to the tray and the
            // hold to the agent; §384 had given the hold to the tray. Both
            // rounds were arguments about which of two things the undiscoverable
            // gesture should hide, and §550 then had to ship a one-time capsule
            // whose entire job was to teach that the gesture existed — a
            // control that has to be advertised is a control that was not
            // found.
            //
            // What removed it was not a better ruling about the gesture but
            // the dock: every feed is in the strip beside this bar now, so the
            // tray's source grid became a second way to a set already on
            // screen, and the panel behind this tap became the four
            // destinations that are NOT a feed — the agent among them. One
            // control, one tap, one panel, and the thing the hold used to
            // reach is a labelled row inside it.
            //
            // The accessibility action goes with it for the same reason: it
            // existed to make an invisible gesture reachable, and there is no
            // longer an invisible gesture. VoiceOver gets the tap, like
            // everyone else.
        }
        // Collapsed there is nothing to its left to make room for, and this 4pt
        // would push the square off-centre inside the glass again — the same
        // bug one level up (2026-08-15).
        .padding(.leading, expanded ? DS.Space.s1 : 0)
        // The glass hugs its one control now — it hugged TWO until §386o took
        // the magnifier (2026-08-07 comment, corrected 2026-08-15). The shape
        // itself says the bar has yielded to the content, and in the corner
        // there is no full-width state left for it to yield FROM.
        .dsGlass(cornerRadius: DS.Radius.pill, tint: roomTint)
        // A scope change re-tints the bar on the same beat the crown re-tints
        // (`MainSurface.crownPour` animates the same value) — the two ends of
        // the screen answering one move, rather than a hard swap down here
        // under a gradient that glided.
        .animation(DS.Motion.standard, value: roomTint)
        // The Mac's secondary-click menu SURVIVES the hold's deletion (§591)
        // and is not a leftover. A right-click menu is a pointer idiom that
        // was never the hidden gesture: it is listed, it is discoverable by
        // the platform's own convention, and on a Mac the agent is reached by
        // ⌘K and by this menu rather than by a 0.45s press nobody performs
        // with a mouse. What it names is unchanged.
        .modifier(BarSecondaryMenu(onAsk: onAsk))
        .modifier(MorphMatch(ns: morphNS))
    }
}

/// The bar's hidden verb in words, for a pointer (2026-07-31) — Mac ONLY, and
/// the `#if` is load-bearing rather than tidiness.
///
/// The phone reaches the agent through the panel this bar's tap opens (§591);
/// a pointer should not have to. A right-click states the door in words and
/// lands on it directly, which is the platform's own convention for a second
/// verb on one control — and unlike the 0.45s hold it replaced, it is listed
/// rather than hidden, so it never needed a capsule to teach it.
///
/// It cannot ship on iOS, though. `.contextMenu` installs its own ~0.5s
/// long-press recognizer, which on a touch screen would fire alongside the
/// bar's own hold — one press would raise the agent AND a menu over it.
/// Under Catalyst there is no touch input, so the menu answers a secondary
/// click only and the two never meet.
private struct BarSecondaryMenu: ViewModifier {
    let onAsk: () -> Void

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.contextMenu {
            Button {
                onAsk()
            } label: {
                Label("Ask your things", systemImage: "sparkles")
            }
        }
        #else
        content
        #endif
    }
}

/// THE CAPSULE ABOVE THE BAR TEACHES THE GESTURE (prd §550, 2026-09-01,
/// user: "i don't want a whisper once a day, i want it once. after onboarding
/// only" → "we either kill it or add something else there but not once a day"
/// → "it could have a whisper that says long press to talk to agents and then
/// empty chat has a link to where to set up agents").
///
/// It was `WhisperCapsule` (prd §165/§166): the day brief's headline, on the
/// first foreground of every calendar day, tapping through to the brief. Two
/// things retired it. §543 deleted every prepopulated door onto that document
/// on the reasoning that they were doors onto a screen you can ask for by
/// name — this was the last one standing, on the one surface that repeats
/// forever. And the day reading was never only here: the All feed's own Today
/// header has drawn `DayBrief.whisper` since §385, so the capsule spent a
/// daily arrival re-stating a line already on the page behind it.
///
/// ## WHY IT IS REPLACED RATHER THAN DELETED
///
/// §390 swapped the bar's verbs — tap opens the sources tray, HOLD raises the
/// agent — and `AgentBar`'s own note states the cost out loud: "the agent is
/// now behind a gesture with no visible affordance", acceptable because other
/// doors exist, and it names this capsule as one of them. Then §543 emptied
/// the agent's landing. Delete this too and nothing on the feed ever says the
/// agent is there, or that there is a choice of who answers.
///
/// So the slot keeps its arrival and changes its subject: the gap §390 left is
/// a GESTURE, not a missing product, and this says the gesture.
///
/// ## WHY THE CAPSULE AND NOT THE BAR'S OWN WORDS
///
/// `AgentBar.expanded` is already a teaching grace with a persisted flag
/// (`sources.everOpened`). It cannot carry this: **a label on a button is a
/// promise about what TAPPING it does**, and after §390 the tap opens the
/// tray. The bar cannot say "hold me" without lying about itself. A separate
/// object above it can point at it.
///
/// ## IT RETIRES BY BEING LEARNED
///
/// Once ever, not once a day: `agent.everRaised` is spent the first time the
/// agent rises by ANY door — this capsule's own tap, the hold, ⌘K, a quick
/// action, a deep link. That is the strongest retirement available, because
/// using the thing is proof the explanation landed. Deliberately NOT also
/// retired by connecting an app: someone can furnish the whole catalog and
/// still never find the hold, and a grace that expires on an unrelated event
/// is the label outliving its own explanation — the inversion
/// `sources.everOpened` records in its own note.
///
/// ## ITS OWN TAP RAISES THE AGENT
///
/// Reading it and obeying it land in the same place, so it is never a control
/// that only talks (§83) — and it is the accessible route for anyone who
/// cannot perform a long press, beside `AgentBar`'s own VoiceOver action.
///
/// ## STILL NEVER BEHIND A TAP (2026-08-07, carried forward)
///
/// Folding it into the bar — press the berry, the hint unfolds — is still
/// self-defeating, and more so now: this explains the very press it would be
/// hiding behind.
///
/// The anatomy is unchanged from the whisper's (user ruling 2026-07-22): the
/// agent's own mark says who this is from, a named line over a quieter one so
/// the artifact is legible before the detail, a chevron to say it opens
/// something, and the trailing edge aligned with the bar's so the two read as
/// one corner system.
struct AgentHintCapsule: View {
    /// No namespace parameter, deliberately. The whisper took one for a
    /// SECOND, title-level `matchedGeometryEffect` pairing
    /// (`WhisperTitleMorph`, id "whisperTitleMorph") that flew its words up
    /// into the brief's masthead; this capsule opens no titled document, so
    /// that modifier, `ShellChrome.risingBriefTitle` and the proxy title
    /// `RootShell` mounted for it are all deleted with the day content. The
    /// bar's own shape morph (`MorphMatch`, id "agentMorph") is a different
    /// pairing and is untouched.
    ///
    /// The room's hue — see `AgentBar.roomTint`. Kept so the bottom cluster
    /// can read as one coordinated pair; `RootShell` passes nil today.
    var roomTint: Color? = nil
    var action: () -> Void

    /// Through `DS.secondaryGesture`, never a literal: the Mac's door here is
    /// `BarSecondaryMenu`'s RIGHT-CLICK, not a press and hold — a pointer has
    /// no hold — and this capsule shows ONCE EVER, so a wrong word spends the
    /// app's single chance to teach its primary surface on an instruction that
    /// cannot be followed. `mac-parity-audit.py` fails the build on a literal
    /// here.
    static var gestureLine: String {
        String(localized: "\(DS.secondaryGesture) the button below.")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                CasberiMark(size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Talk to your agents")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // It points DOWN at the control it describes, which is
                    // directly below it — "the button below" rather than a
                    // name for the mark, because no user-facing copy in this
                    // app has ever called it the berry, and naming it here
                    // would teach a word that appears nowhere else.
                    //
                    // THE MAC IS TOLD ITS OWN GESTURE (prd §607). The Mac's
                    // door is `BarSecondaryMenu`'s right-click, not a press
                    // and hold — a pointer has no hold, and this capsule shows
                    // ONCE EVER, so getting it wrong spends the app's single
                    // chance to teach its primary surface on an instruction
                    // that cannot be followed. Nothing could have caught it:
                    // the string compiles, the capsule renders, and a
                    // screenshot of it looks perfect on either platform.
                    Text(Self.gestureLine)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .dsGlyph(12)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .dsHover()
        }
        .buttonStyle(.plain)
        .dsGlass(cornerRadius: DS.Radius.control, tint: roomTint)
        // It MATERIALIZES (2026-08-06, kept). This appears out of nothing,
        // carrying something new — the glass growing its own lens is the
        // system's way of saying a floating thing just arrived. Reduce Motion
        // stills it, and because it rides the glass rather than the content, a
        // system that declines to draw the transition costs it nothing.
        .dsGlassMaterialize()
        .animation(DS.Motion.standard, value: roomTint)
        .accessibilityElement(children: .combine)
        // The hold is stated for sighted readers above; for VoiceOver the
        // honest instruction is the one that works there — activating this
        // capsule — since the long press on the bar is not the route a
        // VoiceOver user takes (`AgentBar` publishes its own custom action).
        .accessibilityLabel("Talk to your agents")
        .accessibilityHint("Opens the agent")
    }
}

/// Applies `matchedGeometryEffect` only when a real namespace was given —
/// `RootShell` always supplies one, but keeps this optional so a future
/// preview/embedding of `AgentBar` without a namespace doesn't crash on a
/// force-unwrap. Shared with `Composer` (not file-private) — both sides of
/// the morph key the exact same id/namespace pairing, so one modifier
/// keeps them from drifting apart.
struct MorphMatch: ViewModifier {
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns {
            content.matchedGeometryEffect(id: "agentMorph", in: ns)
        } else {
            content
        }
    }
}

