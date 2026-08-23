import SwiftUI

/// THE FACE IS MADE OF THE ADDRESS (2026-08-22, prd §444).
///
/// The address card's whole argument is that an identicon is a cheaper way to
/// recognise an address than reading forty-two characters — `AddressMark`'s own
/// header has said "a wallet is a WHO" since §169, and `WalletFace.tint` derives
/// the card's entire colour from the address's bytes. The card stated that in
/// prose and drew it as a static picture with a string underneath, so the one
/// relationship worth teaching — this face IS these characters — was never once
/// shown happening.
///
/// Two modifiers, one moment. The face settles while a ring in its own derived
/// hue sweeps once around it; then the address fills in FROM ITS ENDS. The
/// direction is the point and not a flourish: `WalletStore.shortAddress`
/// truncates to the last four characters, so the ends are the part you have
/// always been shown and the middle is the part every wallet app hides — which
/// is exactly the part `lookalikeBand` exists to make you look at. The reveal
/// arrives in that order, so the screen's argument and its motion say the same
/// thing.
///
/// **Two clocks, deliberately, and it is not the double-deal.** Each modifier
/// owns its own state, which is what `settleIn` does at forty call sites here.
/// The objection `FlowFigure`/`DemoNFTArt` are exempted for is INDEPENDENT
/// clocks on a strip that arrives as one object; these two are one element
/// each, started in the same frame, on durations chosen to hand off. A shared
/// clock threaded through the header would have to cross the name and the kind
/// line to reach the chip, and the audit cannot follow a value across a struct
/// boundary — so it would cost an exemption to buy nothing.
///
/// Reduce Motion lands both immediately: the face is still the face and the
/// address is still whole, they simply do not travel.

/// The identicon settling, with one ring drawn round it in its own hue.
private struct AddressFaceReveal: ViewModifier {
    /// The address's own derived colour — the same one the pour behind the
    /// header and the watch bar at the foot both wear, so the ring is not a
    /// decoration in an app colour but this address's colour, once more.
    let hue: Color
    /// Whether the mark under this is a FACE. Machinery gets the settle and no
    /// ring, for two reasons that agree: `AddressMark` draws a contract and a
    /// Safe as a rounded SQUARE, and a circle inset far enough to sit outside
    /// a 76pt square's EDGES is nowhere near outside its corners — so the
    /// sweep would draw straight through all four of them. And the ring's
    /// whole meaning is "this face was worked out from this address", which is
    /// a claim about an identicon; machinery has none.
    let isFace: Bool
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(settled ? 1 : 0.88)
            .overlay {
                // A SWEEP rather than an expanding halo. A halo is a landing —
                // it says "this arrived"; a dial closing says "this was worked
                // out", which is what actually happened.
                if isFace {
                    Circle()
                        .trim(from: 0, to: settled ? 1 : 0)
                        .stroke(hue.opacity(settled ? 0 : 0.85),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        // From twelve o'clock: a dial that starts at three reads
                        // as a progress bar somebody wrapped.
                        .rotationEffect(.degrees(-90))
                        // Outside the face, never on it — an identicon is the
                        // information and a stroke across its edge changes it.
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { settled = true; return }
                withAnimation(.spring(duration: 0.52, bounce: 0.2)) { settled = true }
            }
    }
}

/// An address filling in from the ends inward — the part a short form shows,
/// then the part it hides.
private struct AddressEndsFirst: ViewModifier {
    /// How much of each end is already lit before the reveal runs. Not zero:
    /// starting from nothing makes this a generic fade-in, and the whole
    /// reading is that the ENDS were never the secret.
    private static let ends: CGFloat = 0.16
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { geo in
                    let end = geo.size.width * (open ? 0.5 : Self.ends)
                    HStack(spacing: 0) {
                        Rectangle().frame(width: end)
                        Spacer(minLength: 0)
                        Rectangle().frame(width: end)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .onAppear {
                guard !reduceMotion else { open = true; return }
                // Delayed to hand off from the ring rather than run beside it:
                // two things moving at once in a 76pt-tall header reads as the
                // screen loading, not as one thing being worked out.
                withAnimation(.easeOut(duration: 0.42).delay(0.22)) { open = true }
            }
    }
}

/// One chunk of a wrapped address arriving — the ends first, the middle after.
///
/// `AddressEndsFirst` above does this with a mask, which is right for ONE line
/// of text and wrong for a wrapping block: a horizontal mask uncovers the left
/// and right of each LINE, so over two lines it reveals the middle of the
/// address first and hides the ends — the exact inversion of the reading. Here
/// the order is expressed as a delay per chunk instead, off
/// `AddressSpine.revealRank`, so it holds at any width and any number of lines.
///
/// Rank 0 (the two ends) is ALREADY THERE when the view appears rather than
/// fading in from nothing: starting from zero makes this a generic fade, and
/// the whole reading is that the ends were never the secret.
private struct AddressChunkReveal: ViewModifier {
    let index: Int
    let count: Int
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rank: Int { AddressSpine.revealRank(index: index, count: count) }

    func body(content: Content) -> some View {
        content
            .opacity(open || rank == 0 ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { open = true; return }
                // Handed off from the face's ring on the same clock
                // `AddressEndsFirst` used, so the header still reads as one
                // moment rather than two.
                withAnimation(.easeOut(duration: 0.2)
                    .delay(0.22 + Double(rank) * 0.045)) { open = true }
            }
    }
}

extension View {
    /// The identicon settling with one ring in the address's own hue. A
    /// non-face mark (a contract, a Safe) settles without the ring — see
    /// `AddressFaceReveal.isFace`.
    func addressFaceReveal(hue: Color, isFace: Bool) -> some View {
        modifier(AddressFaceReveal(hue: hue, isFace: isFace))
    }

    /// The address filling in from its ends — see `AddressEndsFirst`.
    func addressEndsFirst() -> some View { modifier(AddressEndsFirst()) }

    /// One chunk of a WRAPPED address arriving in ends-first order — see
    /// `AddressChunkReveal`.
    func addressChunkReveal(index: Int, count: Int) -> some View {
        modifier(AddressChunkReveal(index: index, count: count))
    }
}
