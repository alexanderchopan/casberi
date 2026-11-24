import SwiftUI

// MARK: - Following, and a wallet you follow (prd §1969)

extension FeedScreen {
    /// **FOLLOWING (prd §1969, over §1504's list and §1536's switch).** One row
    /// per wallet you follow: its face and name, what it did since you last
    /// looked, and what that did to its money; the ones that moved first.
    /// A tap opens the wallet's own page. Then Follow an account.
    @ViewBuilder
    var walletFollowingPage: some View {
        let news = FollowedNews.shared
        let slots = walletFollowingSlots
        let order = news.ordered(slots.map(\.id))
        let ordered = order.compactMap { id in slots.first { $0.id == id } }
        if slots.isEmpty { walletSkeletonRowsSection }
        walletCard(WalletSection.following.label, glyph: WalletSection.following.glyph) {
            ForEach(ordered) { slot in walletFollowedRow(slot) }
        }
        .task { news.refresh(modelContext) }
        .alert(String(localized: "Name this account"),
               isPresented: Binding(get: { walletNaming != nil }, set: { if !$0 { walletNaming = nil } })) {
            TextField(String(localized: "Name"), text: $walletNameDraft)
            Button(String(localized: "Save")) { saveWalletName() }
            Button(String(localized: "Cancel"), role: .cancel) { walletNaming = nil }
        } message: {
            Text(String(localized: "Blank shows the address instead."))
        }
        Section {
            DSPushRow(title: Text("Follow an account"), tint: DS.pickInk, opens: false) {
                DSHaptic.selection()
                feedSheet = .walletFollow
            } leading: {
                walletDoorLead(ScopeTileGlyph.wallets)
            }
            .walletListRow()
            // The limit, said up front (§170), under the verb it limits.
            DSFootnote(prose: String(localized: "\(slots.count) of \(WalletStore.watchLimit) you can follow"))
                .walletListRow()
        }
    }

