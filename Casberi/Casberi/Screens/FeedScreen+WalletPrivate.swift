import SwiftUI

/// **PRIVATE, IN HOLDINGS (prd §1554).** Under Tokens, Holdings only SHOWS
/// what is private: a head naming it with its total, then one row per token,
/// state and network off the notes Move to private kept (`PrivateMoney.rows`)
/// — "ETH, private" over "1.0% on Aave" where it earns (Ethereum's yield
/// pools, the rate read live, prd §1563) or its network ("Sepolia", which has
/// no Aave), "ETH, moving in" with the amber clock and
/// "Waiting for approval", "ETH, not approved". The Tokens rows above are
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
        // account's, never a followed wallet's.
        if selectedSeat == nil, !walletOnFollowing, selectedWallet.map(YourAccountDemo.isYours) ?? true,
           PrivateMove.available || !rows.isEmpty {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            Group {
                walletPrivateHead(total: mask ?? walletPrivateTotal(rows, prices: store.prices))
                    .task(id: rows.map(\.id)) {
                        await store.refresh()
                        await store.readPrices()
                        await store.readYield()
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
                    walletPrivateRow(row, mask: mask, prices: store.prices)
                }
            }
        }
    }

    /// The section's total: the private dollars, as the box counts them; with
    /// none to count (test money, §949), one token's quantity, else nothing.
    private func walletPrivateTotal(_ rows: [PrivateMoney.Row], prices: [String: Double]) -> String? {
        let held = rows.filter { $0.kind == .held }
        let usd = held.compactMap { PrivateMoney.rowUSD($0, prices: prices) }
        if !usd.isEmpty { return WalletValue.money(usd.reduce(0, +)) }
        guard held.count == 1, let only = held.first else { return nil }
        return PrivateMoney.figure(only.amount, decimals: only.decimals, symbol: only.symbol)
    }

    /// Opens Send privately (prd §1554): to your private balance from the
    /// header, from it (the switch on) from a row.
    private func walletOpenPrivate(_ mode: PrivateMove.Mode) {
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
    }

    /// One token in one state on one network: the preview row's anatomy
    /// (`walletPreviewRow`) with a line under the name — the network for
    /// private money, the state for the rest.
    private func walletPrivateRow(_ row: PrivateMoney.Row, mask: String?, prices: [String: Double]) -> some View {
        let figure = mask ?? PrivateMoney.rowUSD(row, prices: prices).map(WalletValue.money)
            ?? PrivateMoney.figure(row.amount, decimals: row.decimals, symbol: row.symbol)
        let (glyph, hue, state, stateInk): (String?, Color, String, Color) = switch row.kind {
        // What earns says so, the rate read live (prd §1563); else the network.
        case .held: (nil, DS.textSecondary, PrivateMoneyStore.shared.yieldLine(row) ?? PrivateMoney.network(row.chainId), DS.textSecondary)
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
