import Foundation

/// The two deterministic checks an address manager can make about an address
/// itself — no network, no key, no model (2026-08-01). Both exist because this
/// app TRUNCATES addresses everywhere, which is the right call for a list of
/// fifty rows and the exact weakness the two attacks below exploit.
///
/// Pure by construction so it can be harness-tested against the shipped source
/// the way `StripeMoney`/`StripeSilence` are: every function here takes strings
/// and returns a verdict, and nothing in the file reads the book, the corpus,
/// or the clock.
enum AddressSafety {

    // MARK: - Checksum (a typo, caught before it costs a watch)

    /// What an address's own EIP-55 checksum says about it.
    ///
    /// `unavailable` is not a failure and must never be shown as one: an
    /// all-lowercase (or all-uppercase) address carries NO checksum
    /// information at all — the case IS the checksum, so a form with no case
    /// variation has nothing to verify. Most pasted addresses are lowercase,
    /// so `unavailable` is the common answer and silence is the correct
    /// response to it.
    enum Checksum: Equatable { case verified, failed, unavailable }

    /// Verifies a hex address against its own mixed-case checksum. A `failed`
    /// verdict means one character was transcribed wrong — a wrong address
    /// that would otherwise be watched, find nothing, and read as "no activity
    /// found on your chains yet", which blames the chain for a typo.
    ///
    /// Deliberately conservative in one place: an address whose letters happen
    /// to be all-uppercase reads `unavailable` rather than being checked,
    /// because "the person typed it in caps" and "this is a checksummed
    /// address whose letters are all uppercase" are the same string.
    static func checksum(_ address: String) -> Checksum {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ENS.isHexAddress(trimmed) else { return .unavailable }
        let body = trimmed.dropFirst(2)
        // Letters only — a digit is neither case, so an address of mostly
        // digits still answers honestly on the letters it has.
        guard body.contains(where: \.isUppercase), body.contains(where: \.isLowercase)
        else { return .unavailable }
        // Compare BODIES, not whole strings: `isHexAddress` accepts a `0X`
        // prefix and `EIP55.checksum` always answers with a lowercase `0x`,
        // so comparing the full strings would fail an address for its prefix.
        return EIP55.checksum(trimmed).dropFirst(2) == body ? .verified : .failed
    }

    // MARK: - Lookalikes (address poisoning)

    /// True for something that IS an address rather than standing for one.
    /// Names are excluded on purpose — poisoning works on raw addresses, and
    /// two long ENS names sharing a truncation ("supercalifragilistic1.eth"
    /// and "…2.eth") are not an attack, just two long names.
    static func isRawAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return ENS.isHexAddress(trimmed) || SNS.isAddress(trimmed)
            || BitcoinAddress.isAddress(trimmed)
    }

    /// The identity form — hex folds case (EIP-55 case is a checksum, not
    /// identity), base58 never does (its case IS identity, and folding it
    /// merges two different wallets). The same asymmetry `AddressBook.key`
    /// and `WalletStore.dedupeKey` already keep.
    static func identity(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return ENS.isHexAddress(trimmed) ? trimmed.lowercased() : trimmed
    }

    /// What the person actually SEES for this address — nil when it isn't a
    /// raw address. This is deliberately `WalletStore.shortAddress`, the same
    /// function every row, chip and card truncates with: the display form is
    /// the risk surface, so it is also the comparison key. If truncation ever
    /// changes shape, this check follows it automatically.
    static func displayForm(_ address: String) -> String? {
        guard isRawAddress(address) else { return nil }
        return WalletStore.shortAddress(identity(address))
    }

    /// Two addresses that LOOK identical everywhere this app prints them, and
    /// aren't the same address.
    ///
    /// This is the address-poisoning shape. An attacker sends a dust transfer
    /// from a vanity address whose first and last characters match one you
    /// already deal with, betting that you will later copy the wrong one out
    /// of your own history — every truncated display in every wallet app is
    /// built to hide precisely the difference that matters. The check costs
    /// one string comparison and is the one defense a NAMED-ADDRESS ledger is
    /// uniquely placed to offer: the book already holds the address you meant.
    static func isLookalike(_ a: String, _ b: String) -> Bool {
        guard let displayA = displayForm(a), let displayB = displayForm(b),
              displayA == displayB
        else { return false }
        return identity(a) != identity(b)
    }
}
