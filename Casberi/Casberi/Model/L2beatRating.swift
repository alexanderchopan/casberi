import Foundation

// L2BEAT's risk assessments, as a model (prd §428).
//
// THE CENTRAL RULE, inherited whole from §419: every judgment here is L2BEAT'S and this app
// only ever counts, groups and quotes it. Nothing in this file scores a chain, ranks one
// against another, or folds five risks into a verdict.
//
// AND HERE THE RULE IS FREE, WHICH IT WAS NOT FOR WALLETBEAT. Walletbeat publishes no
// composite, so §419 had to refuse to invent one. L2BEAT publishes ITS OWN — `stage`, the
// Stage 0/1/2 ladder their whole methodology exists to produce — so the honest move is to
// cite theirs and compute nothing. Measured 2026-08-21 across all 105 projects: 76 Stage 0,
// 6 Stage 1, 4 Stage 2, 19 "Not applicable".
//
// WHY THERE IS NO COVERAGE GATE HERE. §419 built `WalletbeatCoverage` because most wallets
// were barely examined — sixteen of thirty-two under a quarter, two at literal zero — so a
// bar drawn from raw counts stated a verdict nobody had reached. L2BEAT has no such hole:
// measured 2026-08-21, all 105 projects carry all 5 risks, every one with a value, a
// sentiment and a sentence. So a five-cell strip is honest for every project with no gate
// in front of it, and the whole coverage apparatus is deliberately absent rather than
// ported. If that ever stops being true — a project landing with fewer than five — the
// strip must gain a gate before it gains a cell.

// MARK: - The five axes

/// L2BEAT's own risk axes, in their own order.
///
/// DRIVEN BY THIS ENUM AND NEVER BY THE PAYLOAD'S ORDER. Measured 2026-08-21, all 105
/// projects list the five in one identical order — which is exactly the condition under
/// which depending on it is invisible until the day it changes. §419's rule: an unknown
/// group is skipped rather than guessed into a slot, and the order a card draws in can
/// never depend on JSON ordering.
enum L2beatRiskAxis: String, CaseIterable, Codable, Sendable {
	case sequencerFailure
	case stateValidation
	case dataAvailability
	case exitWindow
	case proposerFailure

	/// L2BEAT's own display name — the string their payload carries, which is also how
	/// their site labels the column. Matched on this, so a rename is a MISS rather than a
	/// silent misfiling into the wrong axis.
	var wireName: String {
		switch self {
		case .sequencerFailure: return "Sequencer Failure"
		case .stateValidation: return "State Validation"
		case .dataAvailability: return "Data Availability"
		case .exitWindow: return "Exit Window"
		case .proposerFailure: return "Proposer Failure"
		}
	}

	/// Sentence case, per the design system's no-eyebrow rule.
	var label: String {
		switch self {
		case .sequencerFailure: return String(localized: "Sequencer failure")
		case .stateValidation: return String(localized: "State validation")
		case .dataAvailability: return String(localized: "Data availability")
		case .exitWindow: return String(localized: "Exit window")
		case .proposerFailure: return String(localized: "Proposer failure")
		}
	}

	/// The axis name at STRIP WIDTH — one word per cell.
	///
	/// It exists so the five positions can be NAMED once, on the risk card, under the strip
	/// they belong to. The strip's whole design is that the same question is always in the
	/// same place; until this landed, nowhere in the app said which place, so the
	/// correspondence was there to be learned with nothing to learn it from.
	///
	/// A SHORTENING OF OUR OWN LABEL, never of L2BEAT's reading. `label` is already ours —
	/// their `wireName` is Title Case and the design system bans that — and this is the same
	/// name with the shared noun dropped, which is unambiguous precisely because all five
	/// appear together. No value, sentence or verdict L2BEAT publishes is abbreviated
	/// anywhere in this feature.
	var shortLabel: String {
		switch self {
		case .sequencerFailure: return String(localized: "Sequencer")
		case .stateValidation: return String(localized: "State")
		case .dataAvailability: return String(localized: "Data")
		case .exitWindow: return String(localized: "Exit")
		case .proposerFailure: return String(localized: "Proposer")
		}
	}

