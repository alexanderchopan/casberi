import SwiftUI

extension LogosSection: DSSectionScope {}

/// The Logos room's figure — one slot per scope, the devnets' `DSRoomSlot`
/// (prd §991). Home is the crown (`RoomHomeCrown`, the combined balance and
/// its line), Node your node's state and what it earned (§1016, folded in by
/// §1155), and Chat your Logos conversations through a paired Observer.
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
        case .home: return false
        // **A ONE-CELL TREEMAP IS THE 100% BAR §610 REMOVED** (Frames' rule):
        // with no token, the coins alone are Home's crown, not a map.
        case .holdings: return head.hasRead && head.tokens.isEmpty
        case .node: return !head.nodeWatched
        // Chat draws its own states: each says what would fill it (§769).
        case .chat: return false
        }
    }

    @ViewBuilder private var reading: some View {
        switch section {
        case .home:     crown
        case .holdings: RoomHoldingsFigure(cells: LogosHoldings.cells(head))
        case .node:     node
        case .chat:     chat
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
                     : String(localized: "No account followed yet."))
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
            ? LogosRoom.name(for: head.accounts[0].id)
            : String(localized: "\(head.accounts.count) accounts · test coins")
        guard let reset = head.resetDay else { return who }
        let day = reset.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "\(who) · testnet reset \(day)")
    }

    // MARK: - Node

    /// Your node in the family's figure grammar (`DSFigureReading`, prd §942:
    /// one number, one noun): its height is the number, and the caption says
    /// whether it is in sync and how many peers it has. Under it, what it
    /// earned (§1016, here since §1155): whether it mines, the tickets ready
    /// — a COUNT, because the node reports no amount and a claim can still
    /// fail — and the reward vouchers.
    @ViewBuilder private var node: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let snap = head.node, snap.reachable, let h = snap.height {
                DSFigureReading(number: LogosWire.amount(Decimal(h)),
                                caption: [String(localized: "height"),
                                          snap.synced ? String(localized: "in sync") : String(localized: "syncing"),
                                          snap.peers.map { $0 == 1 ? String(localized: "1 peer") : String(localized: "\($0) peers") }]
                                    .compactMap { $0 }.joined(separator: " · "))
                if let line = Self.earnings(snap) { note(line) }
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

    /// "Mining · 3 tickets ready", or nil when the node reports no mining.
    static func earnings(_ snap: LogosWire.NodeSnapshot) -> String? {
        let mining: String? = snap.mining.map { on in
            on ? (snap.miningPays == false ? String(localized: "Mining · this network pays no rewards")
                                           : String(localized: "Mining"))
               : String(localized: "Not mining")
        }
        let tickets: String? = snap.tickets.flatMap { t in
            t == 0 ? nil : (t == 1 ? String(localized: "1 ticket ready") : String(localized: "\(t) tickets ready"))
        }
        let parts = [mining, tickets].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The node's text when it has no reading to draw.
    @ViewBuilder private var unread: some View {
        Text(head.node == nil ? String(localized: "Reading your node…")
                              : String(localized: "Not answering"))
            .dsText(.heading24)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Chat (prd §1155)

    /// How many conversations, and the newest one's preview; otherwise the
    /// one sentence that says what would fill the box. Read live from the
    /// paired Observer and never kept (`LogosObserver.ChatState`).
    private var chat: some View {
        chatReading
            // The box always draws, where the list's section does not while
            // it is empty: the read starts here, on every visit and pairing.
            .task(id: LogosObserver.shared.chatPairing?.deviceID) { await LogosObserver.shared.readChat() }
    }

    @ViewBuilder private var chatReading: some View {
        switch LogosObserver.shared.chat {
        case .ready(let convos) where !convos.isEmpty:
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSFigureReading(number: LogosWire.amount(Decimal(convos.count)),
                                caption: convos.count == 1 ? String(localized: "conversation")
                                                           : String(localized: "conversations"))
                if let newest = convos.first {
                    note([newest.title, newest.preview].compactMap { $0 }.joined(separator: " · "))
                }
            }
        case .ready:
            chatEmpty(String(localized: "No conversations"),
                      String(localized: "Start one in Chat in Logos Basecamp."))
        case .loading:
            note(String(localized: "Reading your chats…"))
        case .notStarted:
            chatEmpty(String(localized: "Chat isn't open"),
                      String(localized: "Open Chat in Logos Basecamp on your computer."))
        case .notGranted:
            chatEmpty(String(localized: "No chats"),
                      String(localized: "Pair your Observer again with chats turned on."))
        case .unreachable:
            chatEmpty(String(localized: "Not answering"),
                      String(localized: "Your Observer didn't answer. Check that this device is on the same network."))
        case .notPaired:
            chatEmpty(String(localized: "No chats"),
                      String(localized: "Pair Logos Observer on the Logos page to read your chats."))
        }
    }

    @ViewBuilder private func chatEmpty(_ headline: String, _ words: String) -> some View {
        // The fix is the point of each state ("Open Chat in Logos Basecamp…"),
        // so it is drawn as the note, not only spoken as the words.
        DSEmptyState(headline: Text(headline), words: Text(words),
                     scale: .room(section.skeleton), note: Text(words))
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
