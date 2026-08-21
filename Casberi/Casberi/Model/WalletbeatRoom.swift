import Foundation

// The Walletbeat room's head (prd §419).
//
// Foundation-only by design, so `scripts/walletbeat-selftest.sh` can compile it WHOLE and
// unmodified — the strongest form of "the harness ran the shipped logic". Nothing on this
// host can make Walletbeat revise a rating or publish an incident, so the harness is not
// the best proof these numbers are right, it is the ONLY one.
//
// WHAT THE HEAD ANSWERS: not "which of my wallets is best" — Walletbeat publishes no
// composite and neither do we — but "is there anything about the wallets I use that I
// should know today, and how much has actually been checked?"
//
// COVERAGE OUTRANKS FINDINGS, EVERYWHERE. Measured across all 32 rated wallets, sixteen
// have fewer than a quarter of their attributes judged and two have none at all. A head
// that led with findings would say nothing about the wallet nobody has examined, which
// reads as a clean bill of health — the §83 fake status, in the one room built to tell you
// what is known about your own software.

struct WalletbeatRoom: Equatable {
	/// One watched wallet.
	struct Item: Identifiable, Equatable {
		/// The row's `sourceRef` — the card hands this back and the view that owns the
		/// sheet does the lookup, so no `Thing` is ever held here (corollary 5).
		let id: String
		let walletID: String
		let name: String
		let hardware: Bool
		let counts: WalletbeatCounts
		let lead: WalletbeatLead
		/// Incidents Walletbeat still lists as ongoing or unknown for this wallet.
		let openIncidents: Int
		/// Incidents inside the recency window, open or not.
		let recentIncidents: Int
		/// Whether ratings have ever been read for this wallet on this device. A watch
		/// added seconds ago has no card yet, which is NOT the same as a wallet Walletbeat
		/// has not examined — conflating them would tell someone their brand-new watch is
		/// unrated when the read simply has not run.
		let read: Bool

		var coverage: WalletbeatCoverage { .of(counts) }
	}

	/// Walletbeat's published incidents, across their WHOLE registry — not filtered to the
	/// watch list, because that is not what the registry is (prd §421).
	///
	/// This is the half you get for FOLLOWING alone. It is summarised rather than listed
	/// because the incidents are already rows in the room beneath the head; what the head
	/// adds is the standing they have — how many are still open, and how recent.
	struct News: Equatable {
		let total: Int
		/// Still ongoing or unknown, read off the tag the landing wrote — never inferred.
		let open: Int
		/// Inside the room's recency window, open or not.
		let recent: Int
	}

	let items: [Item]
	/// Every watched wallet, before the display cap — so the headline can never disagree
	/// with the coverage note beneath it.
	let total: Int
	/// The day the bundled directory was taken, for the honest staleness line.
	let snapshotDay: String
	/// A wallet app this device has really connected with and does not yet watch, if
	/// there is one (prd §430). The NAME, because that is all the label needs.
	///
	/// §421 rules that this head NEVER NAMES A WALLET, and that ruling is untouched:
	/// it is about the HEADLINE, where promoting whichever of thirty-two happened to be
	/// newest reads as a warning about software the person may not use. This names a
	/// wallet on the BROWSE BUTTON, it is an offer rather than a finding, and its grounds
	/// are the person's own handshake rather than our pick — every reason the headline
	/// rule exists is absent here.
	let connectedName: String?
	/// Present whenever any incident has landed. Nil is "none landed", never "none exist" —
	/// a first sync that has not run yet must not read as a clean ecosystem.
	let news: News?

	/// Spelled out rather than left to the memberwise initializer so `news` can default:
	/// every existing call site and fixture built a watch-led room and still means to.
	init(items: [Item], total: Int, snapshotDay: String, news: News? = nil,
		 connectedName: String? = nil) {
		self.items = items
		self.total = total
		self.snapshotDay = snapshotDay
		self.news = news
		self.connectedName = connectedName
	}

	var isEmpty: Bool { items.isEmpty }