	/// What the axis is ASKING, in plain words.
	///
	/// OURS, AND THE ONLY TEXT IN THIS FEATURE THAT IS. Every verdict, value and sentence
	/// displayed anywhere here is L2BEAT's, quoted verbatim; these five lines are a plain
	/// description of what the column means, because "Proposer Failure" tells a reader
	/// nothing on its own. They are about the QUESTION and never about any chain's answer
	/// to it, so they stay true whatever L2BEAT rates — the `whyItMatters` split from §419,
	/// with the sides reversed because L2BEAT does not publish this text and Walletbeat did.
	/// Every surface that shows one pairs it with L2BEAT's own answer, never in place of it.
	var asks: String {
		switch self {
		case .sequencerFailure:
			return String(localized: "If the chain's operator stops taking your transactions, can you still get one in?")
		case .stateValidation:
			return String(localized: "What stops the chain from reporting a balance that isn't real?")
		case .dataAvailability:
			return String(localized: "Is the data needed to reconstruct your balance published where anyone can read it?")
		case .exitWindow:
			return String(localized: "If the rules are changed against you, how long do you have to get your money out?")
		case .proposerFailure:
			return String(localized: "If the party posting the chain's state disappears, can your funds still leave?")
		}
	}

	static func named(_ raw: String) -> L2beatRiskAxis? {
		allCases.first { $0.wireName == raw }
	}
}

// MARK: - Their sentiment

/// L2BEAT's own reading of one risk.
///
/// FIVE CASES, and `unknown` is the load-bearing one: a sentiment we do not recognise must
/// never fall through to `good`. Measured 2026-08-21 the wire carries good/bad/warning on
/// 524 of 525 risks and `neutral` on exactly one — so the vocabulary is small, stable, and
/// precisely the kind that grows without warning.
enum L2beatSentiment: String, Codable, Sendable, CaseIterable {
	case good
	case warning
	case bad
	case neutral
	case unknown

	/// How much attention this asks for. Ordering only — never summed, never averaged into
	/// a score. `neutral` and `unknown` sit at the bottom together because neither is a
	/// finding, and above `good` only in the sense that "no reading" is not "fine".
	var concern: Int {
		switch self {
		case .bad: return 3
		case .warning: return 2
		case .neutral, .unknown: return 1
		case .good: return 0
		}
	}

	/// Whether L2BEAT is flagging something. Drives tone, never a score.
	var isConcerning: Bool { self == .bad }

	static func read(_ raw: String?) -> L2beatSentiment {
		guard let raw else { return .unknown }
		return L2beatSentiment(rawValue: raw.lowercased()) ?? .unknown
	}
}

// MARK: - One risk

/// L2BEAT's own qualification on a risk — a second reading they publish BESIDE the first.
///
/// MEASURED 2026-08-21 AND THE SHARPEST TRAP IN THIS PAYLOAD. Thirteen risks carry a
/// `regular` block and four a `warning` block, and Arbitrum — the most-watched chain on the
/// list — is one of them: its Exit Window reads `value: "None", sentiment: bad` at the top
/// with `regular: { value: "10d", sentiment: warning }` underneath. The top level is the
/// EMERGENCY case (contracts are instantly upgradable) and `regular` is the ordinary one
/// (non-emergency upgrades leave you ten days). Reading only the top level throws away the
/// number an Arbitrum user actually wants; reading only `regular` states a reassurance
/// L2BEAT explicitly did not make. So both are kept, drawn one under the other, and NEITHER
/// is ever merged into the other's sentiment — merging would be us editing their call.
struct L2beatRiskNote: Codable, Sendable, Equatable {
	/// L2BEAT's word for this reading — "10d", "None", "∞".
	let value: String
	let sentiment: L2beatSentiment
	/// Their sentence. Optional: a `warning` block carries none.
	var explanation: String?
}

/// One of the five risks, as L2BEAT publishes it.
struct L2beatRisk: Codable, Sendable, Equatable, Identifiable {
	let axis: L2beatRiskAxis
	/// L2BEAT's own word — "Self sequence", "No mechanism", "Validity proofs (SN)".
	///
	/// Note `"None"` is a VALUE, not an absence: it is L2BEAT's word for "there is no exit
	/// window", and measured 2026-08-21 no risk on any project carries an empty one.
	let value: String
	let sentiment: L2beatSentiment
	/// Their sentence, verbatim.
	let explanation: String
	/// Their own qualification, where they publish one. See `L2beatRiskNote`.
	var second: L2beatRiskNote?

