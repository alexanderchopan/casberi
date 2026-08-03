import Foundation

/// WHO ACTUALLY PAID (2026-08-03, prd §293) — ERC-4337 UserOperations, read
/// out of receipts this app already fetches.
///
/// ## The bug this exists to fix
///
/// `WalletGas` has charged every watched wallet the FULL receipt cost of any
/// transaction that moved tokens out of it: `gasUsed × effectiveGasPrice`,
/// taken from `eth_getTransactionReceipt` on the transfer's hash. For an
/// ordinary EOA that is exactly right — you sent the transaction, you paid for
/// it.
///
/// For a smart account it is wrong in both directions at once:
///
/// - **A 4337 account never sends its own transaction.** A bundler does, and
///   one bundle carries several unrelated people's UserOperations. So the
///   wallet was charged the whole bundle — including strangers' operations.
/// - **A paymaster may have paid all of it.** Then the wallet's real cost is
///   zero and the app reported the bundle's full price.
/// - **A Safe is executed by an owner**, so the Safe was charged gas the owner
///   actually paid.
///
/// None of it was visible: a running total renders perfectly whatever number
/// is in it. Same class as the Gnosis Pay decimals bug — the read succeeded,
/// the arithmetic was confident, and the answer was somebody else's.
///
/// ## The rule
///
/// **You paid a transaction's gas only if you actually sent it**, with one
/// refinement for 4337, where a precise per-operation figure exists:
///
/// 1. A `UserOperationEvent` in this receipt names you as `sender` → your cost
///    is that operation's own `actualGasCost`, and **zero if a paymaster is
///    named** (someone else sponsored you).
/// 2. Otherwise the receipt's `from` is you → you paid the whole receipt, as
///    before.
/// 3. Otherwise → you paid nothing. Somebody else sent this.
///
/// Rule 3 alone fixes Safes and every other executed-by-someone-else account;
/// rule 1 buys the exact number and the sponsorship fact on top.
///
/// ## It costs nothing
///
/// `eth_getTransactionReceipt` already returns the transaction's own `logs`,
/// and `WalletGas` already fetches that receipt. The UserOperationEvent is
/// sitting inside a reply this app has been reading and discarding all along
/// — so the whole feature is zero extra requests.
///
/// ## The emitter is checked, and an unknown one is not trusted
///
/// Logs are filtered by topic and by sender, never by EntryPoint address, so
/// this is version-agnostic by construction: v0.6, v0.7 and v0.8 emit the same
/// event signature and all three are matched without an address list to keep
/// current. But an event is only BELIEVED when a known EntryPoint emitted it —
/// any contract can emit any log it likes, and a forged UserOperationEvent
/// naming your wallet with a paymaster would zero out real gas you really
/// paid. An unknown emitter falls through to rules 2/3 (under-report, never
/// trust a stranger) and the probe names it, so a new EntryPoint shows up as a
/// line to read rather than a silent drift.
///
/// Foundation-only so `scripts/wallet-viz-selftest.sh` can compile it as
/// shipped — every failure here is a wrong number that renders perfectly.
enum WalletUserOps {

    /// `UserOperationEvent(bytes32 indexed userOpHash, address indexed sender,
    /// address indexed paymaster, uint256 nonce, bool success,
    /// uint256 actualGasCost, uint256 actualGasUsed)`.
    ///
    /// KECCAK-DERIVED, not recalled: computed against the app's own
    /// `Keccak256` from the signature above (the `AerodromeDeFi` selector
    /// idiom, and the `PrivacyPoolsBridge` topic rule). The signature is
    /// byte-identical across EntryPoint v0.6/v0.7/v0.8, which is what lets one
    /// topic match every version.
    static let userOperationEventTopic =
        "0x49628fd1471006c1482da88028e9ce4dbb080b815c9b0344d39e5a8e6ec1419f"

    /// The canonical EntryPoints, lowercased — the same address on every EVM
    /// chain (deployed deterministically), the `permit2Address` shape.
    ///
    /// **Doc-derived, UNMEASURED** — not verified against a block explorer
    /// from this machine. That is survivable precisely because of how they're
    /// used: an address NOT on this list makes its event untrusted, so a wrong
    /// or stale entry costs us a correction we don't make (the old,
    /// over-reporting behaviour) rather than a wrong number we assert. Add to
    /// it only after checking an explorer.
    static let knownEntryPoints: Set<String> = [
        "0x5ff137d4b0fdcd49dca30c7cf57e578a026d2789",   // v0.6
        "0x0000000071727de22e5e9d8baf0edac6f37da032",   // v0.7
        "0x4337084d9e255ff0702461cf8895ce9e3b5ff108",   // v0.8
    ]

    private static let zeroAddress = "0x0000000000000000000000000000000000000000"

    /// What kind of smart account an address is, when it is one (2026-08-03,
    /// prd §294). Lives HERE rather than beside its reader in
    /// `WalletActingParties` for one reason: `vendor` parses a string the
    /// remote contract chose, and that parser belongs somewhere the harness
    /// can compile as shipped.
    struct SmartAccount: Equatable {
        /// Its own `accountId()` string when it answered — ERC-7579 specifies
        /// `vendorname.accountname.semver`, so the account NAMES ITSELF and
        /// nothing here has to guess a vendor out of bytecode.
        let accountID: String?
        /// The EntryPoint it answered with — always one of `knownEntryPoints`;
        /// an unrecognised answer is never taken as proof of anything.
        let entryPoint: String?

