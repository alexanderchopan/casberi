import SwiftUI
import SwiftData

/// The standing "this is the demo" bar (see `DemoMode`).
///
/// **Not decoration — it is the honesty rule's price for the demo existing.**
/// A furnished demo puts a fake Stripe dispute, a fake $12,480 crown and 68
/// rooms of somebody else's life into the app's ORDINARY chrome, where every
/// other number is real. §83 bans fake status, and the only thing that keeps
/// this on the right side of that line is saying so continuously, in the same
/// frame as the numbers.
///
/// So three properties are load-bearing, and each is a way this could quietly
/// stop being honest:
///   • **Never dismissible.** A banner you can close is a banner that is gone
///     for the rest of the session, and the demo outlives any one screen.
///   • **Always carries the way out.** The exit is ON the marking, not filed
///     in Settings — the moment someone wants their own app back is the
///     moment they are reading this.
///   • **Rides the shell, not the feed.** It is hosted in `RootShell`'s own
///     stack for the agent bar's reason: the demo is just as fake inside a
///     pushed room, the Apps catalog or a bridge setup screen.
///
/// The verb is EXIT, never "delete" — nobody chose to keep any of this, so
/// asking them to delete it would be asking them to take responsibility for
/// rows the app poured in.
struct DemoBanner: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One slow breath on arrival — the ENTRANCE. The standing pulse that
    /// follows it is the glyph's own (see `body`).
    @State private var settled = false
    @State private var explaining = false
    /// Set by the sheet's Exit, consumed by its `onDismiss` — the landing
    /// must wait until the tray is fully DOWN. `present(.apps)` is a
    /// `navigationDestination` PUSH, and SwiftUI intermittently drops one
    /// made under a presented cover (the drop class `RootShell` documents at
    /// length: "Browse the catalog sometimes doesn't work"). The old landing
    /// was immune by accident — `path = []` is a clear, not a push — so §863
    /// inherited the trap the moment it gave the exit somewhere to go.
    @State private var leavingOnDismiss = false

    /// **A STATUS, NOT A BAR (2026-09-05, user: "we could improve the banner
    /// … user can tap it and figure it out").** The full-width glass pill —
    /// sparkle, a nine-word sentence, Exit — was the heaviest chrome on the
    /// screen, sitting above the room's own hero on every demo screen. What
    /// the honesty rule (§83) needs is that the marking is CONTINUOUS and
    /// carries its way out; it does not need the whole sentence in every
    /// frame. So: one tinted capsule with the mark and the word, leading, at
    /// the size of a recording indicator. A tap opens the sentence and the
    /// two verbs, and since 2026-09-18 the capsule NAMES that tap. Still
    /// never dismissible, still on the shell.
    /// The lead is on screen AND this is the screen it is on. The second half
    /// is not belt-and-braces: rooms are paged and a built page stays mounted,
    /// so the lead's `onDisappear` is not promised on a room change or a push.
    private var yields: Bool {
        chrome.demoLeadVisible && filter.source == "All" && filter.tag == "All"
            && route.path.isEmpty
    }

    var body: some View {
        Button {
            DSHaptic.tap()
            explaining = true
        } label: {
            HStack(spacing: DS.Space.s2) {
                // **THE SIGNAL, and the only colour the capsule carries (prd
                // §679, 2026-09-10).** Blue (2026-09-09) was `DS.tint` — the
                // one hue every live control in the app wears, the dock's
                // lozenge included — so a marker meaning "none of this is
                // real" wore the colour that everywhere else means "this is
                // yours and live". Amber is the platform's word for
                // non-production, and it is used here as a DOT and a WORD,
                // never as the capsule's fill: `DS.attention` already means
                // "a seat is broken" (the dashed ring, the catalogue door's
                // mark), and every one of those is amber INK on a dark
                // ground, so a filled amber pill would have read as that.
                //
                // The dot is an SF Symbol so the pulse stays a symbol effect
                // — the render server drives it and the shell pays nothing
                // per frame (§651, §660). The halo behind it is a static
                // gradient, not a second animation.
                // A flat dot (prd §783): the halo and the pulse were the tell.
                Image(systemName: "circle.fill")
                    .dsGlyph(.tick)
                    .foregroundStyle(DS.attention)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text("Demo")
                    .dsText(.label12)
                    .foregroundStyle(DS.attention)
                Text(verbatim: "·")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
                // The sentence the accessibility label below has always
                // spoken, on screen at last: "Demo" alone can be read as a
                // mode somebody turned on; naming the things removes that
                // reading. **And the way out is on the capsule (user,
                // 2026-09-18: "not everyone realizes it's a demo, and even
                // if they do, they may not know how to exit it").** The
                // capsule has carried the exit since §620, but only as a
                // destination behind a tap nothing named — so the tap was
                // discoverable by accident. Naming it costs three words and
                // is the honesty rule's own second half: the marking carries
                // the way out, and now it says so.
                Text("Not your things. Tap to exit.")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 34)
            // **GLASS, a step brighter than the dock's (prd §679).** The
            // banner is floating chrome, which is the one layer §8 gives
            // Liquid Glass to — but the dock is glass too, so plain glass
            // here reads as a control. The light tint lifts it off the
            // slab; the amber above is what says what it is. On the pre-26
            // fallback the tint is faint and the amber does all the work,
            // which is why the amber is not optional.
            .dsGlass(cornerRadius: DS.Radius.pill, tint: .white.opacity(0.35))
            .contentShape(Capsule(style: .continuous))
            .frame(minHeight: DS.Hit.min)
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityLabel(Text("Demo — not your things"))
        .accessibilityHint(Text("Opens the way out"))
        .padding(.horizontal, DS.Space.s4)
        .scaleEffect(settled ? 1 : 0.92)
        // NEVER BOTH IN ONE FRAME (user, 2026-09-20: "why would we need to
        // say demo twice here"). While the All feed's `DemoLead` is on screen
        // it IS the marking, so the capsule stands down — by opacity, never
        // by unmounting: this rides a safe-area inset, and an inset that came
        // and went with the scroll would move the list under the finger.
        .opacity(settled && !yields ? 1 : 0)
        .allowsHitTesting(!yields)
        .accessibilityHidden(yields)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: yields)
        .onAppear {
            guard !settled else { return }
            if reduceMotion { settled = true }
            else { withAnimation(DS.Motion.standard.delay(0.35)) { settled = true } }
        }
        .sheet(isPresented: $explaining, onDismiss: {
            guard leavingOnDismiss else { return }
            leavingOnDismiss = false
            leave()
        }) {
            DemoExplainSheet(leave: { leavingOnDismiss = true; explaining = false })
        }
    }

    /// Land on ACCOUNTS (user, 2026-09-20, reversing 2026-08-31's "land on
    /// the feed"): the exit is the one moment somebody has seen what the app
    /// becomes and owns none of it, and the empty feed asked nothing of them.
    /// With nothing connected the screen seeds itself to Connect.
    ///
    /// Replacing the stack is not tidiness — a pushed room whose rows
    /// have just been deleted is a screen about nothing, and on this codebase
    /// it is also the SwiftData liveness class (a held `Thing` read after a
    /// delete), so leaving someone standing in one is the one landing that
    /// could actually crash.
    private func leave() {
        DemoLeave.run(context: modelContext, store: store, route: route,
                      filter: filter, chrome: chrome)
    }
}

