import Foundation
import SwiftData

// Walletbeat — the wallet apps you use, reviewed by somebody independent (prd §419).
//
// Every other seat in the Wallet group reads what your MONEY did. This one reads what the
// SOFTWARE HOLDING IT does: whether your keys are generated on your own device, whether
// your addresses are handed to a third party by default, whether anybody has audited it.
// Walletbeat is an open, MIT-licensed registry that answers those questions attribute by
// attribute, and publishes its own computed ratings as JSON.
//
// TWO HALVES, SPLIT ALONG §216. Ratings are a STATE — a wallet's standing does not become
// stale by the hour — so they ride a window and update in place. Incidents are EVENTS, so
// they land as things stamped with the day they happened and are never windowed away.
//
// READ-ONLY BY CONSTRUCTION, not by conduct: there is no account, no key, and no endpoint
// here that could accept a write. Both reads are public documents on a public host.

// MARK: - The watch list

/// The wallets you have said you use. The watch IS a `Thing` (the Stocktwits/PostHog
/// shape) rather than a UserDefaults list, so a watched wallet is in the corpus — findable,
/// askable, and filterable — rather than being a setting that only its own screen can see.
enum WalletbeatWatch {
	// Forwarded, never re-spelled: `WalletbeatIdentity` is the one grammar, and the pure
	// sheet half reads it too. Two spellings of a ref prefix in two files is precisely
	// §311, where a bridge stamped `privacypools:dep:` and a room head matched
	// `privacypools:deposit:` — the room went quiet rather than breaking.
	static let source = WalletbeatIdentity.source
	static let seatID = WalletbeatIdentity.seatID

	static let walletPrefix = WalletbeatIdentity.walletPrefix
	static let newsPrefix = WalletbeatIdentity.newsPrefix
	static let revisionPrefix = WalletbeatIdentity.revisionPrefix

	static func walletRef(_ id: String) -> String { "\(walletPrefix)\(id)" }

	static func walletID(from thing: Thing) -> String? {
		guard let ref = thing.sourceRef, ref.hasPrefix(walletPrefix) else { return nil }
		return String(ref.dropFirst(walletPrefix.count))
	}

	static func isWatchRef(_ ref: String?) -> Bool { ref?.hasPrefix(walletPrefix) ?? false }
	static func isNewsRef(_ ref: String?) -> Bool { ref?.hasPrefix(newsPrefix) ?? false }
	static func isRevisionRef(_ ref: String?) -> Bool { ref?.hasPrefix(revisionPrefix) ?? false }

	@MainActor
	static func watchedIDs(context: ModelContext) -> [String] {
		IngestSupport.existingSourceRefs(context, source: source)
			.compactMap { $0.hasPrefix(walletPrefix) ? String($0.dropFirst(walletPrefix.count)) : nil }
			.sorted()
	}

	/// Watch a wallet. Returns nil when it is already watched.
	@MainActor
	@discardableResult
	static func add(_ entry: WalletbeatEntry, context: ModelContext) -> Thing? {
		let ref = walletRef(entry.id)
		guard !IngestSupport.hasSourceRef(context, source: source, ref: ref) else { return nil }
		let thing = Thing(
			kind: .link,
			title: IngestSupport.titleLine(entry.name),
			content: entry.pageURL?.absoluteString ?? "",
			source: source,
			capturedAt: .now,
			tags: ["Watchlist", entry.hardware ? "Hardware" : "Software"],
			sourceRef: ref
		)
		// The wallet's Walletbeat id, which is what every join in this bridge keys on —
		// an incident names wallets by id, never by display name.
		thing.authorHandle = entry.id
		context.insert(thing)
		_ = context.saveHonestly()
		SpotlightIndex.index([thing])
		return thing
	}

	/// Unwatch one wallet.
	///
	/// Takes the wallet's ratings row and its stored card, and DELIBERATELY LEAVES the
	/// incidents: an incident is a thing that happened in the world, not a fact about your
	/// watch list, and deleting the record of a breach because you stopped following the
	/// wallet is the one deletion nobody would want. Incidents are cleared only by
	/// disconnecting the seat entirely.
	@MainActor
	static func remove(_ walletID: String, context: ModelContext) {
		FollowPrune.remove(source: source, context: context) {
			$0.sourceRef == walletRef(walletID)
				|| ($0.sourceRef?.hasPrefix("\(revisionPrefix)\(walletID):") ?? false)
		}
		WalletbeatState.forget(walletID)
	}

