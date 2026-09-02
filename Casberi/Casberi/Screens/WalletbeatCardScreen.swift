import SwiftData
import SwiftUI

/// One wallet's report card (prd §419) — the feature's primary surface.
///
/// EVERY ATTRIBUTE IS SHOWN, in Walletbeat's own order, with Walletbeat's own sentence.
/// Nothing is selected, ranked or summarised: the only editorial act available here would
/// be choosing which findings matter, and that is exactly the act this feature refuses.
/// The one ordering choice — failures first inside each dimension — is stated below.
///
/// SPLIT FROM ITS SCREEN so a watched wallet's THING SHEET draws the same card (§419
/// amendment). Before that split the feed's own rows opened a generic link sheet while the
/// feature's primary surface was reachable only from the setup screen and the directory —
/// the room could not reach its own report card.
struct WalletbeatReportCard: View {
	let walletID: String
	/// The sheet embeds this without its own navigation chrome; the screen wraps it.
	var showsHeader = true
	/// Handed in only where there is a sheet to close before the composer rises.
	var onDismissForAsk: (() -> Void)?

	@Environment(\.modelContext) private var modelContext
	@Environment(BridgeStore.self) private var store
	@Environment(ShellChrome.self) private var chrome

	@State private var card: WalletbeatCard?
	@State private var loading = false
	@State private var failed = false
	@State private var watching = false
	@State private var incidents: [KeyedThing] = []
	/// What Walletbeat has changed its mind about since this device started watching,
	/// keyed by attribute (prd §430). Empty for an unwatched wallet, which is correct —
	/// nothing was ever read to compare against.
	@State private var revised: [String: WalletbeatSheet.Revision] = [:]

	private var entry: WalletbeatEntry? {
		WalletbeatDirectory.wallets.first { $0.id == walletID }
	}

	var name: String { card?.name ?? entry?.name ?? walletID }
	private var counts: WalletbeatCounts { card?.overall ?? entry?.overall ?? .zero }

