import SwiftUI
import Observation

/// The person's chosen Home BACKGROUND (2026-07-10) — a wallpaper, not a
/// banner. The banner band kept reading as content competing with content;
/// as the page canvas, the choice becomes ambient and the dark cards float
/// on it (the chat-app wallpaper mental model). Home-only, per the retired
/// app-wide theme's post-mortem: one image, one screen, one clear purpose.
/// Default is no choice at all — the standard page, unchanged.
@Observable
final class HomeBackgroundStore {
    static let shared = HomeBackgroundStore()

    /// A curated color still stores a small flat-fill image alongside its
    /// name — the Settings tile shows it as the choice's thumbnail, and one
    /// `image != nil` check means "a background is set" for both kinds.
    /// UserDefaults keys keep the old "home.cover" names so a banner chosen
    /// before the pivot survives as the same person's background.
    enum Kind: String { case photo, color }
    static let swatches: [(name: String, hex: String)] = [
        ("Purple", "#8a3ffc"), ("Pink", "#ff2d78"), ("Red", "#ff3b30"),
        ("Orange", "#ff7a00"), ("Teal", "#00b3bf"), ("Green", "#18b84a"),
    ]

    var image: UIImage? {
        didSet {
            if let data = image?.jpegData(compressionQuality: 0.85) {
                UserDefaults.standard.set(data, forKey: "home.cover")
            } else {
                UserDefaults.standard.removeObject(forKey: "home.cover")
                kind = nil
                colorName = nil
            }
            revision += 1
        }
    }

    /// Bumps on every change so anything that can't observe the image
    /// directly (an Equatable onChange) has one value to watch.
    private(set) var revision = 0

    var kind: Kind? {
        didSet { UserDefaults.standard.set(kind?.rawValue, forKey: "home.cover.kind") }
    }

    /// The swatch name in force, when the chosen background is a color —
    /// nil for a photo or no choice. Drives the picker's selected state.
    var colorName: String? {
        didSet { UserDefaults.standard.set(colorName, forKey: "home.cover.colorName") }
    }

    /// The wallpaper form of a chosen color — the swatch deepened toward
    /// black (~45%) so the page stays a dark field the gray section labels
    /// and white ink read on. The swatch circle shows the bright identity;
    /// the page wears the deep version.
    var wallpaperColor: Color? {
        guard kind == .color, let colorName,
              let swatch = Self.swatches.first(where: { $0.name == colorName })
        else { return nil }
        return Color(hex: swatch.hex).mix(with: .black, by: 0.45)
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "home.cover") {
            image = UIImage(data: data)
        }
        kind = UserDefaults.standard.string(forKey: "home.cover.kind").flatMap(Kind.init)
        colorName = UserDefaults.standard.string(forKey: "home.cover.colorName")
    }

    /// Sets a curated color as the background — the flat-fill image is the
    /// Settings tile's thumbnail; the page paints `wallpaperColor` directly.
    func setColor(_ swatch: (name: String, hex: String)) {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let fill = UIColor(Color(hex: swatch.hex))
        let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            fill.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        }
        colorName = swatch.name
        kind = .color
        image = thumb
    }

    func setPhoto(_ photo: UIImage) {
        colorName = nil
        kind = .photo
        image = Self.prepared(photo)
    }

    func clear() {
        image = nil
    }

    /// Downscaled to a sane wallpaper size — the renderer's scale is pinned
    /// to 1, so this is the real max pixel width (same guard as Avatar).
    private static func prepared(_ image: UIImage, maxSide: CGFloat = 1600) -> UIImage {
        let scale = maxSide / max(image.size.width, image.size.height)
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Home's page field — the chosen wallpaper (deepened color, or the photo
/// under the standard 0.5→0.72 scrim so every label stays legible), else
/// the same default page every other screen paints. Lives INSIDE the screen
/// for the same reason DSPageBackground does: NavigationStack's UIKit
/// backing is opaque.
struct HomePageBackground: View {
    var body: some View {
        ZStack {
            let store = HomeBackgroundStore.shared
            if let color = store.wallpaperColor {
                color
            } else if store.kind == .photo, let photo = store.image {
                DS.themedPage
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
            } else {
                DSPageBackground()
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Home wears this instead of `.dsPageBackground()` — the one screen
    /// with its own wallpaper.
    func homePageBackground() -> some View {
        background { HomePageBackground() }
    }
}
