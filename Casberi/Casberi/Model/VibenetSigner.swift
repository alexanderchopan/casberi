import Foundation

/// WHETHER THIS PHONE MAY SIGN, AND WHY NOT (prd §523, 2026-08-29).
///
/// Foundation-only BY DESIGN so `scripts/vibenet-selftest.sh` can compile it
/// WHOLE and unmodified. Every input is a MEASURED value handed in by the
/// caller; nothing here reads a clock, a keychain, or a network. That is what
/// makes the ladder below testable at all, and the ladder is the feature.
///
/// ## THE REFUSALS ARE THE FEATURE
///
/// `SafeSignBlock` (prd §425/§426) earned this shape one chain over: every
/// non-ready state renders as the same absent button, so unless each one
/// NAMES itself the person is left with a screen that does nothing and no way
/// to find out why. Eleven refusals here, and **only three of them mean
/// something is wrong** — the rest mean not yet.
///
/// ## HOW WE KNOW THE ACCOUNT ACCEPTS THIS PHONE (MEASURED 2026-08-29)
///
/// The obvious join — hash this phone's public key into an `actorId` and look
/// for it — is the WRONG SHAPE, and measuring the live chain is what showed
/// why. **The `actorId` is not derived by any contract. It is supplied by the
/// caller**, in the `AuthorizeActor` payload's first word:
///
///     abi.encode(bytes32 actorId, address authenticator,
///                uint256 expiry, uint256 scope, bytes actorData)
///
/// So there is no preimage function to find, in the tree or on chain. Two
/// different clients can authorize the same key under two different ids, and
/// both are correct. A build that hashed a key and looked for the result would
/// answer "this account doesn't list your key" about accounts it can sign
/// for — silently, forever, with every other check green.
///
/// **The join is on `actorData`, which carries the key material.** Measured
/// across all 16 `ActorAuthorized` events this chain has ever emitted:
/// `actorData` is a 20-byte authenticator address followed by its own bytes
/// (a K1 actor's is `address(1)` plus flags; a policy-gated one appends the
/// PolicyManager and a 32-byte commitment). A P-256 actor's carries its public
/// key, so an account accepts this phone exactly when one of its actors'
/// `actorData` contains our `x || y` — and that record's own `actorId` is then
/// read off the same row rather than computed.
///
/// The caller does that match and hands the result in as `ourActorID`. nil
/// means the actor records could not be READ, which is its own refusal
/// (`.actorDataUnreadable`) and is never collapsed into "not an
/// authenticator": cannot-say and no are different answers, and only one of
/// them should stop somebody trusting the room.
///
/// **CEILING, stated because it is real:** no P-256 actor has ever been
/// authorized on this chain (all 16 are K1, delegate or policy), so the exact
/// byte layout of a P-256 `actorData` is inferred from the shape of the other
/// three and is UNVERIFIED. The match is a `contains`, which is why an
/// inferred layout still cannot produce a false positive.
enum VibenetSigner {

    /// The ONLY chain this key may ever sign for, and it is asserted rather
    /// than assumed (`SafeSigner`'s Gnosis rule: a chain where the cross-check
    /// cannot run is a chain this app must not sign on).
    ///
    /// Measured 2026-08-29 off the live node: `eth_chainId` answers
    /// `0x509f455` = 84538453. Signing on a real chain must be IMPOSSIBLE, not
    /// merely unintended, so `decide` refuses any other value and
    /// `vibenet-selftest.sh` mutation-proves that refusal.
    static let chainID: UInt64 = 84_538_453

    // MARK: - Why not

    enum Refusal: Error, Equatable {
        /// This device has no Secure Enclave. Every simulator.
        case noEnclave
        /// No key has been made on this phone yet. Offers to make one.
        case noKey
        /// A key was made and the Keychain no longer holds it, which on
        /// `.biometryCurrentSet` means Face ID was enrolled again. **Not the
        /// same as a cancelled prompt**, which produces the identical system
        /// error and means the opposite thing.
        case keyDestroyed
        /// Asked to sign for a chain that is not vibenet. Carries what it was
        /// asked for, because a silent refusal here reads as a bug.
        case wrongChain(UInt64)
        /// The live contract map did not answer. **Never guess an address** —
        /// vibenet redeploys on no schedule, so a cached address may name a
        /// contract that no longer means what we think.
        case contractsUnreadable
        /// The chain did not answer. Not knowing is not knowing it is fine.
        case chainUnreadable
        /// The account's actor records could not be read, so we cannot say
        /// whether it accepts this phone's key. **Cannot-say, never no** — see
        /// the type doc for why collapsing this into `.notAnAuthenticator`
        /// is the failure this whole type is shaped around.
        case actorDataUnreadable
        /// The chain does not list this key on this account.
        case notAnAuthenticator
        /// The key is listed and its expiry has passed. Carries the date so
        /// the sentence can say when.
        case keyExpired(Date)
        /// The account itself is locked. The room already reads and draws
        /// this; the ask repeats it rather than going quiet.
        case accountLocked
        /// The change was simulated and it would revert. **Something is
        /// wrong.** Carries the chain's own reason where there is one.
        case simulationFailed(String?)
        /// The simulation could not be run at all. **Refuse anyway** — the
        /// whole point of simulating is that we do not sign on a maybe.
        case simulationUnread

