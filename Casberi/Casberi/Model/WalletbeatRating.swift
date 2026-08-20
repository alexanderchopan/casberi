import Foundation

// Walletbeat's ratings, as a model (prd §419).
//
// THE CENTRAL RULE: every judgment here is WALLETBEAT'S and the app only ever counts,
// groups and quotes it. Nothing in this file scores a wallet, ranks one against another,
// or sums dimensions into a verdict — Walletbeat itself declines to publish a composite,
// and inventing one would put our editorial judgment behind their name (§83).
//
// WHY COVERAGE LEADS EVERYTHING, measured 2026-08-20 across all 32 rated wallets: most
// wallets are overwhelmingly UNRATED. Trezor and Firefly are 0 of 25 attributes rated,
// Uniswap Wallet is 1 of 29, and only six wallets clear 80% (Ambire 28/28, MetaMask,
// Rabby, Rainbow 25/29, Zerion 24/29). So a bar chart drawn from raw counts is a LIE by
// omission: an unrated attribute renders as an absence of bad news, and Trezor — about
// which nothing at all is known — reads as cleaner than Rabby, about which a great deal
// is known and some of it is bad. `Coverage` exists so no surface can state a finding
// without first stating how much was looked at.

// MARK: - Dimensions

/// Walletbeat's own attribute groups, in their own order. `maintenance` is published for
/// hardware wallets only, so a software wallet must never be shown an empty sixth group.
enum WalletbeatDimension: String, CaseIterable, Codable, Sendable {
	case security
	case privacy
	case selfSovereignty
	case transparency
	case ecosystem
	case maintenance

	/// Sentence case, per the design system's no-eyebrow rule.
	var label: String {
		switch self {
		case .security: return String(localized: "Security")
		case .privacy: return String(localized: "Privacy")
		case .selfSovereignty: return String(localized: "Self-sovereignty")
		case .transparency: return String(localized: "Transparency")
		case .ecosystem: return String(localized: "Ecosystem")
		case .maintenance: return String(localized: "Maintenance")
		}
	}
}

/// One rating Walletbeat can give an attribute. Their vocabulary, documented in their own
/// `llms.txt`, and deliberately five cases rather than four: EXEMPT ("does not apply to
/// this wallet") is NOT unrated ("nobody has checked"). Folding them together reports a
/// wallet as under-examined when the question simply never applied to it.
enum WalletbeatVerdict: String, Codable, Sendable, CaseIterable {
	case pass = "PASS"
	case partial = "PARTIAL"
	case fail = "FAIL"
	case unrated = "UNRATED"
	case exempt = "EXEMPT"

	/// Whether Walletbeat reached a judgment at all. EXEMPT is excluded on purpose: there
	/// was no question to answer, so counting it as "examined" inflates coverage.
	var isJudged: Bool {
		self == .pass || self == .partial || self == .fail
	}
}

// MARK: - Counts

/// How many of one dimension's attributes landed on each verdict. A count, never a score.
struct WalletbeatCounts: Codable, Sendable, Equatable {
	let pass: Int
	let partial: Int
	let fail: Int
	let unrated: Int
	let exempt: Int

	init(pass: Int = 0, partial: Int = 0, fail: Int = 0, unrated: Int = 0, exempt: Int = 0) {
		self.pass = pass
		self.partial = partial
		self.fail = fail
		self.unrated = unrated
		self.exempt = exempt
	}

	/// Every attribute Walletbeat lists in this dimension, judged or not.
	var total: Int { pass + partial + fail + unrated + exempt }

	/// Attributes Walletbeat actually reached a verdict on.
	var judged: Int { pass + partial + fail }

	/// The denominator coverage is measured against. EXEMPT attributes are removed from
	/// BOTH halves rather than counted as gaps — a hardware wallet exempt from a browser
	/// question has not been under-examined.
	var applicable: Int { total - exempt }

	static func + (a: WalletbeatCounts, b: WalletbeatCounts) -> WalletbeatCounts {
		WalletbeatCounts(
			pass: a.pass + b.pass,
			partial: a.partial + b.partial,
			fail: a.fail + b.fail,
			unrated: a.unrated + b.unrated,
			exempt: a.exempt + b.exempt
		)
	}

	static let zero = WalletbeatCounts()

	func count(of verdict: WalletbeatVerdict) -> Int {
		switch verdict {
		case .pass: return pass
		case .partial: return partial
		case .fail: return fail
		case .unrated: return unrated
		case .exempt: return exempt
		}
	}
}

