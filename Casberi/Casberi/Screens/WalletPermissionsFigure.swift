import SwiftUI

/// **PERMISSIONS' BOX IS YOUR BALANCE, REACHED (prd §1710, retiring §1654's
/// pack of apps; §1656's fills and §1677's delegates kept).**
///
/// One disc is what the scope's wallets hold. A delegate or module reaches
/// its accounts' holdings: when that is all of it the disc is amber, the
/// balance on it and "All of it" under; the disc no longer sizes a circle by
/// a share it does not have (§1677's two delegates each took the pack's floor
/// and filled the box with no figure). An app's grants are circles inside the
/// disc at their dollars, amber with no limit, the charts' tint capped; the
/// grey left over is what nothing can move.
///
/// Beside the disc: the dollars in reach, then who — a delegate or module by
/// its key glyph, never `AssetMark` on a hex name (the ".." disc), an app by
/// its fill — five at most, then "N more". Under it, the key. Empty, the
/// pack's skeleton with "No permissions" (§769, §1677), no key.
///
/// A tap opens what it names: a grant's sheet or the Approvals list, a
/// delegate's sheet, a module's row (`walletOpenPermission`).
///
/// No plate (§782): the disc is the figure, on the box's well. Amber is the
/// rows' status hue; the tint is the charts' (§1385). Hide balances masks
/// every figure; the areas stay, as shares.
struct WalletPermissionsFigure: View {
    let grants: [WalletApprovalExposure.Grant]
    var acting: [PermissionsPack.Acting] = []
    /// What each wallet in scope holds (`PermissionsPack.heldByAccount`).
    var held: [String: Double] = [:]
    /// When these grants were read, while they stand on an earlier launch's
    /// reading (prd §1709); nil once the live read lands.
    var asOf: Date? = nil
    /// Authorizations given to Aztec apps, listed under the box (prd §1762):
    /// with any, an empty pack does not say "No permissions".
    var aztecGrants = 0
    let open: (PermissionsPack.Piece) -> Void

    static let diameter: CGFloat = 200
    static let rowCap = 5

