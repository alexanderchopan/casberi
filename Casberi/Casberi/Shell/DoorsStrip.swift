import SwiftUI

/// The octopus's folder: the four destinations that are NOT a feed, opened as
/// a row above the dock exactly the way a category chip opens its venues
/// (prd §591 amendment, 2026-09-03, user: *"the octopus button needs to open
/// the same way the others do in a strip"* — *"not in a tray"* — *"and also
/// doesn't anymore need 'all'"*).
///
/// **One mechanism for every chip in the dock.** A category chip is a folder:
/// tap it and its sources appear in a row above the strip, tap it again and
/// they go, and the room changes only when you pick one. The agent bar is the
/// dock's first chip, so it is a folder too, and this is what is inside it —
/// the agent, the catalogue, the address book and settings. The tray this
/// replaces (`SourcesOverlay` + `SourcesTray`, then a one-day `DoorsPanel`)
/// was a second presentation grammar for the same idea, raised from the bottom
/// edge over the surface the dock already sits on.
///
/// **Marks, not rows, and no captions** — the venue switcher's own grammar
/// (`CategoryVenueSwitcher`): a recognisable mark in a circle, `DS.Face.list`
/// at rest and folding to `DS.Face.row` on the same scroll signal the switcher
/// and the face rails fold on (§541: two rows above the dock that fold apart
/// read as a twitch). Every mark here is one a person already knows — the
/// berry from the bar they just tapped, the grid the catalogue has always worn,
/// the contact card both wallet rails draw for the book (§461), and their own
/// avatar for settings — so a word under each would be saying what the mark
/// already said. VoiceOver and the Mac's hover tooltip get the names.
///
/// **No "All" capsule.** The tray's header carried one as the always-present
/// road home (§407). "All" is a chip in the dock now, one flick from anywhere,
/// and this row is not a picker over rooms.
///
/// **The agent is a mark here, and that is the cost this arrangement was
/// chosen with.** Asking is a tap and a tap where it was one hidden gesture
/// (§390's hold, deleted in §591). Paid deliberately: one control, one tap,
/// everything labelled, and the three-round argument about which of two
/// destinations an invisible gesture should hide is over. Every other route to
/// the agent — a typed ask, a kept-ask pill, the day strip, the quick action,
/// `casberi://ask?q=`, the widgets, ⌘K — still opens it directly and arrives
/// with the question in hand.
struct DoorsStrip: View {
    var compact: Bool
    let onAgent: () -> Void
    let onApps: () -> Void
    let onAddressBook: () -> Void
    let onSettings: () -> Void

    private var markSize: CGFloat { compact ? DS.Face.row : DS.Face.list }

    var body: some View {
        HStack(spacing: 2) {
            door("Settings", act: onSettings) { AvatarDoor() }
            door("Apps", act: onApps) { AppsDoor() }
            door("Address book", act: onAddressBook) {
                // The same glyph both wallet rails draw (§461), so the three
                // doors onto one screen cannot read as three destinations.
                Image(systemName: "person.text.rectangle")
                    .dsGlyph(markSize * 0.5, weight: .medium)
                    .foregroundStyle(DS.textPrimary)
            }
            door("Ask your things", act: onAgent) {
                // **NOT the berry (§591b, user: "the octopus logo opens a
                // second octopus logo for the chat, i think that should be a
                // bot icon").** The bar you just tapped IS the berry, so
                // repeating it as the first mark inside its own folder said
                // "this door leads back to the button you pressed" — the one
                // reading it must not have. The berry is the app's mark, and
                // every other door here wears the mark of what it opens, so
                // this one should wear the agent's.
                //
                // `bubble.left`, which is what `KindGlyph` already draws for a
                // chat row and for ChatGPT, Claude and Gemini — so the glyph a
                // person meets here is one this app has already taught them.
                // What the door opens is a conversation you ask questions in.
                //
                // The first cut used `bubble.left.and.text.magnifyingglass` and
                // it drew NOTHING on the simulator: an unavailable SF Symbol
                // renders as empty space rather than as an error, so the door
                // was a blank circle you could still press. Only use a symbol
                // this tree already draws somewhere, or look at it.
                Image(systemName: "bubble.left")
                    .dsGlyph(markSize * 0.46, weight: .medium)
                    .foregroundStyle(DS.textPrimary)
            }
        }
        .padding(4)
        // The capsule is the switcher's — `fillFaint`, never glass: this row
        // sits in the band's own scrim, which is chrome content scrolls under,
        // and design law puts Liquid Glass on the floating layer alone.
        .background { Capsule(style: .continuous).fill(DS.fillFaint) }
        .clipShape(Capsule(style: .continuous))
        // LEADING, like every other row in this band. An `HStack` inside the
        // band's `VStack` centres itself, which put this capsule in the middle
        // of the screen while the venue switcher and the face rails all start
        // at the same left edge as the dock below them — one row out of three
        // hanging in the middle reads as a different kind of object.
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.Motion.standard, value: compact)
    }

    @ViewBuilder
    private func door<Mark: View>(_ name: LocalizedStringResource,
                                  act: @escaping () -> Void,
                                  @ViewBuilder mark: () -> Mark) -> some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            mark()
                .frame(width: markSize, height: markSize)
                // A `.frame()` does not make its empty space hit-testable — the
                // catalogue door's own three bug reports (2026-07-26).
                .contentShape(Circle())
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .dsTooltip(String(localized: name))
        .accessibilityLabel(Text(name))
    }
}
