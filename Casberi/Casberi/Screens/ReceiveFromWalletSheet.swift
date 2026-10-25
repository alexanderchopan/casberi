import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// **Receive › From another wallet (prd §1506).** A wallet of your own
/// elsewhere connects, Casberi reads what it holds on every network it
/// agreed to, and you approve each send in that wallet: what is on your
/// account's networks straight to your address, the rest through Relay to
/// Base. One sheet, five moments — connect, read, choose, approve, done —
/// and the connection is torn down when it closes, answered or not.
struct ReceiveFromWalletSheet: View {
    let account: String
    @State private var model: Model

    init(account: String, sample: Bool = false) {
        self.account = account
        _model = State(initialValue: Model(account: account, sample: sample))
    }

    var body: some View {
        DSTray(title: String(localized: "From another wallet"), height: 640, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                switch model.stage {
                case .connecting(let url): connecting(url)
                case .reading: waiting(String(localized: "Reading \(model.short) on every network"))
                case .choosing: choosing
                case .sending(let index): sending(index)
                case .done: done
                case .failed(let words): failed(words)
                }
            }
            .animation(DS.Motion.standard, value: model.stage)
        }
        .task { await model.start() }
        .onDisappear { model.close() }
    }

    // MARK: - Connect

    @ViewBuilder private func connecting(_ url: URL?) -> some View {
        Text("Connect the wallet the money is in, then approve.")
            .dsText(.body17).foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if let url {
            if let code = SignerRequestSheet.code(url.absoluteString) {
                Image(uiImage: code)
                    .interpolation(.none).resizable().scaledToFit()
                    .frame(maxWidth: 240)
                    .padding(DS.Space.s3)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("WalletConnect code"))
            }
            DSDoorRow(icon: "arrow.up.forward.app", label: "Open wallet") {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                } else {
                    DSPasteboard.copySensitive(url.absoluteString)
                    model.copiedInstead = true
                }
            }
            if model.copiedInstead {
                Text("No wallet here opens it: the link is copied, paste it in yours.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DSCopyRow(value: url.absoluteString, label: "Copy link", sensitive: true)
        }
        waitingLine(String(localized: "Waiting for your wallet"))
    }

    // MARK: - Choose

    @ViewBuilder private var choosing: some View {
        let plan = model.plan
        if plan.legs.isEmpty {
            Text("Nothing in \(model.short) can move to you.")
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
        } else {
            Text(model.sentence)
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(plan.legs) { leg in
                let on = model.picked.contains(leg.id)
                Button {
                    DSHaptic.selection()
                    if on { model.picked.remove(leg.id) } else { model.picked.insert(leg.id) }
                } label: {
                    row(Self.words(leg.holding.symbol, raw: leg.amount, decimals: leg.holding.decimals),
                        symbol: leg.holding.symbol,
                        line: Self.line(leg), figure: WalletValue.exactMoney(leg.usd), on: on)
                }
                .buttonStyle(RowPress())
            }
        }
        if !plan.stays.isEmpty {
            Text("Stays in \(model.short)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s3)
            ForEach(plan.stays, id: \.0.id) { held, why in
                row(Self.words(held.symbol, raw: held.raw, decimals: held.decimals),
                    symbol: held.symbol,
                    line: "\(held.networkName) · \(Self.reason(why))", figure: WalletValue.exactMoney(held.usd), on: nil)
            }
        }
        if !plan.legs.isEmpty {
            DSSlabButton(title: model.verb, enabled: !model.picked.isEmpty) { model.send() }
                .padding(.top, DS.Space.s3)
            // Approving is the wallet's, one send at a time; a network's
            // own coin goes last, less what the sends cost.
            DSFootnote(prose: String(localized: "You approve each send in your wallet. Each network keeps a little of its own coin to pay for them."),
                       scale: .page)
        }
    }

    private func row(_ title: String, symbol: String, line: String, figure: String, on: Bool?) -> some View {
        HStack(spacing: DS.Space.s3) {
            // Every token row in Move wears its mark (prd §1534); one that
            // stays behind is dimmed with its words.
            AssetMark(name: symbol, size: DS.Face.list)
                .opacity(on == true ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).dsText(.body17)
                    .foregroundStyle(on == false ? DS.textTertiary : on == nil ? DS.textSecondary : DS.textPrimary)
                Text(verbatim: line).dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: figure).dsText(.body17).monospacedDigit()
                .foregroundStyle(on == true ? DS.textPrimary : DS.textTertiary)
            if let on {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(.body, weight: .medium)
                    .foregroundStyle(on ? DS.pickInk : DS.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Approve, then done

    @ViewBuilder private func sending(_ index: Int) -> some View {
        let legs = model.sendingLegs
        Text("Approve \(index + 1) of \(legs.count) in \(model.walletName)")
            .dsText(.heading24).foregroundStyle(DS.textPrimary)
        ForEach(Array(legs.enumerated()), id: \.element.id) { i, leg in
            HStack(spacing: DS.Space.s3) {
                Text(verbatim: Self.words(leg.holding.symbol, raw: leg.amount, decimals: leg.holding.decimals))
                    .dsText(.body17).foregroundStyle(i <= index ? DS.textPrimary : DS.textTertiary)
                Spacer()
                if model.sent[leg.id] != nil {
                    Text("Sent").dsText(.body17).foregroundStyle(DS.confirmInk)
                } else if model.refused[leg.id] != nil {
                    Text("Not sent").dsText(.body17).foregroundStyle(DS.attentionInk)
                } else if i == index {
                    DSSpinner()
                }
            }
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder private var done: some View {
        Text(model.receipt).dsText(.heading24).foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        if model.sent.values.contains(where: { _ in true }), model.sendingLegs.contains(where: { if case .relay = $0.way { true } else { false } }) {
            Text("What comes through Relay lands on Base in a few minutes.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(model.sendingLegs.filter { model.refused[$0.id] != nil }) { leg in
            Text("\(leg.holding.symbol) on \(leg.holding.networkName) was not sent: \(model.refused[leg.id] ?? "")")
                .dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func failed(_ words: String) -> some View {
        Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
            .fixedSize(horizontal: false, vertical: true)
        DSSlabButton(title: String(localized: "Try again")) { Task { await model.start() } }
    }

    private func waiting(_ words: String) -> some View { waitingLine(words) }

    private func waitingLine(_ words: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            DSSpinner()
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Words

    static func words(_ symbol: String, raw: String, decimals: Int) -> String {
        let n = WalletSweep.amount(raw, decimals: decimals)
        let digits = n >= 100 ? 0 : n >= 1 ? 2 : 4
        return "\(n.formatted(.number.precision(.fractionLength(0...digits)))) \(symbol)"
    }

    static func line(_ leg: WalletSweep.Leg) -> String {
        switch leg.way {
        case .direct: leg.holding.networkName
        case .relay(_, let arrives): String(localized: "\(leg.holding.networkName) · as \(arrives) on Base, through Relay")
        }
    }

    static func reason(_ why: WalletSweep.Stay) -> String {
        switch why {
        case .tooSmall: String(localized: "too small to move")
        case .noRoute: String(localized: "Relay doesn't move it")
        case .noGas: String(localized: "not enough for gas")
        case .forGas: String(localized: "kept for gas")
        }
    }

    // MARK: - Presenting

    /// Over whatever is on screen, as the Signer's sheet is; the connection
    /// closes with it.
    @MainActor
    static func present(account: String, sample: Bool = false) {
        let host = UIHostingController(rootView: ReceiveFromWalletSheet(account: account, sample: sample))
        host.view.backgroundColor = .systemBackground
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(host, animated: true)
    }
}

extension ReceiveFromWalletSheet {
    @MainActor @Observable
    final class Model {
        enum Stage: Equatable {
            case connecting(URL?)
            case reading
            case choosing
            case sending(Int)
            case done
            case failed(String)
        }

        let account: String
        let sample: Bool
        var stage: Stage = .connecting(nil)
        var copiedInstead = false
        var plan = WalletSweep.Plan(legs: [], stays: [])
        var picked: Set<String> = []
        var sendingLegs: [WalletSweep.Leg] = []
        var sent: [String: String] = [:]
        var refused: [String: String] = [:]
        var walletName = String(localized: "your wallet")
        private var pairing: YourAccountSignerLink.Pairing?
        private var source = ""

        init(account: String, sample: Bool) {
            self.account = account
            self.sample = sample
        }

        var short: String { source.isEmpty ? String(localized: "your wallet") : WalletStore.shortAddress(source) }

        private var pickedLegs: [WalletSweep.Leg] { plan.legs.filter { picked.contains($0.id) } }

        /// "Receive $1,240 from 0xab…cd." — the picked money, whose it is.
        var sentence: String {
            String(localized: "Receive \(WalletValue.exactMoney(pickedLegs.reduce(0) { $0 + $1.usd })) from \(short).")
        }

        var verb: String {
            String(localized: "Receive \(WalletValue.exactMoney(pickedLegs.reduce(0) { $0 + $1.usd }))")
        }

        var receipt: String {
            let moved = sendingLegs.filter { sent[$0.id] != nil }.reduce(0) { $0 + $1.usd }
            return moved > 0 ? String(localized: "Received \(WalletValue.exactMoney(moved)) from \(short).")
                             : String(localized: "Nothing was sent.")
        }

        func start() async {
            copiedInstead = false
            if sample { return loadSample() }
            stage = .connecting(nil)
            do {
                let pairing = try await YourAccountSignerLink.connect(
                    signer: nil, chainIds: WalletSweepLive.chainIds, method: WalletSweepLive.method
                ) { url in self.stage = .connecting(url) }
                self.pairing = pairing
                source = pairing.signer
                stage = .reading
                plan = await WalletSweepLive.plan(for: pairing.signer, on: pairing.chainIds, account: account)
                picked = Set(plan.legs.map(\.id))
                stage = .choosing
            } catch YourAccountSignerLink.Failure.timedOut {
                stage = .failed(String(localized: "Your wallet didn't connect."))
            } catch {
                stage = .failed(String(localized: "WalletConnect isn't reachable right now."))
            }
        }

        func send() {
            sendingLegs = pickedLegs
            guard !sendingLegs.isEmpty else { return }
            Task {
                for (i, leg) in sendingLegs.enumerated() {
                    stage = .sending(i)
                    if sample {
                        try? await Task.sleep(for: .seconds(1))
                        sent[leg.id] = "0xsample"
                        continue
                    }
                    guard let pairing else { refused[leg.id] = String(localized: "the wallet disconnected"); continue }
                    do {
                        sent[leg.id] = try await WalletSweepLive.send(leg, over: pairing, account: account)
                        DSHaptic.success()
                    } catch YourAccountSignerLink.Failure.refused(let why) {
                        refused[leg.id] = why.isEmpty ? String(localized: "refused in the wallet") : why
                    } catch {
                        refused[leg.id] = String(localized: "no answer from the wallet")
                    }
                }
                stage = .done
                close()
            }
        }

        func close() {
            if let pairing { YourAccountSignerLink.close(pairing) }
            pairing = nil
        }

        /// `-moveFromWallet sample`: the choosing page over made-up holdings,
        /// no connection, so the sheet can be seen on a simulator.
        private func loadSample() {
            source = "0xab12000000000000000000000000000000c0ffee"
            walletName = "Rainbow"
            let holdings: [WalletSweep.Holding] = [
                .init(chainId: 8453, networkName: "Base", symbol: "USDC", contract: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
                      decimals: 6, raw: "120000000", usd: 120),
                .init(chainId: 8453, networkName: "Base", symbol: "ETH", contract: nil, decimals: 18,
                      raw: "400000000000000000", usd: 1_540),
                .init(chainId: 42161, networkName: "Arbitrum", symbol: "USDT", contract: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9",
                      decimals: 6, raw: "45000000", usd: 45),
                .init(chainId: 42161, networkName: "Arbitrum", symbol: "ETH", contract: nil, decimals: 18,
                      raw: "30000000000000000", usd: 115),
                .init(chainId: 10, networkName: "Optimism", symbol: "OP", contract: "0x4200000000000000000000000000000000000042",
                      decimals: 18, raw: "12000000000000000000", usd: 21),
                .init(chainId: 8453, networkName: "Base", symbol: "DEGEN", contract: "0x4ed4e862860bed51a9570b96d89af5e1b0efefed",
                      decimals: 18, raw: "2000000000000000000", usd: 0.4),
            ]
            var plan = WalletSweep.plan(holdings, yours: WalletSweepLive.yours, relayable: { _, _ in true },
                                        gasPrice: [8453: 10_000_000, 42161: 10_000_000])
            plan.legs = plan.legs.map { leg in
                var leg = leg
                if !WalletSweepLive.yours.contains(leg.holding.chainId) {
                    leg.way = .relay(address: "0x0000000000000000000000000000000000000001",
                                       arrives: leg.holding.isNative ? "ETH" : "USDC")
                }
                return leg
            }
            self.plan = plan
            picked = Set(plan.legs.map(\.id))
            stage = .choosing
        }
    }
}
