import Foundation

// The L2BEAT room's head (prd §428).
//
// Foundation-only by design, so `scripts/l2beat-selftest.sh` can compile it WHOLE and
// unmodified — the strongest form of "the harness ran the shipped logic". Nothing on this
// host can make L2BEAT re-rate a chain or record an incident, so the harness is not the best
// proof these numbers are right, it is the ONLY one.
//
// WHAT THE HEAD ANSWERS: not "which of these chains is safest" — that is a ranking we do not
// make — but "is there anything about the chains I use that I should know today, and how far
// up L2BEAT's ladder are they?"
//
// THE STAGE IS THE SECOND FACT, EVERYWHERE. §419's head led with coverage because most
// wallets were barely examined. L2BEAT examines everything it lists, so the missing context
// is not how much was checked but how much of the chain still depends on its operators
// behaving — which is exactly what their stage ladder says, and which no single risk cell
// conveys. A head that led with findings alone would report a Stage 2 chain's one warning
// and a Stage 0 chain's one warning as the same news.

struct L2beatRoom: Equatable {
	/// One watched chain.
	struct Item: Identifiable, Equatable {
		/// The row's `sourceRef` — the card hands this back and the view that owns the sheet
		/// does the lookup, so no `Thing` is ever held here (corollary 5).
		let id: String
		let chainID: String
		let name: String
		let layer: L2beatLayer
		let stage: L2beatStage?
		let underReview: Bool
		/// L2BEAT's five readings, in their own axis order. Empty only when nothing has been
		/// read for this chain on this device.
		let risks: [L2beatRisk]
		let lead: L2beatLead
		/// Milestones L2BEAT classes as incidents for this chain, inside the recency window.
		let recentIncidents: Int
		/// Every incident on record for this chain, however old.
		let totalIncidents: Int
		/// Whether an assessment exists for this chain at all — from the live read or the
		/// bundled snapshot. A watch added seconds ago on a device that has never synced has
		/// none, which is NOT the same as a chain L2BEAT declined to assess.
		let read: Bool

		/// How many of the five L2BEAT flags. A count of their calls, never a score.
		var flagged: Int { risks.filter { $0.sentiment.isConcerning }.count }
	}

	/// L2BEAT's recorded incidents across their WHOLE registry — not filtered to the watch
	/// list, because that is not what the registry is (§421's ruling, one product over).
	///
	/// This is the half you get for FOLLOWING alone. It is summarised rather than listed
	/// because the incidents are already rows in the room beneath the head; what the head
	/// adds is their standing — how many, how recent, and across how many chains.
	struct News: Equatable {
		let total: Int
		let recent: Int
		/// Distinct chains named. The fact a bare count cannot carry: eleven incidents on one
		/// chain and eleven across eleven are very different readings of an ecosystem.
		let chains: Int
	}

	let items: [Item]
	/// Every watched chain, before the display cap — so the headline can never disagree with
	/// the note beneath it.
	let total: Int
	/// The day the bundled directory was taken, for the honest staleness line.
	let snapshotDay: String
	/// Present whenever any milestone has landed. Nil is "none landed", never "none exist" —
	/// a first sync that has not run yet must not read as a quiet ecosystem.
	let news: News?

	/// Spelled out rather than left to the memberwise initializer so `news` can default:
	/// every watch-led fixture still means to build one without it.
	init(items: [Item], total: Int, snapshotDay: String, news: News? = nil) {
		self.items = items
		self.total = total
		self.snapshotDay = snapshotDay
		self.news = news
	}

	var isEmpty: Bool { items.isEmpty }

	/// How many watched chains L2BEAT has placed on its ladder at all.
	var staged: Int { items.filter { ($0.stage?.rung) != nil }.count }

	/// The highest rung any watched chain has reached, or nil if none is on the ladder.
	var bestRung: Int? { items.compactMap { $0.stage?.rung }.max() }

	// MARK: - Ranking

