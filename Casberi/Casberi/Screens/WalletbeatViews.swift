import SwiftUI

// The shared pieces every Walletbeat surface draws (prd §419).
//
// THE ONE RULE THESE VIEWS ENFORCE: a ratings bar is drawn only when Walletbeat has judged
// enough of a wallet for its shape to mean anything (`WalletbeatCoverage.showsShape`).
// Below that the surface says what is MISSING instead.
//
// Measured across all 32 rated wallets, sixteen have fewer than a quarter of their
// attributes judged and two have none at all — so a bar drawn from raw counts would show
// Trezor, about which nothing is known, as a clean strip with no red in it, sitting beside
// Rabby, about which a great deal is known and some of it is bad. The wallet nobody has
// examined would look like the safest one on the screen. That is the §83 fake status in
// the room built to tell you what is known about your own software, so the gate is here,
// in the view, where it cannot be forgotten by a caller.

/// Walletbeat's verdict counts for one dimension, as a segmented bar.
///
/// UNRATED IS DRAWN, never omitted — the grey is the point. Dropping it would rescale the
/// judged segments to fill the width, so five judged attributes out of twenty-nine would
/// paint the same full bar as twenty-nine out of twenty-nine.
struct WalletbeatBar: View {
	let counts: WalletbeatCounts
	var height: CGFloat = 8

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// Fixed order, so the same verdict sits in the same place on every bar in the app and
	/// the eye can compare two rows without reading either.
	private var segments: [(verdict: WalletbeatVerdict, count: Int, color: Color)] {
		[
			(.pass, counts.pass, DS.confirm),
			(.partial, counts.partial, DS.attention),
			(.fail, counts.fail, DS.destructive),
			(.unrated, counts.unrated, DS.fillLine),
		].filter { $0.count > 0 }
	}

	var body: some View {
		GeometryReader { geo in
			let gap: CGFloat = 2
			// The denominator excludes EXEMPT: an attribute that does not apply to this
			// wallet is not a gap in what is known about it.
			let total = max(counts.applicable, 1)
			let gaps = CGFloat(max(segments.count - 1, 0)) * gap
			let usable = max(geo.size.width - gaps, 1)
			HStack(spacing: gap) {
				ForEach(segments, id: \.verdict) { segment in
					RoundedRectangle(cornerRadius: height / 2, style: .continuous)
						.fill(segment.color)
						.frame(width: max(usable * CGFloat(segment.count) / CGFloat(total), 3))
				}
			}
		}
		.frame(height: height)
		// §299: a drawing sized from data earns an entrance, and it wipes from the leading
		// edge so the segments arrive in the order they are read — pass, then partial,
		// then fail, then the grey of what nobody has judged. Honours Reduce Motion.
		.chartWipe(reduceMotion: reduceMotion)
		.accessibilityElement()
		.accessibilityLabel(Text(WalletbeatCopy.barReadout(counts)))
	}
}

/// What a bar cannot say: how much of this wallet has been looked at.
struct WalletbeatCoverageLine: View {
	let counts: WalletbeatCounts

	var body: some View {
		Text(WalletbeatCopy.coverage(counts))
			.dsText(.label11)
			.foregroundStyle(DS.textTertiary)
	}
}

/// A wallet's verdict shape, or an honest statement that there isn't one yet.
///
/// The single component every list row uses, so the coverage gate cannot be applied on one
/// screen and forgotten on another.
struct WalletbeatShape: View {
	let counts: WalletbeatCounts
	var width: CGFloat = 74

	var body: some View {
		if WalletbeatCoverage.of(counts).showsShape {
			WalletbeatBar(counts: counts)
				.frame(width: width)
		} else {
			// Not a bar, not a dash, not an empty track: a word. A greyed-out bar in this
			// slot reads as "rated, and all grey", which is the exact wrong reading.
			Text(WalletbeatCopy.unratedShort(counts))
				.dsText(.label11)
				.foregroundStyle(DS.textTertiary)
				.frame(width: width, alignment: .trailing)
				.accessibilityLabel(Text(WalletbeatCopy.coverage(counts)))
		}
	}
}

/// One attribute's verdict, as a word plus a dot.
///
/// The WORD leads and the dot follows, deliberately: this is the one place a person reads
/// Walletbeat's individual calls, and a colour-only verdict is unreadable in greyscale and
/// to anyone who doesn't know the palette.
struct WalletbeatVerdictTag: View {
	let verdict: WalletbeatVerdict

	var body: some View {
		HStack(spacing: DS.Space.s1 + 2) {
			Circle()
				.fill(WalletbeatCopy.color(verdict))
				.frame(width: 7, height: 7)
			Text(WalletbeatCopy.label(verdict))
				.dsText(.label11)
				.fontWeight(.semibold)
				.foregroundStyle(verdict.isJudged ? DS.textSecondary : DS.textTertiary)
		}
		.accessibilityElement()
		.accessibilityLabel(Text(WalletbeatCopy.label(verdict)))
	}
}

