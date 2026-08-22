import SwiftUI

/// How your wallets are connected — the address book reading itself
/// (2026-08-22, prd §440).
///
/// **This restores §295's spine and retires the sky.** §435 fused the roster,
/// the connections card and the group decks into one drawing on the grounds
/// that they were five renderings of one graph. Four device drawings later
/// (§436, §437, §438, §439) the map still could not be read: a ring whose
/// bodies clumped, then a wheel, then rings drawn, then a chord for the one
/// relationship it had never shown. The fault was never the arithmetic — every
/// one of those was harness-proven before it shipped — it was that a
/// force-free graph layout has to answer a different geometric question for
/// every corpus shape, and this corpus is almost always the minimum one.
///
/// A spine answers one question and answers it the same way every time:
/// **connected addresses on the left, your wallets on the right, one ribbon
/// per landed relationship.** Two wallets or five, one counterparty or six, it
/// is the same picture with more rows. There is no shape it can collapse into.
///
/// **It asserts nothing §295 didn't.** Every ribbon is the same weight — a
/// connection exists or it doesn't, and scaling one by volume would be the
/// card claiming which relationship matters, which is precisely the analysis
/// the 2026-08-03 ruling ("limit the analysis, it should be factual") forbids.
/// No hue on the ribbons. Order is the order you first dealt with each
/// address, never count and never dollars — sorting would rank. And **no money
/// anywhere**, which is the one thing this card does that §295's did not:
/// §435's ruling struck every figure off this screen, so `Column.usd` is read
/// by nothing here.
///
/// **What it adds to §295.** Faces on both sides, so the picture is made of
/// the same identities the rest of the screen is made of rather than of two
/// columns of text. A naming affordance ON an unnamed node, not only in the
/// button below it. And the §439 reading — two of your OWN wallets that have
/// moved funds to each other — drawn as a bracket joining them on the right,
/// which is the one line here with a face at both ends.
///
/// FLAT BY LAW like its neighbours — plain stacks and two `Path`s, no generic
/// `Widget`/`Row` mount (the render-depth lesson, paid three times).
///
/// Liveness: stores no `Thing`, only value types out of `AddressConnections`,
/// so corollary 5 has nothing to guard here.
struct AddressSpineCard: View {
    let map: AddressConnections.Map
    /// The connected addresses this device has never drawn (prd §441) — they
    /// arrive LAST and DASHED, so the picture is seen growing rather than
    /// arriving already grown. Empty on first sight, by
    /// `AddressConnectionsSeen`'s own seeding rule.
    ///
    /// Declared HERE and not beside the closures below, so the memberwise
    /// initializer keeps `onName` and `onOpen` last and both call sites can
    /// pass them as trailing closures.
    var newNodeIDs: Set<String> = []
    /// Names an address nobody has named. Hands back the node; the card holds
    /// no hex of its own.
    var onName: (AddressConnections.Node) -> Void
    /// Opens a connected address's own card — the same screen the book's row
    /// opens, over the same history this card counted.
    ///
    /// A CLOSURE, never a `.sheet` of this card's own: a presentation attached
    /// to a view inside a `List` row resolves to the same presenting
    /// controller as the screen's, and the row's tap then tears down the sheet
    /// it just started (CLAUDE.md, "one screen, one `.sheet`", paid three
    /// times). The Wallet manager routes this through the slot it already has.
    var onOpen: (AddressConnections.Node) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The node whose ribbons are lit (prd §441) — set for a beat on tap,
    /// BEFORE the sheet rises, so you see which of your wallets that person
    /// reaches before the card covers them.
    ///
    /// It is the only interpretation-free way to answer "which lines are
    /// theirs" on a spine of six: the ribbons all look alike by §295's ruling,
    /// which is right as a resting state and leaves a tap with nothing to
    /// confirm it landed on the row you meant.
    @State private var litNode: String?

