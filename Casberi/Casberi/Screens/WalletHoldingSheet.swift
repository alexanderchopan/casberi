import SwiftUI

/// **EVERY HOLDING OPENS ITS PAGE (user, 2026-11-21: "shouldn't the token
/// page open for all of them which itself has send and swap on it? … or do
/// we have rules? i don't understand").** Holdings had grown a rule per
/// kind: a public token opened its page, a lent or private row went straight
/// into Move, Round-ups and Aztec did nothing. One rule now: a tap on any
/// holding opens its page, which says what it is and where, and lists only
/// the verbs that work for that place; the long press offers the same verbs.
/// A public token keeps its own page (`WalletTokenSheet`, prd §1670), which
/// itemizes networks; this is every other holding's, one place each.
struct WalletHolding: Identifiable, Equatable {
    /// "lent:<aToken>", "private:<row>", "railgun:<id>", "aztec:<id>", "roundups".
    let id: String
    /// The mark's name and the page's title.
    let symbol: String
    var title: String? = nil
    /// The row's figure, drawn when there are no dollars to say exactly: a
    /// mask while balances are hidden, or an amount with no price.
    let figure: String
    /// Its dollars, nil while hidden or unpriced: the page says them whole,
    /// "$1,116", as the token page does, where the row said "$1K".
    var usd: Double? = nil
    /// The row's own line: network · fact · place (prd §1718).
    let line: String
    /// Aztec's own ink on its line (prd §1779).
    var aztec = false
    let verbs: [Verb]

    /// What a holding can do, by place. Values only, so the sheet's route
    /// holds no closure; the screen runs it once the page has gone.
    enum Verb: Equatable, Hashable, Identifiable {
        case lendWithdraw(chainId: Int, symbol: String)
        case lendDeposit(chainId: Int, symbol: String)
        case privateSend
        case railgunSend(contract: String?)
        case railgunSwap(contract: String?)
        case aztecSend

        var id: Self { self }

        func title(_ symbol: String) -> String {
            switch self {
            case .lendWithdraw: String(localized: "Withdraw \(symbol)")
            case .lendDeposit: String(localized: "Deposit \(symbol)")
            case .privateSend, .railgunSend, .aztecSend: String(localized: "Send \(symbol)")
            case .railgunSwap: String(localized: "Swap \(symbol)")
            }
        }

        /// The glyphs the token page wears for the same verbs (§1684).
        var icon: String {
            switch self {
            case .lendWithdraw: "arrow.down"
            case .lendDeposit: "plus"
            case .privateSend, .railgunSend, .aztecSend: "arrow.up.right"
            case .railgunSwap: "arrow.left.arrow.right"
            }
        }
    }
}

struct WalletHoldingSheet: View {
    let holding: WalletHolding
    /// Runs the verb once this sheet has gone (one sheet at a time, §872).
    let act: (WalletHolding.Verb) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pending: WalletHolding.Verb?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSSheetHead(disc: { AssetMark(name: holding.symbol, size: DS.Face.shelf) },
                            lead: String(localized: "Token"),
                            title: holding.title ?? holding.symbol)
                Text(verbatim: holding.usd.map(WalletValue.exactMoney) ?? holding.figure)
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .padding(.horizontal, DS.Space.s4)
                Text(verbatim: holding.line)
                    .dsText(.body17)
                    .foregroundStyle(holding.aztec ? DS.aztecInk : DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s1)
                if !holding.verbs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(holding.verbs) { verb in
                            DSDoorRow(icon: verb.icon, title: Text(verbatim: verb.title(holding.symbol))) {
                                pending = verb
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
                }
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        .dsInk()
        .dsReadSheet()
        .onDisappear {
            guard let verb = pending else { return }
            pending = nil
            act(verb)
        }
    }
}

extension FeedScreen {
    /// A holding's verb, run where Move is raised: after its page has gone,
    /// or straight from its long press.
    func walletDo(_ verb: WalletHolding.Verb) {
        switch verb {
        case .lendWithdraw(let chainId, let symbol):
            DSHaptic.selection()
            LendMove.opening = (chainId, symbol)
            chrome.moveLend = .takeBack
            chrome.moveTray = true
        case .lendDeposit(let chainId, let symbol):
            DSHaptic.selection()
            LendMove.opening = (chainId, symbol)
            chrome.moveLend = .lend
            chrome.moveTray = true
        case .privateSend:
            walletOpenPrivate(.send)
        case .railgunSend(let contract):
            DSHaptic.selection()
            chrome.moveRailgun = .init(contract: contract, takeBack: true)
            chrome.moveTray = true
        case .railgunSwap(let contract):
            DSHaptic.selection()
            chrome.moveRailgun = .init(contract: contract, takeBack: false, swap: true)
            chrome.moveTray = true
        case .aztecSend:
            DSHaptic.selection()
            chrome.moveAztec = .send
            chrome.moveTray = true
        }
    }

    /// A holding's long press: the same verbs its page lists.
    @ViewBuilder
    func walletHoldingMenu(_ holding: WalletHolding) -> some View {
        ForEach(holding.verbs) { verb in
            Button { walletDo(verb) } label: {
                Label(verb.title(holding.symbol), systemImage: verb.icon)
            }
        }
    }

    /// Opens a holding's page.
    func walletOpenHolding(_ holding: WalletHolding) {
        DSHaptic.selection()
        feedSheet = .walletHolding(holding)
    }
}
