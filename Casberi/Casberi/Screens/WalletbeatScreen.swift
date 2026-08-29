import SwiftData
import SwiftUI

/// Walletbeat's connect screen (prd §419).
///
/// The search here is INSTANT AND OFFLINE — it runs over the bundled directory
/// (`WalletbeatDirectory`, regenerated at ship time by `scripts/walletbeat-snapshot.py`),
/// so naming your wallets needs no network at all. Only the full report card and the
/// incidents are read live.
///
/// THE SHAPE (2026-08-29). This screen and `L2beatScreen` are the same page, and the L2BEAT
/// one was reported as *"totally messy like it was just thrown together with the thing to
/// watch at the bottom"*. All five defects were here line for line, so the same pass lands
/// here: the two tiers — incidents everywhere, and the full review for wallets you name —
/// were interleaved rather than stated. Four blocks now, each one act, top to bottom:
///
///   1. who Walletbeat are and how this connects (`BridgeSetupHeader`),
///   2. the way back to what landed (`RoomDoor`),
///   3. THE STANDING FACTS — the registry tier's one slot, then the wallets you watch,
///   4. THE ACT — the wallets this device already connected with, then name one or walk all
///      of them, then what the last read said.
///
/// Nothing here draws over nothing: every block below the header is gated on the state it
/// describes, which is what the shelf was missing.
struct WalletbeatScreen: View {
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

	/// Both tiers (prd §421). Following alone is a real connected state — it reads
	/// Walletbeat's incidents, which is what their registry publishes about the ecosystem
	/// and which this bridge fetches WHOLE, filtered by nothing.
	@State private var following = WalletbeatWatch.following
	/// Wallet apps this device has really connected with over WalletConnect, that
	/// Walletbeat rates and nothing here watches yet (prd §430).
	@State private var suggested: [WalletbeatEntry] = []

	private var connected: Bool { following || !watched.isEmpty }

	var body: some View {
		List {
			BridgeSetupHeader(
				name: "Walletbeat",
				mode: .noAccount,
				intro: "Follow Walletbeat and the wallet security incidents they publish arrive in your feed. Name the wallet apps you use and each one's full review comes too — their judgments, never ours.",
				connected: connected,
				flipTrigger: flipTrigger)

			if connected {
				RoomDoor(name: "Walletbeat", source: WalletbeatWatch.source)
					.listRowSeparator(.hidden)
			}

			// STATE FIRST, THEN THE ACTS. The registry tier is what this seat IS for somebody
			// who never names a wallet, and it used to be the last thing on the screen — a
			// filled primary button below the field, the browse link and two notes, which is
			// §190's "a screen's one filled block, so it reads as THE verb" with the verb
			// buried.
			followSection.listRowSeparator(.hidden)

			// THE STANDING FACTS SIT TOGETHER, ABOVE THE ACTS — what arrives on its own, then
			// the wallets you named — and the finder follows. The shelf used to sit last, so its
			// own add slot (a dashed circle whose whole job is to focus the field) was stranded a
			// screen below the field it focuses; the wallet manager has read this way since §182.
			//
			// GATED ON THE WATCH LIST, never on `connected` — the TokenWatch/Stocktwits rule.
			// Following is a connected state with nothing named, so the shelf drew that lone
			// dashed slot under "Watching 0 · tap for its review, hold to stop watching" —
			// gesture copy for rows that do not exist, which is §83's dead control wearing prose.
			if !watched.isEmpty {
				rosterSection
			}

			watchSection.listRowSeparator(.hidden)

			if connected {
				BridgeDisconnectSection(
					bridgeID: WalletbeatWatch.seatID,
					name: WalletbeatWatch.source,
					teardown: { WalletbeatWatch.removeAll(context: modelContext) }
				).listRowSeparator(.hidden)
			}
		}
		.listStyle(.insetGrouped)
		.scrollContentBackground(.hidden)
		.bridgeSetupWash(name: "Walletbeat")
		.dsAdaptiveContentWidth()
		.dsPageBackground()
		.dsSoftScrollEdges()
		.dsScreenTitle("Walletbeat")
		.navigationDestination(isPresented: $browsing) {
			WalletbeatDirectoryScreen()
		}
		.sheet(item: $opened) { walletID in
			WalletbeatCardScreen(walletID: walletID)
		}
		.onAppear {
			following = WalletbeatWatch.following
			load()
			// Opening the screen doesn't connect — the person taps a wallet to watch it.
			// Only refresh if something is already watched: viewing is not consent.
			if connected { Task { await sync() } }
		}
	}

	// MARK: - Sections

