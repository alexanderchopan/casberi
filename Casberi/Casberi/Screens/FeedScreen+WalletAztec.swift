import SwiftUI

/// **YOUR AZTEC ACCOUNT IN THE WALLET (prd §1700, §1700a).** Two places, both
/// shown only once the account has been used (§1700a item 2):
///   - Holdings › Private, after 0xBow's private balance: one row per thing the
///     account holds (Fee Juice, and each token an app taught the wallet), its
///     line saying private or public on Aztec with Aztec's mark (§1685). Two
///     private places on purpose, never merged (§1700 item 4).
///   - Your account, beside the Safe: the Aztec account and its address's tail.
/// Shield's USDC and WETH in dollars, counted once in the Wallet's total as
/// one Aztec block (`AztecAccountStore.walletHolding`); Fee Juice, and any
/// token without a price, as an amount only.
extension FeedScreen {

    /// How long a reading stands before showing the place reads again.
    static let aztecReadInterval: TimeInterval = 5 * 60

    /// Whether the Aztec account's rows stand here: Yours and All only, as
    /// private money (prd §1590): the account is yours.
    var walletShowsAztec: Bool {
        AztecAccountStore.shared.isShown && selectedSeat == nil && !walletOnFollowing
            && (selectedWallet.map(YourAccountDemo.isYours) ?? true)
    }

    /// **PRIVATE ON AZTEC, UNDER PRIVATE (prd §1700 item 4).** Only what the
    /// account holds privately; what it holds in the open stands under Tokens
    /// (`walletAztecPublicRows`; user, 2026-11-04: "Fee Juice has to move to
    /// tokens i would think because it is public").
    @ViewBuilder
    var walletAztecRows: some View {
        if walletShowsAztec {
            let store = AztecAccountStore.shared
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            // Network · fact · place (prd §1718): on Aztec the network is the
            // place, so the line is the one word.
            ForEach(store.privateHeld) { holding in
                let figure = mask ?? store.usd(holding, units: holding.privateUnits).map(WalletValue.money)
                    ?? Self.aztecFigure(holding, units: holding.privateUnits)
                // Its page, Send from Aztec on it (user, 2026-11-21: "yes i
                // guess it should open send"); the row did nothing.
                let page = WalletHolding(id: "aztec:\(holding.id)", symbol: holding.name, figure: figure,
                                         usd: mask == nil ? store.usd(holding, units: holding.privateUnits) : nil,
                                         line: "Aztec", aztec: true, verbs: [.aztecSend])
                aztecRow(title: holding.name, line: "Aztec", figure: figure, mark: holding.name, tone: DS.textPrimary,
                         page: page, act: { walletOpenHolding(page) })
            }
            .background { aztecReading }
            // NFTs you hold privately (prd §1766): one row a collection, its
            // name, how many, never a price.
            ForEach(store.nftsHeld) { holding in
                aztecRow(title: holding.name, line: "Aztec · " + String(localized: "NFT"),
                         figure: mask ?? Self.nftFigure(holding), mark: nil, tone: DS.textPrimary)
            }
            // On its way in (prd §1700ac): one grey row per deposit Aztec has
            // not handed over, behind a clock, as Railgun's unlisted money is
            // (§1713 item 5) — a state, nobody waiting on you, never amber.
            ForEach(store.arriving) { deposit in
                aztecRow(title: deposit.symbol, line: "Aztec · " + String(localized: "On its way"),
                         figure: mask ?? store.usd(deposit).map(WalletValue.money) ?? AztecAccountStore.figure(deposit),
                         mark: nil, tone: DS.textSecondary, arriving: true)
            }
            .background { aztecArriving }
            // Empty, the place stands where its rows will (prd §1718, §769):
            // Aztec, saying what it takes, its tap Move's sentence to your
            // private account on Aztec.
            if store.privateHeld.isEmpty, store.arriving.isEmpty {
                walletPlaceRow("Aztec", line: String(localized: "Aztec to Aztec only"), mark: nil,
                               hint: String(localized: "Sends to Aztec")) {
                    chrome.moveAztec = .deposit
                    chrome.moveTray = true
                }
            }
        }
    }

    /// What Aztec has not handed over yet, for Home's On its way (prd §1779):
    /// the same grey rows Holdings draws.
    @ViewBuilder
    var walletAztecArrivingRows: some View {
        if walletShowsAztec {
            let store = AztecAccountStore.shared
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            ForEach(store.arriving) { deposit in
                aztecRow(title: deposit.symbol, line: "Aztec · " + String(localized: "On its way"),
                         figure: mask ?? store.usd(deposit).map(WalletValue.money) ?? AztecAccountStore.figure(deposit),
                         mark: nil, tone: DS.textSecondary, arriving: true)
            }
        }
    }