    var body: some View {
        let pieces = PermissionsPack.pieces(grants, acting: acting, held: held)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let money: (Double) -> String = { mask ?? WalletValue.exactMoney($0) }
        if pieces.isEmpty {
            // What would fill it, empty (§769): the pack's own drawing, the
            // short state on it.
            WalletScopeEmptyFigure(section: .permissions, padded: false,
                                   words: aztecGrants > 0 ? String(localized: "\(aztecGrants) to Aztec apps") : nil)
        } else {
            let disc = PermissionsPack.disc(pieces, acting: acting, held: held)
            let inner = PermissionsPack.inner(pieces, disc: disc)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(alignment: .center, spacing: DS.Space.s4) {
                    PermissionsDisc(pieces: pieces, inner: inner, disc: disc, money: money, open: open)
                        .frame(width: Self.diameter, height: Self.diameter)
                    column(pieces, disc: disc, figureOnDisc: disc.whole && inner.isEmpty, money: money)
                }
                legend(inner, disc: disc)
                if let asOf {
                    // The balance's own phrase and ink (prd §825, §1593): a
                    // kept reading is never presented as current (§83).
                    Text("as of \(AccountPageShape.ago(asOf))")
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Beside the disc

    /// The figure (unless the disc carries it), then who reaches it.
    @ViewBuilder
    private func column(_ pieces: [PermissionsPack.Piece], disc: PermissionsPack.Disc,
                        figureOnDisc: Bool, money: @escaping (Double) -> String) -> some View {
        let named = pieces.filter { !$0.isMore }
        let shown = Array(named.prefix(Self.rowCap))
        let rest = named.count - shown.count + (pieces.last?.isMore == true ? (pieces.last?.apps ?? 0) : 0)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !figureOnDisc {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: figure(disc, money: money))
                        .dsText(.heading28)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: caption(disc, money: money))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(shown) { piece in
                    Button {
                        DSHaptic.selection()
                        open(piece)
                    } label: {
                        whoRow(piece, disc: disc)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                }
                if rest > 0 {
                    Text(verbatim: String(localized: "\(rest) more"))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The dollars in reach; "Everything" when a delegate acts and no balance
    /// is read; the balance when nothing in reach is priced.
    private func figure(_ disc: PermissionsPack.Disc, money: (Double) -> String) -> String {
        if let reach = disc.reach { return money(reach) }
        if disc.whole { return String(localized: "Everything") }
        return disc.held > 0 ? money(disc.held) : String(localized: "Unpriced")
    }

    /// "of $12,480 in reach", "All of it", or "in reach" with no balance read;
    /// "Nothing priced in reach" under the balance when no grant is priced.
    private func caption(_ disc: PermissionsPack.Disc, money: (Double) -> String) -> String {
        if disc.whole { return String(localized: "All of it") }
        if disc.reach == nil { return String(localized: "Nothing priced in reach") }
        if disc.held > 0 { return String(localized: "of \(money(disc.held)) in reach") }
        return String(localized: "in reach")
    }

    /// A delegate or module: its key glyph in amber, its name, what it is.
    /// An app: its fill, its name.
    @ViewBuilder
    private func whoRow(_ piece: PermissionsPack.Piece, disc: PermissionsPack.Disc) -> some View {
        if piece.isActing {
            HStack(spacing: DS.Space.s2) {
                DSGlyphLead(glyph: piece.module ? "puzzlepiece.extension.fill" : "key.fill",
                            tint: DS.attention, size: DS.Face.row)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: piece.name)
                        .dsText(.body17)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: piece.symbols.first ?? "")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: DS.Space.s2) {
                Circle()
                    .fill(PermissionsCircle.fill(piece, onAmber: false))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(verbatim: piece.name)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: piece.unlimited ? String(localized: "No limit") : String(localized: "Capped")))
        }
    }

    // MARK: - The key

    /// Names only what the disc shows: no limit, capped, and the grey nothing
    /// reaches.
    private func legend(_ inner: [PermissionsPack.Piece], disc: PermissionsPack.Disc) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            if disc.whole || inner.contains(where: { $0.unlimited && !$0.isMore }) {
                key(PermissionsCircle.unlimitedFill, word: String(localized: "No limit"))
            }
            if !disc.whole, inner.contains(where: { !$0.unlimited && !$0.isMore }) {
                key(PermissionsCircle.cappedFill, word: String(localized: "Capped"))
            }
            if !disc.whole, disc.held > (disc.reach ?? 0) {
                key(PermissionsDisc.groundFill, word: String(localized: "Out of reach"))
            }
            Spacer(minLength: 0)
        }
        .dsText(.subhead12)
        .lineLimit(1)
    }

    private func key(_ fill: Color, word: String) -> some View {
        HStack(spacing: DS.Space.s1 + 2) {
            Circle().fill(fill)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: word).foregroundStyle(DS.textTertiary)
        }
    }
}

/// The disc (prd §1710): the balance, grey, amber when a delegate or module
/// reaches all of it; the grants inside at their dollars.
struct PermissionsDisc: View {
    let pieces: [PermissionsPack.Piece]
    let inner: [PermissionsPack.Piece]
    let disc: PermissionsPack.Disc
    let money: (Double) -> String
    let open: (PermissionsPack.Piece) -> Void