/// The way out, shared by the capsule's sheet and the All feed's `DemoLead`.
/// The DEBUG door that takes the demo's marking out of a marketing capture
/// (`-hideDemoBanner YES`, 2026-09-08). ONE definition, read by the capsule's
/// host and by `DemoLead`: §864 put a second marking on screen, and a door
/// that removes one of two is a door that removes neither — the pill was
/// painted out of every still by hand until this flag, and a preview video
/// cannot be painted at all. DEBUG only, so no shipped build can read it.
@MainActor
enum DemoCapture {
    static var hidesMarking: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "hideDemoBanner") != nil
        #else
        return false
        #endif
    }
}

@MainActor
enum DemoLeave {
    static func run(context: ModelContext, store: BridgeStore, route: HomeRoute,
                    filter: FeedFilter, chrome: ShellChrome) {
        guard !chrome.demoLeaving else { return }
        chrome.demoLeaving = true
        Task { @MainActor in
            // Let the fade play, THEN delete — one transaction, with nothing
            // on screen to re-render through it.
            try? await Task.sleep(for: .milliseconds(420))
            DemoMode.exit(context: context, store: store)
            filter.source = "All"
            filter.tag = "All"
            route.present(.apps)
            chrome.demoLeaving = false
            chrome.demoLeadVisible = false
        }
    }
}

