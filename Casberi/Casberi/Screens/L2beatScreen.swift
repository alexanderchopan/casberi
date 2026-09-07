import SwiftData
import SwiftUI

/// L2BEAT's connect screen (prd §428).
///
/// The search here is INSTANT AND OFFLINE — it runs over the bundled directory
/// (`L2beatDirectory`, regenerated at ship time by `scripts/l2beat-snapshot.py`), so naming
/// the chains you use needs no network at all. The live read then supersedes it.
///
/// THE SHAPE (2026-08-29, reported as *"it looks totally messy like it was just thrown
/// together with the thing to watch at the bottom"*). The two tiers this seat has — incidents
/// everywhere, and the full assessment for chains you name — were interleaved rather than
/// stated: the free tier's own verb was the LAST control on the page, the browse door was a
/// bare blue text link between a sync error and a centered gray note, and the watch shelf
/// drew below all of it, wearing its add slot a screen away from the field that slot exists
/// to focus. Four blocks now, each one act, top to bottom:
///
///   1. who L2BEAT are and how this connects (`BridgeSetupHeader`),
///   2. the way back to what landed (`RoomDoor`),
///   3. THE STANDING FACTS — the registry tier's one slot, then the chains you watch,
///   4. THE ACT — name a chain, or walk all 105, then what the last read said.
///
/// Nothing here draws over nothing: every block below the header is gated on the state it
/// describes, which is what the shelf was missing.
struct L2beatScreen: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store

	@State private var queryField = ""
	@State private var watched: [Thing] = []
	@State private var syncing = false
	@State private var syncPending = false
	@State private var result: BridgeProof?
	@State private var browsing = false
	@FocusState private var fieldFocused: Bool

	/// Both tiers. Following alone is a real connected state — it reads the incidents L2BEAT
	/// has recorded, which is what their registry publishes about the ecosystem and which
	/// this bridge carries whole, filtered by nothing.
	@State private var following = L2beatWatch.following

	private var connected: Bool { following || !watched.isEmpty }

	/// The page's one presentation (`AccountPage.sheet`).
	@State private var sheet: AccountPageSheet?

	var body: some View {
		AccountPage(
			name: "L2BEAT", seatID: L2beatWatch.seatID, source: L2beatWatch.source,
			state: AccountPageState.of(name: "L2BEAT", seatID: L2beatWatch.seatID,
									   connected: connected, store: store),
			intro: "Incidents and full risk assessments for the chains you name — their judgments, never ours.",
			mode: .noAccount,
			// THE SHELF IS THE CHASSIS'S ROSTER NOW, and the defect it was
			// rebuilt for goes with it: the shelf drew its lone dashed add slot
			// under "Watching 0 · tap for its assessment, hold to stop watching" —
			// gesture copy for rows that do not exist, §83's dead control wearing
			// prose. A roster with no rows draws no label at all, and the gestures
			// are the chassis's rather than a caption's.
			rows: rows,
			query: queryField,
			onRemoveRow: unwatch,
			onOpenRow: { sheet = .card(id: $0) },
			cardSheet: { id in AnyView(L2beatCardScreen(chainID: id)) },
			teardown: { L2beatWatch.removeAll(context: modelContext) },
			sheet: $sheet,
			act: {
				// STATE FIRST, THEN THE ACTS. The registry tier is what this seat
				// IS for somebody who never names a chain, and it used to be the
				// last thing on the screen — a filled primary button below the
				// field, the browse link and two notes, which is §190's "a screen's
				// one filled block, so it reads as THE verb" with the verb buried.
				followBlock
				watchBlock
			},
			more: { EmptyView() },
			keySheet: { EmptyView() }
		)
		.navigationDestination(isPresented: $browsing) {
			L2beatDirectoryScreen()
		}
		.onAppear {
			following = L2beatWatch.following
			load()
			// Opening the page doesn't connect — the person taps to watch. Only
			// refresh if something is already on: viewing is not consent.
			if connected { Task { await sync() } }
		}
	}

	// MARK: - The roster

	/// One row per watched entry, saying where it stands — their judgment,
	/// never ours. A tap opens the full card; the shelf's hold-to-unwatch is the
	/// chassis's Remove, with the Mac mirror it never had.
	private var rows: [AccountPageShape.Row] {
		watched.filter(\.isLive).compactMap { thing in
			guard let id = L2beatWatch.chainID(from: thing) else { return nil }
			return AccountPageShape.Row(
				id: id, title: L2beatState.best(id)?.name ?? thing.title,
				subline: rowSubline(id),
				weekCount: 0, hasNew: false, isYou: false, avatarURL: nil)
		}
	}

	private func unwatch(_ id: String) {
		L2beatWatch.remove(id, context: modelContext)
		load()
		L2beatWatch.registerBridge(store: store, context: modelContext)
	}


	// MARK: - Sections

	/// The registry tier — ONE SLOT, TWO STATES.
	///
	/// Following costs nothing and needs nothing named, so it is the screen's primary verb
	/// until it is done. Before this it was the LAST control on the page and then, once on,
	/// it became a centered gray sentence floating between the finder and the shelf — a
	/// filled slab and a centered note are two shapes and two alignments for one fact, which
	/// is most of what made this page read as thrown together.
	///
	/// The on state is a `DSCheckList` and not a `DSSlabNote`: following is a capability that
	/// has been GRANTED, which is exactly the claim that component's checkmark makes — so the
	/// line leads with the STATE and only then says what it brings. Worded the other way round
	/// ("incidents arrive on their own…") it would be a list of what ARRIVES, which that
	/// component's own doc reserves the neutral bullet for, after Stripe's setup screen put a
	/// granted scope and a kind of news under one checkmark and made them read as one list.
	/// It also leaves the screen's one gray sentence for the search's own no-match answer.
	@ViewBuilder private var followBlock: some View {
		if following {
			DSCheckList(lines: [
				"Following L2BEAT — incidents for every chain"
			])
		} else {
			DSSlabButton(title: String(localized: "Follow the incidents"),
						 systemImage: "eye", action: follow)
		}
	}

	/// Naming a chain: type it, or walk the whole registry. ONE BLOCK, in that order.
	///
	/// What was here instead: the field, then the sync result splitting it from a bare blue
	/// "Browse all 105" — the one shape §190 names as what the slab replaced ("a headed
	/// section with a blue text link") — then two notes, with the shelf's own add slot
	/// stranded below all of it. The two ways to find a chain now sit together, and the read's
	/// result reports at the end of the block instead of cutting through the middle of it.
	@ViewBuilder private var watchBlock: some View {
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
				// match" is a common answer and must not read as an error. It no longer
				// carries the count: the door directly beneath it states it, and saying it
				// twice two lines apart is the wordiness §315 exists to stop.
				DSSlabNote(text: String(localized: "L2BEAT doesn't cover that one."), plain: true)
			}

			// A DOOR, in the shape every other push on this screen wears — and it states
			// what stands behind it (`DSSlabDoor`'s own rule), which is the fact somebody
			// deciding whether to walk it wants.
			DSSlabDoor(
				title: String(localized: "Browse every chain"),
				detail: "\(L2beatDirectory.projects.count)",
				systemImage: "square.grid.2x2",
				action: { browsing = true })

			// LAST in the block, not between the field and the door: this reports on the
			// READ, which nobody on this screen asked for, so an unreachable host must not
			// cut the finder in half — which is how a connection error came to read as the
			// browse link being broken.
			BridgeSyncStatusRows(
				syncing: syncing,
				syncingLine: String(localized: "Reading L2BEAT…"),
				proof: result)
		}
	}

	/// What a watched chain's row says — L2BEAT's own stage and how many of the
	/// five risks they flag, which together are what makes watching it worth
	/// anything. Their judgment, never ours; silent where they have not staged
	/// it, rather than inventing a verdict.
	private func rowSubline(_ id: String) -> String {
		guard let project = L2beatState.best(id) else {
			return String(localized: "Reading L2BEAT…")
		}
		return subtitle(project)
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
		L2beatWatch.following = true
		following = true
		L2beatWatch.registerBridge(store: store, context: modelContext)
		Task { await sync() }
	}

	private func watchTyped() {
		guard let first = hits.first else { return }
		watch(first)
	}

	private func watch(_ project: L2beatProject) {
		guard L2beatWatch.add(project, context: modelContext) != nil else { return }
		queryField = ""
		// `add` turns following on (watching implies following) — mirror it, or the screen
		// keeps offering a Follow button for a seat that is already following.
		following = L2beatWatch.following
		load()
		L2beatWatch.registerBridge(store: store, context: modelContext)
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
				result = added > 0 ? .landed(added) : .upToDate
			} else {
				result = .failed(String(localized: "Couldn't reach L2BEAT — check your connection."))
			}
		} while syncPending
	}
}
