import SwiftUI

/// The wallet room's ONE row shape (prd §212, 2026-07-25 — the Cash App pass).
///
/// Before this, every read in the room picked its own container and its own
/// anatomy: Aave and Morpho were full cards with three-stat layouts, the
/// per-wallet split was a card of face-plus-sparkline-plus-pill rows, the
/// warnings read was a card of badge capsules, and a transaction in the
/// history page was a `dsListCardRow`. Six surfaces of near-identical weight
/// stacked before a single transaction — and when everything is a parcel,
/// nothing leads.
///
/// The fix isn't fewer reads, it's fewer containers. Every one of those reads
/// fits this anatomy: a round mark, a title in the money face, a gray subline,
/// and a trailing value or chevron. Rank comes from POSITION under a small
/// gray label, not from having a surface of your own.
///
/// FLAT BY LAW, like everything else in this file's neighbourhood: these draw
/// at the head of an eager screen, so the body is a plain HStack of Text with
/// no erasure and no generic `Widget`/`Row` mount (see the render-depth lesson
/// in CLAUDE.md, paid three times).
///
/// ONE FONT, per prd §190 — the title's weight is what says "tappable", not a
/// second typeface. See `DSTextStyle.heading17` for why the rounded face the
/// Cash App borrow wanted here was the one part of it that got refused. (That
/// reasoning arrived on a wallet-only `rowTitle17` rung; it folded into the
/// app's shared row-title rung on 2026-08-03 — same size, same weight, same
/// face, one name.)
struct WalletRow<Trailing: View>: View {
    /// The leading 34pt mark. Five kinds, because the room has exactly five
    /// kinds of subject: a state (glyph), a wallet (its face — a wallet is a
    /// color in this app), a token or protocol (its REAL brand mark, 2026-08-04
    /// — see `.asset`), and a landed thing (its own `KindGlyph`, the same mark
    /// that thing wears in every other feed — the one case that keeps the
    /// app-icon squircle rather than the circle, because a thing is an object
    /// and the other three are people or states).
    enum Mark {
        case symbol(String, tint: Color)
        case face(String)
        case monogram(String, tint: Color)
        /// A token or protocol by name — its bundled brand mark where one
        /// exists, an honest monogram where it doesn't (`AssetMark`).
        ///
        /// It replaced hand-written initials on 2026-08-04: Aave read "AA",
        /// Morpho "MO", Hyperliquid "HL", while the app had shipped
        /// `brand-aave`, `brand-morpho` and `brand-hyperliquid` for months —
        /// so the room was drawing initials for logos it already owned. The
        /// old case survives for a subject that genuinely has no artwork
        /// anywhere (Spark, today).
        ///
        /// `tint` colours only the monogram fallback; `atRisk` puts the state
        /// on a badge, because re-tinting a real brand mark would be a lie
        /// about the brand.
        case asset(String, tint: Color, atRisk: Bool = false)
        /// Two assets overlapped — a liquidity pool's own pair.
        case pair(String, String)
        /// A landed thing's own `KindGlyph`. `symbol`/`tint` override the
        /// kind's glyph and hue for a room where the kind says nothing — see
        /// `WalletActionMark` (prd §516); nil everywhere else.
        case kind(ThingKind, flagged: Bool = false, symbol: String? = nil,
                  tint: Color? = nil)
    }

    let mark: Mark
    let title: String
    var subtitle: String? = nil
    /// True for a title that's worth reading in full ("Uniswap can spend
    /// unlimited USDC"); false for one whose tail is noise. Default clamps,
    /// because most rows here are labels, not sentences.
    var titleWraps = false
    @ViewBuilder var trailing: Trailing

    private static var markSize: CGFloat { DS.Face.list }

