import SwiftUI

/// The micro-motion kit (2026-07-08) — small, reusable feedback moves for the
/// moments that lacked one: a button arming, an error landing, proof counting
/// up, rows arriving. All ride DS.Motion or short springs; none loops forever
/// except the starter-preview breathe, which is the one "waiting" tell.

// MARK: - Settle-in (a header/icon arrives: 0.92 → 1 + fade)

struct SettleIn: ViewModifier {
    var delay: Double = 0
    @State private var on = false
    /// Added 2026-08-04 (prd §298): this shipped WITHOUT a Reduce Motion guard
    /// and reaches 40 call sites through `settleIn`/`staggerIn` — including
    /// every feed row and the topic map's cells — so the one preference the
    /// whole motion system is supposed to respect was being ignored by the
    /// app's most-used entrance. Every other modifier in this file already had
    /// it; this was the gap, found while auditing `ChartEntrance` against it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1 : 0.92)
            .opacity(on ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(DS.Motion.standard.delay(delay)) { on = true }
            }
    }
}

extension View {
    /// Scale-settle + fade on first appearance — an arrival, not a pop.
    func settleIn(delay: Double = 0) -> some View { modifier(SettleIn(delay: delay)) }
}

// MARK: - Armed pop (a disabled control comes alive: one small spring)

private struct ArmedPop: ViewModifier {
    let armed: Bool
    @State private var up = false
    /// Added 2026-08-21, when this went from two call sites to six: the pop is
    /// a value-change animation, which `design-motion-audit`'s check 1
    /// deliberately does not police (it scopes to entrances) — so the guard was
    /// missing here and nothing could have said so. The disabled→live FILL
    /// swap is what carries the meaning; the spring is the flourish on top, and
    /// it is the flourish this preference exists to drop.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.08 : 1)
            .onChange(of: armed) { _, now in
                guard now, !reduceMotion else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { up = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { up = false }
                }
            }
    }
}

extension View {
    /// One small spring the moment `armed` flips true — the button waking up
    /// as the field gains its first character.
    func armedPop(_ armed: Bool) -> some View { modifier(ArmedPop(armed: armed)) }
}

// MARK: - Error shake (three quick horizontal knocks; failure you can feel)

private struct Shake: GeometryEffect {
    var travel: CGFloat = 6
    var knocks: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * knocks * 2), y: 0))
    }
}

private struct ShakeOn: ViewModifier {
    /// Increment to shake; each new value plays one shake.
    let trigger: Int
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(Shake(animatableData: phase))
            .onChange(of: trigger) {
                phase = 0
                withAnimation(.linear(duration: 0.4)) { phase = 1 }
            }
    }
}

extension View {
    func shake(on trigger: Int) -> some View { modifier(ShakeOn(trigger: trigger)) }
}

// MARK: - Pulse on change (a status dot blinks once when its fact updates)

private struct PulseOnChange<V: Equatable>: ViewModifier {
    let value: V
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.5 : 1)
            .onChange(of: value) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { up = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { up = false }
                }
            }
    }
}

extension View {
    /// One soft scale pulse whenever `value` changes — ambient "just updated".
    func pulseOnChange<V: Equatable>(of value: V) -> some View {
        modifier(PulseOnChange(value: value))
    }
}

// MARK: - Count-up proof line ("3 games in" earns its number)

/// Renders a status line whose LEADING integer counts up from zero with the
/// numeric-text roll. Lines without a leading number render plain.
struct CountUpText: View {
    let text: String
    @State private var shown = 0
    /// Reduce Motion lands the final number immediately (2026-08-04, prd §299)
    /// — the count-up is the animation here, so honouring the preference means
    /// showing the answer, not counting faster.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The in-flight roll — a new text cancels it so two rolls never
    /// interleave writes to `shown` (review 2026-07-08).
    @State private var roller: Task<Void, Never>?

    private var parts: (n: Int, rest: String)? {
        let digits = text.prefix { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits), n > 1 else { return nil }
        return (n, String(text.dropFirst(digits.count)))
    }

    var body: some View {
        if let parts {
            Text("\(shown)\(parts.rest)")
                .contentTransition(.numericText(value: Double(shown)))
                .onAppear { roll(to: parts.n) }
                .onChange(of: text) { if let p = self.parts { roll(to: p.n) } }
        } else {
            Text(text)
        }
    }

