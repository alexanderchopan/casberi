import SwiftUI

/// **PRIVATE, IN HOLDINGS (prd §1554).** Under Tokens, Holdings only SHOWS
/// what is private: a head naming it with its total, then one row per token,
/// state and network off the notes Move to private kept (`PrivateMoney.rows`)
/// — "ETH" over "1.0% on Aave" where it earns (Ethereum's yield pools, the
/// rate read live, prd §1563) or its network ("Sepolia", which has no Aave),
/// "ETH" with the amber clock over "Waiting for approval", "ETH" over "Not
/// approved". The token alone: the head already says private. The Tokens rows above are
/// public balances only; the box counts approved private money as one
/// Private block, and the total counts it once (`PrivateMoneyStore.walletHolding`).
/// No verb here: the acts are Send's (`MovePrivateSentence`). The header
/// opens Send to your private balance; a row opens Send with the Private
/// switch on. Private is never the default.
///
/// The section stands where there is a note to show, or, in a build that can
/// move to private (`PrivateMove.available`: Ethereum, or Sepolia in DEBUG),
/// as the head alone — the door with nothing behind it yet.
extension FeedScreen {

    @ViewBuilder
    var walletPrivateRows: some View {
        let store = PrivateMoneyStore.shared
        let rows = store.rows
        // Yours and All only (prd §1590): private money is your Casberi
        // account's, never a followed wallet's or an app's pick. Privacy
        // Pools has no pick (prd §1738): its tile lands here.
        if selectedSeat == nil, !walletOnFollowing,
           selectedWallet.map(YourAccountDemo.isYours) ?? true,
           PrivateMove.available || !rows.isEmpty {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                // Your Aztec account's rows stand under this head on All and
                // Yours (`walletAztecRows`), so its figure adds them (prd §1700e).
                let aztecStore = AztecAccountStore.shared
                // Railgun's tokens too (prd §1721): one Private balance.
                let railgun = RailgunHoldings.shared
                let railgunRows = selectedSeat == nil ? railgun.shown : []
                let aztec = (selectedSeat == nil && aztecStore.isShown
                    ? aztecStore.privateHeld.compactMap { aztecStore.usd($0, units: $0.privateUnits) }.reduce(0, +) : 0)
                    + railgunRows.compactMap { railgun.usd($0, units: $0.amount) }.reduce(0, +)
                walletPrivateHead(total: mask ?? walletPrivateTotal(rows, prices: store.shownPrices, plus: aztec))
                    .task(id: rows.map(\.id)) {
                        await store.refresh()
                        await store.readPrices()
                        await store.readYield()
                        await RailgunHoldings.shared.refresh()
                        // A new phone finds its private money again here
                        // (prd §1562, every build since §1567): each root's
                        // notes from the pool, its fresh addresses walked
                        // back. Once per root; the line says so meanwhile.
                        // Every root's notes again on a cadence, and what was
                        // sent and not seen asked about (the review of
                        // 2026-10-26, finding 2).
                        await PrivateWatch.findNotes(context: modelContext)
                        await FreshReceive.shared.restore()
                        // What a fresh address was paid moves in from here
                        // too (prd §1560): its row appears as "moving in".
                        await FreshReceive.shared.check(context: modelContext)
                        // A note waiting on the ASP is asked again while the
                        // section shows (the store spaces the asks 20 s).
                        while PrivateMoney.anyWaiting(store.notes), !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(20))
                            await store.refresh()
                        }
                    }
                // One line while a new phone rebuilds it (prd §1567): never
                // a spinner page, gone when done.
                // The savings goal moved to Your account › Spending (prd
                // §1700f item 10): Holdings lists what you hold.
                if store.restoring {
                    Text("Restoring your private balance")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.leading, DSRoomChassis.headGlyph + DSRoomChassis.headGap)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .walletListRow()
                        .transition(.opacity)
                }
                ForEach(rows) { row in
                    walletPrivateRow(row, mask: mask, prices: store.shownPrices)
                }
                // Railgun's tokens (prd §1713, §1721): whatever the wallet
                // holds, spendable first, then what Railgun's screening has
                // yet to list.
                if selectedSeat == nil {
                    walletRailgunRows(mask: mask)
                }
                // Empty, the place stands where its rows will (prd §1718, by
                // §769's rule: an empty state draws what would fill it): one
                // row for Privacy Pools, named and marked as a holding's line
                // ends, saying what it takes; its tap is the Private head's,
                // Send to your private balance.
                // One row whatever protocol sits behind it (prd §1719): the
                // token decides Privacy Pools or Railgun, never the person.
                if rows.isEmpty, RailgunHoldings.shared.shown.isEmpty, !store.restoring, PrivateMove.available {
                    walletPlaceRow(String(localized: "Your private balance"),
                                   line: (PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) ?? .ethereum).name,
                                   mark: nil,
                                   hint: String(localized: "Sends to your private balance")) {
                        walletOpenPrivate(.deposit)
                    }
                }
            }
        }
    }

    /// **RAILGUN'S TOKENS IN THE PRIVATE BLOCK (prd §1713 items 1, 4 and 5,
    /// §1721).** Network · fact · place, the place last and no inline mark
    /// (§1718): "DAI — Ethereum · Railgun", the dollars trailing (the amount
    /// where Casberi has no price). What Railgun's screening has not yet
    /// listed reads "Private in about an hour", grey, behind a clock: a
    /// state, nobody waiting on you, never amber (item 5). A tap opens Send
    /// from it, which takes it back to your account (§1721 item 3).
    @ViewBuilder
    func walletRailgunRows(mask: String?) -> some View {
        let store = RailgunHoldings.shared
        ForEach(store.spendableShown) { h in
            walletRailgunRow(h, units: h.spendable, line: String(localized: "Ethereum · Railgun"), pending: false, mask: mask)
        }
        ForEach(store.pendingShown) { h in
            walletRailgunRow(h, units: h.pending, line: String(localized: "Private in about an hour"), pending: true, mask: mask)
        }
    }

    private func walletRailgunRow(_ h: RailgunHoldings.Held, units: String, line: String, pending: Bool, mask: String?) -> some View {
        let store = RailgunHoldings.shared
        let figure = mask ?? store.usd(h, units: units).map(WalletValue.money)
            ?? RailgunHoldings.figure(units, decimals: h.decimals)
        return Button {
            guard !pending else { return }
            DSHaptic.selection()
            chrome.moveRailgun = .init(contract: h.contract, takeBack: true)
            chrome.moveTray = true
        } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Group {
                    if pending {
                        Image(systemName: "clock")
                            .dsGlyph(.body, weight: .regular)
                            .foregroundStyle(DS.textSecondary)
                    } else {
                        AssetMark(name: h.symbol, size: DS.Mark.badge)
                    }
                }
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: h.symbol)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Text(verbatim: line)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                walletRowFigure(figure, tone: pending ? DS.textSecondary : DS.textPrimary)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .disabled(pending)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(pending ? [] : .isButton)
        .accessibilityLabel(Text(verbatim: [h.symbol, line, figure].joined(separator: ". ")))
        .walletListRow()
    }

    /// **A PRIVATE PLACE WITH NOTHING IN IT YET (prd §1718).** The row a
    /// holding there will take — the place's mark in the lead, its name, the
    /// line saying what it takes, no figure — so an empty Private section
    /// shows the places you have (Privacy Pools, Aztec; Railgun with its
    /// Holdings), one each, and a tap opens Move's sentence to that place.
    /// A place appears only once it exists for you; nothing promises one
    /// you don't have.
    func walletPlaceRow(_ name: String, line: String, mark: String?, hint: String,
                        act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                // Private's eye where no one mark stands for the place.
                Group {
                    if let mark {
                        BridgeIcon(name: mark, size: DS.Face.badge, circular: true)
                    } else {
                        Image(systemName: "eye.slash").dsGlyph(.body).foregroundStyle(DS.textSecondary)
                    }
                }
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Text(verbatim: line)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [name, line].joined(separator: ". ")))
        .accessibilityHint(Text(verbatim: hint))
        .walletListRow()
    }

    /// **ADD MONEY, THE LAST ROW UNDER PRIVATE (prd §1776, user: "i have a
    /// hard time getting money into my aztec account", then "'send to your
    /// private balance' is fine but need a 'add money'").** A verb, so a row
    /// (§746), last (§995), and it stays whether or not anything is held:
    /// the empty place's row went once money was in, and the only way back
    /// was a recipient in Send. The sentence it opens is Send's, unchanged.
    /// Which balance: the one you have; with both, Send's To list, which
    /// leads with the two and is told apart by network (§1719).
    @ViewBuilder
    var walletAddMoneyRow: some View {
        if selectedSeat == nil, !walletOnFollowing,
           selectedWallet.map(YourAccountDemo.isYours) ?? true,
           PrivateMove.available || Self.aztecTakesMoney {
            Button { walletAddMoney() } label: {
                HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                    Image(systemName: "plus")
                        .dsGlyph(.body)
                        .foregroundStyle(DS.pickInk)
                        .frame(width: DSRoomChassis.headGlyph)
                        .accessibilityHidden(true)
                    Text("Add money")
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                }
                .walletRowPitch()
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .dsHover()
            .accessibilityHint(Text("Sends to your private balance"))
            .walletListRow()
        }
    }

    /// Whether Send offers your private balance on Aztec: its To list's own
    /// rule, so the door never promises a row the list will not draw.
    static var aztecTakesMoney: Bool {
        (YourAccountKey.address != nil || DemoMode.isActive) && AztecProver.isAvailable
    }

    func walletAddMoney() {
        DSHaptic.selection()
        switch (PrivateMove.available, Self.aztecTakesMoney) {
        case (true, true): chrome.moveDraft = MoveSentence.privateDraft()
        case (false, true): chrome.moveAztec = .deposit
        default: chrome.movePrivately = .deposit
        }
        chrome.moveTray = true
    }

    /// The section's total: the private dollars, as the box counts them; with
    /// none to count (test money, §949), one token's quantity, else nothing.
    private func walletPrivateTotal(_ rows: [PrivateMoney.Row], prices: [String: Double], plus aztec: Double = 0) -> String? {
        let held = rows.filter { $0.kind == .held }
        let usd = held.compactMap { PrivateMoney.rowUSD($0, prices: prices) }
        if !usd.isEmpty || aztec > 0 { return WalletValue.money(usd.reduce(0, +) + aztec) }
        guard held.count == 1, let only = held.first else { return nil }
        return PrivateMoney.figure(only.amount, decimals: only.decimals, symbol: only.symbol)
    }

    /// Opens Send privately (prd §1554): to your private balance from the
    /// header, from it (the switch on) from a row.
    func walletOpenPrivate(_ mode: PrivateMove.Mode) {
        DSHaptic.selection()
        chrome.movePrivately = mode
        chrome.moveTray = true
    }

    /// The head: the door anatomy (`walletDoor`), whose page is Move's
    /// private sentence.
    private func walletPrivateHead(total: String?) -> some View {
        Button { walletOpenPrivate(.deposit) } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                Image(systemName: "eye.slash")
                    .dsGlyph(.body)
                    .foregroundStyle(DS.pickInk)
                    .frame(width: DSRoomChassis.headGlyph)
                    .accessibilityHidden(true)
                Text("Private")
                    .dsText(.heading24)
                    .foregroundStyle(DS.headInk)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let total {
                    Text(verbatim: total)
                        .dsText(.stat24)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: [String(localized: "Private"), total].compactMap { $0 }.joined(separator: ". ")))
        .accessibilityHint(Text("Sends to your private balance"))
        .walletListRow()
        // Where Privacy Pools' and Railgun's Library tiles land (prd §1738).
        .id(ShellChrome.privateAnchor)
        .task(id: chrome.walletScrollRequest) {
            guard chrome.walletScrollRequest == ShellChrome.privateAnchor else { return }
            try? await Task.sleep(for: .milliseconds(300))
            cardScrollTarget = ShellChrome.privateAnchor
            chrome.walletScrollRequest = nil
        }
    }

    /// One token in one state on one network: the preview row's anatomy
    /// (`walletPreviewRow`) with a line under the name — the network for
    /// private money, the state for the rest.
    private func walletPrivateRow(_ row: PrivateMoney.Row, mask: String?, prices: [String: Double]) -> some View {
        let figure = mask ?? PrivateMoney.rowUSD(row, prices: prices).map(WalletValue.money)
            ?? PrivateMoney.figure(row.amount, decimals: row.decimals, symbol: row.symbol)
        let (glyph, hue, state, stateInk): (String?, Color, String, Color) = switch row.kind {
        // What earns says so, in the one Holdings grammar (prd §1718,
        // network · fact · place): "Ethereum · 3.8% on Aave · Privacy Pools";
        // the rate unread, "Ethereum · On Aave · Privacy Pools".
        case .held: (nil, DS.textSecondary, PrivateMoneyStore.shared.heldLine(row), DS.textSecondary)
        case .waiting: ("clock", DS.attention, String(localized: "Waiting for approval"), DS.attentionInk)
        case .refused: ("xmark.circle", DS.destructive, String(localized: "Not approved"), DS.destructiveInk)
        }
        return Button { walletOpenPrivate(.send) } label: {
            HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                Group {
                    if let glyph {
                        Image(systemName: glyph)
                            .dsGlyph(.body, weight: .regular)
                            .foregroundStyle(hue)
                    } else {
                        AssetMark(name: row.symbol, size: DS.Mark.badge)
                    }
                }
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    // The line's words carry the place, last (prd §1718,
                    // amending §1700f item 9's mark beside them): "Ethereum ·
                    // 1.5% on Aave · Privacy Pools". No small mark, which read
                    // as a second token. A waiting or refused deposit keeps
                    // its state word alone.
                    Text(verbatim: state)
                        .dsText(.subhead12)
                        .foregroundStyle(stateInk)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                walletRowFigure(figure, tone: row.kind == .held ? DS.textPrimary : DS.textSecondary)
            }
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: [row.title, state, figure].joined(separator: ". ")))
        .accessibilityHint(Text("Sends from your private balance"))
        .walletListRow()
    }
}

