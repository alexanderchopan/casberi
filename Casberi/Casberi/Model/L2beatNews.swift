import Foundation

// L2BEAT's milestones, parsed from their config repo (prd §428).
//
// WHY WE PARSE TYPESCRIPT, the §419 answer one product over: L2BEAT publishes machine-
// readable JSON for RISK (`/api/scaling/summary`) and nothing at all for the timeline. Their
// project pages render it, but measured 2026-08-21 one of those pages is 4.5MB — a scrape
// per chain is not a read this app can make. The source of truth is the `milestones:` array
// in `packages/config/src/projects/<id>/<id>.ts`, a flat object literal with no computed
// values, so it reads like JSON wearing different punctuation. The X-archive precedent.
//
// EVERY FIELD IS OPTIONAL EXCEPT TITLE AND DATE. A registry that adds a field breaks
// nothing here, and one that renames a field we read loses that field rather than the row.

/// How L2BEAT classes a milestone. Their vocabulary — measured 2026-08-21 across all 105
/// projects, 226 milestones: 33 `incident` and 193 `general`.
///
/// An unknown value is kept as `general` and STILL LANDS: a new milestone type is news
/// whether or not we have a word for it, and dropping it would be a silent hole in a
/// timeline whose whole job is to be complete.
enum L2beatMilestoneKind: String, Codable, Sendable {
	case incident
	case general

	var label: String {
		switch self {
		case .incident: return String(localized: "Incident")
		case .general: return String(localized: "Milestone")
		}
	}

	/// Whether this is the half a FOLLOWER gets (prd §428). Incidents are the security feed
	/// and are bundled for every chain; general milestones arrive only for chains you name.
	var isIncident: Bool { self == .incident }
}

// MARK: - How old an incident is

/// How a chain's incident history reads on a row with no room for a date.
///
/// IT EXISTS BECAUSE THE DIRECTORY SHIPPED WITHOUT IT. That screen marked every chain with
/// any incident ON RECORD — the same word, in the same attention colour, whether L2BEAT
/// recorded it last month or in 2021 — on the one screen a person uses to decide where to
/// put money. An assessment is a standing judgment and an incident is an event, which is
/// exactly why the cross-link exists; an event with no date is half an event.
///
/// THE WINDOW IS THE ROOM HEAD'S OWN (`L2beatRoomSource.recencyDays`), handed in rather
/// than redeclared. Two definitions of "recent" in one feature drift, and then the room
/// ranks a chain first that the directory draws as old news — §311's shape, where the two
/// halves stop agreeing and nothing breaks loudly enough to notice.
///
/// Pure, so the harness can prove it: nothing on this host can make L2BEAT record an
/// incident, so these are numbers no other check here will ever see.
enum L2beatIncidentAge {
	/// Inside the window, by the room head's own reckoning.
	static func isRecent(_ date: Date, now: Date, withinDays: Int) -> Bool {
		date >= now.addingTimeInterval(-Double(withinDays) * 86_400)
	}

	/// `("Incident", true)` inside the window, `("Incident 2022", false)` outside.
	///
	/// THE YEAR AND NEVER A RELATIVE PHRASE. "Four years ago" is arithmetic the reader then
	/// has to undo before it can be placed against anything else they know, and this row
	/// sits beside a stage and five risk cells that are all statements about NOW — a
	/// relative age is the one reading among them that quietly keeps moving.
	///
	/// The year is stringified BEFORE it is interpolated: `String(localized:)` groups an
	/// `Int`, so the obvious spelling prints "Incident 2,022" — the §375 defect, which
	/// shipped as "2,019 was your loudest year" in a headline before a harness caught it.
	static func mark(latest: Date, now: Date = .now, withinDays: Int,
					 calendar: Calendar = .current) -> (text: String, recent: Bool) {
		if isRecent(latest, now: now, withinDays: withinDays) {
			return (String(localized: "Incident"), true)
		}
		let year = String(calendar.component(.year, from: latest))
		return (String(localized: "Incident \(year)"), false)
	}
}

/// One milestone, as L2BEAT records it.
struct L2beatMilestone: Sendable, Equatable, Codable {
	/// The project's `id` — their repo directory name, which is what this joins on. Never
	/// the slug; see the two-identifier note on `L2beatProject`.
	let projectID: String
	let title: String
	/// Their own sentence. Frequently absent — measured, plenty of milestones are a title
	/// and a date alone.
	let summary: String?
	let kind: L2beatMilestoneKind
	let day: String
	let date: Date
	/// What L2BEAT cites. One URL, unlike Walletbeat's list — their schema carries a single
	/// `url` per milestone.
	let url: String?

