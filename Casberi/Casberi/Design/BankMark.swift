import SwiftUI

/// A bank's own icon where SimpleFIN reads one (prd §1663), else SimpleFIN's
/// mark. The icon is read in a `.task`, never the body; a transparent icon
/// stands on white, as it does in the bank's own browser tab.
struct BankMark: View {
    let connID: String?
    var size: CGFloat = 44
    var circular: Bool = false

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(circular ? AnyShape(Circle())
                               : AnyShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)))
            } else {
                BridgeIcon(name: SimpleFINShape.source, size: size, circular: circular)
            }
        }
        .task(id: connID) { image = connID.flatMap(SimpleFINLogos.image) }
        .onReceive(NotificationCenter.default.publisher(for: SimpleFINLogos.arrived)) { note in
            guard let connID, note.object as? String == connID else { return }
            image = SimpleFINLogos.image(connID: connID)
        }
    }
}
