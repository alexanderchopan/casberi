import Foundation
import SwiftData

// L2BEAT — the chains your money sits on, assessed by somebody independent (prd §428).
//
// The Markets group reads what a venue is PRICING. This one reads what the rails underneath
// are actually made of: whether you can force a transaction in when the operator stops
// taking them, what stops the chain reporting a balance that isn't real, and how long you
// would have to get out if the rules were changed against you. L2BEAT is an open registry
// that answers those five questions for 105 chains and publishes its own Stage 0/1/2 ladder
// over the answers.
//
// TWO HALVES, SPLIT ALONG §216. Risk assessments are a STATE — a chain's standing does not
// change by the hour — so they ride a window and update in place. Milestones are EVENTS, so
// they land as things stamped with the day they happened and are never windowed away.
//
// READ-ONLY BY CONSTRUCTION, not by conduct: there is no account, no key, and no endpoint
// here that could accept a write. Both reads are public documents on a public host.

// MARK: - The watch list

/// The chains you have said you care about. The watch IS a `Thing` (the Stocktwits/PostHog
/// shape) rather than a UserDefaults list, so a watched chain is in the corpus — findable,
/// askable, and filterable — rather than being a setting only its own screen can see.
enum L2beatWatch {
	// Forwarded, never re-spelled: `L2beatIdentity` is the one grammar, and the pure sheet
	// half reads it too. Two spellings of a ref prefix in two files is precisely §311, where
	// a bridge stamped `privacypools:dep:` and a room head matched `privacypools:deposit:`
	// — the room went quiet rather than breaking.
	static let source = L2beatIdentity.source
	static let seatID = L2beatIdentity.seatID

	static let chainPrefix = L2beatIdentity.chainPrefix
	static let newsPrefix = L2beatIdentity.newsPrefix
	static let revisionPrefix = L2beatIdentity.revisionPrefix

	static func chainRef(_ id: String) -> String { "\(chainPrefix)\(id)" }

	static func chainID(from thing: Thing) -> String? {
		guard let ref = thing.sourceRef, ref.hasPrefix(chainPrefix) else { return nil }
		return String(ref.dropFirst(chainPrefix.count))
	}

	static func isChainRef(_ ref: String?) -> Bool { ref?.hasPrefix(chainPrefix) ?? false }
	static func isNewsRef(_ ref: String?) -> Bool { ref?.hasPrefix(newsPrefix) ?? false }
	static func isRevisionRef(_ ref: String?) -> Bool { ref?.hasPrefix(revisionPrefix) ?? false }

	// MARK: Following

	/// Whether the seat is ON, independent of whether any chain is watched.
	///
	/// TWO TIERS OVER ONE SEAT, §421's shape: FOLLOWING is free and gets you L2BEAT's
	/// recorded INCIDENTS, for every chain they cover — that is what the registry is, and
	/// gating it behind naming a chain first would make the ecosystem feed reachable only by
	/// someone who already knew which chain to ask about. WATCHING a chain is the upgrade: it
	/// adds that chain's full risk card, its whole milestone timeline, and revisions when
	/// L2BEAT changes one of its own readings.
	///
	/// A flag rather than a `Thing`, because there is no entity to be: a watch names a chain
	/// and this names nothing. The `X402State`/`ASCState` shape.
	private static let followingKey = "l2beat.following"

	static var following: Bool {
		get { UserDefaults.standard.bool(forKey: followingKey) }
		set { UserDefaults.standard.set(newValue, forKey: followingKey) }
	}

	/// The seat is on when it is followed OR anything is watched. The second half is the
	/// migration hatch every two-tier seat here needs: an install that watched chains before
	/// this flag existed has `false` stored and must stay connected.
	@MainActor
	static func isOn(context: ModelContext) -> Bool {
		following || !watchedIDs(context: context).isEmpty
	}