	var id: String { axis.rawValue }

	/// The strongest concern L2BEAT expresses about this risk ANYWHERE — the headline
	/// sentiment, or a nested one if theirs is worse.
	///
	/// USED ONLY TO CHOOSE WHICH OF THEIR SENTENCES LEADS, never to redraw the strip. The
	/// strip shows `sentiment` verbatim because that is their headline call. But the LEAD is
	/// a choice of what to say first, and leading with something mild while L2BEAT has
	/// written "the single hardcoded address can withdraw all funds" one line down is the
	/// §419 Rabby failure — a naive read handing back the opposite of what the people we are
	/// citing actually said. Measured 2026-08-21: this changes the reading of exactly 2 of
	/// 525 risks, and one of them is that sentence.
	var worstSentiment: L2beatSentiment {
		guard let second, second.sentiment.concern > sentiment.concern else { return sentiment }
		return second.sentiment
	}

	/// The sentence that goes with `worstSentiment`, so a lead never pairs one reading's
	/// severity with the other reading's words.
	var worstExplanation: String {
		if let second, second.sentiment.concern > sentiment.concern {
			if let text = second.explanation, !text.isEmpty { return text }
			return second.value
		}
		return explanation
	}
}

// MARK: - Their stage

/// L2BEAT's own composite, cited and never computed.
///
/// A raw string would have done, and is what the first cut had. It is an enum because the
/// three real stages ORDER and "Not applicable" does not — a chain L2BEAT excludes from the
/// ladder (measured: 19 of 105, Hyperliquid and Gnosis among them) is not a worse Stage 0,
/// and any code that sorted on the raw string would have placed it as one.
enum L2beatStage: String, Codable, Sendable, CaseIterable {
	case stage0 = "Stage 0"
	case stage1 = "Stage 1"
	case stage2 = "Stage 2"
	case notApplicable = "Not applicable"

	/// Where this sits on L2BEAT's ladder, or nil for a chain they do not place on it.
	/// Nil is not zero, and nothing here may treat it as zero.
	var rung: Int? {
		switch self {
		case .stage0: return 0
		case .stage1: return 1
		case .stage2: return 2
		case .notApplicable: return nil
		}
	}

	var label: String {
		switch self {
		case .stage0: return String(localized: "Stage 0")
		case .stage1: return String(localized: "Stage 1")
		case .stage2: return String(localized: "Stage 2")
		case .notApplicable: return String(localized: "Not staged")
		}
	}

	/// What the rung MEANS, in L2BEAT's own framing of their ladder: how much of the chain
	/// still depends on its operators behaving.
	var meaning: String {
		switch self {
		case .stage0:
			return String(localized: "Full training wheels — the operators can still change the rules.")
		case .stage1:
			return String(localized: "Limited training wheels — a security council can still override.")
		case .stage2:
			return String(localized: "No training wheels — users are protected by proofs alone.")
		case .notApplicable:
			return String(localized: "L2BEAT does not place this chain on the stage ladder.")
		}
	}

	/// An unrecognised stage word is nil, never `.stage0`. A chain L2BEAT has begun placing
	/// on a rung we do not know about must read as unplaced, not as the bottom rung.
	static func read(_ raw: String?) -> L2beatStage? {
		guard let raw, !raw.isEmpty else { return nil }
		return L2beatStage(rawValue: raw)
	}
}

// MARK: - A project

/// Which layer a project sits on. L2BEAT's own split; measured 89 layer2 and 16 layer3.
enum L2beatLayer: String, Codable, Sendable {
	case layer2
	case layer3

	var label: String {
		switch self {
		case .layer2: return String(localized: "Layer 2")
		case .layer3: return String(localized: "Layer 3")
		}
	}
}

