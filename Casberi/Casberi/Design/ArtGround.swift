import SwiftUI

/// A cover's colour for a sheet's ground (prd §1650): the song's and the
/// episode's sheets stand on it, as Apple Music's album page does.
@MainActor
enum ArtGround {
    /// The art's average, deep enough that white words stand on it at 4.5:1
    /// or better: the hue kept, the saturation capped, the brightness fixed
    /// low. A colourless cover (a grey average) gives nil and the ink stays.
    static func color(from image: UIImage) -> Color? {
        guard let average = RemoteImageLoader.averageColor(of: image) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard average.getHue(&h, saturation: &s, brightness: &b, alpha: &a), s > 0.08 else { return nil }
        return Color(UIColor(hue: h, saturation: min(s, 0.62), brightness: 0.3, alpha: 1))
    }
}

/// A sheet on its cover's colour: the ground behind everything, dark words
/// on it in either theme, cleared when the sheet walks to another thing.
struct ArtGroundStage<ID: Equatable>: ViewModifier {
    @Binding var ground: Color?
    let id: ID

    func body(content: Content) -> some View {
        content
            .background { (ground ?? .clear).ignoresSafeArea() }
            .transformEnvironment(\.colorScheme) { if ground != nil { $0 = .dark } }
            .onChange(of: id) { _, _ in ground = nil }
    }
}

extension View {
    func artGround<ID: Equatable>(_ ground: Binding<Color?>, resetOn id: ID) -> some View {
        modifier(ArtGroundStage(ground: ground, id: id))
    }
}
