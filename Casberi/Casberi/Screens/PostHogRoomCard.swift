import SwiftUI

/// THE POSTHOG ROOM'S HEAD (2026-08-04, prd §298) — the metrics you watch, as
/// their own curves.
///
/// `MetricDisc` has existed since §223 and lived in two places people rarely
/// are: the setup screen's roster and a metric's detail sheet. The FEED room —
/// the surface you actually live in — led with plain rows. This is the same
/// disc, unchanged, at the room's head.
///
/// The anatomy is the room-head family's (kicker, headline, note, the drawing,
/// coverage note) and the roster below is `AssetRoster`'s slot, so a watched
/// metric wears exactly what a watched token does. Reusing both is the point:
/// this card introduces no new component at all.
///
/// ## Silent metrics lead, and that is the whole ordering
///
/// A metric that stopped firing is the most valuable thing analytics can tell
/// someone who ships (§223), and it is precisely the one a volume sort buries —
/// it has no volume left. `PostHogRoom.ranked` puts it first; this card just
/// draws the order it is given.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `PostHogRoom`, filtered at the
/// boundary by `PostHogRoomSource`. The tap hands back the EVENT NAME, and the
/// section that owns the sheet does the lookup.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
struct PostHogRoomCard: View {
    let room: PostHogRoom
    /// Opens the metric's own row. The card holds no `Thing`, so it hands back
    /// the event name the caller can resolve.
    var onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "PostHog") ?? Color.fixed("#f54e00")

    private var drawn: [PostHogRoom.Metric] {
        Array(room.metrics.prefix(PostHogRoomSource.discCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "PostHog"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(PostHogRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(PostHogRoom.note(room, nextRung: PostHogMilestone.next(after:)))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            roster
                .padding(.top, DS.Space.s4)

            if let note = PostHogRoom.coverageNote(shown: drawn.count,
                                                   total: room.metrics.count,
                                                   unread: room.unread) {
                Text(note)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    /// The discs, in the order the model ranked them — silent first, then
    /// busiest — each arriving in that same order, so the entrance narrates the
    /// ranking rather than decorating it.
    private var roster: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            ForEach(Array(drawn.enumerated()), id: \.element.id) { index, metric in
                slot(metric)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            Spacer(minLength: 0)
        }
    }

    private func slot(_ metric: PostHogRoom.Metric) -> some View {
        AssetRosterSlot(label: metric.event, change: metric.change) {
            MetricDisc(series: metric.series,
                       // No ring at zero — absent, not zeroed. Unread and
                       // genuinely-empty are indistinguishable, and a ring
                       // drawn at 0% would claim the latter (§223).
                       progress: metric.total > 0
                           ? PostHogMilestone.progress(metric.total) : 0,
                       change: metric.change)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            onOpen(metric.event)
        }
        .dsTapCard()
    }
}
