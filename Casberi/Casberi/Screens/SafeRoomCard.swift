import SwiftUI

/// THE SAFE ROOM'S HEAD (2026-08-11) — the signature queue as rings, ranked
/// "your turn" first, then fully-signed, then longest-waiting.
///
/// The anatomy is `RailgunRoomCard`'s, which is `PeerRoomCard`'s: a kicker in
/// the card's own hue, a heavy headline stating the finding as a sentence,
/// ranked rows, no decoration that isn't a reading. What differs is the mark:
/// every sibling room draws a `ShareBar` because its subject is a PROPORTION
/// (which token, which rail); a Safe's subject is a COUNT toward a
/// threshold, so each row wears its own `SafeSignatureDisc` instead —
/// `SafeQueueCard`'s own ring, reused rather than redrawn.
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

    private static let mark = DS.legibleCardFill(for: "Safe")

    private var drawn: [SafeRoom.Entry] {
        Array(room.entries.prefix(SafeRoomSource.rowCap))
    }

    /// One answer for the whole-card tap, the headline's accessibility action
    /// and the decision to offer either at all.
    private var destination: String? { room.lead?.ref ?? fallbackRef }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Safe"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

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
        .modifier(CardTap(destination: destination, onOpen: onOpen))
    }

    @ViewBuilder
    private var headline: some View {
        let text = Text(SafeRoom.headline(room))
            .dsText(.heading22)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DS.Space.s2)
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

    // MARK: - Rings

    private func ring(_ entry: SafeRoom.Entry, index: Int) -> some View {
        let contested = room.isContested(entry)
        return Button {
            DSHaptic.selection()
            onOpen(entry.ref)
        } label: {
            VStack(spacing: DS.Space.s1) {
                SafeSignatureDisc(have: entry.have, required: entry.required, size: 44)
                    // A rival pair is marked on the RING rather than only in
                    // the sentence above: the sentence says two of these
                    // collide, and without this you cannot tell which two.
                    .overlay(alignment: .topTrailing) {
                        if contested {
                            Image(systemName: "arrow.triangle.branch")
                                .dsGlyph(9, weight: .semibold)
                                .foregroundStyle(DS.textSecondary)
                                .padding(2)
                                .background(Circle().fill(DS.surfaceSheet))
                                .offset(x: 3, y: -3)
                        }
                    }
                Text(SafeRoom.waitLabel(entry))
                    .dsText(.label12)
                    .foregroundStyle(entry.awaitsYou ? DS.tint
                                     : entry.isReady ? DS.confirm : DS.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(voiceLabel(entry, contested: contested)))
    }

    /// Spelled out rather than read off the ring: "2 of 3" alone doesn't say
    /// whether that is enough, and the disc carries the met/unmet distinction
    /// in colour, which VoiceOver cannot reach.
    private func voiceLabel(_ entry: SafeRoom.Entry, contested: Bool) -> String {
        var parts = [entry.descriptionText.isEmpty
                     ? String(localized: "a pending transaction") : entry.descriptionText]
        parts.append(entry.isReady
                     ? String(localized: "fully signed, ready to execute")
                     : String(localized: "\(entry.have) of \(entry.required) signatures"))
        if entry.awaitsYou { parts.append(String(localized: "your signature is needed")) }
        if contested { parts.append(String(localized: "shares a queue position with another")) }
        parts.append(SafeRoom.waitLabel(entry))
        return parts.joined(separator: ", ")
    }
}
