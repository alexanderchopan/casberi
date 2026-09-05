import Foundation

/// The ONE place a typed name is routed to the service that can answer it
/// (prd §597, 2026-09-04).
///
/// **Why it exists.** The rule "`.sol` before ENS, because `ENS.looksLikeName`
/// takes ANY dotted string and would send `toly.sol` to a resolver that
/// answers with a null address rather than an error" was true, load-bearing,
/// and SPELLED BY HAND IN SIX PLACES — `WalletWatchField` twice,
/// `AddressBookScreen` twice, `WalletIngest.resolvedAddresses`, and the
/// membership tests in `AddressBook` and `WalletApprovals`. Four of them
/// carried their own copy of the comment explaining it.
///
/// A ternary is fine for two families. Adding `.wei` and `.gwei` makes it a
/// four-way decision in six files, which is the drift shape this codebase has
/// paid for repeatedly (`ToolScore` → `AgentCorpusTools.rank`, the social
/// rooms' nine copied `Shape.init` cases, `GitHubLinks`' two URL readings):
/// the copies do not break, they DISAGREE, and then one screen resolves a name
/// that another screen says is not a name at all.
///
/// So this is a MOVE, not a new layer. The order lives here once; the six call
/// sites ask this file.
enum NameResolve {

    /// Which service claims a string. `none` covers a hex/base58/Bitcoin
    /// address and anything with no dot — callers that already tested for a
    /// literal address never reach this.
    enum Family: Equatable {
        case sns
        case wei(WeiNames.Registry)
        case ens
    }

    /// **THE ORDER, and it is the whole of this file's correctness.** Specific
    /// suffixes first, ENS last — ENS's own test is a catch-all (any dotted
    /// string that is not hex), so anything asked after it is never asked.
    ///
    /// Today that costs `.wei` and `.gwei` names exactly what it once cost
    /// `.sol` ones: sent to `api.ensideas.com`, which has no such TLD, answers
    /// nothing, and leaves the name looking like one nobody has taken.
    static func family(of raw: String) -> Family? {
        if SNS.looksLikeName(raw) { return .sns }
        if let registry = WeiNames.registry(claiming: raw) { return .wei(registry) }
        if ENS.looksLikeName(raw) { return .ens }
        return nil
    }

    /// True when some service claims this string — the test every "should I
    /// try to resolve this?" call site makes.
    static func looksLikeName(_ raw: String) -> Bool { family(of: raw) != nil }

    /// The address a name resolves to, or nil — not a name, no record, or the
    /// resolver was unreachable. A no-op for input that is already an address.
    ///
    /// Note the families answer in DIFFERENT ALPHABETS on purpose: `.sol`
    /// gives base58 and the rest give hex, and callers that can only serve one
    /// (the EVM transfer sync, the NFT reads) narrow afterwards. That is
    /// `WalletIngest.resolvedAddresses`' existing contract and this does not
    /// change it.
    static func resolve(_ raw: String) async -> String? {
        switch family(of: raw) {
        case .sns:                 return await SNS.resolve(raw)
        case .wei:                 return await WeiNamesSource.resolve(raw)
        case .ens:                 return await ENS.resolve(raw)
        case nil:                  return nil
        }
    }

    // MARK: - Reverse

    /// One primary name an address has chosen, with the service that says so.
    struct PrimaryName: Equatable, Hashable {
        /// "Wei", "Gwei", "ENS" — the short label a reach row wears.
        let label: String
        let name: String
    }

    /// Every primary name an address has set, across ENS, WNS and GNS.
    ///
    /// ENS leads because it is the one people mean by "their name", and the
    /// order is FIXED rather than ranked — a ranking would be a claim about
    /// which of somebody's names is really theirs, and these registries are
    /// unrelated to each other. `vitalik.wei` is Vitalik's address;
    /// `vitalik.gwei` is somebody else's entirely (measured), so nothing here
    /// may present one as evidence about another.
    ///
    /// An empty answer is ORDINARY — most addresses have set no primary name
    /// anywhere — and says nothing about names the address HOLDS: forward and
    /// reverse are independent on all three services.
    ///
    /// **Every name here is FORWARD-VERIFIED, on all three services** (prd
    /// §599). Wei and Gwei have been since they landed; ENS is checked by
    /// `forwardVerified` below, which is what makes the three meet one bar —
    /// so nothing downstream needs a badge saying which names can be trusted,
    /// because an unverifiable one is never returned.
    static func primaryNames(for hexAddress: String) async -> [PrimaryName] {
        guard ENS.isHexAddress(hexAddress) else { return [] }
        var out: [PrimaryName] = []
        if let ens = await ENS.reverseName(for: hexAddress),
           await forwardVerified(ens, is: hexAddress) {
            out.append(PrimaryName(label: String(localized: "ENS"), name: ens))
        }
        for (registry, name) in await WeiNamesSource.primaryNames(for: hexAddress) {
            out.append(PrimaryName(label: registry.label, name: name))
        }
        return out
    }

    /// **A REVERSE RECORD IS A CLAIM, NOT A FACT** (prd §599, 2026-09-04).
    ///
    /// Anybody can point a reverse record at any name. ENSIP-3 says so itself
    /// and requires the forward resolution to come back to the same address
    /// before the name is believed — which is exactly the rule
    /// `WeiNamesSource.primaryName` already keeps, and whose own doc cites
    /// ENS as owing the same check. This app did not make it: `ENS.reverseName`
    /// took `name` off the resolver and handed it straight to a book row, so a
    /// stranger's address could present in our own chrome as `vitalik.eth`
    /// beside somebody's money (§83, where believing it costs most).
    ///
    /// **Measured 2026-09-04, and the measurement is why the check is OURS.**
    /// `api.ensideas.com` answers the forward and the reverse query with one
    /// byte-identical object, so its response cannot say whether it verified;
    /// the endpoint is a third party's undocumented internals and this is the
    /// one claim on the screen that must not rest on them. The round trip
    /// costs one request and is spent ONLY on a non-empty answer — the rare
    /// case, since most addresses have set no primary name at all.
    ///
    /// It fails CLOSED: a resolver that does not answer leaves the name
    /// unshown rather than shown unverified. That is the right way round here
    /// — an address with no name and one whose name we could not stand behind
    /// both have nothing honest to print.
    ///
    /// The comparison is case-insensitive because EIP-55 encodes a checksum in
    /// the case of a hex address's letters, so one address legitimately prints
    /// two ways (`AddressCard.foldsCase`'s rule, one screen over).
    private static func forwardVerified(_ name: String, is hexAddress: String) async -> Bool {
        guard let back = await ENS.resolve(name) else { return false }
        return back.caseInsensitiveCompare(hexAddress) == .orderedSame
    }
}
