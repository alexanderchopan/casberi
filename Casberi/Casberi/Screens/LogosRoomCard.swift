import SwiftUI

extension LogosSection: DSSectionScope {}

/// The Logos room's figure — one slot per scope, the devnets' `DSRoomSlot`
/// (prd §991). Home is the crown (`RoomHomeCrown`, the combined balance and
/// its line), Node your node's state and Rewards what it earned (prd §1016).
/// The Activity chart and the Accounts faces went with their tiles (prd
/// §1039): Home lists the moves, and the account menu picks the account.
struct LogosRoomFigure: View {
    let head: LogosRoom.Head
    let section: LogosSection

    var body: some View {
        DSRoomSlot(headline: drawsEmptyState ? nil : slotHeadline,
                   reservesHeadline: !drawsEmptyState && slotHeadline != nil) {
            if drawsEmptyState {
                if let words = section.emptyBody {
                    DSEmptyState(headline: section.emptyHeadline.map { Text($0) },
                                 words: Text(words), scale: .room(section.skeleton))
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s2) { reading }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var slotHeadline: String? { nil }

    private var drawsEmptyState: Bool {
        switch section {
        case .home, .create, .explorer, .send: return false
        // **A ONE-CELL TREEMAP IS THE 100% BAR §610 REMOVED** (Frames' rule):
        // with no token, the coins alone are Home's crown, not a map.
        case .holdings: return head.hasRead && head.tokens.isEmpty
        case .node, .rewards: return !head.nodeWatched
        }
    }

    @ViewBuilder private var reading: some View {
        switch section {
        case .home:     crown
        case .holdings: RoomHoldingsFigure(cells: LogosHoldings.cells(head))
        case .node:     node
        case .rewards:  rewards
        // A verb is never a page — `resolve` never lands here.
        case .create, .explorer, .send: EmptyView()
        }
    }

    // MARK: - Home

    /// The combined balance of the accounts in scope, and the line this phone
    /// sampled of it. **No unit**: LEZ has none (prd §988), so the figure is
    /// the number and the caption names whose it is.
    @ViewBuilder private var crown: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if head.accounts.isEmpty {
                Text(head.nodeWatched
                     ? LogosWire.nodeLine(head.node)
                     : String(localized: "No account watched yet."))
                    .dsText(.heading24)
                    .fixedSize(horizontal: false, vertical: true)
            } else if head.series.count > 1 {
                RoomHomeCrown(samples: head.series, caption: caption,
                              format: Self.plain, exactFormat: Self.plain,
                              changeFormat: Self.plain,
                              box: DSRoomChassis.figureSlot)
            } else if let total = head.total {
                RoomHomeCrown(caption: caption,
                              format: Self.plain, exactFormat: Self.plain,
                              changeFormat: Self.plain,
                              fallbackTotal: NSDecimalNumber(decimal: total).doubleValue,
                              box: DSRoomChassis.figureSlot)
            } else if !head.hasRead {
                note(String(localized: "Reading the testnet…"))
            } else {
                note(String(localized: "Couldn't reach the testnet."))
            }
        }
    }

    private static let plain: (Double) -> String = { LogosWire.amount(Decimal($0.rounded())) }

    /// Whose figure it is — and, in the month after a reset while an
    /// account reads empty, when the chain began (prd §1035), riding the
    /// caption so the fixed lead box never grows a line.
    private var caption: String {
        let who = head.accounts.count == 1
            ? LogosWire.short(head.accounts[0].id)
            : String(localized: "\(head.accounts.count) accounts · test coins")
        guard let reset = head.resetDay else { return who }
        let day = reset.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "\(who) · testnet reset \(day)")
    }

    // MARK: - Node

    /// Your node in the family's figure grammar (`DSFigureReading`, prd §942:
    /// one number, one noun): its height is the number, and the caption says
    /// whether it is in sync and how many peers it has. What it earned is
    /// Rewards' (prd §1016).
    @ViewBuilder private var node: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let snap = head.node, snap.reachable, let h = snap.height {
                DSFigureReading(number: LogosWire.amount(Decimal(h)),
                                caption: [String(localized: "height"),
                                          snap.synced ? String(localized: "in sync") : String(localized: "syncing"),
                                          snap.peers.map { $0 == 1 ? String(localized: "1 peer") : String(localized: "\($0) peers") }]
                                    .compactMap { $0 }.joined(separator: " · "))
            } else {
                unread
            }
        }
    }

    /// The node's text when it has no reading to draw.
    @ViewBuilder private var unread: some View {
        Text(head.node == nil ? String(localized: "Reading your node…")
                              : String(localized: "Not answering"))
            .dsText(.heading24)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Rewards

    /// What your node earned (prd §1016): the mining tickets waiting are the
    /// number — a COUNT, because the node reports no amount and a claim can
    /// still fail — then whether it is mining, and the reward vouchers.
    @ViewBuilder private var rewards: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let snap = head.node, snap.reachable {
                if let t = snap.tickets {
                    DSFigureReading(number: LogosWire.amount(Decimal(t)),
                                    caption: t == 1 ? String(localized: "mining ticket ready")
                                                    : String(localized: "mining tickets ready"))
                } else {
                    Text(String(localized: "This node doesn't report mining."))
                        .dsText(.heading24)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let mining = snap.mining {
                    note(mining
                         ? (snap.miningPays == false ? String(localized: "Mining · this network pays no rewards")
                                                     : String(localized: "Mining"))
                         : String(localized: "Not mining"))
                }
                if let v = snap.vouchers, v > 0, let worth = snap.claimable {
                    note(v == 1
                         ? String(localized: "1 reward voucher · \(LogosWire.amount(worth)) claimable")
                         : String(localized: "\(v) reward vouchers · \(LogosWire.amount(worth)) claimable"))
                }
            } else {
                unread
            }
        }
    }

    @ViewBuilder private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.subhead12)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}


/// **WHAT LOGOS ACCOUNTS HOLD (prd §1084)**, in `RoomHoldings`' shape — the
/// figure and the list draw the same cells. The coins first, then each token
/// by the name its definition carries.
///
/// **No symbol, on purpose.** `RoomHoldingsFigure` prices a cell by its
/// symbol at MAINNET weight, and an LEZ token's name is whatever its maker
/// typed — a test token called "USDC" is not USDC. With no symbol nothing is
/// priced, so every tile is one size: which tokens, never how much.
enum LogosHoldings {
    @MainActor
    static func cells(_ head: LogosRoom.Head) -> [RoomHoldings.Cell] {
        guard !head.tokens.isEmpty else { return [] }
        var out: [RoomHoldings.Cell] = []
        if let total = head.total {
            out.append(RoomHoldings.Cell(name: String(localized: "test coins"),
                                         amount: LogosWire.amount(total)))
        }
        // Two definitions can share a name (three "ANTV"s on the 10-01
        // chain), and a cell is keyed by its name: a shared one carries its
        // definition's short id.
        let names = head.tokens.map { $0.name ?? LogosWire.short($0.definition) }
        for (token, name) in zip(head.tokens, names) {
            let shown = names.filter { $0 == name }.count > 1
                ? "\(name) · \(LogosWire.short(token.definition))" : name
            let amount: String
            if token.nft {
                amount = token.copies > 0
                    ? (token.copies == 1 ? String(localized: "1 NFT") : String(localized: "\(token.copies) NFTs"))
                    : String(localized: "\(LogosWire.amount(token.amount ?? 0)) to print")
            } else {
                amount = LogosWire.amount(token.amount ?? 0)
            }
            out.append(RoomHoldings.Cell(name: shown, amount: amount))
        }
        return out
    }
}
