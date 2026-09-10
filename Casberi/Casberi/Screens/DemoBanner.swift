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

    /// **A STATUS, NOT A BAR (2026-09-05, user: "we could improve the banner
    /// … user can tap it and figure it out").** The full-width glass pill —
    /// sparkle, a nine-word sentence, Exit — was the heaviest chrome on the
    /// screen, sitting above the room's own hero on every demo screen. What
    /// the honesty rule (§83) needs is that the marking is CONTINUOUS and
    /// carries its way out; it does not need the whole sentence in every
    /// frame. So: one tinted capsule with the mark and the word, leading, at
    /// the size of a recording indicator. A tap opens the sentence and the
    /// two verbs. Still never dismissible, still on the shell.
    var body: some View {
        Button {
            DSHaptic.tap()
            explaining = true
        } label: {
            HStack(spacing: DS.Space.s1) {
                // **NOT `sparkles` (user, 2026-09-09): that glyph is the
                // AGENTS category's mark since §662, and two different things
                // in one frame wearing one symbol is the collision §662's own
                // table exists to avoid.** `eye` says you are LOOKING at
                // something rather than owning it, which is what this status
                // means; nothing else in the app draws it.
                Image(systemName: "eye")
                    .dsGlyph(12)
                    // **IT PULSES (user: "it should likely be pulsing so a
                    // user knows to tap it").** This overturns the 2026-09-05
                    // "noticed once" reasoning, and the overturn is narrow:
                    // that argument was against a NAG on chrome that cannot be
                    // dismissed, and it was made when the capsule was the only
                    // thing on the screen wearing the brand pink. In blue it
                    // is one tinted capsule among a screen of tinted controls,
                    // so nothing marks it as the one status that must be read
                    // before a number is believed (§83). A symbol effect, not
                    // an animated opacity: the render server drives it, so it
                    // costs the shell nothing per frame — which is the whole
                    // finding of §660 and §651, one surface over.
                    .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                Text("Demo")
                    .dsText(.label12)
                    .fontWeight(.semibold)
            }
            // **BLUE (user, 2026-09-09: "and probably make it blue"),
            // overturning the brand pink of 2026-09-05.** Recorded because
            // the pink had a reason worth keeping in view: it made the
            // marking read as the app speaking rather than as a warning, and
            // blue is `DS.tint`, the one accent every interactive thing in
            // the app already wears — including the active dock chip
            // directly under this capsule. What buys it back is the pulse
            // above: the capsule is now singled out by MOTION rather than by
            // hue, and the tint says "this is a control you may press",
            // which after §620 it is.
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 30)
            // A step past the rest-chip wash (user: "is it visible enough?")
            // — this is the one status on the screen that must be read before
            // any number is believed, so it wears the hue at a quarter.
            .background { Capsule(style: .continuous).fill(DS.tint.opacity(0.24)) }
            .contentShape(Capsule(style: .continuous))
            .frame(minHeight: DS.Hit.min)
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityLabel(Text("Demo — none of this is yours"))
        .accessibilityHint(Text("Opens the way out"))
        .padding(.horizontal, DS.Space.s4)
        .scaleEffect(settled ? 1 : 0.92)
        .opacity(settled ? 1 : 0)
        .onAppear {
            guard !settled else { return }
            if reduceMotion { settled = true }
            else { withAnimation(DS.Motion.standard.delay(0.35)) { settled = true } }
        }
        .sheet(isPresented: $explaining) {
            DemoExplainSheet(leave: { explaining = false; leave() })
                .dsNavSheet()
        }
    }

    /// Land on the FEED, not a question (2026-08-31): the catalogue answers
    /// "which of MY things?" better and is one tap away.
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
            route.path = []
            chrome.demoLeaving = false
        }
    }
}

/// The sentence the capsule stands for, and the two verbs — the way out, and
/// the way back to looking. The verb is EXIT, never "delete" — nobody chose
/// to keep any of this, so asking them to delete it would be asking them to
/// take responsibility for rows the app poured in.
private struct DemoExplainSheet: View {
    let leave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("This is a demo.")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                // ONE LINE (user, 2026-09-05: "this wording is long"). What
                // happens on exit is said by the verb below it.
                Text("None of it is yours. Exit whenever you're ready.")
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
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dsPageBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
        // Sized to its content (user, 2026-09-05: "this tray needs to be
        // shortened, there is a gap that doesn't need to be there").
        .presentationDetents([.height(292)])
        .dsPageSheet()
    }
}
