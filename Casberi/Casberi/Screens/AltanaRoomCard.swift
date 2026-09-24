import SwiftUI

/// THE ALTANA ROOM'S HEAD (prd §403, the keyring in §407a, the constellation
/// in §408a, THE LIST in §488) — every credential on every watched account,
/// what each can sign for, and how long each has left.
///
/// ## Why the list replaced the constellation
///
/// §408a drew accounts down the left, one token per credential, and a routed
/// line for every account a key could sign for, over a dot rail of the
/// deadlines. Reported as messy, and the reasons measured rather than argued:
///
/// 1. **It had no card.** This was the only room head in the Wallet group
///    with no widget surface and no outer margin, so its content sat naked on
///    the page, flush to the screen edge. Since prd §745 that chrome belongs to
///    `DSRoomChassis.Head`, so no head can forget it.
/// 2. **The layout was absolutely positioned and could overflow.** Width came
///    out of a placement function as `88 + 62·N`, against a card content width
///    of ~321pt on a 393pt phone.
/// 3. **A 44pt circle carried six variables** — the decode load §478 removed
///    one room over: *"the keys stop being a census you decode and become a
///    list you scan."*
/// 4. **The rail had `VibenetKeyShelf`'s defect** — see
///    `AltanaRoom.shelfWindow`.
/// 5. **Two clocks.** Every token said "3h left" and the rail dot beneath it
///    said "9h · Passkey" about the same deadline.
///
/// One row per credential now, one clock per row, one bar shape shared with
/// every other card in the app (`ShareBar`). The rare fact the ties existed
/// for — one credential signing for two of your accounts — is drawn as the
/// FACES on that credential's own row.
///
/// ## The faces stand down when the room is scoped
///
/// Altana is in the Wallet category, so `WalletScopeRail` draws your wallet
/// faces above this room whenever more than one is watched, and since §488 the
/// head obeys that pick. In a scoped room every row belongs to the same
/// account, so the faces draw only where they distinguish something.
///
/// ## Liveness
///
/// Stores no `Thing` — value types out of `AltanaRoom`, composed from a
/// UserDefaults snapshot. Corollary 5 has nothing to guard here.
struct AltanaRoomCard: View {
    let card: AltanaRoom.Card
    /// Opens Altana's own explorer — the only place a key can actually be
    /// revoked (§112: we read and state, they act).
    var onOpen: () -> Void
    /// Opens one credential's sheet.
    var onPickKey: (AltanaRoom.KeyRow) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Altana") ?? Color.fixed("#3565e3")
    /// The credential seat. EVERY row is this size — the one rule §408a's
    /// tokens broke and the reason they are gone: weight says root, never size.
    private static let seat: CGFloat = DS.Mark.row
    /// The countdown column. Fixed, so the numbers line up down the card
    /// rather than floating at the end of titles of different lengths — and
    /// wide enough for the longest word it draws ("no expiry").
    private static let clockWidth: CGFloat = 64

