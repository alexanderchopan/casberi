import Foundation
import SwiftData

/// Builds `L2beatRoom` from the corpus plus the stored assessments (prd §428).
///
/// The split from `L2beatRoom` is the usual one: everything that touches `Thing` or
/// UserDefaults lives here, so the judgement itself stays Foundation-only and provable.
enum L2beatRoomSource {
	static let source = L2beatWatch.source

	/// Rows the head draws before folding. Four chains is what a person watches; a fifth is
	/// named in the coverage note rather than drawn.
	static let rowCap = 4

	/// How long an incident counts as recent.
	///
	/// NINETY DAYS, three times §419's window, and the difference is measured rather than
	/// taste: Walletbeat publishes roughly one or two incidents a week, L2BEAT has recorded
	/// 37 in five years across 105 chains. At thirty days this head would read "no incidents"
	/// almost permanently, which is true and useless — a window has to be long enough that
	/// the answer changes.
	static let recencyDays = 90

	@MainActor
	static func compose(things: [Thing], now: Date = .now) -> L2beatRoom? {
		var watches: [Thing] = []
		var milestones: [Thing] = []
		// Filtered live AT THE BOUNDARY, before any stored property is read (corollary 4).
		for thing in things.live where thing.source == source {
			if L2beatWatch.isChainRef(thing.sourceRef) {
				watches.append(thing)
			} else if L2beatWatch.isNewsRef(thing.sourceRef) {
				milestones.append(thing)
			}
		}
		// Either tier composes a head: watched chains rank, and a follower with no watches
		// gets the incident standing. Neither present means no room at all — the chip only
		// exists when rows do.
		guard !watches.isEmpty || !milestones.isEmpty else { return nil }

		let cutoff = now.addingTimeInterval(-Double(recencyDays) * 86_400)
		let news = newsSummary(milestones, cutoff: cutoff)

		var items: [L2beatRoom.Item] = []
		for watch in watches {
			guard let ref = watch.sourceRef, let chainID = L2beatWatch.chainID(from: watch)
			else { continue }
			// The live read where the sweep has run, the bundled snapshot otherwise — so a
			// chain watched a moment ago already draws L2BEAT's real shape instead of an
			// empty row waiting on a request.
			let project = L2beatState.best(chainID)
			let mine = milestones.filter { isIncident($0) && affects(chainID, thing: $0) }
			items.append(
				L2beatRoom.Item(
					id: ref,
					chainID: chainID,
					name: project?.name ?? watch.title,
					layer: project?.layer ?? .layer2,
					stage: project?.stage,
					underReview: project?.underReview ?? false,
					risks: project?.orderedRisks ?? [],
					lead: project?.lead ?? .unread,
					recentIncidents: mine.filter { $0.capturedAt >= cutoff }.count,
					totalIncidents: mine.count,
					read: project != nil
				)
			)
		}
		// A watch whose row is dead falls through to the news head rather than to nothing:
		// the milestones are still landed rows and still have a standing to report.
		guard !items.isEmpty else {
			guard let news else { return nil }
			return L2beatRoom(
				items: [], total: 0, snapshotDay: L2beatDirectory.generated, news: news)
		}

		let ranked = L2beatRoom.ranked(items)
		return L2beatRoom(
			items: Array(ranked.prefix(rowCap)),
			total: ranked.count,
			snapshotDay: L2beatDirectory.generated,
			news: news
		)
	}

	/// The whole registry's incident standing, for the followed-but-unwatched head.
	///
	/// Nil when nothing has landed, and deliberately NOT a zeroed summary: "none landed" and
	/// "none exist" are different claims, and only the second would be a clean bill of health
	/// for every chain L2BEAT covers.
	///
	/// Counts INCIDENTS only, never every milestone. A room whose head announced "274
	/// incidents" over a list that is mostly launches and upgrades would be inventing an
	/// alarming reading out of L2BEAT's own good news.
	@MainActor
	private static func newsSummary(_ milestones: [Thing], cutoff: Date) -> L2beatRoom.News? {
		guard !milestones.isEmpty else { return nil }
		let incidents = milestones.filter { isIncident($0) }
		guard !incidents.isEmpty else { return L2beatRoom.News(total: 0, recent: 0, chains: 0) }
		return L2beatRoom.News(
			total: incidents.count,
			recent: incidents.filter { $0.capturedAt >= cutoff }.count,
			chains: Set(incidents.compactMap { $0.authorHandle }).count
		)
	}