/// One chain as L2BEAT assesses it.
///
/// TWO IDENTIFIERS AND BOTH ARE LOAD-BEARING, measured 2026-08-21. `id` is the name of the
/// project's own directory in L2BEAT's repo, which is what the milestone read joins on;
/// `slug` is the segment in their public URL. They differ for TEN of the 105 — including OP
/// Mainnet (`optimism` / `op-mainnet`), ZKsync Era (`zksync2` / `zksync-era`), World Chain
/// and Ronin — so joining on the wrong one loses four of the biggest chains on the list, and
/// loses them SILENTLY: a chain with no milestone file reads exactly like a chain with no
/// milestones.
struct L2beatProject: Codable, Sendable, Equatable, Identifiable {
	let id: String
	let slug: String
	let name: String
	let layer: L2beatLayer
	/// The chain this one settles to. "Ethereum" for most; an L3 names its L2.
	let hostChain: String?
	/// L2BEAT's own classification — "Optimistic Rollup", "ZK Rollup", "Validium",
	/// "Optimium", "Other". Measured: 77 of 105 are "Other".
	let category: String?
	let stage: L2beatStage?
	/// L2BEAT is re-examining this project. Their flag, and it outranks every finding on the
	/// row: a rating under review is one they are telling you not to lean on yet.
	let underReview: Bool
	let archived: Bool
	let risks: [L2beatRisk]

	/// Their risks in OUR axis order, so a card can never reshuffle between reads.
	var orderedRisks: [L2beatRisk] {
		L2beatRiskAxis.allCases.compactMap { axis in risks.first { $0.axis == axis } }
	}

	func risk(_ axis: L2beatRiskAxis) -> L2beatRisk? { risks.first { $0.axis == axis } }

	/// How many of the five L2BEAT flags. A count of their calls, never a score.
	var flagged: Int { risks.filter { $0.sentiment.isConcerning }.count }

	/// The project's page on L2BEAT. Built from the SLUG — see the note on the two
	/// identifiers; building it from `id` 404s for ten projects.
	var pageURL: URL? {
		URL(string: "https://\(L2beatHost.site)/scaling/projects/\(slug)")
	}

	/// What this project's row leads with.
	///
	/// THE SELECTION RULE IS FIXED AND STATED, because choosing which finding leads is the
	/// one editorial act this feature cannot avoid — so it is mechanical rather than
	/// tasteful, exactly as §419 made it. Under review always wins: L2BEAT saying "we are
	/// re-examining this" outranks any reading of theirs that may be about to change.
	/// Otherwise the first `bad` in their own axis order leads, then the first `warning`,
	/// and a project with neither is said to have nothing flagged rather than being called
	/// safe. Measured 2026-08-21: only 4 of 105 reach that last case.
	var lead: L2beatLead {
		if underReview { return .underReview }
		guard !risks.isEmpty else { return .unread }
		for axis in L2beatRiskAxis.allCases {
			guard let risk = risk(axis) else { continue }
			if risk.worstSentiment == .bad { return .finding(risk) }
		}
		for axis in L2beatRiskAxis.allCases {
			guard let risk = risk(axis) else { continue }
			if risk.worstSentiment == .warning { return .finding(risk) }
		}
		return .nothingFlagged(count: risks.count)
	}
}

/// The one line a project's row leads with. Every case names its own evidence, so no caller
/// can render a finding without the context that makes it true.
enum L2beatLead: Sendable, Equatable {
	/// No risks read on this device yet — a fact about the read, never about the chain.
	case unread
	case underReview
	case finding(L2beatRisk)
	case nothingFlagged(count: Int)

	var isConcerning: Bool {
		switch self {
		case .finding(let risk): return risk.worstSentiment == .bad
		case .unread, .underReview, .nothingFlagged: return false
		}
	}

	/// The dense form for a directory row — WHICH question L2BEAT leads with, in a phrase.
	///
	/// IT REPLACES A TALLY. The row used to print "2 of 5 flagged" two points from a strip
	/// that says exactly that in colour, so the one line of words on a browse row spent
	/// itself repeating the drawing beside it. The strip is what lets two rows be compared
	/// without reading either; this is the one fact it cannot carry at sixty points — which
	/// of the five — and it stays a WORD, so the row still reads in greyscale and to anyone
	/// who has not learned the palette (`L2beatSentimentTag`'s rule, kept rather than traded).
	///
	/// Never a count and never a verdict: it names L2BEAT's own leading call, chosen by the
	/// fixed ladder in `L2beatProject.lead`, and a chain with nothing flagged is said to have
	/// nothing flagged rather than being called safe.
	var shortLabel: String {
		switch self {
		case .unread:
			return String(localized: "Not assessed")
		case .underReview:
			return String(localized: "Under review")
		case .finding(let risk):
			return risk.worstSentiment == .bad
				? String(localized: "\(risk.axis.label) flagged")
				: String(localized: "\(risk.axis.label) has a caveat")
		case .nothingFlagged:
			return String(localized: "Nothing flagged")
		}
	}
}

