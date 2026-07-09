import SwiftUI
import Observation

/// The person's chosen Home cover (2026-07-09) — the same idea as Avatar
/// (goal 6: one image, owned locally), but for Home's cover instead of the
/// Account tab. Answers the privacy gap in the automatic cover: a fresh
/// screenshot could be something the person doesn't want leading Home. When
/// set, it always wins over the day's newest screenshot — an explicit
/// choice outranks an automatic guess. It renders SHORTER than a live photo
/// cover (150pt vs 250pt) so the two states read differently: a tall bleed
/// means "this just happened," a banner means "this is what I chose."
@Observable
final class HomeCoverStore {
    static let shared = HomeCoverStore()

    /// A curated color IS a photo underneath (a flat-fill image) — GenCover
    /// already knows how to show a banner image at its shorter height, so a
    /// color choice needs no new rendering path. `kind` only tracks
    /// provenance, for the picker to show which swatch (or "Photo") is
    /// currently chosen. Same six vivid primaries the retired Theme
    /// background picker used (2026-07-05 ruling: bright, not muted).
    enum Kind: String { case photo, color }
    static let swatches: [(name: String, hex: String)] = [
        ("Purple", "#8a3ffc"), ("Pink", "#ff2d78"), ("Red", "#ff3b30"),
        ("Orange", "#ff7a00"), ("Teal", "#00b3bf"), ("Green", "#18b84a"),
    ]

    var banner: UIImage? {
        didSet {
            if let data = banner?.jpegData(compressionQuality: 0.85) {
                UserDefaults.standard.set(data, forKey: "home.cover")
            } else {
                UserDefaults.standard.removeObject(forKey: "home.cover")
                kind = nil
                colorName = nil
            }
        }
    }

    var kind: Kind? {
        didSet { UserDefaults.standard.set(kind?.rawValue, forKey: "home.cover.kind") }
    }

    /// The swatch name in force, when the chosen cover is a color — nil for
    /// a photo or no cover. Drives the picker's selected state.
    var colorName: String? {
        didSet { UserDefaults.standard.set(colorName, forKey: "home.cover.colorName") }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "home.cover") {
            banner = UIImage(data: data)
        }
        kind = UserDefaults.standard.string(forKey: "home.cover.kind").flatMap(Kind.init)
        colorName = UserDefaults.standard.string(forKey: "home.cover.colorName")
    }

    /// Sets a curated color as the cover — a small solid-fill image, same
    /// storage/render path as a photo.
    func setColor(_ swatch: (name: String, hex: String)) {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let fill = UIColor(Color(hex: swatch.hex))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            fill.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        }
        colorName = swatch.name
        kind = .color
        banner = image
    }

    func setPhoto(_ image: UIImage) {
        colorName = nil
        kind = .photo
        banner = Self.prepared(image)
    }

    func clear() {
        banner = nil
    }

    /// Downscaled to cover render size — the renderer's scale is pinned to
    /// 1, so this is the real max pixel width (same guard as Avatar/theme).
    private static func prepared(_ image: UIImage, maxSide: CGFloat = 1200) -> UIImage {
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
