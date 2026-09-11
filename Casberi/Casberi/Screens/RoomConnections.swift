import SwiftUI

/// **THE ACCOUNTS SLOT, ONE TEMPLATE FOR EVERY WALLET-FAMILY ROOM (prd §689).**
///
/// §683 did Home, §686/§687 Activity, §688 Holdings. Accounts was the worst of
/// the four: Hegotá and the Privacy devnet drew their own ROSTER in the slot
/// and then drew the same roster again as the list beneath it — 258pt spent
/// restating the rows a finger's width below, which is §610's defect one scope
/// over. Only vibenet had a real figure, and it is a web of who authorised
/// whom (§491, the user's pick of three drawings).
///
/// **THE CROWN IS THE CONNECTIONS BETWEEN THE ACCOUNTS YOU WATCH** (user,
/// 2026-09-11: *"i was thinking it could be the connections between the
/// followed accounts"*, then *"wallet has connected addresses we used to show
/// this somewhere in a previous version"*). Both right, and the second one is
/// the find: **this is §295 restored.** *"N of your addresses are connected"*
/// — a count and a spine, the connected address on the left, your wallets on
/// the right, one ribbon per landed relationship — lived at the foot of the
/// Wallet manager until the Accounts-door redesign deleted that screen. The
/// MODEL survived: `AddressConnections` is still computed, still probed by
/// `-connectionsProbe`, still reported in the demo census every verify run.
/// Only the drawing died, so the app has been working this reading out and
/// showing it to nobody.
///
/// **`AddressConnections.map(edges:watched:)` is a PURE function**, which is
/// why every room can have it: a room that can name its transfers gets the
/// whole reading — the node cap, the §439 direct-pair links, the untouched
/// wallets — without a line of new analysis.
///
/// **§295's own ruling governs the drawing and is not to be "improved"**
/// (user, 2026-08-03: *"limit the 'analysis' b/c it should be factual"*).
/// Every ribbon is the same weight: a connection exists or it does not. No
/// ranking by count, no weighting by value, no "who you deal with most".
struct RoomConnectionsFigure: View {
    let map: AddressConnections.Map?
    var box: CGFloat = DSRoomChassis.figureSlot
    /// What this room calls the things on the right. "wallets" reads wrong in
    /// a room whose subject is accounts on a devnet.
    var yours: String = String(localized: "yours")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let map, !map.nodes.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(headline(map))
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                ConnectionSpine(map: map)
                    .frame(height: DSRoomChassis.crownLine(box: box, chrome: 64))
                if let tail = tail(map) {
                    Text(tail)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// **THE COUNT IS THE HEADLINE, and it counts EVERY connected address
    /// rather than the drawn ones** — `Map.connectedCount`'s own rule: a
    /// display cap must not change what a number means.
    private func headline(_ map: AddressConnections.Map) -> String {
        map.connectedCount == 1
            ? String(localized: "1 address connects \(yours)")
            : String(localized: "\(String(map.connectedCount)) addresses connect \(yours)")
    }

    /// The two things the picture cannot hold, said in words rather than drawn
    /// as empty nodes — `Map`'s own reasoning for naming them.
    private func tail(_ map: AddressConnections.Map) -> String? {
        var parts: [String] = []
        if !map.hiddenNames.isEmpty {
            parts.append(String(localized: "\(String(map.hiddenNames.count)) more aren't drawn"))
        }
        if !map.untouchedWalletNames.isEmpty {
            parts.append(String(localized: "nothing reaches \(map.untouchedWalletNames.joined(separator: ", "))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The spine: connected addresses left, yours right, one ribbon each.
///
/// A `Canvas`, the house idiom for a drawing sized from data, so the arrival
/// rides CoreAnimation rather than a per-frame SwiftUI interpolation on the
/// main actor — and `chartWipe` because `design-motion-audit` cannot see a
/// Canvas and nothing else would say so.
struct ConnectionSpine: View {
    let map: AddressConnections.Map
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            let lefts = map.nodes
            let rights = map.columns
            guard !lefts.isEmpty, !rights.isEmpty else { return }
            let dot: CGFloat = 7
            let leftX = dot / 2 + 1
            let rightX = size.width - dot / 2 - 1
            func ys(_ n: Int) -> [CGFloat] {
                guard n > 1 else { return [size.height / 2] }
                let usable = size.height - dot
                return (0..<n).map { dot / 2 + usable * CGFloat($0) / CGFloat(n - 1) }
            }
            let leftY = ys(lefts.count)
            let rightY = ys(rights.count)
            var index: [String: Int] = [:]
            for (i, c) in rights.enumerated() { index[c.id] = i }

            // **EVERY RIBBON THE SAME WEIGHT (§295).** A connection exists or
            // it does not; a thicker line would be the ranking the ruling
            // forbids.
            for (i, node) in lefts.enumerated() {
                for key in node.walletKeys {
                    guard let j = index[key] else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: leftX, y: leftY[i]))
                    let midX = size.width / 2
                    path.addCurve(to: CGPoint(x: rightX, y: rightY[j]),
                                  control1: CGPoint(x: midX, y: leftY[i]),
                                  control2: CGPoint(x: midX, y: rightY[j]))
                    ctx.stroke(path, with: .color(DS.tint.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            for y in leftY {
                ctx.fill(Path(ellipseIn: CGRect(x: leftX - dot / 2, y: y - dot / 2,
                                                width: dot, height: dot)),
                         with: .color(DS.textSecondary))
            }
            for y in rightY {
                ctx.fill(Path(ellipseIn: CGRect(x: rightX - dot / 2, y: y - dot / 2,
                                                width: dot, height: dot)),
                         with: .color(DS.tint))
            }
        }
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized:
            "\(String(map.connectedCount)) connected addresses across \(String(map.columns.count)) of yours")))
    }
}

/// **THE LIST SAYS WHAT EACH ADDRESS IS AND HOW IT RELATES (prd §689, user:
/// "for the list for wallets what should it be, should it really be what each
/// holds b/c we have a holdings slot for that on the rail. it needs to be
/// something else").**
///
/// Right, and both rooms' own scope description said the wrong thing out loud
/// — *"the addresses you watch, and what each holds"*, which is the Holdings
/// chip's sentence. Every other scope has taken a piece: Home the total,
/// Activity what moved, Holdings what is held, Frames and Permissions the
/// mechanics. What is left, and what nothing else can answer, is **what this
/// address IS and how it relates to the others you watch** — which also makes
/// the list the crown's own legend rather than a second copy of it.
struct RoomAccountsRows: View {
    struct Row: Identifiable {
        var id: String { key }
        let key: String
        let address: String
        let name: String
        /// What it is — `AddressBook.Kind`'s word, or a room's own.
        let kind: String?
        /// How many of the accounts you watch it connects to.
        let connections: Int
        /// True when the chain did not answer for it; the row says so instead
        /// of reading as an address with nothing going on (§515a).
        let unreached: Bool
        var onOpen: (() -> Void)? = nil
    }

    let rows: [Row]

    var body: some View {
        ForEach(rows) { row in
            if let onOpen = row.onOpen {
                Button {
                    DSHaptic.selection()
                    onOpen()
                } label: { body(row).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                body(row)
            }
        }
    }

    @ViewBuilder private func body(_ row: Row) -> some View {
        WalletRow(mark: .face(row.address), title: row.name, subtitleText: subtitle(row)) {
            // **THE CONNECTION COUNT, which is the crown's own unit.** The
            // family rule is that the right edge carries the amount where a
            // row has one and the number that differs row to row where it does
            // not — and here there is no amount, because Holdings owns it.
            if row.connections > 0 {
                Text(String(row.connections))
                    .dsText(.price16)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private func subtitle(_ row: Row) -> Text? {
        var parts: [String] = []
        if let kind = row.kind { parts.append(kind) }
        if row.unreached {
            // An unread address is not an unconnected one, and saying
            // "no connections yet" over a chain that never answered would be
            // the false fact §83 exists to stop.
            parts.append(String(localized: "couldn't be reached"))
        } else if row.connections == 0 {
            parts.append(String(localized: "no connections yet"))
        } else {
            parts.append(row.connections == 1
                         ? String(localized: "connected to 1 of yours")
                         : String(localized: "connected to \(String(row.connections)) of yours"))
        }
        return parts.isEmpty ? nil : Text(parts.joined(separator: " · "))
    }
}

/// **EDGES FROM A ROOM'S OWN MOVES (prd §689).**
///
/// `AddressConnections.map` is a pure function over edges, so a devnet needs
/// only to say who its transfers were with. The Wallet builds its edges from
/// the corpus through `AddressConnectionsSource`; this is the same shape for a
/// room whose transfers are read straight off a chain.
///
/// **Oldest first, which `map` requires and states why**: node order is
/// first-appearance order — "the order you first dealt with them" —
/// deterministic across launches and not a judgment about which address
/// matters. Sorting by count or by value would be the ranking §295 forbids.
enum RoomConnectionsEdges {

    /// One transfer, as a room can describe it without knowing anything about
    /// the address book.
    struct Move {
        /// The watched address this move belongs to.
        let owner: String
        /// Who it was with.
        let counterparty: String
        /// Chain order, oldest smallest. A block number is exactly this.
        let order: UInt64
    }

    static func edges(_ moves: [Move], name: (String) -> String) -> [AddressConnections.Edge] {
        moves
            .filter { !$0.counterparty.isEmpty && !$0.owner.isEmpty }
            // **A MOVE WITH ITSELF IS NOT A CONNECTION.** Some of these chains
            // route a transfer through the sender's own address (a UTXO's
            // change comes straight back), and counting it would make every
            // account connected to itself and to nothing else.
            .filter { $0.counterparty.caseInsensitiveCompare($0.owner) != .orderedSame }
            .sorted { $0.order < $1.order }
            .map { move in
                AddressConnections.Edge(
                    addressKey: move.counterparty.lowercased(),
                    address: move.counterparty,
                    addressName: name(move.counterparty),
                    named: false,
                    walletKey: move.owner.lowercased(),
                    // **NO VALUE, EVER.** These are test chains with no price
                    // — `FramesMoney`'s standing rule — and the spine's own
                    // ruling is that every ribbon weighs the same anyway.
                    usd: nil)
            }
    }
}
