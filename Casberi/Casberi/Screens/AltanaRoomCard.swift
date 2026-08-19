import SwiftUI

/// THE ALTANA ROOM'S HEAD (prd §403, rebuilt as the KEYRING in §407a) — every
/// credential on every watched account, as one picture of right now.
///
/// ## Why tokens replaced the rows
///
/// §405 gave every key a row and §406 tightened the words, and the result
/// still had two structural limits: the card ranked accounts and drew ONE,
/// relegating the rest to a footnote — and the rows said in four lines what a
/// glance could say at once. The keyring draws the whole registry: one token
/// per credential, grouped behind each account's own face. The words the rows
/// carried live on the key's sheet, one tap away, where they always were.
///
/// ## What each mark stores — nothing is decoration
///
/// The GLYPH is the kind (`touchid` for a passkey, `key.horizontal` for a
/// wallet key and for a curve we could not read — "a key" is all we can then
/// honestly claim). A SOLID mark-blue face is the root: its authority is
/// carried by weight, never by size, because a bigger token would imply a
/// magnitude nobody measured. The ARC is the session's remaining grant — the
/// same `progress(now:)` the row runways drew, rendered round, so the two
/// encodings can never disagree because there is only one. An EXPIRED key
/// fades and keeps no arc: done things recede (§406). A LINK badge marks a
/// credential registered under more than one account — the same key id is the
/// same credential by construction, and that single-point-of-failure fact is
/// drawn instead of said.
///
/// ## The §403 rulings all survive
///
/// No green/red — the arc is the room's own hue and an expired token is
/// merely dim. No shared time axis — each arc is its own grant's fraction
/// (the ASC reasoning: two grants on one scale imply a comparison nobody
/// made). The arc draws only when the registration was WITNESSED (§403's
/// honesty rail): an unwitnessed grant shows a plain ring, never a guessed
/// fraction.
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
    /// Opens one credential's sheet. Carries the ACCOUNT as well as the key
    /// (§407a): a shared credential appears under two accounts, and tapping it
    /// under account A must open A's row, not whichever landed newest.
    var onPickKey: (_ address: String, _ row: AltanaRoom.KeyRow) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Altana") ?? Color.fixed("#3565e3")
    private static let tokenSize: CGFloat = 52
    private static let arcWidth: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Altana"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(card.headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
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

            // The keyring. One horizontal band per account; the face leads
            // only when there is more than one account to tell apart —
            // a lone account's face would caption a picture of itself.
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                ForEach(Array(card.accounts.enumerated()), id: \.element.id) { index, group in
                    accountBand(group, showFace: card.accounts.count > 1)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .padding(.top, DS.Space.s4)

            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if let shared = card.sharedNote {
                    Text(shared)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
                if let stale = card.staleNote {
                    Text(stale)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(String(localized: "Only a key’s deadline is published, never its scope."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.top, DS.Space.s4)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One account's band

    @ViewBuilder
    private func accountBand(_ group: AltanaRoom.AccountGroup, showFace: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            if showFace {
                VStack(spacing: DS.Space.s1) {
                    WalletFace(address: group.address, size: DS.Face.rowCircle, circular: true)
                    Text(WalletStore.shortAddress(group.address))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                .padding(.top, DS.Space.s1)
            }
            // Tokens scroll when an account outgrows the width — the band
            // clips inside its own scroll rather than wrapping, so two
            // accounts stay two clean shelves (the mini-cell reasoning).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(group.rows) { row in
                        keyToken(row, address: group.address,
                                 shared: card.sharedKeyIDs.contains(row.id.lowercased()))
                    }
                }
            }
        }
    }

    // MARK: - One credential

    @ViewBuilder
    private func keyToken(_ row: AltanaRoom.KeyRow, address: String, shared: Bool) -> some View {
        Button {
            DSHaptic.selection()
            onPickKey(address, row)
        } label: {
            VStack(spacing: DS.Space.s2) {
                ZStack {
                    // The track ring, and the arc when the grant is real.
                    Circle()
                        .stroke(DS.textTertiary.opacity(0.18), lineWidth: Self.arcWidth)
                    if !row.expired, let progress = row.progress {
                        // REMAINING, not elapsed — the arc drains as the grant
                        // runs out, so a thin arc is a nearly-dead key before
                        // the label is read.
                        Circle()
                            .trim(from: 0, to: max(0.02, 1 - progress))
                            .stroke(Self.mark, style: StrokeStyle(lineWidth: Self.arcWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    // The face: solid for the root's permanent authority,
                    // quiet for a session.
                    Circle()
                        .fill(row.isRoot ? Self.mark : DS.surfaceRaised)
                        .padding(Self.arcWidth + 3)
                    Image(systemName: glyph(row))
                        .dsGlyph(17)
                        .foregroundStyle(row.isRoot ? .white : DS.textPrimary)
                }
                .frame(width: Self.tokenSize, height: Self.tokenSize)
                .overlay(alignment: .topTrailing) {
                    if shared {
                        // The same credential under another account too.
                        Image(systemName: "link")
                            .dsGlyph(9)
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(DS.textTertiary, in: Circle())
                    }
                }

                VStack(spacing: 1) {
                    Text(row.title)
                        .dsText(.label12).fontWeight(.medium)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let line = tokenLine(row) {
                        Text(line)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .frame(minWidth: 58)
            .opacity(row.expired ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibility(row)))
    }

    private func glyph(_ row: AltanaRoom.KeyRow) -> String {
        // `touchid` is what a passkey IS to the person holding the phone;
        // everything else — a wallet key, and a curve we could not read — is
        // honestly "a key", in the seat's own glyph.
        row.kindLabel == String(localized: "Passkey") ? "touchid" : "key.horizontal"
    }

    /// The one line under a token. Deadline first (it is the reading), then
    /// the states with no clock.
    private func tokenLine(_ row: AltanaRoom.KeyRow) -> String? {
        if row.expired { return String(localized: "expired") }
        if let hours = row.hoursLeft {
            return hours == 0 ? String(localized: "under 1h")
                              : String(localized: "\(hours)h left")
        }
        if let days = row.daysLeft { return String(localized: "\(days)d left") }
        if row.isRoot { return String(localized: "no expiry") }
        return nil
    }

    private func accessibility(_ row: AltanaRoom.KeyRow) -> String {
        var parts = [row.title]
        if row.isRoot { parts.append(String(localized: "root key")) }
        if let line = tokenLine(row) { parts.append(line) }
        return parts.joined(separator: ", ")
    }
}
