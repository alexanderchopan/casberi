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
/// shape it used to reach only after a scroll. It is NOT the old FAB restored:
/// the magnifier stays visible beside the berry, because Find was promoted out
/// of the risen composer on 2026-07-30 precisely for being undiscoverable, and
/// a lone berry would re-bury it a month later.
///
/// **It rests in the CORNER** (user ruling 2026-08-07). Compact chrome centred
/// on the bottom edge still sat over the middle of the reading column — the one
/// column this app exists to serve — while claiming the screen's most
/// symmetrical position for its least-frequent verb. `RootShell` now pins the
/// whole floating cluster trailing, so this hugs the bottom-right the way a FAB
/// does, the reading column runs clear beneath it, and the thumb has less
/// distance to travel on the hand most people hold a phone in. Two things did
/// NOT change with it, both deliberately: the magnifier stays beside the berry
/// (see the paragraph above — a corner move is not a reason to re-bury Find,
/// and it costs one glyph of width in a shape that no longer spans anything),
/// and the hold still belongs to the whole pill rather than being split between
/// two corner circles, which at this size would be two targets too small to
/// aim a 0.45s press at.
///
/// So `expanded` no longer means "span the screen" — it only adds the words.
/// The teaching grace survives (a bar nobody has used should still say what it
/// is once); what died is the full-width slab it used to say it from.
struct AgentBar: View {
    var hasUnseenSignal: Bool
    /// The words. FALSE at rest (see the type's own note) — `RootShell` grants
    /// it only as a teaching grace, until the agent has been raised once on
    /// this device, and `ShellChrome.minimized` folds it away early if that
    /// first-time reader scrolls before ever asking. It no longer carries a
    /// width: since 2026-08-07 the pill hugs its contents in the corner in
    /// BOTH states, so this adds a line of text and nothing else.
    var expanded: Bool = false
    var morphNS: Namespace.ID?
    /// The magnifier (2026-07-30). Find is deterministic and writes nothing —
    /// a genuinely different act from asking — but it existed only as a chip
    /// that appears AFTER you raise the agent and type, so the person who
    /// wants to locate a link they saved had to start by asking a question.
    /// This raises the composer straight into a typed search: no brief, field
    /// focused, Find one keystroke away. Same surface, same ruling (§215),
    /// one fewer act of faith.
    var onFind: () -> Void = {}
    /// Hold the bar → every source at once (`SourcesTray`, 2026-07-31). It
    /// lives HERE rather than on the chip strip's catalogue door for three
    /// reasons: this bar is in the bottom thumb zone and the strip is at the
    /// top, which is the hardest place to reach on a phone; this bar is hosted
    /// on `RootShell`'s own ZStack, so the gesture works from Settings, a
    /// bridge setup form, anywhere, while the strip only exists on
    /// `MainSurface`; and the catalogue door is this app's most
    /// gesture-cursed control (three reports, `highPriorityGesture` belt and
    /// braces, the safeAreaInset-over-pager arbitration), which is not a place
    /// to stack a second recognizer.
    var onSources: () -> Void = {}
    /// The room's own hue, when standing in a room that HAS one (2026-08-06) —
    /// `ShellChrome.pourHue`, which is non-nil only inside a scoped wallet.
    ///
    /// The crown has said which room you're in since §159; the bottom chrome
    /// never did, and this is the same fact reaching the other end of the
    /// screen. It is deliberately tied to `pourHue` rather than to a hue of its
    /// own so the two can never disagree — and it inherits that field's whole
    /// argument for free: §297 drains the pour on a source room precisely
    /// because a permanent colour that says nothing is decoration, and a
    /// nil here is that same silence.
    var roomTint: Color? = nil
    var action: () -> Void

