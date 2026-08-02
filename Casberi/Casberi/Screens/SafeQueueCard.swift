import SwiftUI

/// A Safe multisig thing's live queue card (2026-07-20, rebuilt 2026-07-30) —
/// the same shape as `ApprovalPrepareCard`: a read-only recheck, rendered only
/// once it's answered (no spinner theater).
///
/// The 2026-07-30 rebuild is about ONE idea: a Safe is the only object in this
/// app where other people act on your behalf and you wait on them. Every other
/// bridge is solo. So the queue is drawn as the PEOPLE it's waiting on — each
/// owner's own `WalletFace`, lit when they've signed and dim when they
/// haven't, yours marked — instead of the bare fraction "2 of 3", which says
/// nothing about who to go ask. Names come from `WalletIngest.knownLabel`'s
/// existing chain (address-book name → Farcaster handle → short hex), so a
/// person who has named their co-signers sees people, not hex.
///
/// Two facts the old card couldn't state, both cheap and both the kind almost
/// no interface surfaces: a same-nonce CONFLICT (a Safe executes exactly one
/// transaction per nonce, so signing this one may be wasted), and the door out
/// to the person's own Safe app — the one action this app deliberately can't
/// do, and until now had no way to hand off.
struct SafeQueueCard: View {
    let check: SafeBridge.Check
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            switch check.status {
            case .pending(let have, let required):
                pendingHead(have: have, required: required)
                if !check.roster.isEmpty { roster }
                if check.conflicts > 0 { conflictNote }
            case .executed:
                statusLine(icon: "checkmark.circle", tone: DS.confirm,
                           text: "Executed — the transaction went through.")
                if !check.roster.isEmpty { roster }
            case .replaced:
                statusLine(icon: "arrow.triangle.2.circlepath", tone: DS.textTertiary,
                           text: "Replaced — a different transaction executed at this position instead.")
            }
            if let door = check.doorURL, let url = URL(string: door) {
                doorRow(icon: "arrow.up.right", label: "Open in Safe") { openURL(url) }
            }
            Text("Signatures happen in your Safe app — never in Casberi.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: - Head

    /// The disc carries the count so the sentence doesn't have to, and the
    /// sentence spends its words on the thing a fraction can't say: who is
    /// left, or that nobody is.
    private func pendingHead(have: Int, required: Int) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            SafeSignatureDisc(have: have, required: required)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: headline(have: have, required: required))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subline(have: have, required: required) {
                    Text(verbatim: sub)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func headline(have: Int, required: Int) -> String {
        if check.readyToExecute {
            return String(localized: "Fully signed — ready to execute")
        }
        let waiting = check.waitingOn
        // "Your signature is the one missing" is the whole feature in a
        // sentence, and it's only sayable when we know which seat is yours.
        if waiting.count == 1, waiting[0].isYou {
            return String(localized: "Yours is the last signature needed")
        }
        if waiting.contains(where: \.isYou) {
            return String(localized: "Waiting on you and \(waiting.count - 1) other\(waiting.count - 1 == 1 ? "" : "s")")
        }
        guard !waiting.isEmpty else {
            return required > 0
                ? String(localized: "\(have) of \(required) signatures collected")
                : String(localized: "\(have) signatures collected")
        }
        if waiting.count == 1 {
            return String(localized: "Waiting on \(waiting[0].displayName)")
        }
        return String(localized: "Waiting on \(waiting[0].displayName) and \(waiting.count - 1) other\(waiting.count - 1 == 1 ? "" : "s")")
    }

    private func subline(have: Int, required: Int) -> String? {
        guard required > 0 else { return nil }
        if check.readyToExecute {
            return String(localized: "\(have) of \(required) — anyone can execute it now")
        }
        let short = required - have
        return String(localized: "\(have) of \(required) · \(short) more to go")
    }

    // MARK: - The people

    private var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(check.roster) { signer in
                HStack(spacing: DS.Space.s2) {
                    WalletFace(address: signer.address, size: 24, circular: true)
                        .opacity(signer.signed ? 1 : 0.38)
                        .overlay(alignment: .bottomTrailing) {
                            if signer.signed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(DS.confirm)
                                    .background(Circle().fill(DS.page).padding(1))
                                    .offset(x: 2, y: 2)
                            }
                        }
                    Text(verbatim: signer.isYou
                         ? String(localized: "\(signer.displayName) (you)")
                         : signer.displayName)
                        .dsText(.subhead13)
                        .foregroundStyle(signer.signed ? DS.textPrimary : DS.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: signer.signed
                         ? signedLabel(signer)
                         : String(localized: "waiting"))
                        .dsText(.label12)
                        .foregroundStyle(signer.signed ? DS.textTertiary : DS.textSecondary)
                }
            }
        }
    }

    /// When they signed, relative — "2h ago". A confirmation with an
    /// unparseable stamp still counts as signed (the signature is the fact);
    /// it just doesn't claim a time it doesn't have.
    private func signedLabel(_ signer: SafeBridge.Signer) -> String {
        guard let at = signer.signedAt, at != .distantPast else {
            return String(localized: "signed")
        }
        return at.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    // MARK: - Conflict

    /// A Safe executes exactly one transaction per nonce. Two live at the
    /// same one means only one can ever land — so a signature spent on the
    /// loser is spent for nothing. Stated plainly, not as an alarm: it's a
    /// fact about how Safes work, not a sign anything is wrong.
    private var conflictNote: some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 18)
            Text(check.conflicts == 1
                 ? "Another transaction is queued at the same position — only one of the two can execute."
                 : "\(check.conflicts) other transactions are queued at the same position — only one of them can execute.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bits

    private func statusLine(icon: String, tone: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tone)
            Text(text)
                .dsText(.callout15).foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func doorRow(icon: String, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}

/// The signature ring — `MetricDisc`'s doctrine applied to a multisig: a
/// generic glyph names nothing, so this one is segmented by the Safe's OWN
/// owner count and fills per signature collected. A 2-of-3 and a 4-of-7 draw
/// visibly different marks because they ARE different, and the count sits in
/// the middle so the disc states the whole fact alone.
struct SafeSignatureDisc: View {
    let have: Int
    let required: Int
    var size: CGFloat = 44

    private var met: Bool { required > 0 && have >= required }

    var body: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
            // One segment per required signature, with a hairline gap — the
            // ring counts, it doesn't just fill. Drawn as trims rather than a
            // dashed stroke so the gaps stay even at any `required`.
            if required > 0 {
                ForEach(0..<required, id: \.self) { i in
                    let span = 1.0 / Double(required)
                    let gap = min(0.02, span * 0.18)
                    Circle()
                        .trim(from: Double(i) * span + gap / 2,
                              to: Double(i + 1) * span - gap / 2)
                        .stroke(i < have ? (met ? DS.confirm : DS.tint) : DS.textTertiary.opacity(0.28),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            Text(verbatim: required > 0 ? "\(have)/\(required)" : "\(have)")
                .dsText(.label12)
                .monospacedDigit()
                .foregroundStyle(met ? DS.confirm : DS.textPrimary)
        }
        .frame(width: size, height: size)
        .animation(DS.Motion.standard, value: have)
        .accessibilityElement()
        .accessibilityLabel(required > 0
                            ? Text("\(have) of \(required) signatures collected")
                            : Text("\(have) signatures collected"))
        // Tooltip but no hover, deliberately: the ring is a readout, not a
        // control, and a pointer lift on something a click can't act on is the
        // dead affordance the honesty rule bans. Naming a wordless mark is
        // exactly what `dsTooltip` is for — same sentence VoiceOver reads.
        .dsTooltip(required > 0
                   ? String(localized: "\(have) of \(required) signatures collected")
                   : String(localized: "\(have) signatures collected"))
    }
}
