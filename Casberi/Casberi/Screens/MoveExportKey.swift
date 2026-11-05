import SwiftUI
import UIKit

/// **EXPORT A PRIVATE KEY (prd §1493)** — the way out without Casberi. One
/// sentence, one warning, then Create the key: the key is created in memory
/// (`YourAccountExport.create`), noted, and added as an owner on each network
/// with one Face ID each. It is shown only once that has landed somewhere, so
/// nobody holds a key that opens nothing; then once, behind a hold, with Copy,
/// a QR and the two steps that use it. Remove the key takes it off again.
///
/// Raised over whatever is on screen, as the Signer's sheet is: Security is a
/// row in a list, and a row carries no presentation of its own.
struct MoveExportKey: View {
    let account: String
    let networks: [YourAccountOp.Network]
    /// Security reads the chain again when the page closes.
    let onClose: @MainActor () -> Void
    let close: @MainActor () -> Void
    /// The swipe off while the key exists nowhere else (UIKit's spelling,
    /// because the page is a hosting controller's).
    let holdOpen: @MainActor (Bool) -> Void

    enum Stage: Equatable {
        case intro
        case creating
        case shown(YourAccountExport.Key, on: [String], failed: [String])
        /// The Aztec account's keys, shown once (prd §1700f item 6).
        case aztecShown(AztecKeys)
        case refused(String)
    }

    /// What another Aztec wallet needs to open the same account.
    struct AztecKeys: Equatable {
        let secretKey: String
        let signingKey: String
        let salt: String
        /// The words a copy carries, labelled, one per line.
        var text: String { "Secret key: \(secretKey)\nSigning key: \(signingKey)\nSalt: \(salt)\nAccount: Schnorr" }
    }

    /// Which account's key the page reveals (prd §1700f item 6).
    enum Which { case safe, aztec }
    @State private var which: Which = .safe
    @State private var choosing = false
    private var hasAztec: Bool { AztecAccountStore.shared.isShown && AztecProver.isAvailable }
    @State private var stage: Stage
    @State private var revealed = false
    @State private var asQR = false
    @State private var copied = false
    @State private var removing = false

    init(account: String, networks: [YourAccountOp.Network], stage: Stage = .intro,
         onClose: @escaping @MainActor () -> Void, close: @escaping @MainActor () -> Void,
         holdOpen: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.account = account
        self.networks = networks
        self.onClose = onClose
        self.close = close
        self.holdOpen = holdOpen
        _stage = State(initialValue: stage)
    }

    private var shown: Bool {
        switch stage { case .shown, .aztecShown: true; default: false }
    }

