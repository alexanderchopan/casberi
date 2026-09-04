import SwiftUI

/// THE INSTAGRAM ROOM'S HEAD (2026-08-18, prd §395) — the library, with the
/// accounts that fill it.
///
/// The anatomy is `XRoomCard`'s: kicker, heavy headline stating the finding as a
/// sentence, then ranked rows on one scale. What differs is what is missing —
/// there is no strip. X's fifteen years ARE the object, so its span is the
/// picture; here the object is a pile of other people's posts and the span is
/// one clause in the note. Drawing a per-year strip as well would be the same
/// card twice, and this room's own year grid (`FeedHeatmap`) still answers WHEN
/// underneath.
///
/// ## Why the board is here at all
///
/// This card displaces `FeedInsight.leaderboard`'s "Who you save most", and
/// §349 says a head may never draw less than what it displaces. So the board is
/// carried forward whole — same ranking, same `rowCap` — and the card adds the
/// three facts the board could not: how big the library is, how long it took,
/// and how much of it Instagram has since deleted.
///
/// ## No colour for more or less
///
/// One hue, one scale. Saving more from one account than another is not a win
/// and not a failure — `XRoomCard`'s restraint, in a room whose whole content is
/// somebody else's taste.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `InstagramRoom`, filtered at the
/// boundary by `InstagramRoomSource`. The tap hands back an `Account` and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
struct InstagramRoomCard: View {
    let room: InstagramRoom
    /// Hands back the ACCOUNT, not a `Thing` — an account owns many rows, so the
    /// honest landing is its newest kept post.
    var onOpen: (InstagramRoom.Account) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Instagram")

    /// The biggest account's count — every bar's full width, so the rows are on
    /// ONE scale and can't disagree with each other.
    private var top: Int { InstagramRoom.top(room) }

    private var lead: InstagramRoom.Account? { room.accounts.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            // THE LEDE (prd §585) — see `JournalRoomCard` for the rule.
            Group {
                if let lede = InstagramRoom.lede(room) {
                    RoomLedeView(lede: lede, spoken: InstagramRoom.headline(room))
                } else {
                    Text(InstagramRoom.headline(room))
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The whole card is a tap target for touch and pointer and
            // carries nothing for VoiceOver; this states the same verb on
            // the line that names its destination.
            .dsCardLead(Text("Opens the newest post you kept")) {
                DSHaptic.selection()
                if let lead { onOpen(lead) }
            }

            Text(InstagramRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            ForEach(Array(room.accounts.enumerated()), id: \.element.id) { index, account in
                row(account, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)

            if let footnote = InstagramRoom.footnote(room) {
                Text(footnote)
                    .dsText(.label12)
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
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.selection()
            if let lead { onOpen(lead) }
        }
    }

    // MARK: - Rows

    private func row(_ account: InstagramRoom.Account, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(account)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    // The "@" is spoken here rather than stored: `authorHandle`
                    // is the bare handle by ruling (`InstagramImport.landSaves`),
                    // precisely so that grouping never ranks the mark.
                    Text(verbatim: "@" + account.handle)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(InstagramRoom.accountLine(account, act: room.act))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: InstagramRoom.share(kept: account.kept, of: top),
                         index: index,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(account.handle), \(InstagramRoom.accountLine(account, act: room.act))"))
    }
}
