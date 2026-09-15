import SwiftUI

/// **THE CHOICE — a pill you tap to choose something (prd §746, 2026-09-15).**
///
/// The user's ruling: *"most people only need two: a pill you tap to choose
/// something, and a pill that just shows a fact."* This is the first of the
/// two. A scope, a window, a filter, a sort, a picker's current answer — a
/// thing with alternatives, and a selected state that says which one is on.
/// The second is `DSStamp`, which is never tappable.
///
/// **Everything else is a row.** A verb drawn as a capsule — Connect, Copy,
/// Make active, Listen, Ask about this — reads as generated the moment a
/// screen carries three of them, so a verb is `DSDoorRow` (it stands alone),
/// `DSCopyRow` (it copies), or the trailing word of the row it acts on
/// (`DSPushRowTrail`). There is deliberately no tint, no primary and no inert
/// style here: a filled blue chip was a button wearing a chip's name, and an
/// inert one was a fact wearing a control's.
///
/// Lived in `Shell/Composer.swift` until §715 moved it here.
struct Chip: View {
    let text: String
    var glyph: String? = nil
    /// A count after the word, quieter than it — a filter's census.
    var count: Int? = nil
    /// Which alternative is on. The fill is NEUTRAL (`fillStrong` over
    /// `fillFaint`), never tint: the vibenet room ruled that blue means
    /// urgency there (§715), and the range strip already selected this way,
    /// so the one choice in the app takes the selection both already used.
    var selected = false
    /// The target. 44 everywhere (§717), except a strip whose box is budgeted
    /// by someone else's layout — `DSRangeChips` inside a crown (§688) — which
    /// passes its own, never under the height the control it replaced had.
    var hit: CGFloat = DS.Hit.min

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let glyph {
                Image(systemName: glyph)
                    .dsGlyph(12, weight: selected ? .semibold : .regular)
                    .accessibilityHidden(true)
            }
            // A chip is a capsule — its label never breaks across lines
            // (2026-07-21: a squeezed row wrapped "Try with your key" into
            // "Try with / your key" inside a 28pt capsule).
            Text(text)
                .dsText(.label12)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
            if let count {
                Text(verbatim: "\(count)")
                    .dsText(.label12)
                    .monospacedDigit()
                    .opacity(0.7)
            }
        }
        .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: 28)
        .fixedSize(horizontal: true, vertical: false)
        .background(selected ? DS.fillStrong : DS.fillFaint, in: Capsule(style: .continuous))
        .animation(DS.Motion.standard, value: selected)
        // DRAWN 28, TARGETED `hit`. Every Chip is the label of a Button or a
        // Menu, so the floor and the Mac hover are folded in here rather than
        // decided at each call site.
        .dsTapTarget(Capsule(style: .continuous), size: hit)
        .dsHover()
    }
}

/// **THE WINDOW PICKER, ONCE (prd §686), as chips (prd §746).**
///
/// The 7d / 30d / Watched choice the crown and the Activity chart both offer.
/// It was a segmented box — a recessed track with a raised tile — which was a
/// third pill grammar for the same act a `Chip` already performs, so it is a
/// row of chips now and draws nothing of its own.
///
/// It draws NOTHING under two ranges, and that is the rule rather than the
/// caller's manners: a lone chip is a control with no alternative, which §83
/// calls a dead control.
struct DSRangeChips<Option: Hashable>: View {
    let ranges: [Option]
    let range: Option
    /// The chip's word. Generic since §715: the vibenet account's window
    /// strip picks a different type.
    let label: (Option) -> String
    let onPick: (Option) -> Void

    init(ranges: [Option], range: Option, label: @escaping (Option) -> String,
         onPick: @escaping (Option) -> Void) {
        self.ranges = ranges
        self.range = range
        self.label = label
        self.onPick = onPick
    }

    /// The crown budgets this strip at `DSRoomChassis.crownRangeChips` (42),
    /// so a 44pt floor would push its line out through the slot's clip. 32 is
    /// the height the segmented box it replaced was hit at, so no target in
    /// the app got smaller.
    private static var hit: CGFloat { 32 }

    var body: some View {
        if ranges.count > 1 {
            HStack(spacing: DS.Space.s2) {
                ForEach(ranges, id: \.self) { r in
                    Button {
                        guard r != range else { return }
                        DSHaptic.tap()
                        onPick(r)
                    } label: {
                        Chip(text: label(r), selected: r == range, hit: Self.hit)
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityAddTraits(r == range ? .isSelected : [])
                }
            }
        }
    }
}

extension DSRangeChips where Option == WalletRange {
    init(ranges: [WalletRange], range: WalletRange, onPick: @escaping (WalletRange) -> Void) {
        self.init(ranges: ranges, range: range, label: { $0.chipLabel }, onPick: onPick)
    }
}
