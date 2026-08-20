import Foundation

// Walletbeat's wallet security news, parsed from their registry (prd §419).
//
// WHY WE PARSE TYPESCRIPT: Walletbeat publishes machine-readable JSON for RATINGS
// (`/<wallet>/index.json`) and nothing at all for INCIDENTS — the news pages are rendered
// HTML. The source of truth is `data/news/*.ts` in their repo, which is a flat object
// literal with no computed values, so it reads like JSON wearing different punctuation.
// This is the X-archive precedent (`window.YTD.tweets.part0 = [ … ]`): a structured file
// that is not JSON, parsed by field, every field failing safe to nil.
//
// EVERY FIELD IS OPTIONAL EXCEPT TITLE AND DATE. A registry that adds a field breaks
// nothing here, and one that renames a field we read loses that field rather than the row.

/// How Walletbeat classes an incident. Their vocabulary; an unknown value is kept as
/// `other` and still lands, because a new incident type is news whether or not we have a
/// word for it — dropping it would be a silent hole in a security feed.
enum WalletbeatNewsType: String, Codable, Sendable {
	case vulnerability = "VULNERABILITY"
	case dataBreach = "DATA_BREACH"
	case other = "OTHER"

	var label: String {
		switch self {
		case .vulnerability: return String(localized: "Vulnerability")
		case .dataBreach: return String(localized: "Data breach")
		case .other: return String(localized: "Incident")
		}
	}
}

/// Walletbeat's severity call. Ours is never computed — this is read, ranked, and quoted.
enum WalletbeatSeverity: String, Codable, Sendable, Comparable {
	case low = "LOW"
	case medium = "MEDIUM"
	case high = "HIGH"
	case critical = "CRITICAL"

	private var order: Int {
		switch self {
		case .low: return 0
		case .medium: return 1
		case .high: return 2
		case .critical: return 3
		}
	}

	static func < (a: WalletbeatSeverity, b: WalletbeatSeverity) -> Bool { a.order < b.order }

	/// Sentence case, and deliberately worded as Walletbeat's reading rather than a fact:
	/// every surface pairs this with "Walletbeat rates it …".
	var label: String {
		switch self {
		case .low: return String(localized: "low severity")
		case .medium: return String(localized: "medium severity")
		case .high: return String(localized: "high severity")
		case .critical: return String(localized: "critical severity")
		}
	}
}

/// Where an incident stands. `mitigated` is NOT `resolved` and the two are never folded:
/// a breach that has been contained still happened and your data is still out, which is
/// exactly the distinction someone reading a security feed is there for.
enum WalletbeatIncidentStatus: String, Codable, Sendable {
	case ongoing = "ONGOING"
	case mitigated = "MITIGATED"
	case resolved = "RESOLVED"
	case unknown = "UNKNOWN"

	var label: String {
		switch self {
		case .ongoing: return String(localized: "Ongoing")
		case .mitigated: return String(localized: "Mitigated")
		case .resolved: return String(localized: "Resolved")
		case .unknown: return String(localized: "Reported")
		}
	}

	/// Whether this still wants attention. Drives the row's state dot and nothing else —
	/// `unknown` counts as open, because not knowing an incident is closed is not the same
	/// as knowing it is, and the safer reading is the honest one here.
	var isOpen: Bool { self == .ongoing || self == .unknown }
}

/// One citation Walletbeat gives for an incident.
struct WalletbeatSource: Codable, Sendable, Equatable {
	let label: String
	let url: String
}

/// One incident, as Walletbeat records it.
struct WalletbeatIncident: Sendable, Equatable {
	let slug: String
	let title: String
	let summary: String
	let type: WalletbeatNewsType
	let severity: WalletbeatSeverity?
	let status: WalletbeatIncidentStatus
	let publishedAt: Date
	let updatedAt: Date?
	/// Walletbeat wallet ids this incident concerns. Legitimately EMPTY — measured
	/// 2026-08-20, the SafePal and Slope entries name no wallet because neither is a
	/// rated wallet, so an incident with no id is a real incident, never a parse failure.
	let wallets: [String]
	let fundsImpacted: Bool?
	let sources: [WalletbeatSource]

	var ref: String { "walletbeat:news:\(slug)" }
}

// MARK: - What a landed incident's sheet needs