/// A wallet's mark — Walletbeat's own icon for it, falling back to a monogram.
///
/// THE ICONS ARE SNAPSHOTTED, NEVER FETCHED. Walletbeat bundles a logo for every wallet it
/// rates (`public/images/wallets/`), MIT-licensed, in the same repo the ratings come from —
/// so `scripts/walletbeat-snapshot.py --icons` writes them into the asset catalogue at ship
/// time and the app reaches NO image server at run time. That is what makes real marks
/// possible: the first cut of this drew a letter for every wallet on the reasoning that the
/// alternative was reaching out to 32 companies, which was simply wrong about where the
/// logos are.
///
/// The MONOGRAM SURVIVES as the fallback and is not decoration: a wallet Walletbeat adds
/// between our snapshots has a rating before it has a bundled icon here, and a row with a
/// letter is better than a row with a hole.
struct WalletbeatMark: View {
	let name: String
	/// Walletbeat's own id — what the bundled asset is keyed on. Optional because an
	/// incident can name a wallet we have no directory entry for.
	var walletID: String?
	var size: CGFloat = 32

	private var initial: String {
		String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
	}

	/// `brand-wb-<id>`, deliberately its own namespace rather than the catalogue's
	/// `brand-<slug>`: those are marks for apps a person CONNECTS and are styled for that
	/// grid, and Safe is in both sets. One source, one look, no drift.
	private var bundled: UIImage? {
		guard let walletID, !walletID.isEmpty else { return nil }
		return UIImage(named: "brand-wb-\(walletID)")
	}

	var body: some View {
		RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
			.fill(DS.surfaceWell)
			.frame(width: size, height: size)
			.overlay {
				if let bundled {
					Image(uiImage: bundled)
						.resizable()
						.scaledToFit()
						// Inset so an icon carrying its own square field doesn't collide
						// with the well's corner; the plated ones sit on the same grid.
						.padding(size * 0.14)
				} else {
					Text(initial)
						.dsText(.badgeInitial11)
						.fontWeight(.bold)
						.foregroundStyle(DS.textSecondary)
				}
			}
			.accessibilityHidden(true)
	}
}

/// Every sentence and colour these surfaces use, in one place.
///
/// Centralised so the wording of a verdict cannot differ between the room head, the
/// directory and the report card — three screens describing the same rating in three
/// different words is how a reader stops trusting any of them.
enum WalletbeatCopy {
	static func label(_ verdict: WalletbeatVerdict) -> String {
		switch verdict {
		case .pass: return String(localized: "Passes")
		case .partial: return String(localized: "Partly")
		case .fail: return String(localized: "Fails")
		case .unrated: return String(localized: "Not rated")
		case .exempt: return String(localized: "N/A")
		}
	}

	static func color(_ verdict: WalletbeatVerdict) -> Color {
		switch verdict {
		case .pass: return DS.confirm
		case .partial: return DS.attention
		case .fail: return DS.destructive
		case .unrated, .exempt: return DS.fillStrong
		}
	}

	/// "9 of 29 checks rated" — the number the whole feature is organised around.
	static func coverage(_ counts: WalletbeatCounts) -> String {
		String(localized: "\(counts.judged) of \(counts.applicable) checks rated by Walletbeat")
	}

	/// The short form for a list row with no room for a sentence.
	static func unratedShort(_ counts: WalletbeatCounts) -> String {
		counts.judged == 0
			? String(localized: "Not rated")
			: String(localized: "\(counts.judged) of \(counts.applicable)")
	}

	/// The bar's spoken form. Reads out every segment INCLUDING the unrated one, because a
	/// screen reader hearing "nine pass, five fail" without "fifteen not rated" gets the
	/// same false impression the colour-only bar would give.
	static func barReadout(_ counts: WalletbeatCounts) -> String {
		var parts: [String] = []
		if counts.pass > 0 { parts.append(String(localized: "\(counts.pass) pass")) }
		if counts.partial > 0 { parts.append(String(localized: "\(counts.partial) partly")) }
		if counts.fail > 0 { parts.append(String(localized: "\(counts.fail) fail")) }
		if counts.unrated > 0 { parts.append(String(localized: "\(counts.unrated) not rated")) }
		return parts.isEmpty ? String(localized: "Not rated") : parts.joined(separator: ", ")
	}

	/// How Walletbeat's own attribution reads. Every surface says this; none of them ever
	/// states a rating as the app's own finding.
	static let attribution = String(localized: "Walletbeat's ratings, not ours")

	/// That a wallet app announced itself to this device over WalletConnect (prd §430).
	///
	/// DELIBERATELY NOT §422's "You use this", which the incident row wears. That phrase
	/// means "an incident about a wallet you WATCH" — a fact about your watch list — and
	/// this means "an app that really connected here" — a fact about your handshakes. One
	/// phrase over two different pieces of evidence is how a reader stops being able to
	/// tell what either of them is claiming.
	///
	/// It also never says the bare word "connected", which in this app is the CATALOG's
	/// word for a seat that is switched on. A wallet in this list is connected to nothing.
	static let connectedMarker = String(localized: "You've connected with this")

	/// The same fact as an offer, on the screen where naming happens.
	static func connectedOffer(_ count: Int) -> String {
		count == 1
			? String(localized: "You've connected with this wallet app")
			: String(localized: "You've connected with these wallet apps")
	}
}
