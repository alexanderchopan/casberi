import SwiftData
import SwiftUI

/// Every wallet Walletbeat rates (prd §419).
///
/// THE SORT IS THE WHOLE DESIGN PROBLEM, and it is solved by refusing the obvious thing.
/// A "best first" order needs a composite score across five dimensions; Walletbeat
/// publishes no such number and neither do we, so offering one would put our weighting
/// behind their name (§83). The default is ALPHABETICAL, and the only re-order offered is
/// by how much has been REVIEWED — which is a fact about Walletbeat's coverage, not a
/// judgment of the wallet.
///
/// Measured 2026-08-20: sixteen of the 32 have fewer than a quarter of their attributes
/// judged and two have none at all, which is exactly why "Most reviewed" is a useful sort
/// and "best" would be a lie — most of this list is a list of unknowns, and the screen has
/// to say so rather than paint 32 confident strips.
struct WalletbeatDirectoryScreen: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store

	enum Kind: String, CaseIterable, Identifiable {
		case software, hardware
		var id: String { rawValue }
		var label: String {
			switch self {
			case .software: return String(localized: "Software")
			case .hardware: return String(localized: "Hardware")
			}
		}
	}

	enum Order: String, CaseIterable, Identifiable {
		case name, reviewed
		var id: String { rawValue }
		var label: String {
			switch self {
			case .name: return String(localized: "A–Z")
			case .reviewed: return String(localized: "Most reviewed")
			}
		}
	}

	@State private var kind: Kind = .software
	@State private var order: Order = .name
	@State private var watchedIDs: Set<String> = []
	/// Wallets with an incident Walletbeat still lists as open (prd §422).
	///
	/// This screen is where somebody chooses which wallet to trust, and until now
	/// it drew coverage and a maturity stage — but not that one of these wallets
	/// has an unresolved breach, which is landed data one join away. The single
	/// most decision-relevant fact on the screen was the one it withheld.
	@State private var openIncidents: Set<String> = []
	/// Wallets whose app has really announced itself to this device over WalletConnect
	/// (prd §430). The one fact on this screen that is about the PERSON rather than about
	/// the wallet, which is why it is drawn apart from the finding line below it.
	@State private var connected: Set<String> = []
	@State private var opened: String?

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: DS.Space.s3) {
					Picker("", selection: $kind) {
						ForEach(Kind.allCases) { Text($0.label).tag($0) }
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

			ForEach(entries) { entry in
				row(entry)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			}

			Section {
				Text(String(localized: "Walletbeat's ratings, not ours. A wallet marked not rated is one they haven't examined yet — it isn't a verdict.\n\nRatings as of \(WalletbeatDirectory.generated); the wallets you watch are read live."))
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
		.dsScreenTitle("Every wallet")
		.sheet(item: $opened) { walletID in
			WalletbeatCardScreen(walletID: walletID)
		}
		.onAppear(perform: load)
	}

	@ViewBuilder
	private func row(_ entry: WalletbeatEntry) -> some View {
		let counts = entry.overall
		let watching = watchedIDs.contains(entry.id)
		HStack(alignment: .center, spacing: DS.Space.s3) {
			WalletbeatMark(name: entry.name, walletID: entry.id)
			VStack(alignment: .leading, spacing: 2) {
				Text(entry.name)
					.dsText(.body17)
					.foregroundStyle(DS.textPrimary)
					.lineLimit(1)
				// ITS OWN LINE, deliberately. It could be squeezed into the fact line
				// below, but that line's order is §422's ruling — an unresolved incident
				// leads it because it outranks coverage — and this is not a finding at
				// all: it says which of the thirty-two rows are about software this
				// person actually runs. Different question, different line, and the
				// ruling below is left exactly as it was.
				if connected.contains(entry.id) {
					Text(WalletbeatCopy.connectedMarker)
						.dsText(.label11).fontWeight(.semibold)
						.foregroundStyle(DS.tint)
				}
				HStack(spacing: DS.Space.s2) {
					// FIRST, and in words. It outranks coverage because coverage
					// describes how much Walletbeat has looked, and this
					// describes what they found and have not seen fixed.
					if openIncidents.contains(entry.id) {
						Text(String(localized: "Unresolved incident"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
					Text(WalletbeatCopy.coverage(counts))
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
					// Walletbeat's own maturity stage, where they publish one. Hardware
					// wallets have none in their schema, so this is absent rather than
					// showing a dash — an empty slot on two-thirds of the list.
					if let stage = entry.stage {
						Text(stage)
							.dsText(.label11).fontWeight(.semibold)
							.foregroundStyle(DS.textSecondary)
					}
				}
			}
			Spacer(minLength: DS.Space.s2)
			WalletbeatShape(counts: counts)
			// Watch is the verb on every row; a wallet already watched says so instead of
			// offering a control that would do nothing.
			if watching {
				Text(String(localized: "Watching"))
					.dsText(.label11).fontWeight(.semibold)
					.foregroundStyle(DS.textTertiary)
					.frame(width: 58, alignment: .trailing)
			} else {
				Button(action: { watch(entry) }) {
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
		.onTapGesture { DSHaptic.tap(); opened = entry.id }
		.dsTapCard()
	}

	private var entries: [WalletbeatEntry] {
		let filtered = WalletbeatDirectory.wallets.filter { $0.hardware == (kind == .hardware) }
		switch order {
		case .name:
			return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		case .reviewed:
			// By the SHARE judged, not the raw count: hardware wallets have 25 attributes
			// and software 29, so a raw count would rank a hardware wallet below a
			// software one that has been examined less thoroughly. Ties fall through to
			// the name, so the order is total and never reshuffles between opens.
			return filtered.sorted { a, b in
				let ax = share(a), bx = share(b)
				if ax != bx { return ax > bx }
				return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
			}
		}
	}

	private func share(_ entry: WalletbeatEntry) -> Double {
		let counts = entry.overall
		guard counts.applicable > 0 else { return 0 }
		return Double(counts.judged) / Double(counts.applicable)
	}

	private func load() {
		watchedIDs = Set(WalletbeatWatch.watchedIDs(context: modelContext))
		// From the BOOK, not from the rows' `authorHandle`: the row keeps only
		// `wallets.first` and an incident can name several, so a join on the row
		// would leave the second and third wallets unmarked. The book is also
		// where the STATUS lives, and a resolved incident must not mark anything
		// — a permanent warning on a wallet whose bug was fixed years ago is the
		// §83 fake status pointing the other way.
		//
		// Landed incidents only, so this marks what the person's own corpus can
		// show. Someone who has never synced sees no markers rather than a claim
		// we cannot back — the same honesty the head's "Reading Walletbeat…"
		// keeps.
		openIncidents = Set(
			WalletbeatIncidentBook.all().values
				.filter { $0.status.isOpen }
				.flatMap(\.wallets))
		// Resolved on every load rather than stored resolved, so a wallet Walletbeat has
		// added since the sighting starts being marked with no migration — see
		// `WalletConnectApps`, which keeps the app's raw name for exactly this reason.
		connected = WalletbeatWatch.connectedIDs()
	}

	private func watch(_ entry: WalletbeatEntry) {
		DSHaptic.tap()
		guard WalletbeatWatch.add(entry, context: modelContext) != nil else { return }
		load()
		WalletbeatWatch.registerBridge(store: store, context: modelContext)
		Task { _ = await WalletbeatIngest.refresh(context: modelContext) }
	}
}
