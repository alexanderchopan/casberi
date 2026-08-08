import SwiftUI

/// THE CURSOR ROOM'S HEAD (2026-08-08, prd §340) — what your coding agents
/// actually did, and where.
///
/// The anatomy is `AppStoreConnectRoomCard`'s, which took it from
/// `StripeRoomCard` and `CloudflareRunwayCard`: a kicker in the card's one hue,
/// a heavy headline stating the whole finding as a sentence, ranked rows, and
/// no decoration that isn't a reading. What was ruled out there is out here —
/// no coloured rail down a row's side, and **no green/red**: a repository with
/// broken runs is stated in words and by its position, never painted, exactly
/// as a Stripe dispute is.
///
/// ## The one drawing, and what it means
///
/// A `ShareBar` per repository, scaled against the busiest one, encoding ONE
/// thing: how much of your agent time went here. It is deliberately not a
/// pass/fail split bar — a two-tone bar invites reading the ratio as a success
/// rate, which over the newest thirty runs is a statistic nobody chose the
/// window for (§83). The failures are counted in words beside it, where a
/// number can be exact.
///
/// ## The kicker's hue
///
/// Cursor's brand is pure black by their own guidance — the Grok/X case, a
/// genuinely monochrome mark rather than a logo-on-black lockup. Black text on
/// the dark theme is invisible and on the light theme is indistinguishable from
/// body ink, so the kicker takes `DS.legibleCardFill`, the design layer's
/// existing substitution for exactly this (a too-dark brand hue lifts toward
/// the app tint). The identity here is the word.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `CursorRoom`, filtered at the
/// boundary by `CursorRoomSource`. The tap hands back a `Repo` and the section
/// that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson, paid three times).
struct CursorRoomCard: View {
    let room: CursorRoom
    /// Hands back the REPOSITORY, not a `Thing` — the card never holds one.
    /// A repo owns many rows, so there is no single `sourceRef` it could name.
    var onOpen: (CursorRoom.Repo) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Cursor")

    private var drawn: [CursorRoom.Repo] {
        Array(room.repos.prefix(CursorRoomSource.rowCap))
    }

    /// The busiest repository's run count — the bar's full width, so every bar
    /// on the card is on one scale and two rows are comparable at a glance.
    private var top: Int { room.lead?.runs ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Cursor"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(CursorRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            // Only the repositories BEYOND the lead get a row — the lead is the
            // headline, and repeating its name directly underneath is the card
            // arguing with itself. Its own line and bar still draw, because
            // neither is carried by the headline.
            if let lead = room.lead {
                Text(CursorRoom.repoLine(lead))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
                ShareBar(fraction: CursorRoom.share(runs: lead.runs, of: top),
                         reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
            }

            if drawn.count > 1 {
                ForEach(Array(drawn.dropFirst().enumerated()), id: \.element.id) { index, repo in
                    row(repo, index: index)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s3)
            }

            if let note = CursorRoom.note(room, drawn: drawn.count) {
                Text(note)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let lead = room.lead else { return }
            DSHaptic.selection()
            onOpen(lead)
        }
    }

    // MARK: - Rows

    private func row(_ repo: CursorRoom.Repo, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(repo)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(repo.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: DS.Space.s2)
                    Text(CursorRoom.repoLine(repo))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                // The stagger index is shared with the row's own arrival, so a
                // bar lands with the row that owns it rather than on a cadence
                // of its own (one beat per row — `ChartEntrance`'s rule).
                ShareBar(fraction: CursorRoom.share(runs: repo.runs, of: top),
                         index: index + 1,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(repo.name), \(CursorRoom.repoLine(repo))"))
    }
}
