import SwiftUI
import CoreImage.CIFilterBuiltins

/// Pair an MCP client (PRD §34) — the inverse of a bridge: Claude, Raycast, or
/// any MCP client scans this to connect TO the person's things. The consent
/// rail is stated plainly (reads on ask, saves only on approval). This is the
/// FINAL UI, built ahead of the server (same standing as the iCloud-sync
/// setting): the token is real and Keychain-backed, the endpoint it names is a
/// placeholder until the Goal-3 server accepts pairings — the one honest gate.
struct PairClientSheet: View {
    private let payload = MCPPairing.payload()

    var body: some View {
        DSTray(title: "Pair a client", height: 560) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Scan this in Claude, Raycast, or any MCP client.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)

                // The code, on a light card so a camera can read it (QRs need a
                // quiet zone and a light field). It settles in — the pairing
                // handshake arriving, not popping.
                qrCard
                    .settleIn()

                // The consent guarantee, in the alive language — green is the
                // confident tell (matches Data's trust rows).
                guaranteeRow
                    .settleIn(delay: 0.08)

                Spacer(minLength: 0)

                // The honest gate: the token is real, the wire is not yet.
                Text("Connecting goes live when your things sync. Code: \(MCPPairing.shortCode())")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    private var qrCard: some View {
        HStack {
            Spacer()
            Image(uiImage: qrImage(from: payload))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding(DS.Space.s4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            Spacer()
        }
    }

    private var guaranteeRow: some View {
        HStack(spacing: DS.Space.s3) {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(36), style: .continuous)
                .fill(DS.confirm)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "hand.raised.fill")
                        .dsGlyph(16)
                        .foregroundStyle(.white)
                )
            // One line, not a title over its own restatement: "Yours to
            // allow" said what the sentence beneath it already said.
            Text("Reads when you ask · saves only what you approve")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer()
        }
    }

    /// Renders the payload as a QR image (CoreImage, no dependency). Black on
    /// clear; the light card behind it supplies the field.
    private func qrImage(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
                .transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cg)
    }
}