    /// A hold has fired, so the button's own touch-up must not act on top of
    /// it: a SwiftUI Button fires on RELEASE however long the press lasted,
    /// and the long-press gesture ends at its threshold while the finger is
    /// still down — so this flag is always set before the tap it exists to
    /// swallow. Self-clearing on a timer because a press that ends by dragging
    /// off never delivers that tap at all, and a flag left set would eat the
    /// next legitimate one.
    @State private var heldForSources = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                guard !consumeHold() else { return }
                onFind()
            } label: {
                // A satellite, not a twin (2026-08-07): in the corner the berry
                // is the anchor and Find rides beside it, so the glyph steps
                // down a size to say which is which. The TARGET does not —
                // it stays the full 44pt circle below, because a control that
                // reads as secondary still has to be hittable (HIG's floor,
                // and the catalogue door's own lesson one line down).
                Image(systemName: "magnifyingglass")
                    .dsGlyph(15)
                    .foregroundStyle(DS.textSecondary)
                    // The control is the CIRCLE, not the glyph (the catalogue
                    // door's own 2026-07-26 lesson: a `.frame()` around a small
                    // symbol leaves everything but its centre falling through).
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .dsHover()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Find in your things"))
            // Same words as the label above, verbatim, so the pointer and
            // VoiceOver can never name this glyph two different things.
            .dsTooltip(String(localized: "Find in your things"))

            Button {
                guard !consumeHold() else { return }
                action()
            } label: {
                HStack(spacing: DS.Space.s3) {
                    if expanded {
                        Text("Ask your things…")
                            .dsText(.body17)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    if hasUnseenSignal {
                        CasberiMark(size: 20).breathing()
                    } else {
                        CasberiMark(size: 20)
                    }
                }
                .padding(.trailing, DS.Space.s4)
                .padding(.leading, DS.Space.s1)
                .padding(.vertical, DS.Space.s3)
                .contentShape(Capsule())
                .dsHover()
            }
            .buttonStyle(.plain)
            // The words carried the button's name; compact, it needs its own.
            .accessibilityLabel(Text("Ask your things"))
            // The hold, reachable without holding. It rides THIS button rather
            // than the container: a custom action on a plain layout view has no
            // accessibility element of its own to be found on, and VoiceOver
            // would simply never offer it.
            .accessibilityAction(named: Text("Your sources"), onSources)
        }
        .padding(.leading, DS.Space.s1)
        // The glass hugs its two controls in BOTH states now (2026-08-07) —
        // the shape itself says the bar has yielded to the content, and in the
        // corner there is no full-width state left for it to yield FROM.
        .dsGlass(cornerRadius: DS.Radius.pill, tint: roomTint)
        // A scope change re-tints the bar on the same beat the crown re-tints
        // (`MainSurface.crownPour` animates the same value) — the two ends of
        // the screen answering one move, rather than a hard swap down here
        // under a gradient that glided.
        .animation(DS.Motion.standard, value: roomTint)
        // The whole pill, not a per-icon zone: at ~110pt there isn't room to
        // split one hold between two targets, and the tray it opens belongs to
        // the bar as a whole rather than to asking or to finding.
        // `simultaneous`, so the two Buttons above keep their own taps — each
        // guards on `consumeHold()` for the release that follows a hold.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                // Cleared when the NEXT press BEGINS, never on a timer. A timer
                // has to guess how long a finger stays down, and it guesses
                // wrong in the most ordinary case there is: hold until the tray
                // appears, look at it, then let go — by which time a 900ms
                // clear has already expired and the release raises the agent on
                // top of the tray. Press-begin is the one moment that is always
                // before the release it has to swallow and always after the
                // last one, so a hold that ends by dragging off (no touch-up
                // inside, no button action, flag left set) can't eat the next
                // real tap either.
                .onChanged { _ in heldForSources = false }
                .onEnded { _ in
                    heldForSources = true
                    // The `DSHaptic.lift()` this used to fire here now lives on
                    // `RootShell.openSources()`, so the accessibility action
                    // below and the Mac menu get the same buzz the hold does.
                    // Timing is unchanged — the closure runs on this same
                    // threshold, which is the moment a gesture with no visible
                    // affordance has to say it was received.
                    onSources()
                }
        )
        .modifier(BarSecondaryMenu(onSources: onSources, onFind: onFind))
        .modifier(MorphMatch(ns: morphNS))
    }

    /// True if this touch-up is the tail of a hold that already acted.
    private func consumeHold() -> Bool {
        guard heldForSources else { return false }
        heldForSources = false
        return true
    }
}

/// The bar's verbs in words, for a pointer (2026-07-31) — Mac ONLY, and the
/// `#if` is load-bearing rather than tidiness.
///
/// The hold that opens the sources tray (0.45s, above) has no visible
/// affordance: a phone teaches that through repetition, a mouse never does,
/// because click-and-wait is not something anyone tries. A right-click states
/// both doors in words instead.
///
/// It cannot ship on iOS, though. `.contextMenu` installs its own ~0.5s
/// long-press recognizer, which on a touch screen would fire alongside the
/// bar's own hold — one press would open the tray AND raise a menu over it.
/// Under Catalyst there is no touch input, so the menu answers a secondary
/// click only and the two never meet.
private struct BarSecondaryMenu: ViewModifier {
    let onSources: () -> Void
    let onFind: () -> Void

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.contextMenu {
            Button {
                onSources()
            } label: {
                Label("Your sources", systemImage: "square.grid.2x2")
            }
            Button {
                onFind()
            } label: {
                Label("Find in your things", systemImage: "magnifyingglass")
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

/// The whisper's title, travelling (2026-07-22, prd §167a) — pairs the
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
