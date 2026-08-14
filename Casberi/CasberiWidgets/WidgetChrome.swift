import SwiftUI
import WidgetKit

/// The pieces every Casberi tile is built from (2026-08-14, prd §382).
///
/// Until this file there was one widget, so its chrome lived inside it as
/// private types. There are four now, and the parts that must not drift between
/// them — the field behind the content, the accent they tint with, the way a
/// stale reading is stamped — live here instead. `Design/` is app-target only
/// (the widget syncs `Shared/` and `CasberiWidgets/` and nothing else), so this
/// is the widget's design system: `dsText`/`dsGlyph` out of `Shared/Typography`
/// and these.
enum WidgetChrome {
    /// One radius for every tile's inner blocks. `DS.Radius` is app-side, so
    /// the number is spelled here rather than imagined to be shared.
    static let blockRadius: CGFloat = 12

    /// The app accent, carried across the app group by `ThemeStore` (falls back
    /// to Casberi blue before the app has ever written it).
    static var accent: Color {
        let hex = UserDefaults(suiteName: SharedStore.appGroup)?
            .string(forKey: "theme.tint.hex") ?? "#1673e6"
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        return Color(red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255)
    }
}

/// The widget's own field (2026-08-06, generalized to every tile 2026-08-14).
/// It was a hardcoded `.black`, which is wrong in two of the three rendering
/// modes the system asks for and was never looked at again after it shipped.
///
/// `.accented` (the lock screen, StandBy) and `.vibrant` (a tinted Home Screen,
/// and the glass appearances iOS 26 added on top of it) both mean "the system
/// will provide the backing and re-render your content for legibility over it".
/// A widget that paints its own opaque slab there fights that treatment and
/// wins — which is how a tinted Home Screen ends up with one black tile on it.
/// So those modes get nothing, deliberately, and the system's material shows.
///
/// `.fullColor` keeps a dark ground, and gains the app's own crown pour — the
/// one atmospheric move the shell makes (§159), in the person's own chosen
/// accent, which the app already writes across the app group. The widget is the
/// app's face on a Home Screen; wearing the app's signature field costs one
/// gradient and makes the tile recognizably ours rather than a black rectangle
/// with text on it.
///
/// **UNVERIFIED in `.vibrant`.** Neither the simulator nor any build check can
/// show a tinted Home Screen, so the `.fullColor` path is the only one that has
/// been seen. It fails safe: the modes that now get nothing were getting an
/// opaque slab the system had already told us not to draw, so the worst case is
/// the system's own backing instead of ours.
struct WidgetField: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        // Read once, not per gradient stop — three UserDefaults lookups and
        // three Scanner passes to draw one field is silly in a ~30MB extension.
        let accent = WidgetChrome.accent
        switch mode {
        case .fullColor:
            ZStack(alignment: .top) {
                Color.black
                // Half the shell's own dose: a widget is a fraction of the
                // height the crown pour was tuned against, so the same alphas
                // would read as a wash over the whole tile rather than a field
                // at the top of one.
                LinearGradient(stops: [
                    .init(color: accent.opacity(0.16), location: 0),
                    .init(color: accent.opacity(0.05), location: 0.5),
                    .init(color: accent.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        default:
            // Nothing. See the type's own note — the system owns the backing in
            // `.accented` and `.vibrant`, and anything painted here overrides it.
            Color.clear
        }
    }
}

/// A tile's own name, in the app's accent, above its content.
///
/// Sentence case and no letter-spacing, like every other header in the product
/// (2026-07-08 ruling, no exceptions). It exists because a Home Screen holding
/// three Casberi tiles otherwise gives you no way to tell which is which until
/// you read all three; the hero deliberately does NOT wear one, because its
/// whole content is one sentence and a label above it would be the eyebrow §193
/// already removed.
struct WidgetLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .dsText(.widgetEyebrow11)
            .foregroundStyle(WidgetChrome.accent)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// A sparkline over a normalized 0…1 series, oldest first.
///
/// Takes ALREADY-normalized points (`WidgetWalletLine.normalizedPoints`) rather
/// than raw values, so the flat-series rule — a curve that didn't move draws
/// down the MIDDLE, never along the floor — lives in one tested place in
/// `Shared/` instead of inside a `Path` nothing can reach.
struct WidgetSpark: Shape {
    let normalized: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard normalized.count >= 2 else { return path }
        // Inset by the stroke's own half-width at both ends, so the first and
        // last points aren't clipped in half by the frame they're drawn in.
        let inset: CGFloat = 1.5
        let usable = rect.insetBy(dx: 0, dy: inset)
        let step = rect.width / CGFloat(normalized.count - 1)
        for (i, value) in normalized.enumerated() {
            // Flipped: 0 is the bottom of the tile, and a `Path`'s origin is
            // the top-left.
            let point = CGPoint(x: rect.minX + CGFloat(i) * step,
                                y: usable.maxY - CGFloat(value) * usable.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// One thing with a deadline, as a row.
///
/// The trailing time is `Text(_:style:.relative)` — a self-updating label the
/// system re-renders on its own clock, so the row keeps counting down between
/// timeline refreshes instead of freezing at whatever it said when the entry was
/// made. The OVERDUE state is decided by the view from the date at draw time
/// (`WidgetDeadline.isOverdue`), never read from a published flag — see
/// `WidgetDeadline`'s own note for why a boolean about "now" must not be stored
/// in a timeline entry.
struct WidgetDueRow: View {
    let row: WidgetDeadline
    /// Whether to name the app it came from. The large family has the room and
    /// a deadline with no provenance is a demand from nowhere; the medium
    /// family spends that line on the title instead.
    var showsSource = true

    private var overdue: Bool { row.isOverdue() }

    var body: some View {
        // Read ONCE per row, not once per use — `WidgetField` states this rule
        // for its own gradient stops and it matters more here, since the large
        // family draws four of these and each was costing two UserDefaults
        // lookups and two Scanner passes to paint one dot and one timestamp.
        let accent = WidgetChrome.accent
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            // A dot, not an exclamation glyph: the accent already carries
            // urgency and a warning triangle on a Home Screen reads as an app
            // error rather than as your own task being late.
            Circle()
                .fill(overdue ? accent : Color.white.opacity(0.35))
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .dsText(.widgetRecentTitle12)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if showsSource {
                    Text(row.source)
                        .dsText(.widgetSubline11)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(row.due, style: .relative)
                .dsText(.widgetSubline11)
                .foregroundStyle(overdue ? accent : .white.opacity(0.6))
                .lineLimit(1)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// How a figure is drawn when "Hide wallet balances" is on (§374).
///
/// §374's rule 2: a hidden value must read as HIDDEN — never as zero and never
/// as blank. Both of those readings are already spent elsewhere in the wallet
/// (0 means a grant that genuinely reaches nothing; blank means we couldn't
/// know), so borrowing either here would turn a privacy setting into a false
/// statement about somebody's money.
enum WidgetMask {
    static let figure = "••••"
}

/// "as of 5h ago", or nothing at all.
///
/// A reading that is merely a few hours old is the NORMAL cadence — wallet
/// sampling is throttled to one point per four hours — so stamping every tile
/// all day would cry wolf and teach people to ignore the stamp on the one day
/// it matters. Past that, the stamp is the difference between two different
/// claims: "$12,480" and "$12,480, as of yesterday afternoon".
enum WidgetStamp {
    static func text(for date: Date, now: Date = .now,
                     after threshold: TimeInterval) -> String? {
        let age = now.timeIntervalSince(date)
        guard age > threshold else { return nil }
        let hours = Int(age / 3600)
        if hours < 24 {
            return String(localized: "as of \(hours)h ago")
        }
        let days = hours / 24
        return days == 1 ? String(localized: "as of yesterday")
                         : String(localized: "as of \(days) days ago")
    }
}