        /// "Biconomy" out of "biconomy.nexus.1.0.0" — the first dot-component,
        /// title-cased.
        ///
        /// nil unless it is plainly a name: letters and digits only, 2–24
        /// characters. **A contract can return anything it likes from
        /// `accountId()`**, so this is a sanitizer, not a formatter — without
        /// the guard, a hostile account could put a sentence of its own
        /// choosing ("drain your wallet at evil.com") into the app's own
        /// chrome, wearing the app's voice. Refusing to name something is
        /// always available; un-saying it is not.
        var vendor: String? {
            guard let first = accountID?.split(separator: ".").first.map(String.init),
                  (2...24).contains(first.count),
                  first.allSatisfy({ $0.isLetter || $0.isNumber })
            else { return nil }
            return first.prefix(1).uppercased() + first.dropFirst().lowercased()
        }
    }

    /// What one transaction actually cost the wallet in question.
    enum Attribution: Equatable {
        /// The wallet sent it (or its UserOperation paid its own way).
        /// `wei` is the cost in the chain's native units, already scaled.
        case paid(native: Double)
        /// A paymaster covered this operation — the wallet paid nothing, and
        /// `native` is what the sponsor spent on its behalf. Worth stating:
        /// somebody else paying for you is a fact about your money.
        case sponsored(paymaster: String, native: Double)
        /// Somebody else sent this transaction — a bundler, a Safe owner, a
        /// relayer. The wallet's cost is nothing, and there is no sponsor to
        /// name because nobody sponsored the WALLET; they paid for their own
        /// transaction which happened to move the wallet's tokens.
        case notYours
    }

    /// Reads a receipt and answers what it cost `wallet`.
    ///
    /// - `logs`: the receipt's own `logs` array, untouched.
    /// - `from`: the receipt's `from` (who actually sent the transaction).
    /// - `fallbackNative`: `gasUsed × effectiveGasPrice / 1e18`, already
    ///   computed by the caller — used only when rule 2 applies.
    static func attribution(logs: [[String: Any]], from: String?,
                            wallet: String, fallbackNative: Double) -> Attribution {
        let me = wallet.lowercased()
        for log in logs {
            guard let topics = log["topics"] as? [String], topics.count >= 4,
                  topics[0].lowercased() == userOperationEventTopic,
                  addressFromTopic(topics[2]) == me
            else { continue }
            // Any contract can emit any log; only a known EntryPoint's word is
            // taken. An unknown emitter falls through to rules 2/3 below.
            guard let emitter = (log["address"] as? String)?.lowercased(),
                  knownEntryPoints.contains(emitter) else { continue }
            let cost = word(log["data"] as? String, at: 2) / 1e18
            guard cost.isFinite, cost >= 0 else { return .notYours }
            let paymaster = addressFromTopic(topics[3])
            if paymaster != zeroAddress, !paymaster.isEmpty {
                return .sponsored(paymaster: paymaster, native: cost)
            }
            return .paid(native: cost)
        }
        // No operation of ours in this receipt: did we send the transaction
        // ourselves? A Safe, a relayed call and a bundle all fail this test,
        // which is the whole point — the gas was somebody else's.
        guard let from, from.lowercased() == me else { return .notYours }
        guard fallbackNative.isFinite, fallbackNative > 0 else { return .notYours }
        return .paid(native: fallbackNative)
    }

    /// Every UserOperation in a receipt whose emitter we don't recognise —
    /// the probe's drift line. An entry here means a new EntryPoint version is
    /// live and `knownEntryPoints` is behind, which shows up as gas we decline
    /// to correct rather than as a wrong number.
    static func unknownEmitters(logs: [[String: Any]]) -> [String] {
        var out: [String] = []
        for log in logs {
            guard let topics = log["topics"] as? [String], topics.count >= 4,
                  topics[0].lowercased() == userOperationEventTopic,
                  let emitter = (log["address"] as? String)?.lowercased(),
                  !knownEntryPoints.contains(emitter),
                  !out.contains(emitter)
            else { continue }
            out.append(emitter)
        }
        return out
    }

    // MARK: - ABI reading
    //
    // Local rather than `WalletIngest.hexToDouble`, for the reason the type
    // doc gives: this file must compile with no dependencies so the harness
    // can run it as shipped. Two small readers, both of which fail to 0 on a
    // malformed reply rather than guessing.

    /// The 32-byte word at `index` of an ABI-encoded `data` blob, as a Double.
    /// A short or absent blob reads 0 — which for `actualGasCost` means "we
    /// couldn't read it", handled by the caller's `.isFinite` guard rather
    /// than silently charged.
    static func word(_ data: String?, at index: Int) -> Double {
        guard var s = data?.lowercased() else { return 0 }
        if s.hasPrefix("0x") { s.removeFirst(2) }
        let start = index * 64
        guard s.count >= start + 64 else { return 0 }
        let lo = s.index(s.startIndex, offsetBy: start)
        let hi = s.index(lo, offsetBy: 64)
        return hexToDouble(String(s[lo..<hi]))
    }

    /// The low 20 bytes of an indexed address topic, lowercased and
    /// 0x-prefixed. Empty for a malformed topic — never a partial address,
    /// which could otherwise collide with a real one.
    static func addressFromTopic(_ topic: String) -> String {
        var s = topic.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 40 else { return "" }
        return "0x" + String(s.suffix(40))
    }

    /// Big-endian hex → Double. Precision beyond 2^53 is lost, which is fine
    /// for a gas cost (an ETH is 1e18 wei and Double holds ~15 significant
    /// digits — plenty for a number whose largest realistic value is a few
    /// tenths of a coin) and is the same trade `WalletIngest.hexToDouble`
    /// already makes for every balance in the app.
    private static func hexToDouble(_ hex: String) -> Double {
        var out = 0.0
        for ch in hex {
            guard let digit = ch.hexDigitValue else { return 0 }
            out = out * 16 + Double(digit)
        }
        return out
    }
}
