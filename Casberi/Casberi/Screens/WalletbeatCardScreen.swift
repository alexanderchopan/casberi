import SwiftData
import SwiftUI

/// One wallet's report card (prd §419) — the feature's primary surface.
///
/// EVERY ATTRIBUTE IS SHOWN, in Walletbeat's own order, with Walletbeat's own sentence.
/// Nothing is selected, ranked or summarised: the only editorial act available here would
/// be choosing which findings matter, and that is exactly the act this feature refuses.
/// The one ordering choice — failures first inside each dimension — is stated below.
///
/// The card is fetched live on open, so a wallet you have never watched still shows its
/// real ratings; the bundled snapshot's counts draw immediately underneath so the screen
/// is never empty while that request is in flight.
struct WalletbeatCardScreen: View {
	let walletID: String

	@Environment(\.modelContext) private var modelContext
	@Environment(\.dismiss) private var dismiss
	@Environment(BridgeStore.self) private var store

	@State private var card: WalletbeatCard?
	@State private var loading = false
	@State private var failed = false
	@State private var watching = false

	private var entry: WalletbeatEntry? {
		WalletbeatDirectory.wallets.first { $0.id == walletID }
	}

	private var name: String { card?.name ?? entry?.name ?? walletID }
	private var counts: WalletbeatCounts { card?.overall ?? entry?.overall ?? .zero }

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: DS.Space.s4) {
					header
					if WalletbeatCoverage.of(counts).showsShape {
						dimensionSummary
					} else {
						unexaminedNote
					}
					if let card {
						ForEach(card.dimensions, id: \.self) { dimension in
							dimensionSection(card: card, dimension: dimension)
						}
					} else if loading {
						Text(String(localized: "Reading Walletbeat…"))
							.dsText(.subhead13)
							.foregroundStyle(DS.textTertiary)
					} else if failed {
						Text(String(localized: "Couldn't reach Walletbeat. The counts above are from when this app was last updated."))
							.dsText(.subhead13)
							.foregroundStyle(DS.textTertiary)
							.fixedSize(horizontal: false, vertical: true)
					}
					footer
				}
				.padding(DS.Space.s4)
			}
			.dsPageBackground()
			.dsSoftScrollEdges()
			.navigationTitle(name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String(localized: "Done")) { dismiss() }
				}
			}
		}
		.task { await load() }
	}

	// MARK: - Head

	private var header: some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			HStack(spacing: DS.Space.s3) {
				WalletbeatMark(name: name, size: 48)
				VStack(alignment: .leading, spacing: 3) {
					Text(name)
						.dsText(.heading22)
						.foregroundStyle(DS.textPrimary)
					Text(subtitleLine)
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
				}
				Spacer(minLength: DS.Space.s2)
			}

			// Watching is the verb this screen offers. Never a second control that would
			// duplicate the directory's — one place to say yes.
			Button(action: toggleWatch) {
				Text(watching
					? String(localized: "Watching — tap to stop")
					: String(localized: "Watch this wallet"))
					.dsText(.subhead13).fontWeight(.semibold)
					.foregroundStyle(watching ? DS.textTertiary : DS.tint)
			}
			.buttonStyle(.plain)
		}
	}

	private var subtitleLine: String {
		var parts: [String] = []
		let card = self.card
		if (card?.hardware ?? entry?.hardware) == true {
			parts.append(String(localized: "Hardware wallet"))
		} else {
			parts.append(String(localized: "Software wallet"))
		}
		if let stage = card?.stage ?? entry?.stage { parts.append(stage) }
		if let updated = card?.lastUpdated ?? entry?.updated {
			parts.append(String(localized: "Walletbeat reviewed \(updated)"))
		}
		return parts.joined(separator: " · ")
	}

	// MARK: - Summary

	private var dimensionSummary: some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			Text(WalletbeatCopy.coverage(counts))
				.dsText(.label12).fontWeight(.semibold)
				.foregroundStyle(DS.textSecondary)

			ForEach(dimensions, id: \.self) { dimension in
				let counts = dimensionCounts(dimension)
				HStack(spacing: DS.Space.s2) {
					Text(dimension.label)
						.dsText(.subhead13)
						.foregroundStyle(DS.textSecondary)
						.frame(width: 112, alignment: .leading)
					WalletbeatBar(counts: counts)
					Text("\(counts.judged)/\(counts.applicable)")
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.monospacedDigit()
						.frame(width: 40, alignment: .trailing)
				}
			}

			legend
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	private var legend: some View {
		HStack(spacing: DS.Space.s3) {
			ForEach([WalletbeatVerdict.pass, .partial, .fail, .unrated], id: \.self) { verdict in
				WalletbeatVerdictTag(verdict: verdict)
			}
			Spacer(minLength: 0)
		}
	}

	/// The honest alternative to a bar when there is almost nothing behind it.
	private var unexaminedNote: some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			Text(counts.judged == 0
				? String(localized: "Walletbeat hasn't rated this wallet yet")
				: String(localized: "Walletbeat has barely started on this wallet"))
				.dsText(.body17).fontWeight(.semibold)
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)
			Text(counts.judged == 0
				? String(localized: "It's listed, and none of its \(counts.applicable) checks has been judged. That's an absence of information, not a clean bill of health.")
				: String(localized: "Only \(counts.judged) of \(counts.applicable) checks are judged, which is too few to compare against another wallet."))
				.dsText(.subhead13)
				.foregroundStyle(DS.textSecondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	// MARK: - Attributes

	@ViewBuilder
	private func dimensionSection(card: WalletbeatCard, dimension: WalletbeatDimension) -> some View {
		let attributes = ordered(card.attributes(in: dimension))
		if !attributes.isEmpty {
			VStack(alignment: .leading, spacing: DS.Space.s3) {
				Text(dimension.label)
					.dsText(.heading17)
					.foregroundStyle(DS.textPrimary)
				ForEach(attributes) { attribute in
					attributeRow(attribute)
				}
			}
			.padding(.top, DS.Space.s2)
		}
	}

	/// Failures first, then partials, then passes, then the unrated.
	///
	/// The ONE re-ordering on this screen. It is a reading order, not a ranking: everything
	/// is shown, nothing is hidden or scored, and within each band Walletbeat's own
	/// attribute order is preserved (`sorted(by:)` is stable in this use because the bands
	/// are keyed and compared on a single value).
	private func ordered(_ attributes: [WalletbeatAttribute]) -> [WalletbeatAttribute] {
		func band(_ verdict: WalletbeatVerdict) -> Int {
			switch verdict {
			case .fail: return 0
			case .partial: return 1
			case .pass: return 2
			case .unrated: return 3
			case .exempt: return 4
			}
		}
		return attributes.enumerated()
			.sorted { a, b in
				let ab = band(a.element.verdict), bb = band(b.element.verdict)
				return ab == bb ? a.offset < b.offset : ab < bb
			}
			.map(\.element)
	}

	@ViewBuilder
	private func attributeRow(_ attribute: WalletbeatAttribute) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s1 + 2) {
			HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
				Text(attribute.name)
					.dsText(.body17)
					.foregroundStyle(DS.textPrimary)
					.fixedSize(horizontal: false, vertical: true)
				Spacer(minLength: DS.Space.s2)
				WalletbeatVerdictTag(verdict: attribute.verdict)
			}
			// Walletbeat's sentence, verbatim. Where they have none — which is what an
			// unrated attribute means — their QUESTION is shown instead, so the row still
			// says what was being asked rather than going blank.
			if !attribute.explanation.isEmpty {
				Text(attribute.explanation)
					.dsText(.subhead13)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			} else if !attribute.question.isEmpty {
				Text(attribute.question)
					.dsText(.subhead13)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(DS.Space.s3)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	// MARK: - Foot

	private var footer: some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			if let url = entry?.pageURL ?? URL(string: "https://\(WalletbeatHost.site)/\(walletID)/") {
				Link(destination: url) {
					Text(String(localized: "Full review on Walletbeat"))
						.dsText(.subhead13).fontWeight(.semibold)
						.foregroundStyle(DS.tint)
				}
			}
			Text(String(localized: "Every rating on this screen is Walletbeat's own judgment, in their words. Casberi reads their public review and never scores a wallet itself."))
				.dsText(.label11)
				.foregroundStyle(DS.textTertiary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.top, DS.Space.s2)
	}

	// MARK: - Actions

	private var dimensions: [WalletbeatDimension] {
		card?.dimensions ?? entry?.dimensions ?? []
	}

	private func dimensionCounts(_ dimension: WalletbeatDimension) -> WalletbeatCounts {
		card?.counts(in: dimension) ?? entry?.counts[dimension] ?? .zero
	}

	private func load() async {
		watching = WalletbeatWatch.watchedIDs(context: modelContext).contains(walletID)
		// A stored card draws instantly; the live read then replaces it. Both are shown
		// the same way, because a cached rating and a fresh one are equally Walletbeat's.
		if let stored = WalletbeatState.card(walletID) { card = stored }
		guard !loading else { return }
		loading = true
		defer { loading = false }
		if let fresh = await WalletbeatFetch.card(walletID: walletID) {
			card = fresh
			// Cached even when unwatched: opening a report card is the expensive read, and
			// a person comparing three wallets should pay for each one once.
			WalletbeatState.set(fresh)
		} else if card == nil {
			failed = true
		}
	}

	private func toggleWatch() {
		DSHaptic.tap()
		if watching {
			WalletbeatWatch.remove(walletID, context: modelContext)
			watching = false
		} else if let entry {
			WalletbeatWatch.add(entry, context: modelContext)
			watching = true
		}
		WalletbeatWatch.registerBridge(store: store, context: modelContext)
	}
}
