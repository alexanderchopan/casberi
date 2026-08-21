import SwiftUI

// The shared pieces every L2BEAT surface draws (prd §428).
//
// THE STRIP IS FIVE CELLS AND ALWAYS FIVE. Measured 2026-08-21, all 105 projects L2BEAT
// lists carry all five risks — so unlike §419's ratings bar, which had to be gated behind a
// coverage test because most wallets were barely examined, this shape is honest for every
// chain with no gate in front of it. What it must never do is REDISTRIBUTE: a proportional
// bar of five findings would make a chain with one bad risk and a chain with five bad risks
// paint different-width reds over the same five questions, which reads as magnitude where
// there is only tally. Equal cells, one per axis, always in L2BEAT's own order — so the eye
// can compare two rows without reading either, and the same question is always in the same
// place.

/// L2BEAT's five readings for one chain, as a fixed strip.
struct L2beatStrip: View {
	let risks: [L2beatRisk]
	var height: CGFloat = 8

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	/// Always five slots in L2BEAT's own axis order, whether or not a reading exists for
	/// each. A missing axis draws the unknown fill rather than collapsing the strip to four
	/// — a four-cell strip beside a five-cell one reads as a different measurement.
	private var cells: [(axis: L2beatRiskAxis, sentiment: L2beatSentiment)] {
		L2beatRiskAxis.allCases.map { axis in
			(axis, risks.first { $0.axis == axis }?.sentiment ?? .unknown)
		}
	}

	var body: some View {
		HStack(spacing: 2) {
			ForEach(cells, id: \.axis) { cell in
				RoundedRectangle(cornerRadius: height / 2, style: .continuous)
					.fill(L2beatCopy.color(cell.sentiment))
					.frame(maxWidth: .infinity)
			}
		}
		.frame(height: height)
		// §299: a drawing sized from data earns an entrance, and it wipes from the leading
		// edge so the cells arrive in the order they are read. Honours Reduce Motion.
		.chartWipe(reduceMotion: reduceMotion)
		.accessibilityElement()
		.accessibilityLabel(Text(L2beatCopy.stripReadout(risks)))
	}
}

/// L2BEAT's own stage, as a pill.
///
/// THEIR COMPOSITE, CITED AND NEVER COMPUTED — and the reason §419's "invent no composite"
/// rule costs nothing here. The rung's own word leads; a chain L2BEAT does not place on the
/// ladder says so rather than being shown as a zero, because "not staged" and "Stage 0" are
/// different claims and only one of them is a rung.
struct L2beatStageChip: View {
	let stage: L2beatStage?
	var compact: Bool = false

	var body: some View {
		Text(stage?.label ?? String(localized: "Not staged"))
			.dsText(.label11)
			.fontWeight(.semibold)
			.foregroundStyle(L2beatCopy.stageInk(stage))
			.padding(.horizontal, compact ? DS.Space.s1 + 2 : DS.Space.s2)
			.padding(.vertical, compact ? 2 : 3)
			.background(
				Capsule(style: .continuous).fill(L2beatCopy.stageFill(stage))
			)
			.accessibilityLabel(Text(L2beatCopy.stageReadout(stage)))
	}
}

/// One risk's reading, as a word plus a dot.
///
/// The WORD leads and the dot follows, deliberately: this is where a person reads L2BEAT's
/// individual calls, and a colour-only verdict is unreadable in greyscale and to anyone who
/// doesn't know the palette.
struct L2beatSentimentTag: View {
	let sentiment: L2beatSentiment

	var body: some View {
		HStack(spacing: DS.Space.s1 + 2) {
			Circle()
				.fill(L2beatCopy.color(sentiment))
				.frame(width: 7, height: 7)
			Text(L2beatCopy.label(sentiment))
				.dsText(.label11)
				.fontWeight(.semibold)
				.foregroundStyle(sentiment == .unknown ? DS.textTertiary : DS.textSecondary)
		}
		.accessibilityElement()
		.accessibilityLabel(Text(L2beatCopy.label(sentiment)))
	}
}