	/// The seat registers itself off the watch list and CLEARS when the list empties, so
	/// the catalog can never show a connected seat that reads nothing.
	@MainActor
	static func registerBridge(store: BridgeStore, context: ModelContext) {
		let count = watchedIDs(context: context).count
		guard count > 0 else { store.remove(seatID); return }
		store.registerConnected(
			id: seatID,
			name: source,
			proof: String(localized: "\(count) watched"),
			can: [
				String(localized: "Reads Walletbeat's public ratings for the wallets you name."),
				String(localized: "Read-only — no account, no key, and nothing about you is sent."),
			]
		)
	}

	/// Everything the seat planted, for disconnect.
	@MainActor
	static func removeAll(context: ModelContext) {
		FollowPrune.remove(source: source, context: context) { _ in true }
		WalletbeatState.forgetAll()
		WalletbeatIncidentBook.forgetAll()
	}
}

// MARK: - Stored readings

/// Walletbeat's ratings as last read, per wallet, plus the read stamps that keep the
/// windows honest. A reading, not a thing — the PostHog/X402 shape.
enum WalletbeatState {
	private static let cardsKey = "walletbeat.cards"
	private static let newsKey = "walletbeat.news.readAt"

	static func cards() -> [String: WalletbeatCard] {
		guard let data = UserDefaults.standard.data(forKey: cardsKey),
			let decoded = try? JSONDecoder().decode([String: WalletbeatCard].self, from: data)
		else { return [:] }
		return decoded
	}

	static func card(_ walletID: String) -> WalletbeatCard? { cards()[walletID] }

	static func set(_ card: WalletbeatCard) {
		var map = cards()
		map[card.walletID] = card
		replace(map)
	}

	static func replace(_ map: [String: WalletbeatCard]) {
		guard let data = try? JSONEncoder().encode(map) else { return }
		UserDefaults.standard.set(data, forKey: cardsKey)
	}

	static func forget(_ walletID: String) {
		var map = cards()
		map.removeValue(forKey: walletID)
		replace(map)
	}

	/// Forget only the wallets named. Used by the demo teardown, which must not take a
	/// dev install's real watches with it (prd §401's by-name rule).
	static func forgetDemo(_ walletIDs: [String]) {
		var map = cards()
		for id in walletIDs { map.removeValue(forKey: id) }
		replace(map)
	}

	static func forgetAll() {
		UserDefaults.standard.removeObject(forKey: cardsKey)
		UserDefaults.standard.removeObject(forKey: newsKey)
	}

	static var newsReadAt: Date? {
		get { UserDefaults.standard.object(forKey: newsKey) as? Date }
		set {
			if let newValue {
				UserDefaults.standard.set(newValue, forKey: newsKey)
			} else {
				UserDefaults.standard.removeObject(forKey: newsKey)
			}
		}
	}
}

// MARK: - Reads

enum WalletbeatFetch {
	/// One wallet's full ratings, as Walletbeat computes them.
	static func card(walletID: String) async -> WalletbeatCard? {
		guard let url = WalletbeatHost.ratingsURL(walletID: walletID) else { return nil }
		guard let raw = await IngestSupport.getJSON(url) else { return nil }
		// Re-encode rather than plumbing a Data-returning transport: the shared funnel is
		// where NetworkLedger.record lives, and a second door past it is a receipt that
		// never gets written (prd §289).
		guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
		return WalletbeatRatingParse.card(from: data, fetchedAt: .now)
	}

	/// The incident filenames, read from Walletbeat's own `data/news/index.ts`.
	///
	/// Their index enumerates every entry as a dynamic import, so the list of incidents is
	/// one 1.5KB read. This is why the bridge needs NO GitHub API host and never meets its
	/// unauthenticated rate limit — one fewer host to disclose, one fewer to depend on.
	static func newsFiles() async -> [String]? {
		guard let url = rawURL(path: "data/news/index.ts") else { return nil }
		guard let text = await fetchText(url) else { return nil }
		var out: [String] = []
		var seen = Set<String>()
		// `(await import('./2026-08-19-slug')).default,`
		for match in text.ranges(of: "import('./") {
			let tail = text[match.upperBound...]
			guard let close = tail.firstIndex(of: "'") else { continue }
			let name = String(tail[..<close])
			guard !name.isEmpty, name != "index", !seen.contains(name) else { continue }
			seen.insert(name)
			out.append(name)
		}
		return out
	}

