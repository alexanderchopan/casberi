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
///    with neither `dsWidgetSurface()` nor an outer `.padding(.horizontal)` —
///    Gnosis Pay, Stripe, Safe and Privacy Pools all end with both — so its
///    content sat naked on the page, flush to the screen edge. That is §474's
///    reported vibenet bug, unfixed here, and it was most of the complaint.
/// 2. **The layout was absolutely positioned and could overflow.** Width came
///    out of `AltanaRoom.placement` as `88 + 62·N`, against a card content
///    width of ~321pt on a 393pt phone: a fifth exclusive key drew past the
///    edge with no scroll to catch it, and at a 62pt step under 62pt labels,
///    adjacent captions abutted with zero gap. Three accounts spent ~314pt of
///    screen before the rail.
/// 3. **A 44pt circle carried six variables** — fill, border colour, border
///    dash, opacity, glyph, plus its ties' own colour and dash. That is the
///    decode load §478 removed one room over: *"the keys stop being a census
///    you decode and become a list you scan."*
/// 4. **The rail had `VibenetKeyShelf`'s defect, unfixed.** See
///    `AltanaRoom.shelfWindow` — the now-marker was a constant and the axis
///    was elastic.
/// 5. **Two clocks.** Every token said "3h left" and the rail dot beneath it
///    said "9h · Passkey" about the same deadline.
///
/// One row per credential now, one clock per row, one bar shape shared with
/// every other card in the app (`ShareBar`). The rare fact the ties existed
/// for — one credential signing for two of your accounts — is drawn as the
/// FACES on that credential's own row, which is where somebody asking about
/// that key would look for it.
///
/// ## The faces stand down when the room is scoped
///
/// Altana is in the Wallet category, so `WalletScopeRail` draws your wallet
/// faces above this room whenever more than one is watched, and since §488 the
/// head obeys that pick. In a scoped room every row belongs to the same
/// account, so a face on each one is a column of the same picture repeated —
/// they draw only where they distinguish something, which is an unscoped room,
/// or a credential that signs for more than one account (where it is the whole
/// point, scoped or not).
///
/// ## Liveness
///
/// Stores no `Thing` — value types out of `AltanaRoom`, composed from a
/// UserDefaults snapshot. Corollary 5 has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
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
    private static let seat: CGFloat = 28
    /// The countdown column. Fixed, so the numbers line up down the card
    /// rather than floating at the end of titles of different lengths — and
    /// wide enough for the longest word it draws ("no expiry").
    private static let clockWidth: CGFloat = 64

    /// Whether a row names the account it signs for. See the type doc.
    private var namesAccounts: Bool { card.accounts.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            Text(card.headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dsCardLead(Text("Opens this account on Altana")) {
                    DSHaptic.selection()
                    onOpen()
                }

            if let subline = card.subline {
                Text(subline)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }

            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(card.drawn.enumerated()), id: \.element.id) { index, row in
                    keyRow(row, index: index)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .padding(.top, DS.Space.s4)

            // What the cap left off — counted, never silently dropped.
            if let more = card.moreLine {
                Text(more)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s3)
            }

            // ONE line (§488): both sentences this replaced were summaries of
            // rows now drawn above, and what survives is the part the rows
            // cannot carry — see `AltanaRoom.Card.note`.
            if let note = card.note {
                Text(note)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // THE CARD RECIPE, which this head never had (prd §488). Every sibling
        // room head applies exactly this pair after its own padding, and
        // `insightSection` presents them all edge-to-edge on purpose ("the card
        // owns its own padding"), so without it this one's content ran to both
        // screen edges while every neighbouring room sat 18pt in from them.
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
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
            HStack(alignment: .top, spacing: DS.Space.s3) {
                seatMark(row)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(spacing: DS.Space.s2) {
                        Text(row.title)
                            .dsText(.subhead13).fontWeight(.medium)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        if showsFaces(row) { faces(row) }
                        Spacer(minLength: DS.Space.s2)
                        Text(row.countdown(now: now))
                            .dsText(.label12)
                            .fontWeight(urgent ? .semibold : .regular)
                            .foregroundStyle(urgent ? Self.mark : DS.textTertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: Self.clockWidth, alignment: .trailing)
                    }
                    if let fraction = row.shelfFraction(now: now) {
                        // Blue is spent on urgency and only on urgency (§471),
                        // so the one key you might have to act on today is the
                        // one coloured bar on the card.
                        ShareBar(fraction: fraction,
                                 index: index,
                                 fill: urgent ? Self.mark : DS.fillStrong,
                                 reduceMotion: reduceMotion)
                    }
                    if let detail = row.detail {
                        Text(detail)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
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
                .dsGlyph(14)
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
                    .overlay(Circle().strokeBorder(DS.surfaceRaised, lineWidth: 1.5))
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
