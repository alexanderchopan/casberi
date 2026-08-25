import SwiftUI

/// The delegate graph as a FIGURE — actors down the left, the accounts they
/// can act for down the right, one ribbon each (prd §467, 2026-08-24).
///
/// **Why this replaced a list of sentences.** The room drew one row per link
/// reading "<name> · Can act for <name>": the same two names in prose, once
/// per link, so the reader parsed a sentence per row and assembled the graph
/// in their head. A delegate relationship has a SHAPE — somebody on one side,
/// the account they can act for on the other, a line between — and the shape
/// is legible before a single name is read. That is the whole argument for
/// drawing it, and it is the argument the design made.
///
/// **§295's ruling is reused wholesale**, which is why this looks deliberately
/// plain: every ribbon is the same weight and no node carries a hue, because
/// this card makes NO claim that one relationship matters more than another.
/// Nothing here may be sized or coloured to suggest a ranking that was never
/// computed. The direction is stated ONCE in the caption beneath, in words,
/// rather than repeated per row as an arrow nobody reads twice.
///
/// **Dedup is the load-bearing part.** One account can authorize several
/// delegates and one delegate can act for several accounts, so the same
/// address routinely appears in more than one link. Drawn naively that is the
/// same face stacked twice at two different heights with two ribbons leaving
/// two copies of one person — which reads as four parties where there are
/// three. Each side is reduced to its DISTINCT addresses, in first-appearance
/// order (`links` is already totally ordered, so this is stable across opens),
/// and a ribbon connects the two rows that address actually occupies.
struct VibenetLinkSpine: View {
    let links: [VibenetDelegateLink]
    /// How an address is named. Handed in rather than resolved here, so this
    /// figure can never name an account differently from the roster above it.
    let name: (String) -> String
    /// Scope the room to a tapped node, or nil where there is nowhere to go
    /// (prd §476). nil keeps every node a plain read rather than pretending
    /// at a door — the same rule the key tray's own rows follow.
    var onPick: ((String) -> Void)? = nil
    let reduceMotion: Bool

    /// Row pitch. Tall enough that two adjacent faces read as separate nodes
    /// and tight enough that four links stay inside a card.
    private static let pitch: CGFloat = 34
    /// `badge` — the ramp's smallest rung, and the right one: these sit
    /// beside dense inline text as MARKS identifying a node, never as
    /// portraits. Caught by `face-ramp-audit`, which is what the ramp is
    /// for: the first cut invented an 18pt face, off the ramp entirely.
    private static let faceSize: CGFloat = DS.Face.badge
    /// How far the two columns sit apart, as a share of the width. The ribbon
    /// needs a real run to read as a connection rather than a hyphen.
    private static let leftColumn: CGFloat = 0.42

    /// The distinct addresses on each side, in first-appearance order.
    private var actors: [String] { Self.distinct(links.map(\.to)) }
    private var accounts: [String] { Self.distinct(links.map(\.from)) }

    static func distinct(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for address in addresses {
            let key = address.lowercased()
            if seen.insert(key).inserted { out.append(address) }
        }
        return out
    }

    private var rows: Int { max(actors.count, accounts.count) }
    private var height: CGFloat { CGFloat(max(1, rows)) * Self.pitch }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let leftX = width * Self.leftColumn
            let rightX = width * 0.58
            ZStack(alignment: .topLeading) {
                ribbons(leftX: leftX, rightX: rightX)
                column(actors, x: 0, alignment: .leading, emphasised: false)
                column(accounts, x: rightX, alignment: .leading, emphasised: true)
            }
        }
        .frame(height: height)
    }

    /// The connections themselves — ONE `Path` per link, all the same weight.
    /// A cubic rather than a straight line for the reason the address book's
    /// own spine gives: both endpoints sit in the same horizontal band, and a
    /// straight run between two rows one pitch apart reads as a table rule
    /// rather than as a connection.
    @ViewBuilder
    private func ribbons(leftX: CGFloat, rightX: CGFloat) -> some View {
        Path { path in
            for link in links {
                guard let fromRow = index(of: link.to, in: actors),
                      let toRow = index(of: link.from, in: accounts) else { continue }
                let start = CGPoint(x: leftX - 6, y: rowCentre(fromRow))
                let end = CGPoint(x: rightX - 6, y: rowCentre(toRow))
                let run = max(24, end.x - start.x)
                path.move(to: start)
                path.addCurve(to: end,
                              control1: CGPoint(x: start.x + run * 0.55, y: start.y),
                              control2: CGPoint(x: end.x - run * 0.55, y: end.y))
            }
        }
        .stroke(DS.fillLine, style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    @ViewBuilder
    private func column(_ addresses: [String], x: CGFloat,
                        alignment: HorizontalAlignment, emphasised: Bool) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            ForEach(Array(addresses.enumerated()), id: \.offset) { index, address in
                node(address, emphasised: emphasised)
                    .frame(height: Self.pitch, alignment: .leading)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: x)
    }

    /// One node — a door when the caller gave us somewhere to go, a plain
    /// read otherwise. §295's same-weight ruling survives either way: a
    /// tappable node is not a ranked one, and nothing here is sized or
    /// coloured differently for carrying a handler.
    @ViewBuilder
    private func node(_ address: String, emphasised: Bool) -> some View {
        Group {
            if let onPick {
                Button {
                    DSHaptic.selection()
                    onPick(address)
                } label: {
                    nodeBody(address, emphasised: emphasised).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsHover()
            } else {
                nodeBody(address, emphasised: emphasised)
            }
        }
    }

    /// The two columns keep their DIFFERENT weights, which is not a ranking
    /// and so not §295's business: the left column is who ACTS and the right
    /// is the account acted for, and the weight is what tells a reader which
    /// side of the sentence a node is on before any name is read. Making both
    /// primary (a slip while wiring the tap) turned the figure into two
    /// identical columns joined by lines.
    private func nodeBody(_ address: String, emphasised: Bool) -> some View {
        HStack(spacing: 7) {
            WalletFace(address: address, size: Self.faceSize, circular: true)
            Text(name(address))
                .dsText(.callout15)
                .fontWeight(emphasised ? .semibold : .regular)
                .foregroundStyle(emphasised ? DS.textPrimary : DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func rowCentre(_ row: Int) -> CGFloat {
        CGFloat(row) * Self.pitch + Self.pitch / 2
    }

    private func index(of address: String, in column: [String]) -> Int? {
        column.firstIndex { $0.caseInsensitiveCompare(address) == .orderedSame }
    }
}
