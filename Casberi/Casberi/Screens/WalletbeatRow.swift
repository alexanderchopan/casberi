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
		let card = walletID.flatMap { WalletbeatState.card($0) }
		let entry = walletID.flatMap { id in WalletbeatDirectory.wallets.first { $0.id == id } }
		let counts = card?.overall ?? entry?.overall ?? .zero

		// ONE ANATOMY (prd §744): the 38pt mark is the 26pt lead, the stage
		// takes the trailing slot, the bars and the summary are the content.
		DSFeedRow(name: card?.name ?? thing.title, nameLines: 1,
				  line: Text(WalletbeatCopy.coverage(counts))) {
			WalletbeatMark(name: card?.name ?? thing.title, walletID: walletID, size: DS.Mark.row)
		} trailing: {
			if let stage = card?.stage ?? entry?.stage {
				Text(stage)
					.dsText(.label12).fontWeight(.semibold)
					.foregroundStyle(DS.textSecondary)
			}
		} below: {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				if WalletbeatCoverage.of(counts).showsShape {
					dimensionBars(card: card, entry: entry)
				}
				if let summary = thing.summary, !summary.isEmpty {
					Text(summary)
						.dsText(.subhead12)
						.foregroundStyle(DS.textSecondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(.top, DS.Space.s1)
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
						.dsText(.label12)
						.foregroundStyle(DS.textTertiary)
						.frame(width: 96, alignment: .leading)
					WalletbeatBar(counts: counts, height: 6)
					Text("\(counts.judged)/\(counts.applicable)")
						.dsText(.label12)
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
	/// The wallet apps the person said they use (prd §422). Handed in rather than
	/// looked up here: a row must not fetch, and the room already holds the watch
	/// rows it would fetch. Empty for a follower who watches nothing, which is the
	/// common case and correctly draws no marker.
	var watchedWallets: Set<String> = []

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let open = thing.tags.contains(WalletbeatNewsParse.openTag)
		let wallet = thing.authorHandle.flatMap { id in
			WalletbeatDirectory.wallets.first { $0.id == id }
		}
		let mine = WalletbeatIncidentBook.facts(ref: thing.sourceRef)
			.map { facts in facts.wallets.contains { watchedWallets.contains($0) } }
			?? thing.authorHandle.map { watchedWallets.contains($0) } ?? false
		let tags = thing.tags.filter { $0 != WalletbeatNewsParse.openTag }
		// ONE ANATOMY (prd §744): the 38pt mark is the 26pt lead, its status
		// dot scaled with it; the words that were a third row stay one.
		DSFeedRow(name: thing.title, nameLines: 3,
				  line: DSFeed.line(thing.summary), lineLines: 3) {
			ZStack(alignment: .bottomTrailing) {
				if let wallet {
					WalletbeatMark(name: wallet.name, walletID: wallet.id, size: DS.Mark.row)
				} else {
					RoundedRectangle(cornerRadius: DS.Mark.row * 0.28, style: .continuous)
						.fill(DS.surfaceWell)
						.frame(width: DS.Mark.row, height: DS.Mark.row)
						.overlay(
							Image(systemName: "shield")
								.dsGlyph(.caption)
								.foregroundStyle(DS.textTertiary)
						)
				}
				Circle()
					.fill(open ? DS.attention : DS.confirm)
					.frame(width: 9, height: 9)
					.overlay(Circle().strokeBorder(DS.surfaceListRow, lineWidth: 2))
					.offset(x: 3, y: 3)
			}
			.accessibilityHidden(true)
		} trailing: {
			LiveTimeText(date: thing.capturedAt)
		} below: {
			if mine || open || !tags.isEmpty {
				HStack(spacing: DS.Space.s2) {
					if mine {
						Text(String(localized: "You use this"))
							.dsText(.label12).fontWeight(.bold)
							.foregroundStyle(DS.tint)
					}
					if open {
						Text(String(localized: "Unresolved"))
							.dsText(.label12).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
					ForEach(tags, id: \.self) { tag in
						Text(tag)
							.dsText(.label12)
							.foregroundStyle(DS.textTertiary)
					}
				}
				.padding(.top, DS.Space.s1)
			}
		}
	}
}
