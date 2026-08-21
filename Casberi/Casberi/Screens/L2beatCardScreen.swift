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
	/// Handed in only by a host that OWNS the scroll this card sits inside — which is the
	/// screen and not the thing sheet. Absent, the strip key is a legend rather than a
	/// control, because a cell that looks tappable and cannot move anything is exactly the
	/// dead control §83 bans.
	var onScrollToAxis: ((L2beatRiskAxis) -> Void)?

	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store
	@Environment(ShellChrome.self) private var chrome

	@State private var project: L2beatProject?
	@State private var loading = false
	@State private var failed = false
	@State private var watching = false
	@State private var milestones: [KeyedThing] = []
	@State private var live = false
	/// The axis picked off the strip key, so the key and the row it scrolled to agree about
	/// where you are.
	@State private var focusedAxis: L2beatRiskAxis?
	/// ONE toggle for all five rows, not five links (see `riskSection`).
	@State private var showsAsks = false

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
			// THE KEYED strip, and only here. Every other surface draws the bare five cells,
			// whose whole design is that the same question is always in the same place —
			// and until this landed nothing in the app said which place. This is where that
			// is learned, one card above the five rows it summarises.
			L2beatStripKey(risks: project.orderedRisks,
						   onPick: axisPick,
						   focused: focusedAxis)
				.padding(.top, DS.Space.s1)
			legend
		}
		.padding(DS.Space.s4)
		.frame(maxWidth: .infinity, alignment: .leading)
		.dsWidgetSurface()
	}

	/// What a tap on the strip key does — remember the axis, then ask the host to scroll.
	/// Nil where no host can, which is what keeps the key from being a dead control.
	private var axisPick: ((L2beatRiskAxis) -> Void)? {
		guard let onScrollToAxis else { return nil }
		return { axis in
			withAnimation(DS.Motion.standard) { focusedAxis = axis }
			onScrollToAxis(axis)
		}
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
	///
	/// EVERY ROW CARRIES ITS DAY, and that is a fix rather than a nicety: recency is the
	/// load-bearing fact of a section whose whole argument is "and then this happened", and
	/// this card listed a 2021 exploit and last month's halt in one undated voice with
	/// nothing to tell them apart. The date sits on the row rather than in a sort note
	/// because a reader placing an event needs the year, not the rank.
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
						VStack(alignment: .leading, spacing: 1) {
							Text(thing.title)
								.dsText(.subhead13)
								.foregroundStyle(DS.textSecondary)
								.lineLimit(2)
								.fixedSize(horizontal: false, vertical: true)
							Text(L2beatCopy.day(thing.capturedAt))
								.dsText(.label11)
								.foregroundStyle(DS.textTertiary)
						}
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
	/// ONE TOGGLE, NOT FIVE LINKS. "What this asks" was repeated on every row, so the card's
	/// most-repeated element was a control rather than a reading — five identical tinted
	/// lines competing with L2BEAT's five different sentences. It is one question asked once
	/// of the whole section, which is also what it actually is: the five lines behind it are
	/// about the QUESTIONS and never about this chain's answers, so they are either wanted
	/// together or not at all.
	@ViewBuilder
	private func riskSection(_ project: L2beatProject) -> some View {
		if !project.risks.isEmpty {
			VStack(alignment: .leading, spacing: DS.Space.s3) {
				HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
					Text(String(localized: "What L2BEAT checks"))
						.dsText(.heading17)
						.foregroundStyle(DS.textPrimary)
					Spacer(minLength: DS.Space.s2)
					Button {
						DSHaptic.tap()
						withAnimation(DS.Motion.standard) { showsAsks.toggle() }
					} label: {
						Text(showsAsks
							? String(localized: "Hide what these ask")
							: String(localized: "What these ask"))
							.dsText(.label11)
							.foregroundStyle(DS.tint)
					}
					.buttonStyle(.plain)
					.dsHover()
				}
				VStack(alignment: .leading, spacing: DS.Space.s4) {
					ForEach(project.orderedRisks) { risk in
						L2beatRiskRow(risk: risk,
									  showsAsks: showsAsks,
									  focused: focusedAxis == risk.axis)
							// The strip key's pick scrolls here. An explicit id rather than
							// the ForEach's own, so the anchor survives a change of identity
							// on `L2beatRisk`.
							.id(risk.axis)
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
	/// Owned by the SECTION, not the row — one question asked once of all five.
	var showsAsks = false
	/// This is the axis picked off the strip key. A soft fill, never a rule: the design law's
	/// no-hairlines ban is about lines that divide, and this is a selection.
	var focused = false

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

			// What the axis ASKS — ours, and the only text in this feature that is. Folded by
			// default so L2BEAT's own words lead every row, and unfolded by the section's one
			// toggle rather than by a link repeated five times down the card.
			if showsAsks {
				Text(risk.axis.asks)
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, DS.Space.s1)
			}
		}
		.padding(focused ? DS.Space.s2 : 0)
		.background(
			RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
				.fill(focused ? DS.fillFaint : .clear)
		)
	}
}

/// The risk card as its own screen — what the directory and the setup roster open.
///
/// It owns the scroll, so it is the one host that can answer a tap on the strip key. The
/// thing sheet embeds the same card inside a scroll it does not own and hands in nothing,
/// which is why `onScrollToAxis` is optional rather than assumed.
struct L2beatCardScreen: View {
	let chainID: String

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ScrollViewReader { proxy in
				ScrollView {
					L2beatRiskCard(
						chainID: chainID,
						onDismissForAsk: { dismiss() },
						// `.center`, not `.top`: the five rows read as a set, and pinning the
						// picked one to the top hides the four it is being compared against.
						onScrollToAxis: { axis in
							withAnimation(DS.Motion.standard) {
								proxy.scrollTo(axis, anchor: .center)
							}
						})
						.padding(DS.Space.s4)
				}
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
