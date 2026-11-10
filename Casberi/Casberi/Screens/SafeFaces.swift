import SwiftUI

/// A Safe's owners as faces: yours in the pick's ink with what
/// it is (this iPhone, the recovery key, the co-signer), the others by the
/// first letter of their name (prd §1614).
struct SafeFaces: View {
    let faces: [SafeRoster.Face]
    private let size: CGFloat = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(faces.prefix(SafeRoster.faceCap).enumerated()), id: \.offset) { _, face in
                disc(face)
            }
            if faces.count > SafeRoster.faceCap {
                disc(.person("+\(faces.count - SafeRoster.faceCap)"))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func disc(_ face: SafeRoster.Face) -> some View {
        ZStack {
            Circle().fill(face.isYours ? DS.pickInk : DS.fillStrong)
            switch face {
            case .phone: glyph("iphone")
            case .recovery: glyph("key.fill")
            case .coSigner: glyph("person.badge.key.fill")
            case .you: glyph("person.fill")
            case .person(let initial):
                if initial.isEmpty {
                    glyph("person.fill")
                } else {
                    Text(verbatim: initial)
                        .dsText(.label12)
                        .foregroundStyle(DS.textPrimary)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .dsGlyph(.caption)
            .foregroundStyle(Color.white)
    }
}