    static var groundFill: Color { DS.fillStrong }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = WalletPermissionsFigure.diameter
        let circles = PermissionsPack.inside(inner.map(\.usd), scale: disc.scale, diameter: d)
        ZStack(alignment: .topLeading) {
            ground(d)
            ForEach(Array(inner.enumerated()), id: \.element.id) { i, piece in
                let c = circles[i]
                Button {
                    DSHaptic.selection()
                    open(piece)
                } label: {
                    PermissionsCircle(piece: piece, diameter: c.radius * 2,
                                      figure: money(piece.usd), onAmber: disc.whole)
                        .contentShape(Circle())
                }
                .buttonStyle(DSTileButtonStyle())
                .frame(width: c.radius * 2, height: c.radius * 2)
                .position(c.center)
                .settleIn(delay: Double(i) * 0.06)
                .accessibilityLabel(Text(verbatim: label(piece)))
            }
        }
        .frame(width: d, height: d)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: inner.map { "\($0.id):\($0.usd)" })
    }

    /// The whole disc is a door only when it stands for the delegates and
    /// modules: a tap opens the first of them.
    @ViewBuilder
    private func ground(_ d: CGFloat) -> some View {
        if disc.whole, let first = pieces.first(where: \.isActing) {
            Button {
                DSHaptic.selection()
                open(first)
            } label: {
                ZStack {
                    Circle().fill(PermissionsCircle.unlimitedFill)
                    if inner.isEmpty {
                        VStack(spacing: 2) {
                            Text(verbatim: disc.held > 0 ? money(disc.held) : String(localized: "Everything"))
                                .dsText(.heading34)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(verbatim: String(localized: "All of it"))
                                .dsText(.subhead12)
                                .opacity(0.72)
                        }
                        .foregroundStyle(PermissionsCircle.amberInk)
                        .padding(.horizontal, DS.Space.s4)
                    }
                }
                .frame(width: d, height: d)
                .contentShape(Circle())
            }
            .buttonStyle(DSTileButtonStyle())
            .accessibilityLabel(Text(verbatim: disc.held > 0
                ? String(localized: "Can move all of it, \(money(disc.held))")
                : String(localized: "Can move everything")))
        } else {
            Circle().fill(Self.groundFill)
                .frame(width: d, height: d)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: disc.held > 0
                    ? String(localized: "You hold \(money(disc.held))")
                    : String(localized: "In reach")))
        }
    }

    private func label(_ piece: PermissionsPack.Piece) -> String {
        var parts = [piece.name, money(piece.usd)]
        parts += piece.symbols.prefix(3)
        if piece.unlimited { parts.append(String(localized: "No limit")) }
        return parts.joined(separator: ", ")
    }
}

/// One circle inside the disc (prd §1710, fills §1656): the figure leads,
/// the name under it where there is room.
///
///   · 96pt and wider: the figure at `heading24` over the name.
///   · 48pt and wider: the figure at `subhead12`.
///   · Narrower: the fill alone; the row beside the disc names it.
struct PermissionsCircle: View {
    let piece: PermissionsPack.Piece
    let diameter: CGFloat
    let figure: String
    /// The disc is amber (a delegate reaches all of it): every circle on it
    /// is a dark well, its limit left to the list.
    var onAmber = false

    static let named: CGFloat = 96
    static let figured: CGFloat = 48

    static var unlimitedFill: Color { DS.attention }
    static var cappedFill: Color { DS.tint }
    static let amberInk = Color.black.opacity(0.88)

    static func fill(_ piece: PermissionsPack.Piece, onAmber: Bool) -> Color {
        if onAmber { return Color.black.opacity(0.22) }
        if piece.isMore { return DS.textTertiary }
        return piece.unlimited ? unlimitedFill : cappedFill
    }

    /// Dark words on amber, white on the tint and on a dark well.
    private var ink: Color {
        if onAmber { return Self.amberInk }
        if piece.isMore { return DS.textPrimary }
        return piece.unlimited ? Self.amberInk : .white
    }

    var body: some View {
        ZStack {
            Circle().fill(Self.fill(piece, onAmber: onAmber))
            if diameter >= Self.named {
                VStack(spacing: 2) {
                    figureText(.heading24)
                    Text(verbatim: piece.name)
                        .dsText(.subhead12)
                        .opacity(0.72)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, DS.Space.s2)
            } else if diameter >= Self.figured {
                figureText(.subhead12)
                    .padding(.horizontal, DS.Space.s1)
            }
        }
        .foregroundStyle(ink)
        .frame(width: diameter, height: diameter)
    }

    private func figureText(_ rung: DSTextStyle) -> some View {
        Text(verbatim: figure)
            .dsText(rung)
            .fontWeight(.bold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