	/// Order by what needs reading, not by quality.
	///
	/// This is a ranking of ATTENTION, the same thing every room head here does — Stripe
	/// ranks by dispute urgency, App Store Connect by whether Apple is holding a build. It is
	/// emphatically NOT a ranking of the chains: THE STAGE IS NEVER A SORT KEY. A Stage 0
	/// chain is not more urgent than a Stage 2 one, it is a chain with a different set of
	/// standing facts, and sorting on the rung would turn a displayed composite into an
	/// implied league table — the one thing §419's rule forbids, arriving by the back door.
	///
	/// TOTAL, and it has to be. A head that reshuffles between opens over unchanged data
	/// reads as broken, so every comparison falls through to the name.
	static func ranked(_ items: [Item]) -> [Item] {
		items.sorted { a, b in
			if a.recentIncidents != b.recentIncidents { return a.recentIncidents > b.recentIncidents }
			if a.underReview != b.underReview { return a.underReview }
			let ac = concern(a), bc = concern(b)
			if ac != bc { return ac > bc }
			if a.flagged != b.flagged { return a.flagged > b.flagged }
			return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
		}
	}

	/// A chain with a finding you can read outranks one nothing has been read for, because
	/// the head's job is to surface what is knowable today.
	private static func concern(_ item: Item) -> Int {
		switch item.lead {
		case .finding(let risk): return risk.worstSentiment == .bad ? 3 : 2
		case .underReview: return 2
		case .nothingFlagged: return 1
		case .unread: return 0
		}
	}

	// MARK: - Copy

	/// The one sentence at the top. Always about the chain that ranked first, so the headline
	/// and the first row can never describe different things.
	static func headline(_ room: L2beatRoom) -> String {
		guard let top = room.items.first else { return newsHeadline(room) }
		if top.recentIncidents > 0 {
			return top.recentIncidents == 1
				? String(localized: "L2BEAT recorded an incident on \(top.name)")
				: String(localized: "L2BEAT recorded \(top.recentIncidents) incidents on \(top.name)")
		}
		if top.underReview {
			return String(localized: "L2BEAT is re-examining \(top.name)")
		}
		switch top.lead {
		case .finding(let risk) where risk.worstSentiment == .bad:
			return String(localized: "L2BEAT faults \(top.name) on \(risk.axis.label.lowercased())")
		case .finding(let risk):
			return String(localized: "L2BEAT flags \(top.name)'s \(risk.axis.label.lowercased())")
		case .nothingFlagged:
			return String(localized: "L2BEAT flags nothing on \(top.name)")
		case .underReview:
			return String(localized: "L2BEAT is re-examining \(top.name)")
		case .unread:
			return String(localized: "Reading L2BEAT…")
		}
	}

	/// The line under the headline. Never repeats it: it carries the SECOND fact, which is
	/// always where the watched chains sit on L2BEAT's own ladder.
	///
	/// Worded as the RUNG'S MEANING rather than its number, because "Stage 0" is jargon that
	/// says nothing to anyone who has not read their methodology, and the number without the
	/// meaning is the kind of borrowed authority §83 exists to prevent.
	static func note(_ room: L2beatRoom) -> String {
		guard !room.items.isEmpty else { return newsNote(room) }
		let unread = room.items.filter { !$0.read }.count
		if unread == room.total { return String(localized: "Reading L2BEAT…") }

		let onLadder = room.items.compactMap { $0.stage?.rung }
		guard !onLadder.isEmpty else {
			return room.total == 1
				? String(localized: "L2BEAT doesn't place this chain on its stage ladder.")
				: String(localized: "L2BEAT doesn't place any of these on its stage ladder.")
		}
		let zero = onLadder.filter { $0 == 0 }.count
		if zero == onLadder.count {
			return onLadder.count == 1
				? String(localized: "Stage 0 — the operators can still change the rules.")
				: String(localized: "All \(onLadder.count) are Stage 0 — the operators can still change the rules.")
		}
		let above = onLadder.filter { $0 > 0 }.count
		let best = onLadder.max() ?? 0
		let rung = best == 2
			? String(localized: "Stage 2")
			: String(localized: "Stage 1")
		if above == onLadder.count {
			return onLadder.count == 1
				? String(localized: "\(rung) — some of the training wheels are off.")
				: String(localized: "All \(onLadder.count) have passed Stage 0; the highest is \(rung).")
		}
		return String(localized: "\(above) of \(onLadder.count) have passed Stage 0; the rest are still Stage 0.")
	}

