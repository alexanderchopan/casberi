import SwiftUI

/// **A PLACE WITH NOTHING IN IT SAYS WHAT IT WOULD HOLD (prd §611, drawn
/// once by §715, 2026-09-13; redrawn as skeletons by §769 and §770).**
///
/// Two forms, and both draw what would fill the place, empty:
///
/// - `.room(figure)` — a room's lead: the scope's own figure as a still
///   skeleton (`DSSkeletonFigure`), the short state centred on it at the
///   lead's words rung (`heading24`, §766).
/// - `.list(rows:)` — anywhere a list would stand: `DSSkeletonRows` in the
///   feed row's anatomy, the short state centred on them.
///
/// `words` is what VoiceOver reads — the drawing already shows what the
/// place holds, and a paragraph over it was the weak state §769 replaced.
/// `note` is the one exception, and it is for a fact the drawing cannot say
/// and the person needs to act on or not be misled by (§748's honesty and
/// fix-it lines): "One match under Layer 3", "Solana can't be read yet".
///
/// Static, always: no shimmer, because a moving skeleton means "loading" and
/// these mean "empty" (§83). No door — a way out is the caller's.
struct DSEmptyState: View {
    enum Scale: Equatable {
        case room(DSSkeleton.Figure)
        case list(rows: Int)
    }

    var headline: Text? = nil
    let words: Text
    var scale: Scale = .list(rows: 3)
    /// A fact the skeleton cannot say, drawn under the headline. Nil for
    /// almost every caller.
    var note: Text? = nil
    /// How far a room skeleton stops short of the trailing edge — the rooms
    /// that keep their drawings clear of the settings gear pass
    /// `DSRoomChassis.gearColumn`. The words stay centred in the whole box.
    var clearance: CGFloat = 0

    var body: some View {
        switch scale {
        case .room(let figure):
            ZStack {
                DSSkeletonFigure(figure: figure)
                    .padding(.trailing, clearance)
                statement
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(Spoken(headline: headline, words: words, note: note))
        case .list(let rows):
            ZStack {
                DSSkeletonRows(count: rows)
                statement
            }
            .frame(maxWidth: .infinity)
            .modifier(Spoken(headline: headline, words: words, note: note))
        }
    }

    @ViewBuilder private var statement: some View {
        if headline != nil || note != nil {
            VStack(spacing: DS.Space.s2) {
                if let headline {
                    headline
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                }
                if let note {
                    note
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Space.s4)
        }
    }

    /// One element: the headline as its label, the words (and the note) as
    /// its value.
    private struct Spoken: ViewModifier {
        let headline: Text?
        let words: Text
        let note: Text?

        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headline ?? words)
                .accessibilityValue(value)
        }

        private var value: Text {
            let spoken = headline == nil ? Text(verbatim: "") : words
            guard let note else { return spoken }
            return spoken + Text(verbatim: " ") + note
        }
    }
}
