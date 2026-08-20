import SwiftData
import SwiftUI

/// Walletbeat's connect screen (prd §419).
///
/// The search here is INSTANT AND OFFLINE — it runs over the bundled directory
/// (`WalletbeatDirectory`, regenerated at ship time by `scripts/walletbeat-snapshot.py`),
/// so naming your wallets needs no network at all. Only the full report card and the
/// incidents are read live.
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

	private var connected: Bool { !watched.isEmpty }

	var body: some View {
		List {
			BridgeSetupHeader(
				name: "Walletbeat",
				mode: .noAccount,
				intro: "Name the wallet apps you use and Walletbeat's review of each arrives — where your keys are made, who sees your addresses, who has audited the code. Their judgments, never ours.",
				connected: connected,
				flipTrigger: flipTrigger)

			watchSection.listRowSeparator(.hidden)

			if connected {
				rosterSection
				ChipLiveNote(name: "Walletbeat", verb: "for your wallets' reviews.")
					.listRowSeparator(.hidden)
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
			load()
			// Opening the screen doesn't connect — the person taps a wallet to watch it.
			// Only refresh if something is already watched: viewing is not consent.
			if connected { Task { await sync() } }
		}
	}

	// MARK: - Sections

	private var watchSection: some View {
		Section {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				DSSlabField(
					placeholder: String(localized: "Wallet name"),
					text: $queryField,
					actionLabel: String(localized: "WATCH"),
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
					// Walletbeat rates 32 wallets and there are hundreds in the world, so
					// "no match" is the COMMON answer and must not read as an error.
					DSSlabNote(text: String(localized: "Walletbeat doesn't rate that one. It reviews 32 wallets so far."))
				}

				BridgeSyncStatusRows(
					syncing: syncing,
					syncingLine: String(localized: "Reading Walletbeat…"),
					result: result,
					resultIsError: resultIsError)

				Button(action: { DSHaptic.tap(); browsing = true }) {
					HStack(spacing: DS.Space.s2) {
						Text(String(localized: "Browse all 32"))
							.dsText(.subhead13).fontWeight(.semibold)
							.foregroundStyle(DS.tint)
						Spacer()
					}
				}
				.buttonStyle(.plain)

				DSSlabNote(text: String(localized: "Security incidents arrive on their own, for every wallet Walletbeat covers."))
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
		let walletID = WalletbeatWatch.walletID(from: thing)
		let card = walletID.flatMap { WalletbeatState.card($0) }
		// 56 matches `AssetRosterSlot.markSize`, spelled rather than read: that static
		// lives on a generic type whose parameter is being inferred from this very
		// closure, so referring to it here is unresolvable. `MetricDisc` carries the
		// same number as its own default for the same reason.
		AssetRosterSlot(label: card?.name ?? thing.title) {
			WalletbeatMark(name: card?.name ?? thing.title, size: 56)
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
	}

	private func watchTyped() {
		guard let first = hits.first else { return }
		watch(first)
	}

	private func watch(_ entry: WalletbeatEntry) {
		let wasEmpty = watched.isEmpty
		guard WalletbeatWatch.add(entry, context: modelContext) != nil else { return }
		queryField = ""
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
			WalletbeatWatch.registerBridge(store: store, context: modelContext)
			guard !watched.isEmpty else { return }
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
