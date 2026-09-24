import SwiftUI

/// PAYING FOR SOMEBODY ELSE'S FRAMES TRANSACTION (prd §728c) — the sheet a
/// sponsorship link opens on the phone asked to pay.
///
/// **Everything it says is derived from what it would sign.** The request is
/// parameters, rebuilt here by `FramesTransaction.sponsored`, so the people
/// and amounts drawn are read off the same frames the signature commits to —
/// and a token's name is asked of its contract rather than taken from the
/// request, which the sender wrote.
///
/// **It refuses before it prompts** (§530's ruling): a request for another
/// account, one past its deadline, one whose sender has since sent something
/// else, or one it cannot read, says so and offers no verb — Face ID over a
/// transaction the chain will refuse is a prompt that costs attention for
/// nothing.
struct FramesSponsorSheet: View {
    let request: FramesSponsorRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome

    @State private var senderNonce: UInt64?
    @State private var tokens: [String: TokenName] = [:]
    @State private var busy = false
    @State private var errorText: String?
    @State private var now = Date()

    struct TokenName: Equatable {
        var symbol: String?
        var decimals: Int?
    }

    private var mine: String? { FramesKey.address() }
    private var watched: [String] { FramesName.watched }
    private var fields: FramesTransaction.Fields? { FramesSponsor.fields(request) }

    /// Nil in the demo, where nothing is signed and the sheet is shown as a
    /// picture of the flow.
    private var refusal: FramesSponsor.Refusal? {
        guard !DemoMode.isActive else { return nil }
        return FramesSponsor.refusal(request, mine: mine, now: now, senderNonce: senderNonce)
    }

    var body: some View {
        DSTray(title: String(localized: "Pay for a transaction"), height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    legsBlock
                    facts
                    verb
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
        .task { await load() }
    }

    /// Head, facts and verb, plus a row per leg. Scrollable past it with the
    /// `.large` detent, so a short guess costs a drag rather than a clip.
    private var trayHeight: CGFloat {
        min(860, 470 + CGFloat(request.legs.count) * 56)
    }

    // MARK: The ask

    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            WalletFace(address: request.sender, size: DS.Face.shelf, circular: true)
            DSProse.text("\(FramesName.of(request.sender, mine: mine, watched: watched)) asks you to pay the fee")
                .dsText(.reading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            DSProse.text("Only the fee leaves your account. What it sends comes from theirs.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsSheetHeadBlock()
    }

    // MARK: What it pays for

    @ViewBuilder private var legsBlock: some View {
        if let legs = FramesSponsor.legs(request) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                    let paid = person(leg)
                    HStack(spacing: DS.Space.s3) {
                        WalletFace(address: paid, size: DS.Face.list, circular: true)
                        Text(FramesName.of(paid, mine: mine, watched: watched))
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(amount(leg))
                            .dsText(.price17).foregroundStyle(DS.textPrimary)
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    /// The person a leg pays: the transfer's argument for a token leg, the
    /// frame's target for a coin leg.
    private func person(_ leg: FramesTransaction.Leg) -> String {
        tokenTransfer(leg)?.recipient ?? ("0x" + RLP.hex(leg.recipient))
    }

    private func tokenTransfer(_ leg: FramesTransaction.Leg) -> FramesRead.Frame.TokenTransfer? {
        guard !leg.data.isEmpty else { return nil }
        return FramesRead.Frame(mode: 2, flags: 0, target: "0x" + RLP.hex(leg.recipient),
                                executionGas: nil, stateGas: nil, value: "0x0",
                                data: "0x" + RLP.hex(leg.data)).tokenTransfer
    }

    private func amount(_ leg: FramesTransaction.Leg) -> String {
        if let transfer = tokenTransfer(leg) {
            let contract = "0x" + RLP.hex(leg.recipient)
            let name = tokens[contract.lowercased()]
            let move = FramesTokenMove(contract: contract, raw: transfer.raw,
                                       symbol: name?.symbol, decimals: name?.decimals)
            return String(move.signedLine.dropFirst())
        }
        return FramesMoney.eth(fromWeiHex: "0x" + RLP.hex(leg.value), places: 6)
            .map { String(localized: "\($0) test ETH") } ?? "—"
    }

    // MARK: The facts

    @ViewBuilder private var facts: some View {
        DSSpecTable {
            // **AT MOST, and said as at most.** The payer is charged this up
            // front and refunded what the transaction does not use, so the
            // real fee is smaller and never larger.
            if let fields,
               let most = FramesMoney.fee(wei: Decimal(FramesTransaction.maxGas(fields))
                                              * Decimal(fields.maxFeePerGas)) {
                DSSpecRow(label: Text("You pay at most"), value: Text(verbatim: most))
            }
            DSSpecRow(label: Text("Expires"),
                      value: Text(verbatim: FramesSend.date(request.deadline)
                        .formatted(date: .omitted, time: .shortened)))
            if request.legs.count > 1 {
                DSSpecRow(label: Text("All or nothing"),
                          value: Text(request.atomic ? String(localized: "Yes") : String(localized: "No")))
            }
        }
    }

    // MARK: The verb

    @ViewBuilder private var verb: some View {
        if let refusal {
            Text(FramesSponsor.sentence(refusal))
                .dsText(.body17).foregroundStyle(DS.destructive)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let errorText {
                    Text(errorText)
                        .dsText(.label12).foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DSActVerb(title: String(localized: "Pay for it"),
                          glyph: "checkmark.seal",
                          tint: DS.tint,
                          busy: busy,
                          disabled: busy,
                          act: pay)
            }
        }
    }

    private func load() async {
        now = Date()
        guard !DemoMode.isActive else { return }
        senderNonce = await FramesSend.currentNonce(for: request.sender)
        guard let legs = FramesSponsor.legs(request) else { return }
        for leg in legs where !leg.data.isEmpty {
            let contract = "0x" + RLP.hex(leg.recipient)
            guard tokens[contract.lowercased()] == nil else { continue }
            let meta = await DevnetTokens.metadata(contract: contract) { method, params in
                await FramesRPC.call(method: method, params: params)
            }
            tokens[contract.lowercased()] = TokenName(symbol: meta.symbol, decimals: meta.decimals)
        }
    }

    private func pay() {
        guard !DemoMode.isActive else {
            errorText = String(localized: "Nothing is sent in the demo — this is where your own key would sign it.")
            return
        }
        busy = true
        errorText = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let hash = try await FramesSend.payForSponsor(request)
                // Filed under THIS phone's account: the sponsor's history is
                // where a fee it paid belongs, and the ledger lists it there
                // whether or not the transaction moved this account's coin.
                FramesLiveState.shared.notePending(hash: hash, legs: request.legs.count,
                                                   deadline: FramesSend.date(request.deadline),
                                                   sender: request.sponsor)
                DSHaptic.success()
                chrome.rain(sources: [FramesIdentity.source])
                dismiss()
                await FramesLiveState.shared.refresh()
            } catch let failure as FramesSend.Failure {
                errorText = FramesSend.sentence(failure)
            } catch {
                errorText = String(localized: "Couldn't send.")
            }
        }
    }
}
