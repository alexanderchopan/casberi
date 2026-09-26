import SwiftUI
import SwiftData

/// The standing "this is the demo" mark (see `DemoMode`) — a blue pill that
/// floats over every demo screen (prd §919; the shape's reasons are on
/// `DSDemoMark`).
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
///   • **Rides the shell, not the feed.** It is a layer of `RootShell`'s own
///     stack, beside the dock's seat, for the seat's reason: the demo is just
///     as fake inside a pushed room, the Apps catalog or a bridge setup
///     screen — and as `MainSurface`'s inset (until §919) a push covered it.
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

    /// One slow breath on arrival — the ENTRANCE.
    @State private var settled = false

    /// **A BLUE PILL THAT FLOATS, WITH THE VERB ON IT (prd §919, 2026-09-25;
    /// `DSDemoMark` holds the geometry and the reasons).** Four restyles of a
    /// glass capsule and a real person still walked past it (§864); the user
    /// looked at glass, blue and white mocked on the real rooms and chose
    /// blue — the app's own word for "tap me", the colour the All lead's
    /// Exit row already wears. One clause and one verb: the sentence the lead
    /// says, then `Exit` with the lead row's glyph, so the door is the same
    /// at both places. The exit is DIRECT, as the lead's is — a control that
    /// says Exit and then asks is a confirmation nobody asked for, and the
    /// sheet that used to sit behind the tap (`DemoExplainSheet`) is deleted
    /// with it. Still never dismissible, still on the shell.
    /// The lead is on screen AND this is the screen it is on. The second half
    /// is not belt-and-braces: rooms are paged and a built page stays mounted,
    /// so the lead's `onDisappear` is not promised on a room change or a push.
    private var yields: Bool {
        chrome.demoLeadVisible && filter.source == "All" && filter.tag == "All"
            && route.path.isEmpty
    }

    var body: some View {
        DSDemoPill {
            HStack(spacing: DS.Space.s2) {
                Text("Demo")
                    .dsText(.body17)
                Text(verbatim: "·")
                    .dsText(.body17)
                    .accessibilityHidden(true)
                // The lead's sentence (`None of it is yours.`) is the long
                // form; beside the gear column the pill has ~318pt, and at
                // the row's rung the long form wrapped (measured). Three
                // words say the same fact (§813's reason: "Demo" alone reads
                // as a mode somebody turned on; naming the things removes
                // that).
                Text("Not your things")
                    .dsText(.body17)
                    .fixedSize(horizontal: false, vertical: true)
                // Weight carries the verb (§764): the fact is regular, the
                // door is the heavier rung, and the glyph is the lead row's.
                Text("Exit")
                    .dsText(.heading17)
                    .padding(.leading, DS.Space.s2)
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .dsGlyph(.caption, weight: .semibold)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
        } action: {
            DSHaptic.tap()
            leave()
        }
        .scaleEffect(settled ? 1 : 0.92)
        // NEVER BOTH IN ONE FRAME (user, 2026-09-20: "why would we need to
        // say demo twice here"). While the All feed's `DemoLead` is on screen
        // it IS the marking, so the pill stands down — by opacity, so the
        // layer's geometry never changes under a finger.
        .opacity(settled && !yields ? 1 : 0)
        .allowsHitTesting(!yields)
        .accessibilityHidden(yields)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: yields)
        .onAppear {
            guard !settled else { return }
            if reduceMotion { settled = true }
            else { withAnimation(DS.Motion.standard.delay(0.35)) { settled = true } }
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

/// The way out, shared by the pill and the All feed's `DemoLead`.
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
