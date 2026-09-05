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
	@State private var opened: String?
	@FocusState private var fieldFocused: Bool

	/// Both tiers. Following alone is a real connected state — it reads the incidents L2BEAT
	/// has recorded, which is what their registry publishes about the ecosystem and which
	/// this bridge carries whole, filtered by nothing.
	@State private var following = L2beatWatch.following

	private var connected: Bool { following || !watched.isEmpty }

	var body: some View {
		BridgeSetupPage(name: "L2BEAT") {
			BridgeSetupHeader(
				name: "L2BEAT",
				mode: .noAccount,
				intro: "Follow L2BEAT below, and name the chains you use — their incidents and full risk assessments arrive, their judgments, never ours.",
				connected: connected)

			if connected {
				RoomDoor(name: "L2BEAT", source: L2beatWatch.source)
					.listRowSeparator(.hidden)
			}

			// STATE FIRST, THEN THE ACTS. The registry tier is what this seat IS for
			// somebody who never names a chain, and it used to be the last thing on the
			// screen — a filled primary button below the field, the browse link and two
			// notes, which is §190's "a screen's one filled block, so it reads as THE
			// verb" with the verb buried.
			followSection.listRowSeparator(.hidden)

			// THE STANDING FACTS SIT TOGETHER, ABOVE THE ACTS — what arrives on its own,
			// then the chains you named — and the finder follows. The shelf used to sit
			// last, so its own add slot (a dashed circle whose whole job is to focus the
			// field) was stranded a screen below the field it focuses; the wallet manager
			// has read this way round since §182.
			//
			// GATED ON THE WATCH LIST, never on `connected` — the TokenWatch/Stocktwits
			// rule, which this screen and its Walletbeat twin both missed. Following is a
			// connected state with nothing named, so the shelf drew that lone dashed slot
			// under "Watching 0 · tap for its assessment, hold to stop watching" — gesture
			// copy for rows that do not exist, which is §83's dead control wearing prose.
			if !watched.isEmpty {
				rosterSection
			}

			watchSection.listRowSeparator(.hidden)

			if connected {
				BridgeDisconnectSection(
					bridgeID: L2beatWatch.seatID,
					name: L2beatWatch.source,
					teardown: { L2beatWatch.removeAll(context: modelContext) }
				).listRowSeparator(.hidden)
			}
		}
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
	private var followSection: some View {
		Section {
			if following {
				DSCheckList(lines: [
					"Following L2BEAT — their incidents arrive for every chain they cover."
				])
			} else {
				DSSlabButton(title: String(localized: "Follow the incidents"), action: follow)
			}
		}
		.dsSlabSection()
	}

	/// Naming a chain: type it, or walk the whole registry. ONE BLOCK, in that order.
	///
	/// What was here instead: the field, then the sync result splitting it from a bare blue
	/// "Browse all 105" — the one shape §190 names as what the slab replaced ("a headed
	/// section with a blue text link") — then two notes, with the shelf's own add slot
	/// stranded below all of it. The two ways to find a chain now sit together, and the read's
	/// result reports at the end of the block instead of cutting through the middle of it.
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
					// match" is a common answer and must not read as an error. It no longer
					// carries the count: the door directly beneath it states it, and saying it
					// twice two lines apart is the wordiness §315 exists to stop.
					DSSlabNote(text: String(localized: "L2BEAT doesn't cover that one."))
				}

				// A DOOR, in the shape every other push on this screen wears — and it states
				// what stands behind it (`DSSlabDoor`'s own rule), which is the fact somebody
				// deciding whether to walk it wants.
				DSSlabDoor(
					title: String(localized: "Browse every chain"),
					detail: "\(L2beatDirectory.projects.count)",
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
		.dsSlabSection()
	}

	private var rosterSection: some View {
		AssetRosterShelf(note: rosterNote, count: watched.count) {
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
