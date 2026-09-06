import SwiftUI
import Observation

/// Appearance — two global knobs, no per-element fiddling: mode (dark/light)
/// and background (curated color or the person's photo; a photo implies the
/// dark treatment so text stays readable — gap §9.3 stays parked until
/// on-device review). The accent is not a knob (ruling 2026-07-05): the old
/// five options were hex-identical to kind hues, so a picked accent made one
/// kind look pressable everywhere. One fixed blue; kinds own identity.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    // MARK: Accent (fixed)

    /// Casberi blue — off the logo berry's gradient, one step deeper than
    /// the top circle, so it is NOT the link kind's #0a84ff. Interaction ink
    /// only: buttons, active tab, chips, small marks.
    static let accentHex = "#1673e6"

    // MARK: Mode

    var isLight: Bool {
        didSet { UserDefaults.standard.set(isLight, forKey: "theme.light") }
    }

    // MARK: Background color (curated — every option keeps the text ramp legible)

    /// The swatch wears EXACTLY what it applies, in the mode you're in
    /// (ruling 2026-07-05: no wash — choosing a color gives that color,
    /// solid). So the applied darks are real colors, not tinted blacks;
    /// each pair keeps white (dark) / black (light) text ≥ 10:1.
    struct Background: Identifiable, Equatable {
        let name: String
        let darkHex: String
        let lightHex: String
        var id: String { name }
    }

    /// Default is the system's own pair: true black in dark, Apple's
    /// grouped-background gray (#f2f2f7) in light. The rest are BRIGHT primaries
    /// (user ruling 2026-07-06 — "bright primary colors, not muted tints"): the
    /// dark treatment wears the vivid color at full voice, the light treatment a
    /// paler wash of the same hue. Content floats on the dark surface cards, so
    /// body text stays on its own field; the vivid color is the page around it.
    /// Blue is deliberately absent: the fixed accent is blue, so a blue page
    /// makes the blue-tinted treemap and eyebrows collide (blue-on-blue). Every
    /// other primary contrasts with the accent and stays crisp.
    static let backgrounds: [Background] = [
        Background(name: "Default", darkHex: "#000000", lightHex: "#f2f2f7"),
        Background(name: "Purple",  darkHex: "#8a3ffc", lightHex: "#c9a8ff"),
        Background(name: "Pink",    darkHex: "#ff2d78", lightHex: "#ffa5c4"),
        Background(name: "Red",     darkHex: "#ff3b30", lightHex: "#ff9f99"),
        Background(name: "Orange",  darkHex: "#ff7a00", lightHex: "#ffc584"),
        Background(name: "Teal",    darkHex: "#00b3bf", lightHex: "#8fe0e6"),
        Background(name: "Green",   darkHex: "#18b84a", lightHex: "#8fe0a6"),
    ]

    var background: Background {
        didSet { UserDefaults.standard.set(background.name, forKey: "theme.background") }
    }

    // MARK: Background photo (implies the dark treatment)

    var backgroundPhoto: UIImage? {
        didSet {
            // Downscaled to screen size and stored as a file — never raw
            // multi-megabyte images in the render tree or UserDefaults.
            let url = Self.photoURL
            if let photo = backgroundPhoto,
               let data = photo.jpegData(compressionQuality: 0.8) {
                try? data.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static var photoURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("theme-background.jpg")
    }

    /// The background photo's on-disk location — the Data sheet counts it in
    /// the storage total and clears it on Delete everything.
    static var photoFileURL: URL { photoURL }

    // The BLEED — the crown pour's colour, six curated swatches — is GONE
    // (prd §635, 2026-09-06). It defaulted to Ink, which pours nothing, so
    // the whole feature was a settings screen whose job was to switch on a
    // wash §524 had ruled against. See `MainSurface`'s note where the pour
    // itself was removed.


    /// Fits an image to a sane render size for a phone background. The
    /// renderer's scale is pinned to 1 — its default is the device scale,
    /// which would silently multiply the bitmap right back up (3× here).
    static func prepared(_ image: UIImage, maxSide: CGFloat = 1600) -> UIImage {
        let scale = maxSide / max(image.size.width, image.size.height)
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The Theme tile's subline — states the setting in force.
    var summary: String {
        isLight ? String(localized: "Light") : String(localized: "Dark")
    }

    private init() {
        let d = UserDefaults.standard
        isLight = d.bool(forKey: "theme.light")
        // Ruling 2026-07-06: appearance is ONE knob — light or dark. The
        // background-color and photo pickers are retired; stored choices
        // migrate to Default and the photo file is removed (its UI is gone,
        // so a lingering choice would be unreachable state).
        background = Self.backgrounds[0]
        d.removeObject(forKey: "theme.background")
        try? FileManager.default.createDirectory(
            at: Self.photoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Self.photoURL)
        // Migrate away any old UserDefaults-stored photo, and the retired
        // accent choice. The widget reads the accent from the app group —
        // keep it current so the home screen wears the same blue.
        d.removeObject(forKey: "theme.photo")
        d.removeObject(forKey: "theme.tint")
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(Self.accentHex, forKey: "theme.tint.hex")
    }
}

extension DS {
    /// Live theme accessors — reading these inside a view body tracks the
    /// observable store, so a change repaints every token consumer.
    /// Casberi blue, which the accent picker no longer varies. Under Increase
    /// Contrast it steps to a measured pair (≥4.5:1 on every page/sheet/well
    /// surface in both modes) — the shipped blue measures 3.8:1 on the light
    /// well and 4.2:1 on the dark sheet, fine for a fill but thin for the link
    /// and button words it also paints. `accentHex` itself is untouched: the
    /// widget reads that value out of the app group and has no such setting.
    static var themedTint: Color {
        ContrastStore.shared.increased
            ? Color.adaptive(dark: "#62a1ee", light: "#1366cd")
            : Color(hex: ThemeStore.accentHex)
    }
    static var themedTintDim: Color { themedTint.opacity(0.16) }

    /// The detail surface's ground (`dsInk()`).
    ///
    /// "THE INK SHEET" (prd, 2026-07-07) made the thing sheet ink-black in
    /// BOTH modes — "like a photo viewer" — and that held. It is reversed here
    /// (2026-08-12, user ruling, on a tester report): a black rectangle
    /// arriving out of a white page does not read as a photo viewer, it reads
    /// as the app losing its place, and the sheet is no longer mostly a photo
    /// — six category anatomies now carry the words that answer "what IS
    /// this?", which is reading, and reading follows the theme.
    ///
    /// What survives that ruling is the IDEA, which was never "black": the
    /// detail
    /// surface is the extreme of its theme, not another card floating on the
    /// page. So it stays pure `#000` in dark and becomes pure `#ffffff` in
    /// light — the absolute floor and the absolute ceiling, each one tonal
    /// step past the sheet colour its own theme uses for cards. Over a
    /// background PHOTO it stays black, because that path is already forced
    /// dark for legibility (§9.3's parked gap) and a white sheet there would
    /// be the one surface fighting the picture behind it.
    static var inkGround: Color {
        ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil
            ? .white : .black
    }


    /// The pour's colour where it PREVIEWS the setting rather than paints it —
    /// the Color row's badge in settings, the pour card's own glyph. Ink has
    /// no colour to preview, and drawing its `#000000` there would be an
    /// invisible glyph on a dark card (a dead control by sight, honesty rule),
    /// so it previews as secondary ink like the Theme row's sun/moon.

    /// The themed page color (photo rendering is the shell's job). A chosen
    /// photo implies the dark treatment regardless of mode.
    static var themedPage: Color {
        let store = ThemeStore.shared
        return (store.isLight && store.backgroundPhoto == nil)
            ? Color(hex: store.background.lightHex)
            : Color(hex: store.background.darkHex)
    }

}

/// The page field a screen paints behind its content — the themed color, or
/// the person's photo under the prototype's scrim (0.5→0.72 black). Lives
/// INSIDE each screen because NavigationStack's UIKit backing is opaque: a
/// layer behind the nav stack can never show through it.
struct DSPageBackground: View {
    var body: some View {
        ZStack {
            DS.themedPage
            if let photo = ThemeStore.shared.backgroundPhoto {
                // Pinned to the screen's geometry — a bare scaledToFill would
                // expand the layout to the photo's size.
                GeometryReader { geo in
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(
                            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.72)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Caps content to a fixed column on iPad (regular width) so rows and text
/// stop touching the physical screen edges — iPhone (compact width) is
/// untouched. No multi-column layout: this only narrows and centers the
/// SAME single-column content each screen already draws. Backgrounds stay
/// full-bleed (apply this BEFORE `.dsPageBackground()` in the modifier
/// chain, so the background paints the full width behind the centered
/// content, not just the narrowed column).
private struct AdaptiveContentWidth: ViewModifier {
    let width: DSContentWidth
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: width.points)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

/// Which of the two iPad columns a screen's content wants (2026-07-25).
enum DSContentWidth {
    /// A single file of rows or form fields — Settings, every bridge setup
    /// screen, the feed. The default, because that is what nearly every
    /// screen in this app is.
    case reading
    /// A grid or catalog, which answers extra width with extra COLUMNS
    /// rather than longer rows, and so earns more of the canvas.
    case wide

    var points: CGFloat {
        switch self {
        case .reading: DS.Layout.iPadReadingMaxWidth
        case .wide:    DS.Layout.iPadWideMaxWidth
        }
    }
}

extension View {
    /// Every full screen wears this instead of `.background(DS.page)`.
    func dsPageBackground() -> some View {
        background { DSPageBackground() }
    }

    /// iPad-only content-width cap (see `AdaptiveContentWidth`). A no-op on
    /// iPhone. Apply to the screen's own content root (its List/ScrollView),
    /// immediately before `.dsPageBackground()` where that screen has one.
    /// Defaults to the READING column; pass `.wide` from a grid/catalog.
    func dsAdaptiveContentWidth(_ width: DSContentWidth = .reading) -> some View {
        modifier(AdaptiveContentWidth(width: width))
    }

    /// The screen title, sized for the device (2026-07-25). On iPhone this is
    /// the large title every screen already wore. On iPad it goes INLINE:
    /// a large title is laid out by the system against the physical screen
    /// edge, while the content below it is capped and centred by
    /// `dsAdaptiveContentWidth()` — so the two sat on different axes and the
    /// screen read as two unrelated layouts stacked ("Settings" jammed into
    /// the top-left corner of an empty canvas with its card floating in the
    /// middle). Inline centres the title over the column instead, which is
    /// also what iPad system apps do.
    func dsScreenTitle(_ title: LocalizedStringKey) -> some View {
        modifier(DSScreenTitle(title: Text(title)))
    }

    /// The dynamic-title overload (a provider's name, a scoped wallet's
    /// label). Mirrors `navigationTitle`'s own pair, so a string LITERAL at a
    /// call site still resolves to the localized version above.
    func dsScreenTitle<S: StringProtocol>(_ title: S) -> some View {
        modifier(DSScreenTitle(title: Text(title)))
    }

    /// The person's mode, restated. The root shell already sets this, but a
    /// presented sheet is its own presentation and doesn't reliably inherit
    /// the flip — so every sheet's content wears it too, or its adaptive
    /// tokens resolve against stale traits (the dark-tray-in-light-mode bug).
    func dsColorScheme() -> some View {
        preferredColorScheme(
            ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil ? .light : .dark
        )
    }

    /// Pure ink: the extreme of the current theme — the stronger
    /// override for a "detail" surface (`ThingSheetView`, `TokenQuickSheet`,
    /// `SocialPostSheet`, `SocialProfileCard`) or a tray that precedes one
    /// (`DSTray(ink: true)`), so the two read as one continuous sheet
    /// instead of `dsColorScheme()`'s theme-adaptive default showing through
    /// a shade off (2026-07-24, user: "the wallet worth a look details tray
    /// is not ink colored" / "farcaster and bluesky when you tap a face").
    ///
    /// A real `.background` fill, not just `.presentationBackground` alone:
    /// the latter is a preference read once at initial presentation setup,
    /// and stops taking effect once something pushes past this view inside a
    /// `NavigationStack` — so a destination pushed past an ink tray/sheet
    /// needs `.dsInk()` applied again at its own call site (see
    /// `WalletWorthALookTray`'s pushed `ThingSheetView`).
    func dsInk() -> some View {
        let ground = DS.inkGround
        return self
            .background(ground.ignoresSafeArea())
            .presentationBackground(ground)
            // Follows the ground rather than forcing dark, or every adaptive
            // token in the sheet would resolve to its dark value against a
            // white page — which is the black-on-black failure, inverted.
            .colorScheme(ground == .white ? .light : .dark)
    }
}

/// See `dsScreenTitle(_:)`.
private struct DSScreenTitle: ViewModifier {
    let title: Text
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .inline : .large)
    }
}
