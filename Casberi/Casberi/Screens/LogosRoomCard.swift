import SwiftUI

extension LogosSection: DSSectionScope {}

/// The Logos room's figure — one slot per scope, the devnets' `DSRoomSlot`
/// (prd §991). Home is the crown (`RoomHomeCrown`, the combined balance and
/// its line), Accounts the faces (`RoomAccountsFaces`), Activity the chain's
/// rhythm (`RoomActivityChart`), Node your node's state and Rewards what it
/// earned (prd §1016). Every part is a family part; only Node's and Rewards'
/// drawings are this room's own, because only this room has a node.
struct LogosRoomFigure: View {
    let head: LogosRoom.Head
    let section: LogosSection
    /// When each chain row landed, for Activity's chart; the rows themselves
    /// are drawn under the tiles by `FeedScreen`.
    var activityDates: [Date] = []
    /// Every watched account, never the scoped list: Accounts is where the
    /// scope is picked, so feeding it one face would leave no way back.
    var roster: [String] = []
    var scope: String? = nil
    var onPickAccount: ((String?) -> Void)? = nil

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
        case .home:     return false
        case .activity: return activityDates.isEmpty
        case .accounts: return roster.isEmpty
        case .node, .rewards: return !head.nodeWatched
        }
    }

    @ViewBuilder private var reading: some View {
        switch section {
        case .home:     crown
        case .activity: RoomActivityChart(dates: activityDates, box: DSRoomChassis.figureSlot)
        case .accounts: accounts
        case .node:     node
        case .rewards:  rewards
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

    private var caption: String {
        if head.accounts.count == 1, let one = head.accounts.first {
            return LogosWire.short(one.id)
        }
        return String(localized: "\(head.accounts.count) accounts · test coins")
    }

    // MARK: - Accounts

    @ViewBuilder private var accounts: some View {
        RoomAccountsFaces(faces: roster.map { .init(id: $0, name: LogosWire.short($0)) },
                          selected: scope,
                          onPick: { onPickAccount?($0) })
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