        /// Whether this refusal means something is BROKEN rather than merely
        /// not ready. Three of eleven, and the split is what lets a screen
        /// choose between a quiet line and an alarming one.
        var isFault: Bool {
            switch self {
            case .simulationFailed, .keyDestroyed, .contractsUnreadable: true
            default: false
            }
        }
    }

    // MARK: - What we know when we decide

    /// Everything `decide` is allowed to look at. A struct rather than a long
    /// parameter list so the harness can vary exactly one fact at a time, and
    /// so a new input cannot be added without every call site naming it.
    struct Facts: Equatable {
        var enclaveAvailable: Bool
        /// nil when no key was ever made; the raw 64-byte `x || y` hex
        /// otherwise. Absent-vs-destroyed is carried by `keyDestroyed`.
        var publicKeyHex: String?
        var keyDestroyed: Bool
        var chainID: UInt64?
        var contractsReadable: Bool
        var accountReachable: Bool
        var accountLocked: Bool
        /// The `actorId` of the account record whose `actorData` contains this
        /// phone's public key — read off the chain, never computed (see the
        /// type doc). nil when the records could not be read. **nil is not
        /// "no" — it is "we cannot say"**, and the ladder answers it with its
        /// own refusal.
        var ourActorID: String?
        /// Every actorId the account currently authorizes, lowercased.
        var authorizedActorIDs: [String]
        /// Unix seconds for our key on this account; 0 is `Keystore.sol`'s own
        /// convention for "no expiry set", never a date (`VibenetActor.expiry`
        /// carries the same rule and the same warning).
        var expiry: UInt64?
        /// nil when no simulation was run, `.some(nil)` when it succeeded,
        /// `.some(.some(reason))` when it reverted. Three states, because
        /// "did not run" and "ran and failed" are different refusals.
        var simulation: SimulationOutcome?

        init(enclaveAvailable: Bool = true,
             publicKeyHex: String? = nil,
             keyDestroyed: Bool = false,
             chainID: UInt64? = VibenetSigner.chainID,
             contractsReadable: Bool = true,
             accountReachable: Bool = true,
             accountLocked: Bool = false,
             ourActorID: String? = nil,
             authorizedActorIDs: [String] = [],
             expiry: UInt64? = nil,
             simulation: SimulationOutcome? = nil) {
            self.enclaveAvailable = enclaveAvailable
            self.publicKeyHex = publicKeyHex
            self.keyDestroyed = keyDestroyed
            self.chainID = chainID
            self.contractsReadable = contractsReadable
            self.accountReachable = accountReachable
            self.accountLocked = accountLocked
            self.ourActorID = ourActorID
            self.authorizedActorIDs = authorizedActorIDs
            self.expiry = expiry
            self.simulation = simulation
        }
    }

    enum SimulationOutcome: Equatable {
        case succeeds
        case reverts(String?)
    }

    /// What a caller gets when every gate is passed. Carries the facts the ask
    /// sheet has to state, so the view never re-derives one and never
    /// disagrees with the decision that produced it.
    struct Ready: Equatable {
        let actorID: String
        let expiry: UInt64
        /// Whether the account will still be signable after this — false when
        /// our key is the ONLY authorizer, which is `SafeSigner`'s
        /// `hasNoSpareOwner` warning in vibenet's vocabulary. Stated, never a
        /// refusal: in a one-key account our decline IS the lock.
        let isOnlyKey: Bool
    }

    // MARK: - The ladder