	static func incident(file: String) async -> WalletbeatIncident? {
		guard let url = rawURL(path: "data/news/\(file).ts") else { return nil }
		guard let text = await fetchText(url) else { return nil }
		return WalletbeatNewsParse.incident(
			from: text,
			slugFallback: WalletbeatNewsParse.slug(fromFilename: file)
		)
	}

	private static func rawURL(path: String) -> URL? {
		URL(string: "https://\(WalletbeatHost.rawContent)/\(WalletbeatHost.repo)/\(WalletbeatHost.branch)/\(path)")
	}

	/// Their registry files are TypeScript, so the shared JSON funnel cannot carry them.
	/// The request still goes through `IngestSupport`'s session and is still recorded, via
	/// the text overload added for exactly this class of read.
	private static func fetchText(_ url: URL) async -> String? {
		await IngestSupport.getText(url, service: nil)
	}
}

// MARK: - The sync

enum WalletbeatIngest {
	static let source = WalletbeatWatch.source

	/// Ratings are a STATE (§216) — a wallet's standing does not change by the hour, and
	/// each read is ~97KB gzipped, so re-reading every foreground would spend real bytes
	/// to learn nothing. Incidents are EVENTS and are never windowed.
	static let ratingsWindow: TimeInterval = 6 * 3600
	static let newsWindow: TimeInterval = 3 * 3600

	/// How many incidents a first sync brings back. They land with their REAL dates, so a
	/// 2022 breach sorts to 2022 and cannot read as news — the App Store Connect rule.
	static let backfillCap = 12

	@MainActor private static var current: (id: UUID, task: Task<Int?, Never>)?

	/// Chains rather than skips: a wallet watched mid-pass must land in this pass, not be
	/// told "up to date" by a sync that started before it existed.
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
		// The demo reaches nothing (prd §217). Without this a seeded demo seat would read
		// the live registry and overwrite the seeded ratings with a real wallet's.
		guard !DemoMode.isActive else { return 0 }

		let watched = WalletbeatWatch.watchedIDs(context: context)
		guard !watched.isEmpty else { return 0 }

		var existing = IngestSupport.existingSourceRefs(context, source: source)
		var added = 0
		var reachedAny = false

		// ---- Ratings, per watched wallet -------------------------------------------
		var stored = WalletbeatState.cards()
		let now = Date()
		for walletID in watched {
			let last = stored[walletID]?.fetchedAt
			if let last, now.timeIntervalSince(last) < ratingsWindow { continue }
			guard let fresh = await WalletbeatFetch.card(walletID: walletID) else { continue }
			reachedAny = true

			if let before = stored[walletID] {
				for revision in WalletbeatRevisions.between(before, fresh) {
					let ref = revisionRef(walletID: walletID, revision: revision, card: fresh)
					guard !existing.contains(ref) else { continue }
					let thing = revisionThing(
						ref: ref, walletID: walletID, card: fresh, revision: revision, context: context)
					context.insert(thing)
					existing.insert(ref)
					added += 1
				}
			}
			// A FIRST read seeds silently — no revision rows. Otherwise watching a wallet
			// would land twenty-five "now rated" rows for ratings that have stood for
			// months (the Hyperliquid first-sight bug, and the reason every cursor here
			// seeds before it reports).
			stored[walletID] = fresh
			refreshWatchRow(walletID: walletID, card: fresh, context: context)
		}
		WalletbeatState.replace(stored)