	@MainActor
	static func watchedIDs(context: ModelContext) -> [String] {
		IngestSupport.existingSourceRefs(context, source: source)
			.compactMap { $0.hasPrefix(chainPrefix) ? String($0.dropFirst(chainPrefix.count)) : nil }
			.sorted()
	}

	/// Watch a chain. Returns nil when it is already watched.
	@MainActor
	@discardableResult
	static func add(_ project: L2beatProject, context: ModelContext) -> Thing? {
		let ref = chainRef(project.id)
		guard !IngestSupport.hasSourceRef(context, source: source, ref: ref) else { return nil }
		// Watching implies following: the incidents have always arrived for anyone watching a
		// chain, and nothing about naming one is a reason to stop reading them.
		following = true
		var tags = ["Watchlist", project.layer.label]
		if let stage = project.stage, stage != .notApplicable { tags.append(stage.label) }
		let thing = Thing(
			kind: .link,
			title: IngestSupport.titleLine(project.name),
			content: project.pageURL?.absoluteString ?? "",
			source: source,
			capturedAt: .now,
			tags: tags,
			sourceRef: ref
		)
		// The chain's L2BEAT id, which is what every join in this bridge keys on — a
		// milestone names its project by id, never by display name.
		thing.authorHandle = project.id
		context.insert(thing)
		_ = context.saveHonestly()
		SpotlightIndex.index([thing])
		return thing
	}

	/// Unwatch one chain.
	///
	/// Takes the chain's assessment row and its stored reading, and DELIBERATELY LEAVES the
	/// milestones: a milestone is something that happened in the world, not a fact about
	/// your watch list, and deleting the record of an incident because you stopped following
	/// a chain is the one deletion nobody would want. Milestones are cleared only by
	/// disconnecting the seat entirely.
	@MainActor
	static func remove(_ chainID: String, context: ModelContext) {
		FollowPrune.remove(source: source, context: context) {
			$0.sourceRef == chainRef(chainID)
				|| ($0.sourceRef?.hasPrefix("\(revisionPrefix)\(chainID):") ?? false)
		}
		L2beatState.forget(chainID)
	}

	/// The seat registers itself off the watch list and CLEARS when both tiers are off, so
	/// the catalog can never show a connected seat that reads nothing.
	@MainActor
	static func registerBridge(store: BridgeStore, context: ModelContext) {
		let count = watchedIDs(context: context).count
		guard following || count > 0 else { store.remove(seatID); return }
		// The proof says which TIER is on, because "connected" covering both would leave
		// someone who only follows unable to tell whether their watches took.
		let proof = count > 0
			? String(localized: "\(count) watched")
			: String(localized: "Following the ecosystem")
		store.registerConnected(
			id: seatID,
			name: source,
			proof: proof,
			can: [
				count > 0
					? String(localized: "Reads L2BEAT's public risk assessment for the chains you name.")
					: String(localized: "Reads the incidents L2BEAT has recorded across every chain it covers."),
				String(localized: "Read-only — no account, no key, and nothing about you is sent."),
			]
		)
	}

	/// Everything the seat planted, for disconnect.
	@MainActor
	static func removeAll(context: ModelContext) {
		FollowPrune.remove(source: source, context: context) { _ in true }
		following = false
		L2beatState.forgetAll()
		L2beatMilestoneBook.forgetAll()
	}
}

// MARK: - Stored readings

/// L2BEAT's assessments as last read, per chain, plus the stamps that keep the windows
/// honest. A reading, not a thing — the PostHog/X402 shape.
enum L2beatState {
	private static let projectsKey = "l2beat.projects"
	private static let summaryKey = "l2beat.summary.readAt"
	private static let milestoneKey = "l2beat.milestones.readAt"

