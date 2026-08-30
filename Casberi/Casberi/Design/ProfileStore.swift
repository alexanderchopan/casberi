import SwiftUI
import Observation

/// The person's avatar and the name to call them by — owned locally (goal 6).
/// When set, the photo becomes the Account tab icon: the tab wears the person,
/// not a glyph.
///
/// **Both stay on this device and nothing else ever reads them.** Neither lands
/// as a `Thing`, so neither syncs through CloudKit, reaches a provider's context
/// window, or joins the Spotlight donation. That is the 2026-07-10 ruling this
/// screen already carries — personalization paints your SPACE, it never builds a
/// profile of you — which is exactly why the name is one string in UserDefaults
/// and not a field on any model.
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    /// What the app calls you — the greeting's own second half ("Good
    /// afternoon, Alex"). Nil means the greeting stands alone, which is the
    /// default and a complete sentence on its own; nothing anywhere reads this
    /// as a required field.
    var name: String? {
        didSet {
            if let name { UserDefaults.standard.set(name, forKey: "profile.name") }
            else { UserDefaults.standard.removeObject(forKey: "profile.name") }
        }
    }

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
        name = ProfileStore.preparedName(
            UserDefaults.standard.string(forKey: "profile.name") ?? "")
    }

    /// The longest name the masthead can carry before it starts eating the date
    /// beside it. A clamp at WRITE time rather than at draw time, so what the
    /// Settings row shows and what the greeting says can never disagree.
    static let nameLimit = 24

    /// Trims a typed name to something greetable — whitespace off, empty read
    /// as "no name" rather than as an empty greeting, clamped to `nameLimit`.
    /// The image path's `prepared(_:)` in the same shape: the store holds what
    /// it is handed, the caller hands it something already fit to hold.
    static func preparedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(nameLimit))
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
