import SwiftUI

/// **MOVE TO PRIVATE (prd §1547).** Move's grammar on one sentence: "Move
/// 0.001 ETH to private on Sepolia.", the amount a pink word whose choices
/// open under it, and the act a word at the foot's trailing edge, Face ID's
/// glyph beside it. While it works the sentence says what it is doing; done,
/// it says the move waits for approval, and Holdings shows it moving in.
///
/// Sepolia only, and in DEBUG builds only: the sender is the DEBUG testnet
/// sender until your account sends (`PrivacyTestnetSender`). Short of
/// Sepolia ETH, the sentence names the address to fund, and the foot copies it.
struct MovePrivateSheet: View {
    @State private var move = PrivateMove()
    @State private var choosing = false
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSTray(title: String(localized: "Move to private"), height: 560, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                MoveFlow { sentence }
                    .animation(DS.Motion.standard, value: move.stage)
                if choosing, move.stage == .ready { choices }
                Spacer(minLength: DS.Space.s4)
                if move.stage == .ready || move.busy {
                    // The one line the controls cannot say (prd §748): whose
                    // money this is, and that it is test money.
                    DSFootnote("Sepolia test ETH, from this build's test account.")
                }
                foot
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await move.read()
            #if DEBUG
            if let amount = UserDefaults.standard.string(forKey: "movePrivateAmount"), move.choices.contains(amount) {
                move.amount = amount
            }
            NSLog("[Casberi] movePrivate: %@", String(describing: move.stage))
            if UserDefaults.standard.bool(forKey: "movePrivateGo"), move.stage == .ready {
                await move.run()
            }
            #endif
        }
    }

    // MARK: - The sentence

    @ViewBuilder private var sentence: some View {
        switch move.stage {
        case .reading:
            MovePhrase(String(localized: "Reading Sepolia…"), ink: DS.textSecondary)
        case .ready:
            MoveClause(glue: String(localized: "Move")) {
                Button {
                    withAnimation(DS.Motion.standard) { choosing.toggle() }
                    DSHaptic.selection()
                } label: {
                    MoveWord(PrivateMoney.figure(PrivateMoney.baseUnits(move.amount, decimals: 18) ?? "0",
                                                 decimals: 18, symbol: "ETH"),
                             ink: choosing ? DS.pickInk.opacity(0.6) : DS.pickInk)
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Amount, \(move.amount) ETH"))
            }
            MovePhrase(String(localized: "to private on Sepolia."))
        case .needsFunds(let address):
            MovePhrase(String(localized: "Send Sepolia ETH to"))
            MoveClause { MoveWord(Self.short(address), ink: DS.pickInk) }
            MovePhrase(String(localized: "first."))
        case .opening:
            MovePhrase(String(localized: "Opening your private account…"))
        case .registering(let step):
            MovePhrase(String(localized: "Setting up your private account, \(step) of 2…"))
        case .proving:
            MovePhrase(String(localized: "Proving the move…"))
        case .sending:
            MovePhrase(String(localized: "Sending it to the pool…"))
        case .done:
            MovePhrase(String(localized: "Moved. Waiting for approval."))
        case .failed(let words):
            MovePhrase(words + ".", ink: DS.attentionInk)
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(move.choices, id: \.self) { step in
                Button {
                    withAnimation(DS.Motion.standard) {
                        move.amount = step
                        choosing = false
                    }
                    DSHaptic.selection()
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        AssetMark(name: "ETH", size: DS.Face.list)
                        Text(verbatim: PrivateMoney.figure(PrivateMoney.baseUnits(step, decimals: 18) ?? "0",
                                                           decimals: 18, symbol: "ETH"))
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .monospacedDigit()
                        Spacer(minLength: DS.Space.s2)
                        if step == move.amount {
                            Image(systemName: "checkmark")
                                .dsGlyph(.body, weight: .semibold)
                                .foregroundStyle(DS.pickInk)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: DSFeed.headHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityAddTraits(step == move.amount ? [.isSelected] : [])
            }
        }
        .transition(.opacity)
    }

    // MARK: - The foot

    @ViewBuilder private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            switch move.stage {
            case .needsFunds(let address):
                Button {
                    Task { await move.read() }
                    DSHaptic.selection()
                } label: {
                    Text("Check again").dsText(.heading24).foregroundStyle(DS.textPrimary).frame(minHeight: 48)
                }
                .buttonStyle(RowPress())
                Spacer(minLength: DS.Space.s3)
                Button {
                    DSPasteboard.copy(address)
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) { copied = true }
                } label: {
                    footWord(copied ? String(localized: "Copied") : String(localized: "Copy address"), glyph: nil, on: true)
                }
                .buttonStyle(RowPress())
            case .done, .failed:
                Spacer(minLength: 0)
                if case .failed = move.stage {
                    Button {
                        Task { await move.read() }
                        DSHaptic.selection()
                    } label: {
                        footWord(String(localized: "Try again"), glyph: nil, on: true)
                    }
                    .buttonStyle(RowPress())
                } else {
                    Button { dismiss() } label: {
                        Text("Done").dsText(.heading34).foregroundStyle(DS.textSecondary).frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                }
            default:
                Spacer(minLength: 0)
                Button {
                    choosing = false
                    Task { await move.run() }
                } label: {
                    footWord(String(localized: "Move"), glyph: "faceid", on: move.stage == .ready)
                }
                .buttonStyle(RowPress())
                .disabled(move.stage != .ready)
            }
        }
    }

    /// The foot's act: a word at the act rung, pink when it can act, with
    /// the glyph that says how (Face ID) where there is one.
    private func footWord(_ word: String, glyph: String?, on: Bool) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            if let glyph {
                Image(systemName: glyph)
                    .dsGlyph(.title, weight: .semibold)
                    .accessibilityHidden(true)
            }
            Text(verbatim: word).dsText(.heading34)
        }
        .foregroundStyle(on ? DS.pickInk : DS.textTertiary)
        .frame(minHeight: 48, alignment: .trailing)
    }

    /// An address as its tail only, "...e07a" (user rule, 2026-10-26: never
    /// truncated at both ends). Copy address copies the whole of it.
    static func short(_ address: String) -> String {
        address.count > 4 ? "...\(address.suffix(4))" : address
    }
}
