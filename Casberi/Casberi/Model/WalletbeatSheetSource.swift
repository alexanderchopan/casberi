import Foundation
import SwiftData

/// The half of the Walletbeat sheet decision that touches `Thing` (prd §419 amendment).
///
/// `WalletbeatSheet` holds the judgement and is Foundation-only, so the harness compiles
/// it whole; everything here reads models and is guarded at the boundary.
enum WalletbeatSheetSource {
	/// Which anatomy this thing's sheet draws, or nil for the generic one.
	///
	/// Reads stored properties, so every caller must already hold a live model — which the
	/// sheet does: its `init` and its `body` both guard before this is reached.
	@MainActor
	static func shape(for thing: Thing) -> WalletbeatSheet.Shape? {
		WalletbeatSheet.shape(facts(for: thing))
	}

	@MainActor
	static func facts(for thing: Thing) -> WalletbeatSheet.Facts {
		WalletbeatSheet.Facts(
			source: thing.source,
			sourceRef: thing.sourceRef,
			isImportReceipt: Corpus.isImportReceipt(thing))
	}

	/// The incidents on record for one wallet, newest first.
	///
	/// Joined on `authorHandle` — the Walletbeat wallet id the landing stamps — and never
	/// on the title: "Ledger" appears inside plenty of sentences that are not about Ledger.
	@MainActor
	static func incidents(forWallet walletID: String, context: ModelContext,
						  limit: Int = 4) -> [KeyedThing] {
		let source = WalletbeatIdentity.source
		var descriptor = FetchDescriptor<Thing>(
			predicate: #Predicate<Thing> {
				$0.source == source && $0.authorHandle == walletID
			},
			sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
		// Bounded: a report card is drawn on every open and this is a second query behind
		// the ratings read. Four is what the card shows.
		descriptor.fetchLimit = 32
		let rows = ((try? context.fetch(descriptor)) ?? []).live
		return rows
			.filter { WalletbeatWatch.isNewsRef($0.sourceRef) }
			.prefix(limit)
			.map(KeyedThing.init)
	}

	/// The attribute a revision names, resolved against the stored card so the sheet can
	/// show what Walletbeat actually says about it now.
	///
	/// Returns nil rather than guessing when the card has not been read on this device —
	/// a revision row can outlive the ratings it describes (they are forgotten on
	/// unwatch), and inventing an attribute name from its id would print `appIsolation`
	/// at somebody as if it were English.
	@MainActor
	static func revisionAttribute(for thing: Thing) -> (WalletbeatSheet.Revision, WalletbeatAttribute?)? {
		guard let ref = thing.sourceRef,
			let revision = WalletbeatSheet.revision(fromRef: ref)
		else { return nil }
		let attribute = WalletbeatState.card(revision.walletID)?
			.attributes.first { $0.id == revision.attributeID }
		return (revision, attribute)
	}
}
