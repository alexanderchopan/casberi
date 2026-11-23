import SwiftUI

/// **ACCOUNT IS LINES ON PLATES (prd §1937), EACH LINE SAYING WHAT A TAP DOES
/// (prd §1944, user: "you can't tell which things are tappable and which
/// aren't").** A line is the app's row: the setting's name white at the left
/// edge, its value grey at the trailing edge (a state in its own ink), 44pt
/// tall as every row is. Its END is the one thing that says what it does,
/// and there are four ends, never a fifth:
///
/// - **opens** (a page, a sheet, a tray): the grey chevron (§1815, extended
///   by §1944 to sheets on this page);
/// - **acts** (a verb run in place): the verb in the pick's ink, and the
///   whole line is the verb;
/// - **switches**: `AccountSwitch`, two words on one track;
/// - **states** (nothing to do): no mark, and no tap.
///
/// A value never wears the pick's ink: pink is a verb's, at the end.
enum AccountLines {
    /// A line's height: the app's row and the tap minimum (§1482), never
    /// §1937's 32.
    static let pitch: CGFloat = DS.Hit.min
    /// Money's plate rows (`MoneyPlateRows`) keep a word column; Account's
    /// lines no longer do (§1944).
    static let labelWidth: CGFloat = 118
}

/// What a line's end says it does (prd §1944).
enum AccountLineEnd {
    /// A fact: no mark, no tap.
    case states
    /// A page, a sheet or a tray: the chevron.
    case opens
    /// Out of the app (Mail, iOS Settings): the arrow.
    case leaves
    /// A verb run in place, in the pick's ink; `busy` draws its word grey
    /// and takes no tap ("Setting up…").
    case acts(String, busy: Bool = false)
}

struct AccountLine<Trailing: View>: View {
    let label: String
    var value: String?
    var ink: Color = DS.textSecondary
    /// Said instead of `value` when that is wider than the line.
    var short: String? = nil
    var end: AccountLineEnd = .states
    var action: (() -> Void)? = nil
    var labelInk: Color = DS.textPrimary
    @ViewBuilder var trailing: () -> Trailing

    private var busy: Bool {
        if case .acts(_, let busy) = end { return busy }
        return false
    }

    var body: some View {
        if let action, !busy {
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
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: label)
                .dsText(.body17)
                .foregroundStyle(labelInk)
                .lineLimit(1)
                .layoutPriority(2)
            Spacer(minLength: DS.Space.s2)
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
            trailing()
            endMark
        }
        .frame(minHeight: AccountLines.pitch)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var endMark: some View {
        switch end {
        case .states:
            EmptyView()
        case .opens:
            Image(systemName: "chevron.right")
                .dsGlyph(.subhead, weight: .semibold)
                .foregroundStyle(DS.textTertiary)
                .accessibilityHidden(true)
        case .leaves:
            Image(systemName: "arrow.up.right")
                .dsGlyph(.caption, weight: .semibold)
                .foregroundStyle(DS.textTertiary)
                .accessibilityHidden(true)
        case .acts(let word, let busy):
            Text(verbatim: word)
                .dsText(.body17)
                .foregroundStyle(busy ? DS.textTertiary : DS.pickInk)
                .lineLimit(1)
                .fixedSize()
                // The verb keeps its width ("Setting up…" is longer than
                // "Finish"); the value beside it gives way instead.
                .layoutPriority(3)
        }
    }
}

extension AccountLine where Trailing == EmptyView {
    init(label: String, value: String? = nil, ink: Color = DS.textSecondary, short: String? = nil,
         end: AccountLineEnd = .states, labelInk: Color = DS.textPrimary,
         action: (() -> Void)? = nil) {
        self.init(label: label, value: value, ink: ink, short: short, end: end, action: action,
                  labelInk: labelInk) { EmptyView() }
    }
}

/// A group's part on its plate: Public, Private, Following (prd §1947).
struct AccountSubhead: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .dsText(.heading17)
            .fontWeight(.bold)
            .foregroundStyle(DS.textPrimary)
            .frame(minHeight: 32, alignment: .bottomLeading)
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

/// **A SWITCH IS TWO WORDS ON ONE TRACK (prd §1937, §1944):** Off | On,
/// Dark | Light, Wallet | Activity; the lit one is the setting. A tap on the
/// other word asks. Move's $ | token switch in a setting's place.
struct AccountSwitch: View {
    let words: (String, String)
    /// True lights the second word.
    let second: Bool
    var disabled = false
    let pick: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(words.0, lit: !second) { pick(false) }
            segment(words.1, lit: second) { pick(true) }
        }
        .padding(3)
        .frame(height: 32)
        .background(DS.fillFaint, in: Capsule())
        .fixedSize()
        .disabled(disabled)
        .animation(DS.Motion.standard, value: second)
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

/// Off | On, the switch most lines take.
struct AccountOnOff: View {
    let on: Bool
    var disabled = false
    let pick: (Bool) -> Void

    var body: some View {
        AccountSwitch(words: (String(localized: "Off"), String(localized: "On")), second: on,
                      disabled: disabled, pick: pick)
    }
}

/// **AN ACCOUNT OF YOURS, ON ACCOUNT (prd §1947).** Its name, the one line
/// under it that says where it is ("On Base, Ethereum and Robinhood"), and
/// the copy glyph at the end, which copies its address and turns to a tick
/// for a moment (§867). The name and line take no tap: the glyph is the one
/// act, and "How your accounts work" over the accounts is the door.
struct AccountCopyRow: View {
    let name: String
    let line: String
    /// Aztec's whole line wears its ink (prd §1779).
    var ink: Color = DS.textPrimary
    /// Nil draws no glyph: an address not read yet is never a dead copy (§83).
    var copy: (() -> Void)?

    @State private var copied = false

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .dsText(.body17)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(verbatim: line)
                    .dsText(.fact15)
                    .foregroundStyle(ink == DS.textPrimary ? DS.textSecondary : ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let copy {
                Button {
                    copy()
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) { copied = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(1200))
                        withAnimation(DS.Motion.standard) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .dsGlyph(.body, weight: .regular)
                        .foregroundStyle(copied ? DS.confirm : ink == DS.textPrimary ? DS.pickInk : ink)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: DS.Hit.min, height: DS.Hit.min, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Copy the \(name) address"))
            }
        }
        .padding(.vertical, DS.Space.s1)
    }
}

/// "Base, Ethereum and Robinhood": a list of networks as a sentence says it.
enum AccountNetworks {
    static func on(_ names: [String]) -> String {
        String(localized: "On \(ListFormatter.localizedString(byJoining: names))")
    }
}