    /// One wallet you follow: the news since you looked on its line, and
    /// what its money did since then (else what it holds, grey).
    @ViewBuilder
    func walletFollowedRow(_ slot: DSAccountSlot) -> some View {
        let address = slot.id
        let moves = FollowedNews.shared.moves[address] ?? []
        let seen = FollowedNews.seenAt(address)
        let line = FollowedSince.line(moves) ?? FollowedSince.nothingNew(seen, now: .now)
        let figure = walletFollowedFigureWords(address, since: seen, moved: !moves.isEmpty)
        Button {
            DSHaptic.selection()
            chrome.openFollowedWallet(address)
        } label: {
            DSFeedRow(name: slot.name, line: Text(verbatim: line), trailingBesideLine: true) {
                WalletFace(address: address, size: DS.Face.row, circular: true)
            } trailing: {
                if let figure {
                    Text(verbatim: figure.words)
                        .dsText(.body17)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(figure.ink)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .accessibilityLabel(Text(verbatim: "\(slot.name), \(line)"))
        .walletListRow()
        .contextMenu {
            Button {
                walletNameDraft = slot.name == WalletStore.shortAddress(address) ? "" : slot.name
                walletNaming = address
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            if let entry = AddressBook.shared.entry(for: address) {
                Button(role: .destructive) {
                    WalletUnwatch.perform(entry, context: modelContext, chrome: chrome, bridges: bridges)
                } label: {
                    Label(String(localized: "Stop following"), systemImage: "trash")
                }
            }
        }
    }

    /// A followed row's figure: what its money did since you looked when it
    /// moved (green or red), else what it holds, grey. Masked under Hide
    /// balances; nil with no reading.
    func walletFollowedFigureWords(_ address: String, since: Date, moved: Bool) -> (words: String, ink: Color)? {
        let samples = wallet.valueSamples(forAddress: address)
        if BalancePrivacy.shared.withheld { return samples.isEmpty ? nil : (BalancePrivacy.mask, DS.textSecondary) }
        if moved, let delta = FollowedSince.change(samples.map { (at: $0.at, usd: $0.usd) }, since: since),
           abs(delta) >= 1 {
            let words = (delta > 0 ? "+" : "−") + WalletValue.exactMoney(abs(delta))
            return (words, delta > 0 ? DS.confirmInk : DS.destructiveInk)
        }
        guard let latest = samples.last else { return nil }
        return (WalletValue.exactMoney(latest.usd), DS.textSecondary)
    }

    // MARK: - One wallet

    /// A followed wallet's box: its money and its day.
    @ViewBuilder
    var walletFollowedFigure: some View {
        if let shown = portfolioShown, shown.totalUSD > 0 {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            let day = Self.homeDay(homeDayChange(shown))
            DSFigureReading(number: mask ?? WalletValue.exactMoney(shown.totalUSD),
                            caption: day.map { String(localized: "\($0.words) today") } ?? String(localized: "Today"),
                            captionInk: day?.ink ?? DS.textSecondary)
        } else {
            WalletScopeEmptyFigure(section: .followedWallet, padded: false, reading: holdingsReads > 0)
        }
    }

    /// **A WALLET YOU FOLLOW, ON ITS OWN PAGE (prd §1969).** What it did since
    /// you looked, its three biggest holdings, its newest moves, then Send
    /// to it, its address, and the Bluesky account it is linked to. Read
    /// through the pick (`selectedWallet`), never your money's. Going back
    /// off it marks it looked at (`ShellChrome.walletGoBack`), so the news
    /// stands while you read it.
    @ViewBuilder
    func walletFollowedPage(all: [Thing], nextEventID: UUID?) -> some View {
        if let address = selectedWallet {
            let moves = FollowedNews.shared.moves[address] ?? []
            let seen = FollowedNews.seenAt(address)
            // Its money and its day lead the page: no box (prd §1969).
            Section {
                walletFollowedFigure
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .walletListRow()
            }
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: FollowedSince.sinceHead(seen, now: .now))
                        .dsText(.fact15).foregroundStyle(DS.textSecondary)
                    Text(verbatim: FollowedSince.line(moves) ?? String(localized: "Nothing new"))
                        .dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .walletListRow()
            }
            walletFollowedHoldings
            walletFollowedActivity(all, nextEventID: nextEventID)
            walletFollowedActs(address)
        }
    }

    /// The three biggest holdings, then the door to the rest.
    @ViewBuilder
    private var walletFollowedHoldings: some View {
        let positions = (portfolioShown?.tokensOnly(appsApart: false).positions ?? [])
            .filter { $0.usd > 0 }.sorted { $0.usd > $1.usd }
        let total = positions.reduce(0) { $0 + $1.usd }
        if !positions.isEmpty {
            walletCard(WalletSection.holdings.label, glyph: WalletSection.holdings.glyph) {
                ForEach(positions.prefix(3)) { position in
                    WalletTokenRowLabel(position: position, total: total, move: nil)
                        .walletListRow()
                }
                if positions.count > 3 {
                    let rest = positions.count - 3
                    DSMoreRow(title: Text(verbatim: rest == 1 ? String(localized: "1 more token")
                                                              : String(localized: "\(rest) more tokens"))) {
                        withAnimation(DS.Motion.standard) { chrome.walletSection = .holdings }
                    }
                    .walletListRow()
                }
            }
        }
    }

    /// Its newest moves, then the door to all of them.
    @ViewBuilder
    private func walletFollowedActivity(_ all: [Thing], nextEventID: UUID?) -> some View {
        let moves = Self.walletMoves(all)
        let stream = walletStream(moves, cap: 5)
        if !stream.rows.isEmpty {
            walletCard(String(localized: "Activity"), glyph: WalletSection.activity.glyph) {
                walletStreamSections(stream.rows, ownMoves: stream.ownMoves, nextEventID: nextEventID)
                if moves.count > 5 {
                    DSMoreRow(title: Text("All activity")) {
                        withAnimation(DS.Motion.standard) { chrome.walletSection = .activity }
                    }
                    .walletListRow()
                }
            }
        }
    }

    /// Send to it (with an account of yours to send from), its address, and
    /// the Bluesky account a confirmed link joins it to.
    @ViewBuilder
    private func walletFollowedActs(_ address: String) -> some View {
        let name = walletFollowingSlots.first { WalletWatch.sameAddress($0.id, address) }?.name
            ?? WalletStore.shortAddress(address)
        let hex = wallet.resolvedForm(of: address) ?? address
        let bluesky = ContactIndexSources.contact(forKey: Identity.key(.wallet, hex))?
            .identities.first { $0.kind == .bluesky }
            .map { String($0.key.dropFirst(Identity.Kind.bluesky.prefix.count)) }
        Section {
            if YourAccountDemo.shownAddress != nil {
                DSDoorRow(icon: "arrow.up.right", title: Text(verbatim: String(localized: "Send to \(name)"))) {
                    DSHaptic.selection()
                    chrome.moveDraft = MoveSentence.sendDraft(to: hex)
                    chrome.moveTray = true
                }
                .walletListRow()
            }
            DSCopyRow(value: hex, label: "Copy address", sensitive: false)
                .walletListRow()
            if let bluesky {
                DSDoorRow(icon: "person.crop.circle", title: Text(verbatim: String(localized: "Also on Bluesky · @\(bluesky)"))) {
                    DSHaptic.selection()
                    feedSheet = .person(source: "Bluesky", handle: bluesky)
                }
                .walletListRow()
            }
        }
    }
}
