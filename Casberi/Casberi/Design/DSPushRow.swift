import SwiftUI

/// **THE PUSH ROW — a row that takes you somewhere, drawn once (prd §715,
/// 2026-09-13).**
///
/// `DSDoorRow` is the SHEET door (an 18pt icon column, no chevron). The row
/// with a chevron had no owner, so it was drawn by hand twenty-odd times at
/// seven glyph sizes (9, 10, 11, 12, 13, 14 and a text rung) on rows a person
/// moves between in two taps. This is the one anatomy: an optional leading
/// mark, a title, an optional quiet line under it, an optional trailing fact,
/// and `DSChevron`.
///
/// It draws NO padding and NO background — a List row, a room card and a
/// sheet each own their own insets, and a template that guessed would be
/// overridden at every call site.
///
/// Titles are `Text`, never `String`, so a literal stays localizable and a
/// runtime string stays verbatim — the choice `DSSpecRow` made.
struct DSPushRowLabel<Leading: View>: View {
    let title: Text
    var subtitle: Text? = nil
    var fact: Text? = nil
    /// The fact's ink — tertiary for a fact, the verb's own ink when the
    /// fact IS the row's verb (prd §746).
    var factTone: Color = DS.textTertiary
    var subtitleTone: Color = DS.textTertiary
    /// `heading17` instead of `body17` — the room-card door, which is the
    /// one act on its card.
    var prominent = false
    var tint: Color = DS.textPrimary
    /// A spinner stands where the chevron would.
    var busy = false
    /// `false` draws no chevron: the row is a fact, not a door (honesty rule —
    /// a chevron promises more behind the tap).
    var opens = true
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                title
                    .dsText(prominent ? .heading17 : .body17)
                    .foregroundStyle(tint)
                    .lineLimit(2)
                if let subtitle {
                    subtitle
                        .dsText(.subhead12)
                        .foregroundStyle(subtitleTone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: DS.Space.s2)
            DSPushRowTrail(fact: fact, factTone: factTone, busy: busy, opens: opens)
        }
        .contentShape(Rectangle())
    }
}

extension DSPushRowLabel where Leading == EmptyView {
    init(title: Text, subtitle: Text? = nil, fact: Text? = nil,
         factTone: Color = DS.textTertiary,
         subtitleTone: Color = DS.textTertiary, prominent: Bool = false,
         tint: Color = DS.textPrimary, busy: Bool = false, opens: Bool = true) {
        self.init(title: title, subtitle: subtitle, fact: fact, factTone: factTone,
                  subtitleTone: subtitleTone, prominent: prominent, tint: tint,
                  busy: busy, opens: opens) { EmptyView() }
    }
}

/// **The trailing end of a row: its fact, then the chevron (or a spinner).**
///
/// Public since prd §746, so a row with its own leading anatomy (the
/// catalogue's app row, a vibenet sub-account) ends exactly the way every push
/// row does. `init(verb:)` is where a verb that used to be a capsule lands:
/// the word in its own ink, then the chevron when it goes somewhere.
struct DSPushRowTrail: View {
    var fact: Text? = nil
    var factTone: Color = DS.textTertiary
    var busy = false
    var opens = true
    /// A mark in place of the chevron, for a row whose destination is worth
    /// naming — `arrow.up.right` for a door out of the app (prd §449's
    /// "am I leaving?"). Drawn in the fact's ink.
    var glyph: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if let fact {
                fact
                    .dsText(.subhead12)
                    .foregroundStyle(factTone)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if busy {
                DSSpinner()
            } else if let glyph {
                Image(systemName: glyph)
                    .dsGlyph(.caption)
                    .foregroundStyle(factTone)
                    .accessibilityHidden(true)
            } else if opens {
                DSChevron()
            }
        }
    }
}

extension DSPushRowTrail {
    init(verb: RowVerb, busy: Bool = false) {
        self.init(fact: Text(LocalizedStringKey(verb.label)), factTone: verb.ink,
                  busy: busy, opens: verb.opens)
    }
}

/// `DSPushRowLabel` as a `Button`: whole-width target, a tap haptic, hover.
/// A `NavigationLink` site uses the label directly.
struct DSPushRow<Leading: View>: View {
    let title: Text
    var subtitle: Text? = nil
    var fact: Text? = nil
    var factTone: Color = DS.textTertiary
    var subtitleTone: Color = DS.textTertiary
    var prominent = false
    var tint: Color = DS.textPrimary
    var busy = false
    var opens = true
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading

    init(title: Text, subtitle: Text? = nil, fact: Text? = nil,
         factTone: Color = DS.textTertiary,
         subtitleTone: Color = DS.textTertiary, prominent: Bool = false,
         tint: Color = DS.textPrimary, busy: Bool = false, opens: Bool = true,
         action: @escaping () -> Void, @ViewBuilder leading: @escaping () -> Leading) {
        self.title = title
        self.subtitle = subtitle
        self.fact = fact
        self.factTone = factTone
        self.subtitleTone = subtitleTone
        self.prominent = prominent
        self.tint = tint
        self.busy = busy
        self.opens = opens
        self.action = action
        self.leading = leading
    }

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            DSPushRowLabel(title: title, subtitle: subtitle, fact: fact, factTone: factTone,
                           subtitleTone: subtitleTone, prominent: prominent,
                           tint: tint, busy: busy, opens: opens, leading: leading)
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}

extension DSPushRow where Leading == EmptyView {
    init(title: Text, subtitle: Text? = nil, fact: Text? = nil,
         factTone: Color = DS.textTertiary,
         subtitleTone: Color = DS.textTertiary, prominent: Bool = false,
         tint: Color = DS.textPrimary, busy: Bool = false, opens: Bool = true,
         action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, fact: fact, factTone: factTone,
                  subtitleTone: subtitleTone, prominent: prominent, tint: tint,
                  busy: busy, opens: opens, action: action) { EmptyView() }
    }
}

/// The app's one "there's more" glyph on a row. Was `WalletRowChevron`, the
/// wallet room's consolidation that the rest of the app never adopted.
struct DSChevron: View {
    var tint: Color = DS.textTertiary

    var body: some View {
        Image(systemName: "chevron.right")
            .dsGlyph(.caption)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }
}

/// A count-link: "See all 128 ›" beside a section label or under a list.
/// Eight hand-drawn copies at five chevron sizes before §715.
struct DSMoreLink: View {
    let title: Text
    var tint: Color = DS.tint
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: 3) {
                title
                    .dsText(.label12).fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .dsGlyph(.tick, weight: .bold)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}
