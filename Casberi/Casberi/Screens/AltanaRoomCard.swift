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

            if let root = card.rootLine {
                Text(root)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }

            if !card.sessions.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(Array(card.sessions.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session)
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
                Text(String(localized: "What a session key may sign for isn’t published — only until when."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sessionRow(_ session: AltanaRoom.Session) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(session.grantPhrase ?? String(localized: "Session key"))
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: DS.Space.s2)
                Text(trailing(session))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            if let progress = session.progress {
                runway(progress: progress, expired: session.expired)
            }
        }
    }

    /// What the right-hand slot says. An expired key states that plainly rather
    /// than showing "0 days", which reads as a countdown still running.
    private func trailing(_ session: AltanaRoom.Session) -> String {
        if session.expired { return String(localized: "expired") }
        guard let days = session.daysLeft else {
            guard let expiry = session.expiry else { return "" }
            return expiry.formatted(date: .abbreviated, time: .omitted)
        }
        return days == 0 ? String(localized: "today")
                         : String(localized: "\(days)d left")
    }

    private func runway(progress: Double, expired: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.textTertiary.opacity(0.18))
                Capsule()
                    .fill(expired ? DS.textTertiary : Self.mark)
                    .frame(width: max(2, geo.size.width * progress))
            }
        }
        .frame(height: Self.runwayHeight)
        .accessibilityLabel(Text("\(Int(progress * 100)) percent through its grant"))
    }
}