// MARK: - Coverage

/// How much of a wallet Walletbeat has actually examined.
///
/// THRESHOLDS ARE MEASURED, NOT GUESSED (2026-08-20, all 32 wallets). The judged-attribute
/// distribution is strongly bimodal: six wallets sit at 83–100% (Ambire, MetaMask, Rabby,
/// Rainbow, Zerion, and Base App at 56%), a middle band sits between 34% and 56%, and
/// SIXTEEN sit under a quarter — including two at exactly zero. `deep` at 0.7 keeps the
/// well-examined group together, `partial` at 0.3 catches the middle band, and `thin`
/// covers the long tail where a bar chart would otherwise imply a verdict nobody made.
enum WalletbeatCoverage: Sendable, Equatable {
	/// Nothing judged at all — the only honest reading is "not rated yet".
	case none
	/// Some attributes judged, but too few for the shape to mean anything.
	case thin
	case partial
	case deep

	static let deepFloor = 0.7
	static let partialFloor = 0.3

	static func of(_ counts: WalletbeatCounts) -> WalletbeatCoverage {
		guard counts.applicable > 0, counts.judged > 0 else { return .none }
		let share = Double(counts.judged) / Double(counts.applicable)
		if share >= deepFloor { return .deep }
		if share >= partialFloor { return .partial }
		return .thin
	}

	/// Whether a surface may draw the ratings as a comparable shape. Below this, a strip
	/// of colour states a verdict Walletbeat never reached, so the row says what is
	/// missing instead. This is the single gate every ratings view must ask.
	var showsShape: Bool { self == .deep || self == .partial }
}

// MARK: - A directory entry

/// One wallet in the bundled snapshot (`WalletbeatDirectory`, generated by
/// `scripts/walletbeat-snapshot.py`). Counts only — the full report card with Walletbeat's
/// own sentences is fetched live for the one wallet you opened.
struct WalletbeatEntry: Sendable, Identifiable, Equatable {
	let id: String
	let name: String
	let hardware: Bool
	let variants: [String]
	let stage: String?
	let updated: String?
	let counts: [WalletbeatDimension: WalletbeatCounts]

	/// Dimensions this wallet actually has, in Walletbeat's order. Driven by `allCases`
	/// rather than the dictionary, which is unordered — reading a Dictionary's own order
	/// would reshuffle the bars between launches, which reads as broken.
	var dimensions: [WalletbeatDimension] {
		WalletbeatDimension.allCases.filter { (counts[$0]?.total ?? 0) > 0 }
	}

	var overall: WalletbeatCounts {
		dimensions.reduce(WalletbeatCounts.zero) { $0 + (counts[$1] ?? .zero) }
	}

	var coverage: WalletbeatCoverage { .of(overall) }

	/// The wallet's page on Walletbeat. Built from the id because every entry in the
	/// snapshot came from that path, so it cannot point somewhere that does not exist.
	var pageURL: URL? { URL(string: "https://\(WalletbeatHost.site)/\(id)/") }
}

/// One place names the hosts, so a screen, the ingest and the reach registry cannot drift.
enum WalletbeatHost {
	/// Walletbeat's beta build — the only deployment publishing the machine-readable
	/// ratings (measured 2026-08-20: `walletbeat.org` serves the site but answers
	/// `/rabby/index.json` with HTML, and `wallet.page`, which their own `$schema` names,
	/// is an unrelated docs site).
	static let site = "beta.walletbeat.eth.limo"
	/// Their registry, for the incident feed. Their default branch is `beta`, not `main`.
	static let rawContent = "raw.githubusercontent.com"
	static let api = "api.github.com"
	static let repo = "walletbeat/walletbeat"
	static let branch = "beta"

	static func ratingsURL(walletID: String) -> URL? {
		URL(string: "https://\(site)/\(walletID)/index.json")
	}
}

// MARK: - A fetched report card

/// One attribute as Walletbeat publishes it: their question, their verdict, their sentence.
struct WalletbeatAttribute: Codable, Sendable, Equatable, Identifiable {
	let id: String
	let dimension: WalletbeatDimension
	let name: String
	/// Walletbeat's own one-line framing, e.g. "Is your wallet address linkable to other
	/// information about yourself?" — kept because it says what the verdict is ABOUT.
	let question: String
	let verdict: WalletbeatVerdict
	/// Walletbeat's own sentence. Displayed verbatim; never rewritten, never summarised.
	let explanation: String
}

