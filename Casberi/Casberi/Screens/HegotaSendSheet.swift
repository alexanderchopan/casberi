import SwiftUI
import SwiftData

/// SENDING TEST ETH ON HEGOTÁ, AS A SHEET (prd §526, 2026-08-29).
///
/// `HegotaKeySheet` makes the key and claims the faucet — this is what a key
/// is FOR. A destination address, an amount, one Send button wired straight
/// to the proven `HegotaKey.sign` → `HegotaTransaction.encoded` →
/// `HegotaSend.broadcast` path (`HegotaSend.sendValue`). No new promise: the
/// faucet claim already stated this key can act for this account, and a send
/// is that same key signing something a person typed instead of something
/// this app composed on its own.
///
/// **Presented through `FeedSheetRoute`, learned from the fix beside it
/// (§468).** A card living inside `FeedScreen`'s List rows must never own a
/// local `.sheet` — this screen is reached only via `feedSheet =
/// .hegotaSendSheet` from `HegotaKeySheet`'s own button, itself already
/// routed the same way.
struct HegotaSendSheet: View {
    @Environment(\.modelContext) private var modelContext

    @State private var destination = ""
    @State private var amount = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?

    private static let mark = HegotaModeStyle.room

    private enum Phase: Equatable { case form, done }

    private var phase: Phase { sentHash == nil ? .form : .done }

    var body: some View {
        DSTray(title: String(localized: "Send test ETH"), height: trayHeight, ink: true) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSheetHead(disc: { headDisc },
                            stamp: headStamp,
                            stampWeight: headStampWeight,
                            title: headTitle,
                            secondary: HegotaKey.address(),
                            sentence: headSentence)
                switch phase {
                case .form:
                    formBody
                case .done:
                    doneBody
                }
            }
        }
    }

    private var trayHeight: CGFloat {
        switch phase {
        case .form: 460
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
        phase == .done
            ? String(localized: "Sent")
            : String(localized: "Send from this phone's key")
    }

    private var headStamp: String? {
        phase == .done ? String(localized: "Broadcast") : nil
    }

    private var headStampWeight: DSStamp.Weight { .good }

    private var headSentence: String? {
        switch phase {
        case .form:
            String(localized: "Signed by this phone's key, unsponsored \u{2014} the sender pays its own gas, exactly as measured on this chain.")
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
                Text(HegotaIdentity.explorer + "/tx/" + sentHash)
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
        guard let target = RLP.data(fromHex: destination),
              let valueWei = Self.weiData(from: amount),
              let address = HegotaKey.address() else { return }
        errorText = nil
        busy = true
        let to = destination
        Task {
            defer { busy = false }
            do {
                guard let sequence = await HegotaSend.currentNonceSequence(for: address) else {
                    errorText = String(localized: "Couldn't reach the chain to read this account's sequence.")
                    return
                }
                let hash = try await HegotaSend.sendValue(to: target, valueWei: valueWei,
                                                          nonceSequence: sequence)
                DSHaptic.success()
                HegotaSend.landReceipt(txHash: hash, kind: .sent(to: to), in: modelContext)
                sentHash = hash
            } catch let f as HegotaSend.Failure {
                switch f {
                case .broadcastRefused(let why):
                    errorText = String(localized: "The chain refused it: \(why)")
                case .signingRefused:
                    errorText = String(localized: "Signing was cancelled or refused.")
                case .noKey:
                    errorText = String(localized: "No key on this phone.")
                default:
                    errorText = String(localized: "Couldn't send.")
                }
            } catch {
                errorText = String(localized: "Couldn't send.")
            }
        }
    }

    // MARK: - Parsing

    /// The same shape check used across this codebase's other address
    /// inputs (`AltanaDiscovery.isValidAddress`'s reasoning, not its code —
    /// this file stays free of a cross-model dependency for one three-line
    /// check).
    private static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A typed decimal ETH amount to minimal big-endian wei bytes — string
    /// arithmetic throughout, never `Double`, because a floating-point ×1e18
    /// is exactly the precision loss `SafeABI.word`'s own doc exists to
    /// avoid one screen over. Rejects rather than truncates an amount with
    /// more than 18 decimal places, and rejects zero (nothing to send).
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
        // Strip to RLP's minimal, no-leading-zero form (`RLP.quantity`'s own
        // rule) — `SafeABI.word` always returns a fixed 32-byte word, which
        // an RLP `.bytes` field must never carry verbatim.
        var trimmed = word.drop(while: { $0 == 0 })
        guard !trimmed.isEmpty else { return nil }
        return Data(trimmed)
    }
}
