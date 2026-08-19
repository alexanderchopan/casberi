import SwiftUI

/// THE ALTANA ROOM'S HEAD (prd §403, the keyring in §407a, the CONSTELLATION
/// in §408a) — every credential on every watched account, and what each can
/// sign for, as one picture of right now.
///
/// ## Why the constellation replaced the bands
///
/// §407a drew one token per REGISTRATION, grouped in a band per account, with
/// a shared credential appearing twice and wearing a 16pt link badge to say
/// so. Three things were wrong with that and the user named all three:
///
/// 1. **The circles were not the same size.** Each token's arc swept a
///    different fraction and a root wore none at all, so a row of equal
///    circles read as unequal ones. The arcs are GONE — a credential's
///    remaining time is on the rail below and on its sheet, and the token
///    carries identity only. Weight (solid vs outlined) is what marks the
///    root now; size never varies.
/// 2. **The tie was a badge.** The most important and rarest fact on the card
///    — one credential signing for two accounts — was a grey glyph in a
///    corner plus a sentence in the footer. It is a DRAWN LINE now: one
///    token, two ties. The picture says it; the sentence is the accessible
///    reading of the picture rather than the only place it exists.
/// 3. **Duration drawn as length says nothing.** A long bar for a root beside
///    a short one for a session invites a comparison that carries no
///    information — the user's own words. The rail keeps POSITION and drops
///    length entirely: a dot where each deadline falls, relative to now and
///    to the others.
///
/// ## The census counts credentials, not registrations
///
/// Because the picture draws a shared key once, the sentence counts it once.
/// "5 keys" for four credentials was the card disagreeing with its own
/// drawing.
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
    /// EVERY token is this size. The one rule the last cut broke.
    private static let token: CGFloat = 44
    private static let faceSize: CGFloat = 30
    /// Above this many accounts the constellation stops being readable and the
    /// card falls back to a plain list — stated rather than discovered.
    static let maxDrawnAccounts = 3

    private var drawable: Bool {
        card.accounts.count <= Self.maxDrawnAccounts && !card.credentials.isEmpty
    }

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

            if drawable {
                constellation
                    .padding(.top, DS.Space.s4)
            } else {
                // Too many accounts to draw legibly — the tokens still list,
                // which is worse than the picture and better than a tangle.
                flatTokens
                    .padding(.top, DS.Space.s4)
            }

            if !card.rail.isEmpty {
                railView
                    .padding(.top, DS.Space.s4)
            }

            // ONE line (§408a): the tie replaced the shared sentence as the
            // card's primary telling, and the scope ceiling lives on the key's
            // own sheet, which states it beside the dates it governs.
            if let stale = card.staleNote {
                Text(stale)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s4)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    /// The picture: accounts down the left, every credential exactly once, and
    /// a tie from each account to everything that can sign for it.
    ///
    /// Positions come from `AltanaRoom.placement` rather than from stacked
    /// rows — the first cut stacked per account, which drew a shared key twice
    /// and made the picture contradict its own census.
    private var constellation: some View {
        let plan = AltanaRoom.placement(card)
        return ZStack(alignment: .topLeading) {
            // Ties first, so a token always sits on top of its own lines.
            ForEach(plan.ties) { tie in
                if let a = plan.accounts.first(where: { $0.id == tie.account }),
                   let c = plan.credentials.first(where: { $0.id == tie.credential }) {
                    Path { path in
                        path.move(to: CGPoint(x: a.x, y: a.y))
                        if tie.shared {
                            // ROUTED, not diagonal: out from the face, along
                            // the channel between rows, then in to the token.
                            // A straight line here crosses the labels of every
                            // row it passes and takes them with it.
                            let lane = CGPoint(x: a.x + 20, y: a.y)
                            path.addLine(to: lane)
                            path.addLine(to: CGPoint(x: lane.x, y: c.y))
                            path.addLine(to: CGPoint(x: c.x, y: c.y))
                        } else {
                            path.addLine(to: CGPoint(x: c.x, y: c.y))
                        }
                    }
                    .stroke(tie.shared ? Self.mark.opacity(0.9)
                                       : DS.textTertiary.opacity(0.28),
                            style: StrokeStyle(lineWidth: tie.shared ? 2.5 : 2, lineCap: .round))
                }
            }

            ForEach(plan.accounts) { node in
                VStack(spacing: 2) {
                    WalletFace(address: node.id, size: Self.faceSize, circular: true)
                    Text(WalletStore.shortAddress(node.id))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize()
                }
                .position(x: node.x, y: node.y + 10)
            }

            ForEach(Array(plan.credentials.enumerated()), id: \.element.id) { index, node in
                if let row = card.credentials.first(where: { $0.id == node.id }) {
                    tokenColumn(row)
                        .position(x: node.x, y: node.y + 18)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
        }
        .frame(width: plan.width, height: plan.height + 22, alignment: .topLeading)
    }

    private var flatTokens: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s3) {
                ForEach(card.credentials) { row in tokenColumn(row) }
            }
        }
    }

    /// Credentials this account can be signed for by, in the drawn order the
    /// account's own rows established.
    private func credentials(for address: String) -> [AltanaRoom.KeyRow] {
        card.credentials.filter { $0.accountAddresses.contains(address) }
    }

    private func tie(shared: Bool) -> some View {
        Rectangle()
            .fill(shared ? Self.mark.opacity(0.85) : DS.textTertiary.opacity(0.28))
            .frame(width: 14, height: 2)
    }

    @ViewBuilder
    private func tokenColumn(_ row: AltanaRoom.KeyRow) -> some View {
        Button {
            DSHaptic.selection()
            onPickKey(row)
        } label: {
            VStack(spacing: DS.Space.s2) {
                ZStack {
                    Circle()
                        .fill(row.isRoot ? Self.mark : DS.surfaceRaised)
                    Circle()
                        .strokeBorder(row.isShared ? Self.mark
                                                   : DS.textTertiary.opacity(row.isRoot ? 0 : 0.28),
                                      lineWidth: 2)
                    Image(systemName: glyph(row))
                        .dsGlyph(18)
                        .foregroundStyle(row.isRoot ? .white : DS.textPrimary)
                }
                // EVERY token, the same size — no exceptions (§408a).
                .frame(width: Self.token, height: Self.token)

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
            .frame(minWidth: 62)
            .opacity(row.expired ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibility(row)))
    }

    /// The rail: WHEN, never how long (§408a).
    private var railView: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "What expires next"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(DS.textTertiary.opacity(0.18))
                        .frame(height: 5)
                        .offset(y: 5)
                    // The now-marker: the rail always CONTAINS now, so a dot
                    // can never draw to the left of it.
                    Capsule()
                        .fill(DS.textSecondary)
                        .frame(width: 2.5, height: 13)
                        .offset(x: 0, y: 1)
                    ForEach(card.rail) { dot in
                        Circle()
                            .fill(Self.mark)
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, min(geo.size.width - 10, geo.size.width * dot.position - 5)),
                                    y: 2.5)
                    }
                }
            }
            .frame(height: 18)
            // Labels below, first and last only: a label per dot is a thicket,
            // and these two are the ones worth reading — the next thing to
            // happen and the edge of the window.
            HStack(alignment: .top) {
                if let first = card.rail.first {
                    Text(first.label)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: DS.Space.s2)
                if let last = card.rail.last, card.rail.count > 1 {
                    Text(last.label)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    private func glyph(_ row: AltanaRoom.KeyRow) -> String {
        row.kindLabel == String(localized: "Passkey") ? "touchid" : "key.horizontal"
    }

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
        if row.isShared {
            parts.append(String(localized: "signs for \(row.accountAddresses.count) accounts"))
        }
        if let line = tokenLine(row) { parts.append(line) }
        return parts.joined(separator: ", ")
    }

    /// The picture, said once for anyone not looking at it.
    private var accessibilitySummary: String {
        var parts = [card.headline]
        if let shared = card.sharedNote { parts.append(shared) }
        if let stale = card.staleNote { parts.append(stale) }
        return parts.joined(separator: ". ")
    }
}