	/// How many wallets Walletbeat has examined enough for a shape to mean anything.
	var examined: Int { items.filter { $0.coverage.showsShape }.count }

	// MARK: - Ranking

	/// Order by what needs reading, not by quality.
	///
	/// This is a ranking of ATTENTION, the same thing every room head here does — Stripe
	/// ranks by dispute urgency, App Store Connect by whether Apple is holding a build. It
	/// is emphatically NOT a ranking of the wallets themselves: an unexamined wallet sorts
	/// low because there is nothing to read, never because it is safe.
	///
	/// TOTAL, and it has to be. A head that reshuffles between opens over unchanged data
	/// reads as broken, so every comparison falls through to the name.
	static func ranked(_ items: [Item]) -> [Item] {
		items.sorted { a, b in
			if a.openIncidents != b.openIncidents { return a.openIncidents > b.openIncidents }
			if a.recentIncidents != b.recentIncidents { return a.recentIncidents > b.recentIncidents }
			let ac = concern(a), bc = concern(b)
			if ac != bc { return ac > bc }
			if a.counts.fail != b.counts.fail { return a.counts.fail > b.counts.fail }
			return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
		}
	}

	/// A wallet with findings you can actually read outranks one nobody has looked at,
	/// because the head's job is to surface what is knowable today.
	private static func concern(_ item: Item) -> Int {
		switch item.lead {
		case .finding(let attribute): return attribute.verdict == .fail ? 3 : 2
		case .noFailures: return 1
		case .barelyExamined, .unexamined: return 0
		}
	}

	// MARK: - Copy

	/// The one sentence at the top. Always about the wallet that ranked first, so the
	/// headline and the first row can never describe different things.
	static func headline(_ room: WalletbeatRoom) -> String {
		guard let top = room.items.first else { return newsHeadline(room) }
		if top.openIncidents > 0 {
			return String(localized: "\(top.name) has an unresolved security incident")
		}
		if top.recentIncidents > 0 {
			return String(localized: "\(top.name) had a security incident recently")
		}
		switch top.lead {
		case .finding(let attribute) where attribute.verdict == .fail:
			return String(localized: "Walletbeat faults \(top.name) on \(attribute.name.lowercased())")
		case .finding(let attribute):
			return String(localized: "Walletbeat partly faults \(top.name) on \(attribute.name.lowercased())")
		case .noFailures:
			return String(localized: "Nothing Walletbeat checked on \(top.name) failed")
		case .barelyExamined, .unexamined:
			// The honest headline when the best-ranked wallet is one nobody has examined:
			// say so, rather than reaching down the list for a finding and implying it is
			// the most important thing here.
			return room.total == 1
				? String(localized: "Walletbeat hasn't examined \(top.name) yet")
				: String(localized: "Walletbeat hasn't examined your wallets yet")
		}
	}

	/// The line under the headline. Never repeats it: it carries the SECOND fact, which is
	/// always how much has been looked at.
	static func note(_ room: WalletbeatRoom) -> String {
		guard !room.items.isEmpty else { return newsNote(room) }
		let unread = room.items.filter { !$0.read }.count
		if unread == room.total {
			return String(localized: "Reading Walletbeat…")
		}
		let examined = room.examined
		if examined == 0 {
			return String(localized: "Walletbeat lists these wallets but has judged almost nothing about them so far.")
		}
		if examined == room.total {
			return room.total == 1
				? String(localized: "Rated in depth — Walletbeat's own judgments, attribute by attribute.")
				: String(localized: "All \(room.total) rated in depth — Walletbeat's own judgments, attribute by attribute.")
		}
		return String(localized: "\(examined) of \(room.total) rated in depth; the rest Walletbeat has barely examined.")
	}

