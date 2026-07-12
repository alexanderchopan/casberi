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
    static var themedTint: Color { Color(hex: ThemeStore.accentHex) }
    static var themedTintDim: Color { themedTint.opacity(0.16) }

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

extension View {
    /// Every full screen wears this instead of `.background(DS.page)`.
    func dsPageBackground() -> some View {
        background { DSPageBackground() }
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
}