/// The facts an incident's thing sheet draws, kept beside the row rather than inside it.
///
/// WHY A BOOK AND NOT `Thing` FIELDS: an incident's severity, status, funds flag and
/// citations are four more facts than a `.link` row can carry, and every one of them would
/// be a new stored property — which is a CloudKit Production deploy each (docs/
/// cloudkit-deploy.md) for data that is re-read from a public document every few hours.
/// The `X402State`/`ASCState` shape instead: a reading in UserDefaults, keyed by slug.
///
/// The first cut put the citations on `enrichedText`, which is retrieval-only by the
/// 2026-07-15 ruling — so the sheet could not draw them and the sources Walletbeat cites
/// were, structurally, on no screen at all.
struct WalletbeatIncidentFacts: Codable, Sendable, Equatable {
	let slug: String
	let type: WalletbeatNewsType
	let severity: WalletbeatSeverity?
	let status: WalletbeatIncidentStatus
	let fundsImpacted: Bool?
	let wallets: [String]
	let sources: [WalletbeatSource]
	let publishedAt: Date
	let updatedAt: Date?

	init(_ incident: WalletbeatIncident) {
		slug = incident.slug
		type = incident.type
		severity = incident.severity
		status = incident.status
		fundsImpacted = incident.fundsImpacted
		wallets = incident.wallets
		sources = incident.sources
		publishedAt = incident.publishedAt
		updatedAt = incident.updatedAt
	}
}

enum WalletbeatIncidentBook {
	private static let key = "walletbeat.incidents"

	/// Walletbeat has published about a dozen incidents in four years, so this is a
	/// generous ceiling rather than a real constraint — it exists so a registry that starts
	/// publishing daily cannot grow an unbounded blob in UserDefaults.
	static let cap = 200

	static func all() -> [String: WalletbeatIncidentFacts] {
		guard let data = UserDefaults.standard.data(forKey: key),
			let decoded = try? JSONDecoder().decode([String: WalletbeatIncidentFacts].self, from: data)
		else { return [:] }
		return decoded
	}

	static func facts(_ slug: String) -> WalletbeatIncidentFacts? { all()[slug] }

	/// Facts for a landed row, looked up by its `sourceRef`.
	static func facts(ref: String?) -> WalletbeatIncidentFacts? {
		guard let ref, ref.hasPrefix(WalletbeatNewsParse.refPrefix) else { return nil }
		return facts(String(ref.dropFirst(WalletbeatNewsParse.refPrefix.count)))
	}

	/// Record what was just read. Called on landing AND on heal, because an incident's
	/// status is the one fact here that moves after publication — a sheet still reading
	/// "ongoing" a week after the fix is the worst thing this feed could say.
	static func record(_ incident: WalletbeatIncident) {
		var map = all()
		map[incident.slug] = WalletbeatIncidentFacts(incident)
		if map.count > cap {
			// Oldest first, by the incident's own date rather than by insertion — a
			// backfill lands out of order, so insertion order would drop the newest.
			for entry in map.values.sorted(by: { $0.publishedAt < $1.publishedAt })
				.prefix(map.count - cap) {
				map.removeValue(forKey: entry.slug)
			}
		}
		replace(map)
	}

	static func replace(_ map: [String: WalletbeatIncidentFacts]) {
		guard let data = try? JSONEncoder().encode(map) else { return }
		UserDefaults.standard.set(data, forKey: key)
	}

	/// Forget only the slugs named — the demo teardown's rule, since a dev install may hold
	/// real incidents under this same key (prd §401).
	static func forgetDemo(_ slugs: [String]) {
		var map = all()
		for slug in slugs { map.removeValue(forKey: slug) }
		replace(map)
	}

	static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }
}

enum WalletbeatNewsParse {
	static let refPrefix = WalletbeatIdentity.newsPrefix

	/// The tag an unresolved incident wears.
	///
	/// ONE constant, read by the landing that writes it AND the room head that matches it.
	/// §311 is what this prevents: a bridge stamped `privacypools:dep:` while the room head
	/// fetched `privacypools:deposit:`, so no state ever moved and the room went QUIET
	/// rather than breaking — indistinguishable from having nothing to report.
	static let openTag = "Unresolved"

