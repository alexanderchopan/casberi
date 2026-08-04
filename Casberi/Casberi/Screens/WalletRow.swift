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
        case kind(ThingKind, flagged: Bool = false)
    }

    let mark: Mark
    let title: String
    var subtitle: String? = nil
    /// True for a title that's worth reading in full ("Uniswap can spend
    /// unlimited USDC"); false for one whose tail is noise. Default clamps,
    /// because most rows here are labels, not sentences.
    var titleWraps = false
    @ViewBuilder var trailing: Trailing

    private static var markSize: CGFloat { 34 }

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
                .font(.system(size: 14, weight: .semibold))
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
        case .kind(let kind, let flagged):
            KindGlyph(kind: kind, size: Self.markSize)
                .overlay(alignment: .bottomTrailing) {
                    if flagged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
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
            .font(.system(size: 12, weight: .semibold))
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
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(DS.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