// MARK: - Hosts

/// One place names the hosts, so a screen, the ingest and the reach registry cannot drift.
enum L2beatHost {
	/// L2BEAT's own site, which serves the risk data keylessly.
	///
	/// MEASURED 2026-08-21, and stated plainly because it is the one real weakness in this
	/// bridge: this is the SITE's own data endpoint, undocumented and unversioned. L2BEAT's
	/// documented API lives on `api.l2beat.com` and answers 401 without a key. So the shape
	/// here has no contract behind it, which is why `scripts/live-integrations.sh` asserts
	/// the three fields the whole room rests on — `projects`, `stage` and `risks[].sentiment`
	/// — every night. A rename empties the room silently otherwise.
	static let site = "l2beat.com"
	/// Their config repo, for the milestones. Their default branch is `main`.
	static let rawContent = "raw.githubusercontent.com"
	static let repo = "l2beat/l2beat"
	static let branch = "main"

	/// Every project, with its stage and all five risks, in ONE request.
	///
	/// Walletbeat needed one ~342KB document per wallet, which is why §419 had to bundle a
	/// counts-only snapshot and fetch a full card per wallet opened. This is 290KB for all
	/// 105 with nothing left out, so there is no per-project read at all.
	static var summaryURL: URL? {
		URL(string: "https://\(site)/api/scaling/summary")
	}

	/// One project's config file, which is where the milestones live. Keyed on `id`, the
	/// directory name — see the two-identifier note on `L2beatProject`.
	static func milestonesURL(projectID: String) -> URL? {
		URL(string: "https://\(rawContent)/\(repo)/\(branch)/packages/config/src/projects/\(projectID)/\(projectID).ts")
	}
}

// MARK: - Parsing L2BEAT's published assessments

enum L2beatSummaryParse {
	/// Read the whole scaling summary.
	///
	/// Every field degrades: a project missing a name keeps its id, an unknown sentiment
	/// reads `unknown`, an unrecognised axis is DROPPED rather than guessed into a slot.
	/// A project with no readable risks still lands — it is a real chain L2BEAT lists, and
	/// dropping it would make the directory quietly shorter than their own.
	static func projects(from data: Data) -> [L2beatProject] {
		guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
		return projects(fromObject: root)
	}

	/// The same read, from an already-deserialized object.
	///
	/// The live path takes this one. `IngestSupport.getJSON` hands back a parsed object, and
	/// re-encoding it to `Data` only to parse it again is a 290KB round trip on every sweep
	/// — §419 did exactly that because its documents are 342KB per wallet and it needed the
	/// `Data` shape anyway. The `Data` overload above stays for the harness and for anyone
	/// holding bytes.
	static func projects(fromObject root: Any) -> [L2beatProject] {
		guard
			let root = root as? [String: Any],
			let table = root["projects"] as? [String: Any]
		else { return [] }

		var out: [L2beatProject] = []
		for (key, raw) in table {
			guard let block = raw as? [String: Any] else { continue }
			let id = (block["id"] as? String) ?? key
			let slug = (block["slug"] as? String) ?? id
			let layer = L2beatLayer(rawValue: (block["type"] as? String) ?? "") ?? .layer2
			out.append(
				L2beatProject(
					id: id,
					slug: slug,
					name: (block["name"] as? String) ?? id,
					layer: layer,
					hostChain: block["hostChain"] as? String,
					category: block["category"] as? String,
					stage: L2beatStage.read(block["stage"] as? String),
					underReview: (block["isUnderReview"] as? Bool) ?? false,
					archived: (block["isArchived"] as? Bool) ?? false,
					risks: risks(from: block["risks"])
				)
			)
		}
		// Sorted by name so two reads of the same payload produce the same order — a
		// dictionary has none, and a directory that reshuffles between opens reads as broken.
		out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		return out
	}

