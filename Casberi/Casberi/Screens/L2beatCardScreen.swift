import SwiftData
import SwiftUI

/// One chain's risk card (prd §428) — the feature's primary surface.
///
/// EVERY AXIS IS SHOWN, in L2BEAT's own order, with L2BEAT's own value and sentence.
/// Nothing is selected, ranked or summarised: the only editorial act available here would
/// be choosing which findings matter, and that is exactly the act this feature refuses.
///
/// AND THE ORDER IS NEVER RE-SORTED, which is where this diverges from §419 on purpose.
/// That card put a wallet's failures first inside each dimension, a defensible reading order
/// over twenty-nine ragged attributes. Here there are five, they are the same five on every
/// chain, and the strip beside every row in the app paints them in this exact order — so a
/// flagged-first card would break the one correspondence that lets somebody glance at a strip
/// and know which question is red without reading a word.
///
/// SPLIT FROM ITS SCREEN so a watched chain's THING SHEET draws the same card. Before that
/// split in §419's own history the feed's rows opened a generic link sheet while the
/// feature's primary surface was reachable only from setup — the room could not reach its
/// own card.
struct L2beatRiskCard: View {
	let chainID: String
	/// The sheet embeds this without its own navigation chrome; the screen wraps it.
	var showsHeader = true
	/// Handed in only where there is a sheet to close before the composer rises.
	var onDismissForAsk: (() -> Void)?

	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store
	@Environment(ShellChrome.self) private var chrome

	@State private var project: L2beatProject?
	@State private var loading = false
	@State private var failed = false
	@State private var watching = false
	@State private var milestones: [KeyedThing] = []
	@State private var live = false

