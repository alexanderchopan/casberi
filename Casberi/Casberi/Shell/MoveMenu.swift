import SwiftUI

/// **MOVE'S MENU RISES FROM ITS BUTTON (prd §1852, user: "it's a lot of
/// verbs"; "have them on the right and above the fab").** On the phone the
/// Move button no longer raises a sheet to ask what you want: Home dims and
/// five verbs stand in a stack over the button, at the thumb, the button
/// itself the way out. A verb picked raises Move's sheet on that verb; its
/// back returns here.
///
/// **FIVE VERBS (prd §1852, replacing §1781's whole menu of seven).** Buy
/// holds gift cards (Spend was the same act, buying), Swap holds Sweep, and
/// Lend reads Earn; each of the two picks its kind on its own page. Send and
/// Receive stay apart: they are the two everyone uses, and opposites.
enum MoveMenu {
    enum Verb: String, CaseIterable {
        case buy, earn, receive, send, swap

        var label: String {
            switch self {
            case .buy: String(localized: "Buy")
            case .earn: String(localized: "Earn")
            case .receive: String(localized: "Receive")
            case .send: String(localized: "Send")
            case .swap: String(localized: "Swap")
            }
        }
    }

    /// The verbs offered, A–Z in the reader's language (§1547's order).
    static var offered: [Verb] {
        Verb.allCases.filter { $0 != .earn || AaveLend.on }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// The menu stands over the page only on the phone, and only once an
    /// account of yours exists: before that the button raises the walk that
    /// makes one, as it did.
    @MainActor static var rises: Bool { PhoneHome.isOn && YourAccountDemo.shownAddress != nil }

    @MainActor static func pick(_ verb: Verb, _ chrome: ShellChrome) {
        DSHaptic.selection()
        chrome.moveAsk = verb.rawValue
        withAnimation(DS.Motion.standard) { chrome.moveMenu = false }
        chrome.moveTray = true
    }

    /// One target width for every verb: the widest word's, with air.
    static let rowWidth: CGFloat = 200

    @MainActor static func close(_ chrome: ShellChrome) {
        withAnimation(DS.Motion.standard) { chrome.moveMenu = false }
    }
}

/// The page under the menu, dimmed: a tap on it puts the menu away.
struct MoveMenuDim: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        DS.page.opacity(0.88)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { MoveMenu.close(chrome) }
            .accessibilityLabel(Text("Close"))
            .accessibilityAddTraits(.isButton)
            .transition(.opacity)
    }
}

/// The verbs, right-aligned over the Move button.
struct MoveMenuVerbs: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(MoveMenu.offered, id: \.self) { verb in
                Button { MoveMenu.pick(verb, chrome) } label: {
                    // **AN ACT'S RUNG (prd §1912, user, 2026-11-19: "should
                    // the Move menu words be larger? do you think they are
                    // tappable enough?", "they are the same size as our
                    // section titles but not as big as the words in the
                    // sentence"; amends §1889's heading24):** `heading34`,
                    // Add's and the foot's acts' size (§1616), a step under
                    // the sentence. Every row is one width, so "Buy" is
                    // as easy to hit as "Receive".
                    Text(verbatim: verb.label)
                        .dsText(.heading34)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .frame(minWidth: MoveMenu.rowWidth, minHeight: 56, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
            }
        }
        .padding(.trailing, DS.Space.s2)
        .padding(.bottom, DS.Space.s2)
        .transition(.opacity.combined(with: .offset(y: 16)))
    }
}
