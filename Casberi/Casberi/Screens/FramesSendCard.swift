import SwiftUI

/// SENDING ON THE FRAMES DEVNET — the room's Home scope, not a door to one
/// (prd §548; §538's ruling for vibenet, carried to Hegotá by §539 and here by
/// the same reasoning: *"it shouldn't have a door… it should be part of the
/// screen"*).
///
/// **`DevnetSendConsole`'s shared anatomy** — the recipient as a plain row, the
/// money giant and centred, a keypad of bare digits, one button carrying the
/// verb (§544). This chain moves ETH and only ETH, so the unit is a WORD and
/// never a chip: a control that opens a one-item menu is the dead control §83
/// bans. That much is Hegotá's card exactly.
///
/// ## THE ONE THING THIS CARD HAS THAT NO OTHER SEND SCREEN DOES
///
/// **A send here is not one act.** It is a VERIFY frame that authorises
/// execution and payment, then a SENDER frame that moves the value — and
/// without the first the transaction has no payer and is invalid. A to-and-
/// amount form says none of that, and this is the chain whose entire reason
/// for existing is that a transaction has parts.
///
/// So the console shows them, and **the preview is the transaction rather than
/// a description of one**: it renders `FramesSend.plan(…)`, the same function
/// `FramesSend.sendValue` signs. A preview drawn from a parallel description is
/// how a screen ends up promising two frames and sending three; here they are
/// the same object, so they cannot disagree. The harness guards it.
///
/// It is deliberately a READING and not a control — there is no way to edit a
/// frame here, add one, or change a mode. That would be a transaction builder,
/// which is a different product; this says what the tap will do.
struct FramesSendCard: View {
    let account: FramesAccount

    @Environment(ShellChrome.self) private var chrome

    @State private var destination = ""
    @State private var amount = ""
    @State private var picking = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var sentHash: String?

    /// The mark this room signs with. `DS.tint` rather than an invented hue —
    /// the seat's own icon is the brand and the console is chrome around it.
    private static let mark = DS.tint

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            DevnetSendToRow(address: destination.isEmpty ? nil : destination,
                            name: destination.isEmpty ? nil : recipientName,
                            preview: knownAddresses,
                            onTap: { picking = true })

