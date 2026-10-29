import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// **The Signer is asked (prd §1447 item 17).** An operation that needs both
/// keys shows its WalletConnect link here: a code to scan with the Signer's
/// wallet on another device, a door into whichever wallet on this one takes
/// the link (user: "it can be open wallet … i just signed in rainbow each
/// time today"), the link to paste into any other. It closes itself when the
/// answer comes.
///
/// **IT CAN BE LEFT (prd §1601, user: "when there is a failed send b/c my
/// other wallet didn't sign, the screen is frozen in casberi").** Cancel, or
/// pulling the sheet down, stops the ask at once; a wallet that turns the
/// connection down ends it too. A Signer already paired is asked again with
/// no code: the sheet says to approve in its wallet and opens it.
struct SignerRequestSheet: View {
    let ask: SignerAsk
    private var signer: String? { ask.signer }
    @State private var copiedInstead = false
    /// A phone cannot scan its own screen (user: "it's only relevant if you
    /// had another phone"): there the wallet on this phone leads and the code
    /// is small, for a second device; an iPad or a Mac leads with the code.
    private let onPhone = UIDevice.current.userInterfaceIdiom == .phone

    var body: some View {
        DSTray(title: signer == nil ? String(localized: "Your Signer") : String(localized: "Your Signer signs too"),
               height: onPhone ? 420 : 600, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if ask.kept {
                    kept
                } else if let url = ask.link {
                    pairing(url)
                }
                waiting
                // No answer yet: the same question again, and the wallet
                // reopened onto it (prd §1609).
                if ask.canAskAgain {
                    DSDoorRow(icon: "arrow.clockwise", label: "Ask again") { ask.again() }
                }
                DSDoorRow(icon: "xmark", label: "Cancel") { ask.cancel() }
            }
        }
        .onDisappear { ask.dismissed() }
    }

    /// A Signer paired before: no code, its wallet asked again (prd §1601).
    @ViewBuilder private var kept: some View {
        Text(signer.map { String(localized: "Approve in the wallet holding \(AddressTail.short($0, wholeUpTo: 4)).") }
             ?? String(localized: "Approve in your wallet."))
            .dsText(.body17)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        // Opened, never asked `canOpenURL` first: a wallet's own scheme is
        // not one this app declares, so the answer would always be no.
        if let door = ask.door {
            DSDoorRow(icon: "arrow.up.forward.app", label: "Open wallet") { UIApplication.shared.open(door) }
        }
    }

    @ViewBuilder private func pairing(_ url: URL) -> some View {
                Text(onPhone
                     ? (signer.map { String(localized: "Approve in the wallet holding \(AddressTail.short($0, wholeUpTo: 4)).") }
                        ?? String(localized: "Approve twice in the wallet you want: connect, then sign."))
                     : (signer.map { String(localized: "Scan with \(AddressTail.short($0, wholeUpTo: 4)) in its wallet, then approve.") }
                        ?? String(localized: "Scan with the wallet you want, then approve twice: connect, then sign.")))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !onPhone, let code = Self.code(url.absoluteString) {
                    codeImage(code, side: 260)
                        .frame(maxWidth: .infinity)
                }
                doors(url)
                if onPhone, let code = Self.code(url.absoluteString) {
                    // The second device's door, last and small: a code, and
                    // the one line saying who it is for.
                    HStack(alignment: .center, spacing: DS.Space.s3) {
                        codeImage(code, side: 96)
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text("Wallet on another phone?")
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                            Text("Scan this with its camera.")
                                .dsText(.body17)
                                .foregroundStyle(DS.textSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, DS.Space.s3)
                }
    }

    /// The code on white, which a camera needs around it to read it.
    private func codeImage(_ code: UIImage, side: CGFloat) -> some View {
        Image(uiImage: code)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .padding(side < 160 ? DS.Space.s2 : DS.Space.s3)
            .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
            .accessibilityLabel(Text("WalletConnect code"))
    }

    private var waiting: some View {
        HStack(spacing: DS.Space.s2) {
            DSSpinner()
            Text(signer == nil ? String(localized: "Waiting for your wallet") : String(localized: "Waiting for your Signer"))
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder private func doors(_ url: URL) -> some View {
        DSDoorRow(icon: "arrow.up.forward.app", label: "Open wallet") {
            // The wallet that claims WalletConnect's own link (Rainbow,
            // Trust, Zerion…); none here, the link is copied instead.
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                DSPasteboard.copySensitive(url.absoluteString)
                withAnimation(DS.Motion.standard) { copiedInstead = true }
            }
        }
        if copiedInstead {
            Text("No wallet here opens it: the link is copied, paste it in yours.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        DSCopyRow(value: url.absoluteString, label: "Copy link", sensitive: true)
    }

    /// The link as a QR code, one pixel a module (scaled without smoothing).
    static func code(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The account's Signer asked through its own wallet (prd §1447 item 17,
    /// §1455): the sheet raised with the pairing link (or, paired before, the
    /// wallet's door, §1601), taken down when the wallet answers, refuses,
    /// the wait runs out or the person cancels. Every way it ends is said in
    /// words, never "Not sent" alone.
    static func coSigner(owner: String, chainId: Int) -> YourAccountChain.CoSigner {
        YourAccountChain.CoSigner(owner: owner) { _, typedData in
            do {
                return try await asking(signer: owner) { ask in
                    try await YourAccountSignerLink.sign(typedData: typedData, signer: owner, chainId: chainId,
                                                         kept: { ask.ask(kept: $0) }, resend: ask.resends, show: { ask.pair($0) })
                }
            } catch {
                throw YourAccountChain.Failure(message: words(error))
            }
        }
    }

    /// How an ask of the Signer ended, when it did not sign (prd §1601).
    static func words(_ error: Error) -> String {
        if error is CancellationError { return String(localized: "Cancelled, so nothing was sent") }
        switch error as? YourAccountSignerLink.Failure {
        case .declined?, .refused?: return String(localized: "Your Signer declined, so nothing was sent")
        case .timedOut?: return String(localized: "Your Signer did not answer, so nothing was sent")
        case .notTheSigner?: return String(localized: "That wallet is not your Signer, so nothing was sent")
        case .unavailable?, .malformedURI?, .gone?: return String(localized: "Could not reach your Signer's wallet, so nothing was sent")
        default: return String(localized: "Not sent")
        }
    }

    /// `work` with the sheet it raises (`SignerAsk`): Cancel or pulling the
    /// sheet down cancels `work` and throws `CancellationError`; the sheet
    /// comes down however `work` ends (prd §1601).
    static func asking<T: Sendable>(signer: String?, _ work: @escaping @Sendable (SignerAsk) async throws -> T) async throws -> T {
        let ask = await MainActor.run { SignerAsk(signer: signer) }
        let task = Task { try await work(ask) }
        await MainActor.run {
            ask.stop = { task.cancel() }
            if ask.cancelled { task.cancel() }
        }
        defer { Task { @MainActor in ask.done() } }
        do {
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch {
            if await MainActor.run(body: { ask.cancelled }) { throw CancellationError() }
            throw error
        }
    }

    /// One scan for several networks (prd §1456): the wallet is paired on
    /// the first network's ask, for every network the batch names, and each
    /// later ask rides the same session; `finish` tears it down.
    actor Batch {
        let owner: String
        let chainIds: [Int]
        private var pairing: YourAccountSignerLink.Pairing?

        init(owner: String, chainIds: [Int]) {
            self.owner = owner
            self.chainIds = chainIds
        }

        nonisolated func coSigner(chainId: Int) -> YourAccountChain.CoSigner {
            YourAccountChain.CoSigner(owner: owner) { _, typedData in
                try await self.sign(typedData, chainId: chainId)
            }
        }

        private func sign(_ typedData: String, chainId: Int) async throws -> [UInt8] {
            if pairing == nil || pairing?.chainIds.contains(chainId) == false {
                let owner = self.owner, chainIds = self.chainIds
                pairing = try await SignerRequestSheet.asking(signer: owner) { ask in
                    try await YourAccountSignerLink.connect(signer: owner, chainIds: chainIds) { ask.pair($0) }
                }
            }
            guard let pairing else { throw YourAccountSignerLink.Failure.unavailable }
            // Asked with the sheet up and its Cancel (prd §1601), as a kept
            // session is: no second scan, a way out.
            let owner = self.owner
            return try await SignerRequestSheet.asking(signer: owner) { ask in
                await ask.ask(kept: nil)
                return try await YourAccountSignerLink.request(pairing, typedData: typedData, chainId: chainId,
                                                               resend: ask.resends)
            }
        }

        func finish() {
            if let pairing { YourAccountSignerLink.close(pairing) }
            pairing = nil
        }
    }

    /// A wallet chosen as the Signer (prd §1457): scanned once, its first
    /// address taken once it signs the proof (§1516), the session closed.
    static func choose(on chainIds: [Int], account: String) async throws -> String {
        try await asking(signer: nil) { ask in
            let pairing = try await YourAccountSignerLink.connect(signer: nil, chainIds: chainIds) { ask.pair($0) }
            defer { YourAccountSignerLink.close(pairing) }
            try await YourAccountSignerLink.prove(pairing, account: account)
            return pairing.signer
        }
    }

    /// A typed address proven before it is added (prd §1516): its wallet
    /// connects as that address and signs the proof.
    static func prove(signer: String, on chainIds: [Int], account: String) async throws {
        try await asking(signer: signer) { ask in
            let pairing = try await YourAccountSignerLink.connect(signer: signer, chainIds: chainIds) { ask.pair($0) }
            defer { YourAccountSignerLink.close(pairing) }
            try await YourAccountSignerLink.prove(pairing, account: account)
        }
    }

    /// The words for a proof that failed, or nil for any other failure.
    static func proofWords(_ error: Error) -> String? {
        switch error as? YourAccountSignerLink.Failure {
        case .notProven?: String(localized: "That wallet could not sign for this address, so it was not added")
        case .notTheSigner?: String(localized: "That wallet connected as another address")
        case .refused?: String(localized: "Your wallet declined to sign, so nothing was added")
        default: nil
        }
    }

    /// The sheet over a pairing link, for the probes; the closure takes it down.
    @MainActor
    static func present(url: URL, signer: String?) -> @MainActor () -> Void {
        let ask = SignerAsk(signer: signer)
        ask.pair(url)
        return { ask.done() }
    }

    /// Show the sheet over whatever is on screen; the returned closure takes
    /// it down.
    @MainActor
    static func present(_ ask: SignerAsk) -> @MainActor () -> Void {
        let host = UIHostingController(rootView: SignerRequestSheet(ask: ask))
        host.view.backgroundColor = .systemBackground
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(host, animated: true)
        return { [weak host] in host?.dismiss(animated: true) }
    }
}

/// What the Signer sheet shows while the Signer is asked, and the way out
/// of it (prd §1601): a pairing's link, or a kept session's wallet door.
/// Raised on the first of either; Cancel stops the ask through `stop`.
@MainActor @Observable
final class SignerAsk {
    /// Nil while one is being chosen (prd §1457): any wallet's first address.
    let signer: String?
    private(set) var link: URL?
    private(set) var door: URL?
    private(set) var kept = false
    private(set) var cancelled = false
    /// Ask again is offered once the wallet has had `askAgainAfter` to answer.
    private(set) var canAskAgain = false
    static let askAgainAfter: Duration = .seconds(10)
    /// Each Ask again, for the request waiting on the wallet (prd §1609).
    let resends: AsyncStream<Void>
    @ObservationIgnored private let resend: AsyncStream<Void>.Continuation
    @ObservationIgnored private var offer: Task<Void, Never>?
    @ObservationIgnored var stop: @Sendable () -> Void = {}
    @ObservationIgnored private var close: (@MainActor () -> Void)?
    @ObservationIgnored private var closing = false

    init(signer: String?) {
        self.signer = signer
        (resends, resend) = AsyncStream<Void>.makeStream()
    }

    func pair(_ url: URL) {
        link = url
        door = nil
        kept = false
        raise()
    }

    /// A Signer paired before: its request is already sent, so on the
    /// phone its wallet is opened onto it at once (prd §1605); the sheet's
    /// Open wallet stays for the way back, and a wallet on another device
    /// is approved there.
    func ask(kept door: URL?) {
        self.door = door
        link = nil
        kept = true
        raise()
        if let door, UIDevice.current.userInterfaceIdiom == .phone, !closing {
            UIApplication.shared.open(door)
        }
        offerAgain()
    }

    /// Ask the wallet the same question again and open it onto it.
    func again() {
        guard !closing else { return }
        resend.yield()
        if let door, UIDevice.current.userInterfaceIdiom == .phone { UIApplication.shared.open(door) }
        offerAgain()
    }

    private func offerAgain() {
        canAskAgain = false
        offer?.cancel()
        offer = Task { [weak self] in
            try? await Task.sleep(for: Self.askAgainAfter)
            guard !Task.isCancelled, let self, !self.closing else { return }
            withAnimation(DS.Motion.standard) { self.canAskAgain = true }
        }
    }

    private func raise() {
        guard close == nil, !closing else { return }
        close = SignerRequestSheet.present(self)
    }

    /// Stops the ask and takes the sheet down at once, whatever the ask
    /// is waiting on.
    func cancel() {
        guard !cancelled, !closing else { return }
        cancelled = true
        stop()
        done()
    }

    /// Pulled down by hand is a Cancel; taken down by `done` is not.
    func dismissed() { if !closing { cancel() } }

    func done() {
        closing = true
        offer?.cancel()
        resend.finish()
        close?()
        close = nil
    }
}

extension YourAccountChain {
    /// The Signer an operation at both keys asks when its caller named none
    /// (prd §1456): the account's first Signer on `net`, through the Signer
    /// sheet. DEBUG's `-coSignWith` hands a throwaway's test key instead.
    static func defaultCoSigner(_ net: Network, _ account: String) async -> CoSigner? {
        #if DEBUG
        if let test = UserDefaults.standard.string(forKey: "coSignWith") { return ProbeCoSigner.make(test) }
        #endif
        guard let signer = try? await signers(net, account).first else { return nil }
        return SignerRequestSheet.coSigner(owner: signer, chainId: net.chainId)
    }
}