	/// The row's own sub-line. Walletbeat's sentence verbatim where there is one, and our
	/// plain words about their coverage where there is not — never a sentence they didn't
	/// write dressed as one they did.
	static func leadLine(_ item: Item) -> String {
		guard item.read else { return String(localized: "Reading Walletbeat…") }
		switch item.lead {
		case .unexamined:
			return String(localized: "Not rated yet")
		case .barelyExamined(let judged, let applicable):
			return String(localized: "Only \(judged) of \(applicable) checks rated so far")
		case .finding(let attribute):
			return attribute.explanation.isEmpty ? attribute.name : attribute.explanation
		case .noFailures(let judged, _):
			return String(localized: "\(judged) checks rated, none failing")
		}
	}

	/// The small print. States the snapshot's own age, because a directory bundled with the
	/// app is exactly as current as the last ship and pretending otherwise is the kind of
	/// quiet staleness §83 exists to prevent.
	// MARK: The news-led head

	/// What the head says when the seat is FOLLOWED and nothing is watched (prd §421).
	///
	/// It leads with STANDING, not volume: an unresolved incident is the only thing here
	/// that asks anything of you, so it outranks a busier month in which everything was
	/// closed. A quiet window says so plainly rather than drawing an empty frame — "no
	/// incidents in thirty days" is a real answer and the one most people will see.
	///
	/// It never names a wallet. The incidents are rows in the room directly beneath this
	/// card, and a headline naming one of thirty-two wallets somebody may not use would
	/// promote whichever happened to be newest into a warning about their own software.
	static func newsHeadline(_ room: WalletbeatRoom) -> String {
		guard let news = room.news, news.total > 0 else {
			// No incident has landed on this device yet, which is a fact about the read
			// rather than about the world — §83's rule in the one room built to report
			// what is known.
			return String(localized: "Reading Walletbeat…")
		}
		if news.open > 0 {
			return news.open == 1
				? String(localized: "One wallet security incident is still unresolved")
				: String(localized: "\(news.open) wallet security incidents are still unresolved")
		}
		if news.recent > 0 {
			return news.recent == 1
				? String(localized: "One wallet security incident in the last 30 days")
				: String(localized: "\(news.recent) wallet security incidents in the last 30 days")
		}
		return String(localized: "No wallet security incidents in the last 30 days")
	}

	/// The second line. Always the UPGRADE, because the head's job here is to say what
	/// following does not cover: incidents are about wallets in general, and a review of
	/// the wallet in your pocket needs you to name it.
	static func newsNote(_ room: WalletbeatRoom) -> String {
		guard let news = room.news, news.total > 0 else {
			return String(localized: "Walletbeat's security incidents arrive here. Name the wallet apps you use to add their reviews.")
		}
		return String(localized: "\(news.total) landed so far. Name the wallet apps you use and Walletbeat's review of each arrives too — where its keys are made, who sees your addresses.")
	}

	/// What the room's one button says.
	///
	/// The button has always been the door to the directory, and §421 already made its
	/// label follow the tier — "browse" describes the screen rather than the reason to
	/// open it. This takes that one step further where the app has the evidence: somebody
	/// who has connected a wallet does not want to browse thirty-two, they want to name
	/// the one they use, and the handshake already said which (prd §430).
	///
	/// NAMED ONLY WHILE NOTHING IS WATCHED. Once a wallet is named the button's job is the
	/// rest of the registry again, and a label that went on naming one wallet forever
	/// would be a nag rather than a shortcut.
	static func browseLabel(_ room: WalletbeatRoom) -> String {
		guard room.items.isEmpty else {
			return String(localized: "Every wallet Walletbeat rates")
		}
		if let name = room.connectedName {
			return String(localized: "Watch \(name) — you've connected with it")
		}
		return String(localized: "Watch the wallet apps you use")
	}

	static func coverageNote(_ room: WalletbeatRoom) -> String? {
		guard !room.items.isEmpty else {
			return room.news == nil
				? nil
				: String(localized: "Walletbeat's reading, not ours · every wallet they cover")
		}
		let shown = room.items.count
		if shown < room.total {
			return String(localized: "Showing \(shown) of \(room.total) · Walletbeat's ratings, read on this device")
		}
		return String(localized: "Walletbeat's ratings, not ours · read on this device")
	}
}