		// ---- Incidents --------------------------------------------------------------
		let lastNews = WalletbeatState.newsReadAt
		if lastNews == nil || now.timeIntervalSince(lastNews!) >= newsWindow {
			if let files = await WalletbeatFetch.newsFiles() {
				reachedAny = true
				WalletbeatState.newsReadAt = now
				// Newest first, so a first sync's cap keeps the most recent incidents
				// rather than whichever the directory listing happened to name first.
				let ordered = files.sorted(by: >)
				let firstRun = existing.contains { WalletbeatWatch.isNewsRef($0) } == false
				let wanted = firstRun ? Array(ordered.prefix(backfillCap)) : ordered
				let pending = wanted.filter { file in
					guard let slug = WalletbeatNewsParse.slug(fromFilename: file) else { return false }
					return !existing.contains("\(WalletbeatWatch.newsPrefix)\(slug)")
				}
				let incidents = await IngestSupport.boundedGather(pending, maxConcurrent: 4) {
					await WalletbeatFetch.incident(file: $0)
				}
				for incident in incidents.compactMap({ $0 }) {
					guard !existing.contains(incident.ref) else { continue }
					context.insert(incidentThing(incident, context: context))
					existing.insert(incident.ref)
					added += 1
				}
			}
			// An incident already landed can still change — a vulnerability moves from
			// ongoing to resolved, and a row still reading "ongoing" a week later is the
			// worst thing this feed could say. Heal what is already here.
			await healIncidents(context: context)
		}

