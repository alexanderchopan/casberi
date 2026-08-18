import SwiftUI

/// THE GITHUB ROOM'S HEAD (prd §401) — what is waiting on you.
///
/// The anatomy is `CursorRoomCard`'s, which took it from `StripeRoomCard`: a
/// kicker in the card's one hue, a heavy headline stating the finding as a
/// sentence, ranked rows, and no decoration that isn't a reading.
///
/// ## No drawing at all, deliberately
///
/// Its neighbours carry one figure each — a share bar, a runway, a rail —
/// because each has a magnitude worth comparing. This card has none. Three
/// asks and a handful of rows is not a distribution, and the room already
/// leads on *quantity* with the contributions heatmap; a second quantitative
/// figure here would say the same kind of thing twice while the actual reading
/// (something is waiting on YOU) is a fact, not an amount.
///
/// ## The wording carries a date distinction the data cannot
///
/// Every row says "last moved", never "waiting N days". `capturedAt` here is
/// GitHub's `updated_at` for the notification THREAD, so a review requested on
/// Monday whose author pushed a fixup on Friday would read as one day old when
/// it has been waiting five. That gap is invisible and would be believed, so
/// the card refuses the stronger sentence rather than qualifying it in fine
/// print. (Contrast `RadicleRoomCard`, whose ages come from the record and may
/// therefore say "open since".)
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `GitHubRoom`, filtered at the
/// boundary by `GitHubRoomSource`. A tap hands back the row's `sourceRef` and
/// the section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson, paid three times).
struct GitHubRoomCard: View {
    let room: GitHubRoom
    /// Hands back the row's `sourceRef`, never a `Thing`.
    var onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "GitHub")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "GitHub"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(room.headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
                .dsCardLead(Text("Opens what is waiting")) {
                    guard let first = room.items.first else { return }
                    DSHaptic.selection()
                    onOpen(first.ref)
                }

            if let subline = room.subline {
                Text(subline)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }

            ForEach(Array(room.items.enumerated()), id: \.element.ref) { index, item in
                row(item, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - Rows

    private func row(_ item: GitHubRoom.Item, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item.ref)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(item.title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Space.s2) {
                    Text(item.ask.line)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                    Text(lastMoved(item))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.vertical, DS.Space.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(item.ask.line). \(item.title). \(lastMoved(item))"))
    }

    /// "Last moved" and never "waiting" — see this file's own header for why
    /// the weaker sentence is the honest one.
    private func lastMoved(_ item: GitHubRoom.Item) -> String {
        String(localized: "Last moved \(item.lastMoved.formatted(.relative(presentation: .named)))")
    }
}
