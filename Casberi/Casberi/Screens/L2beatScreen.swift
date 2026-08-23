import SwiftData
import SwiftUI

/// L2BEAT's connect screen (prd §428).
///
/// The search here is INSTANT AND OFFLINE — it runs over the bundled directory
/// (`L2beatDirectory`, regenerated at ship time by `scripts/l2beat-snapshot.py`), so naming
/// the chains you use needs no network at all. The live read then supersedes it.
struct L2beatScreen: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store

	@State private var queryField = ""
	@State private var watched: [Thing] = []
	@State private var syncing = false
	@State private var syncPending = false
	@State private var result: String?
	@State private var resultIsError = false
	@State private var flipTrigger = 0
	@State private var browsing = false
	@State private var opened: String?
	@FocusState private var fieldFocused: Bool

	/// Both tiers. Following alone is a real connected state — it reads the incidents L2BEAT
	/// has recorded, which is what their registry publishes about the ecosystem and which
	/// this bridge carries whole, filtered by nothing.
	@State private var following = L2beatWatch.following

	private var connected: Bool { following || !watched.isEmpty }

	var body: some View {
		List {
			BridgeSetupHeader(
				name: "L2BEAT",
				mode: .noAccount,
				intro: "Follow L2BEAT and the incidents they record across every chain arrive in your feed. Name the chains you use and each one's full risk assessment comes too — their judgments, never ours.",
				connected: connected,
				flipTrigger: flipTrigger)

			watchSection.listRowSeparator(.hidden)

			if connected {
				rosterSection
				ChipLiveNote(
					name: "L2BEAT",
					verb: watched.isEmpty
						? "for incidents across every chain."
						: "for incidents and your chains' assessments.")
					.listRowSeparator(.hidden)
				BridgeDisconnectSection(
					bridgeID: L2beatWatch.seatID,
					name: L2beatWatch.source,
					teardown: { L2beatWatch.removeAll(context: modelContext) }
				).listRowSeparator(.hidden)
			}
		}
		.listStyle(.insetGrouped)
		.scrollContentBackground(.hidden)
		.bridgeSetupWash(name: "L2BEAT")
		.dsAdaptiveContentWidth()
		.dsPageBackground()
		.dsSoftScrollEdges()
		.dsScreenTitle("L2BEAT")
		.navigationDestination(isPresented: $browsing) {
			L2beatDirectoryScreen()
		}
		.sheet(item: $opened) { chainID in
			L2beatCardScreen(chainID: chainID)
		}
		.onAppear {
			following = L2beatWatch.following
			load()
			// Opening the screen doesn't connect — the person taps a chain to watch it. Only
			// refresh if something is already on: viewing is not consent.
			if connected { Task { await sync() } }
		}
	}

	// MARK: - Sections

	private var watchSection: some View {
		Section {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				DSSlabField(
					placeholder: String(localized: "Chain name"),
					text: $queryField,
					actionLabel: String(localized: "Watch"),
					focus: $fieldFocused,
					action: watchTyped)

				ForEach(hits) { project in
					BridgeSearchResultRow(
						imageURL: nil,
						fallbackIcon: "L2BEAT",
						title: project.name,
						subtitle: subtitle(project),
						action: { watch(project) })
				}

				if queryField.trimmingCharacters(in: .whitespaces).count >= 2, hits.isEmpty {
					// L2BEAT covers 105 chains and there are far more in the world, so "no
					// match" is a common answer and must not read as an error.
					DSSlabNote(text: String(localized: "L2BEAT doesn't cover that one. It assesses \(L2beatDirectory.projects.count) chains so far."))
				}

				BridgeSyncStatusRows(
					syncing: syncing,
					syncingLine: String(localized: "Reading L2BEAT…"),
					result: result,
					resultIsError: resultIsError)

				Button(action: { DSHaptic.tap(); browsing = true }) {
					HStack(spacing: DS.Space.s2) {
						Text(String(localized: "Browse all \(L2beatDirectory.projects.count)"))
							.dsText(.subhead13).fontWeight(.semibold)
							.foregroundStyle(DS.tint)
						Spacer()
					}
				}
				.buttonStyle(.plain)

				if following {
					DSSlabNote(text: String(localized: "Incidents arrive on their own, for every chain L2BEAT covers."))
				} else {
					// The free tier, and the reason it has its own button: the incidents are
					// about the whole registry, so there is nothing to name before they can
					// arrive.
					DSSlabButton(title: String(localized: "Follow the incidents"), action: follow)
				}
			}
		}
		.dsSlabSection()
	}

	private var rosterSection: some View {
		AssetRosterShelf(note: rosterNote) {
			ForEach(watched.keyed) { row in
				if let thing = row.live { rosterSlot(thing) }
			}
			AssetRosterAddSlot { fieldFocused = true }
		}
		.listRowInsets(EdgeInsets())
		.listRowBackground(Color.clear)
		.listRowSeparator(.hidden)
	}

	@ViewBuilder
	private func rosterSlot(_ thing: Thing) -> some View {
		let chainID = L2beatWatch.chainID(from: thing)
		let project = chainID.flatMap { L2beatState.best($0) }
		// 56 matches `AssetRosterSlot.markSize`, spelled rather than read: that static lives
		// on a generic type whose parameter is being inferred from this very closure.
		AssetRosterSlot(label: project?.name ?? thing.title) {
			L2beatMark(name: project?.name ?? thing.title, chainID: chainID, size: 56)
		}
		.onTapGesture {
			DSHaptic.tap()
			opened = chainID
		}
		.onLongPressGesture {
			guard let chainID else { return }
			DSHaptic.tap()
			L2beatWatch.remove(chainID, context: modelContext)
			load()
			L2beatWatch.registerBridge(store: store, context: modelContext)
		}
	}

	private var rosterNote: String {
		String(localized: "Watching \(watched.count) · tap for its assessment, hold to stop watching")
	}

	// MARK: - Search

	/// Ranked by prefix first, then by containment, so typing "ba" offers Base before
	/// Abstract. Alphabetical inside each band, so the list never reshuffles between
	/// keystrokes over the same match set.
	private var hits: [L2beatProject] {
		let query = queryField.trimmingCharacters(in: .whitespaces).lowercased()
		guard query.count >= 2 else { return [] }
		let already = Set(watched.compactMap { L2beatWatch.chainID(from: $0) })
		let matches = L2beatState.directory().filter {
			!already.contains($0.id)
				&& ($0.name.lowercased().contains(query) || $0.id.contains(query)
					|| $0.slug.contains(query))
		}
		return matches.sorted { a, b in
			let ap = a.name.lowercased().hasPrefix(query)
			let bp = b.name.lowercased().hasPrefix(query)
			if ap != bp { return ap }
			return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
		}
		.prefix(6)
		.map { $0 }
	}

	/// What the search row says under a chain's name — L2BEAT's own stage and how many of the
	/// five they flag, which together are what decides whether watching it tells you anything.
	private func subtitle(_ project: L2beatProject) -> String {
		let stage = project.stage?.label ?? String(localized: "Not staged")
		return "\(stage) · \(L2beatCopy.stripShort(project.orderedRisks))"
	}

	// MARK: - Actions

	private func load() {
		watched = ((try? modelContext.fetch(FetchDescriptor<Thing>(
			predicate: #Predicate { $0.source == "L2BEAT" },
			sortBy: [SortDescriptor(\.title)]))) ?? [])
			.live
			.filter { L2beatWatch.isChainRef($0.sourceRef) }
	}

	private func follow() {
		DSHaptic.tap()
		let wasConnected = connected
		L2beatWatch.following = true
		following = true
		L2beatWatch.registerBridge(store: store, context: modelContext)
		if !wasConnected { flipTrigger += 1 }
		Task { await sync() }
	}

	private func watchTyped() {
		guard let first = hits.first else { return }
		watch(first)
	}

	private func watch(_ project: L2beatProject) {
		let wasEmpty = watched.isEmpty
		guard L2beatWatch.add(project, context: modelContext) != nil else { return }
		queryField = ""
		// `add` turns following on (watching implies following) — mirror it, or the screen
		// keeps offering a Follow button for a seat that is already following.
		following = L2beatWatch.following
		load()
		L2beatWatch.registerBridge(store: store, context: modelContext)
		if wasEmpty { flipTrigger += 1 }
		Task { await sync() }
	}

	private func sync() async {
		if syncing { syncPending = true; return }
		syncing = true
		defer { syncing = false }
		repeat {
			syncPending = false
			let added = await L2beatIngest.refresh(context: modelContext)
			load()
			following = L2beatWatch.following
			L2beatWatch.registerBridge(store: store, context: modelContext)
			// Not gated on the watch list: a follower with nothing watched has really just
			// read the registry and is owed the same result line.
			guard connected else { return }
			if let added {
				result = added > 0
					? String(localized: "\(added) new")
					: String(localized: "Up to date")
				resultIsError = false
			} else {
				result = String(localized: "Couldn't reach L2BEAT — check your connection.")
				resultIsError = true
			}
		} while syncPending
	}
}