/// A chain's mark — L2BEAT's own icon for it, falling back to a monogram.
///
/// THE ICONS ARE SNAPSHOTTED, NEVER FETCHED. L2BEAT serves a 128px PNG for every project it
/// lists, measured 2026-08-21 at 0.4–2.6KB each, so `scripts/l2beat-snapshot.py --icons`
/// writes them into the asset catalogue at ship time and the app reaches NO image server at
/// run time — no new host joins `NetworkReach` for a picture.
///
/// Keyed on the project's `id`, which is what every join in this feature uses, while the
/// snapshot FETCHES by slug. Those differ for ten projects, so an asset named by the wrong
/// one is a chain that silently draws a letter forever.
///
/// The MONOGRAM SURVIVES as the fallback and is not decoration: a chain L2BEAT adds between
/// our snapshots has an assessment before it has a bundled icon here, and a row with a letter
/// is better than a row with a hole.
struct L2beatMark: View {
	let name: String
	var chainID: String?
	var size: CGFloat = 32

	private var initial: String {
		String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
	}

	/// `brand-l2b-<id>`, deliberately its own namespace rather than the catalogue's
	/// `brand-<slug>` or Walletbeat's `brand-wb-<id>`: those are marks for apps a person
	/// connects and are styled for that grid. One source, one look, no drift.
	private var bundled: UIImage? {
		guard let chainID, !chainID.isEmpty else { return nil }
		return UIImage(named: "brand-l2b-\(chainID)")
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
/// Centralised so the wording of a reading cannot differ between the room head, the directory
/// and the risk card — three screens describing the same assessment in three different words
/// is how a reader stops trusting any of them.
enum L2beatCopy {
	static func label(_ sentiment: L2beatSentiment) -> String {
		switch sentiment {
		case .good: return String(localized: "Fine")
		case .warning: return String(localized: "Caveat")
		case .bad: return String(localized: "Flagged")
		case .neutral: return String(localized: "N/A")
		case .unknown: return String(localized: "Not read")
		}
	}

	static func color(_ sentiment: L2beatSentiment) -> Color {
		switch sentiment {
		case .good: return DS.confirm
		case .warning: return DS.attention
		case .bad: return DS.destructive
		case .neutral, .unknown: return DS.fillStrong
		}
	}

	/// The stage pill's ink and fill.
	///
	/// A GRADIENT OF EMPHASIS, NOT OF SAFETY. Stage 2 is not green and Stage 0 is not red:
	/// L2BEAT's ladder measures how much of the chain still depends on its operators, not
	/// whether the chain is dangerous, and painting the rungs in the risk palette would state
	/// a verdict on 76 chains that L2BEAT did not make. So the higher rung simply reads
	/// louder.
	static func stageInk(_ stage: L2beatStage?) -> Color {
		switch stage {
		case .stage2, .stage1: return DS.textPrimary
		case .stage0: return DS.textSecondary
		case .notApplicable, .none: return DS.textTertiary
		}
	}

	static func stageFill(_ stage: L2beatStage?) -> Color {
		switch stage {
		case .stage2, .stage1: return DS.fillStrong
		case .stage0, .notApplicable, .none: return DS.fillLine
		}
	}

	static func stageReadout(_ stage: L2beatStage?) -> String {
		guard let stage else {
			return String(localized: "L2BEAT has not placed this chain on its stage ladder.")
		}
		return "\(stage.label). \(stage.meaning)"
	}

	/// "2 flagged, 1 caveat, 2 fine" — the strip's short form for a row with no room for it.
	static func stripShort(_ risks: [L2beatRisk]) -> String {
		let bad = risks.filter { $0.sentiment == .bad }.count
		guard bad > 0 else {
			let warned = risks.filter { $0.sentiment == .warning }.count
			return warned > 0
				? String(localized: "\(warned) with caveats")
				: String(localized: "Nothing flagged")
		}
		return String(localized: "\(bad) of \(risks.count) flagged")
	}

	/// The strip's spoken form. Names every axis with its reading, because a screen reader
	/// hearing "two flagged" without knowing WHICH two learns nothing actionable.
	static func stripReadout(_ risks: [L2beatRisk]) -> String {
		guard !risks.isEmpty else { return String(localized: "Not assessed yet") }
		return L2beatRiskAxis.allCases.compactMap { axis -> String? in
			guard let risk = risks.first(where: { $0.axis == axis }) else { return nil }
			return "\(axis.label): \(label(risk.sentiment))"
		}.joined(separator: ", ")
	}

	/// How L2BEAT's own attribution reads. Every surface says this; none of them ever states
	/// an assessment as the app's own finding.
	static let attribution = String(localized: "L2BEAT's assessment, not ours")
}