	/// EVERY project from the last summary read, not just the watched ones.
	///
	/// One request returns all 105, so storing only the watched ones would throw away the
	/// directory the app just paid for — and the directory screen is exactly where somebody
	/// decides which chain to watch. The whole map is ~60KB encoded, which is the same order
	/// as the bundled snapshot it supersedes.
	static func projects() -> [String: L2beatProject] {
		guard let data = UserDefaults.standard.data(forKey: projectsKey),
			let decoded = try? JSONDecoder().decode([String: L2beatProject].self, from: data)
		else { return [:] }
		return decoded
	}

	static func project(_ id: String) -> L2beatProject? { projects()[id] }

	/// The best reading available for one chain: what the sweep last read, else the bundle.
	///
	/// A chain watched seconds ago already draws L2BEAT's real shape from the snapshot
	/// instead of an empty row waiting on a request — and a chain L2BEAT added after this
	/// build shipped still draws, because the live read supersedes the bundle rather than
	/// being checked against it.
	static func best(_ id: String) -> L2beatProject? {
		project(id) ?? L2beatDirectory.project(id)
	}

	/// Every chain the app knows about, live read first. The directory screen's source.
	static func directory() -> [L2beatProject] {
		let live = projects()
		guard !live.isEmpty else { return L2beatDirectory.projects }
		var merged = live
		for bundled in L2beatDirectory.projects where merged[bundled.id] == nil {
			merged[bundled.id] = bundled
		}
		return merged.values.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
	}

	static func replace(_ map: [String: L2beatProject]) {
		guard let data = try? JSONEncoder().encode(map) else { return }
		UserDefaults.standard.set(data, forKey: projectsKey)
	}

	static func forget(_ id: String) {
		var map = projects()
		map.removeValue(forKey: id)
		replace(map)
	}

	/// Forget only the chains named. Used by the demo teardown, which must not take a dev
	/// install's real watches with it (prd §401's by-name rule).
	static func forgetDemo(_ ids: [String]) {
		var map = projects()
		for id in ids { map.removeValue(forKey: id) }
		replace(map)
	}

	static func forgetAll() {
		UserDefaults.standard.removeObject(forKey: projectsKey)
		UserDefaults.standard.removeObject(forKey: summaryKey)
		UserDefaults.standard.removeObject(forKey: milestoneKey)
		UserDefaults.standard.removeObject(forKey: rotationKey)
		UserDefaults.standard.removeObject(forKey: seededKey)
	}

	static var summaryReadAt: Date? {
		get { UserDefaults.standard.object(forKey: summaryKey) as? Date }
		set { store(newValue, at: summaryKey) }
	}

	static var milestonesReadAt: Date? {
		get { UserDefaults.standard.object(forKey: milestoneKey) as? Date }
		set { store(newValue, at: milestoneKey) }
	}

	/// Whether the bundled incident history has been landed on this device.
	private static let seededKey = "l2beat.incidents.seeded"

	static var hasSeededIncidents: Bool {
		get { UserDefaults.standard.bool(forKey: seededKey) }
		set { UserDefaults.standard.set(newValue, forKey: seededKey) }
	}

	/// How far the rotating milestone walk has got. See `L2beatIngest.rotationSlice`.
	private static let rotationKey = "l2beat.milestones.cursor"

	static var rotationCursor: Int {
		get { UserDefaults.standard.integer(forKey: rotationKey) }
		set { UserDefaults.standard.set(newValue, forKey: rotationKey) }
	}

	private static func store(_ date: Date?, at key: String) {
		if let date {
			UserDefaults.standard.set(date, forKey: key)
		} else {
			UserDefaults.standard.removeObject(forKey: key)
		}
	}
}

// MARK: - Reads

enum L2beatFetch {
	/// Every chain, with its stage and all five risks, in ONE request.
	static func summary() async -> [L2beatProject] {
		guard let url = L2beatHost.summaryURL else { return [] }
		guard let raw = await IngestSupport.getJSON(url, service: L2beatIdentity.source) else {
			return []
		}
		return L2beatSummaryParse.projects(fromObject: raw)
	}

