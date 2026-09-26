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
/// **§295's "factual, no analysis" (user, 2026-08-03) still governs**, and
/// §923 read it more carefully: a ribbon's WIDTH is what moved between the
/// two — a measured fact, not a ranking — and nothing here says "who you
/// deal with most". **Its colour says only which of your accounts it reaches,
/// and only when there are two or more to tell apart (prd §931)**: with one
/// wallet every ribbon wore that wallet's identicon hue — an arbitrary purple
/// nobody could read (user, 2026-09-26: *"we use purple for the lines but
/// why?"*) — so a lone wallet's ribbons take the one ink, and a face wears a
/// name under it while the column has room (four rows or fewer).
struct RoomConnectionsFigure: View {
    let map: AddressConnections.Map?
    var box: CGFloat = DSRoomChassis.figureSlot
    var yours: String = String(localized: "yours")
    /// The scope: one account's name, or how many you follow — the crown's
    /// own caption, so the tile identifies itself as Home does (prd §923).
    var caption: String? = nil
    /// **THE PRESSED FACE (prd §923).** A node's id or a column's key; while
    /// set, its ribbons draw full and everything else goes quiet, and the
    /// reading names it. A tap toggles, so the graph is never stuck lit.
    @State private var lit: String?

    var body: some View {
        if let map, !map.nodes.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                reading(map)
                ConnectionSpine(map: map, lit: lit) { picked in
                    DSHaptic.selection()
                    lit = lit == picked ? nil : picked
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text(String(localized: "Connected"))
                    Spacer(minLength: 0)
                    Text(map.untouched.isEmpty ? String(localized: "Yours")
                                               : String(localized: "Yours · quiet ones nothing reaches"))
                }
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                if !map.hiddenNames.isEmpty {
                    Text(String(localized: "\(String(map.hiddenNames.count)) more aren't drawn"))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.trailing, 0)
        }
    }

    /// **THE CROWN'S READING (prd §923)** — caption, a figure at `stat24`,
    /// one line — in place of a two-line sentence that ran under the gear.
    /// Under a press it is the pressed address and what it moved with which
    /// of yours.
    @ViewBuilder
    private func reading(_ map: AddressConnections.Map) -> some View {
        let edges = map.nodes.reduce(0) { $0 + $1.walletKeys.count }
        let total = map.columns.count + map.untouched.count
        VStack(alignment: .leading, spacing: 2) {
            if let caption {
                Text(caption)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Text(headline(map, edges: edges))
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(line(map, total: total))
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only the reading clears the gear (§920's rule); the spine below
        // takes the whole width.
        .padding(.trailing, DSRoomChassis.gearColumn)
    }

    private func headline(_ map: AddressConnections.Map, edges: Int) -> String {
        if let lit {
            if let node = map.nodes.first(where: { $0.id == lit }) { return node.name }
            if let column = (map.columns + map.untouched).first(where: { $0.id == lit }) { return column.name }
        }
        return edges == 1 ? String(localized: "1 connection")
                          : String(localized: "\(String(edges)) connections")
    }

    private func line(_ map: AddressConnections.Map, total: Int) -> String {
        if let lit, let node = map.nodes.first(where: { $0.id == lit }) {
            let names = node.walletKeys.compactMap { key in map.columns.first { $0.id == key }?.name }
            let usd = node.walletKeys.compactMap { map.weights[AddressConnections.Weight.key(node.id, $0)]?.usd }
                .reduce(0, +)
            let with = names.joined(separator: ", ")
            let moves = node.count == 1 ? String(localized: "1 move")
                                        : String(localized: "\(String(node.count)) moves")
            return usd > 0 ? String(localized: "\(WalletValue.money(usd)) with \(with) · \(moves)")
                           : String(localized: "with \(with) · \(moves)")
        }
        if let lit, let column = map.columns.first(where: { $0.id == lit }) {
            let n = map.nodes.filter { $0.walletKeys.contains(column.id) }.count
            let who = n == 1 ? String(localized: "1 address") : String(localized: "\(String(n)) addresses")
            if let usd = column.usd, usd > 0 { return String(localized: "\(who) · \(WalletValue.money(usd))") }
            return who
        }
        if let lit, map.untouched.contains(where: { $0.id == lit }) {
            return String(localized: "Nothing reaches it")
        }
        return map.untouched.isEmpty
            ? String(localized: "between \(yours)")
            : String(localized: "reach \(String(map.columns.count)) of your \(String(total))")
    }
}

/// The spine itself (prd §923): faces at the nodes, ribbons weighted by what
/// moved and coloured by which of your accounts they reach, the accounts
/// nothing reaches drawn quiet, and a press that lights one face.
///
/// The ribbons are a `Canvas` (the house idiom for a drawing sized from
/// data); the faces are views over it, because a face is a `WalletFace` —
/// the identicon or the resolved avatar — and a door.
struct ConnectionSpine: View {
    let map: AddressConnections.Map
    var lit: String? = nil
    var onPress: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rights: [AddressConnections.Column] { map.columns + map.untouched }

    var body: some View {
        GeometryReader { geo in
            let lefts = map.nodes
            let rights = rights
            let rows = max(lefts.count, rights.count, 1)
            // The face is a RUNG, never a number (`face-ramp-audit.py`): the
            // row tier while the column has room for it, the badge tier once
            // five or more faces share the height.
            let compact = rows >= 5
            let face: CGFloat = compact ? DS.Face.badge : DS.Face.row
            let leftX = face / 2
            let rightX = geo.size.width - face / 2
            let leftY = Self.ys(lefts.count, height: geo.size.height, face: face)
            let rightY = Self.ys(rights.count, height: geo.size.height, face: face)
            let weights = lefts.flatMap { node in
                node.walletKeys.map { map.weights[AddressConnections.Weight.key(node.id, $0)] }
            }
            let priced = weights.contains { ($0?.usd ?? 0) > 0 }
            let peak = weights.map { w -> Double in priced ? (w?.usd ?? 0) : Double(w?.count ?? 1) }.max() ?? 1
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    var index: [String: Int] = [:]
                    for (i, c) in rights.enumerated() { index[c.id] = i }
                    for (i, node) in lefts.enumerated() {
                        for key in node.walletKeys {
                            guard let j = index[key] else { continue }
                            let w = map.weights[AddressConnections.Weight.key(node.id, key)]
                            let value = priced ? (w?.usd ?? 0) : Double(w?.count ?? 1)
                            let width = 1.5 + 6.5 * CGFloat(peak > 0 ? value / peak : 0)
                            let quiet = lit != nil && lit != node.id && lit != key
                            var path = Path()
                            path.move(to: CGPoint(x: leftX + face / 2, y: leftY[i]))
                            let midX = geo.size.width / 2
                            path.addCurve(to: CGPoint(x: rightX - face / 2, y: rightY[j]),
                                          control1: CGPoint(x: midX, y: leftY[i]),
                                          control2: CGPoint(x: midX, y: rightY[j]))
                            ctx.stroke(path,
                                       with: .color(Self.ink(for: key, columns: rights.count)
                                                        .opacity(quiet ? 0.18 : 0.7)),
                                       style: StrokeStyle(lineWidth: width, lineCap: .round))
                        }
                    }
                }
                ForEach(Array(lefts.enumerated()), id: \.element.id) { i, node in
                    faceButton(id: node.id, address: node.address, name: node.name, compact: compact,
                               quiet: lit != nil && lit != node.id
                                   && !node.walletKeys.contains { $0 == lit })
                        .position(x: leftX, y: leftY[i])
                }
                ForEach(Array(rights.enumerated()), id: \.element.id) { j, column in
                    let reached = map.columns.contains { $0.id == column.id }
                    let touchedByLit = lit.map { l in lefts.contains { $0.id == l && $0.walletKeys.contains(column.id) } } ?? false
                    faceButton(id: column.id, address: column.id, name: column.name, compact: compact,
                               quiet: !reached || (lit != nil && lit != column.id && !touchedByLit),
                               trailing: true)
                        .position(x: rightX, y: rightY[j])
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.standard, value: lit)
        }
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized:
            "\(String(map.connectedCount)) connected addresses across \(String(map.columns.count)) of yours")))
    }

    @ViewBuilder
    /// The ribbon's ink (prd §931): the wallet's own hue only where there are
    /// two or more of yours to tell apart; one wallet, one ink.
    static func ink(for walletKey: String, columns: Int) -> Color {
        columns >= 2 ? WalletFace.tint(for: walletKey) : DS.textTertiary
    }

    /// A name's width under a face — enough for a short name or an address's
    /// two ends, never half the spine.
    static let nameWidth: CGFloat = 96

    private func faceButton(id: String, address: String, name: String, compact: Bool, quiet: Bool,
                            trailing: Bool = false) -> some View {
        Button {
            onPress?(id)
        } label: {
            Group {
                // Two literal rungs rather than one expression, so the ramp
                // audit reads each as the tier it is.
                if compact {
                    WalletFace(address: address, size: DS.Face.badge, circular: true)
                } else {
                    WalletFace(address: address, size: DS.Face.row, circular: true)
                }
            }
            .opacity(quiet ? 0.35 : 1)
            .contentShape(Circle())
            // Drawn at the face's size, targeted at the 44pt floor
            // (`accessibility-audit.py`), the chips' own arrangement.
            .dsTapTarget(Circle(), size: DS.Hit.min)
            // The name under the face while the column has room (prd §931):
            // a face is a door, and a door says where it goes. Hung from the
            // face's bottom edge, out of the ribbons' way, flush with the
            // spine's own edge so the left column reads leading and the
            // right column trailing.
            .overlay(alignment: trailing ? .topTrailing : .topLeading) {
                if !compact {
                    Text(name)
                        .dsText(.label12)
                        .foregroundStyle(lit == id ? DS.textPrimary : DS.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: Self.nameWidth, alignment: trailing ? .trailing : .leading)
                        .opacity(quiet ? 0.35 : 1)
                        .offset(y: DS.Face.row + 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(lit == id ? .isSelected : [])
    }

    /// Faces spaced down the column, the first and last flush with the box.
    static func ys(_ n: Int, height: CGFloat, face: CGFloat) -> [CGFloat] {
        // The name under a face (prd §931) needs its line below the last row
        // — the row tier carries one, the badge tier does not.
        let tail: CGFloat = face >= DS.Face.row ? nameLine : 0
        guard n > 1 else { return [(height - tail) / 2] }
        let usable = height - face - tail
        return (0..<n).map { face / 2 + usable * CGFloat($0) / CGFloat(n - 1) }
    }

    /// The name's line under a face: the 2pt gap plus a `label12` line.
    static let nameLine: CGFloat = 16
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
extension RoomAccountsRows {
    /// The accounts TIED to the ones you follow — one row per node of the
    /// spine, after the followed rows. Same key rule as the map (lowercased
    /// hex), so a tied account that is also followed is never listed twice.
    static func tied(_ map: AddressConnections.Map?, watchedKeys: Set<String>,
                     onOpen: ((String) -> Void)? = nil) -> [Row] {
        (map?.nodes ?? [])
            .filter { !watchedKeys.contains($0.id) }
            .map { node in
                Row(key: node.id, address: node.address, name: node.name, kind: nil,
                    connections: node.walletKeys.count, watched: false, unreached: false,
                    onOpen: onOpen.map { open in { open(node.address) } })
            }
    }
}

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
        /// **Whether YOU follow it (prd §689c, user: "addresses are accounts …
        /// and or tied to them").** The scope's subject is the accounts you
        /// follow AND the accounts tied to them — the left-hand nodes of the
        /// spine are accounts too, and a picture whose nodes have no row is a
        /// figure the list beneath it does not explain. A tied account reads
        /// "tied to 2 of yours"; a followed one reads "connected to 2 of
        /// yours"; the count on the right is the same unit for both.
        var watched: Bool = true
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
                    .dsText(.price17)
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
        } else if !row.watched {
            parts.append(row.connections == 1
                         ? String(localized: "tied to 1 of yours")
                         : String(localized: "tied to \(String(row.connections)) of yours"))
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
