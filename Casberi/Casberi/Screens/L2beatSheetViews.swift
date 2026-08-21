import SwiftUI

// The two L2BEAT sheet heads that aren't the risk card (prd §428).
//
// Every view here is FLAT BY LAW — plain stacks, no generic `Widget`/`Row` mount (the
// first-frame render-depth lesson, paid three times).
//
// Each takes a `Thing` because the title and summary the row already carries are its
// content, and each guards its own body: SwiftUI re-evaluates a leaf on the model's own
// observation, with no involvement from the parent that built it (corollary 5).

/// A milestone — L2BEAT's prose, what they class it as, and their citation.
struct L2beatMilestoneHead: View {
	let thing: Thing

	@Environment(\.openURL) private var openURL

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let facts = L2beatMilestoneBook.facts(ref: thing.sourceRef)
		VStack(alignment: .leading, spacing: DS.Space.s4) {
			Text(thing.title)
				.dsText(.heading28)
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)
				.textSelection(.enabled)

			kindLine(facts)

			if let summary = thing.summary, !summary.isEmpty {
				Text(summary)
					.dsText(.reading20)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
					.textSelection(.enabled)
			}

			if let facts { factCard(facts) }
			if let facts, let url = facts.url, !url.isEmpty { source(url) }

			stamp(facts)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	/// What L2BEAT classes this as — their word, never ours.
	///
	/// AND NO STATUS, deliberately. §419's incident head could show ongoing-versus-resolved
	/// because Walletbeat publishes a `status` field; L2BEAT's milestone schema has none, so
	/// there is nothing here to state and inventing one — "resolved" because it is old — is
	/// exactly the §83 fake status this feature exists to avoid.
	@ViewBuilder
	private func kindLine(_ facts: L2beatMilestoneFacts?) -> some View {
		let isIncident = thing.tags.contains(L2beatNewsParse.incidentTag)
		HStack(spacing: DS.Space.s2) {
			if let facts {
				Text(facts.kind.label)
					.dsText(.label11).fontWeight(.bold)
					.foregroundStyle(isIncident ? DS.attention : DS.textSecondary)
					.padding(.horizontal, 10).padding(.vertical, 4)
					.background(
						Capsule(style: .circular)
							.fill(isIncident ? DS.attention.opacity(0.13) : DS.fillFaint))
				if let name = facts.projectName {
					Text(name)
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
				}
			}
			Spacer(minLength: 0)
		}
	}

	/// What their record states, and nothing it doesn't.
	@ViewBuilder
	private func factCard(_ facts: L2beatMilestoneFacts) -> some View {
		let project = L2beatState.best(facts.projectID)
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			factRow(String(localized: "Chain"), facts.projectName ?? facts.projectID)
			if let stage = project?.stage {
				// L2BEAT's stage AS IT STANDS NOW, and the label says so: this is a record of
				// something that happened, sometimes years ago, and the ladder has moved
				// since. Printing today's rung beside a 2022 event without that word would
				// read as the rung it had then.
				factRow(String(localized: "L2BEAT stage today"), stage.label)
			}
			if let project, project.underReview {
				factRow(String(localized: "Assessment"),
						String(localized: "Under review"), tinted: true)
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

	/// L2BEAT's own citation, a door to the original announcement. One, not a list — their
	/// schema carries a single `url` per milestone, unlike Walletbeat's `ref` array.
	@ViewBuilder
	private func source(_ url: String) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			Text(String(localized: "Source"))
				.dsText(.label11).fontWeight(.semibold)
				.foregroundStyle(DS.textTertiary)
			Button {
				DSHaptic.tap()
				if let link = URL(string: url) { openURL(link) }
			} label: {
				HStack(alignment: .top, spacing: DS.Space.s3) {
					Text(L2beatSheetCopy.host(of: url))
						.dsText(.subhead13).fontWeight(.semibold)
						.foregroundStyle(DS.textPrimary)
						.multilineTextAlignment(.leading)
						.fixedSize(horizontal: false, vertical: true)
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

	/// Provenance said, never implied.
	@ViewBuilder
	private func stamp(_ facts: L2beatMilestoneFacts?) -> some View {
		Text(String(localized: "Recorded \(Self.day.string(from: thing.capturedAt)) · From L2BEAT, an open registry of layer-2 risk"))
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

/// L2BEAT changing its reading — only meaningful as what it moved to.
struct L2beatRevisionHead: View {
	let thing: Thing
	let revision: L2beatSheet.Revision
	let project: L2beatProject?
	let risk: L2beatRisk?

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let name = project?.name ?? revision.projectID
		VStack(alignment: .leading, spacing: DS.Space.s4) {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				Text(revision.isStageMove
					? String(localized: "L2BEAT moved this chain's stage")
					: String(localized: "L2BEAT revised its assessment"))
					.dsText(.label11).fontWeight(.semibold)
					.foregroundStyle(DS.brandHue(for: "l2beat") ?? DS.tint)
				Text(headline)
					.dsText(.heading28)
					.foregroundStyle(DS.textPrimary)
					.fixedSize(horizontal: false, vertical: true)
				Text(name)
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
			}

			// What it moved TO. Deliberately not a before→after pair: the ref records only
			// where it landed, and painting an arrow from a "before" we never stored would
			// be inventing the half of the story that matters most.
			HStack(spacing: DS.Space.s3) {
				if revision.isStageMove {
					L2beatStageChip(stage: revision.afterStage)
				} else if let sentiment = revision.afterSentiment {
					L2beatSentimentTag(sentiment: sentiment)
				}
				if let risk {
					Text(risk.value)
						.dsText(.subhead13).fontWeight(.semibold)
						.foregroundStyle(DS.textSecondary)
				}
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

			// The day WE NOTICED, said as that and not as theirs. L2BEAT's summary states
			// what is true, never when it became true, so there is no publication date here
			// to cite — and dating their change to the day our sweep ran would be a claim
			// about them we cannot support.
			Text(revision.day.map {
				String(localized: "Noticed \($0) · L2BEAT's reading, not ours")
			} ?? String(localized: "L2BEAT's own reading, not ours"))
				.dsText(.label11)
				.foregroundStyle(DS.textTertiary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var headline: String {
		if revision.isStageMove {
			return revision.afterStage?.meaning ?? thing.title
		}
		return revision.axis?.label ?? thing.title
	}
}

/// Small shared bits the sheet heads need.
enum L2beatSheetCopy {
	static func host(of url: String) -> String {
		URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
	}
}