    /// **PUBLIC ON AZTEC, UNDER TOKENS.** Fee Juice first: AZTEC made gas,
    /// public on Aztec by design, wearing AZTEC's mark ("it should be the
    /// Aztec token"), its amount alone and never in dollars or the total —
    /// it can be spent only on fees and goes nowhere else (user: "ok" to
    /// that). Then any token held in the open, in dollars where priced.
    @ViewBuilder
    var walletAztecPublicRows: some View {
        if walletShowsAztec {
            let store = AztecAccountStore.shared
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            ForEach(store.publicHeld) { holding in
                let gas = holding.kind == .feeJuice
                // Gas is one figure wherever it is kept (prd §1700aa): the
                // account's own and what it holds in the private fee contract.
                // And what Aztec has carried for the next send to mint (prd §1886).
                let units = gas ? NSDecimalNumber(decimal: holding.gasUnits + AztecGas.carried(store.snapshot.gas ?? [])).stringValue
                    : holding.publicUnits
                // Network · fact (prd §1718): "Aztec · Gas"; a public token,
                // "Aztec" alone, as the Tokens rows above it name theirs.
                aztecRow(title: holding.name,
                         // A row holding gas never says None (prd §1862, §83).
                         line: gas ? Self.gasLine(Self.gasStanding(units)) : "Aztec",
                         figure: mask ?? (gas ? nil : store.usd(holding, units: units).map(WalletValue.money))
                             ?? Self.aztecFigure(holding, units: units),
                         // Grey, as every Tokens row's figure is.
                         mark: gas ? "AZTEC" : holding.name, tone: DS.textSecondary,
                         // The gas row opens Gas on Aztec (prd §1761).
                         act: gas ? { feedSheet = .aztecGas } : nil)
            }
            .background { aztecReading }
            // An account in use that holds no gas still shows where gas is
            // added (prd §1761): the row stood only once there was some.
            if store.shown.used, !store.publicHeld.contains(where: { $0.kind == .feeJuice }) {
                let carried = AztecGas.carried(store.snapshot.gas ?? [])
                if carried > 0 {
                    // Carried and waiting for the next send to mint it (prd
                    // §1886): gas you hold, never None.
                    aztecRow(title: "Fee Juice", line: Self.gasLine(AztecGas.state),
                             figure: mask ?? Self.gasFigure(carried), mark: "AZTEC", tone: DS.textSecondary,
                             act: { feedSheet = .aztecGas })
                } else {
                    // The figure says None; the line does not say it twice.
                    aztecRow(title: "Fee Juice", line: Self.gasLine(AztecGas.state == .none ? .enough : AztecGas.state),
                             figure: String(localized: "None"), mark: "AZTEC", tone: DS.attentionInk,
                             act: { feedSheet = .aztecGas })
                }
            }
        }
    }

    /// The account read again when its last reading is old (never in the
    /// demo, whose account is sample data), and the rows' prices.
    private var aztecReading: some View {
        let store = AztecAccountStore.shared
        return Color.clear.task(id: store.shown.address) {
            _ = await store.walletHolding() // the demo's prices are its own
            guard !DemoMode.isActive else { return }
            let stale = store.snapshot.readAt.map { Date().timeIntervalSince($0) > Self.aztecReadInterval } ?? true
            if stale, AztecProver.isAvailable {
                await store.refresh()
                _ = await store.walletHolding()
            }
        }
    }

