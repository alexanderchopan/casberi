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
	/// The wallet whose report card is open over this sheet (prd §430).
	@State private var openedWallet: String?

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let facts = WalletbeatIncidentBook.facts(ref: thing.sourceRef)
		VStack(alignment: .leading, spacing: DS.Space.s4) {
			// THE CONTAINER'S OWN TITLE RULE (prd §560) — see
			// `L2beatSheetViews.liveBody`; the two registry heads shared the
			// stray `heading28` and are swept together.
			Text(thing.title)
				.dsText(thing.title.count > 100 ? .heading22 : .heading34)
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
		// ONE presentation on this view, and it lives here rather than on a row: the
		// head is itself inside a presented sheet, which is the one place this app
		// allows a nested `.sheet` (`ReplyingToRow`'s ruling). It hangs off `liveBody`
		// so a row deleted underneath takes the card down with it.
		.sheet(item: $openedWallet) { walletID in
			WalletbeatCardScreen(walletID: walletID)
		}
	}

	/// Kind, status, and Walletbeat's severity — attributed, never stated as ours.
	@ViewBuilder
	private func statusLine(_ facts: WalletbeatIncidentFacts?) -> some View {
		let open = thing.tags.contains(WalletbeatNewsParse.openTag)
		HStack(spacing: DS.Space.s2) {
			if let facts {
				// THE SHARED STAMP (prd §560, 2026-09-01) — see
				// `L2beatSheetViews.kindLine` for the full reasoning; these two
				// heads carried the same hand-rolled capsule and are swept
				// together. The KIND is `quiet` (a classification, not news);
				// the STATUS takes the two weights it already meant — `urgent`
				// while it is open, `good` once Walletbeat records it closed,
				// which is `DSStamp`'s own `confirm`/`attention` pair reached
				// by naming the meaning instead of picking the colour.
				DSStamp(word: facts.type.label, weight: .quiet)
				DSStamp(word: facts.status.label, weight: open ? .urgent : .good)
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
				affectedRow(facts.wallets)
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

	/// Who it affected — and a door to what Walletbeat says about each of them (prd §430).
	///
	/// This line was a joined string, which made the sheet a dead end at exactly the
	/// moment its reader has the next question: a rating is a standing judgment and an
	/// incident is an event, so reading about a breach is precisely when somebody wants
	/// the report card. The card already cross-links the other way ("On record"); this is
	/// the direction that was missing.
	///
	/// ONE WALLET PER LINE rather than a wrapping row of chips: a name is a door here, and
	/// a door clipped by its neighbour is a door nobody finds. Three named wallets is
	/// three lines, which is the honest size of that fact.
	///
	/// A WALLET WE DO NOT CARRY IS STILL NAMED, and is deliberately NOT a door: Walletbeat
	/// files incidents against products they do not rate (their SafePal and Slope entries
	/// name no rated wallet at all), so the id falls back to itself — an incident naming a
	/// wallet we cannot name is still about that wallet — and offering a report card that
	/// does not exist would be the dead control §83 bans.
	@ViewBuilder
	private func affectedRow(_ ids: [String]) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
			Text(String(localized: "Affects"))
				.dsText(.subhead13)
				.foregroundStyle(DS.textTertiary)
			Spacer(minLength: DS.Space.s2)
			VStack(alignment: .trailing, spacing: DS.Space.s1) {
				ForEach(ids, id: \.self) { id in
					if let entry = WalletbeatDirectory.wallets.first(where: { $0.id == id }) {
						Button {
							DSHaptic.tap()
							openedWallet = id
						} label: {
							HStack(spacing: DS.Space.s1 + 2) {
								Text(entry.name)
									.dsText(.subhead13).fontWeight(.semibold)
									.foregroundStyle(DS.tint)
									.multilineTextAlignment(.trailing)
								Image(systemName: "chevron.right")
									.dsGlyph(10, weight: .bold)
									.foregroundStyle(DS.tint)
							}
						}
						.buttonStyle(.plain)
						.dsHover()
						.accessibilityLabel(Text(String(localized: "What Walletbeat says about \(entry.name)")))
					} else {
						Text(id)
							.dsText(.subhead13).fontWeight(.semibold)
							.foregroundStyle(DS.textPrimary)
							.multilineTextAlignment(.trailing)
					}
				}
			}
		}
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

			// BEFORE → AFTER where the ref records a before, and the verdict alone
			// where it does not (prd §430).
			//
			// This surface drew the landing verdict alone for as long as it existed, and
			// its own note said why: the ref recorded nothing else, and "painting an arrow
			// from a 'before' we never stored would be inventing the half of the story
			// that matters most". The before is stored now. It is still never INFERRED —
			// a row landed before that change has no before, and draws exactly what it
			// always drew rather than guessing one from the card as it stands today,
			// which would be a different reading of a different moment.
			HStack(spacing: DS.Space.s3) {
				if let before = revision.before {
					WalletbeatVerdictTag(verdict: before)
					Image(systemName: "arrow.right")
						.dsGlyph(11)
						.foregroundStyle(DS.textTertiary)
						.accessibilityHidden(true)
				}
				WalletbeatVerdictTag(verdict: revision.after)
				Spacer(minLength: 0)
			}
			.padding(DS.Space.s4)
			.frame(maxWidth: .infinity, alignment: .leading)
			.dsWidgetSurface()
			.accessibilityElement(children: .combine)
			.accessibilityLabel(Text(revision.before.map {
				String(localized: "Walletbeat moved this from \(WalletbeatCopy.label($0)) to \(WalletbeatCopy.label(revision.after))")
			} ?? WalletbeatCopy.label(revision.after)))

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
