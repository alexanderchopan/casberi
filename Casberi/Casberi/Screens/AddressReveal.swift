import SwiftUI
import UIKit

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
    /// The address's own derived colour.
    ///
    /// This is now the ONLY place that colour appears on the sheet: the pour
    /// behind the header and the tint on the watch bar both went on
    /// 2026-08-22, and the ring stayed because it is not decoration in an app
    /// colour — it is the claim that this face was worked out from this
    /// address, drawn in the colour that claim produced.
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

/// THE HERO IS THE FACE THE ROW WAS WEARING (2026-08-27, prd §502).
///
/// The card opens as a sheet, and a sheet arrives as a new surface — so the
/// 96pt face at the top of it read as a picture this screen had, rather than
/// as the 36pt face you had your finger on a beat earlier. `AddressMark` draws
/// the same mark at both sizes off the same address, which is the claim §483
/// makes about these faces ("just different accounts of the same thing"), and
/// nothing on screen said it.
///
/// So the hero ENTERS AT `DS.Face.list` — the ramp tier the book row draws —
/// and grows to its own. Both ends are ramp tokens rather than numbers, for
/// `AddressFlightOverlay`'s stated reason one file over: a travelling or
/// growing face's ends are the sizes the face has really been, and
/// `face-ramp-audit` can only see that when they are named.
///
/// **What this deliberately is NOT: a flight from the row.** Three doors were
/// weighed and all three are shut. `.navigationTransition(.zoom)` is out —
/// prd §232 dropped it for sheets after a device-specific crash that never
/// reproduced here. `AddressFlightOverlay` cannot cross a presentation
/// boundary: its two anchors have to resolve in ONE preference space, which is
/// why §444's filing flight runs wholly inside the move sheet. And measuring
/// the hero's global frame to interpolate by hand gives a delta that is wrong
/// by however far the sheet still has to rise, since `onAppear` fires mid
/// presentation. A scale is the part of the claim that can be made honestly
/// from here; the travel is not, and a travel aimed at a stale frame is worse
/// than none.
///
/// Reduce Motion lands it at full size — the face is still the face.
private struct AddressHeroArrival: ViewModifier {
    /// The hero's own size, so the entering scale is a ratio of two ramp
    /// tiers rather than a literal.
    let size: CGFloat
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(grown ? 1 : DS.Face.list / size)
            .onAppear {
                guard !reduceMotion else { grown = true; return }
                // One turn later, for `AddressFlight`'s own reason: a value
                // written and animated in the same runloop turn is coalesced,
                // and the growth never happens.
                DispatchQueue.main.async {
                    withAnimation(.spring(duration: 0.5, bounce: 0.18)) { grown = true }
                }
            }
    }
}

