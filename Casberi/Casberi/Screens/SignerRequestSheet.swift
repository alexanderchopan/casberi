import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// **The Signer is asked (prd §1447 item 17).** An operation that needs both
/// keys shows its WalletConnect link here: a code to scan with the Signer's
/// wallet on another device, a door into MetaMask on this one, the link to
/// paste into any other. It closes itself when the answer comes.
struct SignerRequestSheet: View {
    let url: URL
    let signer: String

    var body: some View {
        DSTray(title: String(localized: "Your Signer signs too"), height: 600, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Scan with …\(String(signer.suffix(4))) in its wallet, then approve.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                if let code = Self.code(url.absoluteString) {
                    Image(uiImage: code)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(DS.Space.s3)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("WalletConnect code"))
                }
                if let metaMask = Self.metaMask(url) {
                    DSDoorRow(icon: "arrow.up.forward.app", label: "Open MetaMask") {
                        UIApplication.shared.open(metaMask)
                    }
                }
                DSCopyRow(value: url.absoluteString, label: "Copy link", sensitive: true)
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Waiting for your Signer")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
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

    /// MetaMask's own door to a pairing link on this phone.
    static func metaMask(_ url: URL) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://metamask.app.link/wc?uri=" + encoded)
    }

    /// Show the sheet over whatever is on screen; the returned closure takes
    /// it down.
    @MainActor
    static func present(url: URL, signer: String) -> @MainActor () -> Void {
        let host = UIHostingController(rootView: SignerRequestSheet(url: url, signer: signer))
        host.view.backgroundColor = .systemBackground
        host.isModalInPresentation = true
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
