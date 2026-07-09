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

    var banner: UIImage? {
        didSet {
            if let data = banner?.jpegData(compressionQuality: 0.85) {
                UserDefaults.standard.set(data, forKey: "home.cover")
            } else {
                UserDefaults.standard.removeObject(forKey: "home.cover")
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "home.cover") {
            banner = UIImage(data: data)
        }
    }

    /// Downscaled to cover render size — the renderer's scale is pinned to
    /// 1, so this is the real max pixel width (same guard as Avatar/theme).
    static func prepared(_ image: UIImage, maxSide: CGFloat = 1200) -> UIImage {
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
