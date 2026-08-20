import Foundation

// Which anatomy a Walletbeat thing's sheet draws (prd §419 amendment).
//
// Foundation-only, the `NoteSheet` split: the judgement lives here where
// `scripts/walletbeat-selftest.sh` compiles it whole, and everything that touches `Thing`
// lives in `WalletbeatSheetSource`.
//
// WHY THREE ANATOMIES. The room holds three genuinely different records and the generic
// `.link` sheet served all of them the same way — a title, a URL and some tags. A watched
// wallet is a STANDING REVIEW with no date worth showing; an incident is something that
// HAPPENED, with a severity, a status and citations; a revision is a note that somebody
// CHANGED THEIR MIND, which is only meaningful as before-and-after. Drawing all three
// alike is the §313 X-room failure — a wall of undifferentiated rows over data that
// deserved better — one layer further in.

enum WalletbeatSheet {
	enum Shape: String, Equatable, Sendable {
		/// A wallet you watch — its report card, in place of a link to a website.
		case wallet
		/// A security incident Walletbeat published.
		case incident
		/// Walletbeat revising one of its own ratings.
		case revision
	}

	/// The only facts the decision needs. A value type, so the pure half never sees a model.
	struct Facts: Equatable, Sendable {
		var source: String
		var sourceRef: String?
		/// Our own note about a sync is not one of these records — it keeps the plain band
		/// in the room and the plain sheet here, the way every other room treats its
		/// receipt.
		var isImportReceipt: Bool = false
	}

	/// The shape, or nil when this thing is not one we draw.
	///
	/// Decided on the REF NAMESPACE rather than on the kind: all three records land as
	/// `.link`, so a kind test could not tell them apart, and the namespace is the thing
	/// the landing actually guarantees.
	static func shape(_ f: Facts) -> Shape? {
		guard f.source == WalletbeatIdentity.source, !f.isImportReceipt else { return nil }
		guard let ref = f.sourceRef else { return nil }
		if ref.hasPrefix(WalletbeatIdentity.walletPrefix) { return .wallet }
		if ref.hasPrefix(WalletbeatIdentity.newsPrefix) { return .incident }
		if ref.hasPrefix(WalletbeatIdentity.revisionPrefix) { return .revision }
		return nil
	}

	/// A revision's before/after, read back out of its own ref.
	///
	/// The ref is `walletbeat:rev:<wallet>:<attribute>:<verdict>:<date>` — written by
	/// `WalletbeatIngest.revisionRef` and parsed only here, so the two halves are one
	/// grammar rather than two hardcoded spellings (§311's lesson: a producer and a
	/// consumer that disagree make the surface go QUIET rather than break).
	struct Revision: Equatable, Sendable {
		var walletID: String
		var attributeID: String
		var after: WalletbeatVerdict
		var day: String?
	}

	static func revision(fromRef ref: String) -> Revision? {
		guard ref.hasPrefix(WalletbeatIdentity.revisionPrefix) else { return nil }
		let body = String(ref.dropFirst(WalletbeatIdentity.revisionPrefix.count))
		let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
		guard parts.count >= 3 else { return nil }
		guard let verdict = WalletbeatVerdict(rawValue: parts[2]) else { return nil }
		let day = parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil
		guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
		return Revision(walletID: parts[0], attributeID: parts[1], after: verdict, day: day)
	}
}

/// The ref grammar, in one place.
///
/// Hoisted out of `WalletbeatWatch` (which needs SwiftData) so the pure half can read the
/// same constants the landing writes. `WalletbeatWatch` forwards to these rather than
/// re-declaring them — two spellings of a ref prefix is exactly the §311 bug.
enum WalletbeatIdentity {
	static let source = "Walletbeat"
	static let seatID = "walletbeat"
	static let walletPrefix = "walletbeat:wallet:"
	static let newsPrefix = "walletbeat:news:"
	static let revisionPrefix = "walletbeat:rev:"
}
