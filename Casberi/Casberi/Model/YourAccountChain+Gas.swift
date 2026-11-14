import Foundation

/// **GAS PAID IN USDC, ASKED OF THE CHAIN (prd §1780).** `YourAccountGas` is
/// the bytes; this is the reads and the one decision: an account short of
/// ETH for a send's fee, on a network with Circle's paymaster, pays the fee
/// from its USDC. The send's ETH itself is never fronted, and an account
/// with ETH for the fee pays in ETH as before.
extension YourAccountChain {
    /// How one operation's gas is paid in USDC.
    struct UsdcGas: Equatable, Sendable {
        let paymaster: String
        let token: String
        /// The paymaster's fixed charge of gas, which its post-step must be
        /// allowed (`PostOpGasLimitTooLow` otherwise).
        let charge: UInt64
        /// The permit it is handed, when the allowance does not cover the send.
        var data: [UInt8] = []
        /// For the estimate alone: priced as if the allowance stood, so the
        /// fee is known before a permit is signed.
        var assumeAllowance = false
    }

    /// What the paymaster and the token say now.
    struct GasFacts: Equatable, Sendable {
        let paymaster: String
        let token: YourAccountOp.Token
        let allowance: String
        let nonce: String
        /// One ETH in USDC's base units, by the paymaster's own oracle.
        let price: String
        let charge: UInt64
        let spreadBips: UInt64
        /// The account's USDC.
        let held: String
        /// The token's own domain separator.
        let domain: [UInt8]
    }

    #if DEBUG
    /// `-usdcGasProbe YES`: a dry run prices and signs as if the account
    /// held 1,000 USDC, so a simulator's empty account reaches the
    /// paymaster's whole validation. Nothing is sent in a dry run.
    static var pretendsUSDC: Bool { UserDefaults.standard.bool(forKey: "usdcGasProbe") }
    #endif