	/// One chain's milestones, from its own config file in L2BEAT's repo.
	///
	/// Keyed on the project's `id` — the directory name — and never its slug. See the
	/// two-identifier note on `L2beatProject`: joining on the slug loses ten chains
	/// including OP Mainnet and ZKsync Era, and loses them silently.
	static func milestones(projectID: String) async -> [L2beatMilestone]? {
		guard let url = L2beatHost.milestonesURL(projectID: projectID) else { return nil }
		guard let text = await IngestSupport.getText(url, service: L2beatIdentity.source) else {
			return nil
		}
		return L2beatNewsParse.milestones(from: text, projectID: projectID)
	}
}

// MARK: - The sync

enum L2beatIngest {
	static let source = L2beatWatch.source

	/// Risk assessments are a STATE (§216) — a chain's standing does not change by the hour,
	/// and the read is 290KB, so re-reading every foreground would spend real bytes to learn
	/// nothing. Milestones are EVENTS and their window is shorter.
	static let summaryWindow: TimeInterval = 6 * 3600
	static let milestonesWindow: TimeInterval = 3 * 3600

	/// How many UNWATCHED chains the rotating milestone walk reads per pass.
	///
	/// The follow tier promises L2BEAT's incidents across every chain they cover, and there
	/// is no index file to read them from — their milestones live in 105 separate config
	/// files, which is 105 requests a sweep cannot make. So the bundled snapshot is the
	/// baseline and this walk keeps it current: eight chains a pass, oldest-visited first,
	/// so the whole registry is re-read about every thirteen passes while any single sweep
	/// costs eight small requests. Watched chains are always read and never wait their turn.
	static let rotationSlice = 8

	/// A generous ceiling on the first landing, for the day L2BEAT starts recording daily.
	/// The bundle carries 37 incidents today and they land wearing their REAL dates — some
	/// from 2021 — so they sort into history rather than arriving as news.
	static let incidentBackfillCap = 80

	@MainActor private static var current: (id: UUID, task: Task<Int?, Never>)?

	/// Chains rather than skips: a chain watched mid-pass must land in this pass, not be told
	/// "up to date" by a sync that started before it existed.
	@MainActor
	static func refresh(context: ModelContext) async -> Int? {
		let predecessor = current?.task
		let id = UUID()
		let task = Task { () -> Int? in
			if let predecessor { _ = await predecessor.value }
			return await run(context: context)
		}
		current = (id, task)
		let value = await task.value
		if current?.id == id { current = nil }
		return value
	}

