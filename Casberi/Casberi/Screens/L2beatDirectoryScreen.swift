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
/// one value mostly reshuffles ties.
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

	@State private var layer: Layer = .layer2
	@State private var order: Order = .name
	@State private var watchedIDs: Set<String> = []
	/// Chains L2BEAT has recorded an incident on.
	///
	/// This screen is where somebody chooses which chain to trust, and the risk strip says
	/// what L2BEAT thinks of the design while this says what has actually gone wrong. Landed
	/// rows only, so it marks what the person's own corpus can show — someone who has never
	/// synced sees no markers rather than a claim we cannot back.
	@State private var incidentChains: Set<String> = []
	@State private var opened: String?

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: DS.Space.s3) {
					Picker("", selection: $layer) {
						ForEach(Layer.allCases) { Text($0.label).tag($0) }
					}
					.pickerStyle(.segmented)

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
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)

			ForEach(entries) { project in
				row(project)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			}

			Section {
				Text(String(localized: "L2BEAT's assessment, not ours. The five cells are their own risk axes, in their order — a chain with nothing flagged is one they found nothing to flag, not one they call safe.\n\nBundled as of \(L2beatDirectory.generated); read live once connected."))
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

	@ViewBuilder
	private func row(_ project: L2beatProject) -> some View {
		let watching = watchedIDs.contains(project.id)
		HStack(alignment: .center, spacing: DS.Space.s3) {
			L2beatMark(name: project.name, chainID: project.id)
			VStack(alignment: .leading, spacing: 2) {
				Text(project.name)
					.dsText(.body17)
					.foregroundStyle(DS.textPrimary)
					.lineLimit(1)
				HStack(spacing: DS.Space.s2) {
					// FIRST, and in words. It outranks the strip because the strip describes
					// what L2BEAT thinks of the design and this describes what has happened.
					if incidentChains.contains(project.id) {
						Text(String(localized: "Incident"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
					if project.underReview {
						Text(String(localized: "Under review"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
					L2beatStageChip(stage: project.stage, compact: true)
					Text(L2beatCopy.stripShort(project.orderedRisks))
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.lineLimit(1)
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

	private var entries: [L2beatProject] {
		let filtered = L2beatState.directory().filter {
			!$0.archived && $0.layer == (layer == .layer3 ? .layer3 : .layer2)
		}
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

	private func byName(_ a: L2beatProject, _ b: L2beatProject) -> Bool {
		a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
	}

	private func load() {
		watchedIDs = Set(L2beatWatch.watchedIDs(context: modelContext))
		incidentChains = Set(
			L2beatMilestoneBook.all().values
				.filter { $0.kind.isIncident }
				.map(\.projectID))
	}

	private func watch(_ project: L2beatProject) {
		DSHaptic.tap()
		guard L2beatWatch.add(project, context: modelContext) != nil else { return }
		load()
		L2beatWatch.registerBridge(store: store, context: modelContext)
		Task { _ = await L2beatIngest.refresh(context: modelContext) }
	}
}