    var body: some View {
        HStack(alignment: titleWraps ? .top : .center, spacing: DS.Space.s3) {
            markView
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .lineLimit(titleWraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: titleWraps)
                if let subtitle {
                    Text(subtitle)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            trailing
        }
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .dsGlyph(14)
                .foregroundStyle(tint)
                .frame(width: Self.markSize, height: Self.markSize)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
        case .face(let address):
            WalletFace(address: address, size: Self.markSize, circular: true)
        case .monogram(let text, let tint):
            Text(text)
                .dsText(.badgeInitial11).foregroundStyle(tint)
                .frame(width: Self.markSize, height: Self.markSize)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
        case .asset(let name, let tint, let atRisk):
            AssetMark(name: name, size: Self.markSize, tint: tint,
                      badge: atRisk ? DS.attention : nil)
        case .pair(let first, let second):
            // A liquidity position is TWO assets, so its mark is two — real
            // brand discs where the app bundles them (2026-08-01). It replaced
            // a literal "UN" monogram on every Uniswap row, which named the
            // protocol the card's own header already names and said nothing
            // about which pool you were looking at.
            AssetPairMark(first: first, second: second, size: Self.markSize * 0.78)
                .frame(width: Self.markSize, height: Self.markSize)
        case .kind(let kind, let flagged, let symbol, let tint):
            KindGlyph(kind: kind, size: Self.markSize, tint: tint, symbol: symbol)
                .overlay(alignment: .bottomTrailing) {
                    if flagged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .dsGlyph(9, weight: .regular)
                            .foregroundStyle(DS.destructive)
                            .padding(3)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

extension WalletRow where Trailing == WalletRowChevron {
    /// The door form — a row whose whole job is to open something.
    init(mark: Mark, title: String, subtitle: String? = nil, titleWraps: Bool = false) {
        self.init(mark: mark, title: title, subtitle: subtitle,
                  titleWraps: titleWraps) { WalletRowChevron() }
    }
}

extension WalletRow where Trailing == EmptyView {
    /// The terminal form — a row that IS the whole read. No chevron, because
    /// a chevron promises more behind the tap (the honesty rule).
    init(terminal mark: Mark, title: String, subtitle: String? = nil) {
        self.init(mark: mark, title: title, subtitle: subtitle,
                  titleWraps: false) { EmptyView() }
    }
}

/// The room's one "there's more" glyph. Before the pass, a single wallet
/// screen carried a chevron, a "Where it's held ›" text link, a centered
/// "See all 128 transactions ›" link, a "Revoke ↗" pill, range chips and jump
/// chips — six grammars for the same promise. Two survive: this, on a row,
/// and a count-link on a section label (`WalletSectionLabel`).
struct WalletRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .dsGlyph(12)
            .foregroundStyle(DS.textTertiary)
            .accessibilityHidden(true)
    }
}

/// A row's trailing reading — the number, and optionally what it is. Money in
/// the money face, its qualifier in the quietest ink, right-aligned so a
/// column of rows reads as a column of figures.
struct WalletRowValue: View {
    let value: String
    var caption: String? = nil
    /// A real delta colors its caption; `nil` leaves it tertiary. Flat
    /// changes have no direction, so the caller passes nil rather than 0
    /// (`TokenChartStyle.isFlat`'s own rule).
    var change: Double? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .dsText(.price16).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .dsText(.label12)
                    .foregroundStyle(change.map { TokenChartStyle.accent(change: $0, scheme: scheme) }
                                     ?? DS.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The shape of what's ahead (2026-08-20, prd §417) — the widget's runway
/// (§382a) at card scale, above the Coming up rows.
///
/// Four rows say WHAT the next things are; a rail says how they're spread —
/// three deadlines bunched into next week reads completely differently from
/// three spaced over a quarter, and no list gives that at any length. The
/// widget's "Needs you" tile has paired the two since §382a; the room drew the
/// rows alone.
///
/// **The invariant is inherited verbatim: the window always CONTAINS now.**
/// `WidgetRunway.positions` folds the current moment into the range rather than
/// clamping onto it, so a row that has slipped past its date can never draw
/// ahead of the marker. That is the whole reason this reuses the widget's
/// arithmetic instead of restating it: one shape, one set of edge cases, and
/// the tile and the room can never disagree about the same deadlines.
///
/// Declines exactly where the widget's does — nothing to place, or every date
/// at one moment, which has no shape and would divide by zero. The rows below
/// say it instead.
struct WalletRunwayRail: View {
    /// Which way the window runs. The DRAWING is identical — `WidgetRunway`
    /// folds `now` into the range either way, so a past span simply puts the
    /// marker at the right-hand end and a future one at the left. What differs
    /// is the sentence spoken, and pretending otherwise would have VoiceOver
    /// announce a decade of transfers as "things ahead".
    ///
    /// `.behind` is the address card's history span (prd §417): first contact
    /// to now, every transfer a dot. The gap between the last dot and the
    /// marker is the reading a rows-only list can never give — how long since
    /// you two last spoke.
    enum Sense { case ahead, behind }

    let dates: [Date]
    var sense: Sense = .ahead

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private let dotSize: CGFloat = 9
    private let trackHeight: CGFloat = 3
    private let band: CGFloat = 20

    var body: some View {
        if let placed = WidgetRunway.positions(for: dates) {
            GeometryReader { geo in
                rail(placed, width: geo.size.width)
            }
            .frame(height: band)
            // Dots on a track read as nothing to VoiceOver (§299, the risk
            // strip's own lesson). The rail's claim is a SPREAD, so that is
            // what it says; the rows beneath name each item in full.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken))
            .onAppear { arrived = true }
        }
    }

    private func rail(_ placed: (dots: [Double], now: Double),
                      width: CGFloat) -> some View {
        // Dots are inset by their own radius so one at either extreme stays
        // fully on the track rather than half-hanging off the card — the risk
        // strip's rule, and the reason `WidgetRunway.pad` exists besides.
        let inset = dotSize / 2
        let usable = max(1, width - dotSize)
        let mid = band / 2
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(DS.fillLine)
                .frame(height: trackHeight)
                .offset(y: mid - trackHeight / 2)
                .chartWipe(reduceMotion: reduceMotion)

            // Now, as a notch rather than a dot: it is not one of the things
            // being placed, and drawing it as one more circle would make the
            // present read as a fifth deadline.
            Capsule()
                .fill(DS.textTertiary)
                .frame(width: 2, height: 13)
                .position(x: inset + usable * placed.now, y: mid)
                .opacity(arrived ? 1 : 0)
                .animation(reduceMotion ? nil
                           : DS.Motion.standard.delay(ChartEntrance.lead), value: arrived)

            ForEach(Array(placed.dots.enumerated()), id: \.offset) { index, at in
                Circle()
                    .fill(DS.tint)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: inset + usable * at, y: mid)
                    .opacity(arrived ? 1 : 0)
                    .scaleEffect(arrived ? 1 : 0.5)
                    .animation(dropIn(index), value: arrived)
            }
        }
    }

    /// Each dot lands after the track it sits on has wiped in — a deadline
    /// floating over an undrawn axis is a dot in a card.
    private func dropIn(_ index: Int) -> Animation? {
        reduceMotion ? nil
            : .spring(response: 0.55, dampingFraction: 0.85)
                .delay(ChartEntrance.offset(index: index) + 0.22)
    }

    private var spoken: String {
        guard let first = dates.min(), let last = dates.max() else { return "" }
        let from = first.formatted(.dateTime.month().day())
        let to = last.formatted(.dateTime.month().day())
        switch sense {
        case .ahead:
            return dates.count == 1
                ? String(localized: "One thing ahead, \(from).")
                : String(localized: "\(dates.count) things ahead, from \(from) to \(to).")
        case .behind:
            return dates.count == 1
                ? String(localized: "One, on \(from).")
                : String(localized: "\(dates.count) between \(from) and \(to).")
        }
    }
}

/// A section's name — the small gray label that does the ranking now that the
/// cards are gone, with an optional count-link on its trailing edge. The
/// label IS the door: "Activity · 128 total ›" replaces a centered "See all"
/// row sitting below the content it opens.
struct WalletSectionLabel: View {
    let title: String
    var trailingTitle: String? = nil
    var onTapTrailing: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text(title)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
            if let trailingTitle, let onTapTrailing {
                Button {
                    DSHaptic.selection()
                    onTapTrailing()
                } label: {
                    HStack(spacing: 3) {
                        Text(trailingTitle)
                            .dsText(.label12).fontWeight(.semibold)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .dsGlyph(9, weight: .bold)
                    }
                    .foregroundStyle(DS.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
