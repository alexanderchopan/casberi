import Foundation
import Observation

// MARK: - The watch list

/// Which Altana accounts this device watches ON TOP OF the wallets it already
/// watches (2026-08-28, amending prd §465).
///
/// **Why a seat that rides the watched wallets grew a list of its own.** §403
/// gated Altana on EVIDENCE rather than on watching, for the right reason:
/// most wallets hold no keystore entry, and a seat lighting up for every
/// watched wallet claims a registry entry that isn't there (§83). The cost of
/// that correctness is that somebody with no registered key sees the seat, taps
/// Connect, watches their wallet, and gets NOTHING — forever, with nothing on
/// screen to say the registry simply has not reached them yet. Measured
/// 2026-08-28 against `explorer.altana.network`: **39 keys across 9 accounts**,
/// every one of them somebody else's.
///
/// So this is vibenet's answer (§465), taken for vibenet's own two reasons
/// rather than by analogy:
///
/// 1. **These are not your wallets.** An Altana example is somebody else's
///    account, offered to look at. Putting it in `WalletStore` would spend one
///    of the FIVE capped slots — a cap that exists because each watch is a
///    metered Zerion read — on an address that read cannot even see: there is
///    no BNB entry in `WalletIngest.allChains`, which is exactly why §403 gave
///    this seat its own registry table with its own hosts. A watched Altana
///    account would cost a metered read and return nothing.
/// 2. **The read is keyless and free**, so there is no expensive tier to
///    ration and therefore NO CAP — §465's rule 1, and the same reasoning:
///    a limit with no cost behind it is a control that protects nothing.
///
/// The seat stays gated on evidence for BOTH populations: watching an example
/// that turns out to hold no key still does not light the seat, because
/// `AltanaKeystore.evidence` is stamped by the read, never by the watch.
@Observable
final class AltanaWatch {
    static let shared = AltanaWatch()
    private static let key = "altana.watch.addresses.v1"

    private var addressList: [String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            addressList = saved
        } else {
            addressList = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(addressList) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    var addresses: [String] { addressList }
    var connected: Bool { !addressList.isEmpty }

    /// Every spelling of every account here, lowercased — the shape
    /// `BridgeStore.watchedForms()` hands the seat table, so the seat's count
    /// can union the two populations without either knowing about the other.
    /// There is only ever one spelling: Altana accounts are hex, since the
    /// registry is keyed by address and no name registrar resolves onto it.
    var watchedForms: Set<String> { Set(addressList.map { $0.lowercased() }) }

    /// Delegates to `AddressBook`, exactly as `VibenetWatch` has since the
    /// 2026-08-27 unification — one account is one book entry, so a name
    /// survives a disconnect and reaches a second device.
    func name(for address: String) -> String? { AddressBook.shared.name(for: address) }

    func setName(_ raw: String, for address: String) {
        AddressBook.shared.setName(raw, for: address, networks: [AddressBook.Network.altana])
    }

    func isWatching(_ address: String) -> Bool {
        addressList.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// A plain `0x`-prefixed 40-hex address — the whole validation, and
    /// `VibenetWatch.isValidAddress`'s own reasoning: the keystore is keyed by
    /// address and Altana runs no name registrar, so a pasted name that is not
    /// already hex is not an Altana account. Deliberately NOT `ENS`-resolving:
    /// an ENS name resolves to a MAINNET address, and 38 of the 39 keys
    /// measured are on BNB — resolving would quietly answer a different
    /// question than the one asked.
    /// Forwards to `AltanaDiscovery`, which is the pure file and therefore the
    /// one a harness can compile. ONE validator, two call sites: the field and
    /// the account list must never disagree about what an Altana address is.
    static func isValidAddress(_ raw: String) -> Bool {
        AltanaDiscovery.isValidAddress(raw)
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AltanaWatch.isValidAddress(address), !isWatching(address) else { return false }
        addressList.append(address)
        // Watching implies the book holds it — `VibenetWatch.add`'s invariant.
        let book = AddressBook.shared
        if book.entry(for: address) == nil {
            book.setName(WalletStore.shortAddress(address), for: address,
                         networks: [AddressBook.Network.altana])
        } else {
            book.addNetwork(AddressBook.Network.altana, for: address)
        }
        return true
    }

    /// Stop watching one account — and KEEP THE NAME (§472's ruling, which
    /// applies here for the same reason: watching and naming are two tiers over
    /// one ledger, and a name costs nothing to keep).
    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    func removeAll() { addressList.removeAll() }
}
