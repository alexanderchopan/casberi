import SwiftUI

/// **ACCOUNT IS LINES ON PLATES (prd §1937, user picked H of the canvas
/// "Account, updated": "yea. that's good").** Every setting is one line: its
/// word grey in a fixed column, its value where the values start, a verb or a
/// switch at the end; lines stand `pitch` apart with no gap, as Home's
/// balance rows do. Groups stand on plates (`AccountPlate`) so each reads as
/// one thing (user: "it would make them feel like discrete things").
enum AccountLines {
    /// A line's height: tight, as Home's places (prd §1930), and the whole
    /// line is its tap.
    static let pitch: CGFloat = 32
    /// The words' column: "Notifications" and "Privacy Pools" fit at 17.
    static let labelWidth: CGFloat = 118
}

struct AccountLine<Trailing: View>: View {
    let label: String
    var value: String?
    var ink: Color = DS.textPrimary
    /// Said instead of `value` when that is wider than the line.
    var short: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if let action {
            Button {
                DSHaptic.selection()
                action()
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Text(verbatim: label)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: AccountLines.labelWidth, alignment: .leading)
            if let value {
                // One line, always: a value too wide says its short form.
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: value).lineLimit(1).fixedSize()
                    Text(verbatim: short ?? value).lineLimit(1).minimumScaleFactor(short == nil ? 0.7 : 1)
                }
                .dsText(.body17)
                .foregroundStyle(ink)
                .layoutPriority(1)
            }
            Spacer(minLength: DS.Space.s2)
            trailing()
        }
        .frame(minHeight: AccountLines.pitch)
        .accessibilityElement(children: .contain)
    }
}

extension AccountLine where Trailing == EmptyView {
    init(label: String, value: String?, ink: Color = DS.textPrimary, short: String? = nil,
         action: (() -> Void)? = nil) {
        self.init(label: label, value: value, ink: ink, short: short, action: action) { EmptyView() }
    }
}

/// A group's part on its plate: Public, Private, Saving (prd §1937).
struct AccountSubhead: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .dsText(.heading17)
            .fontWeight(.bold)
            .foregroundStyle(DS.textPrimary)
            .frame(minHeight: AccountLines.pitch, alignment: .bottomLeading)
            .padding(.top, DS.Space.s2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **A GROUP ON ITS PLATE (prd §1937, amending §782 for Account's three
/// groups only):** Home's section panel, its name at the section rung,
/// the lines on it. The plate reaches past the lines' column by `bleed`, so
/// the words stand where they would without it.
struct AccountPlate<Content: View>: View {
    let name: String
    var glyph: String = ""
    @ViewBuilder let content: () -> Content

    static var bleed: CGFloat { DS.Space.s3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionPanelName(name: name, glyph: glyph, inset: 0)
            content()
        }
        .padding(.horizontal, Self.bleed)
        .padding(.top, DS.Space.s1)
        .padding(.bottom, DS.Space.s3)
        .background(SectionPanel.fill, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .padding(.horizontal, -Self.bleed)
    }
}

/// **OFF | ON (prd §1937):** two words on one track, the one it is lit; Move's
/// $ | token switch in a setting's place. A tap on the other word asks.
struct AccountOnOff: View {
    let on: Bool
    var disabled = false
    let pick: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(String(localized: "Off"), lit: !on) { pick(false) }
            segment(String(localized: "On"), lit: on) { pick(true) }
        }
        .padding(3)
        .frame(height: 32)
        .background(DS.fillFaint, in: Capsule())
        .fixedSize()
        .disabled(disabled)
        .animation(DS.Motion.standard, value: on)
    }

    private func segment(_ word: String, lit: Bool, _ act: @escaping () -> Void) -> some View {
        Button {
            guard !lit else { return }
            act()
            DSHaptic.selection()
        } label: {
            Text(verbatim: word)
                .dsText(.fact15)
                .lineLimit(1)
                .foregroundStyle(lit ? DS.textPrimary : DS.textSecondary)
                .padding(.horizontal, 10)
                .frame(minWidth: 40, minHeight: 26)
                .background { if lit { Capsule().fill(DS.fillStrong) } }
                .dsTapTarget()
                .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityAddTraits(lit ? [.isSelected] : [])
    }
}
