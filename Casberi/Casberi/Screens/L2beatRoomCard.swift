import SwiftUI

/// The L2BEAT room's head (prd §428).
///
/// FLAT BY LAW — a plain `VStack`, no generic `Widget`/`Row` mount. The eager head of a
/// scroll is where this app's first-frame stack overflows have all happened.
///
/// HOLDS NO `Thing`. The tap hands back a `sourceRef` and the section that owns the sheet
/// does the lookup against the live corpus (corollary 5).
struct L2beatRoomCard: View {
	let room: L2beatRoom
	var onOpen: (String) -> Void
	var onBrowse: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// The source-name eyebrow retired here 2026-08-22 (prd §452). A room
			// head renders only inside its own source's room, under a chip strip
			// where that source's chip is the lit one — so the card introduced
			// itself with a word already on screen, one row up.
			Text(L2beatRoom.headline(room))
				.dsText(.heading22)
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)

			Text(L2beatRoom.note(room))
				.dsText(.subhead13)
				.foregroundStyle(DS.textSecondary)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.top, DS.Space.s1)

			VStack(spacing: 0) {
				ForEach(Array(room.items.enumerated()), id: \.element.id) { index, item in
					row(item)
						.chartArrival(index: index, reduceMotion: reduceMotion)
				}
			}
			.padding(.top, DS.Space.s3)

			// The label is the VERB the tier is missing (§421's ruling). Following alone, the
			// useful next act is naming the chains your money is actually on — "browse"
			// describes the screen rather than the reason to open it, and this is the only
			// door to that screen from inside the room.
			Button(action: { DSHaptic.tap(); onBrowse() }) {
				Text(room.items.isEmpty
					? String(localized: "Watch the chains you use")
					: String(localized: "Every chain L2BEAT covers"))
					.dsText(.subhead13).fontWeight(.semibold)
					.foregroundStyle(DS.tint)
			}
			.buttonStyle(.plain)
			.padding(.top, DS.Space.s3)

			if let note = L2beatRoom.coverageNote(room) {
				Text(note)
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, DS.Space.s2)
			}
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
		.padding(.horizontal, DS.Space.s4)
		.padding(.top, DS.Space.s2)
	}

	@ViewBuilder
	private func row(_ item: L2beatRoom.Item) -> some View {
		HStack(alignment: .center, spacing: DS.Space.s3) {
			L2beatMark(name: item.name, chainID: item.chainID)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: DS.Space.s2) {
					Text(item.name)
						.dsText(.body17)
						.foregroundStyle(DS.textPrimary)
						.lineLimit(1)
					// A recent incident outranks the assessment, so it is said in words on the
					// row rather than left to a colour.
					if item.recentIncidents > 0 {
						Text(String(localized: "Incident"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					} else if item.underReview {
						Text(String(localized: "Under review"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
				}
				Text(L2beatRoom.leadLine(item))
					.dsText(.subhead13)
					.foregroundStyle(item.lead.isConcerning ? DS.textSecondary : DS.textTertiary)
					.lineLimit(2)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: DS.Space.s2)
			VStack(alignment: .trailing, spacing: DS.Space.s1 + 2) {
				L2beatStageChip(stage: item.stage, compact: true)
				if item.risks.isEmpty {
					// Not a strip, not a dash, not an empty track: a word. Five grey cells in
					// this slot read as "assessed, and all unknown", which is the exact wrong
					// reading of a chain nothing has been read for yet.
					Text(String(localized: "Not read"))
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.frame(width: 74, alignment: .trailing)
				} else {
					L2beatStrip(risks: item.risks)
						.frame(width: 74)
				}
			}
		}
		.padding(.vertical, DS.Space.s2)
		.contentShape(Rectangle())
		.onTapGesture { DSHaptic.tap(); onOpen(item.id) }
		.dsTapCard()
	}
}
