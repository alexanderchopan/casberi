import SwiftData
import SwiftUI

/// Every chain L2BEAT covers (prd §428).
///
/// THE SORT IS THE WHOLE DESIGN PROBLEM, and §419 solved it for Walletbeat by refusing every
/// order but the alphabet and coverage — because Walletbeat publishes no composite and
/// offering one would put our weighting behind their name. HERE THE ANSWER IS DIFFERENT, and
/// the difference is the point: L2BEAT publishes its own ladder, so "by stage" is THEIR order
/// presented, not ours computed. Nothing on this screen adds five sentiments together.
///
/// The third order, "most flagged", is a count of L2BEAT's own calls — the same category of
/// fact as §419's "most reviewed", and equally not a verdict: a chain with four flags is one
/// L2BEAT has more to say about, not one that is four times worse.
///
/// Measured 2026-08-21: 76 of 105 are Stage 0 and 19 are not on the ladder at all, which is
/// exactly why the default is alphabetical — a stage sort over a list that is three-quarters
/// one value mostly reshuffles ties. AND IT IS ALSO WHY THAT SORT GROUPS rather than merely
/// sorting: this screen's own header said the reshuffle was near-meaningless and then offered
/// it as a plain list anyway, so choosing it changed the order of 105 rows and told the reader
/// nothing. Banded, it says how many are on each rung and WHAT THE RUNG MEANS — a sentence
/// that until now could only be reached by opening a card, one chain at a time.
///
/// SEARCH LEADS THE PAGE (the §200 ruling, "make sure the search bar is at the top"). The
/// connect screen has had an instant offline search since this seat shipped while the
/// comparison table — the surface actually built for finding one chain among 105 — made you
/// scroll for it.
struct L2beatDirectoryScreen: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store

	enum Layer: String, CaseIterable, Identifiable {
		case layer2, layer3
		var id: String { rawValue }
		var label: String {
			switch self {
			case .layer2: return String(localized: "Layer 2")
			case .layer3: return String(localized: "Layer 3")
			}
		}
	}

	enum Order: String, CaseIterable, Identifiable {
		case name, stage, flagged
		var id: String { rawValue }
		var label: String {
			switch self {
			case .name: return String(localized: "A–Z")
			case .stage: return String(localized: "By stage")
			case .flagged: return String(localized: "Most flagged")
			}
		}
	}

	/// One run of rows under one heading.
	///
	/// DERIVED FROM `entries`, never sorted again: the bands are the consecutive runs of an
	/// already-ordered list, so a heading can never disagree with the order it heads.
	private struct Band: Identifiable {
		let id: String
		/// Nil for the ungrouped list and for search results — a band with no heading.
		let head: Head?
		let projects: [L2beatProject]

		struct Head {
			/// Nil covers BOTH "L2BEAT says Not applicable" and a rung word this build does
			/// not know: neither is a place on the ladder, both sort last already, and
			/// splitting them would put a heading over a band of one unrecognised string.
			let stage: L2beatStage?
			let count: Int
		}
	}

	@State private var layer: Layer = .layer2
	@State private var order: Order = .name
	@State private var query = ""
	@State private var watchedIDs: Set<String> = []
	/// The DAY of the newest incident L2BEAT has recorded on each chain.
	///
	/// This screen is where somebody chooses which chain to trust, and the risk strip says
	/// what L2BEAT thinks of the design while this says what has actually gone wrong. Landed
	/// rows only, so it marks what the person's own corpus can show — someone who has never
	/// synced sees no markers rather than a claim we cannot back.
	///
	/// A DATE and not a flag, which is the fix: the row used to mark any incident ever
	/// recorded with one word in the attention colour, so a 2021 exploit and last month's halt
	/// were the same red on the screen where the difference decides everything. See
	/// `L2beatIncidentAge`, which draws the line using the ROOM HEAD'S OWN window.
	@State private var incidentLatest: [String: Date] = [:]
	@State private var opened: String?
	@FocusState private var searchFocused: Bool

	var body: some View {
		// Computed ONCE per render and handed down: `bands` walks the whole directory and
		// sorts it, and both the list and the empty-state test need the answer.
		let bands = self.bands
		return List {
			Section {
				VStack(alignment: .leading, spacing: DS.Space.s3) {
					searchField

					Picker("", selection: $layer) {
						ForEach(Layer.allCases) { Text($0.label).tag($0) }
					}
					.pickerStyle(.segmented)

					// Hidden while searching, the §200 shape: an ordering is a statement about
					// a whole list, and three matches have no order worth choosing. Results
					// rank prefix-first instead, which is the only order a search wants.
					if !searching {
						HStack(spacing: DS.Space.s4) {
							ForEach(Order.allCases) { option in
								Button(action: { DSHaptic.tap(); order = option }) {
									Text(option.label)
										.dsText(.subhead13)
										.fontWeight(order == option ? .semibold : .regular)
										.foregroundStyle(order == option ? DS.textPrimary : DS.textTertiary)
								}
								.buttonStyle(.plain)
							}
							Spacer()
						}
					}
				}
			}
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)

			ForEach(bands) { band in
				if let head = band.head {
					bandHead(head)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				}
				ForEach(band.projects) { project in
					row(project)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				}
			}

			if searching, bands.allSatisfy({ $0.projects.isEmpty }) {
				emptySearchNote
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			}

			Section {
				Text(String(localized: "L2BEAT's assessment, not ours. The five cells are their own risk axes, always in their order — open a chain to see which question sits in which cell. A chain with nothing flagged is one they found nothing to flag, not one they call safe.\n\nBundled as of \(L2beatDirectory.generated); read live once connected."))
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.dsAdaptiveContentWidth()
		.dsPageBackground()
		.dsSoftScrollEdges()
		.dsScreenTitle("Every chain")
		.sheet(item: $opened) { chainID in
			L2beatCardScreen(chainID: chainID)
		}
		.onAppear(perform: load)
	}

	// MARK: - Search

	private var searchField: some View {
		HStack(spacing: DS.Space.s2) {
			Image(systemName: "magnifyingglass")
				.dsGlyph(15, weight: .medium)
				.foregroundStyle(DS.textTertiary)
			TextField(String(localized: "Search chains"), text: $query)
				.dsText(.body17).foregroundStyle(DS.textPrimary)
				.tint(DS.tint)
				.focused($searchFocused)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
			if !query.isEmpty {
				Button {
					query = ""
					DSHaptic.tap()
				} label: {
					Image(systemName: "xmark.circle.fill")
						.dsGlyph(15, weight: .regular)
						.foregroundStyle(DS.textTertiary)
						.dsTapTarget(Circle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel(Text("Clear search"))
			}
		}
		.padding(.horizontal, DS.Space.s4)
		.frame(height: DS.Radius.widget + 36)
		.background(DS.surfaceWell, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
	}

	private var trimmedQuery: String {
		query.trimmingCharacters(in: .whitespaces).lowercased()
	}

	private var searching: Bool { !trimmedQuery.isEmpty }

	/// A miss inside the chosen layer is not the same answer as a miss in the registry, and
	/// on a two-tab screen the difference is one tap away — so the note names it rather than
	/// leaving somebody to conclude L2BEAT doesn't cover their chain.
	@ViewBuilder
	private var emptySearchNote: some View {
		let other: Layer = layer == .layer3 ? .layer2 : .layer3
		let elsewhere = matches(in: other).count
		VStack(alignment: .leading, spacing: DS.Space.s1) {
			Text(elsewhere > 0
				? String(localized: "Nothing under \(layer.label).")
				: String(localized: "L2BEAT doesn't cover that one."))
				.dsText(.subhead13)
				.foregroundStyle(DS.textSecondary)
			if elsewhere > 0 {
				Text(elsewhere == 1
					? String(localized: "One match under \(other.label).")
					: String(localized: "\(elsewhere) matches under \(other.label)."))
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
			} else {
				Text(String(localized: "They assess \(L2beatDirectory.projects.count) chains so far."))
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
			}
		}
		.padding(.vertical, DS.Space.s3)
	}

	// MARK: - Rows

	@ViewBuilder
	private func bandHead(_ head: Band.Head) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s1) {
			HStack(spacing: DS.Space.s2) {
				L2beatStageChip(stage: head.stage)
				Text(head.count == 1
					? String(localized: "1 chain")
					: String(localized: "\(head.count) chains"))
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
				Spacer(minLength: 0)
			}
			// THE RUNG'S MEANING, not its number. "Stage 0" is jargon from a methodology most
			// readers have not read, and until this heading existed the sentence explaining it
			// lived only inside a card — one chain at a time, on a screen whose whole job is
			// comparing them.
			Text(head.stage?.meaning
				?? String(localized: "L2BEAT doesn't place these chains on its stage ladder."))
				.dsText(.subhead13)
				.foregroundStyle(DS.textSecondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.top, DS.Space.s3)
		.padding(.bottom, DS.Space.s1)
	}

	@ViewBuilder
	private func row(_ project: L2beatProject) -> some View {
		let watching = watchedIDs.contains(project.id)
		let incident = incidentLatest[project.id].map {
			L2beatIncidentAge.mark(latest: $0, withinDays: L2beatRoomSource.recencyDays)
		}
		HStack(alignment: .center, spacing: DS.Space.s3) {
			L2beatMark(name: project.name, chainID: project.id)
			VStack(alignment: .leading, spacing: 2) {
				Text(project.name)
					.dsText(.body17)
					.foregroundStyle(DS.textPrimary)
					.lineLimit(1)
				HStack(spacing: DS.Space.s2) {
					// FIRST, and in words. It outranks the strip because the strip describes
					// what L2BEAT thinks of the design and this describes what has happened —
					// and it carries its YEAR once it is outside the room head's own recency
					// window, because an event with no date is half an event.
					if let incident {
						Text(incident.text)
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(incident.recent ? DS.attention : DS.textTertiary)
					}
					if project.underReview {
						Text(String(localized: "Under review"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
					L2beatStageChip(stage: project.stage, compact: true)
					// WHICH question L2BEAT leads with — never the tally this line used to
					// carry, which said in words exactly what the strip says in colour two
					// inches away. Skipped under review, where the chip beside it already says
					// the same word and L2BEAT is telling you not to lean on the readings.
					if !project.underReview {
						Text(project.lead.shortLabel)
							.dsText(.label11)
							.foregroundStyle(DS.textTertiary)
							.lineLimit(1)
					}
				}
			}
			Spacer(minLength: DS.Space.s2)
			L2beatStrip(risks: project.orderedRisks)
				.frame(width: 62)
			// Watch is the verb on every row; a chain already watched says so instead of
			// offering a control that would do nothing.
			if watching {
				Text(String(localized: "Watching"))
					.dsText(.label11).fontWeight(.semibold)
					.foregroundStyle(DS.textTertiary)
					.frame(width: 58, alignment: .trailing)
			} else {
				Button(action: { watch(project) }) {
					Text(String(localized: "Watch"))
						.dsText(.label11).fontWeight(.bold)
						.foregroundStyle(DS.tint)
						.frame(width: 58, alignment: .trailing)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.vertical, DS.Space.s2)
		.contentShape(Rectangle())
		.onTapGesture { DSHaptic.tap(); opened = project.id }
		.dsTapCard()
	}

	// MARK: - What is shown

	/// The rows, banded.
	///
	/// Search and the two ungrouped orders are one headless band; "by stage" is the same
	/// ordered list cut into its consecutive runs. Cut from `entries` rather than regrouped
	/// from scratch, so a band's heading can never disagree with the order it sits in.
	private var bands: [Band] {
		let rows = entries
		guard !searching, order == .stage else {
			return [Band(id: "all", head: nil, projects: rows)]
		}
		var out: [Band] = []
		var run: [L2beatProject] = []
		// Doubly optional on purpose: the outer nil means "no run started yet", the inner one
		// means "this run is the chains L2BEAT does not place on the ladder". Collapsing them
		// would start the first band by comparing against a rung nobody has.
		var rung: Int?? = nil
		for project in rows {
			let here = project.stage?.rung
			if let rung, rung != here {
				out.append(band(run))
				run = []
			}
			rung = .some(here)
			run.append(project)
		}
		if !run.isEmpty { out.append(band(run)) }
		return out
	}

	private func band(_ run: [L2beatProject]) -> Band {
		// The band's own stage word comes from its FIRST member, so a run of unrecognised
		// stage strings is headed "Not staged" rather than by whichever string it holds.
		let stage = run.first?.stage?.rung != nil ? run.first?.stage : nil
		return Band(
			id: stage?.rawValue ?? "unstaged",
			head: Band.Head(stage: stage, count: run.count),
			projects: run)
	}

	private var entries: [L2beatProject] {
		let filtered = visible(layer)
		if searching { return rank(filtered) }
		switch order {
		case .name:
			return filtered.sorted { byName($0, $1) }
		case .stage:
			// Highest rung first, and a chain L2BEAT does not place on the ladder sorts LAST
			// rather than as a zero — "not staged" is not a worse Stage 0, and putting it
			// beneath the bottom rung would state a ranking L2BEAT declined to make. Ties
			// fall through to the name, so the order is total and never reshuffles.
			return filtered.sorted { a, b in
				let ar = a.stage?.rung, br = b.stage?.rung
				if ar != br {
					guard let ar else { return false }
					guard let br else { return true }
					return ar > br
				}
				return byName(a, b)
			}
		case .flagged:
			return filtered.sorted { a, b in
				if a.flagged != b.flagged { return a.flagged > b.flagged }
				return byName(a, b)
			}
		}
	}

	private func visible(_ layer: Layer) -> [L2beatProject] {
		L2beatState.directory().filter {
			!$0.archived && $0.layer == (layer == .layer3 ? .layer3 : .layer2)
		}
	}

	private func matches(in layer: Layer) -> [L2beatProject] {
		guard searching else { return [] }
		return rank(visible(layer))
	}

	/// Prefix first, then containment, alphabetical inside each band — the connect screen's
	/// own ranking, spelled the same way so typing "ba" offers Base before Abstract on both
	/// screens and neither reshuffles between keystrokes over one match set.
	private func rank(_ list: [L2beatProject]) -> [L2beatProject] {
		let needle = trimmedQuery
		guard !needle.isEmpty else { return list }
		return list
			.filter {
				$0.name.lowercased().contains(needle) || $0.id.contains(needle)
					|| $0.slug.contains(needle)
			}
			.sorted { a, b in
				let ap = a.name.lowercased().hasPrefix(needle)
				let bp = b.name.lowercased().hasPrefix(needle)
				if ap != bp { return ap }
				return byName(a, b)
			}
	}

	private func byName(_ a: L2beatProject, _ b: L2beatProject) -> Bool {
		a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
	}

	// MARK: - Data

	private func load() {
		watchedIDs = Set(L2beatWatch.watchedIDs(context: modelContext))
		// Newest incident per chain, by L2BEAT's own day string — lexical comparison is a real
		// date comparison for `YYYY-MM-DD` and needs no parse to find the max.
		var newest: [String: String] = [:]
		for facts in L2beatMilestoneBook.all().values where facts.kind.isIncident {
			if let seen = newest[facts.projectID], seen >= facts.day { continue }
			newest[facts.projectID] = facts.day
		}
		incidentLatest = newest.compactMapValues { L2beatNewsParse.date(fromISO: $0) }
	}

	private func watch(_ project: L2beatProject) {
		DSHaptic.tap()
		guard L2beatWatch.add(project, context: modelContext) != nil else { return }
		load()
		L2beatWatch.registerBridge(store: store, context: modelContext)
		Task { _ = await L2beatIngest.refresh(context: modelContext) }
	}
}
