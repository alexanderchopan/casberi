import SwiftUI

/// THE SAFE ROOM'S HEAD (2026-08-11) — the signature queue, ranked "your
/// turn" first, then fully-signed, then longest-waiting.
///
/// The anatomy is `RailgunRoomCard`'s, which is `PeerRoomCard`'s: a kicker in
/// the card's own hue, a heavy headline stating the finding as a sentence,
/// ranked rows, no decoration that isn't a reading. What differs is the mark:
/// every sibling room draws a `ShareBar` because its subject is a PROPORTION
/// (which token, which rail); a Safe's subject is a COUNT toward a
/// threshold, so each row wears its own `SafeSignatureDisc` instead —
/// `SafeQueueCard`'s own ring, reused rather than redrawn.
///
/// ## Rows, not a rail (2026-08-24, prd §464)
///
/// The rings were a horizontal `ScrollView` of 60pt cells, and `rowCap` is 3 —
/// so it could never scroll, spent about 150pt of a 330pt card on emptiness,
/// and clipped in three separate places for want of the width it was throwing
/// away. `row(_:)` carries the whole reasoning; the short version is that the
/// card now says WHAT each transaction is and WHAT STATE it is in, both of
/// which the corpus already held and neither of which fitted in 60pt.
///
/// ## The tap always has a destination, or there is no tap (2026-08-17)
///
/// `SafeRoomSource.compose` returns a card on MODULE RISK ALONE — nothing
/// pending, one Safe whose funds can move without a signature. Both tap paths
/// here used to resolve through `room.lead`, so that card carried a
/// full-surface `onTapGesture`, announced "Opens this Safe" to VoiceOver, and
/// did nothing at all: a dead control on the highest-stakes card this bridge
/// draws. `destination` is now the single answer to "what does this open" —
/// the lead entry, else the config alert naming the module — and when it is
/// nil the gesture and the accessibility action are BOTH withheld rather than
/// left announcing a door that isn't there.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `SafeRoom`, filtered at the
/// boundary by `SafeRoomSource`. The tap hands back a `sourceRef`; the
/// section that owns the sheet resolves it against the live corpus
/// (`openBySourceRef`, corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson).
struct SafeRoomCard: View {
    let room: SafeRoom
    /// What the card opens when nothing is pending — see the type doc. Nil is
    /// a legitimate state and means the card simply doesn't open anything.
    var fallbackRef: String?
    /// Hands back a `sourceRef` — the card never holds a `Thing`.
    var onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Reading it invalidates the card when the text setting changes, and it is
    // what moves the fraction out of the ring and into `metadata`.
    @Environment(\.sizeCategory) private var sizeCategory

    private static let mark = DS.legibleCardFill(for: "Safe")

    private var drawn: [SafeRoom.Entry] {
        Array(room.entries.prefix(SafeRoomSource.rowCap))
    }

