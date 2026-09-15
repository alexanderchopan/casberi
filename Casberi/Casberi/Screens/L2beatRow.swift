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
		let project = chainID.flatMap { L2beatState.best($0) }

		// ONE ANATOMY (prd §744): the 38pt mark is the 26pt lead, the stage
		// takes the trailing slot, the risks and the summary are the content.
		DSFeedRow(name: project?.name ?? thing.title, nameLines: 1,
				  line: Text(subtitle(project))) {
			L2beatMark(name: project?.name ?? thing.title, chainID: chainID, size: DS.Mark.row)
		} trailing: {
			L2beatStageChip(stage: project?.stage)
		} below: {
			VStack(alignment: .leading, spacing: DS.Space.s2) {
				if let project, !project.risks.isEmpty {
					riskLines(project)
				}
				if let summary = thing.summary, !summary.isEmpty {
					Text(summary)
						.dsText(.subhead13)
						.foregroundStyle(DS.textSecondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(.top, DS.Space.s1)
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
		let tags = thing.tags.filter { $0 != L2beatNewsParse.incidentTag }

		// ONE ANATOMY (prd §744): as `WalletbeatNewsRow`.
		DSFeedRow(name: thing.title, nameLines: 3,
				  line: DSFeed.line(thing.summary), lineLines: 3) {
			ZStack(alignment: .bottomTrailing) {
				if let project {
					L2beatMark(name: project.name, chainID: project.id, size: DS.Mark.row)
				} else {
					RoundedRectangle(cornerRadius: DS.Mark.row * 0.28, style: .continuous)
						.fill(DS.surfaceWell)
						.frame(width: DS.Mark.row, height: DS.Mark.row)
						.overlay(
							Image(systemName: "square.stack.3d.up")
								.dsGlyph(11)
								.foregroundStyle(DS.textTertiary)
						)
				}
				if isIncident {
					Circle()
						.fill(DS.attention)
						.frame(width: 9, height: 9)
						.overlay(Circle().strokeBorder(DS.surfaceListRow, lineWidth: 2))
						.offset(x: 3, y: 3)
				}
			}
			.accessibilityHidden(true)
		} trailing: {
			LiveTimeText(date: thing.capturedAt)
		} below: {
			if mine || isIncident || !tags.isEmpty {
				HStack(spacing: DS.Space.s2) {
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
					ForEach(tags, id: \.self) { tag in
						Text(tag)
							.dsText(.label11)
							.foregroundStyle(DS.textTertiary)
					}
				}
				.padding(.top, DS.Space.s1)
			}
		}
	}
}
