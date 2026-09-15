import SwiftUI

/// The L2BEAT room's head (prd §428).
///
/// Composed through `DSRoomChassis.Head` (prd §745): the chains are
/// `MarkedRow`s — the shape Walletbeat's wallets share — and the directory door
/// is the template's `HeadLink`.
///
/// HOLDS NO `Thing`. The tap hands back a `sourceRef` and the section that owns the sheet
/// does the lookup against the live corpus (corollary 5).
struct L2beatRoomCard: View {
	let room: L2beatRoom
	var onOpen: (String) -> Void
	var onBrowse: () -> Void

	var body: some View {
		DSRoomChassis.Head(
			lead: .sentence(L2beatRoom.headline(room)),
			notes: [.note(L2beatRoom.note(room))],
			footnotes: [.quiet(L2beatRoom.coverageNote(room))]) {
			if !room.items.isEmpty {
				DSRoomChassis.Block {
					DSRoomChassis.Rows(items: room.items) { index, item in
						DSRoomChassis.MarkedRow(
							name: item.name,
							flag: flag(item),
							line: L2beatRoom.leadLine(item),
							index: index,
							action: { onOpen(item.id) }) {
							L2beatMark(name: item.name, chainID: item.chainID, size: DS.Mark.row)
						} trailing: {
							assessment(item)
						}
					}
				}
			}

			// The label is the VERB the tier is missing (§421's ruling). Following alone, the
			// useful next act is naming the chains your money is actually on — "browse"
			// describes the screen rather than the reason to open it, and this is the only
			// door to that screen from inside the room.
			DSRoomChassis.Block {
				DSRoomChassis.HeadLink(
					title: room.items.isEmpty
						? String(localized: "Watch the chains you use")
						: String(localized: "Every chain L2BEAT covers"),
					action: onBrowse)
			}
		}
	}

	/// A recent incident outranks the assessment, so it is said in words on the row
	/// rather than left to a colour.
	private func flag(_ item: L2beatRoom.Item) -> String? {
		if item.recentIncidents > 0 { return String(localized: "Incident") }
		if item.underReview { return String(localized: "Under review") }
		return nil
	}

	private func assessment(_ item: L2beatRoom.Item) -> some View {
		VStack(alignment: .trailing, spacing: DS.Space.s1 + 2) {
			L2beatStageChip(stage: item.stage, compact: true)
			if item.risks.isEmpty {
				// Not a strip, not a dash, not an empty track: a word. Five grey cells in
				// this slot read as "assessed, and all unknown", which is the exact wrong
				// reading of a chain nothing has been read for yet.
				Text(String(localized: "Not read"))
					.dsText(.label12)
					.foregroundStyle(DS.textTertiary)
					.frame(width: 74, alignment: .trailing)
			} else {
				L2beatStrip(risks: item.risks)
					.frame(width: 74)
			}
		}
	}
}