	/// The registry tier — ONE SLOT, TWO STATES.
	///
	/// Following costs nothing and needs nothing named, so it is the screen's primary verb
	/// until it is done. Before this it was the LAST control on the page and then, once on, it
	/// became a centered gray sentence floating between the finder and the shelf — a filled
	/// slab and a centered note are two shapes and two alignments for one fact.
	///
	/// The on state is a `DSCheckList` and not a `DSSlabNote`: following is a capability that
	/// has been GRANTED, which is exactly the claim that component's checkmark makes — so the
	/// line leads with the STATE and only then says what it brings. Worded the other way round
	/// ("incidents arrive on their own…") it would be a list of what ARRIVES, which that
	/// component's own doc reserves the neutral bullet for. It also leaves the screen's one
	/// gray sentence for the search's own no-match answer.
	private var followSection: some View {
		Section {
			if following {
				DSCheckList(lines: [
					"Following Walletbeat — their security incidents arrive for every wallet they cover."
				])
			} else {
				// The free tier, and the reason it has its own verb: the incidents are about the
				// whole registry, so there is nothing to name before they can arrive. Before §421
				// they were gated behind watching a wallet — not a decision anyone took, just the
				// watch list doubling as the connect act.
				DSSlabButton(title: String(localized: "Follow the security news"), action: follow)
			}
		}
		.dsSlabSection()
	}

