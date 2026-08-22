import SwiftUI

/// The A–Z scrubber down the trailing edge of the address book (2026-08-22,
/// prd §440).
///
/// **Present letters only, never a full A–Z.** A strip offering `Q` on a book
/// with no Q is a control that does nothing, which is §83's ban on dead
/// controls wearing twenty-six tiny copies. It also means the strip is SHORT
/// on a small book, which is honest about how big the book is — and it is why
/// the letters are handed in rather than generated: `AddressBookShape.index`
/// derives them from the sections actually rendered, so the strip and the list
/// can never disagree about which headings exist.
///
/// **A drag scrubs, a tap jumps.** Both go through the same callback, and the
/// callback fires only when the letter CHANGES — without that, a slow drag
/// down the strip sends one `scrollTo` per frame and the list stutters against
/// its own animation.
///
/// It is deliberately not a `UITableView` section index: this is a `List` with
/// `Section`s inside a `ScrollViewReader`, and the system index is only
/// available to a table view that owns its own data source.
struct AddressIndexBar: View {
    let letters: [String]
    var onPick: (String) -> Void

    /// The letter under the finger right now, so a scrub can tell "moved to a
    /// new letter" from "moved four points inside the same one".
    @State private var active: String?
    /// Where that letter sits, in this bar's own space — the bubble's vertical
    /// anchor. Held rather than derived from `active`'s index so the bubble
    /// tracks the FINGER through a letter's full height rather than jumping in
    /// 13.5pt steps.
    @State private var touchY: CGFloat = 0

    /// Tight enough that a 27-letter book fits a phone, loose enough to aim
    /// at. The strip is not the primary way to move — the search field is —
    /// so it is allowed to be small; what it must not be is ambiguous, which
    /// is what the highlight below is for.
    private static let rowHeight: CGFloat = 13.5

    var body: some View {
        // Below three letters there is nothing to scrub between: a strip of
        // two is chrome that costs a column of the row width it sits over.
        if letters.count >= 3 {
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .dsText(.tab10).fontWeight(.semibold)
                        .foregroundStyle(active == letter ? DS.tint : DS.textTertiary)
                        .frame(height: Self.rowHeight)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 18)
            .padding(.vertical, DS.Space.s2)
            .background {
                // Only while scrubbing. A permanent pill would sit over the
                // list's own trailing edge on every screen; the strip itself
                // is legible without one.
                if active != nil {
                    Capsule().fill(DS.fillFaint)
                }
            }
            // THE BUBBLE (prd §441) — the letter you are on, beside the finger.
            //
            // The strip is 18 points wide and its type is 10pt, which is right
            // for a resting index and far too small to read WHILE your thumb is
            // over it. Both Apple's and Cash App's indexes answer this the same
            // way: a large glyph offset to the leading side, where the finger
            // is not.
            //
            // An overlay on the bar rather than on the screen, so it cannot
            // fight the list's own scroll for the same coordinate space; it
            // draws outside the bar's bounds, which is what `.leading` and a
            // negative offset buy.
            .overlay(alignment: .topLeading) {
                if let active {
                    Text(active)
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .frame(width: 46, height: 46)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: -54, y: touchY - 23)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Tracked continuously so the bubble follows the
                        // finger; the CALLBACK below still fires only on a
                        // change of letter.
                        touchY = value.location.y
                        let index = Int(value.location.y / Self.rowHeight)
                        guard letters.indices.contains(index) else { return }
                        let letter = letters[index]
                        // Only on CHANGE — see the type's own note.
                        guard letter != active else { return }
                        withAnimation(DS.Motion.press) { active = letter }
                        DSHaptic.selection()
                        onPick(letter)
                    }
                    .onEnded { _ in
                        withAnimation(DS.Motion.standard) { active = nil }
                    }
            )
            .padding(.trailing, 2)
            // One control, not twenty-seven — VoiceOver scrubs the list with
            // the rotor and reads the headings themselves; a per-letter button
            // here would put the whole alphabet in its path twice.
            .accessibilityElement()
            .accessibilityLabel(Text("Index"))
            .accessibilityHidden(true)
        }
    }
}
