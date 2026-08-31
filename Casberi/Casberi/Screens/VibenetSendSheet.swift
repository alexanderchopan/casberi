import SwiftUI
import SwiftData

/// SENDING ETH FROM A VIBENET ACCOUNT, AS A SHEET (prd §533, 2026-08-31).
///
/// `HegotaSendSheet`'s anatomy, one chain over — same fields (To, Amount),
/// same phase model, same door: `FeedSheetRoute`, never a local `.sheet`
/// (§468's rule, since this presents from inside `FeedScreen`'s List).
///
/// **What is different, stated rather than hidden.** Hegotá's key IS the
/// sending address (a plain EOA); a vibenet account is a separate object this
/// phone's key merely authorizes. So this sheet takes `account` as an
/// explicit parameter — the caller already knows which account it's scoped
/// to, and this sheet never re-derives or guesses one.
///
/// **The mechanic, for whoever reads this next.** `VibenetTransaction.Call`
/// carries no value by design (confirmed against the reference
/// `DefaultAccount.sol`, not assumed) — a send is the account calling
/// ITSELF, invoking `execute(recipient, valueWei, "")`, which is where the
/// real value-carrying EVM `CALL` happens. See `VibenetExecute`'s own doc.
///
/// **One account, one key, today.** This app has never authorized more than
/// one signer per account (`VibenetCreate.plan` hardcodes a single initial
/// actor), so there is no "which key" question yet and none is asked here.
struct VibenetSendSheet: View {
    let account: Data

    @Environment(\.modelContext) private var modelContext

    @State private var destination = ""
    @State private var amount = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    private enum Phase: Equatable { case form, done }

    private var phase: Phase { sentHash == nil ? .form : .done }

    var body: some View {
        // SCROLLABLE, AND WIDENED from the start — the `HegotaSendSheet`/
        // `VibenetKeySheet` fix for the guessed-height class of bug, applied
        // here on day one rather than after a report.
        DSTray(title: String(localized: "Send test ETH"), height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    DSSheetHead(disc: { headDisc },
                                stamp: headStamp,
                                stampWeight: headStampWeight,
                                title: headTitle,
                                secondary: "0x" + VibenetTransaction.hex(account),
                                sentence: headSentence,
                                inkCard: true)
                    switch phase {
                    case .form:
                        formBody
                    case .done:
                        doneBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trayHeight: CGFloat {
        switch phase {
        case .form: 620
        case .done: 340
        }
    }

    // MARK: - Head

    private var headDisc: some View {
        ZStack {
            Circle()
                .fill(Self.mark.opacity(0.18))
                .frame(width: DS.Face.list, height: DS.Face.list)
            Image(systemName: phase == .done ? "checkmark" : "arrow.up.right")
                .dsGlyph(16, weight: .semibold)
                .foregroundStyle(Self.mark)
        }
        .accessibilityHidden(true)
    }

    private var headTitle: String {
        phase == .done ? String(localized: "Sent") : String(localized: "Send")
    }

    private var headStamp: String? {
        phase == .done ? String(localized: "Broadcast") : nil
    }

    private var headStampWeight: DSStamp.Weight { .good }

    private var headSentence: String? {
        switch phase {
        case .form:
            String(localized: "Signed by this phone's key. Whether the sender or the devnet's faucet pays is checked when you tap Send.")
        case .done:
            String(localized: "The transaction is on its way to the chain.")
        }
    }

    // MARK: - Form

    private var canSend: Bool {
        !busy && Self.isValidAddress(destination) && Self.weiData(from: amount) != nil
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "To"))
                well {
                    TextField(String(localized: "0x\u{2026}"), text: $destination)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .tint(DS.tint)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !destination.isEmpty, !Self.isValidAddress(destination) {
                    Text(String(localized: "That doesn't look like an address."))
                        .dsText(.label11)
                        .foregroundStyle(DS.destructive)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                caption(String(localized: "Amount"))
                well {
                    HStack(spacing: DS.Space.s2) {
                        TextField("0.0", text: $amount)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .tint(DS.tint)
                            .keyboardType(.decimalPad)
                        Text(String(localized: "ETH"))
                            .dsText(.body17)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                if !amount.isEmpty, Self.weiData(from: amount) == nil {
                    Text(String(localized: "Enter an amount up to 18 decimal places."))
                        .dsText(.label11)
                        .foregroundStyle(DS.destructive)
                }
            }

            Button {
                DSHaptic.tap()
                send()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").dsGlyph(13, weight: .semibold)
                    Text(String(localized: "Send"))
                    if busy { ProgressView().controlSize(.mini) }
                }
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(canSend ? .white : DS.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(canSend ? AnyShapeStyle(Self.mark) : AnyShapeStyle(DS.gray200),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(!canSend)
            .armedPop(canSend)
            .animation(DS.Motion.standard, value: canSend)
            .dsHover()

            if let errorText {
                Text(errorText)
                    .dsText(.label11)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func well<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceWell,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
    }

    // MARK: - Done

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let sentHash {
                Text(VibenetExplorer.tx(sentHash))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Button {
                DSHaptic.tap()
                destination = ""
                amount = ""
                sentHash = nil
                errorText = nil
            } label: {
                Text(String(localized: "Send another"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)
            }
            .buttonStyle(PressSpring())
            .dsHover()
        }
    }

    // MARK: - Act

    private func send() {
        guard let target = VibenetTransaction.data(fromHex: destination), target.count == 20,
              let valueWei = Self.weiData(from: amount) else { return }
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let sent = try await VibenetSend.sendValue(from: account, to: target, valueWei: valueWei)
                DSHaptic.success()
                VibenetSend.landSendReceipt(sent, to: target, valueWei: valueWei, in: modelContext)
                sentHash = sent.transactionHash
            } catch let f as VibenetSend.Failure {
                switch f {
                case .noSponsor:
                    errorText = String(localized: "Nobody is sponsoring right now, and this account has nothing to pay with. Try again later.")
                case .sponsorUnreadable:
                    errorText = String(localized: "Couldn't reach the sponsor to ask who pays, so nothing was signed.")
                case .broadcastRefused(let why):
                    errorText = String(localized: "The network refused it: \(why)")
                case .payerRefused(let why):
                    errorText = String(localized: "The sponsor refused: \(why)")
                case .signingRefused:
                    errorText = String(localized: "Face ID didn't confirm, so nothing was signed.")
                case .chainUnreachable:
                    errorText = String(localized: "Couldn't reach the network, so nothing was sent.")
                case .noKey:
                    errorText = String(localized: "This phone has no key yet.")
                case .cannotCompose:
                    errorText = String(localized: "Couldn't put the transaction together.")
                }
            } catch {
                errorText = String(localized: "Couldn't send.")
            }
        }
    }

    // MARK: - Parsing

    private static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A typed decimal ETH amount to minimal big-endian wei bytes —
    /// `HegotaSendSheet.weiData`'s own reasoning, string arithmetic
    /// throughout, never `Double`: this devnet's own faucet balances run
    /// into the billions of ETH, well past `Double`'s exact-integer range.
    private static func weiData(from text: String) -> Data? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let frac = parts.count == 2 ? String(parts[1]) : ""
        guard whole.allSatisfy(\.isNumber), frac.allSatisfy(\.isNumber), frac.count <= 18
        else { return nil }
        let combined = whole + frac + String(repeating: "0", count: 18 - frac.count)
        guard let word = SafeABI.word(uint256: combined) else { return nil }
        var trimmed = word.drop(while: { $0 == 0 })
        guard !trimmed.isEmpty else { return nil }
        return Data(trimmed)
    }
}
