import SwiftUI

/// **A PLACE WITH NOTHING IN IT SAYS WHAT IT WOULD HOLD (prd §611, drawn
/// once by §715, 2026-09-13).**
///
/// Two tiers and no more: an optional headline and one paragraph. Before
/// §715 the room form was byte-identical in three room cards and a fourth
/// wrapped it, and the inline form was drawn at three rungs.
///
/// - `.room` — a room card's figure slot: `stat24` headline in the chassis's
///   reserved row, `body17` words. With no headline the words sit centred in
///   the slot; with one, both sit at the top.
/// - `.inline` — under a list or in a sheet: `body17` semibold, `subhead12`.
///
/// No door. A way out is the caller's, and most empty states have none.
struct DSEmptyState: View {
    enum Scale { case room, inline }

    var headline: Text? = nil
    let words: Text
    var scale: Scale = .inline

    var body: some View {
        switch scale {
        case .room:
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if let headline {
                    headline
                        .dsText(.stat24)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .frame(height: DSRoomChassis.headlineRow, alignment: .leading)
                }
                words
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: headline == nil ? .leading : .topLeading)
            .accessibilityElement(children: .combine)
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
