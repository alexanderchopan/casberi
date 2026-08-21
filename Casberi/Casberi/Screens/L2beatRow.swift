import SwiftUI

/// The L2BEAT room's row shapes (prd §428).
///
/// The room holds three kinds of thing and they read differently on purpose: a WATCHED CHAIN
/// is a standing assessment, a MILESTONE is something that happened on a date, and a
/// REVISION is a note that L2BEAT's own reading changed. Drawing all three as the same band
/// would make the room what §313 found the X room to be — a wall of undifferentiated titles
/// over data that deserved better.
///
/// Each of these guards its own body: SwiftUI re-evaluates a leaf's body on the model's own
/// observation, with no involvement from the parent that built it (corollary 5).

/// A watched chain — L2BEAT's standing assessment, drawn from the freshest reading.
struct L2beatChainRow: View {
	let thing: Thing

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let chainID = L2beatWatch.chainID(from: thing)
		// The live read where the sweep has run, the bundled snapshot otherwise — so a chain
		// watched a moment ago already draws L2BEAT's real shape instead of an empty row
		// waiting on a request that may be hours away.
		let project = chainID.flatMap { L2beatState.best($0) }

		VStack(alignment: .leading, spacing: DS.Space.s2) {
			HStack(alignment: .center, spacing: DS.Space.s3) {
				L2beatMark(name: project?.name ?? thing.title, chainID: chainID, size: 38)
				VStack(alignment: .leading, spacing: 2) {
					Text(project?.name ?? thing.title)
						.dsText(.body17)
						.foregroundStyle(DS.textPrimary)
						.lineLimit(1)
					Text(subtitle(project))
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.lineLimit(1)
				}
				Spacer(minLength: DS.Space.s2)
				L2beatStageChip(stage: project?.stage)
			}

			if let project, !project.risks.isEmpty {
				riskLines(project)
			}

			// L2BEAT's own sentence about the sharpest finding, where there is one.
			if let summary = thing.summary, !summary.isEmpty {
				Text(summary)
					.dsText(.subhead13)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	/// What kind of chain this is, in L2BEAT's own words. Their `category` is the useful half
	/// ("Optimistic Rollup"); measured 2026-08-21 it reads "Other" for 77 of 105, and in that
	/// case the layer is the only thing left worth saying.
	private func subtitle(_ project: L2beatProject?) -> String {
		guard let project else { return String(localized: "Reading L2BEAT…") }
		let category = project.category ?? ""
		let host = project.hostChain.map { String(localized: "on \($0)") }
		let head = (category.isEmpty || category == "Other") ? project.layer.label : category
		return [head, host].compactMap { $0 }.joined(separator: " · ")
	}

	/// One line per axis, so the shape says WHICH question a chain fails rather than only how
	/// many. This is the only place in the room a person reads L2BEAT's five calls together.
	@ViewBuilder
	private func riskLines(_ project: L2beatProject) -> some View {
		VStack(spacing: DS.Space.s1 + 2) {
			ForEach(project.orderedRisks) { risk in
				HStack(spacing: DS.Space.s2) {
					Text(risk.axis.label)
						.dsText(.label11)
						.foregroundStyle(DS.textTertiary)
						.frame(width: 104, alignment: .leading)
					Text(risk.value)
						.dsText(.label11)
						.foregroundStyle(DS.textSecondary)
						.lineLimit(1)
					Spacer(minLength: DS.Space.s2)
					Circle()
						.fill(L2beatCopy.color(risk.sentiment))
						.frame(width: 7, height: 7)
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel(Text("\(risk.axis.label): \(risk.value), \(L2beatCopy.label(risk.sentiment))"))
			}
		}
	}
}

/// A milestone, or a revision — both are things that happened on a day.
struct L2beatNewsRow: View {
	let thing: Thing
	/// The chains the person said they use. Handed in rather than looked up here: a row must
	/// not fetch, and the room already holds the watch rows it would fetch. Empty for a
	/// follower who watches nothing, which is the common case and correctly draws no marker.
	var watchedChains: Set<String> = []

	var body: some View {
		if thing.isLive { liveBody }
	}

	@ViewBuilder private var liveBody: some View {
		let isIncident = thing.tags.contains(L2beatNewsParse.incidentTag)
		let chainID = thing.authorHandle
		let project = chainID.flatMap { L2beatState.best($0) }
		let mine = chainID.map { watchedChains.contains($0) } ?? false

		HStack(alignment: .top, spacing: DS.Space.s3) {
			// Every other room's rows lead with a disc. The chain's own mark where the
			// milestone names one, and a neutral glyph where it does not.
			ZStack(alignment: .bottomTrailing) {
				if let project {
					L2beatMark(name: project.name, chainID: project.id, size: 38)
				} else {
					RoundedRectangle(cornerRadius: 38 * 0.28, style: .continuous)
						.fill(DS.surfaceWell)
						.frame(width: 38, height: 38)
						.overlay(
							Image(systemName: "square.stack.3d.up")
								.dsGlyph(15)
								.foregroundStyle(DS.textTertiary)
						)
				}
				// Only an INCIDENT earns a state dot. A launch or an upgrade wearing one would
				// make every row in a mostly-good timeline look like an alert.
				if isIncident {
					Circle()
						.fill(DS.attention)
						.frame(width: 11, height: 11)
						.overlay(Circle().strokeBorder(DS.page, lineWidth: 2.5))
						.offset(x: 3, y: 3)
				}
			}
			.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: DS.Space.s2) {
				HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
					Text(thing.title)
						.dsText(.body17)
						.foregroundStyle(DS.textPrimary)
						.fixedSize(horizontal: false, vertical: true)
					Spacer(minLength: DS.Space.s2)
					LiveTimeText(date: thing.capturedAt)
				}

				if let summary = thing.summary, !summary.isEmpty {
					Text(summary)
						.dsText(.subhead13)
						.foregroundStyle(DS.textSecondary)
						.lineLimit(3)
						.fixedSize(horizontal: false, vertical: true)
				}

				HStack(spacing: DS.Space.s2) {
					// LEADS the strip, because it is the fact that decides whether this row is
					// about you at all — an incident on Base reads identically to one on a
					// chain you have never touched, and the tag saying "Base" cannot tell them
					// apart. In the tint rather than `DS.attention`, which in this row means
					// "L2BEAT calls this an incident" and must keep meaning only that.
					if mine {
						Text(String(localized: "You watch this"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.tint)
					}
					if isIncident {
						Text(String(localized: "Incident"))
							.dsText(.label11).fontWeight(.bold)
							.foregroundStyle(DS.attention)
					}
					ForEach(thing.tags.filter { $0 != L2beatNewsParse.incidentTag }, id: \.self) { tag in
						Text(tag)
							.dsText(.label11)
							.foregroundStyle(DS.textTertiary)
					}
				}
			}
		}
	}
}
