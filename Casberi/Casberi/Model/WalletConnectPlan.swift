import Foundation

/// What one WalletConnect handshake found, arranged as a list to CHOOSE from
/// (2026-08-13, prd §376).
///
/// Until this, `WalletScreen.watchConnected` looped `WalletStore.add` over
/// every account the settled session handed over and watched all of them —
/// silently, unnamed, with no ask. Three things were wrong with that, and only
/// the first is cosmetic:
///
/// (1) A wallet that shares three accounts landed three anonymous `0x…` rows,
///     while typing `vitalik.eth` into the field beside it lands a NAMED one.
///     The richer door produced the poorer entry.
/// (2) **It truncated in silence.** `add` returns `false` on `.limitReached`,
///     and `watchConnected` only reported trouble when EVERY add failed — so
///     watching three wallets and then connecting one sharing four accounts
///     landed two, dropped two, and said "connected". That is exactly the
///     class §307/§309 named in the import rooms: a silent cap is only ever
///     found by somebody who knows how much they put in, and nobody knows how
///     many accounts their wallet shared.
/// (3) The handshake ALSO knows about Safes the shared address signs on
///     (`SafeBridge.signerSafes`), and that fact surfaced later as a scrolling
///     toast rather than at the one moment the person is standing there
///     deciding what to watch.
///
/// This type is the pure half — the arithmetic and the ordering, Foundation
/// only, so `scripts/wallet-connect-plan-selftest.sh` compiles it WHOLE and
/// unmodified. Nothing here reaches the network, the store, or the view.
///
/// It deliberately makes NO judgement about whether an address is "yours".
/// A session proves control of the keys, and a Safe reverse-lookup proves
/// current ownership, but neither is a claim this app repeats back — §295's
/// standing ruling ("limit the analysis, it should be factual") applies with
/// full force to a screen whose whole job is to state what was found.
enum WalletConnectPlan {

    /// Why a row is on the list — the distinction the sheet draws its two
    /// sections and its preselection rule from.
    enum Origin: Equatable {
        /// The wallet handed this over at approval. The person chose it, in
        /// their own wallet's account picker, moments ago.
        case shared
        /// We went and found it: `via` (a shared address) is a current owner
        /// of this Safe on `chain`. Nobody asked for it.
        case safe(via: String, chain: String)

        var isShared: Bool { if case .shared = self { return true }; return false }
    }

    struct Row: Identifiable, Equatable {
        /// The address exactly as it arrived — never the comparison form.
        /// `WalletStore` stores what it was given, and a row that displays a
        /// lowercased EVM address has thrown away its EIP-55 checksum for no
        /// reason.
        let address: String
        /// CAIP-2 namespace — `eip155` or `solana`. A Safe is always EVM.
        let namespace: String
        let origin: Origin
        /// Already in the watch list. Such a row is shown (its absence would
        /// read as "your wallet didn't share it") and cannot be picked — no
        /// checkbox that would mean nothing, §83.
        let alreadyWatching: Bool
        /// The comparison form. Also the identity, so one address reached by
        /// both roads — shared AND signed-on — is one row, not two.
        let key: String
        var id: String { key }
    }

    /// One handshake's whole finding, with every number the sheet states.
    struct Plan: Equatable {
        let rows: [Row]
        /// Watch slots free right now. Rows already watched don't consume it.
        let roomLeft: Int
        /// Picked when the sheet opens: the shared accounts, up to `roomLeft`.
        let preselected: Set<String>

        /// Rows that could be added — everything not already watched.
        var pickable: [Row] { rows.filter { !$0.alreadyWatching } }

        /// How many pickable rows CANNOT fit, however the person chooses.
        ///
        /// This number is the whole reason this type exists. It was previously
        /// unrepresented anywhere, which is what made the truncation silent.
        var overflow: Int { max(0, pickable.count - roomLeft) }

        /// The most that may be selected at once.
        var selectionCeiling: Int { min(pickable.count, roomLeft) }

        /// Whether a not-yet-picked row may still be picked.
        func canPick(_ picked: Set<String>) -> Bool { picked.count < selectionCeiling }
    }