	var body: some View {
		ScrollViewReader { proxy in
			VStack(alignment: .leading, spacing: DS.Space.s4) {
				if showsHeader { header }
				if WalletbeatCoverage.of(counts).showsShape {
					dimensionSummary(proxy: proxy)
				} else {
					unexaminedNote
				}
				if !incidents.isEmpty { incidentCrossLink }
				if let card {
					ForEach(card.dimensions, id: \.self) { dimension in
						dimensionSection(card: card, dimension: dimension)
							.id(Self.anchor(dimension))
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
		}
		.task { await load() }
	}

	static func anchor(_ dimension: WalletbeatDimension) -> String {
		"walletbeat.dim.\(dimension.rawValue)"
	}

	// MARK: - Head

	private var header: some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			HStack(spacing: DS.Space.s3) {
				WalletbeatMark(name: name, walletID: walletID, size: 48)
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

	/// Watching is the verb this surface offers. Never a second control that would
	/// duplicate the directory's — one place to say yes.
	var watchVerb: some View {
		Button(action: toggleWatch) {
			Text(watching
				? String(localized: "Watching — tap to stop")
				: String(localized: "Watch this wallet"))
				.dsText(.subhead13).fontWeight(.semibold)
				.foregroundStyle(watching ? DS.textTertiary : DS.tint)
		}
		.buttonStyle(.plain)
		.dsHover()
	}

	private var subtitleLine: String {
		var parts: [String] = []
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

	private func dimensionSummary(proxy: ScrollViewProxy) -> some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			Text(WalletbeatCopy.coverage(counts))
				.dsText(.label12).fontWeight(.semibold)
				.foregroundStyle(DS.textSecondary)

			ForEach(dimensions, id: \.self) { dimension in
				let counts = dimensionCounts(dimension)
				Button {
					DSHaptic.tap()
					withAnimation(DS.Motion.standard) {
						proxy.scrollTo(Self.anchor(dimension), anchor: .top)
					}
				} label: {
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
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				// A bar is tappable only once the attributes it summarises exist to scroll
				// to. Before the live read lands there is no anchor, and a control that
				// does nothing is the dead control §83 bans.
				.disabled(card == nil)
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

	/// What the ratings cannot say: whether anything has actually gone wrong.
	///
	/// A rating is a standing judgment and an incident is an event, so neither substitutes
	/// for the other — a wallet can rate well and still have been breached last week.
	private var incidentCrossLink: some View {
		VStack(alignment: .leading, spacing: DS.Space.s2) {
			Text(String(localized: "On record"))
				.dsText(.label11).fontWeight(.semibold)
				.foregroundStyle(DS.textTertiary)
			ForEach(incidents) { row in
				if let thing = row.live {
					HStack(alignment: .top, spacing: DS.Space.s3) {
						Circle()
							.fill(thing.tags.contains(WalletbeatNewsParse.openTag)
								? DS.attention : DS.confirm)
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

	// MARK: - Attributes

	/// One card per DIMENSION, with its attributes as gapless rows inside it.
	///
	/// The first cut gave every attribute its own `dsWidgetSurface`, which for a
	/// well-rated wallet is twenty-nine floating shadows down one screen. The elevation
	/// ladder (§61) says a grouped section lifts as ONE card and its interior rows
	/// separate by spacing — never by lines, and never by their own shadows.
	@ViewBuilder
	private func dimensionSection(card: WalletbeatCard, dimension: WalletbeatDimension) -> some View {
		let attributes = ordered(card.attributes(in: dimension))
		if !attributes.isEmpty {
			VStack(alignment: .leading, spacing: DS.Space.s3) {
				Text(dimension.label)
					.dsText(.heading17)
					.foregroundStyle(DS.textPrimary)
				VStack(alignment: .leading, spacing: DS.Space.s4) {
					ForEach(attributes) { attribute in
						WalletbeatAttributeRow(attribute: attribute,
											   revision: revised[attribute.id])
					}
				}
				.padding(DS.Space.s4)
				.frame(maxWidth: .infinity, alignment: .leading)
				.dsWidgetSurface()
			}
			.padding(.top, DS.Space.s2)
		}
	}

	/// Failures first, then partials, then passes, then the unrated.
	///
	/// The ONE re-ordering here. It is a reading order, not a ranking: everything is shown,
	/// nothing is hidden or scored, and within each band Walletbeat's own attribute order
	/// is preserved (the enumerated offset is the tiebreak, so the sort is total and the
	/// card cannot reshuffle between opens).
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

	// MARK: - Foot

	private var footer: some View {
		VStack(alignment: .leading, spacing: DS.Space.s3) {
			if let onDismissForAsk {
				Button {
					DSHaptic.tap()
					// Dismiss first: the composer rises over the shell, and a sheet still
					// up would sit between them.
					onDismissForAsk()
					chrome.ask(String(localized: "What does Walletbeat say about \(name)?"),
							   withKey: AgentKey.isConfigured)
				} label: {
					Chip(text: AgentKey.active.map { String(localized: "Ask \($0.agent) about this") }
						?? String(localized: "Ask about this"),
						 style: .neutral, glyph: "sparkles")
				}
				.buttonStyle(.plain)
				.dsHover()
			}
			if let url = entry?.pageURL ?? URL(string: "https://\(WalletbeatHost.site)/\(walletID)/") {
				Link(destination: url) {
					Text(String(localized: "Full review on Walletbeat"))
						.dsText(.subhead13).fontWeight(.semibold)
						.foregroundStyle(DS.tint)
				}
			}
			Text(WalletbeatCopy.attribution)
				.dsText(.label11)
				.foregroundStyle(DS.textTertiary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.top, DS.Space.s2)
	}

	// MARK: - Data

	private var dimensions: [WalletbeatDimension] {
		card?.dimensions ?? entry?.dimensions ?? []
	}

	private func dimensionCounts(_ dimension: WalletbeatDimension) -> WalletbeatCounts {
		card?.counts(in: dimension) ?? entry?.counts[dimension] ?? .zero
	}

	private func load() async {
		watching = WalletbeatWatch.watchedIDs(context: modelContext).contains(walletID)
		incidents = WalletbeatSheetSource.incidents(forWallet: walletID, context: modelContext)
		revised = WalletbeatSheetSource.revisions(forWallet: walletID, context: modelContext)
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

/// One attribute: Walletbeat's question, their verdict, their sentence — and, on tap,
/// their own answer to why the question is worth asking at all.
struct WalletbeatAttributeRow: View {
	let attribute: WalletbeatAttribute
	/// Walletbeat changing its mind about THIS attribute, if this device saw it happen
	/// (prd §430). Nil is the common case and draws nothing.
	var revision: WalletbeatSheet.Revision?

	@State private var expanded = false

	var body: some View {
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

			// WHAT MOVED, and when. Last, because it is a fact about the verdict's
			// HISTORY and everything above it is the verdict itself — a reader wants to
			// know what Walletbeat says before they want to know when it changed.
			//
			// Their date and their words for both verdicts; nothing here is our reading
			// of the change. A revision with no recorded before says only that it moved,
			// rather than reaching for the card as it stands today to fill the gap —
			// that would be a different moment's verdict wearing this one's date.
			if let revision {
				Text(Self.revisedLine(revision))
					.dsText(.label11)
					.foregroundStyle(DS.textTertiary)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, DS.Space.s1)
			}

			if let why = attribute.whyItMatters, !why.isEmpty {
				if expanded {
					// Their prose carries markdown links, so it is SET as markdown rather
					// than printed with its own punctuation showing — §399's ruling, one
					// room over. An unparseable string falls back to itself.
					Text(WalletbeatProse.attributed(why))
						.dsText(.subhead13)
						.foregroundStyle(DS.textSecondary)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.top, DS.Space.s1)
				} else {
					Button {
						withAnimation(DS.Motion.standard) { expanded = true }
					} label: {
						// Says HOW MUCH, never a bare "more" — the disclosure convention
						// this app already keeps for a folded note.
						Text(String(localized: "Why this matters — \(WalletbeatProse.words(why)) words"))
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

	/// "Walletbeat changed this from Partly on 22 Jul 2026".
	///
	/// The day is Walletbeat's own `lastUpdated` string. It is FORMATTED when it parses
	/// and printed verbatim when it does not — their spelling of a date is readable
	/// either way, and dropping it would be losing the fact to tidy the sentence.
	static func revisedLine(_ revision: WalletbeatSheet.Revision) -> String {
		let when = revision.day.map { raw -> String in
			WalletbeatNewsParse.day(raw).map { Self.day.string(from: $0) } ?? raw
		}
		switch (revision.before, when) {
		case (let before?, let when?):
			return String(localized: "Walletbeat changed this from \(WalletbeatCopy.label(before)) on \(when)")
		case (let before?, nil):
			return String(localized: "Walletbeat changed this from \(WalletbeatCopy.label(before))")
		case (nil, let when?):
			return String(localized: "Walletbeat revised this on \(when)")
		case (nil, nil):
			return String(localized: "Walletbeat has revised this")
		}
	}

	private static let day: DateFormatter = {
		let f = DateFormatter()
		f.dateStyle = .medium
		f.timeStyle = .none
		return f
	}()
}

/// Walletbeat's prose, rendered.
enum WalletbeatProse {
	static func words(_ text: String) -> Int {
		text.split(whereSeparator: \.isWhitespace).count
	}

	/// Their markdown as an `AttributedString`, falling back to the plain string.
	///
	/// `.inlineOnlyPreservingWhitespace` deliberately: this is one paragraph inside a row,
	/// so block parsing would swallow the line structure the row already controls.
	static func attributed(_ text: String) -> AttributedString {
		(try? AttributedString(
			markdown: text,
			options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
			?? AttributedString(text)
	}
}

/// The report card as its own screen — what the directory and the setup roster open.
struct WalletbeatCardScreen: View {
	let walletID: String

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ScrollView {
				WalletbeatReportCard(walletID: walletID, onDismissForAsk: { dismiss() })
					.padding(DS.Space.s4)
			}
			.dsPageBackground()
			.dsSoftScrollEdges()
			.navigationTitle(
				WalletbeatDirectory.wallets.first { $0.id == walletID }?.name ?? walletID)
			.navigationBarTitleDisplayMode(.inline)
			.dsSheetDismiss { dismiss() }
		}
		.dsNavSheet()
	}
}