/// WHAT THE COPY TOOK, SWEPT ONCE (2026-08-27, prd §502).
///
/// The address card's Copy tile fires a haptic and changes nothing on screen —
/// the one verb this sheet is most opened for, answering silently, while the
/// row's own `CopyAddressButton` has said "Copied" in place since it was
/// written. This is that answer, drawn on the thing that was copied rather
/// than on the control that copied it.
///
/// A shimmer masked by the content itself, in the ADDRESS's own hue: the same
/// colour the face is worked out from (§444), so the sweep says "this string,
/// this identity" rather than "an app event happened". One pass, then gone —
/// a repeating shimmer is a loading state, and nothing here is loading.
///
/// Reduce Motion draws nothing at all: the expansion beside it is the fact,
/// and this is the flourish.
private struct AddressCopySweep: ViewModifier {
    /// Bumped by the copy. Changing — not merely non-zero — is what runs it,
    /// so a second copy sweeps again.
    let token: Int
    let hue: Color
    @State private var phase: CGFloat = 0
    @State private var sweeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if sweeping {
                    GeometryReader { geo in
                        let band = max(60, geo.size.width * 0.4)
                        LinearGradient(colors: [hue.opacity(0), hue, hue.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (geo.size.width + band * 2))
                    }
                    // Masked by the very thing that was copied, so the light
                    // runs through the characters rather than over the row.
                    .mask(content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: token) { _, _ in
                guard !reduceMotion, token > 0 else { return }
                phase = 0
                sweeping = true
                withAnimation(.easeInOut(duration: 0.55)) { phase = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sweeping = false }
            }
    }
}

/// THE ADDRESS INTRODUCING ITSELF (2026-09-04, prd §599).
///
/// §597 taught this card to stand an auto name (`…44b1`, nobody's word) under
/// the name the ADDRESS claims — its verified primary on ENS, Wei or Gwei —
/// and drew the swap as a cross-fade. A cross-fade is what this app uses for a
/// value that CHANGED; nothing changed here. The app went and asked three
/// registries who this is, one of them answered, and the answer arrived while
/// you were looking at the screen.
///
/// So it is written in. A typewriter is the one motion that says a name was
/// received rather than recomputed, and it is honest in a way a flourish is
/// not: the characters appear in the order the string has them, and the string
/// is the whole of what arrived.
///
/// **It runs ONLY on an arrival, never on a rename.** The card's `.task` reads
/// what is already known before it asks, so a second visit draws the name on
/// the first frame and types nothing — which is right, because on that visit
/// nothing was learned. The caller passes `typeOn` for the one specific string
/// that landed, so a later rename to something else takes the ordinary swap;
/// a name you typed yourself being typed back at you is the app performing
/// your own act (§83's shape, in motion).
///
/// **The caret is what stops it reading as a glitch.** From the first frame
/// there is a mark on the line, so the name grows out of something rather than
/// out of a blank; it retires when the last character lands. It does NOT
/// blink — a repeating animation is a loading state, and nothing here is
/// loading (`AddressCopySweep`'s rule, one modifier up).
///
/// Reduce Motion draws the whole name immediately. VoiceOver always reads the
/// whole name: a prefix is a different name, and on this screen that matters
/// more than anywhere else in the app.
struct AddressArrivingName: View {
    let name: String
    let style: DSTextStyle
    /// True for the one string that just arrived from a resolve.
    let typeOn: Bool
    /// How long the whole name takes, however long it is. A per-character
    /// delay is right for `vitalik.eth` and a crawl for a long subdomain, so
    /// the STEP grows instead and the clock stays put.
    private static let span: Double = 0.42
    private static let tick: Double = 0.028
    @State private var typed: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var caretHeight: CGFloat {
        UIFontMetrics(forTextStyle: style.relative)
            .scaledValue(for: style.size * 0.86)
    }

    private var shown: String {
        guard let typed else { return name }
        return String(name.prefix(typed))
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(shown)
                .dsText(style)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
            if typed != nil {
                // Sized off the type ramp rather than a literal, and scaled
                // the way the ramp scales — so the caret is the height of the
                // name it is writing at either rung and at any Dynamic Type
                // setting. `DSTextStyle.scaledFont` does this arithmetic for
                // the glyphs; there is no way to ask it for a height, so the
                // same two lines are spelled here rather than a constant that
                // would be right at one text size only.
                Capsule()
                    .fill(DS.textTertiary)
                    .frame(width: 2, height: caretHeight)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .task(id: name) {
            guard typeOn, !reduceMotion else { typed = nil; return }
            let count = name.count
            guard count > 1 else { typed = nil; return }
            // Ticks are fixed and the step absorbs the length, so a
            // forty-character subdomain lands on the same clock as `a.wei`.
            let ticks = max(1, Int(Self.span / Self.tick))
            let step = max(1, Int(ceil(Double(count) / Double(ticks))))
            typed = 0
            var landed = 0
            while landed < count {
                try? await Task.sleep(for: .milliseconds(Int(Self.tick * 1000)))
                guard !Task.isCancelled else { break }
                landed = min(count, landed + step)
                typed = landed
            }
            withAnimation(DS.Motion.standard) { typed = nil }
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

    /// The card's hero entering at the size the row drew it — see
    /// `AddressHeroArrival`.
    func addressHeroArrival(size: CGFloat) -> some View {
        modifier(AddressHeroArrival(size: size))
    }

    /// One sweep through what a copy just took — see `AddressCopySweep`.
    func addressCopySweep(token: Int, hue: Color) -> some View {
        modifier(AddressCopySweep(token: token, hue: hue))
    }
}