    /// **Order is the design.** Local and free first, then the two "we could
    /// not read" cases, then what the chain says about this key, and the
    /// simulation last because it is the most expensive and the most
    /// alarming. Reordering changes which sentence a person sees when several
    /// things are wrong at once, so the harness pins it.
    static func decide(_ f: Facts, now: Date) -> Result<Ready, Refusal> {
        // 1. Can this device ever?
        guard f.enclaveAvailable else { return .failure(.noEnclave) }

        // 2. Is there a key? Destroyed is checked BEFORE absent: a destroyed
        //    key still has its cached public half, so testing absence first
        //    would report `.noKey` and offer to make one, quietly hiding the
        //    fact that an account out there still authorizes a key this phone
        //    can no longer produce.
        if f.keyDestroyed { return .failure(.keyDestroyed) }
        guard let key = f.publicKeyHex, !key.isEmpty else { return .failure(.noKey) }

        // 3. The devnet-only rail. Before any read, so a misconfigured caller
        //    cannot spend a request on its way to being refused.
        guard let chain = f.chainID else { return .failure(.chainUnreadable) }
        guard chain == chainID else { return .failure(.wrongChain(chain)) }

        // 4. We refuse to act on an address we had to guess.
        guard f.contractsReadable else { return .failure(.contractsUnreadable) }
        guard f.accountReachable else { return .failure(.chainUnreadable) }

        // 5. Can we even ask the question? nil here is "cannot say", and
        //    answering "no" on a cannot-say is the silent failure this whole
        //    type exists to avoid.
        guard let ours = f.ourActorID?.lowercased(), !ours.isEmpty else {
            return .failure(.actorDataUnreadable)
        }

        // 6. Does the account accept it?
        let authorized = f.authorizedActorIDs.map { $0.lowercased() }
        guard authorized.contains(ours) else { return .failure(.notAnAuthenticator) }

        // 7. Has it expired? 0 means no expiry was ever set — a value, not a
        //    date, and reading it as 1970 expires every unlimited key.
        let expiry = f.expiry ?? 0
        if expiry != 0 {
            let when = Date(timeIntervalSince1970: TimeInterval(expiry))
            if when <= now { return .failure(.keyExpired(when)) }
        }

        // 8. A locked account refuses everything, and says so rather than
        //    letting the simulation deliver the news as a revert.
        if f.accountLocked { return .failure(.accountLocked) }

        // 9. Simulation last. Both of these refuse — "could not run" is not
        //    permission to proceed.
        switch f.simulation {
        case .none:                    return .failure(.simulationUnread)
        case .some(.reverts(let why)): return .failure(.simulationFailed(why))
        case .some(.succeeds):         break
        }

        return .success(Ready(actorID: ours,
                              expiry: expiry,
                              isOnlyKey: authorized.count == 1))
    }

    // MARK: - Sentences

    /// The copy for each refusal. Kept beside the ladder rather than in the
    /// view so a new case cannot be added without a sentence — Swift's
    /// exhaustive switch is the enforcement, which is the same trick
    /// `AgentPanelProbe` used to keep its own registry honest.
    static func sentence(_ r: Refusal) -> String {
        switch r {
        case .noEnclave:
            String(localized: "This device has no Secure Enclave, so it can't hold a signing key.")
        case .noKey:
            String(localized: "This phone doesn't have a key on vibenet yet.")
        case .keyDestroyed:
            String(localized: "Face ID was set up again on this phone, which erases the key. Nothing was signed and nothing was lost \u{2014} make a new key, then authorize it from another account that can act for this one.")
        case .wrongChain(let id):
            String(localized: "This key only signs on vibenet, and that request named chain \(String(id)).")
        case .contractsUnreadable:
            String(localized: "Couldn't read vibenet's contract list, and its addresses change too often to guess.")
        case .chainUnreadable:
            String(localized: "Couldn't reach the chain, so we can't say whether this would work.")
        case .actorDataUnreadable:
            String(localized: "Couldn't read this account's keys, so we can't say whether it accepts this phone's.")
        case .notAnAuthenticator:
            String(localized: "This account doesn't list this phone's key.")
        case .keyExpired:
            String(localized: "This phone's key on this account has expired.")
        case .accountLocked:
            String(localized: "This account is locked, so nothing can act for it.")
        case .simulationFailed(let why):
            if let why, !why.isEmpty {
                String(localized: "Tried it against the chain first and it would fail: \(why)")
            } else {
                String(localized: "Tried it against the chain first and it would fail.")
            }
        case .simulationUnread:
            String(localized: "Couldn't try it against the chain first, so it isn't offered.")
        }
    }

    /// A short label for a probe line and for the one place a screen names the
    /// refusal rather than reading it. Stable strings, never localized — a
    /// probe that reads differently per device is a probe nobody can compare.
    static func name(_ r: Refusal) -> String {
        switch r {
        case .noEnclave:            "noEnclave"
        case .noKey:                "noKey"
        case .keyDestroyed:         "keyDestroyed"
        case .wrongChain:           "wrongChain"
        case .contractsUnreadable:  "contractsUnreadable"
        case .chainUnreadable:      "chainUnreadable"
        case .actorDataUnreadable:  "actorDataUnreadable"
        case .notAnAuthenticator:   "notAnAuthenticator"
        case .keyExpired:           "keyExpired"
        case .accountLocked:        "accountLocked"
        case .simulationFailed:     "simulationFailed"
        case .simulationUnread:     "simulationUnread"
        }
    }
}
