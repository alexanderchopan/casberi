import SwiftUI

/// THE APP STORE CONNECT ROOM'S HEAD (2026-08-06, prd §324) — where every app
/// stands right now.
///
/// A heavy headline stating the whole finding as a sentence, the other apps as
/// rows, and no decoration that isn't a reading. What was ruled out for Stripe
/// is out here — no coloured rail down the side of a row, and **no green/red**:
/// a rejection is stated in words, not painted, exactly as a Stripe dispute is.
///
/// ## What replaces the rail
///
/// Stripe draws one time axis, because that room is about deadlines converging
/// on you. This room has ONE clock — a TestFlight build's 90-day death — and it
/// belongs to a single app rather than to the card, so a shared axis would place
/// two apps' unrelated builds on one scale and imply a comparison nobody made.
/// Each app gets its own thin runway instead, drawn only when there is a build
/// with an expiry to draw.
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
/// Stores no `Thing` — only value types out of `ASCRoom`. The lookup happens at
/// the tap, in the section that owns the sheet.
///
/// Composed through `DSRoomChassis.Head` and its ranked `Row` (prd §745).
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
        let leadRunway = room.lead.flatMap { runwayLabel($0) }
        DSRoomChassis.Head(
            lead: .sentence(ASCRoom.headline(room)),
            // The lead has no row of its own (see below), so the headline is
            // the only place its destination can be reached.
            door: room.lead.map { lead in
                DSRoomChassis.Door(hint: Text("Opens this app")) { onOpen(lead) }
            },
            notes: [.note(leadRunway)],
            footnotes: [.quiet(ASCRoom.note(room, drawn: drawn.count))]) {
            // Only the apps BEYOND the lead get a row — the lead is the
            // headline, and repeating it directly underneath is the card
            // arguing with itself. Its build runway still draws, because that
            // is a fact the headline doesn't carry.
            if let lead = room.lead, leadRunway != nil {
                DSRoomChassis.Block { runwayBar(lead) }
            }

            if drawn.count > 1 {
                DSRoomChassis.Block {
                    ForEach(Array(drawn.dropFirst().enumerated()), id: \.element.id) { index, app in
                        DSRoomChassis.Row(
                            title: app.name,
                            line: standingLine(app),
                            index: index,
                            action: { onOpen(app) }) {
                            if runwayLabel(app) != nil { runwayBar(app) }
                        }
                    }
                }
            }
        }
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
        // The runway states a length, so it reveals along that length — the
        // entrance the rows' own arrival used to stand in for before the rows
        // moved into the template (prd §745, design-motion-audit check 2).
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityLabel(ASCRoom.buildLabel(app) ?? "")
    }

    /// Apple's own TestFlight lifetime, and the bar's full width. Stated here
    /// rather than in `ASCRoom` because it is a DRAWING constant — nothing in
    /// the model's arithmetic depends on it.
    private static let buildLife = 90
}