    /// One Safe the reverse-lookup turned up, as `SafeBridge` reports it.
    struct FoundSafe: Equatable {
        let address: String
        /// The shared address that signs on it — the "via" the row explains
        /// itself with. A Safe with no reachable reason to be here is never
        /// constructed.
        let owner: String
        /// Safe's own chain segment ("eth", "base", "gno"), shown so a row
        /// naming a Safe on a chain the person doesn't use is recognisable
        /// as such rather than mysterious.
        let chain: String
    }

    /// The comparison form two addresses collapse in.
    ///
    /// MIRRORS `WalletStore.dedupeKey`, which is private and is the form the
    /// cap and the duplicate test actually use — if these two ever disagree,
    /// this sheet offers a row that `add` then silently refuses as a
    /// duplicate, which is the exact failure mode it exists to end. The
    /// self-test pins both spellings.
    ///
    /// The asymmetry is load-bearing and is `WalletStore`'s reasoning intact:
    /// an EVM address is hex whose case is an EIP-55 checksum rather than
    /// identity, so it must collapse; a Solana address is base58, where case
    /// IS identity, so lowercasing it can fold two genuinely different wallets
    /// into one and discard the second. Lowercase only what is provably hex.
    static func matchKey(_ address: String) -> String {
        isHexAddress(address) ? address.lowercased() : address
    }

    /// `ENS.isHexAddress`'s rule, restated so this file stays Foundation-only
    /// and compilable on its own — trim and all, since a rule that agrees
    /// about every address anyone will actually paste and disagrees at the
    /// edges is the worse kind of copy. Pinned to the original by the harness.
    static func isHexAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        return t.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// Build the list.
    ///
    /// - Parameters:
    ///   - shared: every distinct account the settled session handed over, in
    ///     the order `WalletConnectBridge.accounts(from:)` produced — which is
    ///     sorted by namespace and therefore stable across connects. Order is
    ///     never recomputed here: a list that reshuffles between opens of the
    ///     same wallet reads as broken.
    ///   - safes: what the reverse-lookup found, or `[]` when it found nothing
    ///     AND when it couldn't look. The caller keeps those two apart in its
    ///     own copy (§85) — this function is arithmetic and has no opinion.
    ///   - watched: every currently watched address, in any spelling.
    ///   - limit: `WalletStore.watchLimit`.
    static func make(shared: [(address: String, namespace: String)],
                     safes: [FoundSafe],
                     watched: [String],
                     limit: Int) -> Plan {
        let watchedKeys = Set(watched.map(matchKey))
        var rows: [Row] = []
        var seen = Set<String>()

        // Shared first, and a Safe that is ALSO a shared account never becomes
        // a second row: the wallet handing it over is the stronger fact, and
        // "we found this" is a strange thing to say about something you were
        // just given.
        for account in shared {
            let key = matchKey(account.address)
            guard seen.insert(key).inserted else { continue }
            rows.append(Row(address: account.address,
                            namespace: account.namespace,
                            origin: .shared,
                            alreadyWatching: watchedKeys.contains(key),
                            key: key))
        }
        for safe in safes {
            let key = matchKey(safe.address)
            guard seen.insert(key).inserted else { continue }
            rows.append(Row(address: safe.address,
                            namespace: evmNamespace,
                            origin: .safe(via: safe.owner, chain: safe.chain),
                            alreadyWatching: watchedKeys.contains(key),
                            key: key))
        }

        // Room is measured against the watch list as it stands, NOT against
        // the rows: an already-watched row costs nothing to keep watching.
        let roomLeft = max(0, limit - watchedKeys.count)

        // Preselect what the person already chose in their own wallet, and
        // nothing else. A Safe we went and found is never pre-ticked — the
        // difference between "here is what you handed us" and "here is what we
        // went looking for" is the whole reason the sheet has two sections,
        // and pre-ticking the second would collapse it.
        //
        // Capped at `roomLeft`, so the sheet can never open in a state its own
        // Add button would have to refuse.
        var preselected = Set<String>()
        for row in rows where row.origin.isShared && !row.alreadyWatching {
            guard preselected.count < roomLeft else { break }
            preselected.insert(row.key)
        }

        return Plan(rows: rows, roomLeft: roomLeft, preselected: preselected)
    }

    static let evmNamespace = "eip155"
}