	/// Naming a wallet: the ones this device already connected with, then type it, then walk
	/// the whole registry. ONE BLOCK, in that order.
	///
	/// What was here instead: the field, then the sync result splitting it from a bare blue
	/// "Browse all 32" — the one shape §190 names as what the slab replaced ("a headed section
	/// with a blue text link") — then two notes, with the shelf's own add slot stranded below
	/// all of it. The three ways to find a wallet now sit together, and the read's result
	/// reports at the end of the block instead of cutting through the middle of it.
	private var watchSection: some View {
		Section {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				// ABOVE the field, because it is the answer to the question the field asks.
				// §419's naming step is a search over the registry, and for anybody who has ever
				// connected a wallet the app already knew which one — the handshake's peer
				// metadata names it (prd §430).
				suggestionRows

				DSSlabField(
					placeholder: String(localized: "Wallet name"),
					text: $queryField,
					actionLabel: String(localized: "Watch"),
					focus: $fieldFocused,
					action: watchTyped)

				ForEach(hits) { entry in
					BridgeSearchResultRow(
						imageURL: nil,
						fallbackIcon: "Walletbeat",
						title: entry.name,
						subtitle: subtitle(entry),
						action: { watch(entry) })
				}

				if queryField.trimmingCharacters(in: .whitespaces).count >= 2, hits.isEmpty {
					// Walletbeat rates a few dozen wallets and there are hundreds in the world, so
					// "no match" is the COMMON answer and must not read as an error. It no longer
					// carries the count: the door directly beneath it states it, and saying it twice
					// two lines apart is the wordiness §315 exists to stop.
					DSSlabNote(text: String(localized: "Walletbeat doesn't rate that one."))
				}

				// A DOOR, in the shape every other push on this screen wears — and it states what
				// stands behind it (`DSSlabDoor`'s own rule), read off the directory rather than
				// typed, so a snapshot that rates one more wallet cannot leave the label behind.
				DSSlabDoor(
					title: String(localized: "Browse every wallet"),
					detail: "\(WalletbeatDirectory.wallets.count)",
					action: { browsing = true })

				// LAST in the block, not between the field and the door: this reports on the READ,
				// which nobody on this screen asked for, so an unreachable host must not cut the
				// finder in half — which is how a connection error came to read as the browse link
				// being broken.
				BridgeSyncStatusRows(
					syncing: syncing,
					syncingLine: String(localized: "Reading Walletbeat…"),
					result: result,
					resultIsError: resultIsError)
			}
		}
		.dsSlabSection()
	}

	/// The offer, and its GROUNDS in the same breath.
	///
	/// A bare list of wallet names here would be a recommendation — a claim about which
	/// wallets are worth watching, which is the one claim this whole feature refuses to
	/// make (§419). Saying where the names came from turns it into what it actually is: a
	/// record of what this person already did, handed back so they need not retype it.
	///
	/// A plain header rather than a `DSSlabNote`: the sentence is a heading for the rows
	/// under it rather than fine print, and the screen's one §315 gray sentence is spent on
	/// the search's no-match answer.
	@ViewBuilder
	private var suggestionRows: some View {
		if !suggested.isEmpty {
			Text(WalletbeatCopy.connectedOffer(suggested.count))
				.dsText(.label12).fontWeight(.semibold)
				.foregroundStyle(DS.textSecondary)
			ForEach(suggested) { entry in
				Button(action: { watch(entry) }) {
					HStack(spacing: DS.Space.s3) {
						WalletbeatMark(name: entry.name, walletID: entry.id)
						VStack(alignment: .leading, spacing: 0) {
							Text(entry.name).dsText(.body17)
								.foregroundStyle(DS.textPrimary).lineLimit(1)
							Text(subtitle(entry)).dsText(.subhead13)
								.foregroundStyle(DS.textTertiary).lineLimit(1)
						}
						Spacer()
						// The DIRECTORY's word for this act, in its sentence case, not
						// the field's uppercase `actionLabel` above: this is a card row
						// offering the same verb the directory's rows offer, and one act
						// spelled two ways across two screens is the drift `WalletbeatCopy`
						// exists to stop.
						Text(String(localized: "Watch"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.tint)
					}
				}
				.buttonStyle(.plain)
				.dsListCardRow()
			}
		}
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
		let walletID = WalletbeatWatch.walletID(from: thing)
		let card = walletID.flatMap { WalletbeatState.card($0) }
		// 56 matches `AssetRosterSlot.markSize`, spelled rather than read: that static
		// lives on a generic type whose parameter is being inferred from this very
		// closure, so referring to it here is unresolvable. `MetricDisc` carries the
		// same number as its own default for the same reason.
		AssetRosterSlot(label: card?.name ?? thing.title) {
			WalletbeatMark(name: card?.name ?? thing.title, walletID: walletID, size: 56)
		}
		.onTapGesture {
			DSHaptic.tap()
			opened = walletID
		}
		.onLongPressGesture {
			guard let walletID else { return }
			DSHaptic.tap()
			WalletbeatWatch.remove(walletID, context: modelContext)
			load()
			WalletbeatWatch.registerBridge(store: store, context: modelContext)
		}
	}

	private var rosterNote: String {
		String(localized: "Watching \(watched.count) · tap for its review, hold to stop watching")
	}

	// MARK: - Search

	/// Ranked by prefix first, then by containment, so typing "le" offers Ledger before
	/// Keycard Shell. Alphabetical inside each band, so the list never reshuffles between
	/// keystrokes over the same match set.
	private var hits: [WalletbeatEntry] {
		let query = queryField.trimmingCharacters(in: .whitespaces).lowercased()
		guard query.count >= 2 else { return [] }
		let already = Set(watched.compactMap { WalletbeatWatch.walletID(from: $0) })
		let matches = WalletbeatDirectory.wallets.filter {
			!already.contains($0.id)
				&& ($0.name.lowercased().contains(query) || $0.id.contains(query))
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

	/// What the search row says under a wallet's name — how much Walletbeat has actually
	/// examined, which is the fact that decides whether watching it will tell you anything.
	private func subtitle(_ entry: WalletbeatEntry) -> String {
		let kind = entry.hardware
			? String(localized: "Hardware")
			: String(localized: "Software")
		let counts = entry.overall
		guard counts.judged > 0 else {
			return String(localized: "\(kind) · not rated yet")
		}
		return "\(kind) · \(WalletbeatCopy.coverage(counts))"
	}

	// MARK: - Actions

	private func load() {
		watched = ((try? modelContext.fetch(FetchDescriptor<Thing>(
			predicate: #Predicate { $0.source == "Walletbeat" },
			sortBy: [SortDescriptor(\.title)]))) ?? [])
			.live
			.filter { WalletbeatWatch.isWatchRef($0.sourceRef) }
		// Recomputed with the watch list, so watching a suggestion removes it from the
		// offer in the same pass rather than leaving a row whose button now does nothing.
		suggested = WalletbeatWatch.connectedSuggestions(context: modelContext)
	}

	private func follow() {
		DSHaptic.tap()
		let wasConnected = connected
		WalletbeatWatch.following = true
		following = true
		WalletbeatWatch.registerBridge(store: store, context: modelContext)
		if !wasConnected { flipTrigger += 1 }
		Task { await sync() }
	}

	private func watchTyped() {
		guard let first = hits.first else { return }
		watch(first)
	}

	private func watch(_ entry: WalletbeatEntry) {
		let wasEmpty = watched.isEmpty
		guard WalletbeatWatch.add(entry, context: modelContext) != nil else { return }
		queryField = ""
		// `add` turns following on (watching implies following) — mirror it, or the
		// screen keeps offering a Follow button for a seat that is already following.
		following = WalletbeatWatch.following
		load()
		WalletbeatWatch.registerBridge(store: store, context: modelContext)
		if wasEmpty { flipTrigger += 1 }
		Task { await sync() }
	}

	private func sync() async {
		if syncing { syncPending = true; return }
		syncing = true
		defer { syncing = false }
		repeat {
			syncPending = false
			let added = await WalletbeatIngest.refresh(context: modelContext)
			load()
			following = WalletbeatWatch.following
			WalletbeatWatch.registerBridge(store: store, context: modelContext)
			// Not gated on the watch list any more: a follower with nothing watched has
			// really just read the registry and is owed the same result line.
			guard connected else { return }
			if let added {
				result = added > 0
					? String(localized: "\(added) new")
					: String(localized: "Up to date")
				resultIsError = false
			} else {
				result = String(localized: "Couldn't reach Walletbeat — check your connection.")
				resultIsError = true
			}
		} while syncPending
	}
}

// `String: Identifiable` already exists in `AppsScreen.swift`, which is what makes
// `.sheet(item: $opened)` work here. Deliberately not re-declared — a second retroactive
// conformance is a redeclaration error, and one is already one more than ideal.