    private static func uint(_ hex: String) -> String? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count == 32 else { return nil }
        return YourAccountOp.decimal(bytes)
    }

    private static func small(_ hex: String) -> UInt64? { uint(hex).flatMap { UInt64($0) } }

    /// Every fact the decision needs, asked at once. Nil when the network
    /// has no paymaster, it is paused, or anything did not answer: the send
    /// then says what ETH to add, as it always did.
    static func gasFacts(_ net: Network, account: String) async -> GasFacts? {
        guard let paymaster = net.usdcGas else { return nil }
        let token = YourAccountOp.dollar(on: net)
        guard let contract = token.contract else { return nil }
        func call(_ to: String, _ data: [UInt8]) async -> String? { try? await ethCall(net, to: to, data: data) }
        async let allowance = call(contract, YourAccountGas.allowanceCall(owner: account, spender: paymaster))
        async let nonce = call(contract, YourAccountGas.noncesCall(owner: account))
        async let domain = call(contract, YourAccount.sel("DOMAIN_SEPARATOR()"))
        async let price = call(paymaster, YourAccount.sel("fetchPrice()"))
        async let charge = call(paymaster, YourAccount.sel("additionalGasCharge()"))
        async let spread = call(paymaster, YourAccount.sel("feeSpread()"))
        async let paused = call(paymaster, YourAccount.sel("paused()"))
        async let held = balance(net, token, of: account)
        guard let a = await allowance.flatMap(uint), let n = await nonce.flatMap(uint),
              let d = await domain.flatMap(SafeABI.hexBytes), d.count == 32,
              let p = await price.flatMap(uint), p != "0",
              let c = await charge.flatMap(small), let s = await spread.flatMap(small),
              await paused.flatMap(uint) == "0", var h = await held else { return nil }
        #if DEBUG
        if pretendsUSDC { h = "1000000000" }
        #endif
        return GasFacts(paymaster: paymaster, token: token, allowance: a, nonce: n, price: p, charge: c,
                        spreadBips: s, held: h, domain: d)
    }

    /// The most `op` can take from the account's USDC.
    static func gasCost(_ op: YourAccountOp.Op, _ facts: GasFacts) -> String? {
        guard let maxCost = op.maxCost else { return nil }
        return YourAccountGas.tokenCost(maxCost: maxCost, maxFeePerGas: op.maxFeePerGas, charge: facts.charge,
                                        price: facts.price, spreadBips: facts.spreadBips)
    }

    /// **THE OPERATION WITH ITS GAS IN USDC, OR NIL.** Priced first as if the
    /// allowance stood. Where what is left of the allowance covers it, that
    /// is the operation. Where it does not, the account signs a permit for
    /// the cap behind Face ID (its own prompt, saying what it is for), and
    /// the operation is priced again carrying it, so the bundler runs the
    /// permit it will really carry.
    ///
    /// Nil is "not this way": no paymaster here, or its reads failed. A
    /// refusal the person should read (not enough USDC for the gas) throws.
    static func payInUSDC(_ net: Network, account: String, deployed: Bool, entry: YourAccountOp.Entry,
                          calls: [YourAccountOp.Call], rotateTo next: (x: [UInt8], y: [UInt8])?,
                          signer: Signer, coSignerOwner: String?, knownNonce: UInt64?, usdcOut: String,
                          report: @escaping @Sendable (String) -> Void,
                          stage: @escaping @Sendable (Stage) async -> Void) async throws -> (op: YourAccountOp.Op, cost: String)? {
        guard let facts = await gasFacts(net, account: account), let contract = facts.token.contract else { return nil }
        func built(_ gas: UsdcGas) async throws -> YourAccountOp.Op {
            try await build(net, account: account, deployed: deployed, entry: entry, calls: calls, rotateTo: next,
                            signerOwner: signer.owner, coSignerOwner: coSignerOwner, knownNonce: knownNonce,
                            gas: gas, report: report)
        }
        func afford(_ cost: String) throws {
            guard YourAccountOp.atMost(YourAccountOp.sum(usdcOut, cost), facts.held) else {
                let dollars = YourAccountGas.spoken(cost)
                throw Failure(message: String(localized: "Not enough USDC on \(net.name) for the fee too: it can take up to $\(dollars)"))
            }
        }
        var gas = UsdcGas(paymaster: facts.paymaster, token: contract, charge: facts.charge, assumeAllowance: true)
        let first = try await built(gas)
        guard let firstCost = gasCost(first, facts) else { return nil }
        report("gas in USDC: up to \(firstCost) units, allowance \(facts.allowance)")
        if !YourAccountGas.needsPermit(allowance: facts.allowance, cost: firstCost) {
            try afford(firstCost)
            return (first, firstCost)
        }
        // A permit, for the cap. The domain is computed here and must be the
        // token's own: a node's word alone never chooses what is signed.
        guard let name = YourAccountGas.tokenName(chainId: net.chainId),
              YourAccountGas.domainSeparator(name: name.name, version: name.version, chainId: net.chainId, token: contract) == facts.domain else {
            report("gas in USDC: the token's domain is not the one this phone computes")
            return nil
        }
        try afford(firstCost)
        let value = YourAccountGas.permitValue(cost: YourAccountOp.sum(firstCost, firstCost))
        guard let digest = YourAccountGas.permitDigest(domain: facts.domain, owner: account, spender: facts.paymaster,
                                                       value: value, nonce: facts.nonce) else { return nil }
        let dollars = YourAccountGas.spoken(value)
        let why = String(localized: "Let the fee come from your USDC on \(net.name), up to $\(dollars)")
        await stage(.signing)
        let signature: [UInt8]
        if deployed {
            // The account answers for its own signature before it leaves the
            // phone, both keys where it asks for both (`YourAccountMessage`).
            signature = try await YourAccountMessage.sign(hash: digest, on: net, account: account, reason: why)
            guard let permit = YourAccountGas.permitCall(owner: account, spender: facts.paymaster, value: value, signature: signature),
                  (try? await ethCall(net, to: contract, data: permit)) != nil else {
                throw Failure(message: String(localized: "USDC on \(net.name) did not accept the permit, so nothing was sent"))
            }
        } else {
            // No account yet, so nothing on chain can answer for it: the
            // passkey factory checks the assertion, and the bundler's
            // simulation runs the permit after the account it creates.
            guard coSignerOwner == nil,
                  let message = SafeMessageEncoder.safeMessageHash(chainId: net.chainId, safe: account, message: digest),
                  let toSign = SafeWebAuthn.signingDigest(challenge: message) else { return nil }
            let (r, s) = try await signer.sign(toSign, why)
            guard let assertion = SafeWebAuthn.signatureBytes(r: r, s: s),
                  let check = SafeWebAuthn.isValidSignatureForSignerCalldata(message: message, signature: assertion, x: signer.x, y: signer.y),
                  let checkBytes = SafeABI.hexBytes(check),
                  let one = YourAccountMessage.envelope(r: r, s: s, owner: signer.owner) else {
                throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
            }
            guard (try? await ethCall(net, to: SafeWebAuthn.factory, data: checkBytes)).map(SafeWebAuthn.isMagic) == true else {
                throw Failure(message: String(localized: "The signature did not check out, so nothing was sent"))
            }
            signature = one
        }
        guard let data = YourAccountGas.permitData(token: contract, amount: value, signature: signature) else { return nil }
        gas.data = data
        gas.assumeAllowance = false
        let second = try await built(gas)
        guard let cost = gasCost(second, facts) else { return nil }
        report("gas in USDC: with its permit, up to \(cost) units of \(value)")
        guard YourAccountOp.atMost(cost, value) else {
            throw Failure(message: String(localized: "\(net.name) could not price this send"))
        }
        try afford(cost)
        return (second, cost)
    }

    /// Before the tap: whether this send's fee would come from USDC, and
    /// the most it could take. Nil where it would not (the send then says
    /// what ETH to add). Signs nothing, so a permit's own gas is not in it.
    static func gasPreview(_ net: Network, account: String, deployed: Bool, entry: YourAccountOp.Entry,
                           calls: [YourAccountOp.Call], rotateTo next: (x: [UInt8], y: [UInt8])?,
                           signerOwner: String, coSignerOwner: String?, ethOut: String, usdcOut: String) async -> String? {
        // The ETH a send moves is never fronted: only its fee.
        guard let eth = await balance(net, YourAccountOp.eth, of: account), YourAccountOp.atMost(ethOut, eth),
              let facts = await gasFacts(net, account: account), let contract = facts.token.contract,
              let op = try? await build(net, account: account, deployed: deployed, entry: entry, calls: calls, rotateTo: next,
                                        signerOwner: signerOwner, coSignerOwner: coSignerOwner,
                                        gas: UsdcGas(paymaster: facts.paymaster, token: contract, charge: facts.charge,
                                                     assumeAllowance: true)),
              let cost = gasCost(op, facts),
              YourAccountOp.atMost(YourAccountOp.sum(usdcOut, cost), facts.held) else { return nil }
        return cost
    }
}
