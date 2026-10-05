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
        // Holdings lists what is held, not what happened (`logosHoldingsSection`).
        case .holdings:
            return []
        }
    }

    /// The devnets' chrome, Logos' parts (prd §991). Every account feeds the
    /// menu, never the scoped list, for Frames' reason: this is the control
    /// that SETS the scope. The verbs are rows, not tiles (prd §1108): "New
    /// account" heads the Accounts menu while this phone holds no key, and
    /// Send leads Holdings (`logosHoldingsSection`); which a page offers is
    /// `LogosSection.canCreate`/`canSend`. The Explorer tile is deleted: the
    /// Logos page carries the door and every row opens its transaction.
    @ViewBuilder
    func logosScopeChromeSection(_ active: LogosSection) -> some View {
        let head = LogosRoom.compose(scope: chrome.logosScope)
        let roster = LogosStore.shared.accounts
        Section {
            DSRoomScopeChrome(
                source: LogosRoom.source,
                sections: chrome.logosSections,
                active: active,
                home: .home,
                onPick: { picked in chrome.logosSection = picked },
                accounts: logosAccountSlots(roster) + hostedNetworkSlots,
                scope: chrome.logosScope,
                onPickAccount: { picked in
                    if !pickHostedNetwork(picked) { logosPickAccount(picked) }
                },
                // A key whose account is no longer watched offers it again,
                // which watches it (`LogosSend.create`).
                accountAction: LogosSection.canCreate(keyAccount: logosKeyAccount(roster))
                    ? .init(title: String(localized: "New account"), symbol: "plus") { logosCreate() }
                    : nil,
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
                : ListFormatter.localizedString(byJoining: roster.map(LogosRoom.name(for:))),
            faces: roster.prefix(2).map { .wallet(address: $0) })
        return [all] + roster.map { id in
            DSAccountSlot(id: id,
                          name: LogosKey.holds(id) ? String(localized: "This phone · \(LogosRoom.name(for: id))")
                                                   : LogosRoom.name(for: id),
                          sub: store.balance(for: id)
                              .map { String(localized: "\(LogosWire.amount($0)) test coins") }
                              .map { LogosScreen.withID(id, $0) },
                          faces: [.wallet(address: id)])
        }
    }

    // MARK: - Create and Send (prd §1084)

    /// Create: **one tap makes it** (Frames' §553). The account is watched,
    /// so the room lists it, and the room turns to it. It holds nothing yet:
    /// LEZ has no faucet, so somebody has to send to it — the copy says so,
    /// and copies the id so it can be handed over.
    func logosCreate() {
        guard !DemoMode.isActive else {
            chrome.flash(String(localized: "No key is made in the demo — this is where your own would be."))
            return
        }
        do {
            let id = try LogosSend.create()
            UIPasteboard.general.string = id
            withAnimation(DS.Motion.standard) { chrome.logosScope = id }
            chrome.flash(String(localized: "Account made. Its id is copied — send test coins to it to fund it."))
            chrome.rain(sources: [LogosRoom.source])
            Task { _ = await LogosIngest.refresh(context: modelContext) }
        } catch {
            chrome.flash(String(localized: "Couldn't make a key: \(String(describing: error))"), tone: .failure)
        }
    }

    /// Who the send sheet offers: every watched account but this phone's own.
    var logosSendCandidates: [(address: String, name: String?)] {
        let mine = LogosKey.accountID()
        return LogosStore.shared.accounts.filter { $0 != mine }.map { ($0, nil) }
    }

    /// What this phone's account holds, or nil when it has not been read — a
    /// failed read and a real zero must not look alike (§83).
    var logosHeldLine: String? {
        guard let mine = LogosKey.accountID(), let balance = LogosStore.shared.balance(for: mine) else { return nil }
        return String(localized: "\(LogosWire.amount(balance)) available · the fee comes out of it")
    }

    /// Returns nil on success, or the sentence the sheet shows.
    func sendLogos(to: String, amount: String) async -> String? {
        guard !DemoMode.isActive else {
            return String(localized: "Nothing is sent in the demo — this is where your own key would sign it.")
        }
        guard let value = LogosWire.typedAmount(amount) else {
            return String(localized: "Test coins on Logos are whole numbers.")
        }
        switch await LogosSend.send(to: to, amount: value, context: modelContext) {
        case .success:
            chrome.rain(sources: [LogosRoom.source])
            return nil
        case .failure(let failure):
            return failure.words
        }
    }

    /// This phone's account, when the room still watches it — a key whose
    /// account was unwatched counts as none, so Create can watch it again.
    func logosKeyAccount(_ roster: [String]) -> String? {
        LogosKey.accountID().flatMap { roster.contains($0) ? $0 : nil }
    }

    /// Holdings' list (prd §1084): one row per asset, the family's
    /// `RoomHoldingsRows`, in the rows' column like the Wallet's. **Send leads
    /// it (prd §1108)**, Frames' row, on the pages `LogosSection.canSend`
    /// allows.
    @ViewBuilder
    var logosHoldingsSection: some View {
        let cells = LogosHoldings.cells(LogosRoom.compose(scope: chrome.logosScope))
        if LogosSection.canSend(account: chrome.logosScope,
                                keyAccount: logosKeyAccount(LogosStore.shared.accounts)) {
            Section {
                DSDoorRow(icon: "arrow.up.right", label: "Send") { feedSheet = .logosSend }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                              bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        if !cells.isEmpty {
            Section {
                RoomHoldingsRows(cells: cells)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                              bottom: DS.Space.s4, trailing: DS.Space.s4))
            }
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
