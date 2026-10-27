import Foundation

/// **DETAILS: THIS EXACT OPERATION, BEFORE THE TAP (prd §1509 item 1).**
/// Move asks for a preview whenever its sentence settles: the same route
/// `MoveSentence.spend` will take (the session key under the spend limit,
/// both keys over it, else this phone), the same calls `transact` signs
/// (`assemble`), the same unsigned operation (`build`, `sessionBuild`),
/// simulated. What comes back is the fee ceiling, the nonce, what the
/// simulation found, the calls in words, the hash and the calldata.
///
/// The operation is kept for a minute (`Prepared`): signing these same
/// items on the same route in that time signs it as it stands — its quotes,
/// its gas, its fee — so the hash Raw transaction showed is the hash Face
/// ID signs. Later than that, signing assembles and prices afresh, as it
/// always did.
///
/// The demo's preview comes off its table (`YourAccountDemo`), never a node.
extension YourAccountChain {
    struct Preview: Equatable, Sendable {
        let network: Network
        let route: Prepared.Signs
        /// The most the operation can cost, in wei; nil when it could not be priced.
        let feeWei: String?
        /// The sequence the operation uses, under its own nonce key.
        let nonce: UInt64?
        let checked: YourAccountPreview.Checked
        let words: [YourAccountPreview.Step]
        let approvals: [YourAccountPreview.Approval]
        /// Each swap's sold amount and its pools, from the quote it signs.
        var sold: [YourAccountPreview.Sold] = []
        let hash: [UInt8]?
        let hashKind: YourAccountPreview.HashKind
        let callData: [UInt8]
        /// Why signing would be refused, in words: a fee the account cannot
        /// pay, a node that would not price it, no Signer over the limit.
        var refusal: String? = nil
    }

    /// An operation built for a preview, kept for signing (prd §1509).
    struct Prepared: @unchecked Sendable {
        enum Signs: Equatable, Sendable { case owner, bothKeys, session }
        let items: [Item]
        let roundUp: RoundUpBuy?
        let route: Signs
        let op: YourAccountOp.Op
        let assembled: AssembledParts?
        let made: Date

        /// How long a kept operation may be signed as it stands: inside
        /// it a gas price, a quote and a nonce have rarely moved; the nonce
        /// and the bytes are checked again anyway, and the calls simulated
        /// again.
        static let lifetime: TimeInterval = 60

        private static let store = Store()

        static func keep(_ p: Prepared) async { await store.put(p) }

        /// The kept operation for exactly these items on this route, fresh
        /// enough; taken, so it is signed at most once.
        static func take(_ items: [Item], roundUp: RoundUpBuy?, route: Signs) async -> Prepared? {
            await store.take { p in
                same(p.items, items) && p.roundUp == roundUp && p.route == route
                    && Date().timeIntervalSince(p.made) < lifetime
            }
        }

        /// The same transaction, whatever ids its lines carry: the sentence's
        /// line being filled is a new value every time it is read. A swap's
        /// quote is not compared — signing a kept preview signs the preview's
        /// own quote, asked of the pools with it.
        static func same(_ a: [Item], _ b: [Item]) -> Bool {
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { x, y in
                switch (x, y) {
                case (.send(let p), .send(let q)):
                    p.network == q.network && p.token == q.token && p.amount == q.amount
                        && p.to.lowercased() == q.to.lowercased() && p.toName == q.toName
                case (.swap(let s), .swap(let t)):
                    s.network == t.network && s.sell == t.sell && s.buy == t.buy && s.amount == t.amount && s.to == t.to
                default:
                    false
                }
            }
        }

        private actor Store {
            private var kept: Prepared?
            func put(_ p: Prepared) { kept = p }
            func take(where matches: (Prepared) -> Bool) -> Prepared? {
                guard let p = kept, matches(p) else { return nil }
                kept = nil
                return p
            }
        }
    }

