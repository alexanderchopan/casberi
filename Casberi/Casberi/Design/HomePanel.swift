import SwiftUI

/// **THE FEED RISES ON A PANEL (prd §1858).** On the phone's Home the wallet
/// stands on the page and what is new stands on a panel under it: a curved
/// top edge in a faint grey that fades to the page within a screen, so the
/// feed you scroll is the page's own black and only its edge says where it
/// begins.
///
/// The fade is one layer behind the List (a row's background cannot run past
/// its row). `HomePanelCap` is the List row at the panel's top: it reports
/// where it stands, and `HomePanelFade` draws there. Once the cap has
/// scrolled off and been recycled, the place is its last content position
/// less the scroll, so the grey still on screen keeps moving with the page.
@MainActor @Observable
final class HomePanelPlace {
    static let shared = HomePanelPlace()

    /// The cap's top in global space while its row is alive.
    var capY: CGFloat?
    /// The cap's top plus the scroll when its row last left.
    var leftAt: CGFloat?
    /// The List's content offset.
    var offset: CGFloat = 0

    /// Where the panel's top stands on screen now; nil before it is known.
    var y: CGFloat? { capY ?? leftAt.map { $0 - offset } }
}

enum HomePanelMetrics {
    static let radius: CGFloat = 30
    /// The air between the panel's edge and its first row.
    static let cap: CGFloat = 22
    /// How far the grey runs before it is the page.
    static let fade: CGFloat = 520
}

/// The row at the panel's top: air, and the report of where the panel is.
struct HomePanelCap: View {
    var body: some View {
        Color.clear
            .frame(height: HomePanelMetrics.cap)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                HomePanelPlace.shared.capY = y
            }
            .onDisappear {
                let place = HomePanelPlace.shared
                if let y = place.capY { place.leftAt = y + place.offset }
                place.capY = nil
            }
            .accessibilityHidden(true)
    }
}

/// The panel's fill, behind the List.
struct HomePanelFade: View {
    var body: some View {
        GeometryReader { geo in
            if let y = HomePanelPlace.shared.y {
                UnevenRoundedRectangle(topLeadingRadius: HomePanelMetrics.radius,
                                       topTrailingRadius: HomePanelMetrics.radius, style: .continuous)
                    .fill(LinearGradient(stops: [
                        .init(color: DS.fillFaint, location: 0),
                        .init(color: DS.fillFaint.opacity(0.55), location: 0.42),
                        .init(color: DS.fillFaint.opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(height: HomePanelMetrics.fade)
                    .offset(y: y - geo.frame(in: .global).minY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