/// A wallet's full ratings as last read from Walletbeat.
struct WalletbeatCard: Codable, Sendable, Equatable {
	let walletID: String
	let name: String
	let hardware: Bool
	let stage: String?
	/// The day WALLETBEAT last revised the entry — not the day we read it. Both are shown,
	/// because a fresh read of a two-year-old entry is not fresh information.
	let lastUpdated: String?
	let site: String?
	let attributes: [WalletbeatAttribute]
	let fetchedAt: Date

	func attributes(in dimension: WalletbeatDimension) -> [WalletbeatAttribute] {
		attributes.filter { $0.dimension == dimension }
	}

	var dimensions: [WalletbeatDimension] {
		WalletbeatDimension.allCases.filter { d in attributes.contains { $0.dimension == d } }
	}

	func counts(in dimension: WalletbeatDimension) -> WalletbeatCounts {
		var pass = 0, partial = 0, fail = 0, unrated = 0, exempt = 0
		for attribute in attributes where attribute.dimension == dimension {
			switch attribute.verdict {
			case .pass: pass += 1
			case .partial: partial += 1
			case .fail: fail += 1
			case .unrated: unrated += 1
			case .exempt: exempt += 1
			}
		}
		return WalletbeatCounts(pass: pass, partial: partial, fail: fail, unrated: unrated, exempt: exempt)
	}

	var overall: WalletbeatCounts {
		dimensions.reduce(WalletbeatCounts.zero) { $0 + counts(in: $1) }
	}

	var coverage: WalletbeatCoverage { .of(overall) }

	/// What this wallet's row says under its name.
	///
	/// THE SELECTION RULE IS FIXED AND STATED, because choosing which finding leads is the
	/// one editorial act this feature cannot avoid — so it is made mechanical rather than
	/// tasteful. Thin coverage always wins: "nobody has checked this" outranks any single
	/// finding, and leading with a lone FAIL from a wallet with two judged attributes would
	/// imply the other twenty-three were fine. Otherwise the first FAIL in Walletbeat's own
	/// dimension order leads, then the first PARTIAL, and a wallet with neither is said to
	/// have no failures rather than being called good.
	var lead: WalletbeatLead {
		let counts = overall
		switch coverage {
		case .none:
			return .unexamined(applicable: counts.applicable)
		case .thin:
			return .barelyExamined(judged: counts.judged, applicable: counts.applicable)
		case .partial, .deep:
			if let worst = firstAttribute(verdict: .fail) {
				return .finding(worst)
			}
			if let partial = firstAttribute(verdict: .partial) {
				return .finding(partial)
			}
			return .noFailures(judged: counts.judged, applicable: counts.applicable)
		}
	}

	private func firstAttribute(verdict: WalletbeatVerdict) -> WalletbeatAttribute? {
		for dimension in WalletbeatDimension.allCases {
			if let hit = attributes.first(where: { $0.dimension == dimension && $0.verdict == verdict }) {
				return hit
			}
		}
		return nil
	}
}

/// The one line a wallet row leads with. Every case names its own evidence, so no caller
/// can render a finding without the context that makes it true.
enum WalletbeatLead: Sendable, Equatable {
	case unexamined(applicable: Int)
	case barelyExamined(judged: Int, applicable: Int)
	case finding(WalletbeatAttribute)
	case noFailures(judged: Int, applicable: Int)

	/// Whether this line reports something wrong. Drives tone only — never a score.
	var isConcerning: Bool {
		switch self {
		case .finding(let attribute): return attribute.verdict == .fail
		case .unexamined, .barelyExamined, .noFailures: return false
		}
	}
}

// MARK: - Parsing Walletbeat's published ratings

/// Reads Walletbeat's own `rated-wallet` JSON export.
///
/// We consume their COMPUTED export and never their raw feature files. Measured
/// 2026-08-20: `data/software-wallets/rabby.ts` carries
/// `erc20Approvals: SpendingApprovalsControl.CAN_INSPECT_AND_REVOKE`, while Walletbeat's
/// own evaluator rates that same attribute FAIL — "Rabby does not let you inspect or
/// revoke token approvals" — because a sibling ERC-1155 field drags the attribute down.
/// A plain reading of the features gives the OPPOSITE answer to the people whose judgment
/// we are citing, which is the worst possible failure for a feature built on attribution.
enum WalletbeatRatingParse {
	/// Sentences Walletbeat emits as filler where it has nothing to say. Kept out of the
	/// corpus and off the card: "See full details on the wallet page." under a heading
	/// that already links to the wallet page is noise wearing the shape of a finding.
	static let placeholders: Set<String> = [
		"See full details on the wallet page.",
	]

