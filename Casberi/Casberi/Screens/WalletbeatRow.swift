import SwiftUI

/// The Walletbeat room's row shapes (prd §419).
///
/// The room holds three kinds of thing and they read differently on purpose: a WATCHED
/// WALLET is a standing report card, an INCIDENT is something that happened on a date, and
/// a REVISION is a note that somebody's judgment changed. Drawing all three as the same
/// band would make the room what §313 found the X room to be — a wall of undifferentiated
/// titles over data that deserved better.
///
/// Each of these guards its own body: SwiftUI re-evaluates a leaf's body on the model's own
/// observation, with no involvement from the parent that built it (corollary 5).

/// A watched wallet — Walletbeat's standing review, drawn from the stored card.
struct WalletbeatWalletRow: View {
	let thing: Thing

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let walletID = WalletbeatWatch.walletID(from: thing)
		// The live card first, then the bundled snapshot — so a wallet watched a moment
		// ago already draws Walletbeat's real shape instead of an empty row waiting on a
		// request that may be minutes away.
		let card = walletID.flatMap { WalletbeatState.card($0) }
		let entry = walletID.flatMap { id in WalletbeatDirectory.wallets.first { $0.id == id } }
		let counts = card?.overall ?? entry?.overall ?? .zero

		VStack(alignment: .leading, spacing: DS.Space.s2) {
			HStack(alignment: .center, spacing: DS.Space.s3) {
				WalletbeatMark(name: thing.title, size: 38)
				VStack(alignment: .leading, spacing: 2) {
					Text(card?.name ?? thing.title)
						.dsText(.body17)
						.foregroundStyle(DS.textPrimary)
						.lineLimit(1)
					Text(WalletbeatCopy.coverage(counts))
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
				}
				Spacer(minLength: DS.Space.s2)
				if let stage = card?.stage ?? entry?.stage {
					Text(stage)
						.dsText(.label11).fontWeight(.semibold)
						.foregroundStyle(DS.textSecondary)
				}
			}

			if WalletbeatCoverage.of(counts).showsShape {
				dimensionBars(card: card, entry: entry)
			}

			// Walletbeat's own sentence about the sharpest finding, where there is one.
			if let summary = thing.summary, !summary.isEmpty {
				Text(summary)
					.dsText(.subhead13)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	/// One bar per dimension, so the shape says WHERE a wallet is weak rather than only
	/// how much of it is. Falls back to the snapshot's counts before a card is read.
	@ViewBuilder
	private func dimensionBars(card: WalletbeatCard?, entry: WalletbeatEntry?) -> some View {
		let dimensions = card?.dimensions ?? entry?.dimensions ?? []
		VStack(spacing: DS.Space.s1 + 2) {
			ForEach(dimensions, id: \.self) { dimension in
				let counts = card?.counts(in: dimension) ?? entry?.counts[dimension] ?? .zero
				HStack(spacing: DS.Space.s2) {
					Text(dimension.label)
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.frame(width: 96, alignment: .leading)
					WalletbeatBar(counts: counts, height: 6)
					Text("\(counts.judged)/\(counts.applicable)")
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.monospacedDigit()
						.frame(width: 38, alignment: .trailing)
				}
			}
		}
	}
}

/// A security incident, or a rating revision — both are things that happened on a day.
struct WalletbeatNewsRow: View {
	let thing: Thing

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let open = thing.tags.contains(WalletbeatNewsParse.openTag)
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
				Text(thing.title)
					.dsText(.body17)
					.foregroundStyle(DS.textPrimary)
					.fixedSize(horizontal: false, vertical: true)
				Spacer(minLength: DS.Space.s2)
				LiveTimeText(date: thing.capturedAt)
			}

			if let summary = thing.summary, !summary.isEmpty {
				Text(summary)
					.dsText(.subhead13)
					.foregroundStyle(DS.textSecondary)
					.lineLimit(3)
					.fixedSize(horizontal: false, vertical: true)
			}

			HStack(spacing: DS.Space.s2) {
				// The kind and, when it is still open, that fact — in words. A state that
				// exists only as a colour is a state a lot of people never receive.
				if open {
					Text(String(localized: "Unresolved"))
						.dsText(.label11).fontWeight(.bold)
						.foregroundStyle(DS.attention)
				}
				ForEach(thing.tags.filter { $0 != "Security" && $0 != WalletbeatNewsParse.openTag }, id: \.self) { tag in
					Text(tag)
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
				}
			}
		}
	}
}
