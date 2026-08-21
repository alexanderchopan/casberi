import Foundation
import SwiftData

/// The half of the L2BEAT sheet decision that touches `Thing` (prd §428).
///
/// `L2beatSheet` holds the judgement and is Foundation-only, so the harness compiles it
/// whole; everything here reads models and is guarded at the boundary.
enum L2beatSheetSource {
	/// Which anatomy this thing's sheet draws, or nil for the generic one.
	///
	/// Reads stored properties, so every caller must already hold a live model — which the
	/// sheet does: its `init` and its `body` both guard before this is reached.
	@MainActor
	static func shape(for thing: Thing) -> L2beatSheet.Shape? {
		L2beatSheet.shape(facts(for: thing))
	}

	@MainActor
	static func facts(for thing: Thing) -> L2beatSheet.Facts {
		L2beatSheet.Facts(
			source: thing.source,
			sourceRef: thing.sourceRef,
			isImportReceipt: Corpus.isImportReceipt(thing))
	}

	/// The chain a row is about, from the freshest reading available.
	@MainActor
	static func project(for thing: Thing) -> L2beatProject? {
		guard let id = thing.authorHandle, !id.isEmpty else { return nil }
		return L2beatState.best(id)
	}

	/// The milestones on record for one chain, newest first.
	///
	/// Joined on `authorHandle` — the L2BEAT project id the landing stamps — and never on the
	/// title: "Base" appears inside plenty of sentences that are not about Base.
	@MainActor
	static func milestones(forChain chainID: String, context: ModelContext,
						   limit: Int = 4) -> [KeyedThing] {
		let source = L2beatIdentity.source
		var descriptor = FetchDescriptor<Thing>(
			predicate: #Predicate<Thing> {
				$0.source == source && $0.authorHandle == chainID
			},
			sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
		// Bounded: a risk card is drawn on every open and this is a second query behind the
		// assessment read. Four is what the card shows.
		descriptor.fetchLimit = 32
		let rows = ((try? context.fetch(descriptor)) ?? []).live
		return rows
			.filter { L2beatWatch.isNewsRef($0.sourceRef) }
			.prefix(limit)
			.map(KeyedThing.init)
	}

	/// The risk a revision names, resolved against the stored assessment so the sheet can
	/// show what L2BEAT actually says about it now.
	///
	/// Returns nil rather than guessing when nothing has been read for the chain — a revision
	/// row can outlive the assessment it describes (those are forgotten on unwatch), and
	/// inventing a reading from an axis name would state a verdict nobody made.
	@MainActor
	static func revisionSubject(for thing: Thing) -> (L2beatSheet.Revision, L2beatProject?, L2beatRisk?)? {
		guard let ref = thing.sourceRef,
			let revision = L2beatSheet.revision(fromRef: ref)
		else { return nil }
		let project = L2beatState.best(revision.projectID)
		let risk = revision.axis.flatMap { axis in project?.risk(axis) }
		return (revision, project, risk)
	}
}
