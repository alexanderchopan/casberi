import SwiftUI
import SwiftData

/// THIS PHONE'S KEY ON HEGOTÁ, AS A SHEET (prd §525, 2026-08-29).
///
/// `VibenetCreateSheet`'s anatomy, one chain over: `DSSheetHead` — a disc, a
/// stamp, a title, one sentence saying what it means now — then a captioned
/// body, then one full-width control for whichever act the phase calls for.
/// No text-link verbs; the one thing a phase asks for gets the weight the
/// ready state's button gets.
///
/// **What is different from vibenet's sheet, stated rather than hidden.**
/// This key is `HegotaKey` — a plain secp256k1 scalar in the Keychain, not a
/// Secure Enclave key — on the user's own ruling that a devnet with worthless
/// money does not need hardware-backed non-export. The head says so in its own
/// sentence, because the difference from vibenet's promise is exactly the
/// kind of thing that must not be silently implied to be the same.
struct HegotaKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var presence: HegotaKey.Presence = .none
    @State private var busy = false
    @State private var keyFailure: String?
    @State private var faucetResult: String?
    @State private var faucetBusy = false

    private static let mark = HegotaModeStyle.room

    private enum Phase: Equatable { case noKey, ready, working }

    private var phase: Phase {
        switch presence {
        case .none, .destroyed: .noKey
        case .present:          busy ? .working : .ready
        }
    }

    var body: some View {
        DSTray(title: String(localized: "This phone's key"), height: trayHeight, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSheetHead(disc: { headDisc },
                            stamp: headStamp,
                            stampWeight: headStampWeight,
                            title: headTitle,
                            secondary: headSecondary,
                            sentence: headSentence)
                switch phase {
                case .noKey:
                    noKeyBody
                case .ready, .working:
                    readyBody
                }
            }
        }
        .task { refresh() }
    }

    private var trayHeight: CGFloat {
        switch phase {
        case .noKey:            340
        case .ready, .working:  460
        }
    }

    // MARK: - Head

    private var headDisc: some View {
        ZStack {
            Circle()
                .fill(presence == .destroyed ? DS.destructive.opacity(0.16) : Self.mark.opacity(0.18))
                .frame(width: DS.Face.list, height: DS.Face.list)
            Image(systemName: presence == .destroyed ? "exclamationmark.triangle.fill" : "key.fill")
                .dsGlyph(presence == .destroyed ? 14 : 16, weight: .semibold)
                .foregroundStyle(presence == .destroyed ? DS.destructive : Self.mark)
        }
        .accessibilityHidden(true)
    }

    private var headTitle: String {
        switch presence {
        case .present:   String(localized: "A key on this phone")
        case .destroyed: String(localized: "This phone's key is gone")
        case .none:      String(localized: "No key yet")
        }
    }

    private var headSecondary: String? {
        if presence == .present, let address = HegotaKey.address() { return address }
        return String(localized: "Hegotá \u{00B7} frame-transaction devnet")
    }

    private var headSentence: String? {
        switch presence {
        case .present:
            String(localized: "A plain secp256k1 key on this device, not the Secure Enclave \u{2014} there is nothing of value here to protect.")
        case .destroyed:
            String(localized: "It was removed from this phone's keychain. Making a new one is safe \u{2014} nothing on a devnet is lost by it.")
        case .none:
            String(localized: "Making one lets this phone sign and send on the devnet directly.")
        }
    }

    private var headStamp: String? {
        switch presence {
        case .present:   String(localized: "Ready")
        case .destroyed: String(localized: "Gone")
        case .none:      nil
        }
    }

    private var headStampWeight: DSStamp.Weight {
        switch presence {
        case .present:   .good
        case .destroyed: .urgent
        case .none:      .quiet
        }
    }

    // MARK: - No key

    private var noKeyBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button {
                DSHaptic.tap()
                makeKey()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").dsGlyph(13, weight: .semibold)
                    Text(String(localized: "Make a key on this phone"))
                }
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .dsHover()
            if let keyFailure {
                Text(keyFailure)
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Ready

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Test ETH"))
                Button {
                    DSHaptic.tap()
                    claimFaucet()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill").dsGlyph(13, weight: .semibold)
                        Text(String(localized: "Claim from the faucet"))
                        if faucetBusy { ProgressView().controlSize(.mini) }
                    }
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s3)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressSpring())
                .disabled(faucetBusy)
                .dsHover()
                if let faucetResult {
                    Text(faucetResult)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Rate-limited to one claim per source IP per hour — measured,
                // not guessed (§525) — so the copy says why a second tap may
                // fail rather than leaving it to read as broken.
                Text(String(localized: "One claim per hour."))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Actions"))
                Button {
                    DSHaptic.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").dsGlyph(12, weight: .semibold)
                        Text(String(localized: "Remove this key"))
                    }
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.destructive)
                }
                .buttonStyle(PressSpring())
                .dsHover()
                .simultaneousGesture(TapGesture().onEnded { removeKey() })
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
    }

    // MARK: - Acts

    private func refresh() {
        presence = HegotaKey.presence()
    }

    private func makeKey() {
        keyFailure = nil
        do {
            _ = try HegotaKey.create()
            DSHaptic.success()
            refresh()
        } catch {
            keyFailure = Self.keySentence(for: error)
        }
    }

    private func removeKey() {
        HegotaKey.delete()
        refresh()
        chrome.flash(String(localized: "Key removed"))
    }

    private func claimFaucet() {
        guard let address = HegotaKey.address() else { return }
        faucetBusy = true
        faucetResult = nil
        Task {
            defer { faucetBusy = false }
            do {
                let claim = try await HegotaSend.claimFaucet(for: address)
                DSHaptic.success()
                HegotaSend.landReceipt(txHash: claim.transactionHash, kind: .claimed, in: modelContext)
                faucetResult = String(localized: "Sent \u{2014} \(claim.transactionHash.prefix(10))\u{2026}")
            } catch let f as HegotaSend.Failure {
                switch f {
                case .faucetRefused(let why):
                    faucetResult = why.lowercased().contains("429") || why.lowercased().contains("limit")
                        ? String(localized: "Already claimed this hour \u{2014} try again later.")
                        : String(localized: "The faucet refused: \(why)")
                default:
                    faucetResult = String(localized: "Couldn't reach the faucet.")
                }
            } catch {
                faucetResult = String(localized: "Couldn't reach the faucet.")
            }
        }
    }

    private static func keySentence(for error: Error) -> String {
        guard let f = error as? HegotaKey.Failure else {
            return String(localized: "Couldn't make a key.")
        }
        switch f {
        case .alreadyExists:
            return String(localized: "There's already a key on this phone.")
        case .missing:
            return String(localized: "No key was found.")
        case .curve:
            return String(localized: "The key could not be generated.")
        case .selfCheck:
            return String(localized: "The new key didn't check out \u{2014} nothing was saved.")
        case .locked(let status), .keychainRefused(let status):
            return String(localized: "The keychain refused (code \(String(Int(status)))).")
        }
    }
}
