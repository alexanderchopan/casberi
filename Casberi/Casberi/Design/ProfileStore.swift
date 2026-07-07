import SwiftUI
import Observation

/// The person's avatar — one image, owned locally (goal 6). When set, it
/// becomes the Account tab icon: the tab wears the person, not a glyph.
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    var avatar: UIImage? {
        didSet {
            if let data = avatar?.jpegData(compressionQuality: 0.85) {
                UserDefaults.standard.set(data, forKey: "profile.avatar")
            } else {
                UserDefaults.standard.removeObject(forKey: "profile.avatar")
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "profile.avatar") {
            avatar = UIImage(data: data)
        }
    }

    /// Downscales a picked image to tab/row size so storage stays small.
    /// Renderer scale pinned to 1 — the default device scale would multiply
    /// the bitmap back up.
    static func prepared(_ image: UIImage, maxSide: CGFloat = 240) -> UIImage {
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