    /// What signing `items` would do now, without signing. Never throws: a
    /// refusal is the preview's `refusal`, said in Details and the line.
    static func preview(_ items: [Item], account: String, roundUp: RoundUpBuy?) async -> Preview? {
        guard let net = items.first?.network, items.allSatisfy({ $0.network == net }) else { return nil }
        if YourAccountDemo.isDemo(account) { return demoPreview(items, on: net) }
        let sends = items.compactMap { if case .send(let p) = $0 { p } else { nil } }
        var route: Prepared.Signs = .owner
        if case .on = (try? await limitState(net, account)) ?? .off {
            route = .bothKeys
            if sends.count == items.count, let p = await sessionPreview(sends, net: net, account: account, roundUp: roundUp) {
                return p
            }
        }
        // What assembling wrote, kept for a refusal after it: the bundler
        // refusing to price the operation still leaves Details the calls in
        // words, the pools and the simulation's verdict (prd §1545).
        var written: Assembled?
        do {
            let parts = try await assemble(items, account: account, roundUp: roundUp, renew: route == .bothKeys)
            written = parts.assembled
            let a = parts.assembled
            let entry: YourAccountOp.Entry = a.deployed ? try await accountEntry(net, account) : .module4337
            // Who signs beside this phone: the Signer over the limit, or the
            // one `operate` asks itself when the account already needs both.
            var coSigner: String?
            if route == .bothKeys {
                guard let first = try await signers(net, account).first else {
                    return empty(a, route: route, refusal: String(localized: "Add a signer first: over the limit, a send waits on it"))
                }
                coSigner = first
            } else if a.deployed, entry == .adapter, try await threshold(net, account) >= 2 {
                // `operate` refuses this at signing; say so now.
                guard let first = try await signers(net, account).first else {
                    return empty(a, route: route, refusal: String(localized: "Your Signer signs this too, and none is on \(net.name)"))
                }
                coSigner = first
            }
            let op = try await build(net, account: account, deployed: a.deployed, entry: entry, calls: a.calls,
                                     rotateTo: a.nextKey, signerOwner: a.signer.owner, coSignerOwner: coSigner)
            // A preview the sentence has moved past is never kept: it would
            // take the place of the one now on screen.
            if !Task.isCancelled {
                await Prepared.keep(Prepared(items: items, roundUp: roundUp, route: route, op: op, assembled: parts, made: Date()))
            }
            let fee = op.maxCost.map(String.init)
            return Preview(network: net, route: route, feeWei: fee, nonce: op.nonce, checked: a.simulated.checked,
                           words: a.words, approvals: a.approvals, sold: a.sold, hash: YourAccountOp.safeOpHash(op, chainId: net.chainId),
                           hashKind: .eip712, callData: op.callData,
                           refusal: await short(a.payments, fee: fee, net: net, account: account, deployed: a.deployed))
        } catch let failure as Failure {
            if let written { return empty(written, route: route, refusal: failure.message) }
            return Preview(network: net, route: route, feeWei: nil, nonce: nil, checked: .notChecked, words: [],
                           approvals: [], hash: nil, hashKind: .eip712, callData: [], refusal: failure.message)
        } catch {
            return Preview(network: net, route: route, feeWei: nil, nonce: nil, checked: .notChecked, words: [],
                           approvals: [], hash: nil, hashKind: .eip712, callData: [], refusal: String(localized: "\(net.name) did not answer"))
        }
    }

    /// Sends under the limit, on the session key; nil when the session key
    /// cannot carry them — the policy refusing them in the estimate (over the
    /// limit), or any other refusal before Face ID — so both keys sign,
    /// exactly as `MoveSentence.spend` falls back.
    private static func sessionPreview(_ sends: [YourAccountOp.Payment], net: Network, account: String,
                                       roundUp asked: RoundUpBuy?) async -> Preview? {
        // A buy on this network waits for Face ID (prd §1545).
        let roundUp = sessionRoundUp(asked, on: net)
        guard let (callData, salt) = try? await sessionCall(sends, roundUp: roundUp, account: account),
              let op = try? await sessionBuild(net, account: account, callData: callData, salt: salt) else { return nil }
        let steps: [Step] = sends.compactMap { YourAccountOp.call(for: $0).map { ([$0], nil) } }
        let symbols = Dictionary(sends.compactMap { p in p.token.contract.map { ($0.lowercased(), p.token.symbol) } },
                                 uniquingKeysWith: { a, _ in a })
        let simulated = await check(net, account: account, approvals: [], steps: steps, symbols: symbols)
        if !Task.isCancelled {
            await Prepared.keep(Prepared(items: sends.map(Item.send), roundUp: roundUp, route: .session, op: op,
                                         assembled: nil, made: Date()))
        }
        var words = sends.map { p in
            YourAccountPreview.send(YourAccountOp.spoken(p.amount, decimals: p.token.decimals), p.token.symbol,
                                    to: p.toName ?? YourAccountPreview.short(p.to))
        }
        if let roundUp {
            let dollar = YourAccountOp.dollar(on: net)
            words.append(YourAccountPreview.roundUp(YourAccountOp.spoken(roundUp.units, decimals: dollar.decimals), dollar.symbol,
                                                    buys: roundUp.target.symbol, on: roundUp.target.network))
        } else if let asked {
            let dollar = YourAccountOp.dollar(on: net)
            words.append(YourAccountPreview.roundUpKept(YourAccountOp.spoken(asked.units, decimals: dollar.decimals), dollar.symbol))
        }
        words.append(YourAccountPreview.underLimit)
        let fee = op.maxCost.map(String.init)
        return Preview(network: net, route: .session, feeWei: fee, nonce: op.nonce, checked: simulated.checked,
                       words: words, approvals: [], hash: YourAccountOp.userOpHash(op, chainId: net.chainId),
                       hashKind: .userOp, callData: op.callData,
                       refusal: await short(sends, fee: fee, net: net, account: account))
    }

    private static func empty(_ a: Assembled, route: Prepared.Signs, refusal: String) -> Preview {
        Preview(network: a.net, route: route, feeWei: nil, nonce: nil, checked: a.simulated.checked, words: a.words,
                approvals: a.approvals, sold: a.sold, hash: nil, hashKind: .eip712, callData: [], refusal: refusal)
    }