/// **WAITING FOR APPROVAL, IN NEEDS YOU (prd §1561).** One row per deposit
/// 0xBow's ASP has not approved, as the board drew it: the amber clock,
/// "0.0001 ETH waiting for approval", "Since 2:14 PM"; it leaves when
/// approved. Refused (or `poi_required`), the row turns red — "0.0001 ETH not
/// approved" — and its line is the act, "Take it back": the ragequit, a public
/// exit to the address the deposit came from (`PrivateTakeBack`), proved,
/// run against the chain, then signed. A deposit that has waited past a week
/// offers it too, after its date. The verb is a word, never a pill; nothing
/// explains it but the dialog that names where the money goes.
struct WalletPrivateAsks: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var confirming: PrivateMoney.Ask?

    private var store: PrivateMoneyStore { .shared }
    private var taking: PrivateTakeBack { .shared }

    var body: some View {
        let asks = store.asks()
        if !asks.isEmpty {
            Section {
                ForEach(asks) { ask in row(ask) }
            }
            .task(id: asks.map(\.id)) {
                // The ASP is asked again while a row stands (spaced 20 s);
                // every root's notes on their cadence, and what was sent and
                // not seen asked about (the review of 2026-10-26, finding 2).
                while PrivateMoney.anyWaiting(store.notes), !Task.isCancelled {
                    await PrivateWatch.findNotes(context: context)
                    await store.refresh()
                    try? await Task.sleep(for: .seconds(20))
                }
            }
            .confirmationDialog(confirming.map { Text("Take back \($0.figure)?") } ?? Text(verbatim: ""),
                                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { ask in
                Button(String(localized: "Take it back")) { takeBack(ask) }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { ask in
                // Where it goes, on the network it is on, and what it gives up.
                Text(ask.note.chainId == PrivacyNetwork.ethereum.chainId
                     ? String(localized: "It goes back to your account on Ethereum, in public. This deposit won't be private.")
                     : String(localized: "It goes back to \(Self.owner) on Sepolia, in public."))
            }
        }
    }

    /// Where a ragequit pays: the account's owner, by its tail.
    private static var owner: String {
        #if DEBUG
        PrivacyTestnetSender.address.map(YourAccount.short) ?? String(localized: "the address it came from")
        #else
        String(localized: "the address it came from")
        #endif
    }

    private func row(_ ask: PrivateMoney.Ask) -> some View {
        let stage = taking.stage(ask.note)
        let working = stage.map { if case .failed = $0 { false } else { true } } ?? false
        return DSPushRow(title: Text(verbatim: ask.title), subtitle: line(ask, stage: stage),
                         subtitleTone: DS.textSecondary, busy: working, opens: false) {
            guard !working else { return }
            if ask.canTakeBack {
                confirming = ask
            } else if !ask.note.tx.isEmpty, let link = URL(string: PrivateMoney.explorerTx(ask.note.tx, chainId: ask.note.chainId)) {
                openURL(link)
            }
        } leading: {
            ZStack {
                Color.clear.frame(width: DS.Face.row, height: DS.Face.row)
                Image(systemName: ask.kind == .refused ? "xmark.circle" : "clock")
                    .dsGlyph(.body, weight: .semibold)
                    .foregroundStyle(ask.kind == .refused ? DS.destructive : DS.attention)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(ask.canTakeBack ? Text("Returns it to the address it came from") : Text(verbatim: ""))
        .walletListRow()
    }

    /// The line: where the take-back stands, else the date it has waited
    /// since and, where it is offered, the act.
    private func line(_ ask: PrivateMoney.Ask, stage: PrivateTakeBack.Stage?) -> Text {
        if let stage {
            if case .failed = stage {
                return Text(verbatim: PrivateTakeBack.words(stage)).foregroundStyle(DS.attentionInk)
            }
            return Text(verbatim: PrivateTakeBack.words(stage))
        }
        let act = Text("Take it back").foregroundStyle(ask.kind == .refused ? DS.destructiveInk : DS.pickInk)
        switch (ask.kind, ask.canTakeBack) {
        case (.refused, _): return act
        case (.waiting, true): return Text(verbatim: PrivateMoney.since(ask.note.at, now: .now) + " · ") + act
        case (.waiting, false): return Text(verbatim: PrivateMoney.since(ask.note.at, now: .now))
        }
    }

    private func takeBack(_ ask: PrivateMoney.Ask) {
        Task {
            guard let hash = await taking.run(ask.note, context: context) else { return }
            DSHaptic.success()
            chrome.flash(PrivateMoney.takenBackTitle(figure: ask.figure, to: Self.owner), tone: .success)
            chrome.refreshRooms()
            NSLog("privateTakeBack| row | %@", hash)
        }
    }
}