            DevnetSendFigure(amount: amount, dim: amount.isEmpty) {
                HStack(spacing: DS.Space.s2) {
                    Text(String(localized: "test ETH"))
                        .dsText(.callout15)
                        .fontWeight(.semibold)
                        .foregroundStyle(amount.isEmpty ? DS.textTertiary : DS.textSecondary)
                    if let available = FramesMoney.eth(fromWeiHex: account.balanceWeiHex ?? "") {
                        // NO MAX, Hegotá's rule and this chain's too: gas is
                        // the sender's, so the whole balance is the one amount
                        // that provably cannot be sent. Stated, never offered
                        // as a tap.
                        Text(String(localized: "\(available) available"))
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }

            DevnetSendKeypad(amount: $amount, tint: Self.mark)

            if let planned { FramesPlanStrip(fields: planned) }

            Button {
                DSHaptic.tap()
                send()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").dsGlyph(13, weight: .semibold)
                    Text(sendLabel)
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
            .animation(DS.Motion.standard, value: canSend)
            .dsHover()

            if let errorText {
                Text(errorText)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let sentHash {
                Text(String(localized: "Sent · \(WalletStore.shortAddress(sentHash))"))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $picking) {
            DevnetSendPicker(title: String(localized: "Send to"),
                             candidates: pickerEntries) { picked in
                destination = picked
                picking = false
            }
        }
    }

    // MARK: - What the tap will do

    /// The transaction, unsigned — nil until there is a real recipient and a
    /// real amount, so the strip appears when there is something true to say
    /// rather than sitting there as a diagram of nothing.
    private var planned: FramesTransaction.Fields? {
        guard let sender = RLP.data(fromHex: account.address),
              FramesWatch.isValidAddress(destination),
              let target = RLP.data(fromHex: destination),
              let wei = Self.weiData(from: amount)
        else { return nil }
        return FramesSend.plan(sender: sender, to: target, valueWei: wei,
                               nonce: account.nonce ?? 0)
    }

    private var canSend: Bool { !busy && planned != nil }

    private var sendLabel: String {
        guard canSend else { return String(localized: "Send") }
        return String(localized: "Send \(amount) test ETH")
    }

    private func send() {
        guard let target = RLP.data(fromHex: destination),
              let wei = Self.weiData(from: amount) else { return }
        busy = true
        errorText = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                // The nonce is READ, never taken from the account snapshot: a
                // send a moment after another one is exactly when the cached
                // figure is stale, and a nonce too low is refused with a
                // sentence nobody can act on.
                let nonce = await FramesSend.currentNonce(for: account.address) ?? account.nonce ?? 0
                let hash = try await FramesSend.sendValue(to: target, valueWei: wei, nonce: nonce)
                sentHash = hash
                amount = ""
                await FramesLiveState.shared.refresh()
            } catch let failure as FramesSend.Failure {
                errorText = Self.sentence(for: failure)
            } catch {
                errorText = String(localized: "It didn't send.")
            }
        }
    }

    /// The node's own words wherever there are any (§530). A refusal with no
    /// reason cannot be acted on, and on a send that is the worst place for it.
    private static func sentence(for failure: FramesSend.Failure) -> String {
        switch failure {
        case .noKey:
            String(localized: "There's no account on this phone yet.")
        case .signingRefused:
            String(localized: "The signature was refused.")
        case .chainUnreachable:
            String(localized: "Couldn't reach the chain — nothing was sent.")
        case .prefixTooLarge:
            String(localized: "The verify step asks for more gas than this chain allows.")
        case .broadcastRefused(let why):
            String(localized: "The network refused it: \(why)")
        case .faucet(let verdict):
            verdict.sentence ?? String(localized: "The faucet didn't answer.")
        }
    }

    // MARK: - The recipient

    private var recipientName: String? { FramesWatch.shared.name(for: destination) }

    private var knownAddresses: [String] {
        FramesWatch.shared.addresses.filter {
            $0.caseInsensitiveCompare(account.address) != .orderedSame
        }
    }

    private var pickerEntries: [(address: String, name: String?)] {
        knownAddresses.map { ($0, FramesWatch.shared.name(for: $0)) }
    }

    /// Decimal ETH to a minimal big-endian wei `Data`. Hegotá's own converter,
    /// unchanged: 18 decimals is a wei and a 19th is not a small amount, it is
    /// an unrepresentable one.
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
        let trimmed = word.drop(while: { $0 == 0 })
        guard !trimmed.isEmpty else { return nil }
        return Data(trimmed)
    }
}

/// WHAT YOUR SEND BECOMES — the frames, drawn from the transaction itself.
///
/// A reading, never a control: there is no way to edit a frame, add one or
/// change a mode. That is a transaction builder and a different product. This
/// says what the tap will do, on the one chain where that is not obvious.
struct FramesPlanStrip: View {
    let fields: FramesTransaction.Fields

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "This sends as \(fields.frames.count) frames"))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            HStack(spacing: DS.Space.s2) {
                ForEach(Array(fields.frames.enumerated()), id: \.offset) { index, frame in
                    FramesPlanCell(index: index, frame: frame)
                    if index < fields.frames.count - 1 {
                        Image(systemName: "arrow.right")
                            .dsGlyph(10, weight: .semibold)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .animation(DS.Motion.standard, value: fields.frames.count)
    }
}

private struct FramesPlanCell: View {
    let index: Int
    let frame: FramesTransaction.Frame

    /// `0` DEFAULT, `1` VERIFY, `2` SENDER — the chain's own words, because the
    /// chip is where the vocabulary gets learned (`FramesSection.label`'s
    /// ruling).
    private var name: String {
        switch frame.mode {
        case 1: String(localized: "Verify")
        case 2: String(localized: "Sender")
        case 0: String(localized: "Default")
        default: String(localized: "Mode \(String(frame.mode))")
        }
    }

    /// **THE PERMISSION, said out loud.** A VERIFY frame's flags ARE the
    /// authorisation on this chain — there is no standing grant anywhere, so
    /// this is the only place it can be read (`FramesSection`'s Permissions
    /// ruling). Without an APPROVE the transaction has no payer and is
    /// invalid, so "approves both" is load-bearing rather than a detail.
    private var detail: String {
        if frame.mode == 1 {
            let execution = frame.flags & 0x1 != 0
            let payment = frame.flags & 0x2 != 0
            if execution && payment { return String(localized: "approves both") }
            if payment { return String(localized: "approves payment") }
            if execution { return String(localized: "approves running") }
            return String(localized: "approves nothing")
        }
        return frame.value.isEmpty ? String(localized: "no value")
                                   : String(localized: "moves the value")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            Text(detail)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .background(DS.gray100, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }
}