	/// Read one `data/news/<date>-<slug>.ts` entry.
	///
	/// Returns nil only when the two facts every row needs are missing — a title and a
	/// date. Everything else degrades: a missing severity means we do not state one, a
	/// missing status reads `unknown`, an unparsed `wallets` list means the incident lands
	/// without joining a watch.
	static func incident(from text: String, slugFallback: String? = nil) -> WalletbeatIncident? {
		guard
			let title = string(field: "title", in: text),
			let publishedRaw = string(field: "publishedAt", in: text),
			let published = day(publishedRaw)
		else { return nil }

		let slug = string(field: "slug", in: text) ?? slugFallback
		guard let slug, !slug.isEmpty else { return nil }

		let typeRaw = enumCase(field: "type", in: text)
		let severityRaw = enumCase(field: "severity", in: text)
		let statusRaw = enumCase(field: "status", in: text)

		return WalletbeatIncident(
			slug: slug,
			title: title,
			summary: string(field: "summary", in: text) ?? "",
			type: typeRaw.flatMap(WalletbeatNewsType.init(rawValue:)) ?? .other,
			// An unknown severity is nil, NEVER a default. Defaulting to `.low` would put
			// a reassuring word we invented next to Walletbeat's name; the surfaces are
			// built to say nothing when this is nil.
			severity: severityRaw.flatMap(WalletbeatSeverity.init(rawValue:)),
			status: statusRaw.flatMap(WalletbeatIncidentStatus.init(rawValue:)) ?? .unknown,
			publishedAt: published,
			updatedAt: string(field: "updatedAt", in: text).flatMap(day),
			wallets: stringArray(field: "wallets", in: text),
			fundsImpacted: bool(field: "fundsImpacted", in: text, nested: true),
			sources: sources(in: text)
		)
	}