	/// `l2beat:news:<projectID>:<day>:<slug>`.
	///
	/// The project and the DAY are both in the identity, so two chains announcing the same
	/// upgrade on the same day are two rows, and one chain's repeated annual event does not
	/// dedupe against its own history.
	var ref: String { "\(L2beatIdentity.newsPrefix)\(projectID):\(day):\(L2beatNewsParse.slug(title))" }
}

// MARK: - What a landed milestone's sheet needs

/// The facts a milestone's thing sheet draws, kept beside the row rather than inside it.
///
/// WHY A BOOK AND NOT `Thing` FIELDS, §419's reasoning unchanged: the kind, the citation and
/// the project it names are three more facts than a `.link` row can carry, and every one
/// would be a new stored property — a CloudKit Production deploy each (docs/
/// cloudkit-deploy.md) for data re-read from a public document.
struct L2beatMilestoneFacts: Codable, Sendable, Equatable {
	let projectID: String
	let projectName: String?
	let kind: L2beatMilestoneKind
	let day: String
	let url: String?
	let summary: String?
}

enum L2beatMilestoneBook {
	private static let key = "l2beat.milestones"

	/// L2BEAT has published 226 milestones across 105 chains in five years, so this is a
	/// generous ceiling rather than a real constraint — it exists so a repo that starts
	/// recording daily cannot grow an unbounded blob in UserDefaults.
	static let cap = 600

	static func all() -> [String: L2beatMilestoneFacts] {
		guard let data = UserDefaults.standard.data(forKey: key),
			let decoded = try? JSONDecoder().decode([String: L2beatMilestoneFacts].self, from: data)
		else { return [:] }
		return decoded
	}

	static func facts(_ slug: String) -> L2beatMilestoneFacts? { all()[slug] }

	/// Facts for a landed row, looked up by its `sourceRef`.
	static func facts(ref: String?) -> L2beatMilestoneFacts? {
		guard let ref, ref.hasPrefix(L2beatIdentity.newsPrefix) else { return nil }
		return facts(String(ref.dropFirst(L2beatIdentity.newsPrefix.count)))
	}

	static func record(_ milestone: L2beatMilestone, projectName: String?) {
		var map = all()
		let key = String(milestone.ref.dropFirst(L2beatIdentity.newsPrefix.count))
		map[key] = L2beatMilestoneFacts(
			projectID: milestone.projectID,
			projectName: projectName,
			kind: milestone.kind,
			day: milestone.day,
			url: milestone.url,
			summary: milestone.summary)
		if map.count > cap {
			// Oldest first, by the milestone's own DAY rather than by insertion — a
			// backfill lands out of order, so insertion order would drop the newest.
			for entry in map.sorted(by: { $0.value.day < $1.value.day }).prefix(map.count - cap) {
				map.removeValue(forKey: entry.key)
			}
		}
		replace(map)
	}

	static func replace(_ map: [String: L2beatMilestoneFacts]) {
		guard let data = try? JSONEncoder().encode(map) else { return }
		UserDefaults.standard.set(data, forKey: key)
	}

	/// Forget only the keys named — the demo teardown's rule, since a dev install may hold
	/// real milestones under this same key (prd §401).
	static func forgetDemo(_ keys: [String]) {
		var map = all()
		for key in keys { map.removeValue(forKey: key) }
		replace(map)
	}

	static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - Parsing

enum L2beatNewsParse {
	/// The tag an INCIDENT wears.
	///
	/// ONE constant, read by the landing that writes it AND the room head that matches it.
	/// §311 is what this prevents: a bridge stamped `privacypools:dep:` while the room head
	/// fetched `privacypools:deposit:`, so no state ever moved and the room went QUIET
	/// rather than breaking — indistinguishable from having nothing to report.
	static let incidentTag = "Incident"

	/// Read every milestone out of one project's config file.
	///
	/// The block is found by its own field name and then walked with a bracket counter, so a
	/// URL or a sentence containing a brace cannot end it early. A file with no `milestones:`
	/// array yields an empty list, which is the common case and not a failure.
	static func milestones(from text: String, projectID: String) -> [L2beatMilestone] {
		guard let block = arrayBlock(field: "milestones", in: text) else { return [] }
		var out: [L2beatMilestone] = []
		for entry in objects(in: block) {
			guard
				let title = string(field: "title", in: entry),
				let day = string(field: "date", in: entry).map(dayString),
				let date = self.date(fromISO: day)
			else { continue }
			let kindRaw = string(field: "type", in: entry)
			out.append(
				L2beatMilestone(
					projectID: projectID,
					title: title,
					summary: string(field: "description", in: entry),
					kind: kindRaw.flatMap(L2beatMilestoneKind.init(rawValue:)) ?? .general,
					day: day,
					date: date,
					url: string(field: "url", in: entry)
				)
			)
		}
		return out
	}

