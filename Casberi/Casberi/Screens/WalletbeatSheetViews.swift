import SwiftUI

// The three Walletbeat sheet heads (prd §419 amendment).
//
// Every view here is FLAT BY LAW — plain stacks, no generic `Widget`/`Row` mount (the
// first-frame render-depth lesson, paid three times).
//
// Each takes VALUES where it can. `WalletbeatIncidentHead` takes a `Thing` because the
// title and summary the row already carries are its content, and it guards its own body:
// SwiftUI re-evaluates a leaf on the model's own observation, with no involvement from the
// parent that built it (corollary 5).

/// A security incident — Walletbeat's prose, the facts they record, and their citations.
struct WalletbeatIncidentHead: View {
	let thing: Thing

	@Environment(\.openURL) private var openURL

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let facts = WalletbeatIncidentBook.facts(ref: thing.sourceRef)
		VStack(alignment: .leading, spacing: DS.Space.s4) {
			Text(thing.title)
				.dsText(.heading28)
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)
				.textSelection(.enabled)

			statusLine(facts)

			if let summary = thing.summary, !summary.isEmpty {
				Text(summary)
					.dsText(.reading20)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
					.textSelection(.enabled)
			}

			if let facts { factCard(facts) }
			if let facts, !facts.sources.isEmpty { sources(facts.sources) }

			stamp(facts)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	/// Kind, status, and Walletbeat's severity — attributed, never stated as ours.
	@ViewBuilder
	private func statusLine(_ facts: WalletbeatIncidentFacts?) -> some View {
		let open = thing.tags.contains(WalletbeatNewsParse.openTag)
		HStack(spacing: DS.Space.s2) {
			if let facts {
				Text(facts.type.label)
					.dsText(.label11).fontWeight(.bold)
					.foregroundStyle(DS.textSecondary)
					.padding(.horizontal, 10).padding(.vertical, 4)
					.background(Capsule(style: .circular).fill(DS.fillFaint))
				Text(facts.status.label)
					.dsText(.label11).fontWeight(.bold)
					.foregroundStyle(open ? DS.attention : DS.confirm)
					.padding(.horizontal, 10).padding(.vertical, 4)
					.background(
						Capsule(style: .circular)
							.fill((open ? DS.attention : DS.confirm).opacity(0.13)))
				if let severity = facts.severity {
					// "Walletbeat rates it …", never a bare severity word: the judgment is
					// theirs and every surface in this feature says so.
					Text(String(localized: "Walletbeat rates it \(severity.label)"))
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
				}
			}
			Spacer(minLength: 0)
		}
	}

	/// What their record states, and nothing it doesn't.
	@ViewBuilder
	private func factCard(_ facts: WalletbeatIncidentFacts) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			if !facts.wallets.isEmpty {
				factRow(String(localized: "Affects"), affectedNames(facts.wallets))
			}
			if let funds = facts.fundsImpacted {
				// The two readings are genuinely different and both are worth saying: a
				// flaw that could reach funds is not the same as one that did.
				factRow(String(localized: "Funds at risk"),
						funds ? String(localized: "Yes, by Walletbeat's reading")
							  : String(localized: "No, by Walletbeat's reading"),
						tinted: funds)
			}
			if let updated = facts.updatedAt, updated > facts.publishedAt {
				factRow(String(localized: "Last revised"), Self.day.string(from: updated))
			}
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	@ViewBuilder
	private func factRow(_ key: String, _ value: String, tinted: Bool = false) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
			Text(key)
				.dsText(.subhead13)
				.foregroundStyle(DS.textTertiary)
			Spacer(minLength: DS.Space.s2)
			Text(value)
				.dsText(.subhead13).fontWeight(.semibold)
				.foregroundStyle(tinted ? DS.attention : DS.textPrimary)
				.multilineTextAlignment(.trailing)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	/// A wallet id is Walletbeat's internal spelling, so it is resolved to the name a
	/// person would say. An id we don't carry falls back to itself rather than vanishing —
	/// an incident naming a wallet we can't name is still about that wallet.
	private func affectedNames(_ ids: [String]) -> String {
		ids.map { id in
			WalletbeatDirectory.wallets.first { $0.id == id }?.name ?? id
		}.joined(separator: ", ")
	}

