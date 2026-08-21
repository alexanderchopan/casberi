import Foundation

/// The wallet APPS this device has connected with, by their own names (prd §430).
///
/// A settled WalletConnect session carries `peer: AppMetadata`, whose `name` is the wallet
/// app announcing itself — "Rabby", "MetaMask", "Safe{Wallet}". Until now nothing kept it:
/// the session is read for its accounts and torn down on the spot (deliberately — see
/// `WalletConnectBridge.connect`), so the one fact that says WHICH SOFTWARE holds these keys
/// died with it, and Walletbeat's seat went on asking people to type a name the handshake
/// had already told us.
///
/// A READING, NOT A THING (the `X402State`/`ASCState` shape). Nothing here is an entity in
/// the corpus: it is a note about this device's own history, it never leaves it, no host is
/// reached for it, and no `Thing` property is added — so no CloudKit deploy.
///
/// THE RAW NAME IS WHAT IS STORED, never the wallet id it resolves to, and that is the
/// decision this file rests on. Walletbeat rates 32 wallets today and will rate more; a
/// resolved id freezes today's directory into the record, while the raw name is re-resolved
/// on every read — so a wallet Walletbeat adds next month starts being offered to somebody
/// who connected with it last year, for free and with no migration.
///
/// DELIBERATELY NOT CLEARED BY WALLETBEAT'S DISCONNECT. This is a WalletConnect fact that
/// Walletbeat happens to read, not Walletbeat's data — the seat's teardown takes what the
/// seat planted (§401's by-name rule), and taking this would also be taking it from every
/// other reader it may later have.
enum WalletConnectApps {
	private static let key = "walletconnect.apps.seen"

	/// Bounded, because this is a convenience rather than a record anybody audits: a person
	/// who connects with a dozen different wallet apps is served just as well by the last
	/// twelve, and an unbounded dictionary in UserDefaults is a slow leak nobody watches.
	static let cap = 12

	/// Every app name seen, with when it was last seen.
	static func all() -> [String: Date] {
		guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Date]
		else { return [:] }
		return raw
	}

	/// Note that a wallet app announced itself. Idempotent — a second connect with the same
	/// wallet moves its stamp forward rather than adding a row.
	static func record(appNamed name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		// A nameless peer is a fact we do not have. An empty key would resolve to nothing
		// anyway, so storing it only spends a slot in the cap.
		guard !trimmed.isEmpty else { return }
		var map = all()
		map[trimmed] = Date()
		if map.count > cap {
			// Oldest sighting goes, so the cap always keeps what the person did most
			// recently — which is what every reader here is asking about.
			for stale in map.sorted(by: { $0.value < $1.value }).prefix(map.count - cap) {
				map.removeValue(forKey: stale.key)
			}
		}
		UserDefaults.standard.set(map, forKey: key)
	}

	/// The book in the shape `WalletbeatMatch.suggestions` reads.
	static func sightings() -> [(name: String, seenAt: Date)] {
		all().map { (name: $0.key, seenAt: $0.value) }
	}

	static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }
}
