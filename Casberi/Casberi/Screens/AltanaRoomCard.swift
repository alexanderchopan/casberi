import SwiftUI

/// THE ALTANA ROOM'S HEAD (2026-08-18, prd §403) — who can sign as you, and
/// for how much longer.
///
/// The anatomy is `AppStoreConnectRoomCard`'s, which took it from
/// `StripeRoomCard` and `CloudflareRunwayCard`: a kicker in the card's one hue,
/// a heavy headline stating the whole finding as a sentence, ranked rows, and
/// nothing drawn that isn't a reading. What was ruled out there is out here —
/// no coloured rail down a row, and **no green/red**. An expired key is not a
/// failure and a live one is not a success; both are just facts, and painting
/// them would make a tidy-up look like an incident.
///
/// ## The runway means more here than it does next door
///
/// `AppStoreConnectRoomCard` draws its runway only when this device watched the
/// transition, because Apple publishes no start date — so on a fresh install it
/// honestly draws nothing. Here BOTH ends come off the chain (§403), so every
/// session key gets a true bar on first sight, on every device. Each key keeps
/// its OWN bar rather than sharing one axis, for the same reason that card gives:
/// two grants written at different times and lengths on one scale imply a
/// comparison nobody made.
///
/// ## The bar is drawn only when the grant is real
///
/// `AltanaKeystore.Key.progress` returns nil unless the registration date was
/// WITNESSED against the expiry (see the pure file). This card omits the bar in
/// that case rather than drawing an empty or full one — a runway is a claim
/// about elapsed time, and drawing it from an unverified date is the §83 line
/// for this card.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `AltanaRoom`, composed from a
/// UserDefaults snapshot. Corollary 5 has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
struct AltanaRoomCard: View {
    let card: AltanaRoom.Card
    /// Opens Altana's own explorer for this account — the only place a key can
    /// actually be revoked (§112: we read and state, they act).
    var onOpen: () -> Void
    /// Opens one credential's own sheet (§405).
    ///
    /// Until this existed the card's three rows were INERT while looking
    /// exactly like the tappable rows beneath them, and §404's credential
    /// sheet — the grant window, the curve, the live re-check — was reachable
    /// only by scrolling past the card that summarised it. The richest surface
    /// in the feature behind the poorest affordance.
    var onPickKey: (AltanaRoom.KeyRow) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Altana") ?? Color.fixed("#3565e3")
    /// A hairline is banned outright (§8), so the runway is a capsule with real
    /// height rather than a rule.
    private static let runwayHeight: CGFloat = 5

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

            // The census, when the alarm took the headline (§406) — ASC's
            // headline-plus-subline anatomy, restoring the fact the urgency
            // used to delete.
            if let subline = card.subline {
                Text(subline)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }

            if !card.rows.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, row in
                        keyRow(row)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                }
                .padding(.top, DS.Space.s3)
            }

            // The tidy-up line and the scope ceiling, both quiet. The second is
            // not decoration: a session key's powers are NOT readable from the
            // registry, and a card that showed a deadline without saying so
            // would imply we knew what the key could do.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if let stale = card.staleNote {
                    Text(stale)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
                if let other = card.otherWalletsNote {
                    Text(other)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(String(localized: "Only a key’s deadline is published, never its scope."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.top, DS.Space.s3)
        }
        // The section paints the card's BACKGROUND (every sibling head relies
        // on that), but it does NOT inset the contents — `PeerRoomCard` and
        // `AppStoreConnectRoomCard` both keep this padding and drop only the
        // background. Removing both together drew the card edge-to-edge and
        // clipped every trailing label ("today", "25d left", "expired") off
        // the right of the screen.
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func keyRow(_ row: AltanaRoom.KeyRow) -> some View {
        Button {
            DSHaptic.selection()
            onPickKey(row)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(row.title)
                        .dsText(.body17).fontWeight(.medium)
                        .foregroundStyle(DS.textPrimary)
                    Spacer(minLength: DS.Space.s2)
                    Text(trailing(row))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                }
                if let detail = subtitle(row) {
                    Text(detail)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
                // An expired row draws NO bar (§406): a full grey runway made
                // the least important row the heaviest thing on the card, and
                // "expired" in the trailing slot already says everything the
                // bar did. Done things recede.
                if !row.expired, let progress = row.progress {
                    runway(progress: progress)
                }
            }
            .contentShape(Rectangle())
            // …and the whole row dims with them, title included.
            .opacity(row.expired ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(row.title), \(trailing(row))"))
    }

    /// The row's second line. The chain is appended ONLY when this account
    /// spans more than one registry — otherwise the card's footer already
    /// says it once, and repeating "BNB Smart Chain" on every row is chrome.
    private func subtitle(_ row: AltanaRoom.KeyRow) -> String? {
        guard card.chains.count > 1, let chain = row.chainLabel else { return row.detail }
        guard let detail = row.detail else { return chain }
        return detail + " · " + chain
    }

    /// What the right-hand slot says. An expired key states that plainly rather
    /// than showing "0 days", which reads as a countdown still running.
    private func trailing(_ session: AltanaRoom.KeyRow) -> String {
        if session.expired { return String(localized: "expired") }
        // Inside the last day the headline says "9 hours", and a row saying
        // "today" underneath it is the card disagreeing with itself about the
        // same clock (§406).
        if let hours = session.hoursLeft {
            return hours == 0 ? String(localized: "under 1h left")
                              : String(localized: "\(hours)h left")
        }
        guard let days = session.daysLeft else {
            // A credential that never runs out — which is what a root key IS,
            // and the fact worth stating in the slot where every other row
            // carries a countdown.
            guard let expiry = session.expiry else { return String(localized: "no expiry") }
            return expiry.formatted(date: .abbreviated, time: .omitted)
        }
        return String(localized: "\(days)d left")
    }

    private func runway(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.textTertiary.opacity(0.18))
                Capsule()
                    .fill(Self.mark)
                    .frame(width: max(2, geo.size.width * progress))
            }
        }
        .frame(height: Self.runwayHeight)
        .accessibilityLabel(Text("\(Int(progress * 100)) percent through its grant"))
    }
}
