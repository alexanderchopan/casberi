import SwiftUI

/// **A PLACE WITH NOTHING IN IT SAYS WHAT IT WOULD HOLD (prd §611, drawn
/// once by §715, 2026-09-13; the room form redrawn by §769).**
///
/// - `.room(figure)` — a room's lead: the scope's own figure as a still
///   skeleton (`DSSkeletonFigure`), and the short state centred on it at the
///   lead's words rung (`heading24`, §766). Nothing else is drawn: `words` is
///   what VoiceOver reads, because the drawing already shows what the scope
///   holds and a paragraph over it was the weak state §769 replaced.
/// - `.inline` — under a list or in a sheet: `body17` semibold, `subhead12`.
///
/// No door. A way out is the caller's, and most empty states have none.
struct DSEmptyState: View {
    enum Scale: Equatable {
        case room(DSSkeleton.Figure)
        case inline
    }

    var headline: Text? = nil
    let words: Text
    var scale: Scale = .inline
    /// How far the skeleton stops short of the trailing edge — the rooms that
    /// keep their drawings clear of the settings gear pass
    /// `DSRoomChassis.gearColumn`, so the empty figure ends where a real one
    /// would. The headline stays centred in the whole box.
    var clearance: CGFloat = 0

    var body: some View {
        switch scale {
        case .room(let figure):
            ZStack {
                DSSkeletonFigure(figure: figure)
                    .padding(.trailing, clearance)
                if let headline {
                    headline
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, DS.Space.s4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headline ?? words)
            .accessibilityValue(headline == nil ? Text(verbatim: "") : words)
        case .inline:
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let headline {
                    headline
                        .dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                }
                words
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
