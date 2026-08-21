import Foundation

// Which wallet app you actually use, learned rather than typed (prd §430).
//
// §419's whole naming step is a list of 32 wallets and a search field, i.e. homework, and
// §419 §8 held the way out open without building it: a settled WalletConnect session's
// peer metadata NAMES the wallet app, so the seat can offer "you've connected with Rabby —
// watch it?" with nothing typed. This is that join's pure half — Foundation-only by design,
// so `scripts/walletbeat-selftest.sh` compiles it WHOLE and unmodified.
//
// THE ASYMMETRY THAT SHAPES EVERY RULE HERE: a MISS costs nothing (no offer is made, and
// the search field is exactly where it was), while a WRONG MATCH offers somebody a security
// review of software they do not run, on the screen where they decide what to trust with
// their keys. So every rule below resolves conservatively — exact after normalisation,
// never a prefix or a substring, and an ambiguous key resolves to NOTHING rather than to
// whichever entry came first.
//
// UNMEASURED, and structurally so: this host has no wallet app and no device, so no real
// `AppMetadata.name` has ever been observed here. What IS measured is the other side of the
// join — Walletbeat's own 32 display names, read 2026-08-20 — and that measurement is what
// forced the one transform this file makes; see `key`.

enum WalletbeatMatch {

	/// The comparison form for a wallet's name.
	///
	/// THE TRAILING "WALLET" IS DROPPED, and that is not tidiness — it is the difference
	/// between a feature that fires and one that never does. Measured against Walletbeat's
	/// own 32 display names: they systematically append the word where the app itself does
	/// not — "Ledger Wallet", "Trezor Wallet", "Keystone Wallet", "Cypherock Wallet",
	/// "GridPlus Wallet", "Firefly Wallet", "Uniswap Wallet" — while a WalletConnect peer
	/// calls itself "Ledger", "Trezor", "Keystone". A strict comparison would therefore miss
	/// nearly every hardware wallet in the registry, which is §311's silent-quiet failure:
	/// the offer simply never appears and nothing anywhere says why.
	///
	/// It also earns its keep in the other direction — Safe's app announces itself as
	/// "Safe{Wallet}", which lands on the same key as Walletbeat's "Safe".
	///
	/// ONLY that one word, and only when something is left. Stripping "app", "live" or
	/// "suite" as well would start folding genuinely different products together, and the
	/// cost of a fold is a wrong answer rather than no answer. A wallet actually named
	/// "Wallet" keeps its name rather than normalising to nothing.
	///
	/// Non-alphanumerics are separators, not characters: "Safe{Wallet}", "Safe Wallet" and
	/// "safe-wallet" are one product written three ways.
	static func key(_ raw: String) -> String? {
		var tokens = raw.lowercased()
			.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
			.map(String.init)
		if tokens.count > 1, tokens.last == "wallet" { tokens.removeLast() }
		let joined = tokens.joined()
		return joined.isEmpty ? nil : joined
	}

	/// Every spelling that resolves to a wallet, with the ambiguous ones removed.
	///
	/// Both the DISPLAY NAME and Walletbeat's own ID are registered, because they answer
	/// different peers: "Bridge Wallet" is what their directory calls `mtpelerin`, and
	/// "OneKey" is what the app calls "OneKey Pro". Neither alone covers both.
	///
	/// A KEY CLAIMED BY TWO WALLETS IS DROPPED ENTIRELY rather than resolved to the first —
	/// dropping it makes the feature quiet for that name, and quiet is the cheap failure
	/// here. Measured 2026-08-20: no collision exists across the real 32, and the harness
	/// asserts that against the shipped snapshot, so a future rename that would create one
	/// fails the build instead of silently offering the wrong review.
	static func index(_ entries: [(id: String, name: String)]) -> [String: String] {
		var claims: [String: Set<String>] = [:]
		for entry in entries {
			for spelling in [entry.name, entry.id] {
				guard let k = key(spelling) else { continue }
				claims[k, default: []].insert(entry.id)
			}
		}
		return claims.compactMapValues { $0.count == 1 ? $0.first : nil }
	}

	/// The wallet a connected app's own name resolves to, or nil.
	static func walletID(forAppNamed name: String, in entries: [(id: String, name: String)]) -> String? {
		guard let k = key(name) else { return nil }
		return index(entries)[k]
	}

	/// The wallets worth offering: apps this device has really connected with, that
	/// Walletbeat rates, that are not already watched — most recently seen first.
	///
	/// Ordering is by the SIGHTING, never by anything about the wallet: this is a list of
	/// what the person did, and sorting it by coverage or by findings would turn a record of
	/// their own actions into a ranking of their software (§419's central rule).
	///
	/// Deduped, because one wallet app reached by two spellings ("Safe", "Safe{Wallet}") is
	/// one wallet and must not be offered twice.
	static func suggestions(
		apps: [(name: String, seenAt: Date)],
		watched: [String],
		entries: [(id: String, name: String)]
	) -> [String] {
		let table = index(entries)
		let already = Set(watched)
		var out: [String] = []
		var seen = Set<String>()
		for app in apps.sorted(by: { $0.seenAt > $1.seenAt }) {
			guard let k = key(app.name), let id = table[k] else { continue }
			guard !already.contains(id), seen.insert(id).inserted else { continue }
			out.append(id)
		}
		return out
	}
}