    /// `operate`'s own balance rule, said before the tap: ETH for what is
    /// sent and the most the fee can be.
    private static func short(_ payments: [YourAccountOp.Payment], fee: String?, net: Network, account: String,
                              deployed: Bool = true) async -> String? {
        guard let fee, var held = await balance(net, YourAccountOp.eth, of: account) else { return nil }
        if deployed { held = YourAccountOp.sum(held, await feeDeposit(net, of: account)) }
        #if DEBUG
        // `-moveSimulateETH` (prd §1542): the same pretended balance the
        // simulation runs with, so Details can be seen; `transact` still refuses.
        if let pretended = simulatedETH { held = pretended }
        #endif
        let out = payments.filter { $0.token.contract == nil }.reduce("0") { YourAccountOp.sum($0, $1.amount) }
        let need = YourAccountOp.sum(out, fee)
        guard !YourAccountOp.atMost(need, held) else { return nil }
        return shortOfETH(need: need, held: held, on: net, deployed: deployed)
    }

    // MARK: - The demo (§1475)

    /// The demo's preview off its table: its fee, its nonce, the calls in
    /// words, and a real SafeOp over its sends, so Raw transaction shows the
    /// encoders' own bytes. Nothing is asked of any node.
    private static func demoPreview(_ items: [Item], on net: Network) -> Preview {
        typealias Words = YourAccountPreview
        func figure(_ units: String, _ token: YourAccountOp.Token) -> String { YourAccountOp.spoken(units, decimals: token.decimals) }
        var calls: [YourAccountOp.Call] = []
        var words: [Words.Step] = []
        var approvals: [Words.Approval] = []
        var least: (String, YourAccountOp.Token)?
        var sold: [Words.Sold] = []
        for item in items {
            switch item {
            case .send(let p):
                if let c = YourAccountOp.call(for: p) { calls.append(c) }
                words.append(Words.send(figure(p.amount, p.token), p.token.symbol, to: p.toName ?? Words.short(p.to)))
            case .swap(let s) where s.quote.wrap != nil:
                // WETH and ETH one for one (prd §1559): the one call, its words.
                if let w = s.quote.wrap {
                    calls += s.quote.calls.compactMap(YourAccountSwap.accountCall)
                    words.append(Words.wrap(w, figure(s.amount, s.sell)))
                    least = (least.map { YourAccountOp.sum($0.0, s.amount) } ?? s.amount, s.buy)
                    sold.append(Words.Sold(token: s.sell, amount: s.amount, route: nil, wrap: w))
                }
            case .swap(let s):
                let venue = s.quote.route?.venue
                if let contract = s.sell.contract, let router = venue?.router,
                   let approve = YourAccountSwap.approvalCalls([(contract, router, s.amount)])?.first {
                    calls.insert(approve, at: approvals.count)
                    approvals.append(Words.Approval(figure: figure(s.amount, s.sell), symbol: s.sell.symbol,
                                                    spender: venue?.exchange ?? "Uniswap"))
                }
                words.append(Words.swap(figure(s.amount, s.sell), s.sell.symbol, atLeast: figure(s.quote.minimumBuy, s.buy), s.buy.symbol,
                                        on: venue?.exchange ?? "Uniswap"))
                least = (least.map { YourAccountOp.sum($0.0, s.quote.minimumBuy) } ?? s.quote.minimumBuy, s.buy)
                sold.append(Words.Sold(token: s.sell, amount: s.amount, route: s.quote.route, across: s.quote.across))
            }
        }
        words = approvals.map { Words.approve($0.figure, $0.symbol, to: $0.spender) } + words
        words.append(Words.rotate(to: YourAccountDemo.previewKey))
        let key = YourAccountDemo.previewKeyXY
        let callData = YourAccountOp.callData(calls: calls, rotateTo: key) ?? []
        var op = YourAccountOp.Op(sender: YourAccountDemo.address, nonce: YourAccountDemo.previewNonce,
                                  factory: nil, factoryData: [], callData: callData)
        op.verificationGasLimit = 420_000
        op.callGasLimit = 140_000
        op.preVerificationGas = 60_000
        op.maxFeePerGas = YourAccountDemo.previewMaxFee(on: net)
        op.maxPriorityFeePerGas = op.maxFeePerGas / 10
        // The demo's refusing address: its token refuses the transfer, as a
        // blacklisted recipient's USDC does (canvas figure 9).
        let refused = items.enumerated().first { _, item in
            if case .send(let p) = item { return p.to.lowercased() == YourAccountDemo.refusing }
            return false
        }
        var checked: YourAccountPreview.Checked = least.map { .returnsAtLeast($0.0, $0.1) } ?? .lands
        if let (n, item) = refused, case .send(let p) = item {
            checked = .fails(call: n, token: p.token.symbol, reason: "Blacklistable: account is blacklisted")
        }
        return Preview(network: net, route: .owner, feeWei: op.maxCost.map(String.init), nonce: op.nonce,
                       checked: checked, words: words, approvals: approvals,
                       sold: sold, hash: YourAccountOp.safeOpHash(op, chainId: net.chainId), hashKind: .eip712, callData: callData)
    }
}