/// **The demo, said where people read (user, 2026-09-20: "i had a user land
/// on demo and not realize").** The capsule is chrome, and chrome at the top
/// edge is read as status; this is the same fact at the head of the All feed,
/// at the lead's words rung, with the way out as a row under it (§746: a verb
/// is a row). Flat — no plate, no well (§749, §782). It scrolls away with the
/// feed, and the capsule takes over the moment it has (`demoLeadVisible`), so
/// the marking stays continuous (§83) without ever being said twice.
///
/// The exit is direct: the sentence above the row is the whole of what
/// `DemoExplainSheet` would have said.
struct DemoLead: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(FeedFilter.self) private var filter
    @Environment(ShellChrome.self) private var chrome

    /// The catalog's own sentence with the catalog's own word found inside
    /// it, so every language keeps its word order and still gets the amber.
    private static var statement: AttributedString {
        var line = AttributedString(String(localized: "This is a demo."))
        if let word = line.range(of: String(localized: "Demo"), options: .caseInsensitive) {
            line[word].foregroundColor = DS.attention
        }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            // "demo" in the capsule's amber — one signal in three places:
            // the cover's letter tiles, this word, the capsule's dot.
            Text(Self.statement)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("None of it is yours.")
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                DSHaptic.tap()
                DemoLeave.run(context: modelContext, store: store, route: route,
                              filter: filter, chrome: chrome)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .dsGlyph(.caption, weight: .regular)
                        .frame(width: 18, alignment: .center)
                        .accessibilityHidden(true)
                    Text("Exit the demo")
                        .dsText(.body17)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.tint)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        }
        // THE VIEWPORT, NOT THE CELL. `onAppear`/`onDisappear` in a `List`
        // track cell recycling, which lags the viewport by most of a screen:
        // scrolling the lead just out of sight would leave the flag true and
        // the capsule still standing down, so the demo would show a fake
        // crown and somebody else's rooms with NO marking anywhere — the
        // continuous marking §83 charges the demo for, failing exactly where
        // §864 was meant to fix it. `onScrollVisibilityChange` answers the
        // question actually being asked.
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            chrome.demoLeadVisible = visible
        }
        .onDisappear { chrome.demoLeadVisible = false }
    }
}

/// The sentence the capsule stands for, and the two verbs — the way out, and
/// the way back to looking. The verb is EXIT, never "delete" — nobody chose
/// to keep any of this, so asking them to delete it would be asking them to
/// take responsibility for rows the app poured in.
private struct DemoExplainSheet: View {
    let leave: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// What the content below the title measures — `trayHeight`'s whole
    /// input. 0 until the first layout pass.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        DSTray(title: "This is a demo.", height: trayHeight) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // ONE LINE (user, 2026-09-05: "this wording is long"). What
                // happens on exit is said by the verb below it.
                // "Exit whenever you're ready" restated the verb under it
                // (prd §748).
                Text("None of it is yours.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DS.Space.s3)
                DSActVerb(title: "Exit the demo") { leave() }
                Button {
                    DSHaptic.tap()
                    dismiss()
                } label: {
                    Text("Keep looking")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                contentHeight = $0
            }
        }
    }

    /// Sized to its content (user, 2026-09-05: "this tray needs to be
    /// shortened, there is a gap that doesn't need to be there") — MEASURED
    /// rather than a tuned constant, so a wrapped sentence or a larger text
    /// size cannot reopen the gap or clip "Keep looking". `DSTray`'s chrome is
    /// "pad, title, gap, … pad"; the fallback lasts one layout pass.
    private var trayHeight: CGFloat {
        let chrome = DS.Space.s6 + 40 + DS.Space.s4 + DS.Space.s6
        return (contentHeight > 0 ? contentHeight : 224) + chrome
    }
}