	/// `2026-05-24T00:00:00Z` → `2026-05-24`. Their dates are ISO-8601 with a midnight-UTC
	/// time that means nothing; only the day is real.
	static func dayString(_ raw: String) -> String {
		String(raw.prefix(10))
	}

	/// `2026-05-24` at UTC NOON.
	///
	/// Noon, not midnight, and this is not fussiness — §419's lesson, and it bites harder
	/// here because L2BEAT's own dates ARE midnight UTC. A midnight stamp lands on the
	/// PREVIOUS DAY for every reader west of Greenwich, so a milestone dated today would
	/// file itself under yesterday in the feed's day grouping across the Americas. Noon is
	/// the only hour that reads as the right day in every timezone the app ships to.
	static func date(fromISO day: String) -> Date? {
		let parts = day.split(separator: "-")
		guard parts.count == 3,
			let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
			(1...12).contains(m), (1...31).contains(d), y >= 2000, y <= 2100
		else { return nil }
		var components = DateComponents()
		components.year = y
		components.month = m
		components.day = d
		components.hour = 12
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
		return calendar.date(from: components)
	}

	/// A stable, readable identity for one milestone within its project and day.
	/// Lowercased words joined by hyphens, capped so a ref cannot grow without bound.
	static func slug(_ title: String) -> String {
		let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
		return words.prefix(8).joined(separator: "-")
	}

	// MARK: Readers

	/// Everything between `<field>: [` and its matching `]`.
	static func arrayBlock(field: String, in text: String) -> String? {
		guard let start = text.range(of: "\(field): [") else { return nil }
		var depth = 0
		var started = false
		var out = ""
		for character in text[start.lowerBound...] {
			if character == "[" { depth += 1; started = true }
			if started { out.append(character) }
			if character == "]" {
				depth -= 1
				if started, depth <= 0 { break }
			}
		}
		return out.isEmpty ? nil : out
	}

	/// Split a `[ { … }, { … } ]` block into its top-level objects.
	///
	/// BRACE-COUNTED, and quote-aware. A milestone description containing a brace is
	/// unlikely; a URL containing one is not, and a naive split on `},` puts half of one
	/// milestone into the next.
	static func objects(in block: String) -> [String] {
		var out: [String] = []
		var depth = 0
		var current = ""
		var quote: Character?
		var escaped = false
		for character in block {
			if let open = quote {
				current.append(character)
				if escaped { escaped = false; continue }
				if character == "\\" { escaped = true; continue }
				if character == open { quote = nil }
				continue
			}
			if character == "'" || character == "\"" {
				if depth > 0 { current.append(character) }
				quote = character
				continue
			}
			if character == "{" {
				depth += 1
				if depth == 1 { current = ""; continue }
			}
			if character == "}" {
				depth -= 1
				if depth == 0 { out.append(current); current = ""; continue }
			}
			if depth > 0 { current.append(character) }
		}
		return out
	}

	/// A quoted string for `<field>:` inside one object.
	///
	/// Anchored on the field name preceded by a boundary, so `url:` cannot be found inside
	/// `sourceUrl:` and `type:` cannot be found inside `subtype:`. §419 learned this the
	/// other way round — its unanchored search found a nested `label:` and reported one
	/// object's value as another's.
	static func string(field: String, in object: String) -> String? {
		var searchStart = object.startIndex
		while let range = object.range(of: "\(field):", range: searchStart..<object.endIndex) {
			searchStart = range.upperBound
			let before = range.lowerBound
			if before > object.startIndex {
				let prior = object[object.index(before: before)]
				// A letter, digit or underscore before the name means this is the tail of a
				// longer identifier, not our field.
				if prior.isLetter || prior.isNumber || prior == "_" { continue }
			}
			var rest = object[range.upperBound...]
			while let first = rest.first, first == " " || first == "\n" || first == "\t" {
				rest = rest.dropFirst()
			}
			guard let quote = rest.first, quote == "'" || quote == "\"" else { continue }
			rest = rest.dropFirst()
			var value = ""
			var escaped = false
			for character in rest {
				if escaped { value.append(character); escaped = false; continue }
				if character == "\\" { escaped = true; continue }
				if character == quote { return unwrap(value) }
				value.append(character)
			}
			return nil
		}
		return nil
	}

	/// L2BEAT's formatter hard-wraps prose inside its string literals, so a description
	/// arrives with newlines mid-sentence. They are the FORMATTER'S line breaks, not the
	/// writer's, so they collapse to spaces — unlike a journal note, where §399 keeps them.
	static func unwrap(_ raw: String) -> String {
		raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