    /// Rolls 0 → n in a few visible steps inside ~0.5s. A fresh roll cancels
    /// the previous one; a cancelled roll never writes again.
    private func roll(to n: Int) {
        roller?.cancel()
        guard !reduceMotion else { shown = n; return }
        shown = 0
        roller = Task { @MainActor in
            let steps = min(n, 6)
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(500 / UInt64(steps)))
                guard !Task.isCancelled else { return }
                withAnimation(DS.Motion.standard) { shown = n * i / steps }
            }
        }
    }
}

// MARK: - Swipe hint nudge (teaches the swipe-to-pin gesture, once ever)

/// The one swipe lesson, shared by every list that pins via a trailing swipe
/// (Feed, Wallet, Tokens' watchlist, 2026-07-11): the first row nudges
/// left once, a pin peeks from the trailing edge, the row settles back, then
/// `onDone` retires it — for good, everywhere, since callers key `active` off
/// the same "coach.swipe.done" flag. One gesture, one lesson, taught once no
/// matter which screen a person meets it on first.
struct SwipeHintNudge: ViewModifier {
    let active: Bool
    var onDone: () -> Void
    @State private var nudge: CGFloat = 0
    /// Under Reduce Motion the lesson is RETIRED rather than played still
    /// (2026-08-04, prd §299). The whole teaching device is the movement — a
    /// nudge that doesn't move teaches nothing, and holding the row hostage for
    /// 2.6 seconds to teach nothing is worse than skipping it. `onDone` fires
    /// immediately so the flag is set and no list waits on it again.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: nudge)
            .background(alignment: .trailing) {
                if active {
                    Image(systemName: "pin.fill")
                        .dsGlyph(14)
                        .foregroundStyle(DS.tint)
                        .opacity(nudge < -8 ? Double(min(1, -nudge / 48)) : 0)
                }
            }
            .onAppear {
                guard active else { return }
                guard !reduceMotion else { onDone(); return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1400))
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) { nudge = -56 }
                    try? await Task.sleep(for: .milliseconds(800))
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { nudge = 0 }
                    try? await Task.sleep(for: .milliseconds(400))
                    onDone()
                }
            }
    }
}

// MARK: - Connect bloom (an app's hue floods a store surface as a connect lands)

/// The connect payoff, shared by the Apps store and the product page so the
/// beat can't drift between them. Bump `token` to fire; the modifier commits
/// full opacity in ONE frame, then eases it out. (A `pulse = 1` immediately
/// followed by `withAnimation { pulse = 0 }` in the same synchronous call
/// coalesces — SwiftUI never renders the 1, so nothing blooms. The commit must
/// land a frame before the ease-out, which the follow-up hop guarantees.)
struct ConnectBloom: ViewModifier {
    /// The app's identity hue (a hueless app passes the tint).
    let hue: Color
    /// Bump to play one bloom.
    let token: Int
    @State private var pulse: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if pulse > 0.001 {
                    LinearGradient(colors: [hue.opacity(0.5), hue.opacity(0.12), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .opacity(pulse)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: token) {
                guard token > 0 else { return }
                pulse = 1
                if reduceMotion { pulse = 0; return }
                // A follow-up main-actor hop so the `= 1` renders before the
                // ease-out reads from it (see the note above).
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.75)) { pulse = 0 }
                }
            }
    }
}

extension View {
    /// The connect-payoff bloom — the app's hue washing over the surface as a
    /// connection lands, then receding. `token` is a counter you bump on success.
    func connectBloom(hue: Color, token: Int) -> some View {
        modifier(ConnectBloom(hue: hue, token: token))
    }
}

// MARK: - Land flash (a jump lands on a section: its header glows once)

/// A one-shot highlight the moment a jump lands on a shelf — the header's tint
/// glows up behind the words, then fades. A temporary fill, not a line (no
/// hairlines); nothing when idle. Off under Reduce Motion. Overlapping lands
/// cancel the prior clear so a second tap can't blink the glow off early.
struct LandFlash: ViewModifier {
    let trigger: Int
    /// The glow's hue — a jump lands in the neutral tint; a shelf COMPLETING
    /// lands in its own category color, so the payoff wears the set's identity.
    var tint: Color = DS.tint
    @State private var on = false
    @State private var clear: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(tint.opacity(on ? 0.14 : 0))
                    .padding(.horizontal, DS.Space.s2)
                    .padding(.vertical, -DS.Space.s1)
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) {
                guard !reduceMotion, trigger > 0 else { return }
                clear?.cancel()
                withAnimation(.easeOut(duration: 0.2)) { on = true }
                clear = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.5)) { on = false }
                }
            }
    }
}