    /// One answer for the whole-card tap, the headline's accessibility action
    /// and the decision to offer either at all.
    private var destination: String? { room.lead?.ref ?? fallbackRef }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            headline

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
                        .dsGlyph(11, weight: .regular)
                }
                .padding(.top, DS.Space.s1)
            }

            // The state line — a nonce collision, or the fully-signed count
            // the headline couldn't carry. Deliberately NOT orange: §238 ruled
            // a rival pair is stated plainly, because it is how Safes work and
            // not a sign anything is wrong.
            if let state = SafeRoom.stateNote(room) {
                Text(state)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            if !drawn.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(Array(drawn.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
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
        .modifier(CardTap(destination: destination, onOpen: onOpen))
    }

    @ViewBuilder
    private var headline: some View {
        // THE LEDE (prd §585) — see `JournalRoomCard` for the rule. A count
        // of transactions waiting on you is a FIGURE; "Nothing pending across
        // your 3 Safes" is a statement and keeps `heading22`.
        let text = Group {
            if let lede = SafeRoom.lede(room) {
                RoomLedeView(lede: lede, spoken: SafeRoom.headline(room))
            } else {
                Text(SafeRoom.headline(room))
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The whole card is a tap target for touch and pointer and carries
        // nothing for VoiceOver; this states the same verb on the line that
        // names its destination — and says nothing when there is no
        // destination to name.
        if let destination {
            text.dsCardLead(Text("Opens this Safe")) {
                DSHaptic.selection()
                onOpen(destination)
            }
        } else {
            text
        }
    }

    /// Attaches the surface gesture only when there is somewhere to go, so a
    /// module-only card with no alert row behind it doesn't read as tappable.
    private struct CardTap: ViewModifier {
        let destination: String?
        let onOpen: (String) -> Void

        func body(content: Content) -> some View {
            if let destination {
                content.onTapGesture {
                    DSHaptic.selection()
                    onOpen(destination)
                }
            } else {
                content
            }
        }
    }

    // MARK: - Rows

    /// ONE PENDING TRANSACTION, FULL WIDTH (2026-08-24, prd §464).
    ///
    /// This was a 60pt cell in a horizontal `ScrollView`, and every one of the
    /// card's three clipping failures came out of that box. `rowCap` is 3, so
    /// the rail could never scroll: it spent ~150pt of a ~330pt card on empty
    /// space to the right of the last ring while squeezing each caption into
    /// 60pt with `lineLimit(1)` and no ellipsis. Giving that width back fixes
    /// the clipping without shrinking one rung of type, and buys the two
    /// things the cell had no room for:
    ///
    ///   - **The subject.** `descriptionText` is cached on every entry by
    ///     `SafeBridge` and cost nothing to draw, and it was drawn ONLY inside
    ///     `voiceLabel` — so a VoiceOver user heard what the transaction was
    ///     and a sighted one read "2/3" and "3 days", the two facts that mean
    ///     least when you don't know what it is.
    ///   - **The state, in words.** See `SafeRoom.stateLabel`.
    ///
    /// The disc is unchanged in kind and only smaller: it is `SafeQueueCard`'s
    /// own ring, and it stays a RING because a Safe's subject is a count
    /// toward a threshold where every sibling room's is a proportion — the
    /// distinction this file's own header draws against their `ShareBar`s. At
    /// 34 it leads a row rather than standing as a tile.
    private func row(_ entry: SafeRoom.Entry) -> some View {
        let contested = room.isContested(entry)
        return Button {
            DSHaptic.selection()
            onOpen(entry.ref)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                SafeSignatureDisc(have: entry.have, required: entry.required,
                                  size: 34)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    // Two lines and then it wraps — never a fixed width, which
                    // is what the caption box was and what clipped.
                    Text(verbatim: SafeRoom.subject(entry))
                        .dsText(.callout15)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    metadata(entry, contested: contested)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(voiceLabel(entry, contested: contested)))
    }

    /// State · wait · position, as ONE concatenated `Text` so the whole clause
    /// wraps as a paragraph rather than as three views that can break apart.
    ///
    /// `scaledFont` rather than `dsText`, because a concatenated `Text` needs
    /// `Text`'s own `.font(_:)` overload to stay `Text`-typed — the exact case
    /// that property exists for, so this is still the ramp and still Dynamic
    /// Type. The state word is semibold in its own tint and everything after it
    /// is secondary: the tint now REINFORCES a word rather than carrying the
    /// fact alone.
    ///
    /// Above `.accessibilityMedium` the fraction joins this line, because the
    /// disc has stopped drawing it (`SafeSignatureDisc.drawsCount`) — the two
    /// halves of one rule, and the reason the count can never be lost.
    private func metadata(_ entry: SafeRoom.Entry, contested: Bool) -> Text {
        var line = Text(verbatim: SafeRoom.stateLabel(entry))
            .font(DSTextStyle.subhead13.scaledFont)
            .fontWeight(.semibold)
            .foregroundStyle(stateTint(entry))
        if sizeCategory.isAccessibilityCategory, entry.required > 0 {
            line = line + trailing(String(localized: "\(entry.have) of \(entry.required)"))
        }
        line = line + trailing(SafeRoom.waitLabel(entry))
        // The rival pair, said. It was a 9pt glyph offset off a ring's corner
        // — the smallest mark on the card carrying the highest-stakes fact on
        // it, and unlabelled. `ordered` already draws a contested pair
        // adjacent, so printing the shared position on both is what makes the
        // pairing readable rather than merely present.
        if contested, let position = SafeRoom.positionLabel(entry) {
            line = line + trailing(position)
        }
        return line
    }

    private func trailing(_ text: String) -> Text {
        Text(verbatim: " · " + text)
            .font(DSTextStyle.subhead13.scaledFont)
            .foregroundStyle(DS.textSecondary)
    }

    /// The state's colour, matching the ring's own fill so the mark and the
    /// word can never disagree.
    private func stateTint(_ entry: SafeRoom.Entry) -> Color {
        entry.awaitsYou ? DS.tint : entry.isReady ? DS.confirm : DS.textSecondary
    }

    /// Spelled out rather than read off the row: the disc carries the met/unmet
    /// distinction in colour, which VoiceOver cannot reach, and the subject and
    /// the state now come from the same two functions the row draws — so the
    /// spoken card and the drawn one can no longer drift.
    private func voiceLabel(_ entry: SafeRoom.Entry, contested: Bool) -> String {
        var parts = [SafeRoom.subject(entry)]
        parts.append(entry.isReady
                     ? String(localized: "fully signed, ready to execute")
                     : String(localized: "\(entry.have) of \(entry.required) signatures"))
        if entry.awaitsYou { parts.append(String(localized: "your signature is needed")) }
        if contested { parts.append(String(localized: "shares a queue position with another")) }
        parts.append(SafeRoom.waitLabel(entry))
        return parts.joined(separator: ", ")
    }
}