	/// Walletbeat's own citations, each a door to the original disclosure.
	@ViewBuilder
	private func sources(_ sources: [WalletbeatSource]) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			Text(String(localized: "Sources"))
				.dsText(.label11).fontWeight(.semibold)
				.foregroundStyle(DS.textTertiary)
			ForEach(sources, id: \.url) { source in
				Button {
					DSHaptic.tap()
					if let url = URL(string: source.url) { openURL(url) }
				} label: {
					HStack(alignment: .top, spacing: DS.Space.s3) {
						VStack(alignment: .leading, spacing: 2) {
							Text(source.label)
								.dsText(.subhead13).fontWeight(.semibold)
								.foregroundStyle(DS.textPrimary)
								.multilineTextAlignment(.leading)
								.fixedSize(horizontal: false, vertical: true)
							Text(WalletbeatNewsParse.host(of: source.url))
								.dsText(.label11)
								.foregroundStyle(DS.textTertiary)
						}
						Spacer(minLength: DS.Space.s2)
						Image(systemName: "arrow.up.right")
							.dsGlyph(11)
							.foregroundStyle(DS.textTertiary)
					}
					.padding(DS.Space.s3)
					.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.dsWidgetSurface()
				.dsHover()
			}
		}
	}

	/// Provenance said, never implied.
	@ViewBuilder
	private func stamp(_ facts: WalletbeatIncidentFacts?) -> some View {
		Text(String(localized: "Published \(Self.day.string(from: facts?.publishedAt ?? thing.capturedAt)) · From Walletbeat, an open registry of wallet practices"))
			.dsText(.label11)
			.foregroundStyle(DS.textTertiary)
			.fixedSize(horizontal: false, vertical: true)
	}

	private static let day: DateFormatter = {
		let f = DateFormatter()
		f.dateStyle = .medium
		f.timeStyle = .none
		return f
	}()
}

/// Walletbeat changing its mind — only meaningful as before-and-after.
struct WalletbeatRevisionHead: View {
	let thing: Thing
	let revision: WalletbeatSheet.Revision
	let attribute: WalletbeatAttribute?

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let name = WalletbeatDirectory.wallets.first { $0.id == revision.walletID }?.name
			?? revision.walletID
		VStack(alignment: .leading, spacing: DS.Space.s4) {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				Text(String(localized: "Walletbeat revised its review"))
					.dsText(.label11).fontWeight(.semibold)
					.foregroundStyle(DS.brandHue(for: "walletbeat") ?? DS.tint)
				Text(attribute?.name ?? thing.title)
					.dsText(.heading28)
					.foregroundStyle(DS.textPrimary)
					.fixedSize(horizontal: false, vertical: true)
				Text(String(localized: "\(name) · \(revision.after.isJudged ? String(localized: "now rated") : String(localized: "no longer rated"))"))
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
			}

			// The verdict it moved TO. Deliberately not a before→after pair: the ref
			// records only where it landed, and painting an arrow from a "before" we
			// never stored would be inventing the half of the story that matters most.
			HStack(spacing: DS.Space.s3) {
				WalletbeatVerdictTag(verdict: revision.after)
				Spacer(minLength: 0)
			}
			.padding(DS.Space.s4)
			.frame(maxWidth: .infinity, alignment: .leading)
			.dsWidgetSurface()

			if let summary = thing.summary, !summary.isEmpty {
				Text(summary)
					.dsText(.reading20)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
					.textSelection(.enabled)
			}

			Text(revision.day.map {
				String(localized: "Walletbeat's entry was revised \($0) · their judgment, not ours")
			} ?? String(localized: "Walletbeat's own judgment, not ours"))
				.dsText(.label11)
				.foregroundStyle(DS.textTertiary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}
