import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// **The Signer is asked (prd §1447 item 17).** An operation that needs both
/// keys shows its WalletConnect link here: a code to scan with the Signer's
/// wallet on another device, a door into whichever wallet on this one takes
/// the link (user: "it can be open wallet … i just signed in rainbow each
/// time today"), the link to paste into any other. It closes itself when the
/// answer comes.
struct SignerRequestSheet: View {
    let url: URL
    /// Nil while one is being chosen (prd §1457): any wallet's first address.
    let signer: String?
    @State private var copiedInstead = false
    /// A phone cannot scan its own screen (user: "it's only relevant if you
    /// had another phone"): there the wallet on this phone leads and the code
    /// is small, for a second device; an iPad or a Mac leads with the code.
    private let onPhone = UIDevice.current.userInterfaceIdiom == .phone

    var body: some View {
        DSTray(title: signer == nil ? String(localized: "Your Signer") : String(localized: "Your Signer signs too"),
               height: onPhone ? 420 : 600, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(onPhone
                     ? (signer.map { String(localized: "Approve in the wallet holding …\(String($0.suffix(4))).") }
                        ?? String(localized: "Approve twice in the wallet you want: connect, then sign."))
                     : (signer.map { String(localized: "Scan with …\(String($0.suffix(4))) in its wallet, then approve.") }
                        ?? String(localized: "Scan with the wallet you want, then approve twice: connect, then sign.")))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !onPhone, let code = Self.code(url.absoluteString) {
                    codeImage(code, side: 260)
                        .frame(maxWidth: .infinity)
                }
                doors
                waiting
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

    @ViewBuilder private var doors: some View {
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
    /// §1455): the sheet raised with the pairing link, taken down when the
    /// wallet answers, refuses or the wait runs out.
    static func coSigner(owner: String, chainId: Int) -> YourAccountChain.CoSigner {
        YourAccountChain.CoSigner(owner: owner) { _, typedData in
            let handle = await MainActor.run { Handle() }
            defer { Task { @MainActor in handle.close() } }
            return try await YourAccountSignerLink.sign(typedData: typedData, signer: owner, chainId: chainId) { url in
                handle.close = present(url: url, signer: owner)
            }
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
                let handle = await MainActor.run { Handle() }
                let owner = self.owner
                do {
                    pairing = try await YourAccountSignerLink.connect(signer: owner, chainIds: chainIds) { url in
                        handle.close = SignerRequestSheet.present(url: url, signer: owner)
                    }
                } catch {
                    await MainActor.run { handle.close() }
                    throw error
                }
                await MainActor.run { handle.close() }
            }
            guard let pairing else { throw YourAccountSignerLink.Failure.unavailable }
            return try await YourAccountSignerLink.request(pairing, typedData: typedData, chainId: chainId)
        }

        func finish() {
            if let pairing { YourAccountSignerLink.close(pairing) }
            pairing = nil
        }
    }

    /// A wallet chosen as the Signer (prd §1457): scanned once, its first
    /// address taken once it signs the proof (§1516), the session closed.
    static func choose(on chainIds: [Int], account: String) async throws -> String {
        let handle = await MainActor.run { Handle() }
        defer { Task { @MainActor in handle.close() } }
        let pairing = try await YourAccountSignerLink.connect(signer: nil, chainIds: chainIds) { url in
            handle.close = present(url: url, signer: nil)
        }
        defer { YourAccountSignerLink.close(pairing) }
        try await YourAccountSignerLink.prove(pairing, account: account)
        return pairing.signer
    }

    /// A typed address proven before it is added (prd §1516): its wallet
    /// connects as that address and signs the proof.
    static func prove(signer: String, on chainIds: [Int], account: String) async throws {
        let handle = await MainActor.run { Handle() }
        defer { Task { @MainActor in handle.close() } }
        let pairing = try await YourAccountSignerLink.connect(signer: signer, chainIds: chainIds) { url in
            handle.close = present(url: url, signer: signer)
        }
        defer { YourAccountSignerLink.close(pairing) }
        try await YourAccountSignerLink.prove(pairing, account: account)
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

    @MainActor
    final class Handle {
        var close: @MainActor () -> Void = {}
    }

    /// Show the sheet over whatever is on screen; the returned closure takes
    /// it down.
    @MainActor
    static func present(url: URL, signer: String?) -> @MainActor () -> Void {
        let host = UIHostingController(rootView: SignerRequestSheet(url: url, signer: signer))
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
