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

    /// The recording tone, and the only red a tile draws: the app's
    /// `DS.destructive` on a dark ground (`#ff453a`), spelled here because
    /// `Design/` is app-side. It marks one state — a voice note recording.
    static let recording = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)

    /// A change's direction, the app's `DS.confirm` / `DS.destructive` on a dark
    /// ground (`#30d158`, `#ff453a`), spelled once so no tile picks its own
    /// green or red (prd §782). A flat change takes neither (§83).
    ///
    /// They are WORDS on the tile, so they take the app's status INKS (prd
    /// §1004): the hue in dark, the darker ink on the white ground in light
    /// (`DS.confirmInk` / `destructiveInk`, `#1f7936` / `#c62e25`).
    static let gain = adaptive(dark: (48, 209, 88), light: (31, 121, 54))
    static let loss = adaptive(dark: (255, 69, 58), light: (198, 46, 37))

    /// A tile's header: Casberi pink (user, 2026-10-04: "we don't use blue").
    /// `DS.brandInk`'s two registers (`#e0193a` light, `#fb3a53` dark, Apple
    /// Music's hue since prd §1252), spelled here because `Design/` is
    /// app-side.
    static let header = adaptive(dark: (251, 58, 83), light: (224, 25, 58))

    static func adaptive(dark: (Int, Int, Int), light: (Int, Int, Int)) -> Color {
        func ui(_ c: (Int, Int, Int)) -> UIColor {
            UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                    blue: CGFloat(c.2) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? ui(dark) : ui(light)
        })
    }

    /// The app accent, carried across the app group by `ThemeStore` (falls back
    /// to Casberi blue before the app has ever written it — the same
    /// `ThemeStore.accentHex` that `DS.tint` draws). The Live Activities' only;
    /// the Home Screen tiles are black and white with a pink header.
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

/// Every tile's ground: white in light mode, black in dark (user, 2026-10-04:
/// "black and white", "we don't use blue"). It replaced a black slab with the
/// accent's pour over it.
///
/// `.accented` (the lock screen, StandBy) and `.vibrant` (a tinted Home Screen,
/// and iOS 26's glass appearances) mean "the system provides the backing and
/// re-renders your content over it". A tile that paints its own opaque slab
/// there fights that and wins, which is how a tinted Home Screen ends up with
/// one black tile on it — so those modes get nothing, and the system's
/// material shows. **UNVERIFIED in `.vibrant`**: neither the simulator nor any
/// check can show a tinted Home Screen.
struct WidgetField: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if mode == .fullColor {
            scheme == .dark ? Color.black : Color.white
        } else {
            Color.clear
        }
    }
}

/// A tile's own name, in Casberi pink, above its content.
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
            .foregroundStyle(WidgetChrome.header)
            .lineLimit(1)
            .widgetAccentable()
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
