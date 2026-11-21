import SwiftUI

/// **DETAILS, UNDER THE SENTENCE (prd §1509 item 1, canvas figures 2 and
/// 4).** The rows Move's grey line opens with its last word: for a send the
/// full address, from, the network fee in its coin, the nonce and what the
/// simulation found; for a swap the least it returns, where it swaps and the
/// pool's fee (prd §1539), the network fee, the exact approval, the nonce and
/// the simulation. Then one door,
/// Raw transaction. Nothing here is a control but the door: the sentence
/// above is still the screen.
struct MoveDetails: View {
    typealias Op = YourAccountOp
    typealias Words = YourAccountPreview

    /// Nil while it is being read.
    let preview: YourAccountChain.Preview?
    let swap: Bool
    /// Who a send goes to, in the sentence's order, once each.
    let to: [String]
    let account: String
    /// The network fee's ceiling in dollars at the Wallet's ETH price.
    let networkFeeUSD: Double?
    /// Every warning, in order, each with whether it is red (prd §1509 item
    /// 2: the line shows one, Details lists them all), and what the
    /// addresses were checked against.
    var warnings: [(text: String, red: Bool)] = []
    var checkedWith: [String] = []
    /// **READY IS ONE RECEIPT (prd §1932):** the rows continue the receipt's
    /// lines (Fee, Check, the warnings in their ink), and what only a careful
    /// reader wants (the lists asked, Raw transaction) waits behind Details.
    var lines = false
    var open = false
    var onOpen: (() -> Void)? = nil
    let onRaw: () -> Void

    var body: some View {
        if lines { linesBody } else { rowsBody }
    }

