import SwiftUI

/// THE CREDENTIAL CARD (2026-08-18, prd §404) — the head of an Altana key's
/// thing sheet.
///
/// Anatomy borrowed from `MoneyReceiptCard`, which is the other sheet head in
/// this app that replaces a generic body with a real one: a subject disc, a
/// heading, a small set of stated facts, and a bottom edge that carries STATE
/// rather than decoration. Here the state-carrying element is the grant
/// window — full and grey means the paper is finished, a marker inside it
/// means the grant is still running.
///
/// **No green/red.** An expired key is not a failure and a live one is not a
/// success; both are facts. Grey is the only tonal change, and it means
/// "finished", exactly as `MoneyReceiptCard`'s torn edge does.
///
/// ## The window draws only when it is real
///
/// `AltanaKeySheet.progress` returns nil unless the registration date was
/// WITNESSED against the expiry (see `AltanaKeystore.registeredAt`). The card
/// then omits the window entirely rather than drawing an empty or full one —
/// a window is a claim about elapsed time, and drawing it from a date we never
/// confirmed is the §83 line for this card.
///
/// ## Liveness
///
/// Stores no `Thing` — only the value model. Corollary 5 has nothing to guard.
struct AltanaKeyCard: View {
    let model: AltanaKeySheet.Model
    /// Opens Altana's own explorer — the only place a key is actually revoked
    /// or tidied away (§112: we read and state, they act).
    var onOpen: () -> Void
    /// Opens another watched wallet this same credential signs for.
    var onWallet: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Altana") ?? Color.fixed("#3565e3")
    private static let windowHeight: CGFloat = 6

    private var finished: Bool { model.expired || model.live == .revoked }
    private var hue: Color { finished ? DS.textTertiary : Self.mark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            liveLine.padding(.top, DS.Space.s3)
            if let progress = AltanaKeySheet.progress(model) {
                window(progress).padding(.top, DS.Space.s4)
            }
            facts.padding(.top, DS.Space.s4)
            if !model.alsoSignsFor.isEmpty {
                alsoSignsFor.padding(.top, DS.Space.s3)
            }
            if let tidy = AltanaKeySheet.tidyNote(model) {
                Text(tidy)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }
            if let ceiling = AltanaKeySheet.scopeCeiling(model) {
                Text(ceiling)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    // MARK: - Pieces

    private var head: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(46), style: .continuous)
                .fill(hue)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.appIcon(46), style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                             startPoint: .top, endPoint: .center))
                )
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "key.horizontal.fill")
                        .dsGlyph(20)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(AltanaKeySheet.title(model))
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                // Empty when neither the curve nor the chain could be read —
                // skipped rather than drawn as a blank line.
                if !AltanaKeySheet.subtitle(model).isEmpty {
                    Text(AltanaKeySheet.subtitle(model))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The live re-check. A dot rather than an icon, because this is a STATE
    /// and not an action — and it is the only thing on the card that changes
    /// after mount, so it settles in rather than appearing.
    private var liveLine: some View {
        HStack(spacing: DS.Space.s2) {
            Circle()
                .fill(model.live == .revoked ? DS.textTertiary : hue)
                .frame(width: 7, height: 7)
                .opacity(model.live == .checking ? 0.45 : 1)
            Text(AltanaKeySheet.liveLine(model))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
        }
        .animation(reduceMotion ? nil : DS.Motion.standard, value: model.live)
    }

    /// Granted → expires, with a marker where now sits.
    private func window(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .top) {
                capLabel(String(localized: "Granted"), model.registeredAt)
                Spacer(minLength: DS.Space.s3)
                capLabel(model.expired ? String(localized: "Expired") : String(localized: "Expires"),
                         model.expiry, trailing: true)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.textTertiary.opacity(0.18))
                    Capsule().fill(hue)
                        .frame(width: max(2, geo.size.width * progress))
                    // The marker is only meaningful while the grant is
                    // running — on a finished one the bar IS the answer.
                    if !finished {
                        Circle()
                            .fill(DS.textPrimary)
                            .frame(width: 11, height: 11)
                            .offset(x: max(0, geo.size.width * progress - 5.5))
                    }
                }
            }
            .frame(height: Self.windowHeight)
            if let line = AltanaKeySheet.windowLine(model) {
                Text(line)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(AltanaKeySheet.windowLine(model) ?? ""))
    }

    private func capLabel(_ label: String, _ date: Date?, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(label)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            Text(date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            if let registered = AltanaKeySheet.registeredLine(model) {
                fact(String(localized: "Registered"), registered)
            }
            fact(String(localized: "Used"), AltanaKeySheet.usageLine(model))
            fact(String(localized: "Key id"), shortKey, quiet: true)
        }
    }

    private func fact(_ k: String, _ v: String, quiet: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).dsText(.subhead13).foregroundStyle(DS.textSecondary)
            Spacer(minLength: DS.Space.s3)
            Text(v)
                .dsText(.subhead13)
                .fontWeight(quiet ? .regular : .semibold)
                .foregroundStyle(quiet ? DS.textSecondary : DS.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, DS.Space.s2)
    }

    private var shortKey: String {
        let body = model.keyID.hasPrefix("0x") ? String(model.keyID.dropFirst(2)) : model.keyID
        guard body.count > 12 else { return model.keyID }
        return "0x\(body.prefix(4))…\(body.suffix(4))"
    }

    /// The single-point-of-failure reading. Named wallets, tappable, and drawn
    /// only when the SAME key id really is registered elsewhere — never an
    /// inference about similarity.
    private var alsoSignsFor: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "Also signs for"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            HStack(spacing: DS.Space.s2) {
                ForEach(model.alsoSignsFor, id: \.self) { address in
                    Button {
                        DSHaptic.selection()
                        onWallet(address)
                    } label: {
                        Text(WalletStore.shortAddress(address))
                            .dsText(.subhead13).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                            .padding(.horizontal, DS.Space.s3)
                            .padding(.vertical, DS.Space.s2)
                            .background(DS.surfaceWell, in: Capsule())
                    }
                    .buttonStyle(PressSpring())
                }
                Spacer(minLength: 0)
            }
        }
    }
}
