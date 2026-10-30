import SwiftUI

/// **SAFE AND 0XBOW PRIVACY POOLS, AS YOUR ACCOUNT'S OWN (prd §1614).** Your
/// account is a Safe and your private balance is 0xBow's Privacy Pools v2,
/// so each pick shows your money in it: the box (`WalletSafeBox`,
/// `WalletPoolsBox`) and one section under Home's doors — "Without a
/// signature" (what can move each Safe with nobody signing) and "How hidden"
/// (how many deposits each private balance sits among, and when a send from
/// it would be easy to link).
extension FeedScreen {

    /// Whether the pick is one of the two whose Home carries its own section.
    var walletPickHasOwnSection: Bool {
        guard let source = selectedSeat?.source else { return false }
        return source == SafeBridge.sourceName || source == PrivacyPoolsBridge.sourceName
    }

    /// The box's money, masked under Hide balances; nil before a read.
    var walletBoxTotal: String? {
        // The demo's account is not in the demo's read; a real one is (§1442l).
        let demoAccount = DemoMode.isActive && selectedSeat?.source == SafeBridge.sourceName
            ? YourAccountDemo.totalUSD : 0
        let total = (portfolioShown?.totalUSD ?? 0) + demoAccount
        guard total > 0 else { return nil }
        return BalancePrivacy.shared.withheld ? BalancePrivacy.mask : WalletValue.money(total)
    }

    /// The Safe rows' ids and tags: a landed, signed or gone transaction
    /// changes it, so the Safe box reads its queue again.
    static func safeQueueKey(_ visible: [Thing]) -> Int {
        var hasher = Hasher()
        for thing in visible where thing.isLive && thing.source == SafeBridge.sourceName {
            hasher.combine(thing.sourceRef)
            hasher.combine(thing.tags)
        }
        return hasher.finalize()
    }

    /// A Safe's door: your account's keys, or the Safe's own app.
    func walletOpenSafe(_ safe: SafeRoster.Safe) {
        if safe.isYourAccount {
            chrome.walletSection = .yourAccount
        } else if let seg = safe.seg, let url = SafeBridge.webURL(seg: seg, safeAddress: safe.address) {
            openExternal(url)
        }
    }

    /// Opens Move's private sentence (prd §1554).
    func walletMovePrivately(_ mode: PrivateMove.Mode) {
        DSHaptic.selection()
        chrome.movePrivately = mode
        chrome.moveTray = true
    }

    // MARK: - The 0xBow box

    var walletPoolsBox: some View {
        let store = PrivacyPoolsReading.store
        let rows = store.rows
        let earning = rows.lazy.compactMap { store.yieldLine($0) }.first
            .map { String(localized: "Earning \($0)") }
        return WalletPoolsBox(split: PoolsSplit.compose(rows, store: store),
                              mask: BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil,
                              earning: earning,
                              canMove: PrivateMove.available,
                              onMove: { walletMovePrivately(.deposit) })
            .task { await PrivacyPoolsReading.refresh() }
    }

    // MARK: - Home's own section

    @ViewBuilder
    var walletPickSection: some View {
        switch selectedSeat?.source {
        case SafeBridge.sourceName?:
            WalletUnsignedSection(onOpenSafe: walletOpenSafe, queueKey: Self.safeQueueKey(visible))
        case PrivacyPoolsBridge.sourceName?: walletHiddenSection
        default: EmptyView()
        }
    }

    // MARK: - How hidden

    @ViewBuilder
    private var walletHiddenSection: some View {
        let store = PrivacyPoolsReading.store
        let counts = PrivacyPoolsCrowd.counts()
        // One row per token and network: money waiting to move in hides in
        // the same pool as what is already there.
        let held = store.rows.filter { $0.kind != .refused }
            .reduce(into: [PrivateMoney.Row]()) { out, row in
                if !out.contains(where: { $0.symbol == row.symbol && $0.chainId == row.chainId }) { out.append(row) }
            }
        walletCard(String(localized: "How hidden"), glyph: "eye.slash") {
            if held.isEmpty {
                // The pools you could move into, each with its crowd and rate.
                if PrivateMove.available {
                    ForEach(["ETH", "USDC"], id: \.self) { symbol in
                        walletPreviewRow(String(localized: "\(symbol) on Ethereum"),
                                         figure: PrivacyPoolsCrowd.crowd(symbol: symbol, chainId: 1, counts: counts)
                                            .map(Self.crowdWords),
                                         act: { walletMovePrivately(.deposit) }) {
                            AssetMark(name: symbol, size: DS.Mark.badge)
                        }
                    }
                }
            } else {
                ForEach(held) { row in
                    let notes = store.shownNotes
                        .filter { $0.symbol == row.symbol && $0.chainId == row.chainId && PrivateMoney.kind($0.status) != .refused }
                    let soon = PrivacyPoolsCrowd.tooSoon(newest: notes.map(\.at).max())
                    // The smallest crowd any of its notes is in: the honest one.
                    let crowd = notes.compactMap {
                        PrivacyPoolsCrowd.crowd(symbol: row.symbol, chainId: row.chainId, share: $0.share,
                                                plain: $0.share == nil, counts: counts)
                    }.min()
                    walletPreviewRow(String(localized: "\(row.symbol) on \(PrivateMoney.network(row.chainId))"),
                                     figure: soon ? String(localized: "Wait a day") : crowd.map(Self.crowdWords),
                                     tone: soon ? DS.attentionInk : DS.textSecondary,
                                     act: { walletMovePrivately(.send) }) {
                        AssetMark(name: row.symbol, size: DS.Mark.badge)
                    }
                }
            }
        }
    }

