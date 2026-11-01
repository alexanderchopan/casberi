import Foundation

/// **DETAILS: THIS EXACT OPERATION, BEFORE THE TAP (prd §1509 item 1).**
/// Move asks for a preview whenever its sentence settles: the same calls
/// `transact` signs (`assemble`), the same unsigned operation (`build`), with
/// the co-signer where the account needs it, simulated. What comes back is the fee ceiling, the nonce, what the
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
        /// pay, a node that would not price it, no co-signer where both keys
        /// are needed.
        var refusal: String? = nil
        /// Your Signer signs this too: the account needs both keys on this
        /// network (prd §1456, §1570).
        var signerSigns = false
    }

    /// An operation built for a preview, kept for signing (prd §1509).
    struct Prepared: @unchecked Sendable {
        enum Signs: Equatable, Sendable { case owner, bothKeys }
        let items: [Item]
        let roundUp: RoundUpBuy?
        let route: Signs
        let op: YourAccountOp.Op
        let assembled: AssembledParts?
        let made: Date
        /// The module's own answer for `op` exactly, asked with the preview
        /// (prd §1605): signing this operation unchanged checks its hash
        /// against it with no round trip of its own.
        var moduleAnswer: (entry: YourAccountOp.Entry, bytes: [UInt8])? = nil

        /// How long a kept operation may be signed as it stands: inside
        /// it a gas price, a quote and a nonce have rarely moved; the nonce
        /// and the bytes are checked again anyway, and the calls simulated
        /// again.
        static let lifetime: TimeInterval = 60

        private static let store = Store()

        static func keep(_ p: Prepared) async { await store.put(p) }

        /// The kept operation for exactly these items on this route, fresh
        /// enough; taken, so it is signed at most once.
        ///
        /// **A PREVIEW STILL BEING MADE IS WAITED FOR (prd §1610).** A tap
        /// while the preview of these same items is reading took the long
        /// way and asked every one of its questions a second time; now it
        /// waits for that preview, up to `joinWait`, and signs what it made.
        static func take(_ items: [Item], roundUp: RoundUpBuy?, route: Signs) async -> Prepared? {
            let until = Date().addingTimeInterval(joinWait)
            while true {
                let (p, making) = await store.take(making: { same($0, items) }) { p in
                    same(p.items, items) && p.roundUp == roundUp && p.route == route
                        && Date().timeIntervalSince(p.made) < lifetime
                }
                if let p { return p }
                guard making, Date() < until, !Task.isCancelled else { return nil }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        /// The longest a tap waits on a preview of its own items.
        static let joinWait: TimeInterval = 20

        /// A preview of `items` is being made; `end` when it is done, kept or not.
        static func begin(_ items: [Item]) async -> UUID { await store.begin(items) }
        static func end(_ id: UUID) async { await store.end(id) }

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
            private var making: [UUID: [Item]] = [:]
            func put(_ p: Prepared) { kept = p }
            func begin(_ items: [Item]) -> UUID {
                let id = UUID()
                making[id] = items
                return id
            }
            func end(_ id: UUID) { making[id] = nil }
            /// The kept operation if it matches, and whether a preview of
            /// these items is still being made.
            func take(making same: ([Item]) -> Bool, where matches: (Prepared) -> Bool) -> (Prepared?, Bool) {
                if let p = kept, matches(p) {
                    kept = nil
                    return (p, false)
                }
                return (nil, making.values.contains(where: same))
            }
        }
    }

    /// What signing `items` would do now, without signing. Never throws: a
    /// refusal is the preview's `refusal`, said in Details and the line.
    static func preview(_ items: [Item], account: String, roundUp: RoundUpBuy?) async -> Preview? {
        guard let net = items.first?.network, items.allSatisfy({ $0.network == net }) else { return nil }
        if YourAccountDemo.isDemo(account) { return demoPreview(items, on: net) }
        let making = await Prepared.begin(items)
        defer { Task { await Prepared.end(making) } }
        // Move's send passes no co-signer; `operate` asks one where the
        // account needs both keys, so the kept operation is the owner's.
        let route: Prepared.Signs = .owner
        // What assembling wrote, kept for a refusal after it: the bundler
        // refusing to price the operation still leaves Details the calls in
        // words, the pools and the simulation's verdict (prd §1545).
        var written: Assembled?
        do {
            let parts = try await assemble(items, account: account, roundUp: roundUp)
            written = parts.assembled
            let a = parts.assembled
            let entry: YourAccountOp.Entry = a.deployed ? try await knownEntry(net, account) : .module4337
            // Who signs beside this phone: the one `operate` asks itself
            // when the account needs both keys.
            var coSigner: String?
            if a.deployed, entry == .adapter, try await knownThreshold(net, account) >= 2 {
                // `operate` refuses this at signing; say so now.
                guard let first = try await knownSigners(net, account).first else {
                    return empty(a, route: route, refusal: String(localized: "Your Signer signs this too, and none is on \(net.name)"))
                }
                coSigner = first
            }
            let op = try await build(net, account: account, deployed: a.deployed, entry: entry, calls: a.calls,
                                     rotateTo: a.nextKey, signerOwner: a.signer.owner, coSignerOwner: coSigner)
            let fee = op.maxCost.map(String.init)
            // The module asked for this operation's hash now, beside the
            // balances (prd §1605), so the tap need not ask it.
            async let answer = try? moduleAnswer(net, entry: entry, op: op)
            let refusal = await short(a.payments, fee: fee, net: net, account: account, deployed: a.deployed)
            // A preview the sentence has moved past is never kept: it would
            // take the place of the one now on screen.
            if !Task.isCancelled {
                await Prepared.keep(Prepared(items: items, roundUp: roundUp, route: route, op: op, assembled: parts, made: Date(),
                                             moduleAnswer: (await answer).map { (entry: entry, bytes: $0) }))
            }
            return Preview(network: net, route: route, feeWei: fee, nonce: op.nonce, checked: a.simulated.checked,
                           words: a.words, approvals: a.approvals, sold: a.sold, hash: YourAccountOp.safeOpHash(op, chainId: net.chainId),
                           hashKind: .eip712, callData: op.callData, refusal: refusal, signerSigns: coSigner != nil)
        } catch let failure as Failure {
            if let written { return empty(written, route: route, refusal: failure.message) }
            return Preview(network: net, route: route, feeWei: nil, nonce: nil, checked: .notChecked, words: [],
                           approvals: [], hash: nil, hashKind: .eip712, callData: [], refusal: failure.message)
        } catch {
            return Preview(network: net, route: route, feeWei: nil, nonce: nil, checked: .notChecked, words: [],
                           approvals: [], hash: nil, hashKind: .eip712, callData: [], refusal: String(localized: "\(net.name) did not answer"))
        }
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