    private var linesBody: some View {
        VStack(alignment: .leading, spacing: MoveReceipt.gap) {
            if let preview {
                if swap { swapRows(preview) } else { sendRows(preview) }
                checkedRow(preview)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                    MoveReceiptNote(text: w.text, ink: w.red ? DS.destructiveInk : DS.attentionInk)
                }
                MoveReceiptLine(label: "") {
                    MoveChip(text: String(localized: "Details"), tone: open ? .answered : .empty,
                             trail: open ? "chevron.up" : "chevron.down") { onOpen?() }
                }
                if open {
                    // One source a line: a list's own name holds commas.
                    ForEach(Array(checkedWith.enumerated()), id: \.offset) { n, source in
                        MoveReceiptNote(text: n == 0 ? String(localized: "Checked with \(source)") : source)
                    }
                    if preview.hash != nil {
                        MoveReceiptLine(label: "") {
                            MoveChip(text: String(localized: "Raw transaction"), tone: .answered, trail: "chevron.right", action: onRaw)
                        }
                    }
                }
            } else {
                MoveReceiptLine(label: "") {
                    DSSpinner()
                    Text("Checking").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
        }
        .transition(.opacity)
    }

    private var rowsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview {
                if swap { swapRows(preview) } else { sendRows(preview) }
                // The nonce, the whole address and who sends are Raw
                // transaction's (prd §1916): the receipt reads in words.
                checkedRow(preview)
                foundRows
                if preview.hash != nil {
                    DSPushRow(title: Text("Raw transaction"), action: onRaw) { EmptyView() }
                }
            } else {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Checking").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .walletRowPitch()
            }
        }
        // No air of its own: in the deck it continues the receipt's rows at
        // their one pitch (prd §1916).
        .transition(.opacity)
    }

    // MARK: - A send

    @ViewBuilder private func sendRows(_ p: YourAccountChain.Preview) -> some View {
        // **TO IS A NAME AND A TAIL (prd §1916, user, 2026-11-19, of the
        // receipt's 42 characters):** the whole address, checksummed, is Raw
        // transaction's, where it is copied.
        // On the receipt, To is its own line already (prd §1932).
        if !lines {
            ForEach(to, id: \.self) { address in
                let name = AddressBook.shared.entry(for: address)?.name
                row(String(localized: "To"), [name, AddressTail.short(address)].compactMap { $0 }.joined(separator: " "))
            }
        }
        // A round-up bought on the exchanges with the send (prd §1545): where,
        // its pool fee, and the exact approval it makes, as a swap's are.
        ForEach(Array(exchanges(p).enumerated()), id: \.offset) { _, words in
            row(String(localized: "Round-up"), words)
        }
        feeRow(p)
        ForEach(Array(p.approvals.enumerated()), id: \.offset) { _, a in
            // The spender stays in the value: who may spend is a security fact.
            row(String(localized: "Approves"), String(localized: "\(a.figure) \(a.symbol) to \(a.spender)"))
        }
    }

    /// The network fee, its ceiling in dollars over the coin; "Not priced"
    /// with why when the bundler would not estimate it.
    private func feeRow(_ p: YourAccountChain.Preview) -> some View {
        guard let wei = p.feeWei else {
            return row(String(localized: "Network fee"), String(localized: "Not priced"))
        }
        // From your USDC (prd §1780): the paymaster's most, in its dollars.
        if let units = p.gasUSDC {
            return row(String(localized: "Network fee"), String(localized: "Up to $\(YourAccountGas.spoken(units)) from your USDC"))
        }
        let coin = "\(Words.coin(wei)) ETH"
        guard let usd = networkFeeUSD else { return row(String(localized: "Network fee"), String(localized: "Up to \(coin)")) }
        let value = usd < 0.01 ? String(localized: "Under a cent") : String(localized: "Up to \(MoveSentence.money(usd))")
        return row(String(localized: "Network fee"), value)
    }

    // MARK: - A swap

    @ViewBuilder private func swapRows(_ p: YourAccountChain.Preview) -> some View {
        if let leg = p.sold.compactMap(\.across).first {
            // **TO ANOTHER NETWORK (prd §1555):** what arrives — exactly
            // what a relayer pays, so its least — Across's fee, rounded as a
            // pool's, and its time.
            // A swap on arrival (prd §1566): its minimum, of what it buys there.
            let dest = Op.networks.first { $0.chainId == leg.to } ?? p.network
            let token = leg.swap?.buy ?? YourAccountAcross.token(leg.asset, on: dest)
            let least = leg.swap?.minimum ?? leg.outputAmount
            row(String(localized: "You get at least"), "\(MoveSentence.figure(least, decimals: token.decimals)) \(token.symbol)")
            // The fee is the row's name, as Network fee's is (user, 2026-11-19).
            row(String(localized: "Across fee"), YourAccountSwap.percent(pips: leg.feePips))
            if let time = YourAccountAcross.time(leg.seconds) {
                row(String(localized: "Expected time"), time)
            }
        } else if case .returnsAtLeast(let units, let token) = p.checked {
            row(String(localized: "You get at least"), "\(MoveSentence.figure(units, decimals: token.decimals)) \(token.symbol)")
        }
        // Where each swap goes, once per distinct pool: "On Uniswap · 0.05%
        // pool fee". The pool's fee is in the price, so it is never added to
        // the fee below, and there is no one else's fee to add (prd §1539).
        ForEach(Array(exchanges(p).enumerated()), id: \.offset) { _, words in
            row(String(localized: "Swaps"), words)
        }
        feeRow(p)
        ForEach(Array(p.approvals.enumerated()), id: \.offset) { _, a in
            // The spender stays in the value: who may spend is a security fact.
            row(String(localized: "Approves"), String(localized: "\(a.figure) \(a.symbol) to \(a.spender)"))
        }
    }

    /// Each swap's exchange and pool fee, once each, short enough for the
    /// row's one line: "Uniswap · 0.01%" (prd §1556).
    private func exchanges(_ p: YourAccountChain.Preview) -> [String] {
        var out: [String] = []
        for s in p.sold {
            // A wrap or an unwrap says so, no pool (prd §1559).
            if let words = s.wrap.map(YourAccountSwap.words) ?? s.route.map(YourAccountSwap.brief), !out.contains(words) {
                out.append(words)
            }
            // The swap on arrival, its network named: "Uniswap · 0.05% on Ethereum" (prd §1566).
            if let words = s.across.flatMap(YourAccountAcross.arrivalBrief), !out.contains(words) { out.append(words) }
        }
        return out
    }

    // MARK: - What the simulation found

    /// Green only when this exact operation was simulated (§83); "Not run"
    /// when the node would not, never "Goes through". **A TEST RUN, IN
    /// PLAIN WORDS (prd §1914, user, 2026-11-19: "i have no idea what 'lands
    /// as written' means"):** it was tried first, and it goes through.
    private func checkedRow(_ p: YourAccountChain.Preview) -> some View {
        switch p.checked {
        case .lands:
            return row(String(localized: "Simulated"), String(localized: "Succeeds"), ink: DS.confirmInk)
        // **SAID ONCE (prd §1916):** what it returns at least is the row
        // above, "You get at least"; the simulation says it succeeds.
        case .returnsAtLeast:
            return row(String(localized: "Simulated"), String(localized: "Succeeds"), ink: DS.confirmInk)
        case .fails:
            return row(String(localized: "Simulated"), String(localized: "Would fail"), ink: DS.destructiveInk)
        case .notChecked:
            return row(String(localized: "Simulated"), String(localized: "Not simulated"))
        }
    }

    // MARK: - The warnings

    /// "Found", every warning in its ink; "Checked with", the lists and the
    /// services asked, and the date of the list. Always TWO headings: under
    /// one "Found", the sources read as findings ("Found: OFAC's sanctions
    /// list") — a person took a first-send warning for a sanctions hit.
    @ViewBuilder private var foundRows: some View {
        if !warnings.isEmpty || !checkedWith.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Found").dsText(.body17).foregroundStyle(DS.textSecondary)
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                            Text(verbatim: w.text).dsText(.body17)
                                .foregroundStyle(w.red ? DS.destructiveInk : DS.attentionInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !checkedWith.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checked with").dsText(.body17).foregroundStyle(DS.textSecondary)
                        ForEach(checkedWith, id: \.self) { line in
                            Text(verbatim: line).dsText(.body17).foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Space.s3)
        }
    }

    // MARK: - One row

    /// A name, and its value trailing over its line: the Wallet rows' pitch
    /// (§1482), the body rung.
    /// **ONE LINE A ROW (user, 2026-10-26, prd §1555):** no subtext under
    /// any row; a fact worth keeping folds into the value.
    @ViewBuilder private func row(_ label: String, _ value: String,
                                  ink: Color = DS.textPrimary) -> some View {
        if lines {
            MoveReceiptFact(label: Self.short(label), value: value, ink: ink)
        } else {
            wideRow(label, value, ink: ink)
        }
    }

    /// The receipt's label column holds a word or two (prd §1932).
    static func short(_ label: String) -> String {
        switch label {
        case String(localized: "Network fee"): String(localized: "Fee")
        case String(localized: "Simulated"): String(localized: "Check")
        case String(localized: "You get at least"): String(localized: "At least")
        case String(localized: "Across fee"): "Across"
        case String(localized: "Expected time"): String(localized: "Time")
        default: label
        }
    }

    private func wideRow(_ label: String, _ value: String,
                         ink: Color = DS.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Text(verbatim: label).dsText(.body17).foregroundStyle(DS.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.body17).foregroundStyle(ink)
                .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        // **EVERY ROW 48 (prd §1916):** the deck's one row height.
        .frame(minHeight: MoveSentence.factHeight)
        .accessibilityElement(children: .combine)
    }
}