	var name: String { project?.name ?? chainID }

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.s4) {
			if showsHeader { header }
			if let project {
				stageCard(project)
				if !milestones.isEmpty { milestoneCrossLink }
				riskSection(project)
			} else if loading {
				Text(String(localized: "Reading L2BEAT…"))
					.dsText(.subhead13)
					.foregroundStyle(DS.textTertiary)
			} else if failed {
				Text(String(localized: "Couldn't reach L2BEAT, and this chain isn't in the copy bundled with the app."))
					.dsText(.subhead13)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
			}
			footer
		}
		.task { await load() }
	}

	// MARK: - Head

	private var header: some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			HStack(spacing: DS.Space.s3) {
				L2beatMark(name: name, chainID: chainID, size: 48)
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
			watchVerb
		}
	}

	/// Watching is the verb this surface offers. Never a second control that would duplicate
	/// the directory's — one place to say yes.
	var watchVerb: some View {
		Button(action: toggleWatch) {
			Text(watching
				? String(localized: "Watching — tap to stop")
				: String(localized: "Watch this chain"))
				.dsText(.subhead13).fontWeight(.semibold)
				.foregroundStyle(watching ? DS.textTertiary : DS.tint)
		}
		.buttonStyle(.plain)
		.dsHover()
		.disabled(project == nil)
	}

	private var subtitleLine: String {
		guard let project else { return String(localized: "Reading L2BEAT…") }
		var parts: [String] = [project.layer.label]
		if let category = project.category, !category.isEmpty, category != "Other" {
			parts.append(category)
		}
		if let host = project.hostChain { parts.append(String(localized: "on \(host)")) }
		return parts.joined(separator: " · ")
	}

	// MARK: - Their stage

	/// L2BEAT's own composite, and the reason this feature never computes one.
	///
	/// The rung's MEANING carries the card, not its number: "Stage 1" is jargon from a
	/// methodology most readers have not read, and a number without its meaning is borrowed
	/// authority (§83). A chain they do not place on the ladder says so plainly rather than
	/// being shown as a zero.
	@ViewBuilder
	private func stageCard(_ project: L2beatProject) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			HStack(spacing: DS.Space.s2) {
				L2beatStageChip(stage: project.stage)
				if project.underReview {
					Text(String(localized: "Under review"))
						.dsText(.label11).fontWeight(.bold)
						.foregroundStyle(DS.attention)
				}
				Spacer(minLength: 0)
			}
			Text(project.stage?.meaning
				?? String(localized: "L2BEAT does not place this chain on its stage ladder."))
				.dsText(.body17)
				.foregroundStyle(DS.textPrimary)
				.fixedSize(horizontal: false, vertical: true)
			if project.underReview {
				Text(String(localized: "L2BEAT is re-examining this chain, so these readings may change."))
					.dsText(.subhead13)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			L2beatStrip(risks: project.orderedRisks, height: 10)
				.padding(.top, DS.Space.s1)
			legend
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	private var legend: some View {
		HStack(spacing: DS.Space.s3) {
			ForEach([L2beatSentiment.good, .warning, .bad], id: \.self) { sentiment in
				L2beatSentimentTag(sentiment: sentiment)
			}
			Spacer(minLength: 0)
		}
	}

	/// What the assessment cannot say: whether anything has actually gone wrong.
	///
	/// An assessment is a standing judgment and an incident is an event, so neither
	/// substitutes for the other — a chain can assess well and still have been halted
	/// last month.
	private var milestoneCrossLink: some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			Text(String(localized: "On record"))
				.dsText(.label11).fontWeight(.semibold)
				.foregroundStyle(DS.textTertiary)
			ForEach(milestones) { row in
				if let thing = row.live {
					HStack(alignment: .top, spacing: DS.Space.s3) {
						Circle()
							.fill(thing.tags.contains(L2beatNewsParse.incidentTag)
								? DS.attention : DS.fillStrong)
							.frame(width: 8, height: 8)
							.padding(.top, 6)
						Text(thing.title)
							.dsText(.subhead13)
							.foregroundStyle(DS.textSecondary)
							.lineLimit(2)
							.fixedSize(horizontal: false, vertical: true)
						Spacer(minLength: 0)
					}
				}
			}
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	// MARK: - The five

	/// ONE card, five gapless rows inside it.
	///
	/// The elevation ladder (§61): a grouped section lifts as ONE card and its interior rows
	/// separate by spacing — never by lines, and never by their own shadows.
	@ViewBuilder
	private func riskSection(_ project: L2beatProject) -> some View {
		if !project.risks.isEmpty {
			VStack(alignment: .leading, spacing: DS.Space.s3) {
				Text(String(localized: "What L2BEAT checks"))
					.dsText(.heading17)
					.foregroundStyle(DS.textPrimary)
				VStack(alignment: .leading, spacing: DS.Space.s4) {
					ForEach(project.orderedRisks) { risk in
						L2beatRiskRow(risk: risk)
					}
				}
				.padding(DS.Space.s4)
				.frame(maxWidth: .infinity, alignment: .leading)
				.dsWidgetSurface()
			}
			.padding(.top, DS.Space.s2)
		}
	}

	// MARK: - Foot

	private var footer: some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			if let onDismissForAsk {
				Button {
					DSHaptic.tap()
					// Dismiss first: the composer rises over the shell, and a sheet still up
					// would sit between them.
					onDismissForAsk()
					chrome.ask(String(localized: "What does L2BEAT say about \(name)?"),
							   withKey: AgentKey.isConfigured)
				} label: {
					Chip(text: AgentKey.active.map { String(localized: "Ask \($0.agent) about this") }
						?? String(localized: "Ask about this"),
						 style: .neutral, glyph: "sparkles")
				}
				.buttonStyle(.plain)
				.dsHover()
			}
			if let url = project?.pageURL {
				Link(destination: url) {
					Text(String(localized: "Full assessment on L2BEAT"))
						.dsText(.subhead13).fontWeight(.semibold)
						.foregroundStyle(DS.tint)
				}
			}
			Text(freshnessLine)
				.dsText(.label11)
				.foregroundStyle(DS.textTertiary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.top, DS.Space.s2)
	}

	/// States WHICH copy of L2BEAT's assessment this is.
	///
	/// A bundled reading and a freshly-read one look identical on screen, and the bundled one
	/// is exactly as current as the last app update — pretending otherwise is the quiet
	/// staleness §83 exists to prevent.
	private var freshnessLine: String {
		let attribution = String(localized: "Every reading here is L2BEAT's own, in their words. Casberi reads their public assessment and never rates a chain itself.")
		guard project != nil else { return attribution }
		return live
			? "\(attribution) \(String(localized: "Read on this device."))"
			: "\(attribution) \(String(localized: "Bundled with the app as of \(L2beatDirectory.generated)."))"
	}

	// MARK: - Data

	private func load() async {
		watching = L2beatWatch.watchedIDs(context: modelContext).contains(chainID)
		milestones = L2beatSheetSource.milestones(forChain: chainID, context: modelContext)
		// The bundled snapshot draws INSTANTLY and costs nothing; the live read replaces it
		// when the sweep has run. Both are shown the same way, because a bundled assessment
		// and a fresh one are equally L2BEAT's — only their date differs, and the footer says
		// which.
		if let stored = L2beatState.project(chainID) {
			project = stored
			live = true
			return
		}
		if let bundled = L2beatDirectory.project(chainID) { project = bundled }
		// Only reach out for a chain we have no copy of at all — a chain L2BEAT added since
		// this build shipped. One request fills all 105, so it is never made per card.
		guard project == nil, !loading else { return }
		loading = true
		defer { loading = false }
		let fresh = await L2beatFetch.summary()
		guard !fresh.isEmpty else { failed = true; return }
		var map = L2beatState.projects()
		for entry in fresh { map[entry.id] = entry }
		L2beatState.replace(map)
		L2beatState.summaryReadAt = .now
		if let hit = fresh.first(where: { $0.id == chainID }) {
			project = hit
			live = true
		} else {
			failed = true
		}
	}

	private func toggleWatch() {
		DSHaptic.tap()
		if watching {
			L2beatWatch.remove(chainID, context: modelContext)
			watching = false
		} else if let project {
			L2beatWatch.add(project, context: modelContext)
			watching = true
		}
		L2beatWatch.registerBridge(store: store, context: modelContext)
	}
}

