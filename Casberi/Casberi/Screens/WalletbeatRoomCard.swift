import SwiftUI

/// The Walletbeat room's head (prd §419).
///
/// FLAT BY LAW — a plain `VStack`, no generic `Widget`/`Row` mount. The eager head of a
/// scroll is where this app's first-frame stack overflows have all happened.
///
/// HOLDS NO `Thing`. The tap hands back a `sourceRef` and the section that owns the sheet
/// does the lookup against the live corpus (corollary 5).
struct WalletbeatRoomCard: View {
	let room: WalletbeatRoom
	var onOpen: (String) -> Void
	var onBrowse: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let mark = DS.brandHue(for: "walletbeat") ?? Color.fixed("#6c5ce7")

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(String(localized: "Walletbeat"))
				.dsText(.label12).fontWeight(.semibold)
				.foregroundStyle(Self.mark)

			Text(WalletbeatRoom.headline(room))
				.dsText(.heading22)
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.top, DS.Space.s2)

			Text(WalletbeatRoom.note(room))
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

			// The label is the VERB the tier is missing (prd §421), and it NAMES the
			// wallet when the app already knows which one you use (prd §430). Every word
			// of it lives in `WalletbeatRoom`, where the harness compiles it — a label
			// composed here would be the one piece of this room's copy nothing proves.
			Button(action: { DSHaptic.tap(); onBrowse() }) {
				Text(WalletbeatRoom.browseLabel(room))
					.dsText(.subhead13).fontWeight(.semibold)
					.foregroundStyle(DS.tint)
			}
			.buttonStyle(.plain)
			.padding(.top, DS.Space.s3)

			if let note = WalletbeatRoom.coverageNote(room) {
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
	private func row(_ item: WalletbeatRoom.Item) -> some View {
		HStack(alignment: .center, spacing: DS.Space.s3) {
			WalletbeatMark(name: item.name, walletID: item.walletID)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: DS.Space.s2) {
					Text(item.name)
						.dsText(.body17)
						.foregroundStyle(DS.textPrimary)
						.lineLimit(1)
					// An unresolved incident is the one thing that outranks the rating,
					// so it is said in words on the row rather than left to a colour.
					if item.openIncidents > 0 {
						Text(String(localized: "Unresolved"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
				}
				Text(WalletbeatRoom.leadLine(item))
					.dsText(.subhead13)
					.foregroundStyle(item.lead.isConcerning ? DS.textSecondary : DS.textTertiary)
					.lineLimit(2)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: DS.Space.s2)
			WalletbeatShape(counts: item.counts)
		}
		.padding(.vertical, DS.Space.s2)
		.contentShape(Rectangle())
		.onTapGesture { DSHaptic.tap(); onOpen(item.id) }
		.dsTapCard()
	}
}