	/// `2026-08-19` at UTC noon.
	///
	/// NOON, not midnight, and this is not fussiness: Walletbeat dates an entry by day with
	/// no time, and a midnight-UTC stamp lands on the PREVIOUS DAY for every reader west of
	/// Greenwich — so an incident published today would file itself under yesterday in the
	/// feed's day grouping for most of the Americas. Noon is the only hour that reads as
	/// the right day in every timezone the app ships to.
	static func day(_ raw: String) -> Date? {
		let parts = raw.split(separator: "-")
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

	// MARK: - Field readers

	/// Find `<field>:` at the literal's own indent level, then hand back everything after
	/// the colon up to the end of that value.
	///
	/// Anchored on a NEWLINE plus indentation on purpose. `title:` appears inside `ref`'s
	/// nested objects as `label:`, and `type:` appears inside `impact:` — an unanchored
	/// search finds a nested field and reports one object's value as another's.
	/// - Parameter nested: opt in to matching at ANY indentation, for a field that lives
	///   inside a child object. `fundsImpacted` is the only one — it sits in `impact: { … }`
	///   two tabs deep, so the strict anchors miss it entirely and it read as nil for every
	///   incident (caught against all four real entries before this shipped). It stays
	///   opt-in rather than becoming the default because the strict anchor is what keeps
	///   `title:` from matching a citation's `label:` block and `type:` from matching
	///   `impact.category` — loosening it globally trades a missing field for a wrong one.
	private static func valueRegion(field: String, in text: String, nested: Bool = false) -> Substring? {
		for indent in ["\n\t", "\n  ", "\n"] {
			let needle = "\(indent)\(field):"
			guard let range = text.range(of: needle) else { continue }
			return text[range.upperBound...]
		}
		guard nested else { return nil }
		// Any indentation, but still newline-anchored so `xfundsImpacted:` cannot match.
		guard let range = text.range(
			of: "\\n[ \\t]*\(NSRegularExpression.escapedPattern(for: field)):",
			options: .regularExpression
		) else { return nil }
		return text[range.upperBound...]
	}

	/// A quoted string, which may sit on the line BELOW its field name — Walletbeat's
	/// formatter wraps long summaries that way, and every incident summary is long.
	static func string(field: String, in text: String) -> String? {
		guard var rest = valueRegion(field: field, in: text) else { return nil }
		while let first = rest.first, first == " " || first == "\n" || first == "\t" {
			rest = rest.dropFirst()
		}
		guard let quote = rest.first, quote == "'" || quote == "\"" else { return nil }
		rest = rest.dropFirst()
		var out = ""
		var escaped = false
		for character in rest {
			if escaped {
				out.append(character)
				escaped = false
				continue
			}
			if character == "\\" { escaped = true; continue }
			if character == quote { return unwrap(out) }
			out.append(character)
		}
		return nil
	}

	/// Walletbeat hard-wraps prose inside its string literals, so a summary arrives with
	/// newlines mid-sentence. They are the FORMATTER'S line breaks, not the writer's, so
	/// they collapse to spaces — unlike a journal note, where §399 keeps them.
	private static func unwrap(_ raw: String) -> String {
		raw.replacingOccurrences(of: "\n", with: " ")
			.replacingOccurrences(of: "\t", with: " ")
			.split(separator: " ", omittingEmptySubsequences: true)
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// `severity: Severity.HIGH` → `HIGH`. The enum's own name is ignored: what matters is
	/// the member, and reading the type name would break the day they rename the enum.
	static func enumCase(field: String, in text: String) -> String? {
		guard var rest = valueRegion(field: field, in: text) else { return nil }
		while let first = rest.first, first == " " || first == "\t" { rest = rest.dropFirst() }
		var token = ""
		for character in rest {
			if character.isLetter || character.isNumber || character == "_" || character == "." {
				token.append(character)
			} else {
				break
			}
		}
		guard let member = token.split(separator: ".").last, !member.isEmpty else { return nil }
		// A bare identifier with no dot is not an enum member — reading it would turn
		// `status: someVariable` into a confident wrong status.
		guard token.contains(".") else { return nil }
		return String(member)
	}

	static func bool(field: String, in text: String, nested: Bool = false) -> Bool? {
		guard var rest = valueRegion(field: field, in: text, nested: nested) else { return nil }
		while let first = rest.first, first == " " || first == "\t" { rest = rest.dropFirst() }
		if rest.hasPrefix("true") { return true }
		if rest.hasPrefix("false") { return false }
		return nil
	}

	/// `wallets: ['rabby', 'trezor']` → `["rabby", "trezor"]`; `[]` → `[]`.
	static func stringArray(field: String, in text: String) -> [String] {
		guard var rest = valueRegion(field: field, in: text) else { return [] }
		while let first = rest.first, first == " " || first == "\n" || first == "\t" {
			rest = rest.dropFirst()
		}
		guard rest.first == "[" else { return [] }
		rest = rest.dropFirst()
		var out: [String] = []
		var current: String?
		var quote: Character?
		for character in rest {
			if let open = quote {
				if character == open {
					if let value = current, !value.isEmpty { out.append(value) }
					current = nil
					quote = nil
				} else {
					current?.append(character)
				}
				continue
			}
			if character == "'" || character == "\"" {
				quote = character
				current = ""
				continue
			}
			if character == "]" { break }
		}
		return out
	}

	/// Walletbeat's citations.
	///
	/// `ref` is EITHER an array of objects OR a single object — measured 2026-08-20, the
	/// BitBox entry writes `ref: {` while the other three write `ref: [`. Both are scanned
	/// the same way, by walking the balanced block after the field and pairing each
	/// `label`/`url` as it appears, so the shape simply does not matter.
	static func sources(in text: String) -> [WalletbeatSource] {
		guard let region = valueRegion(field: "ref", in: text) else { return [] }
		// Bound the scan at the block's own close so a later top-level field's URL cannot
		// be collected as a citation.
		var depth = 0
		var started = false
		var block = ""
		for character in region {
			if character == "[" || character == "{" { depth += 1; started = true }
			if started { block.append(character) }
			if character == "]" || character == "}" {
				depth -= 1
				if depth <= 0 && started { break }
			}
		}
		guard !block.isEmpty else { return [] }

		var out: [WalletbeatSource] = []
		var scan = Substring(block)
		while let urlRange = scan.range(of: "url:") {
			let head = scan[..<urlRange.lowerBound]
			let tail = scan[urlRange.upperBound...]
			guard let url = quoted(String(tail)) else { break }
			// The label is whichever `label:` most recently preceded this `url:`, so an
			// entry that omits one still pairs the rest correctly.
			let label = lastQuoted(after: "label:", in: String(head)) ?? ""
			if url.hasPrefix("http://") || url.hasPrefix("https://") {
				out.append(WalletbeatSource(label: label.isEmpty ? host(of: url) : label, url: url))
			}
			scan = tail
		}
		return out
	}

	private static func quoted(_ text: String) -> String? {
		var rest = Substring(text)
		while let first = rest.first, first == " " || first == "\n" || first == "\t" {
			rest = rest.dropFirst()
		}
		guard let quote = rest.first, quote == "'" || quote == "\"" else { return nil }
		rest = rest.dropFirst()
		var out = ""
		var escaped = false
		for character in rest {
			if escaped { out.append(character); escaped = false; continue }
			if character == "\\" { escaped = true; continue }
			if character == quote { return out }
			out.append(character)
		}
		return nil
	}

	private static func lastQuoted(after needle: String, in text: String) -> String? {
		guard let range = text.range(of: needle, options: .backwards) else { return nil }
		return quoted(String(text[range.upperBound...])).map(unwrap)
	}

	static func host(of url: String) -> String {
		URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
	}

	/// The slug carried by a filename like `2026-08-19-rabby-silent-signature-extraction.ts`.
	/// Used only as a fallback identity; the file's own `slug:` field wins when present.
	static func slug(fromFilename name: String) -> String? {
		var stem = name
		if stem.hasSuffix(".ts") { stem = String(stem.dropLast(3)) }
		let parts = stem.split(separator: "-")
		guard parts.count > 3, Int(parts[0]) != nil else { return stem.isEmpty ? nil : stem }
		return parts.dropFirst(3).joined(separator: "-")
	}
}