extension View {
    /// One glow behind this view each time `trigger` bumps — a jump's arrival,
    /// so a scroll-to doesn't land in silence. `tint` colors the glow (a shelf
    /// completing glows in its own category color).
    func landFlash(_ trigger: Int, tint: Color = DS.tint) -> some View {
        modifier(LandFlash(trigger: trigger, tint: tint))
    }
}

// MARK: - Connect promote (a just-connected row lifts as it takes its seat)

/// The pin-lift beat (§polish §11), reused for a store connect: the row that
/// just connected scales up a touch and casts a soft shadow while it glides to
/// its connected seat in the shelf, so the state change reads as a promotion
/// rather than a silent re-sort. One shot per `token` bump, and only on the row
/// whose name matches — the whole shelf shares one token, so the match gates
/// it. Off under Reduce Motion (the re-sort still happens, just without the
/// lift). `isTarget` is re-read at fire time, so a token bumped for another row
/// never lifts this one.
struct ConnectPromote: ViewModifier {
    let isTarget: Bool
    let token: Int
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.03 : 1)
            .shadow(color: DS.tint.opacity(up ? 0.28 : 0),
                    radius: up ? 12 : 0, y: up ? 4 : 0)
            .onChange(of: token) {
                guard !reduceMotion, token > 0, isTarget else { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.6)) { up = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { up = false }
                }
            }
    }
}

extension View {
    /// A scale-and-shadow promote the moment `token` bumps for this row — the
    /// just-connected app taking its connected seat, felt as a lift.
    func connectPromote(isTarget: Bool, token: Int) -> some View {
        modifier(ConnectPromote(isTarget: isTarget, token: token))
    }
}

// MARK: - Staggered arrival (list rows land one after another)

extension View {
    /// The feed's entrance grammar for any list: fade-up with a per-index
    /// delay, playing once on appearance.
    func staggerIn(index: Int, step: Double = 0.04) -> some View {
        settleIn(delay: Double(index) * step)
    }
}

// MARK: - Breathing (the working state — alive, not spinning)

/// The mark breathes while the librarian works: a slow scale-and-dim loop,
/// the preview map's "waiting to fill" grammar reused for "thinking". The
/// only other looping motion in the app, and like the first it exists only
/// while something real is in flight. Still under Reduce Motion.
private struct Breathe: ViewModifier {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (up ? 1.08 : 0.94))
            .opacity(reduceMotion ? 1 : (up ? 1 : 0.7))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

extension View {
    func breathing() -> some View { modifier(Breathe()) }
}

// MARK: - Symbol swap (a glyph that changes MORPHS into the new one)

/// The swap feel for an `Image(systemName:)` whose symbol is chosen by a
/// ternary — a copy button becoming a checkmark, a magnifier becoming an ✕, a
/// play becoming a pause (2026-08-21).
///
/// **Why this is a modifier and not fifteen hand-spelled ternaries.** The app
/// had exactly ONE symbol that morphed — `AccountScreen`'s Theme sun↔moon,
/// which spells `contentTransition(reduceMotion ? .identity : …)` inline — and
/// fourteen more that HARD-CUT: the glyph is one thing on one frame and a
/// different thing on the next, which reads as a redraw rather than as the
/// control answering you. SF Symbols has had the morph since iOS 17 and it
/// costs nothing (the render server interpolates it), so the only reason the
/// other fourteen didn't have it was that nobody had a word for it.
///
/// **The `.animation` is load-bearing, not decoration.** `contentTransition`
/// plays only when the change that drives it is itself animated, and these
/// flags are almost all flipped from a plain button action with no
/// `withAnimation` around them — so the transition alone would be a modifier
/// that does nothing, which is worse than not adding it. Binding the animation
/// to the SAME value is what guarantees the morph actually runs.
///
/// Reduce Motion takes `.identity` (an instant swap, which is the honest
/// answer — the glyph still changes, it just doesn't travel) and drops the
/// animation with it, so nothing is left half-honouring the preference.
private struct SymbolSwap<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .animation(reduceMotion ? nil : DS.Motion.standard, value: value)
    }
}

extension View {
    /// One glyph morphing into the next whenever `value` changes — for an
    /// `Image(systemName:)` picked by a ternary off that same value.
    func dsSymbolSwap<V: Equatable>(_ value: V) -> some View {
        modifier(SymbolSwap(value: value))
    }
}