	/// The row's own sub-line. L2BEAT's sentence verbatim where there is one, and our plain
	/// words about their reading where there is not — never a sentence they didn't write
	/// dressed as one they did.
	static func leadLine(_ item: Item) -> String {
		guard item.read else { return String(localized: "Reading L2BEAT…") }
		switch item.lead {
		case .unread:
			return String(localized: "Not assessed yet")
		case .underReview:
			return String(localized: "L2BEAT is re-examining this assessment")
		case .finding(let risk):
			let text = risk.worstExplanation
			return text.isEmpty ? "\(risk.axis.label): \(risk.value)" : text
		case .nothingFlagged(let count):
			return String(localized: "\(count) checks, none flagged")
		}
	}

	// MARK: The news-led head

	/// What the head says when the seat is FOLLOWED and nothing is watched.
	///
	/// It never names a chain. The incidents are rows in the room directly beneath this card,
	/// and a headline naming one of 105 chains somebody may not use would promote whichever
	/// happened to be newest into a warning about their own money.
	///
	/// A quiet window says so plainly rather than drawing an empty frame — "no incidents in
	/// ninety days" is a real answer and the one most people will see.
	static func newsHeadline(_ room: L2beatRoom) -> String {
		guard let news = room.news, news.total > 0 else {
			// Nothing landed on this device yet, which is a fact about the read rather than
			// about the world — §83's rule in the one room built to report what is known.
			return String(localized: "Reading L2BEAT…")
		}
		if news.recent > 0 {
			return news.recent == 1
				? String(localized: "One incident recorded in the last 90 days")
				: String(localized: "\(news.recent) incidents recorded in the last 90 days")
		}
		return String(localized: "No incidents recorded in the last 90 days")
	}

	/// The second line. Always the UPGRADE — but the REASON to take it, never the
	/// instruction, because the button directly beneath it is the instruction (2026-08-29).
	///
	/// It carried both until this: the note said "Name the chains you use…" and the
	/// button one line down said "Watch the chains you use" — the same act, twice,
	/// in two different verbs. Two costs, and the second is the worse one: the words are
	/// wasted, and a reader has to decide whether naming and watching are one thing or
	/// two (§511's "one consequence, one word"). The verb is now the button's alone and
	/// the note spends its whole line on what following does not cover.
	static func newsNote(_ room: L2beatRoom) -> String {
		guard let news = room.news, news.total > 0 else {
			return String(localized: "Recorded incidents arrive here. Watching the chains you use adds a risk assessment of each.")
		}
		let across = news.chains == 1
			? String(localized: "on one chain")
			: String(localized: "across \(news.chains) chains")
		return String(localized: "\(news.total) on record \(across). Watching yours adds who can stop your transactions, and how long you'd have to get out.")
	}

	/// The small print. States the snapshot's own age, because a directory bundled with the
	/// app is exactly as current as the last ship and pretending otherwise is the kind of
	/// quiet staleness §83 exists to prevent.
	static func coverageNote(_ room: L2beatRoom) -> String? {
		guard !room.items.isEmpty else {
			return room.news == nil
				? nil
				: String(localized: "L2BEAT's reading, not ours · every chain they cover")
		}
		let shown = room.items.count
		if shown < room.total {
			return String(localized: "Showing \(shown) of \(room.total) · L2BEAT's assessment, read on this device")
		}
		return String(localized: "L2BEAT's assessment, not ours · read on this device")
	}
}
