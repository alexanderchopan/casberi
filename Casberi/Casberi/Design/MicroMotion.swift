import SwiftUI

/// The micro-motion kit (2026-07-08) — small, reusable feedback moves for the
/// moments that lacked one: a button arming, an error landing, proof counting
/// up, rows arriving. All ride DS.Motion or short springs; none loops forever
/// except the starter-preview breathe, which is the one "waiting" tell.

// MARK: - Settle-in (a header/icon arrives: 0.92 → 1 + fade)

struct SettleIn: ViewModifier {
    var delay: Double = 0
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1 : 0.92)
            .opacity(on ? 1 : 0)
            .onAppear {
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

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.08 : 1)
            .onChange(of: armed) { _, now in
                guard now else { return }
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
/// (Feed, Wallet, Dexscreener's watchlist, 2026-07-11): the first row nudges
/// left once, a pin peeks from the trailing edge, the row settles back, then
/// `onDone` retires it — for good, everywhere, since callers key `active` off
/// the same "coach.swipe.done" flag. One gesture, one lesson, taught once no
/// matter which screen a person meets it on first.
struct SwipeHintNudge: ViewModifier {
    let active: Bool
    var onDone: () -> Void
    @State private var nudge: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: nudge)
            .background(alignment: .trailing) {
                if active {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.tint)
                        .opacity(nudge < -8 ? Double(min(1, -nudge / 48)) : 0)
                }
            }
            .onAppear {
                guard active else { return }
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

// MARK: - Staggered arrival (list rows land one after another)

extension View {
    /// The feed's entrance grammar for any list: fade-up with a per-index
    /// delay, playing once on appearance.
    func staggerIn(index: Int, step: Double = 0.04) -> some View {
        settleIn(delay: Double(index) * step)
    }
}