/// One risk: L2BEAT's question, their reading, their sentence — and their own qualification
/// where they publish one.
struct L2beatRiskRow: View {
	let risk: L2beatRisk

	@State private var expanded = false

	var body: some View {
		VStack(alignment: .leading, spacing: DS.Space.s1 + 2) {
			HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
				Text(risk.axis.label)
					.dsText(.body17)
					.foregroundStyle(DS.textPrimary)
					.fixedSize(horizontal: false, vertical: true)
				Spacer(minLength: DS.Space.s2)
				L2beatSentimentTag(sentiment: risk.sentiment)
			}

			// L2BEAT's own word for this reading — "Self sequence", "No mechanism", "10d".
			// It leads the sentence because it is the answer, and the sentence is the
			// reasoning behind it.
			Text(risk.value)
				.dsText(.subhead13).fontWeight(.semibold)
				.foregroundStyle(DS.textSecondary)

			if !risk.explanation.isEmpty {
				Text(risk.explanation)
					.dsText(.subhead13)
					.foregroundStyle(DS.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			// Their own qualification, drawn UNDER the headline reading and never merged
			// into it. Measured 2026-08-21 this is Arbitrum's ten-day exit window sitting
			// beneath an emergency case L2BEAT rates "None" — two readings they publish
			// together, and showing either alone misstates them.
			if let second = risk.second {
				HStack(alignment: .top, spacing: DS.Space.s2) {
					Circle()
						.fill(L2beatCopy.color(second.sentiment))
						.frame(width: 6, height: 6)
						.padding(.top, 6)
					VStack(alignment: .leading, spacing: 1) {
						Text(second.value)
							.dsText(.label11).fontWeight(.semibold)
							.foregroundStyle(DS.textSecondary)
						if let text = second.explanation, !text.isEmpty {
							Text(text)
								.dsText(.label11)
								.foregroundStyle(DS.textTertiary)
								.fixedSize(horizontal: false, vertical: true)
						}
					}
				}
				.padding(.top, DS.Space.s1)
			}

			// What the axis ASKS — ours, and the only text in this feature that is. Folded
			// by default so L2BEAT's own words lead every row.
			if expanded {
				Text(risk.axis.asks)
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, DS.Space.s1)
			} else {
				Button {
					withAnimation(DS.Motion.standard) { expanded = true }
				} label: {
					Text(String(localized: "What this asks"))
						.dsText(.label11)
						.foregroundStyle(DS.tint)
				}
				.buttonStyle(.plain)
				.dsHover()
				.padding(.top, DS.Space.s1)
			}
		}
	}
}

/// The risk card as its own screen — what the directory and the setup roster open.
struct L2beatCardScreen: View {
	let chainID: String

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ScrollView {
				L2beatRiskCard(chainID: chainID, onDismissForAsk: { dismiss() })
					.padding(DS.Space.s4)
			}
			.dsPageBackground()
			.dsSoftScrollEdges()
			.navigationTitle(L2beatState.best(chainID)?.name ?? chainID)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String(localized: "Done")) { dismiss() }
				}
			}
		}
		.dsPageSheet()
	}
}