	@MainActor
	private static func run(context: ModelContext) async -> Int? {
		// The demo reaches nothing (prd §217). Without this a seeded demo seat would read the
		// live registry and overwrite the seeded assessments with the real ones.
		guard !DemoMode.isActive else { return 0 }

		let watched = L2beatWatch.watchedIDs(context: context)
		guard L2beatWatch.following || !watched.isEmpty else { return 0 }

		var existing = IngestSupport.existingSourceRefs(context, source: source)
		var added = 0
		var reachedAny = false
		let now = Date()

		// ---- The bundled incident history, once ------------------------------------
		//
		// Landed before any request, so a follower who has never had a network sees
		// L2BEAT's incidents on the very first open rather than an empty room claiming a
		// quiet ecosystem.
		if !L2beatState.hasSeededIncidents {
			for milestone in L2beatDirectory.seededIncidents.prefix(incidentBackfillCap) {
				guard !existing.contains(milestone.ref) else { continue }
				context.insert(milestoneThing(milestone, context: context))
				existing.insert(milestone.ref)
				added += 1
			}
			L2beatState.hasSeededIncidents = true
		}

		// ---- Risk assessments, one request for all of them --------------------------
		let lastSummary = L2beatState.summaryReadAt
		if lastSummary == nil || now.timeIntervalSince(lastSummary!) >= summaryWindow {
			let fresh = await L2beatFetch.summary()
			if !fresh.isEmpty {
				reachedAny = true
				L2beatState.summaryReadAt = now
				var stored = L2beatState.projects()
				// A FIRST read seeds silently — no revision rows. Otherwise connecting would
				// land a revision for every reading that has stood for months (the
				// Hyperliquid first-sight bug, and the reason every cursor here seeds
				// before it reports).
				let firstRead = stored.isEmpty
				let watchedSet = Set(watched)
				for project in fresh {
					if !firstRead, let before = stored[project.id] {
						for change in L2beatRevisions.between(before, project) {
							guard lands(change, watched: watchedSet.contains(project.id))
							else { continue }
							let ref = revisionRef(project: project, change: change)
							guard !existing.contains(ref) else { continue }
							context.insert(revisionThing(
								ref: ref, project: project, change: change, context: context))
							existing.insert(ref)
							added += 1
						}
					}
					stored[project.id] = project
				}
				L2beatState.replace(stored)
				for id in watched { refreshWatchRow(chainID: id, context: context) }
			}
		}

		// ---- Milestones --------------------------------------------------------------
		let lastMilestones = L2beatState.milestonesReadAt
		if lastMilestones == nil || now.timeIntervalSince(lastMilestones!) >= milestonesWindow {
			let targets = milestoneTargets(watched: watched)
			let batches = await IngestSupport.boundedGather(targets, maxConcurrent: 4) {
				await L2beatFetch.milestones(projectID: $0)
			}
			var reachedMilestones = false
			for (index, batch) in batches.enumerated() {
				guard let batch else { continue }
				reachedMilestones = true
				let projectID = targets[index]
				let isWatched = watched.contains(projectID)
				for milestone in batch {
					// A GENERAL milestone lands only for a chain you watch. An INCIDENT
					// lands whatever tier you are on — that is what following L2BEAT means.
					guard isWatched || milestone.kind.isIncident else { continue }
					guard !existing.contains(milestone.ref) else { continue }
					context.insert(milestoneThing(milestone, context: context))
					existing.insert(milestone.ref)
					added += 1
				}
			}
			if reachedMilestones {
				reachedAny = true
				L2beatState.milestonesReadAt = now
				advanceRotation()
			}
		}

		if added > 0 || reachedAny { _ = context.saveHonestly() }
		return reachedAny ? added : nil
	}

	/// Which revisions reach the feed at which tier.
	///
	/// A STAGE move is ecosystem news and lands for every chain; a risk revision is detail
	/// about a chain you named and lands only for those. The same split as
	/// incidents-versus-milestones, and for the same reason: 105 chains' worth of risk
	/// revisions in the feed of somebody who watches none is a firehose, while a chain
	/// reaching Stage 1 is the single most reported thing this data produces.
	static func lands(_ change: L2beatChange, watched: Bool) -> Bool {
		switch change {
		case .stage: return true
		case .risk: return watched
		}
	}

	// MARK: The rotating walk

	/// Which chains this pass reads milestones for: every watched chain, plus the next slice
	/// of the registry.
	///
	/// The rotation is over the BUNDLED directory rather than the live one, so the order is
	/// stable across launches and a cursor means the same thing next time. A chain L2BEAT
	/// added after this build shipped is reached the next time the snapshot is regenerated,
	/// which is the same freshness the rest of the bundle has.
	@MainActor
	static func milestoneTargets(watched: [String]) -> [String] {
		let all = L2beatDirectory.projects.map(\.id)
		guard !all.isEmpty else { return watched }
		let start = ((L2beatState.rotationCursor % all.count) + all.count) % all.count
		var slice: [String] = []
		for offset in 0..<min(rotationSlice, all.count) {
			slice.append(all[(start + offset) % all.count])
		}
		// Watched chains lead and are deduped against the slice, so a watched chain that also
		// falls in this pass's window is read once rather than twice.
		var seen = Set<String>()
		return (watched + slice).filter { seen.insert($0).inserted }
	}

