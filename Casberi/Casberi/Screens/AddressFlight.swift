import SwiftUI

/// THE STAR FLIGHT (2026-08-22, prd §441) — a wallet's face travelling from
/// its row in the book to its slot in the watched shelf.
///
/// **§212 already claimed this moment in prose and never built it.** It retired
/// the footer that explained the star, on the grounds that "tapping a star
/// visibly drops the wallet into the shelf at the top of the same screen, which
/// teaches it better than the sentence did" — and then the wallet simply
/// appeared. §433 added `connectPromote` (the row lifts) and a slot transition
/// (the shelf scales in), which are two animations that do not know about each
/// other: nothing crosses the gap, so nothing says the row and the slot are the
/// same wallet.
///
/// **Why an overlay rather than `matchedGeometryEffect`.** That modifier
/// animates one view between two positions when exactly one of them is the
/// source, and here BOTH views persist — starring an address does not remove
/// its row. Flipping `isSource` between two views that both stay on screen is
/// the shape that produces the famous ghost-and-snap. An explicit overlay is
/// two rectangles and an interpolation, and it does exactly what it says.
///
/// **The anchors come from the views themselves**, never from measured
/// constants: the row's position depends on the sort, the scroll offset and how
/// many groups are above it, and the slot's depends on how full the shelf is.
/// Any constant would be right on one book and wrong on every other.
///
/// Reduce Motion skips the flight entirely — the face still lands, it just
/// doesn't travel.

/// One face in the air.
struct FlightingFace: Equatable {
    /// The book entry's id — the key both anchors are published under.
    let id: String
    /// The address, for the face itself. Held rather than looked up, because
    /// the row it came from may re-sort out from under the flight.
    let address: String
}

/// Where a flight starts and ends. Both halves publish into one dictionary so
/// the overlay can read a pair without either view knowing the other exists.
struct AddressFlightAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        // FIRST wins. A book row and a shelf slot publish under different
        // prefixes so they cannot collide — but a row rendered twice during a
        // List recycle can, and taking the first keeps the flight aimed at the
        // one that was already on screen.
        value.merge(nextValue()) { existing, _ in existing }
    }
}

extension View {
    /// Publishes this view's frame as a flight endpoint.
    func flightAnchor(_ key: String) -> some View {
        anchorPreference(key: AddressFlightAnchors.self, value: .bounds) {
            [key: $0]
        }
    }
}

/// The travelling face, drawn over the whole screen.
///
/// Interpolates position AND size: a face leaves a 36pt row and arrives in a
/// 56pt slot, and a constant-size flight reads as a sticker sliding rather than
/// as the row becoming the slot.
struct AddressFlightOverlay: View {
    let flight: FlightingFace?
    let anchors: [String: Anchor<CGRect>]
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let flight,
               let from = anchors["row:" + flight.id],
               let to = anchors["slot:" + flight.id] {
                let a = proxy[from], b = proxy[to]
                // Eased on the CALLER's animation; this is a pure function of
                // `progress`, so the curve lives in one place.
                //
                // **The SIZE comes off the ramp, not off the anchors.** Those
                // rects are the mark's LAYOUT frame, which is the same number
                // today and stops being it the moment either mark gains a
                // border, a badge or a padding — and then the flight would
                // begin at a size the face has never actually been. The row
                // draws `DS.Face.list` and the slot draws `DS.Face.shelf`, so
                // those are the two ends; the anchors are asked only for WHERE,
                // which is the thing they alone can answer.
                let size = DS.Face.list + (DS.Face.shelf - DS.Face.list) * progress
                let x = a.midX + (b.midX - a.midX) * progress
                // A shallow ARC rather than a straight line. The two points are
                // nearly always in the same column (the shelf is at the top,
                // the row below it), so a straight interpolation is a vertical
                // slide — which reads as scrolling, not as travelling. The lift
                // is a fraction of the distance and peaks at halfway.
                let lift = min(64, abs(b.midY - a.midY) * 0.18)
                let arc = -sin(progress * .pi) * lift
                let y = a.midY + (b.midY - a.midY) * progress + arc
                WalletFace(address: flight.address, size: size, circular: true)
                    .frame(width: size, height: size)
                    .position(x: x, y: y)
                    // Fades out only at the very end, so the face is solid for
                    // the whole journey and the slot has already drawn
                    // underneath it by the time it goes.
                    .opacity(progress > 0.92 ? Double((1 - progress) / 0.08) : 1)
                    .allowsHitTesting(false)
                    // The flight is decoration over a change VoiceOver is
                    // already told about by the star's own label.
                    .accessibilityHidden(true)
            }
        }
    }
}