	static func risks(from raw: Any?) -> [L2beatRisk] {
		guard let list = raw as? [[String: Any]] else { return [] }
		var out: [L2beatRisk] = []
		for entry in list {
			guard
				let name = entry["name"] as? String,
				let axis = L2beatRiskAxis.named(name),
				let value = entry["value"] as? String,
				// An empty value is DROPPED, not kept as a blank cell. Measured
				// 2026-08-21 no risk on any of the 105 carries one — note `"None"`
				// is a real value, L2BEAT's own word for "there is no exit window",
				// and only a genuinely absent string reaches this.
				!value.isEmpty
			else { continue }
			out.append(
				L2beatRisk(
					axis: axis,
					value: value,
					sentiment: L2beatSentiment.read(entry["sentiment"] as? String),
					explanation: (entry["description"] as? String) ?? "",
					second: note(entry["regular"]) ?? note(entry["warning"])
				)
			)
		}
		// Deduped by axis, keeping the first: two blocks for one axis would otherwise draw
		// two cells in a strip built to have five.
		var seen = Set<L2beatRiskAxis>()
		let deduped = out.filter { seen.insert($0.axis).inserted }
		// Returned in OUR axis order, so the STORED array is canonical too. `orderedRisks`
		// would reorder these at every draw anyway — sorting here makes that a safety net
		// rather than the only thing standing between the strip and the payload's order,
		// and it matters because these are persisted: a reading decoded from disk months
		// later must paint the same five cells in the same five places.
		return L2beatRiskAxis.allCases.compactMap { axis in deduped.first { $0.axis == axis } }
	}

	private static func note(_ raw: Any?) -> L2beatRiskNote? {
		guard let block = raw as? [String: Any], let value = block["value"] as? String,
			!value.isEmpty
		else { return nil }
		return L2beatRiskNote(
			value: value,
			sentiment: L2beatSentiment.read(block["sentiment"] as? String),
			explanation: (block["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
		)
	}
}

// MARK: - Revisions

/// What changed between two readings of the same project.
///
/// TWO KINDS AND THEY ARE NOT THE SAME NEWS. A risk changing is L2BEAT revising one reading;
/// a STAGE changing is the thing their whole methodology exists to certify, and "Base
/// reached Stage 1" is the single most reported event this data produces. Folding them into
/// one "something changed" row would bury the second inside the first.
enum L2beatChange: Sendable, Equatable {
	case risk(axis: L2beatRiskAxis, before: L2beatSentiment, after: L2beatSentiment,
			  value: String, explanation: String)
	case stage(before: L2beatStage?, after: L2beatStage)

	/// Whether L2BEAT moved in the direction that is good news. Used for wording only.
	var isImprovement: Bool {
		switch self {
		case .risk(_, let before, let after, _, _):
			return after.concern < before.concern
		case .stage(let before, let after):
			guard let after = after.rung else { return false }
			return after > (before?.rung ?? -1)
		}
	}
}

enum L2beatRevisions {
	/// Compare two readings of one project.
	///
	/// A risk moving to `unknown` is deliberately NOT reported: an unreadable sentiment is
	/// our information degrading, not the chain's safety changing, and wording it as news
	/// would read as a downgrade of the chain (§419's withdrawn-rating rule).
	///
	/// A stage moving to `notApplicable` is reported, because that IS a real change: L2BEAT
	/// removing a chain from the ladder is them saying the ladder no longer describes it.
	static func between(_ before: L2beatProject, _ after: L2beatProject) -> [L2beatChange] {
		guard before.id == after.id else { return [] }
		var out: [L2beatChange] = []

		if let now = after.stage, now != before.stage {
			out.append(.stage(before: before.stage, after: now))
		}

		let old = Dictionary(before.risks.map { ($0.axis, $0) }, uniquingKeysWith: { a, _ in a })
		for axis in L2beatRiskAxis.allCases {
			guard let now = after.risk(axis), let was = old[axis] else { continue }
			guard now.sentiment != was.sentiment else { continue }
			guard now.sentiment != .unknown else { continue }
			out.append(
				.risk(axis: axis, before: was.sentiment, after: now.sentiment,
					  value: now.value, explanation: now.explanation))
		}
		return out
	}
}