    /// What Aztec has carried is claimed while its row stands, asked again
    /// every half minute (prd §1700ac); the row leaves with the claim.
    private var aztecArriving: some View {
        Color.clear.task {
            while !AztecAccountStore.shared.arriving.isEmpty, !Task.isCancelled {
                await AztecArrivals.settle()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// The amount alone, at most two places (the row's title already names
    /// the token; user, 2026-11-04: "it shouldn't say it where the balance of
    /// it is. i also don't like all the decimals"): "28.54". Less than a
    /// hundredth keeps the places it needs to show something ("0.0042").
    /// The token's name alone when its decimals are unknown, never a guess.
    static func aztecFigure(_ holding: AztecAccountStore.Holding, units: String?) -> String {
        guard let decimals = holding.decimals else { return holding.name }
        let amount = (units.flatMap { Decimal(string: $0) } ?? 0) / pow(10, decimals)
        if amount > 0, amount < Decimal(string: "0.01")! {
            return amount.formatted(.number.precision(.significantDigits(1...2)))
        }
        return amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Holdings' row anatomy (`walletPrivateRow`), with no act: nothing opens
    /// until Aztec has its sends (§1700 step 4), so it is not a button.
    /// A collection's figure: its one token's number, else how many, with a
    /// plus when more were held than were read (prd §1766).
    static func nftFigure(_ holding: AztecAccountStore.Holding) -> String {
        let ids = holding.ids ?? []
        if ids.count == 1, holding.more != true, let only = ids.first, only.count <= 8 { return "#" + only }
        return "\(ids.count)" + (holding.more == true ? "+" : "")
    }

    /// The gas row's line: the place and the fact (prd §1718), and how the
    /// gas stands when that needs saying (prd §1761).
    /// How the gas stands for a row that holds `units`: "None" only when it
    /// holds none.
    /// Fee Juice in base units (18 places), as the gas row draws it.
    static func gasFigure(_ units: Decimal) -> String {
        let amount = units / pow(10, 18)
        if amount > 0, amount < Decimal(string: "0.01")! {
            return amount.formatted(.number.precision(.significantDigits(1...2)))
        }
        return amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func gasStanding(_ units: String?) -> AztecGas.Standing {
        let held = (units.flatMap { Decimal(string: $0) } ?? 0) > 0
        return held && AztecGas.state == .none ? .enough : AztecGas.state
    }

    @MainActor static func gasLine(_ state: AztecGas.Standing) -> String {
        // Private gas is said so (user, 2026-11-19): what the private fee
        // contract holds pays the next send without naming the account.
        let name = AztecGas.paysPrivately ? String(localized: "Aztec · Private gas") : String(localized: "Aztec · Gas")
        guard let word = AztecGasTray.word(state) else { return name }
        return name + " · " + word.words
    }

    @ViewBuilder
    private func aztecRow(title: String, line: String, figure: String, mark: String?, tone: Color,
                          arriving: Bool = false, page: WalletHolding? = nil, act: (() -> Void)? = nil) -> some View {
        if let act {
            Button {
                DSHaptic.selection()
                act()
            } label: {
                aztecRowLabel(title: title, line: line, figure: figure, mark: mark, tone: tone, arriving: arriving)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .dsHover()
            .contextMenu { if let page { walletHoldingMenu(page) } }
            .walletListRow()
        } else {
            aztecRowLabel(title: title, line: line, figure: figure, mark: mark, tone: tone, arriving: arriving)
                .walletListRow()
        }
    }

    private func aztecRowLabel(title: String, line: String, figure: String, mark: String?, tone: Color,
                               arriving: Bool) -> some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            Group {
                if arriving {
                    Image(systemName: "clock").dsGlyph(.body, weight: .regular).foregroundStyle(DS.textSecondary)
                } else if let mark {
                    AssetMark(name: mark, size: DS.Mark.row)
                } else {
                    ProtocolInlineMark(mark: "aztec")
                }
            }
            .frame(width: DSRoomChassis.headGlyph)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                // The line's word carries the place (prd §1718): no small
                // mark beside it.
                // Aztec's own ink on its line (prd §1779): a different world, seen in the list.
                Text(verbatim: line)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.aztecInk)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            walletRowFigure(figure, tone: tone)
        }
        .walletRowPitch()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [title, line, figure].joined(separator: ". ")))
    }

    // MARK: - Authorizations given to Aztec apps (prd §1762)

    /// Whether the authorizations stand here: where the Aztec account does.
    var walletShowsAztecGrants: Bool {
        walletShowsAztec && !AztecGrantsStore.shared.grants.isEmpty
    }

    /// **WHAT AZTEC APPS MAY STILL DO IN YOUR NAME (prd §1762).** One row an
    /// authorization: the app, the call and who may make it, and Revoke: the
    /// app's word for a permission taken away (user, 2026-11-12: "revoke
    /// permissions"). "Take back" is Lend's word, for money.
    /// Read against Aztec's registry when the page appears, so one an app
    /// has used is gone.
    @ViewBuilder
    var walletAztecGrantsSection: some View {
        if walletShowsAztecGrants {
            let store = AztecGrantsStore.shared
            walletCard(String(localized: "Aztec apps"), glyph: "checkmark.seal", anchor: "aztecGrants") {
                ForEach(store.grants) { grant in
                    HStack(spacing: DS.Space.s3) {
                        Group {
                            if let icon = AztecAppsStore.shared.icons[grant.host] {
                                Image(uiImage: icon).resizable().scaledToFill()
                                    .frame(width: DS.Face.list, height: DS.Face.list)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Face.list * 0.2237, style: .continuous))
                            } else {
                                ProtocolInlineMark(mark: "aztec")
                            }
                        }
                        .frame(width: DS.Face.list)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: AztecAppsShape.name(host: grant.host))
                                .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                            Text(verbatim: AztecGrantsShape.line(grant))
                                .dsText(.subhead12).foregroundStyle(DS.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: DS.Space.s2)
                        aztecTakeBackWord(grant)
                    }
                    .walletRowPitch()
                    .walletListRow()
                }
                .task { await store.refresh() }
            }
        }
    }

    /// The row's one act, in the pick's ink as Revoke is (prd §1385).
    private func aztecTakeBackWord(_ grant: AztecGrantsShape.Grant) -> some View {
        let store = AztecGrantsStore.shared
        let inFlight = store.takingBack == grant.hash
        return Button {
            DSHaptic.selection()
            Task {
                do {
                    try await store.takeBack(grant)
                    chrome.flash(String(localized: "Revoked"))
                } catch {
                    chrome.flash(AztecEngine.words(error))
                }
            }
        } label: {
            Text(verbatim: inFlight ? String(localized: "Revoking…") : String(localized: "Revoke"))
                .dsText(.body17)
                .foregroundStyle(store.takingBack == nil ? DS.pickInk : DS.textTertiary)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 44)
        }
        .buttonStyle(RowPress())
        .disabled(store.takingBack != nil || DemoMode.isActive)
        .layoutPriority(1)
        .accessibilityLabel(Text("Revoke \(AztecAppsShape.name(host: grant.host))'s authorization"))
    }

    /// **THE PRIVATE PLACES ARE DOORS (prd §1786, of a canvas: "Build and
    /// ship").** Under Account's box, which is always the Safe: your private
    /// balance, whose address is new each time, and your private account,
    /// whose address stands on its own page in Aztec's ink and nowhere here.
    /// Someone who came to copy an address copies the public one.
    @ViewBuilder
    func walletPrivatePlaces() -> some View {
        let store = AztecAccountStore.shared
        let aztec = store.isShown ? store.shown.address : nil
        // **YOUR PRIVATE ACCOUNTS (prd §1946):** each its name, where it is,
        // and the copy glyph for its address. Privacy Pools' address is made
        // new each time; Railgun's is your one 0zk address; Aztec's is paid
        // from Aztec only, which the copy says (prd §1779).
        if PrivateMove.freshAvailable {
            // Watched on Base, Ethereum and Robinhood (prd §1878).
            AccountCopyRow(name: "Privacy Pools", line: AccountNetworks.on(ReceivePools.names), copy: {
                guard !DemoMode.isActive else { chrome.flash(YourAccountDemo.actsLater); return }
                guard let entry = FreshReceive.shared.unusedCurrent() else {
                    chrome.flash(FreshReceive.shared.failure ?? String(localized: "No new address could be made"), tone: .failure)
                    return
                }
                DSPasteboard.copy(entry.address)
                chrome.flash(String(localized: "Copied · new address each time"), tone: .success)
            })
        }
        if RailgunPocket.available, PrivateMove.freshAvailable {
            AccountCopyRow(name: "Railgun", line: AccountNetworks.on(["Ethereum"]), copy: {
                Task { @MainActor in
                    let address = DemoMode.isActive ? ReceiveDemo.privateAddress
                        : try? await RailgunPocket.privateAddress()
                    guard let address else { chrome.flash(String(localized: "Railgun did not answer"), tone: .failure); return }
                    DSPasteboard.copy(address)
                    chrome.flash(String(localized: "Address copied"), tone: .success)
                }
            })
        }
        // The account is yours from the start (prd §1700t): its line stands
        // from the first frame; its copy waits on the address it reads.
        if store.isShown {
            AccountCopyRow(name: "Aztec", line: AccountNetworks.on(["Aztec"]), ink: DS.aztecInk,
                           copy: aztec.map { address -> () -> Void in {
                               if DemoMode.isActive { chrome.flash(YourAccountDemo.actsLater); return }
                               DSPasteboard.copy(address)
                               chrome.flash(String(localized: "Copied · paid from Aztec only"), tone: .success)
                           } })
        }
        if store.isShown, aztec == nil, !DemoMode.isActive, AztecProver.isAvailable {
            // Its address comes from the engine: read it once, here, and keep it.
            Color.clear.frame(height: 0).task { _ = await store.refresh() }
        }
    }

    /// Whether Account has a private place to list.
    var walletHasPrivatePlaces: Bool {
        PrivateMove.freshAvailable || AztecAccountStore.shared.isShown
    }
}
