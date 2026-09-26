import SwiftUI

/// **ONE NUMBER, ONE CAPTION (prd §936).** Every wallet-family tile's reading.
///
/// The pass before this (§920–§929) gave each tile three lines — caption,
/// figure, sentence — and the sentence was doing the chart's job ("reach 2 of
/// your 5", "Yours · quiet ones nothing reaches"). The user's read of it:
/// *"sometimes i feel it looks vibecoded"*. Apple's Health and Stocks put one
/// number over one small caption and let the drawing say the rest, so that is
/// the grammar now: `number` at `price40`, `caption` at `body17`. `alarm` is
/// the one fact that needs you, appended in the alarm ink — never a second
/// colour for decoration.
///
/// Only the reading clears the gear (§920); the figure under it takes the
/// whole width.
struct DSFigureReading: View {
    let number: String
    let caption: String
    var alarm: String? = nil
    /// The number's ink — the change on a money line is the one place a
    /// number wears gain or loss (§936: red and green mean up and down).
    var numberInk: Color = DS.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A number takes `price40` (prd §766's rung for a number in a
            // lead); `stat24` beside a `body17` caption read as the same size.
            Text(number)
                .dsText(.price40)
                .foregroundStyle(numberInk)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // The caption at the move line's rung (`body17`, secondary), so
            // every tile's second line matches the Home crown's.
            // No caption draws no line (user, 2026-09-26: "$26K" alone —
            // the list under the crown says what it is made of).
            if !caption.isEmpty || !(alarm ?? "").isEmpty {
                captionText
                    .dsText(.body17)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var captionText: Text {
        let base = Text(caption).foregroundStyle(DS.textSecondary)
        guard let alarm, !alarm.isEmpty else { return base }
        return base + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
            + Text(alarm).foregroundStyle(DS.destructive)
    }
}

/// **THE BAR LIST (prd §936): the tiles' one drawing for "how many of each".**
///
/// Accounts drew ribbons, Permissions drew keys, Frames drew a flow and the
/// Privacy devnet a ring — four inventions for the same question. They are
/// all ranked horizontal bars now: a label and its value on one line, the bar
/// under it in the one accent, and the alarm ink only on a bar that needs you.
/// A row is a 44pt door (`DS.Hit.min`); a press lights one bar and quiets the
/// rest, and the tile's reading names the lit one.
struct DSBarList: View {
    struct Bar: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
        /// 0…1 of the longest bar; clamped, and never drawn thinner than a dot.
        let share: Double
        var alarm = false
    }

    let bars: [Bar]
    var lit: String? = nil
    /// Four rows and the "+N more" line fit under a reading in the fixed box
    /// (`visualSlot` 300 − a ~72pt reading − 8 = 220; 4 × 44 + 16 = 192).
    var shown = 4
    var onPress: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let thickness: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bars.prefix(shown).enumerated()), id: \.element.id) { index, bar in
                row(bar)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            if bars.count > shown {
                Text(String(localized: "+\(String(bars.count - shown)) more"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: lit)
    }

    @ViewBuilder
    private func row(_ bar: Bar) -> some View {
        let content = VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(bar.label)
                    .foregroundStyle(lit == bar.id ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(bar.value)
                    .foregroundStyle(bar.alarm ? DS.destructive : DS.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .dsText(.label12)
            GeometryReader { geo in
                Capsule()
                    .fill(bar.alarm ? DS.destructive : DS.tint)
                    .frame(width: max(Self.thickness,
                                      geo.size.width * CGFloat(min(max(bar.share, 0), 1))))
            }
            .frame(height: Self.thickness)
        }
        .opacity(lit != nil && lit != bar.id ? 0.35 : 1)
        .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .center)
        .contentShape(Rectangle())

        if let onPress {
            Button {
                DSHaptic.selection()
                onPress(bar.id)
            } label: { content }
            .buttonStyle(PressSpring())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(lit == bar.id ? .isSelected : [])
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// A reading over a bar list, top-aligned in the scope's fixed box. It
/// measured and reported its own height for one build (prd §936) so the box
/// could shrink to it; the tiles under the box moved with it, so the box is
/// fixed again and this only stacks the two.
struct DSBarFigure<Reading: View>: View {
    @ViewBuilder let reading: () -> Reading
    let bars: DSBarList

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            reading()
            // **CENTRED IN WHAT IS LEFT (user: "can't we center them so they
            // look good if they have limited info?").** The box is fixed
            // (prd §936), so one or two bars sit in the middle of the space
            // under the number rather than hugging it with air below; a full
            // list fills the space either way.
            bars
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