    /// "Among 170": the deposits a balance hides among.
    static func crowdWords(_ count: Int) -> String {
        String(localized: "Among \(count.formatted())")
    }
}

/// The 0xBow pick's reads, started where its box stands: the notes and their
/// approval, prices, rates, and the crowd (once a day).
@MainActor
enum PrivacyPoolsReading {
    static var store: PrivateMoneyStore { PrivateMoneyStore.shared }

    static func refresh() async {
        // The crowd first: one small read, where the rest wait on prices.
        await PrivacyPoolsCrowd.refresh()
        await store.refresh()
        await store.readPrices()
        await store.readYield()
    }
}

/// **WITHOUT A SIGNATURE (prd §1614):** each Safe you hold a key to, and what
/// can move it with nobody signing. Your account's spend limit is a module
/// that spends without asking, so it is stated in money; a Safe with no
/// module says None; a module on another Safe is red. A row opens the Safe.
struct WalletUnsignedSection: View {
    var onOpenSafe: (SafeRoster.Safe) -> Void
    /// The queue's rows, so a signature landing re-reads whether the box is busy.
    var queueKey: Int = 0
    /// Read from the first frame (stored reads, no network), so the header
    /// never stands without its rows.
    @State private var roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
    /// Whether the box is the queue, which hides the roster it lists at rest.
    @State private var busy = Self.queueWaitsOnYou()

    var body: some View {
        if !roster.isEmpty {
            // **YOUR SAFES WHILE THE BOX IS BUSY (prd §1614a).** The box turns
            // into the queue when a signature waits on you, and the Safes it
            // listed at rest would be out of reach until you sign: they stand
            // here instead, each with its keys and how many must sign.
            if busy { yourSafes }
            section
        }
    }

    private static func queueWaitsOnYou() -> Bool {
        SafeRoomSource.compose()?.entries.contains(where: \.yourTurn) ?? false
    }

    private var yourSafes: some View {
        SectionPanelGroup(anchor: nil) {
            SectionPanelName(name: String(localized: "Your Safes"), glyph: "person.badge.key")
        } rows: {
            Section {
                ForEach(roster.safes) { safe in
                    Button {
                        DSHaptic.selection()
                        onOpenSafe(safe)
                    } label: {
                        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                            Image(systemName: safe.isYourAccount ? "person.crop.circle" : "person.2")
                                .dsGlyph(.body)
                                .foregroundStyle(DS.textSecondary)
                                .frame(width: DSRoomChassis.headGlyph)
                                .accessibilityHidden(true)
                            Text(verbatim: safe.name)
                                .dsText(.body17)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            SafeFaces(faces: safe.faces)
                            if let need = SafeRoster.need(safe) {
                                Text(verbatim: need)
                                    .dsText(.price17)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .walletRowPitch()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .accessibilityLabel(Text(verbatim: [safe.name, SafeRoster.line(safe), SafeRoster.need(safe)]
                        .compactMap { $0 }.joined(separator: ", ")))
                    .walletListRow()
                }
            }
        }
        .environment(\.feedSectionPanelFilled, false)
    }

    private var section: some View {
        SectionPanelGroup(anchor: nil) {
            SectionPanelName(name: String(localized: "Without a signature"), glyph: "checkmark.shield")
        } rows: {
            Section { rows }
        }
        // Bare, as the Feed's (prd §1382), and as `walletCard` draws it.
        .environment(\.feedSectionPanelFilled, false)
        .task(id: queueKey) {
            busy = Self.queueWaitsOnYou()
            roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
            await SafeRosterReading.shared.refresh()
            roster = SafeRoomSource.roster(yours: SafeRosterReading.shared.yours)
        }
    }

    @ViewBuilder
    private var rows: some View {
            ForEach(roster.safes) { safe in
                let unsigned = SafeRoster.unsigned(safe)
                Button {
                    DSHaptic.selection()
                    onOpenSafe(safe)
                } label: {
                    HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
                        Image(systemName: glyph(unsigned.tone))
                            .dsGlyph(.body)
                            .foregroundStyle(ink(unsigned.tone, glyph: true))
                            .frame(width: DSRoomChassis.headGlyph)
                            .accessibilityHidden(true)
                        Text(verbatim: safe.name)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: unsigned.word)
                            .dsText(.price17)
                            .foregroundStyle(ink(unsigned.tone, glyph: false))
                            .lineLimit(1)
                    }
                    .walletRowPitch()
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .accessibilityLabel(Text(verbatim: "\(safe.name). \(unsigned.word)"))
                .walletListRow()
            }
    }

    private func glyph(_ tone: SafeRoster.Tone) -> String {
        switch tone {
        case .quiet: "gauge.with.dots.needle.33percent"
        case .confirm: "checkmark.shield"
        case .danger: "exclamationmark.shield"
        }
    }

    /// A status word takes the ink, a glyph keeps the hue (§1004).
    private func ink(_ tone: SafeRoster.Tone, glyph: Bool) -> Color {
        switch tone {
        case .quiet: DS.textSecondary
        case .confirm: glyph ? DS.confirm : DS.confirmInk
        case .danger: glyph ? DS.destructive : DS.destructiveInk
        }
    }
}