    var body: some View {
        DSTray(title: shown ? String(localized: "Your private key")
               : hasAztec ? String(localized: "Private keys") : String(localized: "Private key"),
               height: 640, detents: [.large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                switch stage {
                case .intro, .creating, .refused: intro
                case let .shown(key, on, failed): reveal(key, on: on, failed: failed)
                case let .aztecShown(keys): revealAztec(keys)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        // DSTray's `presentationBackground` reaches only a SwiftUI
        // presentation; a hosting controller's sheet takes it from here.
        .background(DS.surfaceSheet.ignoresSafeArea())
        // The key exists nowhere else: a swipe must not lose it. "I saved it"
        // and "Remove the key" are the way out (way-back-audit's ALLOWED).
        .onChange(of: stage, initial: true) { _, now in
            switch now {
            case .shown, .aztecShown: holdOpen(true)
            default: holdOpen(now == .creating)
            }
        }
        .onDisappear { onClose() }
    }

    // MARK: - Create

    @ViewBuilder private var intro: some View {
        MoveFlow {
            MoveWord(String(localized: "A key that opens"))
            // The account the key opens: tapped, Safe or Aztec (prd §1700f
            // item 6); with no Aztec account it is the Safe's and says so.
            Button {
                guard hasAztec, stage == .intro else { return }
                withAnimation(DS.Motion.standard) { choosing.toggle() }
                DSHaptic.selection()
            } label: {
                MoveWord(which == .aztec ? String(localized: "your Aztec account") : String(localized: "your Safe"), ink: DS.pickInk)
            }
            .buttonStyle(RowPress())
            .accessibilityHint(hasAztec ? Text("Picks which account") : Text(""))
            MoveWord(String(localized: "in another wallet."))
        }
        if choosing {
            VStack(alignment: .leading, spacing: 0) {
                accountChoice(.safe, String(localized: "Safe"), networks.map(\.name).formatted(.list(type: .and)), mark: "safe")
                accountChoice(.aztec, String(localized: "Aztec"), String(localized: "Private"), mark: "aztec")
            }
            .transition(.opacity)
        } else {
            Text("You'll see it once.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
            Text(verbatim: which == .aztec ? String(localized: "Aztec") : networks.map(\.name).formatted(.list(type: .and)))
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
        }
        if case let .refused(words) = stage {
            Text(verbatim: words)
                .dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accountChoice(_ pick: Which, _ title: String, _ line: String, mark: String) -> some View {
        Button {
            withAnimation(DS.Motion.standard) { which = pick; choosing = false }
            DSHaptic.selection()
        } label: {
            HStack(spacing: DS.Space.s3) {
                ProtocolInlineMark(mark: mark).frame(width: DSRoomChassis.headGlyph)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary)
                    Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
                if which == pick { Image(systemName: "checkmark").dsGlyph(.body).foregroundStyle(DS.pickInk) }
            }
            .frame(minHeight: DSFeed.headHeight + DS.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }

    // MARK: - Shown once

    @ViewBuilder private func reveal(_ key: YourAccountExport.Key, on: [String], failed: [String]) -> some View {
        Text(verbatim: String(localized: "On \(on.formatted(.list(type: .and)))"))
            .dsText(.subhead12).foregroundStyle(DS.textSecondary)
        if !failed.isEmpty {
            Text(verbatim: failed.joined(separator: " · "))
                .dsText(.subhead12).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        keyWell(key)
        HStack(spacing: DS.Space.s4) {
            tile(copied ? "checkmark" : "doc.on.doc", copied ? String(localized: "Copied") : String(localized: "Copy")) {
                DSPasteboard.copySensitive(key.hex)
                withAnimation(DS.Motion.standard) { copied = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(DS.Motion.standard) { copied = false }
                }
            }
            tile(asQR ? "textformat" : "qrcode", asQR ? String(localized: "Text") : String(localized: "QR")) {
                withAnimation(DS.Motion.standard) { asQR.toggle() }
            }
        }
        step(1, String(localized: "Import it into any wallet"), String(localized: "As a private key. It shows empty; that's expected."))
        step(2, String(localized: "Open app.safe.global with that wallet"), String(localized: "Your account and your money are there."))
    }

    /// The Aztec account's keys, once: held to show, copied together.
    @ViewBuilder private func revealAztec(_ keys: AztecKeys) -> some View {
        Text("Aztec").dsText(.subhead12).foregroundStyle(DS.textSecondary)
        ZStack {
            Text(verbatim: keys.text)
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .blur(radius: revealed ? 0 : 12)
                .accessibilityHidden(!revealed)
            if !revealed {
                VStack(spacing: DS.Space.s1) {
                    Image(systemName: "eye").dsGlyph(.title).foregroundStyle(DS.textPrimary)
                    Text("Hold to show").dsText(.heading17).foregroundStyle(DS.textPrimary)
                    Text("Nobody nearby?").dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(DS.Space.s4)
        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 60, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
            withAnimation(DS.Motion.standard) { revealed = pressing }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your Aztec keys, hidden"))
        .accessibilityAction(named: Text("Show")) { withAnimation(DS.Motion.standard) { revealed.toggle() } }
        tile(copied ? "checkmark" : "doc.on.doc", copied ? String(localized: "Copied") : String(localized: "Copy")) {
            DSPasteboard.copySensitive(keys.text)
            withAnimation(DS.Motion.standard) { copied = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(DS.Motion.standard) { copied = false }
            }
        }
        step(1, String(localized: "Import it into an Aztec wallet"), String(localized: "As a Schnorr account: the secret key, the signing key, salt 0."))
    }

    /// Blurred until held: the key is on screen only while a finger is.
    private func keyWell(_ key: YourAccountExport.Key) -> some View {
        ZStack {
            Group {
                if asQR, let code = SignerRequestSheet.code(key.hex) {
                    Image(uiImage: code)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 200)
                        .padding(DS.Space.s3)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
                } else {
                    Text(verbatim: key.grouped)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .blur(radius: revealed ? 0 : 12)
            .accessibilityHidden(!revealed)
            if !revealed {
                VStack(spacing: DS.Space.s1) {
                    Image(systemName: "eye").dsGlyph(.title).foregroundStyle(DS.textPrimary)
                    Text("Hold to show").dsText(.heading17).foregroundStyle(DS.textPrimary)
                    Text("Nobody nearby?").dsText(.subhead12).foregroundStyle(DS.textSecondary)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(DS.Space.s4)
        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 60, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
            withAnimation(DS.Motion.standard) { revealed = pressing }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your private key, hidden"))
        .accessibilityAction(named: Text("Show")) { withAnimation(DS.Motion.standard) { revealed.toggle() } }
    }

    private func tile(_ glyph: String, _ word: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: glyph).dsGlyph(.title).foregroundStyle(DS.pickInk)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                Text(verbatim: word).dsText(.subhead12).foregroundStyle(DS.textPrimary)
            }
            .frame(minWidth: 64, minHeight: DS.Hit.min)
        }
        .buttonStyle(PressSpring())
    }

    private func step(_ n: Int, _ title: String, _ line: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(verbatim: "\(n)").dsText(.heading17).foregroundStyle(DS.textSecondary)
                .monospacedDigit()
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(verbatim: line).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The foot (the keys walk's: a grey word, a pink verb)

    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            if case .aztecShown = stage {
                Spacer(minLength: DS.Space.s3)
                verb(String(localized: "I saved it"), enabled: true) { close() }
            } else if case let .shown(key, on, _) = stage {
                Button { remove(key, from: on) } label: {
                    Text(removing ? String(localized: "Removing…") : String(localized: "Remove the key"))
                        .dsText(.heading17).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
                }
                .buttonStyle(RowPress())
                .disabled(removing)
                Spacer(minLength: DS.Space.s3)
                verb(String(localized: "I saved it"), enabled: !removing) { close() }
            } else {
                Spacer(minLength: DS.Space.s3)
                verb(stage == .creating ? String(localized: "Revealing…") : String(localized: "Reveal key"),
                     enabled: stage != .creating && (which == .aztec || !networks.isEmpty)) {
                    if which == .aztec { revealAztecKeys() } else { create() }
                }
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset - DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
        .background(DS.surfaceSheet)
    }

    private func verb(_ word: String, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(verbatim: word)
                .dsText(.heading34)
                .foregroundStyle(enabled ? DS.pickInk : DS.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(minHeight: 48, alignment: .trailing)
        }
        .buttonStyle(RowPress())
        .disabled(!enabled)
    }

    // MARK: - Acting

    /// Face ID and the co-signer, then the engine hands the keys over once.
    private func revealAztecKeys() {
        withAnimation(DS.Motion.standard) { stage = .creating }
        Task {
            do {
                try await PrivateRootKey.unlock(reason: String(localized: "Reveal your Aztec account's key"))
                try await AztecCoSign.approve(String(localized: "Reveal your Aztec account's private key"))
                guard let out = try await AztecEngine.shared.call("exportKeys") as? [String: Any],
                      let secret = out["secretKey"] as? String, let signing = out["signingKey"] as? String else {
                    throw AztecCoSign.Failure(message: String(localized: "Your Aztec account did not answer"))
                }
                withAnimation(DS.Motion.standard) {
                    stage = .aztecShown(AztecKeys(secretKey: secret, signingKey: signing, salt: out["salt"] as? String ?? "0x0"))
                }
            } catch {
                withAnimation(DS.Motion.standard) { stage = .refused(AztecEngine.words(error)) }
            }
        }
    }

    private func create() {
        guard stage != .creating else { return }
        let key: YourAccountExport.Key
        do { key = try YourAccountExport.create() } catch {
            stage = .refused(String(localized: "Couldn't create a key on this \(ThisDevice.name)"))
            return
        }
        YourAccountExport.note(key.address, for: account)
        withAnimation(DS.Motion.standard) { stage = .creating }
        Task {
            var on: [String] = []
            var failed: [String] = []
            for net in networks {
                do {
                    let sent = try await YourAccountChain.addOutsideKey(
                        key.address, on: net, reason: String(localized: "Add a private key to your account on \(net.name)")) { _ in }
                    if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
                    else { on.append(net.name) }
                } catch let failure as YourAccountChain.Failure {
                    failed.append(MoveRecovery.worded(failure.message, on: net))
                } catch {
                    failed.append(String(localized: "\(net.name): not sent"))
                }
            }
            // Nowhere: the key opens nothing, so it is never shown.
            guard !on.isEmpty else {
                YourAccountExport.forget(key.address, for: account)
                withAnimation(DS.Motion.standard) { stage = .refused(failed.joined(separator: " · ")) }
                return
            }
            DSHaptic.success()
            withAnimation(DS.Motion.standard) { stage = .shown(key, on: on, failed: failed) }
        }
    }

    /// Off every network it went on; the page closes once it is.
    private func remove(_ key: YourAccountExport.Key, from on: [String]) {
        guard !removing else { return }
        removing = true
        Task {
            let failed = await Self.remove(key.address, account: account,
                                           from: networks.filter { on.contains($0.name) })
            removing = false
            if failed.isEmpty { close() } else {
                withAnimation(DS.Motion.standard) {
                    if case let .shown(key, on, _) = stage { stage = .shown(key, on: on, failed: failed) }
                }
            }
        }
    }

    /// Shared with Security's Remove: the failures, worded per network; the
    /// record is forgotten only once the key is off everywhere.
    static func remove(_ address: String, account: String, from networks: [YourAccountOp.Network]) async -> [String] {
        var failed: [String] = []
        for net in networks {
            do {
                let sent = try await YourAccountChain.removeOwnerKey(
                    address, on: net, reason: String(localized: "Remove \(YourAccount.short(address)) from your account on \(net.name)")) { _ in }
                if case .pending = sent.outcome { failed.append(String(localized: "\(net.name): sent, not yet seen")) }
            } catch let failure as YourAccountChain.Failure {
                failed.append(MoveRecovery.worded(failure.message, on: net))
            } catch {
                failed.append(String(localized: "\(net.name): not removed"))
            }
        }
        if failed.isEmpty { YourAccountExport.forget(address, for: account) }
        return failed
    }

    // MARK: - Raising it

    @MainActor
    final class Handle {
        var close: @MainActor () -> Void = {}
        var holdOpen: @MainActor (Bool) -> Void = { _ in }
    }

    /// Over whatever is on screen; the returned closure takes it down.
    @MainActor
    static func present(account: String, networks: [YourAccountOp.Network], stage: Stage = .intro,
                        onClose: @escaping @MainActor () -> Void) {
        let handle = Handle()
        let host = UIHostingController(rootView: MoveExportKey(account: account, networks: networks, stage: stage,
                                                               onClose: onClose, close: { handle.close() },
                                                               holdOpen: { handle.holdOpen($0) }))
        host.view.backgroundColor = UIColor(DS.surfaceSheet)
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        handle.close = { [weak host] in host?.dismiss(animated: true) }
        handle.holdOpen = { [weak host] in host?.isModalInPresentation = $0 }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(host, animated: true)
    }
}