	/// Whether a landed milestone is one L2BEAT classed as an incident, read off the tag the
	/// landing wrote — never inferred from its words.
	@MainActor
	private static func isIncident(_ thing: Thing) -> Bool {
		thing.tags.contains(L2beatNewsParse.incidentTag)
	}

	/// A milestone names its chain by L2BEAT id, which the landing stamps onto `authorHandle`.
	/// Matched on the id and never on the title: "Base" appears inside plenty of sentences
	/// that are not about Base.
	@MainActor
	private static func affects(_ chainID: String, thing: Thing) -> Bool {
		thing.authorHandle == chainID
	}

	/// `-l2beatRoomProbe YES`.
	///
	/// An empty head has FIVE causes that render as one silence — nothing watched and nothing
	/// followed, a first sync that has not landed yet, a watch whose chain left L2BEAT's
	/// registry, assessments that failed to decode, or a compose that changed underneath the
	/// card — and only the last two are bugs. This names which.
	@MainActor
	static func probeLines(context: ModelContext, now: Date = .now) -> [String] {
		let source = L2beatIdentity.source
		let things = ((try? context.fetch(FetchDescriptor<Thing>(
			predicate: #Predicate { $0.source == source },
			sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live

		let watched = L2beatWatch.watchedIDs(context: context)
		let stored = L2beatState.projects()
		var out: [String] = [
			"following=\(L2beatWatch.following) watched=\(watched.count) [\(watched.joined(separator: ","))]",
			"live=\(stored.count) bundled=\(L2beatDirectory.projects.count) snapshot=\(L2beatDirectory.generated) rows=\(things.count)",
			"news=\(things.filter { L2beatWatch.isNewsRef($0.sourceRef) }.count) revisions=\(things.filter { L2beatWatch.isRevisionRef($0.sourceRef) }.count) seeded=\(L2beatState.hasSeededIncidents)",
			"summaryReadAt=\(L2beatState.summaryReadAt.map(IngestSupport.isoString) ?? "never") milestonesReadAt=\(L2beatState.milestonesReadAt.map(IngestSupport.isoString) ?? "never") cursor=\(L2beatState.rotationCursor)",
		]

		for id in watched {
			guard let project = L2beatState.best(id) else {
				out.append("chain| \(id) — NOT ASSESSED (no reading, live or bundled)")
				continue
			}
			let live = stored[id] != nil ? "live" : "bundled"
			let cells = project.orderedRisks
				.map { "\($0.axis.rawValue)=\($0.sentiment.rawValue)" }
				.joined(separator: " ")
			out.append(
				"chain| \(id) name=\(project.name) source=\(live) stage=\(project.stage?.rawValue ?? "-") review=\(project.underReview) flagged=\(project.flagged)/\(project.risks.count) \(cells)")
		}

		guard let room = compose(things: things, now: now) else {
			out.append("compose=nil — no card (nothing watched AND no milestone landed)")
			return out
		}
		if let news = room.news {
			out.append("news| total=\(news.total) recent=\(news.recent) chains=\(news.chains)")
		} else {
			out.append("news| none landed")
		}
		out.append("headline=\(L2beatRoom.headline(room))")
		out.append("note=\(L2beatRoom.note(room))")
		out.append("coverageNote=\(L2beatRoom.coverageNote(room) ?? "-")")
		for item in room.items {
			out.append(
				"item| \(item.name) stage=\(item.stage?.rawValue ?? "-") read=\(item.read) recent=\(item.recentIncidents) total=\(item.totalIncidents) lead=\(L2beatRoom.leadLine(item))")
		}
		return out
	}
}
