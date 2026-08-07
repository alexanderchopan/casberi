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

    /// One slow breath on arrival, then still for the rest of the session.
    ///
    /// Noticed ONCE is the requirement — the banner has to be seen, or it
    /// isn't marking anything. Noticed continuously is a nag, and a nag on a
    /// bar that cannot be dismissed is the worst of both. So this is a single
    /// entrance, not a `repeatForever` breathe: the design-motion audit would
    /// flag the latter, and it would be right to.
    @State private var settled = false

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Demo — none of this is yours")
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: DS.Space.s2)

            Button {
                DSHaptic.tap()
                leave()
            } label: {
                Text("Exit")
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s1)
        .padding(.vertical, DS.Space.s1)
        .dsGlass(cornerRadius: DS.Radius.pill)
        .padding(.horizontal, DS.Space.s4)
        .scaleEffect(settled ? 1 : 0.92)
        .opacity(settled ? 1 : 0)
        .onAppear {
            guard !settled else { return }
            if reduceMotion { settled = true }
            else { withAnimation(DS.Motion.standard.delay(0.35)) { settled = true } }
        }
    }

    /// Land on the FORK, not on the empty feed and not in the catalog.
    ///
    /// This is the whole reason the demo is worth having. Someone who has just
    /// watched a furnished app fill up now has the question "so which of MY
    /// things?" — which is precisely what the fork asks, and it is the same
    /// screen that read as premature when it ran before any evidence existed.
    /// The catalog was the other candidate and is one tap away on that screen;
    /// it is not the landing, because §217 already ruled that sixty-odd tiles
    /// is a wall to survey and three verbs is a fork you answer in a second.
    ///
    /// Resetting the stack first is not tidiness — a pushed room whose rows
    /// have just been deleted is a screen about nothing, and on this codebase
    /// it is also the SwiftData liveness class (a held `Thing` read after a
    /// delete), so leaving someone standing in one is the one landing that
    /// could actually crash.
    private func leave() {
        guard !chrome.demoLeaving else { return }
        chrome.demoLeaving = true
        Task { @MainActor in
            // Let the fade play, THEN delete — one transaction, with nothing
            // on screen to re-render through it.
            try? await Task.sleep(for: .milliseconds(420))
            DemoMode.exit(context: modelContext, store: store)
            filter.source = "All"
            filter.tag = "All"
            route.path = [.startHere]
            chrome.demoLeaving = false
        }
    }
}
