import SwiftUI

/// THE SAFE ROOM'S HEAD (2026-08-11) — the signature queue, ranked "your
/// turn" first, then fully-signed, then longest-waiting.
///
/// A heavy headline stating the finding as a sentence, the queue as rows, no
/// decoration that isn't a reading. What differs from every sibling is the
/// mark: a Safe's subject is a COUNT toward a threshold, so each row wears its
/// own `SafeSignatureDisc` rather than a `ShareBar` — `SafeQueueCard`'s own
/// ring, reused rather than redrawn.
///
/// ## Rows, not a rail (2026-08-24, prd §464)
///
/// The rings were a horizontal `ScrollView` of 60pt cells, and `rowCap` is 3 —
/// so it could never scroll, spent about 150pt of a 330pt card on emptiness,
/// and clipped in three separate places. `row(_:)` carries the reasoning.
///
/// ## The tap always has a destination, or there is no tap (2026-08-17)
///
/// `SafeRoomSource.compose` returns a card on MODULE RISK ALONE — nothing
/// pending, one Safe whose funds can move without a signature. `destination`
/// is the single answer to "what does this open" — the lead entry, else the
/// config alert naming the module — and when it is nil the head has no
/// `Door`, so the gesture and the accessibility action are BOTH withheld
/// rather than left announcing a door that isn't there.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `SafeRoom`, filtered at the
/// boundary by `SafeRoomSource`. The tap hands back a `sourceRef`; the
/// section that owns the sheet resolves it against the live corpus
/// (`openBySourceRef`, corollary 5).
///
/// Composed through `DSRoomChassis.Head` (prd §745): the module warning is the
/// template's `alert` line — the one register a head may raise its voice in.
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

    private var drawn: [SafeRoom.Entry] {
        Array(room.entries.prefix(SafeRoomSource.rowCap))
    }

    /// One answer for the whole-card tap, the headline's accessibility action
    /// and the decision to offer either at all.
    private var destination: String? { room.lead?.ref ?? fallbackRef }

    var body: some View {
        DSRoomChassis.Head(
            // THE LEDE (prd §585). A count of transactions waiting on you is a
            // FIGURE; "Nothing pending across your 3 Safes" is a statement.
            lead: .figure(SafeRoom.lede(room), otherwise: SafeRoom.headline(room)),
            door: door,
            notes: [
                // The module warning wears attention ink — the one fact this
                // bridge can state that isn't merely informational (a module
                // can move funds WITHOUT a signature).
                .alert(SafeRoom.note(room), glyph: "exclamationmark.triangle.fill"),
                // The guard line, in a plainer register (2026-09-07). A guard is
                // a rule the owners CHOSE, not a way out for funds.
                .note(SafeRoom.guardNote(room), glyph: "shield.lefthalf.filled"),
                // The state line — a nonce collision, or the fully-signed count
                // the headline couldn't carry. Deliberately NOT attention ink:
                // §238 ruled a rival pair is stated plainly.
                .note(SafeRoom.stateNote(room)),
            ],
            footnotes: [.quiet(SafeRoom.footnote(room, drawn: drawn.count))]) {
            if !drawn.isEmpty {
                DSRoomChassis.Block {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        DSRoomChassis.Rows(items: drawn) { index, entry in
                            row(entry)
                                .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }

    /// The head's door, or none — see the type doc.
    private var door: DSRoomChassis.Door? {
        if let destination {
            return DSRoomChassis.Door(hint: Text("Opens this Safe")) { onOpen(destination) }
        }
        return nil
    }

    // MARK: - Rows

    /// ONE PENDING TRANSACTION, FULL WIDTH (2026-08-24, prd §464).
    ///
    /// Giving the width back fixes the clipping without shrinking one rung of
    /// type, and buys the two things the old 60pt cell had no room for:
    ///
    ///   - **The subject.** `descriptionText` is cached on every entry by
    ///     `SafeBridge`, and it was drawn ONLY inside `voiceLabel` — so a
    ///     VoiceOver user heard what the transaction was and a sighted one read
    ///     "2/3" and "3 days".
    ///   - **The state, in words.** See `SafeRoom.stateLabel`.
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
    /// `Text`'s own `.font(_:)` overload to stay `Text`-typed. Above
    /// `.accessibilityMedium` the fraction joins this line, because the disc
    /// has stopped drawing it (`SafeSignatureDisc.drawsCount`).
    private func metadata(_ entry: SafeRoom.Entry, contested: Bool) -> Text {
        var line = Text(verbatim: SafeRoom.stateLabel(entry))
            .font(DSTextStyle.subhead13.scaledFont)
            .fontWeight(.semibold)
            .foregroundStyle(stateTint(entry))
        if sizeCategory.isAccessibilityCategory, entry.required > 0 {
            line = line + trailing(String(localized: "\(entry.have) of \(entry.required)"))
        }
        line = line + trailing(SafeRoom.waitLabel(entry))
        // The rival pair, said. `ordered` already draws a contested pair
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
        // `isExecutable`, NOT `isReady` (2026-09-07, prd §652). A threshold met
        // behind two earlier transactions is fully signed and cannot be sent.
        // Green is reserved for the state somebody can act on.
        entry.awaitsYou ? DS.tint : entry.isExecutable ? DS.confirm : DS.textSecondary
    }

    /// Spelled out rather than read off the row: the disc carries the met/unmet
    /// distinction in colour, which VoiceOver cannot reach, and the subject and
    /// the state come from the same two functions the row draws.
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
