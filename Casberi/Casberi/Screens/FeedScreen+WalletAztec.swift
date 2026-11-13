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
                aztecRow(title: holding.name, line: "Aztec",
                         figure: mask ?? store.usd(holding, units: holding.privateUnits).map(WalletValue.money)
                             ?? Self.aztecFigure(holding, units: holding.privateUnits),
                         mark: holding.name, tone: DS.textPrimary)
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
                walletPlaceRow(String(localized: "Your private balance"), line: "Aztec", mark: nil,
                               hint: String(localized: "Sends to your private balance on Aztec")) {
                    chrome.moveAztec = .deposit
                    chrome.moveTray = true
                }
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
                let units = gas ? NSDecimalNumber(decimal: holding.gasUnits).stringValue : holding.publicUnits
                // Network · fact (prd §1718): "Aztec · Gas"; a public token,
                // "Aztec" alone, as the Tokens rows above it name theirs.
                aztecRow(title: holding.name,
                         line: gas ? Self.gasLine(AztecGas.state) : "Aztec",
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
                // The figure says None; the line does not say it twice.
                aztecRow(title: "Fee Juice", line: Self.gasLine(AztecGas.state == .none ? .enough : AztecGas.state),
                         figure: String(localized: "None"), mark: "AZTEC", tone: DS.attentionInk,
                         act: { feedSheet = .aztecGas })
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
    static func gasLine(_ state: AztecGas.Standing) -> String {
        guard let word = AztecGasTray.word(state) else { return String(localized: "Aztec · Gas") }
        return String(localized: "Aztec · Gas") + " · " + word.words
    }

    @ViewBuilder
    private func aztecRow(title: String, line: String, figure: String, mark: String?, tone: Color,
                          arriving: Bool = false, act: (() -> Void)? = nil) -> some View {
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
                    AssetMark(name: mark, size: DS.Mark.badge)
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
                Text(verbatim: line)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
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
    /// authorization: the app, the call and who may make it, and Take back.
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
                    chrome.flash(String(localized: "Taken back"))
                } catch {
                    chrome.flash(AztecEngine.words(error))
                }
            }
        } label: {
            Text(verbatim: inFlight ? String(localized: "Taking back…") : String(localized: "Take back"))
                .dsText(.body17)
                .foregroundStyle(store.takingBack == nil ? DS.pickInk : DS.textTertiary)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 44)
        }
        .buttonStyle(RowPress())
        .disabled(store.takingBack != nil || DemoMode.isActive)
        .layoutPriority(1)
        .accessibilityLabel(Text("Take back \(AztecAppsShape.name(host: grant.host))'s authorization"))
    }

    /// Your account's accounts (§1700a item 1): once the Aztec account's
    /// address is known (§1700t), the card lists both — the Safe, then Aztec — by their own
    /// names, the line under each saying how it works and its address's tail
    /// ("Public · …c8e01", "Private · …2b3c"; user, 2026-11-04: "do as you
    /// recommend"). Not "Public/Private account": 0xBow's private balance is a
    /// third private place, and Aztec can hold public balances too. Before
    /// Aztec is used the box above already names the Safe, so no list is drawn.
    @ViewBuilder
    func walletAccountList(safe: String) -> some View {
        let store = AztecAccountStore.shared
        if store.isShown, let aztec = store.shown.address {
            // Each row picks the address Your Account's header shows (prd
            // §1700f item 2): the lit one is the one showing.
            accountListRow(mark: "safe", title: String(localized: "Safe"),
                           line: String(localized: "Public · \(AddressTail.short(safe))"),
                           lit: !chrome.yourAccountShowsAztec) { chrome.yourAccountShowsAztec = false }
            accountListRow(mark: "aztec", title: String(localized: "Aztec"),
                           line: String(localized: "Private · \(AddressTail.short(aztec))"),
                           lit: chrome.yourAccountShowsAztec) { chrome.yourAccountShowsAztec = true }
        } else if store.isShown, !DemoMode.isActive, AztecProver.isAvailable {
            // The account is yours from the start (prd §1700t) but its
            // address comes from the engine: read it once, here, and keep it.
            Color.clear.frame(height: 0).task { _ = await store.refresh() }
        }
    }

    /// The Holdings row's anatomy: the mark, the name over its line; the lit
    /// row's name in the primary ink, the other's secondary.
    private func accountListRow(mark: String, title: String, line: String, lit: Bool,
                                pick: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { pick() }
        } label: {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            ProtocolInlineMark(mark: mark)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .foregroundStyle(lit ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
                Text(verbatim: line)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .walletRowPitch()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(lit ? .isSelected : [])
        .accessibilityHint(Text("Shows its address above"))
        .walletStackRow()
    }
}
