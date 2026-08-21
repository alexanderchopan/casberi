import Foundation

// Which anatomy an L2BEAT thing's sheet draws (prd §428).
//
// Foundation-only, the `NoteSheet`/`WalletbeatSheet` split: the judgement lives here where
// `scripts/l2beat-selftest.sh` compiles it whole, and everything that touches `Thing` lives
// in `L2beatSheetSource`.
//
// WHY THREE ANATOMIES. The room holds three genuinely different records and the generic
// `.link` sheet serves all of them the same way — a title, a URL and some tags. A watched
// chain is a STANDING ASSESSMENT with no date worth showing; a milestone is something that
// HAPPENED, with a kind and a citation; a revision is a note that somebody CHANGED THEIR
// MIND, which is only meaningful as before-and-after. Drawing all three alike is the §313
// X-room failure one layer further in.

enum L2beatSheet {
	enum Shape: String, Equatable, Sendable {
		/// A chain you watch — its risk card, in place of a link to a website.
		case chain
		/// A milestone or incident L2BEAT recorded.
		case milestone
		/// L2BEAT revising one of its own readings, or moving a chain's stage.
		case revision
	}

	/// The only facts the decision needs. A value type, so the pure half never sees a model.
	struct Facts: Equatable, Sendable {
		var source: String
		var sourceRef: String?
		/// Our own note about a sync is not one of these records — it keeps the plain band
		/// in the room and the plain sheet here, the way every other room treats its receipt.
		var isImportReceipt: Bool = false
	}

	/// The shape, or nil when this thing is not one we draw.
	///
	/// Decided on the REF NAMESPACE rather than on the kind: all three records land as
	/// `.link`, so a kind test could not tell them apart, and the namespace is the thing the
	/// landing actually guarantees.
	static func shape(_ f: Facts) -> Shape? {
		guard f.source == L2beatIdentity.source, !f.isImportReceipt else { return nil }
		guard let ref = f.sourceRef else { return nil }
		if ref.hasPrefix(L2beatIdentity.chainPrefix) { return .chain }
		if ref.hasPrefix(L2beatIdentity.newsPrefix) { return .milestone }
		if ref.hasPrefix(L2beatIdentity.revisionPrefix) { return .revision }
		return nil
	}

	/// A revision's subject, read back out of its own ref.
	///
	/// The ref is `l2beat:rev:<project>:<axis-or-stage>:<after>:<day>` — written by
	/// `L2beatIngest.revisionRef` and parsed only here, so the two halves are one grammar
	/// rather than two hardcoded spellings (§311's lesson: a producer and a consumer that
	/// disagree make the surface go QUIET rather than break).
	struct Revision: Equatable, Sendable {
		var projectID: String
		/// The axis this revision names, or nil when it is a stage move.
		var axis: L2beatRiskAxis?
		/// L2BEAT's new reading — a sentiment for a risk revision, a stage for a stage move.
		var afterSentiment: L2beatSentiment?
		var afterStage: L2beatStage?
		var day: String?

		var isStageMove: Bool { afterStage != nil }
	}

	/// The token a stage revision writes where a risk revision writes its axis.
	static let stageSubject = "stage"

	static func revision(fromRef ref: String) -> Revision? {
		guard ref.hasPrefix(L2beatIdentity.revisionPrefix) else { return nil }
		let body = String(ref.dropFirst(L2beatIdentity.revisionPrefix.count))
		let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
		guard parts.count >= 3, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
		let day = parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil

		if parts[1] == stageSubject {
			// A stage's own raw value carries a space ("Stage 1"), which cannot ride a
			// colon-separated ref, so the landing writes the rung and this reads it back.
			guard let stage = stage(fromToken: parts[2]) else { return nil }
			return Revision(projectID: parts[0], axis: nil, afterSentiment: nil,
							afterStage: stage, day: day)
		}
		guard let axis = L2beatRiskAxis(rawValue: parts[1]) else { return nil }
		guard let sentiment = L2beatSentiment(rawValue: parts[2]) else { return nil }
		return Revision(projectID: parts[0], axis: axis, afterSentiment: sentiment,
						afterStage: nil, day: day)
	}

	/// `Stage 1` → `stage1`, so a stage can ride a colon-separated ref without its space.
	static func token(for stage: L2beatStage) -> String {
		switch stage {
		case .stage0: return "stage0"
		case .stage1: return "stage1"
		case .stage2: return "stage2"
		case .notApplicable: return "unstaged"
		}
	}

	static func stage(fromToken token: String) -> L2beatStage? {
		switch token {
		case "stage0": return .stage0
		case "stage1": return .stage1
		case "stage2": return .stage2
		case "unstaged": return .notApplicable
		default: return nil
		}
	}
}

/// The ref grammar, in one place.
///
/// Hoisted out of `L2beatWatch` (which needs SwiftData) so the pure half can read the same
/// constants the landing writes. `L2beatWatch` forwards to these rather than re-declaring
/// them — two spellings of a ref prefix is exactly the §311 bug.
enum L2beatIdentity {
	static let source = "L2BEAT"
	static let seatID = "l2beat"
	static let chainPrefix = "l2beat:chain:"
	static let newsPrefix = "l2beat:news:"
	static let revisionPrefix = "l2beat:rev:"
}
