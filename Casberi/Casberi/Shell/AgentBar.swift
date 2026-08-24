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
    /// It names the TAP (§390) — "Your sources", not "Ask your things…". A
    /// label on a button is a promise about what pressing it does, and after
    /// the swap that sentence would have been the honesty rule's dead control
    /// wearing the wrong verb.
    var expanded: Bool = false
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

    /// A hold has fired, so the button's own touch-up must not act on top of
    /// it: a SwiftUI Button fires on RELEASE however long the press lasted,
    /// and the long-press gesture ends at its threshold while the finger is
    /// still down — so this flag is always set before the tap it exists to
    /// swallow. Cleared when the next press BEGINS, never on a timer (see the
    /// gesture's own note).
    @State private var heldForAgent = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                guard !consumeHold() else { return }
                onSources()
            } label: {
                HStack(spacing: DS.Space.s3) {
                    if expanded {
                        Text("Your sources")
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
                .frame(width: expanded ? nil : 44, height: expanded ? nil : 44)
                .contentShape(Capsule())
                .dsHover()
            }
            .buttonStyle(.plain)
            // The words carried the button's name; compact, it needs its own.
            .accessibilityLabel(Text("Your sources"))
            // The hold, reachable without holding. It rides THIS button rather
            // than the container: a custom action on a plain layout view has no
            // accessibility element of its own to be found on, and VoiceOver
            // would simply never offer it. It names the AGENT since §390 — the
            // action always states whichever verb the hold reaches, because
            // that is the one a person can't discover by pressing.
            .accessibilityAction(named: Text("Ask your things"), onAsk)
            // The hold. It rides the berry rather than the pill (prd §384), so
            // the control under the finger owns exactly one hold and the
            // gesture does what that control says. §390 changed WHERE it goes
            // (the agent, not the tray) and nothing else about it.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    // Cleared when the NEXT press BEGINS, never on a timer. A
                    // timer has to guess how long a finger stays down, and it
                    // guesses wrong in the most ordinary case there is: hold
                    // until the agent rises, look at it, then let go — by which
                    // time a 900ms clear has already expired and the release
                    // opens the tray under the risen agent. Press-begin is the
                    // one moment that is always before the release it has to
                    // swallow and always after the last one.
                    .onChanged { _ in heldForAgent = false }
                    .onEnded { _ in
                        heldForAgent = true
                        // The buzz lives at the destination, not on the
                        // recognizer (`RootShell`'s two doors), so the
                        // accessibility action and the Mac menu feel the same
                        // as the gesture does.
                        onAsk()
                    }
            )
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
        // The hold moved OFF the container and onto the button (prd §384), and
        // §390 changed what it reaches. The button is a full 44pt control, so
        // the finger has already chosen; `simultaneous` keeps its own tap, and
        // the tap guards on `consumeHold()` for the release that follows a
        // hold.
        .modifier(BarSecondaryMenu(onAsk: onAsk))
        .modifier(MorphMatch(ns: morphNS))
    }

    /// True if this touch-up is the tail of a hold that already acted.
    private func consumeHold() -> Bool {
        guard heldForAgent else { return false }
        heldForAgent = false
        return true
    }
}

/// The bar's hidden verb in words, for a pointer (2026-07-31) — Mac ONLY, and
/// the `#if` is load-bearing rather than tidiness.
///
/// The 0.45s hold has no visible affordance: a phone teaches that through
/// repetition, a mouse never does, because click-and-wait is not something
/// anyone tries. A right-click states the door in words instead. It names the
/// AGENT since §390, following the hold rather than the destination — the tap
/// needs no menu entry, it is the click.
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

