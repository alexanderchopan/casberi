import Foundation
import SwiftData

/// Builds `WalletbeatRoom` from the corpus plus the stored ratings (prd §419).
///
/// The split from `WalletbeatRoom` is the usual one: everything that touches `Thing` or
/// UserDefaults lives here, so the judgement itself stays Foundation-only and provable.
enum WalletbeatRoomSource {
	static let source = WalletbeatWatch.source

	/// Rows the head draws before folding. Four wallets is what a person watches; a fifth
	/// is named in the coverage note rather than drawn.
	static let rowCap = 4

	/// How long an incident counts as recent. Thirty days, because these are disclosures
	/// rather than alerts — a breach three weeks old is still the most important thing
	/// about a wallet, and Walletbeat publishes roughly one or two a week.
	static let recencyDays = 30

	@MainActor
	static func compose(things: [Thing], now: Date = .now) -> WalletbeatRoom? {
		var watches: [Thing] = []
		var incidents: [Thing] = []
		// Filtered live AT THE BOUNDARY, before any stored property is read (corollary 4).
		for thing in things.live where thing.source == source {
			if WalletbeatWatch.isWatchRef(thing.sourceRef) {
				watches.append(thing)
			} else if WalletbeatWatch.isNewsRef(thing.sourceRef) {
				incidents.append(thing)
			}
		}
		// Either tier composes a head (prd §421): watched wallets rank, and a follower with
		// no watches gets the incident standing. Neither present means no room at all —
		// the chip only exists when rows do.
		guard !watches.isEmpty || !incidents.isEmpty else { return nil }

		let cards = WalletbeatState.cards()
		// Read once per compose, off two local records — no request, and nothing is
		// resolved that the directory does not currently rate (prd §430).
		let connectedName = WalletbeatMatch.suggestions(
			apps: WalletConnectApps.sightings(),
			// From the ROWS this compose is already holding, never a second fetch: the
			// head must never offer a wallet it is about to draw as watched, and a list
			// read separately can disagree with the one on screen.
			watched: watches.compactMap { WalletbeatWatch.walletID(from: $0) },
			entries: WalletbeatDirectory.wallets.map { (id: $0.id, name: $0.name) })
			.first
			.flatMap { id in WalletbeatDirectory.wallets.first { $0.id == id }?.name }
		let cutoff = now.addingTimeInterval(-Double(recencyDays) * 86_400)
		let news = newsSummary(incidents, cutoff: cutoff)

		var items: [WalletbeatRoom.Item] = []
		for watch in watches {
			guard let ref = watch.sourceRef, let walletID = WalletbeatWatch.walletID(from: watch) else { continue }
			let entry = WalletbeatDirectory.wallets.first { $0.id == walletID }
			let card = cards[walletID]

			// The counts come from the LIVE card when one has been read, and fall back to
			// the bundled snapshot otherwise — so a wallet watched a moment ago already
			// draws Walletbeat's real shape instead of an empty row waiting on a request.
			let counts: WalletbeatCounts = card?.overall ?? entry?.overall ?? .zero
			let lead: WalletbeatLead = card?.lead
				?? .unexamined(applicable: counts.applicable)

			let mine = incidents.filter { affects(walletID, thing: $0) }
			items.append(
				WalletbeatRoom.Item(
					id: ref,
					walletID: walletID,
					name: card?.name ?? entry?.name ?? watch.title,
					hardware: card?.hardware ?? entry?.hardware ?? false,
					counts: counts,
					lead: lead,
					openIncidents: mine.filter { isOpen($0) }.count,
					recentIncidents: mine.filter { $0.capturedAt >= cutoff }.count,
					read: card != nil
				)
			)
		}
		// A watch whose row is dead falls through to the news head rather than to nothing:
		// the incidents are still landed rows and still have a standing to report.
		guard !items.isEmpty else {
			guard let news else { return nil }
			return WalletbeatRoom(
				items: [], total: 0, snapshotDay: WalletbeatDirectory.generated, news: news,
				connectedName: connectedName)
		}

		let ranked = WalletbeatRoom.ranked(items)
		return WalletbeatRoom(
			items: Array(ranked.prefix(rowCap)),
			total: ranked.count,
			snapshotDay: WalletbeatDirectory.generated,
			news: news,
			connectedName: connectedName
		)
	}

	/// The whole registry's incident standing, for the followed-but-unwatched head.
	///
	/// Nil when nothing has landed, and deliberately NOT a zeroed summary: "none landed"
	/// and "none exist" are different claims, and only the second would be a clean bill of
	/// health for every wallet Walletbeat covers.
	@MainActor
	private static func newsSummary(_ incidents: [Thing], cutoff: Date) -> WalletbeatRoom.News? {
		guard !incidents.isEmpty else { return nil }
		return WalletbeatRoom.News(
			total: incidents.count,
			open: incidents.filter { isOpen($0) }.count,
			recent: incidents.filter { $0.capturedAt >= cutoff }.count
		)
	}

