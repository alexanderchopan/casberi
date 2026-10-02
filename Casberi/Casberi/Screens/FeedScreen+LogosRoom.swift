import SwiftUI
import SwiftData

// The Logos room (prd §991): its rows, scope chrome, account slots and pick, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - Logos (prd §991)

    /// The Logos room's rows for one scope: Home's are the chain's moves
    /// (narrowed to the picked account) — the deleted Activity tile's list
    /// (prd §1039) — Node is your node's health and Rewards what it earned
    /// (prd §1016).
    func logosRows(_ rows: [Thing], section: LogosSection) -> [Thing] {
        switch section {
        case .home:
            return rows.filter { thing in
                guard let account = LogosRoom.account(ofRef: thing.sourceRef) else { return false }
                return chrome.logosScope == nil || chrome.logosScope == account
            }
        case .node:
            return rows.filter { LogosRoom.isNodeRef($0.sourceRef) }
        case .rewards:
            return rows.filter { LogosRoom.isRewardsRef($0.sourceRef) }
        case .explorer:
            return []
        }
    }

    /// The devnets' chrome, Logos' parts (prd §991). Every account feeds the
    /// menu, never the scoped list, for Frames' reason: this is the control
    /// that SETS the scope. The one verb is the explorer, the last tile (prd
    /// §1039) — the seat holds no key, so it has nothing to send and nothing
    /// to sign. It opens the page the Actions row opened: the explorer's root
    /// on All, the account's own page on an account's.
    @ViewBuilder
    func logosScopeChromeSection(_ active: LogosSection) -> some View {
        let head = LogosRoom.compose(scope: chrome.logosScope)
        let roster = LogosStore.shared.accounts
        Section {
            DSRoomScopeChrome(
                source: LogosRoom.source,
                sections: chrome.logosSections,
                verbs: LogosSection.verbs,
                active: active,
                home: .home,
                onPick: { picked in
                    guard picked == .explorer else {
                        chrome.logosSection = picked
                        return
                    }
                    let page = chrome.logosScope.map { "\(LogosIngest.explorer)/account/\($0)" }
                        ?? LogosIngest.explorer
                    if let url = URL(string: page) { UIApplication.shared.open(url) }
                },
                accounts: logosAccountSlots(roster) + hostedNetworkSlots,
                scope: chrome.logosScope,
                onPickAccount: { picked in
                    if !pickHostedNetwork(picked) { logosPickAccount(picked) }
                },
                crown: { slot in
                    Group {
                        if slot.isShowing(chrome.logosScope) {
                            LogosRoomFigure(head: head, section: .home)
                        }
                    }
                },
                figure: { scope in
                    LogosRoomFigure(head: head, section: scope)
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                      bottom: DSRoomChassis.contentGap, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The Logos accounts as deck cards, "All" first — Frames' shape.
    private func logosAccountSlots(_ roster: [String]) -> [DSAccountSlot] {
        let store = LogosStore.shared
        let all = DSAccountSlot(
            id: "",
            name: String(localized: "All accounts"),
            sub: roster.isEmpty
                ? String(localized: "Nothing watched on Logos yet")
                : ListFormatter.localizedString(byJoining: roster.map(LogosWire.short)),
            faces: roster.prefix(2).map { .wallet(address: $0) })
        return [all] + roster.map { id in
            DSAccountSlot(id: id, name: LogosWire.short(id),
                          sub: store.balance(for: id).map { String(localized: "\(LogosWire.amount($0)) test coins") },
                          faces: [.wallet(address: id)])
        }
    }

    func logosPickAccount(_ picked: String?) {
        withAnimation(DS.Motion.standard) {
            chrome.logosScope = (picked?.isEmpty ?? true) ? nil : picked
        }
    }

    var logosSectionPublication: [LogosSection] {
        guard source == LogosRoom.source else { return [] }
        return LogosSection.present()
    }
}