/// The whisper (ruling 6's flag-gated sketch, ruled real 2026-07-22 — prd
/// §165): one glass card above the bar on the first open of a day, carrying
/// the day brief. Floating layer, so glass is lawful here. Tap opens the
/// Today brief itself (prd §166). It dies for the day the moment the agent
/// rises by any path — its one job is done — and never shows with nothing to
/// say (`DayBrief.whisper` composes nil).
///
/// **It names itself** (user ruling 2026-07-22). The first cut was a pill: a
/// tint dot beside one line of facts. That is notification grammar — a dot
/// plus a sentence reads as "a transaction happened", and nobody could tell
/// it was a daily synthesis. Three changes fix the read, and each is doing a
/// job: the day is NAMED on its own line ("Your Wednesday brief") so the
/// artifact is legible before the facts are; the unread dot becomes the
/// agent's own mark, which says who this is from instead of merely that it's
/// new; and a chevron says it opens something rather than just sitting there.
///
/// It used to be INSET from the bar below it (2026-07-22) because two
/// full-width glass slabs stacked read as one confusing double-bar. That inset
/// is GONE (2026-08-07) and the hierarchy it bought is now free: the bar
/// hugged into the bottom-right corner, so the pair is a wide slab above a
/// small pill and cannot be misread as two bars. The capsule keeps its own
/// trailing edge aligned with the bar's, so the two read as one corner system.
///
/// **It is never put behind a tap** (ruling 2026-08-07, considered and
/// declined). Folding it into the bar — press the berry, the whisper unfolds —
/// looks tidier and breaks the feature: this is once-a-day unsolicited news,
/// and it works precisely because it ARRIVES rather than waits. Behind a press
/// it becomes a menu item, unopened on the one day it had something to say.
struct WhisperCapsule: View {
    var title: String
    var lead: String
    var walletPct: Double?
    /// The bar↔surface morph's own namespace (2026-07-22) — the title text
    /// carries a SECOND, independent `matchedGeometryEffect` pairing inside
    /// it (id "whisperTitleMorph", position-only — see `WhisperTitleMorph`),
    /// so the words themselves travel from the capsule up into the masthead
    /// as the agent rises, rather than the capsule's promise and the
    /// screen's title merely happening to match. Optional for the same
    /// reason `AgentBar.morphNS` is: a namespace-free preview still renders.
    var morphNS: Namespace.ID?
    /// The room's hue — see `AgentBar.roomTint`. The capsule takes it too so
    /// the bottom cluster reads as one coordinated pair (2026-07-23) rather
    /// than one tinted slab beside a neutral one.
    var roomTint: Color? = nil
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// The figure wears its own direction (§83's accent rule) — rendered by
    /// `DayBrief.Whisper` itself since 2026-07-31, so the capsule and the
    /// detail pane's resting state can't drift on the format or the accent.
    private var detail: Text {
        DayBrief.Whisper(title: title, lead: lead, walletPct: walletPct)
            .detailText(scheme: scheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                CasberiMark(size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .modifier(WhisperTitleMorph(ns: morphNS))
                    detail
                        .dsText(.subhead13)
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
        // It MATERIALIZES (2026-08-06). This capsule appears once a day, out of
        // nothing, carrying something genuinely new — the one piece of chrome in
        // the app whose arrival is itself the news. Fading it in like any other
        // view spent that moment on nothing; the glass growing its own lens is
        // the system's own way of saying a floating thing just arrived. Reduce
        // Motion stills it (`dsGlassMaterialize` gates), and because it rides
        // the glass rather than the content, a system that declines to draw the
        // transition costs the capsule nothing.
        .dsGlassMaterialize()
        .animation(DS.Motion.standard, value: roomTint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(lead)"
                            + (walletPct.map { String(format: ", wallet %+.1f percent", $0) } ?? ""))
        .accessibilityHint("Opens your day")
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

/// The whisper's title, travelling (2026-07-22, prd §167 item 1) — pairs the
/// capsule's `Text(title)` with the masthead's own title in `Composer`
/// (`briefTitleText`), same id, same shared namespace. POSITION only, not
/// size/frame: the two texts are genuinely different type scales
/// (`subhead13` → `heading22`), and matching their full frames would stretch
/// the smaller glyph run into the bigger one's bounds — a visible distortion
/// for a beat. Position-only lets the words travel to their new home while
/// each text crossfades into its own real style, which reads as "the same
/// words, grown up" rather than "text smeared across the screen".
struct WhisperTitleMorph: ViewModifier {
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns {
            content.matchedGeometryEffect(id: "whisperTitleMorph", in: ns, properties: .position)
        } else {
            content
        }
    }
}