	static func card(from data: Data, fetchedAt: Date) -> WalletbeatCard? {
		guard
			let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let walletID = root["walletId"] as? String,
			let overall = root["overall"] as? [String: Any]
		else { return nil }

		var attributes: [WalletbeatAttribute] = []
		// Driven by our own enum rather than the payload's key order: a group we do not
		// know is skipped rather than guessed into a dimension, and the order a card
		// draws in can never depend on JSON key ordering.
		for dimension in WalletbeatDimension.allCases {
			guard let group = overall[dimension.rawValue] as? [String: Any] else { continue }
			for (attributeID, raw) in group {
				guard
					let block = raw as? [String: Any],
					let evaluation = block["evaluation"] as? [String: Any],
					let verdictText = evaluation["rating"] as? String
				else { continue }
				let meta = block["attribute"] as? [String: Any]
				// An unknown verdict reads as UNRATED rather than being dropped: a dropped
				// attribute shrinks the denominator, which inflates coverage — the one
				// number this whole file exists to keep honest.
				let verdict = WalletbeatVerdict(rawValue: verdictText) ?? .unrated
				let explanation = (evaluation["shortExplanation"] as? String)
					.map { $0.replacingOccurrences(of: "\n", with: " ") }
					.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
				attributes.append(
					WalletbeatAttribute(
						id: attributeID,
						dimension: dimension,
						name: (meta?["attributeDisplayName"] as? String) ?? attributeID,
						question: (meta?["shortQuestion"] as? String) ?? "",
						verdict: verdict,
						explanation: placeholders.contains(explanation) ? "" : explanation
					)
				)
			}
		}

		guard !attributes.isEmpty else { return nil }
		// Sorted by dimension and then by attribute id so a card's order is TOTAL and
		// identical between reads — a report card that reshuffles between opens over
		// unchanged data reads as broken.
		attributes.sort { a, b in
			let ai = WalletbeatDimension.allCases.firstIndex(of: a.dimension) ?? 0
			let bi = WalletbeatDimension.allCases.firstIndex(of: b.dimension) ?? 0
			return ai == bi ? a.id < b.id : ai < bi
		}

		let types = (root["types"] as? [String])?.map { $0.uppercased() } ?? []
		return WalletbeatCard(
			walletID: walletID,
			name: (root["displayName"] as? String) ?? walletID,
			hardware: types.contains("HARDWARE"),
			stage: root["stage"] as? String,
			lastUpdated: root["lastUpdated"] as? String,
			site: root["website"] as? String,
			attributes: attributes,
			fetchedAt: fetchedAt
		)
	}
}

// MARK: - Revisions

/// What changed between two readings of the same wallet, so a revision can be reported as
/// news with the specific attribute named rather than a bare "something changed".
struct WalletbeatRevision: Sendable, Equatable {
	let attributeID: String
	let dimension: WalletbeatDimension
	let name: String
	let before: WalletbeatVerdict
	let after: WalletbeatVerdict
	let explanation: String

	/// Whether Walletbeat moved from not-knowing to knowing. Reported differently from a
	/// changed verdict — "now rated" and "downgraded" are different news, and wording a
	/// first rating as a change implies the wallet altered something it did not.
	var isFirstJudgment: Bool { !before.isJudged && after.isJudged }
}

enum WalletbeatRevisions {
	/// Compare two cards for the same wallet.
	///
	/// A verdict LOST (a judged attribute going back to UNRATED) is deliberately NOT
	/// reported: Walletbeat withdrawing a rating pending re-examination is housekeeping,
	/// and announcing "your wallet is no longer rated for scam prevention" as news would
	/// read as a downgrade of the wallet rather than of our information.
	static func between(_ before: WalletbeatCard, _ after: WalletbeatCard) -> [WalletbeatRevision] {
		guard before.walletID == after.walletID else { return [] }
		let old = Dictionary(before.attributes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		var out: [WalletbeatRevision] = []
		for attribute in after.attributes {
			guard let was = old[attribute.id] else { continue }
			guard was.verdict != attribute.verdict, attribute.verdict.isJudged else { continue }
			out.append(
				WalletbeatRevision(
					attributeID: attribute.id,
					dimension: attribute.dimension,
					name: attribute.name,
					before: was.verdict,
					after: attribute.verdict,
					explanation: attribute.explanation
				)
			)
		}
		return out
	}
}