    /// Whether a row names the account it signs for. See the type doc.
    private var namesAccounts: Bool { card.accounts.count > 1 }

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(card.headline),
            // The lead leaves the app; the rows below open sheets. A face-wide
            // gesture would make every gap between rows a trip to the explorer.
            door: DSRoomChassis.Door(hint: Text("Opens this account on Altana"),
                                     wholeCard: false,
                                     action: onOpen),
            notes: [.note(card.subline)],
            // What the cap left off — counted, never silently dropped — then ONE
            // line (§488) for what the rows cannot carry.
            footnotes: [.quiet(card.moreLine), .quiet(card.note)]) {
            if !card.drawn.isEmpty {
                DSRoomChassis.Block {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        DSRoomChassis.Rows(items: card.drawn) { index, row in
                            keyRow(row, index: index)
                                .chartArrival(index: index, reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    // MARK: - One credential

    /// A row, in one grammar for all four states.
    ///
    /// The bar draws only where a bar is a reading — `shelfFraction` returns
    /// nil for a root (no end), an expired key (no time left) and a ghost (not
    /// on the shelf at all), so those rows collapse to two lines and their
    /// absence of a bar says "no clock", which is exactly true.
    @ViewBuilder
    private func keyRow(_ row: AltanaRoom.KeyRow, index: Int) -> some View {
        let now = Date.now
        let urgent = row.isUrgent(now: now)
        let finished = row.expired || row.isGone
        Button {
            DSHaptic.selection()
            onPickKey(row)
        } label: {
            // The feed row's anatomy (prd §763): the seat mark on the 26pt
            // lead, the key's title as the name, the faces and the countdown
            // in the trailing slot, the detail as the line, the bar below.
            DSFeedRow(name: row.title,
                      line: row.detail.map { Text($0) },
                      lead: { seatMark(row) },
                      trailing: {
                          HStack(spacing: DS.Space.s2) {
                              if showsFaces(row) { faces(row) }
                              Text(row.countdown(now: now))
                                  .dsText(.subhead12)
                                  .fontWeight(urgent ? .medium : .regular)
                                  .foregroundStyle(urgent ? Self.mark : DS.textTertiary)
                                  .monospacedDigit()
                                  .lineLimit(1)
                                  .frame(width: Self.clockWidth, alignment: .trailing)
                          }
                      },
                      below: {
                          if let fraction = row.shelfFraction(now: now) {
                              // Blue is spent on urgency and only on urgency
                              // (§471), so the one key you might have to act
                              // on today is the one coloured bar on the card.
                              ShareBar(fraction: fraction,
                                       index: index,
                                       fill: urgent ? Self.mark : DS.fillStrong,
                                       reduceMotion: reduceMotion)
                                  .padding(.top, DS.Space.s1)
                          }
                      })
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(finished ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibility(row)))
    }

    /// Root or session, said by WEIGHT and never by size (§408a's one surviving
    /// token rule): a root is solid in the room's mark, a session is outlined,
    /// a revoked credential is outlined in a dashed stroke — which is the whole
    /// reading, since the registry has dropped it and only our own memory of it
    /// remains (§410).
    private func seatMark(_ row: AltanaRoom.KeyRow) -> some View {
        ZStack {
            Circle()
                .fill(row.isRoot && !row.isGone ? Self.mark : DS.fillFaint)
            Circle()
                .strokeBorder(DS.textTertiary.opacity(row.isRoot && !row.isGone ? 0 : 0.28),
                              style: StrokeStyle(lineWidth: 1.5,
                                                 dash: row.isGone ? [2, 3] : []))
            Image(systemName: glyph(row))
                .dsGlyph(.subhead)
                .foregroundStyle(row.isRoot && !row.isGone ? .white : DS.textSecondary)
        }
        .frame(width: Self.seat, height: Self.seat)
    }

    /// The accounts this credential can sign for.
    ///
    /// Overlapped rather than spaced, so a pair reads as one fact ("this key,
    /// those two accounts") rather than as two separate marks — `FacePile`'s
    /// own shape, spelled here because that view draws `RemoteThumb` from URLs
    /// and these are `WalletFace` identicons off an address.
    private func faces(_ row: AltanaRoom.KeyRow) -> some View {
        HStack(spacing: -DS.Face.badge * 0.34) {
            ForEach(row.accountAddresses.prefix(3), id: \.self) { address in
                WalletFace(address: address, size: DS.Face.badge, circular: true)
                    // The card under these faces is `dsWidgetSurface()`,
                    // i.e. `DS.surfaceSheet` — so that is what the ring must
                    // punch out (§542's sweep).
                    .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 1.5))
            }
        }
        .fixedSize()
    }

    /// A face earns its place only where it distinguishes something: an
    /// unscoped room (rows belong to different accounts), or a credential that
    /// signs for more than one account, which is the fact the whole
    /// constellation was built to say.
    private func showsFaces(_ row: AltanaRoom.KeyRow) -> Bool {
        namesAccounts || row.isShared
    }

    private func glyph(_ row: AltanaRoom.KeyRow) -> String {
        row.kindLabel == String(localized: "Passkey") ? "touchid" : "key.horizontal"
    }

    private func accessibility(_ row: AltanaRoom.KeyRow) -> String {
        var parts = [row.title]
        if row.isRoot { parts.append(String(localized: "root key")) }
        if row.isShared {
            parts.append(String(localized: "signs for \(row.accountAddresses.count) accounts"))
        }
        if let detail = row.detail { parts.append(detail) }
        parts.append(row.countdown(now: .now))
        return parts.joined(separator: ", ")
    }

    /// The card, said once for anyone not looking at it. Deliberately fuller
    /// than what is drawn: the shared and hygiene sentences are pictures and
    /// row states on screen, and neither reads as anything to VoiceOver.
    private var accessibilitySummary: String {
        var parts = [card.headline]
        if let shared = card.sharedNote { parts.append(shared) }
        if let revoked = card.revokedNote { parts.append(revoked) }
        if let stale = card.staleNote { parts.append(stale) }
        return parts.joined(separator: ". ")
    }
}