		if added > 0 || reachedAny { _ = context.saveHonestly() }
		return reachedAny ? added : nil
	}

	// MARK: Landing

	private static func revisionRef(
		walletID: String, revision: WalletbeatRevision, card: WalletbeatCard
	) -> String {
		// The entry's own revision date is part of the identity, so a rating that goes
		// FAIL → PASS → FAIL lands twice rather than deduping against its own history.
		let stamp = card.lastUpdated ?? ""
		return "\(WalletbeatWatch.revisionPrefix)\(walletID):\(revision.attributeID):\(revision.after.rawValue):\(stamp)"
	}

	@MainActor
	private static func revisionThing(
		ref: String, walletID: String, card: WalletbeatCard,
		revision: WalletbeatRevision, context: ModelContext
	) -> Thing {
		let verb = revision.isFirstJudgment
			? String(localized: "now rates")
			: String(localized: "changed its rating of")
		let title = String(localized: "Walletbeat \(verb) \(card.name)'s \(revision.name.lowercased())")
		let thing = Thing(
			kind: .link,
			title: IngestSupport.titleLine(title),
			content: card.walletID.isEmpty
				? "" : "https://\(WalletbeatHost.site)/\(card.walletID)/",
			source: source,
			// Stamped with the day WALLETBEAT revised the entry, not the day we noticed.
			// Our own clock would date a months-old revision to today the first time a
			// second read happens to run — the PeerRoom rule.
			capturedAt: WalletbeatNewsParse.day(card.lastUpdated ?? "") ?? .now,
			tags: ["Rating"],
			sourceRef: ref
		)
		thing.authorHandle = walletID
		thing.summary = revision.explanation.isEmpty ? nil : revision.explanation
		return thing
	}

	@MainActor
	private static func incidentThing(_ incident: WalletbeatIncident, context: ModelContext) -> Thing {
		var tags = [incident.type.label]
		// The room head matches this exact tag to count what is still open — see
		// `WalletbeatNewsParse.openTag`, which both halves read so they cannot drift.
		if incident.status.isOpen { tags.append(WalletbeatNewsParse.openTag) }
		// Named by the WALLET's display name where we know it, so the tag reads the way a
		// person would say it. An unknown id is dropped rather than tagged raw — a tag
		// reading "mtpelerin" is worse than no tag.
		for id in incident.wallets {
			if let entry = WalletbeatDirectory.wallets.first(where: { $0.id == id }) {
				tags.append(entry.name)
			}
		}
		let thing = Thing(
			kind: .link,
			title: IngestSupport.titleLine(incidentTitle(incident)),
			content: incident.sources.first?.url ?? "https://\(WalletbeatHost.site)/news/",
			source: source,
			capturedAt: incident.publishedAt,
			tags: tags,
			sourceRef: incident.ref
		)
		thing.summary = incident.summary.isEmpty ? nil : incident.summary
		thing.authorHandle = incident.wallets.first
		thing.enrichedText = retrievalText(incident)
		thing.externalLink = "https://\(WalletbeatHost.site)/news/"
		// The facts the sheet draws — severity, status, the funds flag and Walletbeat's
		// citations — none of which a `.link` row can carry without four new stored
		// properties and four CloudKit deploys.
		WalletbeatIncidentBook.record(incident)
		return thing
	}

	/// The severity LEADS a serious incident's title.
	///
	/// §303's clamp ruling: `titleLine` cuts at 80 characters, and Walletbeat's titles run
	/// long — "Slope Wallet users' seed phrases leaked to user tracking platform Sentry" is
	/// 73 on its own. A trailing severity is exactly what the clamp eats, so a critical
	/// breach would read like any other row. Only high and critical lead: prefixing every
	/// low-severity fix with a word turns the signal into chrome.
	static func incidentTitle(_ incident: WalletbeatIncident) -> String {
		guard let severity = incident.severity, severity >= .high else { return incident.title }
		let word = severity == .critical
			? String(localized: "Critical")
			: String(localized: "Serious")
		return "\(word) · \(incident.title)"
	}

	private static func retrievalText(_ incident: WalletbeatIncident) -> String {
		var parts = [incident.summary]
		parts.append(contentsOf: incident.sources.map { "\($0.label) — \($0.url)" })
		return parts.filter { !$0.isEmpty }.joined(separator: "\n")
	}

	/// Refresh a watch row's display copy from the freshly-read card.
	///
	/// `summary` carries Walletbeat's own sentence ONLY when the lead is one of their
	/// findings — the coverage leads ("nobody has rated this yet") are our words about
	/// their data, and a field documented as source-authored display copy must not carry
	/// a sentence its source never wrote.
	@MainActor
	private static func refreshWatchRow(walletID: String, card: WalletbeatCard, context: ModelContext) {
		let ref = WalletbeatWatch.walletRef(walletID)
		guard let thing = IngestSupport.thingsByRef(context, source: source)[ref], thing.isLive else { return }
		if case .finding(let attribute) = card.lead, !attribute.explanation.isEmpty {
			thing.summary = attribute.explanation
		} else {
			thing.summary = nil
		}
		// Every explanation, for retrieval only — so "which of my wallets leaks my
		// address?" can reach a wallet whose row shows a different finding.
		let lines = card.attributes
			.filter { !$0.explanation.isEmpty }
			.map { "\($0.name): \($0.explanation)" }
		thing.enrichedText = lines.isEmpty ? nil : lines.joined(separator: "\n")
		if thing.title != card.name, !card.name.isEmpty {
			thing.title = IngestSupport.titleLine(card.name)
		}
	}

	/// Re-read the incidents already landed so a status change reaches the row.
	///
	/// Bounded to the newest few: an incident's status settles within days of publication
	/// and then never moves again, so walking the whole history every window would spend
	/// a request per entry forever to re-learn that 2022 is still 2022.
	@MainActor
	private static func healIncidents(context: ModelContext) async {
		let rows = IngestSupport.thingsByRef(context, source: source)
			.filter { WalletbeatWatch.isNewsRef($0.key) && $0.value.isLive }
			.sorted { $0.value.capturedAt > $1.value.capturedAt }
			.prefix(4)
		guard !rows.isEmpty else { return }
		guard let files = await WalletbeatFetch.newsFiles() else { return }
		for (ref, thing) in rows {
			let slug = String(ref.dropFirst(WalletbeatWatch.newsPrefix.count))
			guard let file = files.first(where: { $0.hasSuffix(slug) }) else { continue }
			guard let fresh = await WalletbeatFetch.incident(file: file), thing.isLive else { continue }
			let title = IngestSupport.titleLine(incidentTitle(fresh))
			if thing.title != title { thing.title = title }
			if let summary = fresh.summary.isEmpty ? nil : fresh.summary, thing.summary != summary {
				thing.summary = summary
			}
			// The whole reason to heal: an incident that has since been resolved must stop
			// counting as open, or the room keeps an alarm lit over something that closed.
			WalletbeatIncidentBook.record(fresh)
			let wasOpen = thing.tags.contains(WalletbeatNewsParse.openTag)
			if fresh.status.isOpen, !wasOpen {
				thing.tags.append(WalletbeatNewsParse.openTag)
			} else if !fresh.status.isOpen, wasOpen {
				thing.tags.removeAll { $0 == WalletbeatNewsParse.openTag }
			}
		}
	}
}
