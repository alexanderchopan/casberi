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
    /// blue — the app's own word for "tap me". One clause and one verb: the
    /// fact, then `Exit`. The exit is DIRECT — a control that
    /// says Exit and then asks is a confirmation nobody asked for, and the
    /// sheet that used to sit behind the tap (`DemoExplainSheet`) is deleted
    /// with it. Still never dismissible, still on the shell.
    var body: some View {
        DSDemoPill {
            HStack(spacing: DS.Space.s2) {
                Text("Demo")
                    .dsText(.body17)
                Text(verbatim: "·")
                    .dsText(.body17)
                    .accessibilityHidden(true)
                // `None of it is yours.` wrapped at the row's rung (measured).
                // Three words say the same fact (§813's reason: "Demo" alone
                // reads as a mode somebody turned on; naming the things
                // removes that).
                Text("Not your things")
                    .dsText(.body17)
                    .fixedSize(horizontal: false, vertical: true)
                // Weight carries the verb (§764): the fact is regular, the
                // door is the heavier rung.
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
        // THE ONE MARKING, EVERYWHERE (prd §946). All used to lead with its
        // own `DemoLead` and this stood down under it (§864); once the pill
        // carried the same fact and the same Exit (§919) the two were the
        // demo said twice, so the lead is deleted and this never yields.
        .opacity(settled ? 1 : 0)
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

/// The way out.
/// The DEBUG door that takes the demo's marking out of a marketing capture
/// (`-hideDemoBanner YES`, 2026-09-08). ONE definition, read by the pill's
/// host and by `DSDemoMark.marking` — the pill was painted out of every still
/// by hand until this flag, and a preview video cannot be painted at all.
/// DEBUG only, so no shipped build can read it.
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
        }
    }
}