	private static func advanceRotation() {
		let count = max(L2beatDirectory.projects.count, 1)
		L2beatState.rotationCursor = (L2beatState.rotationCursor + rotationSlice) % count
	}

	// MARK: Landing

	static func revisionRef(project: L2beatProject, change: L2beatChange) -> String {
		switch change {
		case .risk(let axis, _, let after, _, _):
			return "\(L2beatWatch.revisionPrefix)\(project.id):\(axis.rawValue):\(after.rawValue):\(dayStamp())"
		case .stage(_, let after):
			return "\(L2beatWatch.revisionPrefix)\(project.id):\(L2beatSheet.stageSubject):\(L2beatSheet.token(for: after)):\(dayStamp())"
		}
	}

	/// Today, as `2026-08-21`.
	///
	/// A revision's identity carries the day WE SAW IT, not a day L2BEAT publishes — unlike
	/// a milestone, which carries their own date. There is no revision date in this payload
	/// to use: the summary states what is true now and says nothing about when it changed.
	/// So the row's own capture time is honest (we noticed today) and the copy never claims
	/// L2BEAT changed it today. Including it in the ref is what lets a reading that goes
	/// bad → good → bad land twice rather than deduping against its own history.
	private static func dayStamp(_ now: Date = .now) -> String {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
		let parts = calendar.dateComponents([.year, .month, .day], from: now)
		return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
	}

	/// The title a revision row wears.
	///
	/// §303's clamp ruling: `titleLine` cuts at 80 characters, so what matters LEADS. For a
	/// stage move that is the stage, because "Base reached Stage 1" is the whole story and a
	/// trailing rung is exactly what the clamp eats.
	static func revisionTitle(project: L2beatProject, change: L2beatChange) -> String {
		switch change {
		case .stage(let before, let after):
			if after == .notApplicable {
				return String(localized: "L2BEAT took \(project.name) off the stage ladder")
			}
			if let was = before?.rung, let now = after.rung, now < was {
				return String(localized: "\(project.name) dropped to \(after.label)")
			}
			return String(localized: "\(project.name) reached \(after.label)")
		case .risk(let axis, _, let after, let value, _):
			let verb = after.isConcerning
				? String(localized: "now faults")
				: String(localized: "re-rated")
			return String(localized: "L2BEAT \(verb) \(project.name) on \(axis.label.lowercased()): \(value)")
		}
	}

	@MainActor
	private static func revisionThing(
		ref: String, project: L2beatProject, change: L2beatChange, context: ModelContext
	) -> Thing {
		var tags = ["Rating"]
		if case .stage = change { tags.append("Stage") }
		let thing = Thing(
			kind: .link,
			title: IngestSupport.titleLine(revisionTitle(project: project, change: change)),
			content: project.pageURL?.absoluteString ?? "",
			source: source,
			// Stamped NOW, deliberately, and this diverges from §419 on purpose: Walletbeat
			// publishes a `lastUpdated` for each entry, so a revision there could be dated to
			// the day THEY revised it. L2BEAT's summary carries no such field — it says what
			// is true, not when it became true — so the only honest stamp is when we noticed,
			// and the copy is worded to claim nothing more.
			capturedAt: .now,
			tags: tags,
			sourceRef: ref
		)
		thing.authorHandle = project.id
		switch change {
		case .risk(_, _, _, _, let explanation):
			thing.summary = explanation.isEmpty ? nil : explanation
		case .stage(_, let after):
			thing.summary = after.meaning
		}
		return thing
	}

