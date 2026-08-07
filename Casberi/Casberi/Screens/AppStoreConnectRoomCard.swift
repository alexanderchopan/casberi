import SwiftUI

/// THE APP STORE CONNECT ROOM'S HEAD (2026-08-06, prd §324) — where every app
/// stands right now.
///
/// The anatomy is `StripeRoomCard`'s, which took it from `CloudflareRunwayCard`
/// and `WalletApprovalExposureCard`, where these rulings were made: a kicker in
/// the card's one hue, a heavy headline stating the whole finding as a sentence,
/// ranked rows, and no decoration that isn't a reading. What was ruled out there
/// is out here — no coloured rail down the side of a row, and **no green/red**:
/// a rejection is stated in words, not painted, exactly as a Stripe dispute is.
///
/// ## What replaces the rail
///
/// Stripe and Cloudflare both draw one time axis, because both rooms are about
/// deadlines converging on you. This room has ONE clock — a TestFlight build's
/// 90-day death — and it belongs to a single app rather than to the card, so a
/// shared axis would place two apps' unrelated builds on one scale and imply a
/// comparison nobody made. Each app gets its own thin runway instead, drawn only
/// when there is a build with an expiry to draw.
///
/// ## The duration is drawn only when it is real
///
/// `ASCRoom.waitLabel` returns nil for a state this device didn't watch arrive,
/// and this card simply omits it. That is the §83 line for this card: "In review
/// · 0 days" on a version Apple has had since Tuesday is a confident wrong
/// answer about the one number being watched. See `ASCStanding.observed`.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `ASCRoom`. Corollary 5 has
/// nothing to guard here; the lookup happens at the tap, in the section that
/// owns the sheet.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
struct AppStoreConnectRoomCard: View {
    let room: ASCRoom
    /// Hands back the APP, not a `Thing` — the card never holds one.
    var onOpen: (ASCRoom.App) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "App Store Connect") ?? Color.fixed("#0a84ff")
    /// How thin the runway is. A hairline is banned outright (§8), so this is a
    /// capsule with real height rather than a rule.
    private static let runwayHeight: CGFloat = 5

    private var drawn: [ASCRoom.App] {
        Array(room.apps.prefix(ASCRoomSource.rowCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "App Store Connect"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(ASCRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            // Only the apps BEYOND the lead get a row — the lead is the
            // headline, and repeating it directly underneath is the card
            // arguing with itself. Its build runway still draws, because that
            // is a fact the headline doesn't carry.
            if let lead = room.lead, let runway = runwayLabel(lead) {
                Text(runway)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
                runwayBar(lead)
                    .padding(.top, DS.Space.s2)
            }

            if drawn.count > 1 {
                ForEach(Array(drawn.dropFirst().enumerated()), id: \.element.id) { index, app in
                    row(app)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s3)
            }

            if let note = ASCRoom.note(room, drawn: drawn.count) {
                Text(note)
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

    // MARK: - Rows

    private func row(_ app: ASCRoom.App) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(app)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(app.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(standingLine(app))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                if runwayLabel(app) != nil { runwayBar(app) }
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "In review · 2 days", or just the state when we never watched it arrive.
    private func standingLine(_ app: ASCRoom.App) -> String {
        var line = ASCRoom.stateLabel(app.state)
        if let wait = ASCRoom.waitLabel(days: app.days) { line += " · \(wait)" }
        return line
    }

    private func runwayLabel(_ app: ASCRoom.App) -> String? {
        guard app.expiresInDays != nil else { return nil }
        return ASCRoom.buildLabel(app)
    }

    // MARK: - The runway

    /// How much of a TestFlight build's life is left, as one capsule.
    ///
    /// Its full width is the 90 days Apple gives a build, so the bar SHORTENS
    /// as the deadline approaches and two apps' bars are comparable without a
    /// shared axis. It is one length and one hue — the §300 rule that area
    /// means magnitude and only magnitude — with no colour change near the end:
    /// the words beside it already say "2 days left", and turning the bar red
    /// would be the same fact twice, in the register this card doesn't use.
    private func runwayBar(_ app: ASCRoom.App) -> some View {
        let left = max(0, min(Self.buildLife, app.expiresInDays ?? 0))
        let fraction = Double(left) / Double(Self.buildLife)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.surfaceWell)
                Capsule()
                    .fill(Self.mark.opacity(0.85))
                    // A build on its last day still draws something — a bar
                    // that vanishes reads as "no build" rather than "no time".
                    .frame(width: max(Self.runwayHeight, geo.size.width * fraction))
            }
        }
        .frame(height: Self.runwayHeight)
        .accessibilityLabel(ASCRoom.buildLabel(app) ?? "")
    }

    /// Apple's own TestFlight lifetime, and the bar's full width. Stated here
    /// rather than in `ASCRoom` because it is a DRAWING constant — nothing in
    /// the model's arithmetic depends on it.
    private static let buildLife = 90
}
