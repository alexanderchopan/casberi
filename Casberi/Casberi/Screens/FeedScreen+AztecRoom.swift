import SwiftUI
import SwiftData

// The Aztec room (2026-10-11): its rows, scope chrome and sequencer pick —
// Logos' room (`FeedScreen+LogosRoom.swift`) with this network's two scopes.
extension FeedScreen {

    /// Home's list is the activity (prd §1039): every row, narrowed to the
    /// picked sequencer. Node lists the sequencers themselves
    /// (`aztecRosterSection`), so no two tiles draw the same list.
    func aztecRows(_ rows: [Thing]) -> [Thing] {
        rows.filter { thing in
            guard let address = AztecRoom.sequencer(ofRef: thing.sourceRef) else { return true }
            return chrome.aztecScope == nil || chrome.aztecScope == address
        }
    }

    /// Node's list: one row per sequencer in scope, its duty line under its
    /// name. A tap narrows the room to it; on its own page the row is the
    /// page, so it opens nothing.
    @ViewBuilder
    var aztecRosterSection: some View {
        let store = AztecStore.shared
        let shown = chrome.aztecScope.map { s in store.sequencers.filter { $0 == s } } ?? store.sequencers
        Section {
            ForEach(shown, id: \.self) { address in
                let reading = store.reading(for: address)
                Button {
                    if chrome.aztecScope == nil { aztecPickSequencer(address) }
                } label: {
                    DSPushRowLabel(
                        title: Text(AztecRoom.name(for: address)),
                        subtitle: Text([reading.map(AztecWire.line)
                                            ?? (store.readAt == nil ? String(localized: "Reading…")
                                                                    : String(localized: "Not seen by this node")),
                                        AztecRoomFigure.stakeLine(store.stake(for: address), symbol: store.stakeSymbol),
                                        AztecRoomFigure.dutyLine(store.duty(for: address))]
                                        .compactMap { $0 }.joined(separator: "\n")),
                        fact: reading.flatMap { AztecWire.isStopped($0) ? Text("Stopped") : nil },
                        factTone: DS.attentionInk,
                        opens: chrome.aztecScope == nil) {
                        WalletFace(address: address, size: DS.Face.list, circular: true)
                    }
                }
                .buttonStyle(RowPress())
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }

    /// Holdings' list (round two): one row per followed account, its PUBLIC
    /// Fee Juice trailing. A tap narrows the room to it, as Node's does.
    @ViewBuilder
    var aztecHoldingsSection: some View {
        let store = AztecStore.shared
        let shown = chrome.aztecScope.map { s in store.accounts.filter { $0 == s } } ?? store.accounts
        Section {
            ForEach(shown, id: \.self) { account in
                Button {
                    if chrome.aztecScope == nil { aztecPickSequencer(account) }
                } label: {
                    DSPushRowLabel(
                        title: Text(AztecRoom.name(for: account)),
                        subtitle: Text(String(localized: "Public Fee Juice")),
                        fact: store.publicFeeJuice(for: account).map { Text(AztecWire.tokens($0)) },
                        opens: chrome.aztecScope == nil,
                        factFits: true) {
                        WalletFace(address: account, size: DS.Face.list, circular: true)
                    }
                }
                .buttonStyle(RowPress())
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                .feedRowBackground()
                .listRowSeparator(.hidden)
            }
        }
    }

    /// The testnets' chrome, Aztec's parts. The account menu is the
    /// sequencers; its first row follows another (the Aztec page, where an
    /// attester address is read). No verb is a tile (prd §1108).
    @ViewBuilder
    func aztecScopeChromeSection(_ active: AztecSection) -> some View {
        let head = AztecRoom.compose(scope: chrome.aztecScope)
        let roster = AztecStore.shared.sequencers + AztecStore.shared.accounts
        Section {
            DSRoomScopeChrome(
                source: AztecRoom.source,
                sections: chrome.aztecSections,
                active: active,
                home: .home,
                onPick: { picked in chrome.aztecSection = picked },
                accounts: aztecSequencerSlots(roster) + hostedNetworkSlots,
                scope: chrome.aztecScope,
                onPickAccount: { picked in
                    if !pickHostedNetwork(picked) { aztecPickSequencer(picked) }
                },
                accountAction: .init(title: String(localized: "Follow a sequencer"), symbol: "plus") {
                    if let destination = BridgeRouter.destination(forOffer: AztecRoom.source) {
                        route.openAccount(destination)
                    }
                },
                crown: { slot in
                    Group {
                        if slot.isShowing(chrome.aztecScope) {
                            AztecRoomFigure(head: head, section: .home)
                        }
                    }
                },
                figure: { scope in
                    AztecRoomFigure(head: head, section: scope)
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                      bottom: DSRoomChassis.contentGap, trailing: 0))
            .feedRowBackground()
            .listRowSeparator(.hidden)
        }
    }

    /// The followed sequencers as deck cards, "All" first — Logos' shape.
    private func aztecSequencerSlots(_ roster: [String]) -> [DSAccountSlot] {
        let store = AztecStore.shared
        let all = DSAccountSlot(
            id: "",
            name: String(localized: "All"),
            sub: roster.isEmpty
                ? String(localized: "Nothing followed on Aztec yet")
                : ListFormatter.localizedString(byJoining: roster.map(AztecRoom.name(for:))),
            faces: roster.prefix(2).map { .wallet(address: $0) })
        return [all] + roster.map { address in
            DSAccountSlot(id: address, name: AztecRoom.name(for: address),
                          sub: store.accounts.contains(address)
                              ? store.publicFeeJuice(for: address).map { String(localized: "\(AztecWire.tokens($0)) public Fee Juice") }
                              : store.reading(for: address).map(AztecWire.line),
                          faces: [.wallet(address: address)])
        }
    }

    func aztecPickSequencer(_ picked: String?) {
        withAnimation(DS.Motion.standard) {
            chrome.aztecScope = (picked?.isEmpty ?? true) ? nil : picked
        }
    }

    var aztecSectionPublication: [AztecSection] {
        guard source == AztecRoom.source else { return [] }
        return AztecSection.present()
    }
}