    /// **The ribbons draw themselves** (§297, carried over) — a `trim` across
    /// one `Path`, so the connections are STRUCK one after another in
    /// first-dealt order, the order the rows are already in.
    ///
    /// A stroke-draw and not a wipe, deliberately. A wipe reveals the ribbons
    /// as a group, which says "a picture is appearing"; tracing each curve
    /// from a name to a wallet says "this address reached this wallet, and
    /// then this one" — the sentence the card exists to make. It stays inside
    /// the factual ruling: the order traced is the order already on screen, so
    /// the entrance ranks nothing the drawing doesn't.
    @State private var drawn: CGFloat = 0

    /// One row of the spine, both sides. Fixed so the ribbons' arithmetic and
    /// the labels' layout can't disagree — the two are computed from the same
    /// number rather than one measured off the other.
    private static let rowHeight: CGFloat = 40
    /// The connected side is wider than the wallet side because its names are:
    /// a counterparty is often an unnamed `…44b1`, or an app, while your own
    /// wallets are things you called "Main" and "Cold".
    private static let leftWidth: CGFloat = 128
    private static let rightWidth: CGFloat = 96
    /// Where the §439 bracket lives — outside the wallet column, so it can
    /// never cross a face or a name.
    private static let bracketGutter: CGFloat = 16
    /// `DS.Face.row` — a face here sits beside 14pt text in a 40pt row, which
    /// is precisely the tier's own definition. Named through the ramp rather
    /// than written as 26 so a change to the tier reaches the spine too.
    private static let faceSize: CGFloat = DS.Face.row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connected")
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textTertiary)

            Text(AddressConnections.headline(count: map.connectedCount))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            if let subhead = AddressConnections.subhead(count: map.connectedCount) {
                Text(subhead)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            if !map.nodes.isEmpty {
                spine.padding(.top, DS.Space.s4)
            }

            if let target = map.firstUnnamed {
                nameButton(target)
            }

            notes
        }
        // FULL WIDTH (prd §442, seen on a device). A `VStack` sizes to its
        // content, so the card was as wide as its own longest wrapped line —
        // it stopped a third of the way short of the field above it and read
        // as a layout fault rather than as a card.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    // MARK: - The spine

    /// Both columns and the ribbons between them, laid out on ONE height so
    /// the shorter side centres against the taller one.
    private var spine: some View {
        let rows = max(map.nodes.count, map.columns.count)
        let height = CGFloat(rows) * Self.rowHeight
        return HStack(spacing: DS.Space.s2) {
            VStack(spacing: 0) {
                ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                    nodeRow(node)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .frame(width: Self.leftWidth, height: height)

            ribbons
                .frame(maxWidth: .infinity)
                .frame(height: height)

            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    ForEach(Array(map.columns.enumerated()), id: \.element.id) { index, column in
                        columnRow(column)
                            .chartArrival(index: index, reduceMotion: reduceMotion)
                    }
                }
                .frame(width: Self.rightWidth, height: height)
                bracket(height: height)
            }
            .frame(width: Self.rightWidth + Self.bracketGutter, height: height)
        }
        // CONTAIN, not combine: the nodes are buttons, and a combined element
        // would swallow them and leave VoiceOver no way to open an address.
        // Each node carries its own sentence instead.
        .accessibilityElement(children: .contain)
    }

    /// One connected address. **Name on the left, face on the RIGHT** — the
    /// two columns face each other across the gap, so every ribbon leaves a
    /// face and arrives at one rather than at the end of a word.
    private func nodeRow(_ node: AddressConnections.Node) -> some View {
        HStack(spacing: DS.Space.s2) {
            Button {
                DSHaptic.selection()
                light(node)
            } label: {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(node.name)
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(transactionCount(node.count))
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                // The whole area is the door, not just the rendered text —
                // without this a short name ("Mom") leaves most of its own row
                // dead to the touch.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(nodeDescription(node)))
            .accessibilityHint(Text("Opens this address"))

            // **The naming affordance, ON the node** — an unnamed connection
            // wears a dashed ring instead of a face and offers the pencil
            // beside it. §295 put naming only in the button below, which is
            // still there and still targets the first unnamed over EVERY
            // connection (including ones the cap didn't draw) — but a person
            // looking at a row of hex wants to fix THAT row, and had to
            // read a button at the bottom of the card to discover they could.
            if node.named {
                WalletFace(address: node.address, size: Self.faceSize, circular: true)
            } else {
                Button {
                    DSHaptic.tap()
                    onName(node)
                } label: {
                    Circle()
                        .strokeBorder(DS.tint.opacity(0.55),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: Self.faceSize, height: Self.faceSize)
                        .overlay {
                            Image(systemName: "square.and.pencil")
                                .dsGlyph(11, weight: .semibold)
                                .foregroundStyle(DS.tint)
                        }
                        .dsTapTarget(Circle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Name \(node.name)"))
            }
        }
        .frame(height: Self.rowHeight)
    }

    /// One of your wallets. Face on the LEFT — see `nodeRow`. **No figure**:
    /// §435 struck every money reading off this screen, so `column.usd` is
    /// deliberately unread here even though the model still carries it for
    /// callers elsewhere.
    private func columnRow(_ column: AddressConnections.Column) -> some View {
        HStack(spacing: DS.Space.s2) {
            // `column.id` and not an unfolded address, and safe for a FACE
            // specifically: `AddressBook.key(for:)` lowercases hex and leaves
            // base58 alone, and `WalletFace` folds its seed to lowercase
            // itself — so the key seeds the identical identicon the same
            // wallet wears everywhere else. (`Node` carries a separate
            // unfolded `address` because it feeds a DOOR, where the EIP-55
            // checksum is load-bearing; nothing here is passed onward.)
            WalletFace(address: column.id, size: Self.faceSize, circular: true)
            Text(column.name)
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// One curve per relationship, all the same weight. Drawn in a single
    /// `Path` rather than a shape per edge: at six nodes and five wallets that
    /// is up to thirty views doing nothing but stroking a line.
    ///
    /// THREE layers, and the split is what keeps §295's ruling intact. The
    /// settled ribbons and the NEW ones are the same weight and the same
    /// colour — a new connection is drawn dashed and drawn LAST, which is a
    /// statement about when we first saw it and not about how much it matters.
    /// The LIT layer is a transient answer to a tap and is on screen for a
    /// quarter of a second.
    private var ribbons: some View {
        GeometryReader { geo in
            ZStack {
                ribbonPath(in: geo.size) { !newNodeIDs.contains($0.id) }
                    .trim(from: 0, to: drawn)
                    .stroke(DS.textTertiary,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ribbonPath(in: geo.size) { newNodeIDs.contains($0.id) }
                    .trim(from: 0, to: drawn)
                    .stroke(DS.textTertiary,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                               dash: [3, 4]))
                if let litNode {
                    ribbonPath(in: geo.size) { $0.id == litNode }
                        .stroke(DS.tint,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            guard drawn == 0 else { return }
            guard !reduceMotion else { drawn = 1; return }
            // Longer than a wipe: the point is to follow one line at a time,
            // and at `ChartEntrance.wipe` a busy map is a flicker.
            withAnimation(.easeInOut(duration: 1.1).delay(ChartEntrance.lead)) { drawn = 1 }
        }
        // A `Path` reads as nothing to VoiceOver, and everything it draws is
        // spoken by the node it leaves from ("…reaches Main, Trading").
        .accessibilityHidden(true)
    }

    /// **TWO OF YOUR OWN WALLETS, JOINED** (prd §439) — money that moved
    /// between two wallets you watch, directly.
    ///
    /// Drawn apart from the ribbons because it is a different KIND of fact,
    /// not a stronger one: every ribbon says "this stranger reached that
    /// wallet of yours", and this says "you moved funds between two of your
    /// own". It is the only line on the card with a face at both ends, so it
    /// is a relationship rather than an attachment — which is why it is a
    /// bracket in the tint rather than one more grey curve.
    ///
    /// §295's ruling still binds: it carries no weight, no arrow and no
    /// amount. The distinction is kind, not size.
    ///
    /// In the GUTTER, outside the wallet column, so it can never cross a face
    /// or a name however many pairs there are.
    @ViewBuilder
    private func bracket(height: CGFloat) -> some View {
        let pairs = walletLinkRows
        if !pairs.isEmpty {
            let inset = self.inset(count: map.columns.count, of: height)
            Path { path in
                for (i, pair) in pairs.enumerated() {
                    let a = inset + centre(pair.0)
                    let b = inset + centre(pair.1)
                    // Each successive pair bows a little further out, so two
                    // brackets over the same column never trace one line.
                    let x0 = Self.rightWidth - 2
                    let bow = x0 + Self.bracketGutter * (0.55 + 0.35 * CGFloat(i % 2))
                    path.move(to: CGPoint(x: x0, y: a))
                    path.addCurve(to: CGPoint(x: x0, y: b),
                                  control1: CGPoint(x: bow, y: a),
                                  control2: CGPoint(x: bow, y: b))
                }
            }
            .trim(from: 0, to: drawn)
            .stroke(DS.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: Self.rightWidth + Self.bracketGutter, height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// §439's pairs as ROW INDEXES into the drawn wallet column.
    ///
    /// A link whose either end isn't a drawn column is dropped rather than
    /// clamped — the same rule every ribbon obeys, and clamping would draw a
    /// bracket to a wallet that isn't there.
    private var walletLinkRows: [(Int, Int)] {
        map.walletLinks.compactMap { link in
            guard let a = map.columns.firstIndex(where: { $0.id == link.a }),
                  let b = map.columns.firstIndex(where: { $0.id == link.b }),
                  a != b
            else { return nil }
            return (min(a, b), max(a, b))
        }
    }

    /// The ribbons leaving the nodes this filter admits.
    private func ribbonPath(in size: CGSize,
                            where include: (AddressConnections.Node) -> Bool) -> Path {
        Path { path in
            let width = size.width
            let leftInset = inset(count: map.nodes.count, of: size.height)
            let rightInset = inset(count: map.columns.count, of: size.height)
            for (nodeIndex, node) in map.nodes.enumerated() where include(node) {
                let from = leftInset + centre(nodeIndex)
                for key in node.walletKeys {
                    guard let columnIndex = map.columns.firstIndex(where: { $0.id == key })
                    else { continue }
                    let to = rightInset + centre(columnIndex)
                    path.move(to: CGPoint(x: 0, y: from))
                    // Horizontal control points: the curve leaves and arrives
                    // flat, so a ribbon reads as joining two rows rather than
                    // pointing at the gap between them.
                    path.addCurve(to: CGPoint(x: width, y: to),
                                  control1: CGPoint(x: width / 2, y: from),
                                  control2: CGPoint(x: width / 2, y: to))
                }
            }
        }
    }

    /// Lights a node's ribbons, then opens it.
    ///
    /// The delay is the whole point and is short enough not to read as lag:
    /// opening immediately covers the drawing with a sheet, so the one moment
    /// the diagram could confirm what you tapped is the moment it is hidden.
    /// Reduce Motion skips straight through — the light is decoration, and the
    /// card it opens carries the same facts in words.
    private func light(_ node: AddressConnections.Node) {
        guard !reduceMotion else { onOpen(node); return }
        withAnimation(.easeOut(duration: 0.12)) { litNode = node.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.easeIn(duration: 0.16)) { litNode = nil }
            onOpen(node)
        }
    }

    /// Where a side's stack starts, so a short side centres against the tall one.
    private func inset(count: Int, of height: CGFloat) -> CGFloat {
        max(0, (height - CGFloat(count) * Self.rowHeight) / 2)
    }

    private func centre(_ index: Int) -> CGFloat {
        CGFloat(index) * Self.rowHeight + Self.rowHeight / 2
    }

    // MARK: - The action, and the caveats

    /// The card's naming prompt, and only when a connected address has no name.
    ///
    /// An address that has moved real money with two of your wallets and still
    /// reads as hex is the best naming prompt this app can show — and naming it
    /// rewrites every landed transfer that carries it (`CounterpartyRetitle`),
    /// so one tap fixes the past as well as the future. It targets the FIRST
    /// unnamed one; picking the busiest would be a ranking.
    ///
    /// Its target is drawn from EVERY connection, not the drawn prefix, so the
    /// prompt cannot vanish behind the display cap (`Map.firstUnnamed`). That
    /// means it can name a node that isn't on screen — correct, and why the
    /// button says which address it is rather than just "Name this address".
    private func nameButton(_ target: AddressConnections.Node) -> some View {
        Button {
            DSHaptic.selection()
            onName(target)
        } label: {
            Text(String(localized: "Name \(target.name)"))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(DS.page)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(DS.textPrimary,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .padding(.top, DS.Space.s4)
    }

    /// THE FACTS THE PICTURE CANNOT DRAW (§435's ruling, kept verbatim in
    /// intent): what wasn't drawn, which of your wallets nothing reaches,
    /// whether any two of yours have dealt with each other, and since when any
    /// of this is true.
    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            // §439 in WORDS as well as in the bracket. The drawing states it
            // as the one tinted line on the card, which is the right way to
            // SHOW it and not a reliable way to READ it — at two watched
            // wallets there is nothing else on the card to compare it
            // against. This is the relationship the person asked for by name,
            // so it gets a sentence as well as a line.
            if let joined = walletLinkNote { note(joined) }
            // Named, not just counted: the cap cuts by first-dealt order, so
            // everything behind it is a NEWER connection than everything drawn.
            if let hidden = AddressConnections.hiddenNote(hidden: map.hiddenCount,
                                                          names: map.hiddenNames) {
                note(hidden)
            }
            if let untouched = AddressConnections.untouchedNote(
                map.untouchedWalletNames, connectedCount: map.connectedCount) {
                note(untouched)
            }
            // The honesty line every wallet running total carries: a wallet
            // watched four days ago and one watched in March are not
            // comparable, and a card that quietly compared them would be
            // stating a fact it can't know.
            note(String(localized: "Since you started watching each wallet."))
        }
        .padding(.top, DS.Space.s3)
    }

    /// The §439 sentence. Names the PAIR, never a count — "2 direct links" is
    /// the tally the module doctrine forbids, and at the two-wallet corpus
    /// this reading exists for there is exactly one pair to name anyway. Past
    /// two pairs it names how many of your wallets are involved rather than
    /// every pairing, which is arithmetic nobody reads.
    private var walletLinkNote: String? {
        let pairs = walletLinkRows
        guard !pairs.isEmpty else { return nil }
        if pairs.count == 1 {
            let a = map.columns[pairs[0].0].name, b = map.columns[pairs[0].1].name
            return String(localized: "\(a) and \(b) have moved funds to each other.")
        }
        let involved = Set(pairs.flatMap { [$0.0, $0.1] }).count
        return String(localized: "\(involved) of your wallets have moved funds to each other.")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func transactionCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 transaction")
                   : String(localized: "\(count) transactions")
    }

    /// One node's ribbons as a sentence, for VoiceOver — the facts the drawing
    /// carries for this row, since a `Path` reads as nothing at all.
    private func nodeDescription(_ node: AddressConnections.Node) -> String {
        let wallets = node.walletKeys.compactMap { key in
            map.columns.first { $0.id == key }?.name
        }
        return String(localized:
            "\(node.name), \(transactionCount(node.count)), reaches \(wallets.joined(separator: ", "))")
    }
}