	/// An incident names its wallets by Walletbeat id, which the landing stamps onto
	/// `authorHandle`. Matched on the id and never on the title: "Ledger" appears inside
	/// plenty of sentences that are not about Ledger.
	@MainActor
	private static func affects(_ walletID: String, thing: Thing) -> Bool {
		thing.authorHandle == walletID
	}

	/// Whether an incident is still open, read off the tag the landing wrote.
	///
	/// Deliberately conservative: only an incident we can SEE is ongoing counts as open.
	/// Walletbeat marks most entries resolved or mitigated within days, so treating an
	/// unreadable status as open would keep a permanent alarm on the room.
	@MainActor
	private static func isOpen(_ thing: Thing) -> Bool {
		thing.tags.contains(WalletbeatNewsParse.openTag)
	}

	/// `-walletbeatRoomProbe YES`.
	///
	/// An empty head has FIVE causes that render as one silence — nothing watched, a first
	/// sync that has not landed a card yet, a watch whose wallet left Walletbeat's
	/// directory, ratings that failed to decode, or a compose that changed underneath the
	/// card — and only the last two are bugs. This names which.
	@MainActor
	static func probeLines(context: ModelContext, now: Date = .now) -> [String] {
		let things = ((try? context.fetch(FetchDescriptor<Thing>(
			predicate: #Predicate { $0.source == "Walletbeat" },
			sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live

		let watched = WalletbeatWatch.watchedIDs(context: context)
		let cards = WalletbeatState.cards()
		var out: [String] = [
			"following=\(WalletbeatWatch.following) watched=\(watched.count) [\(watched.joined(separator: ","))]",
			"cards=\(cards.count) rows=\(things.count) directory=\(WalletbeatDirectory.wallets.count) snapshot=\(WalletbeatDirectory.generated)",
			"news=\(things.filter { WalletbeatWatch.isNewsRef($0.sourceRef) }.count) revisions=\(things.filter { WalletbeatWatch.isRevisionRef($0.sourceRef) }.count) newsReadAt=\(WalletbeatState.newsReadAt.map(IngestSupport.isoString) ?? "never")",
		]

		// The WalletConnect join (prd §430). It has FOUR states that all render as one
		// absent offer — no handshake has ever settled on this device, an app whose name
		// Walletbeat does not rate, a name whose key is claimed by two entries and is
		// therefore refused, and every match already watched — and only the third is a
		// bug. The raw names are printed beside what they resolved to, because the whole
		// join is that one arrow.
		let sightings = WalletConnectApps.sightings().sorted { $0.seenAt > $1.seenAt }
		let table = WalletbeatMatch.index(
			WalletbeatDirectory.wallets.map { (id: $0.id, name: $0.name) })
		out.append("apps=\(sightings.count) keys=\(table.count)")
		for app in sightings {
			let key = WalletbeatMatch.key(app.name) ?? "-"
			let hit = table[key]
			out.append(
				"app| \"\(app.name)\" key=\(key) → \(hit ?? "NOT RATED") watched=\(hit.map { watched.contains($0) } ?? false)")
		}
        

		for id in watched {
			guard let card = cards[id] else {
				out.append("card| \(id) — NOT READ YET (no ratings fetched on this device)")
				continue
			}
			let counts = card.overall
			out.append(
				"card| \(id) name=\(card.name) coverage=\(card.coverage) judged=\(counts.judged)/\(counts.applicable) pass=\(counts.pass) partial=\(counts.partial) fail=\(counts.fail) unrated=\(counts.unrated) updated=\(card.lastUpdated ?? "-")"
			)
		}

		guard let room = compose(things: things, now: now) else {
			out.append("compose=nil — no card (nothing watched AND no incident landed)")
			return out
		}
		if let news = room.news {
			out.append("news| total=\(news.total) open=\(news.open) recent=\(news.recent)")
		} else {
			out.append("news| none landed")
		}
		out.append("headline=\(WalletbeatRoom.headline(room))")
		out.append("browseLabel=\(WalletbeatRoom.browseLabel(room))")
		out.append("note=\(WalletbeatRoom.note(room))")
		out.append("coverageNote=\(WalletbeatRoom.coverageNote(room) ?? "-")")
		for item in room.items {
			out.append(
				"item| \(item.name) coverage=\(item.coverage) read=\(item.read) open=\(item.openIncidents) recent=\(item.recentIncidents) lead=\(WalletbeatRoom.leadLine(item))"
			)
		}
		return out
	}
}
