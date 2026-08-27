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
/// computed.
///
/// **WHICH WAY AUTHORITY RUNS IS DRAWN NOW (2026-08-26, prd §482).** Reported:
/// *"hard to tell who can do what in terms of parent child… presuming the
/// first one has greater authority but not really clear."* The presumption is
/// the normal left-to-right reading and it was exactly backwards: `to` (the
/// DELEGATE) was drawn on the left and `from` (the account that authorized
/// it) on the right, so the face you read first held the least power. The
/// only signal was the right column's heavier weight, and weight reads as
/// importance, not as role — it half-said the right thing in a language that
/// cannot say roles at all.
///
/// Two changes, and §467's refusal of per-row arrows survives both. **The
/// columns are swapped**, so the account that granted the power leads and the
/// row reads left-to-right in one direction — the weight difference below now
/// AGREES with the roles instead of contradicting them. **And the roles are
/// named at the head of each column** rather than in a caption 60pt below in
/// tertiary ink: §467 was right that the direction should be said once rather
/// than per row, and wrong about where once is. Named at the top, one label
/// serves four links as easily as one.
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

    /// The node whose ribbons are lit (prd §479) — set for a beat on tap and
    /// cleared before the destination opens. `@State`, so it cannot outlive
    /// the view; a light that survived the gesture would be a ranking.
    @State private var lit: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

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
    ///
    /// `accounts` is `from` — the side that AUTHORIZED — and it draws on the
    /// LEFT (prd §482); `actors` is `to`, the delegate, and draws on the
    /// right. Named for what they are rather than for where they sit, so a
    /// future layout change cannot make these two names lie.
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
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // THE ROLES, NAMED ONCE (prd §482). `label11` tertiary, the
                // quietest rung on the ramp: these are what the columns ARE,
                // not a reading of their own, and a heading that competes
                // with the names beneath it would be a third thing to read.
                HStack(spacing: 0) {
                    Text(String(localized: "Account"))
                        .frame(width: rightX, alignment: .leading)
                    Text(String(localized: "Can act for it"))
                    Spacer(minLength: 0)
                }
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
                ZStack(alignment: .topLeading) {
                    ribbons(leftX: leftX, rightX: rightX)
                    column(accounts, x: 0, alignment: .leading, emphasised: true)
                    column(actors, x: rightX, alignment: .leading, emphasised: false)
                }
                .frame(height: height)
            }
        }
        .frame(height: height + Self.headRoom)
    }

    /// What the column heads add to the figure's own height — the label's
    /// line height plus the gap under it. Spelled out because the frame is
    /// computed rather than laid out: a `GeometryReader` reports the size it
    /// was GIVEN, so a head drawn inside one that did not account for it is
    /// a head drawn over the first row.
    private static let headRoom: CGFloat = 15 + DS.Space.s1

    /// The connections themselves — ONE `Path` per link, all the same weight.
    /// A cubic rather than a straight line for the reason the address book's
    /// own spine gives: both endpoints sit in the same horizontal band, and a
    /// straight run between two rows one pitch apart reads as a table rule
    /// rather than as a connection.
    @ViewBuilder
    private func ribbons(leftX: CGFloat, rightX: CGFloat) -> some View {
        // TWO PASSES: every ribbon at rest, then the tapped node's own on top
        // (prd §479). The address book's spine has answered a tap this way
        // since §441 — "a tapped spine node LIGHTS its own ribbons for 240ms
        // before the sheet covers them" — and this spine, which is the same
        // drawing, did not. Free consistency, and it answers the one question
        // a tap on a node raises: which of these lines was I just told about?
        //
        // §295's same-weight ruling is intact: the light is a TRANSIENT answer
        // to a gesture, not a claim that one relationship matters more. At
        // rest every ribbon is identical, exactly as before.
        ZStack {
            ribbonPath(leftX: leftX, rightX: rightX, only: nil)
                .stroke(DS.fillLine, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            if let lit {
                ribbonPath(leftX: leftX, rightX: rightX, only: lit)
                    .stroke(Self.mark.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .transition(.opacity)
            }
        }
    }

    /// The ribbons, or just the ones touching one address.
    private func ribbonPath(leftX: CGFloat, rightX: CGFloat, only address: String?) -> Path {
        Path { path in
            for link in links {
                if let address,
                   link.from.caseInsensitiveCompare(address) != .orderedSame,
                   link.to.caseInsensitiveCompare(address) != .orderedSame { continue }
                // LEFT is the account that authorized, RIGHT is its
                // delegate (prd §482) — the ribbon must follow the columns
                // or every line joins the wrong two faces while the figure
                // still looks perfectly well drawn.
                guard let fromRow = index(of: link.from, in: accounts),
                      let toRow = index(of: link.to, in: actors) else { continue }
                let start = CGPoint(x: leftX - 6, y: rowCentre(fromRow))
                let end = CGPoint(x: rightX - 6, y: rowCentre(toRow))
                let run = max(24, end.x - start.x)
                path.move(to: start)
                path.addCurve(to: end,
                              control1: CGPoint(x: start.x + run * 0.55, y: start.y),
                              control2: CGPoint(x: end.x - run * 0.55, y: end.y))
            }
        }
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
                    // LIGHT, THEN GO (prd §479, §441's own order): the beat
                    // happens before the sheet covers the drawing, so there is
                    // something to have seen. Reduce Motion skips straight to
                    // the destination — a light that cannot fade is a light
                    // that stays on.
                    if reduceMotion {
                        onPick(address)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) { lit = address }
                        Task {
                            try? await Task.sleep(nanoseconds: 240_000_000)
                            withAnimation(.easeOut(duration: 0.2)) { lit = nil }
                            onPick(address)
                        }
                    }
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
    /// and so not §295's business: the left column is the account that
    /// AUTHORIZED and the right is its delegate, and the weight tells a
    /// reader which side of the sentence a node is on before any name is
    /// read. Making both primary (a slip while wiring the tap) turned the
    /// figure into two identical columns joined by lines.
    ///
    /// Since §482 the heavier side is the one with more authority, so the
    /// weight now AGREES with the column heads instead of pointing the other
    /// way. Kept rather than dropped for that reason: two signals saying one
    /// thing is redundancy, which is what a figure about permissions should
    /// have.
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