	@MainActor
	private static func milestoneThing(_ milestone: L2beatMilestone, context: ModelContext) -> Thing {
		let project = L2beatState.best(milestone.projectID)
		var tags = [milestone.kind.label]
		// The room head matches this exact tag to count incidents — see
		// `L2beatNewsParse.incidentTag`, which both halves read so they cannot drift.
		if milestone.kind.isIncident, !tags.contains(L2beatNewsParse.incidentTag) {
			tags.append(L2beatNewsParse.incidentTag)
		}
		// Named by the CHAIN's display name where we know it, so the tag reads the way a
		// person would say it. An unknown id is dropped rather than tagged raw — a tag
		// reading "zksync2" is worse than no tag.
		if let project { tags.append(project.name) }
		let thing = Thing(
			kind: .link,
			title: IngestSupport.titleLine(milestoneTitle(milestone, project: project)),
			content: milestone.url ?? project?.pageURL?.absoluteString ?? "",
			source: source,
			capturedAt: milestone.date,
			tags: tags,
			sourceRef: milestone.ref
		)
		thing.summary = milestone.summary
		thing.authorHandle = milestone.projectID
		thing.externalLink = project?.pageURL?.absoluteString
		// The facts the sheet draws — the kind, the citation and the chain it names — none of
		// which a `.link` row can carry without three new stored properties and three
		// CloudKit deploys.
		L2beatMilestoneBook.record(milestone, projectName: project?.name)
		return thing
	}

	/// The chain LEADS every milestone title.
	///
	/// §303's clamp ruling again, and here it is the difference between a usable feed and an
	/// unusable one: L2BEAT writes milestone titles for a page that already says which chain
	/// you are looking at, so "Nitro upgrade" and "Stage 1 achieved" carry no subject at all.
	/// In a mixed feed of 105 chains a subject-less title is unreadable, and a trailing chain
	/// name is exactly what `titleLine`'s 80-character cut eats.
	static func milestoneTitle(_ milestone: L2beatMilestone, project: L2beatProject?) -> String {
		guard let name = project?.name, !name.isEmpty else { return milestone.title }
		// Their own title sometimes already opens with the chain's name, in which case
		// prefixing it reads as a stutter ("Base · Base mainnet launch").
		if milestone.title.localizedCaseInsensitiveContains(name) { return milestone.title }
		return "\(name) · \(milestone.title)"
	}

	/// Refresh a watched chain's row from the freshest reading.
	///
	/// `summary` carries L2BEAT's own sentence ONLY when the lead is one of their findings —
	/// "not read yet" and "under review" are our words about their data, and a field
	/// documented as source-authored display copy must not carry a sentence its source never
	/// wrote.
	@MainActor
	static func refreshWatchRow(chainID: String, context: ModelContext) {
		let ref = L2beatWatch.chainRef(chainID)
		guard let thing = IngestSupport.thingsByRef(context, source: source)[ref], thing.isLive,
			let project = L2beatState.best(chainID)
		else { return }
		if case .finding(let risk) = project.lead, !risk.worstExplanation.isEmpty {
			thing.summary = risk.worstExplanation
		} else {
			thing.summary = nil
		}
		// Every reading, for retrieval only — so "which of my chains can't I force a
		// transaction into?" can reach a chain whose row shows a different finding.
		let lines = project.orderedRisks
			.filter { !$0.explanation.isEmpty }
			.map { "\($0.axis.label) — \($0.value): \($0.explanation)" }
		thing.enrichedText = lines.isEmpty ? nil : lines.joined(separator: "\n")
		if thing.title != project.name, !project.name.isEmpty {
			thing.title = IngestSupport.titleLine(project.name)
		}
		// The stage rides the row's tags so it can be filtered and asked about. Re-stamped
		// rather than appended, or a chain promoted to Stage 1 would wear both rungs.
		var tags = thing.tags.filter { !$0.hasPrefix("Stage ") }
		if let stage = project.stage, stage != .notApplicable, !tags.contains(stage.label) {
			tags.append(stage.label)
		}
		if tags != thing.tags { thing.tags = tags }
	}
}
