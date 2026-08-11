import SwiftUI

/// THE SAFE ROOM'S HEAD (2026-08-11) — the signature queue as rings, ranked
/// "your turn" first then longest-waiting.
///
/// The anatomy is `RailgunRoomCard`'s, which is `PeerRoomCard`'s: a kicker in
/// the card's own hue, a heavy headline stating the finding as a sentence,
/// ranked rows, no decoration that isn't a reading. What differs is the mark:
/// every sibling room draws a `ShareBar` because its subject is a PROPORTION
/// (which token, which rail); a Safe's subject is a COUNT toward a
/// threshold, so each row wears its own `SafeSignatureDisc` instead —
/// `SafeQueueCard`'s own ring, reused rather than redrawn.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `SafeRoom`, filtered at the
/// boundary by `SafeRoomSource`. The tap hands back the entry's own
/// `sourceRef`; the section that owns the sheet resolves it against the live
/// corpus (`openBySourceRef`, corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson).
struct SafeRoomCard: View {
    let room: SafeRoom
    /// Hands back the entry's `sourceRef` — the card never holds a `Thing`.
    var onOpen: (SafeRoom.Entry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Safe")

    private var drawn: [SafeRoom.Entry] {
        Array(room.entries.prefix(SafeRoomSource.rowCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Safe"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(SafeRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            // The module warning wears attention orange — the one fact this
            // bridge can state that isn't merely informational (`SafeBridge`'s
            // own top-of-file doc: a module can move funds WITHOUT a
            // signature, the highest-stakes thing this card can say).
            if let note = SafeRoom.note(room) {
                Label {
                    Text(note).dsText(.subhead13).foregroundStyle(DS.attention)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.attention)
                        .font(.system(size: 11))
                }
                .padding(.top, DS.Space.s1)
            }

            if !drawn.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: DS.Space.s4) {
                        ForEach(Array(drawn.enumerated()), id: \.element.id) { index, entry in
                            ring(entry, index: index)
                                .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                    .padding(.horizontal, 1)   // clears the ring's own focus ring
                }
                .padding(.top, DS.Space.s3)
            }

            if let footnote = SafeRoom.footnote(room, drawn: drawn.count) {
                Text(footnote)
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

    // MARK: - Rings

    private func ring(_ entry: SafeRoom.Entry, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(entry)
        } label: {
            VStack(spacing: DS.Space.s1) {
                SafeSignatureDisc(have: entry.have, required: entry.required, size: 44)
                Text(SafeRoom.waitLabel(entry))
                    .dsText(.label12)
                    .foregroundStyle(entry.yourTurn ? DS.tint : DS.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(entry.descriptionText), \(entry.have) of \(entry.required) signatures, \(SafeRoom.waitLabel(entry))"))
    }
}