/// **RAW TRANSACTION, A PAGE DEEPER (prd §1509 item 1, canvas figure 3).**
/// The calls in words first, numbered, the key change included; then the
/// hash Face ID signs, labelled in ERC-8213's own terms (an "EIP-712 Digest"
/// for a SafeOp, the "Operation hash" for the session key's), and the
/// operation's calldata with its byte count and its Calldata Digest, each
/// with Copy. It takes the sentence's place in Move, its title the way back.
/// What Raw transaction shows, whoever signs it: Move's own operation, or
/// a Safe transaction the co-signer is asked for (prd §1514).
struct RawTransaction: Equatable {
    let words: [YourAccountPreview.Step]
    /// The account's nonce, which the receipt no longer shows (prd §1916).
    var nonce: UInt64? = nil
    let hash: [UInt8]
    let hashKind: YourAccountPreview.HashKind
    let callData: [UInt8]
}

extension YourAccountChain.Preview {
    var raw: RawTransaction? {
        hash.map { RawTransaction(words: words, nonce: nonce, hash: $0, hashKind: hashKind, callData: callData) }
    }
}

struct MoveRawPage: View {
    let raw: RawTransaction?
    var refusal: String? = nil
    /// Move's page draws its title, the way back; the Safe's sign block
    /// opens it in place and has none.
    var onBack: (() -> Void)? = nil
    /// Who it goes to, whole and checksummed, and who sends it: the
    /// receipt says a name and a tail (prd §1916).
    var to: [String] = []
    var from: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            // The title row indents itself to the rows' column from the
            // chassis inset; Move's page already stands in that column.
            if let onBack {
                DSRoomTitleRow(title: String(localized: "Move"), pick: String(localized: "Raw transaction"), onTitle: onBack)
                    .padding(.leading, -DSRoomChassis.titleIndent)
            }
            if let p = raw {
                let hash = p.hash
                ForEach(to, id: \.self) { address in
                    section(String(localized: "To")) {
                        Text(verbatim: EIP55.checksum(address))
                            .dsText(.mono17)
                            .foregroundStyle(DS.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        DSCopyRow(value: EIP55.checksum(address), label: "Copy address", sensitive: false)
                    }
                }
                if from != nil || p.nonce != nil {
                    section(String(localized: "From")) {
                        if let from {
                            Text("Your account \(YourAccount.short(from))").dsText(.body17).foregroundStyle(DS.textPrimary)
                        }
                        if let nonce = p.nonce {
                            Text("Nonce \(nonce)").dsText(.body17).foregroundStyle(DS.textSecondary)
                        }
                    }
                }
                section(String(localized: "What it does")) {
                    ForEach(Array(p.words.enumerated()), id: \.offset) { n, step in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                            Text(verbatim: "\(n + 1)").dsText(.body17).foregroundStyle(DS.textTertiary).monospacedDigit()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: step.words).dsText(.body17).foregroundStyle(DS.textPrimary)
                                if let detail = step.detail {
                                    Text(verbatim: detail).dsText(.subhead12).foregroundStyle(DS.textTertiary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, DS.Space.s2)
                    }
                }
                let hex = YourAccountPreview.hex(hash)
                section(p.hashKind.label) {
                    Text(verbatim: hex)
                        .dsText(.mono17)
                        .foregroundStyle(DS.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    DSCopyRow(value: hex, label: "Copy hash", sensitive: false)
                }
                let data = YourAccountPreview.hex(p.callData)
                section(String(localized: "Calldata · \(p.callData.count) bytes")) {
                    // The bytes clipped to a few lines, scrolling inside.
                    ScrollView {
                        Text(verbatim: data)
                            .dsText(.mono12)
                            .foregroundStyle(DS.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 112)
                    .scrollIndicators(.visible)
                    Text("Calldata Digest").dsText(.label12).foregroundStyle(DS.textSecondary)
                        .padding(.top, DS.Space.s2)
                    Text(verbatim: YourAccountPreview.hex(YourAccountPreview.calldataDigest(p.callData)))
                        .dsText(.mono12)
                        .foregroundStyle(DS.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    DSCopyRow(value: data, label: "Copy calldata", sensitive: false)
                }
            } else if let refusal {
                Text(verbatim: refusal).dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Checking").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: title).dsText(.label12).foregroundStyle(DS.textSecondary)
            content()
        }
    }
}
