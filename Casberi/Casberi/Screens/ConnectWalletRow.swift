import SwiftUI

/// The "Connect a wallet app" row — ONE implementation of the WalletConnect
/// handshake's UI, for both screens that offer it (prd §462).
///
/// §461 split the wallet manager into the roster and the Address Book, and the
/// connect flow stayed on the roster alone — which made connecting read as
/// watching's private door. It never was: a wallet app is also how you DISCOVER
/// addresses (it shares accounts, and §376's picker goes and finds the Safes
/// they sign on), and discovering is the book's business. So the row lives on
/// both screens, and what differs is the VERB the picker lands — the roster
/// watches (capped, starts syncing), the book names (uncapped, writes nothing
/// the app fetches). See `WalletConnectPickerSheet.Mode`.
///
/// Extracted from `WalletScreen` verbatim rather than copied to it: the
/// handshake's edge cases (the cancel generation, the manual-pairing fallback,
/// the Catalyst fork) were each paid for on a device, and two copies of that
/// is two places for the next fix to miss.
struct ConnectWalletRow: View {
    /// The settled session's accounts, handed to the caller — who presents the
    /// picker in its own mode. This row never watches and never names.
    var onFound: ([WalletConnectBridge.ConnectedAccount]) -> Void
    /// A worded outcome (message, isError) — the caller owns where it draws.
    var onNote: (String, Bool) -> Void

    /// The in-flight handshake — proposed, wallet opened, waiting on a human to
    /// approve over there (2026-07-16). Held as the Task rather than a Bool so
    /// a second tap can CANCEL it: the wait runs to the proposal's 5-minute
    /// expiry, and a person who opened their wallet, chose not to approve, and
    /// came back must not find a stuck button and no way out.
    @State private var connectTask: Task<Void, Never>?
    /// Bumped on every start and every cancel, so an in-flight handshake can
    /// tell whether it's still the CURRENT one.
    @State private var connectGeneration = 0
    /// The pairing URI, shown when nothing claimed `wc:` (2026-07-23) so it can
    /// be pasted into a wallet by hand. Non-nil means the handshake is still
    /// listening for that paste to be approved.
    @State private var pairingURI: URL?
    private var connecting: Bool { connectTask != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Button {
                DSHaptic.tap()
                if connecting { cancelConnect() } else { connectWallet() }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "wallet.pass.fill")
                        .dsGlyph(15, weight: .medium)
                        .foregroundStyle(DS.tint)
                        .frame(width: 34, height: 34)
                        .background(DS.tintDim, in: RoundedRectangle(
                            cornerRadius: DS.Radius.appIcon(34), style: .continuous))
                    Text(connecting ? "Waiting — tap to cancel" : "Connect a wallet app")
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .dsGlyph(12, weight: .semibold)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The app's one card token, not the gray (prd §542). This
                // is a row-card on a page, not a paper — no pour, no torn
                // edge — so it takes `surfaceSheet` like every other card
                // that sits on the page rather than ink like a paper.
                .dsInkFill()
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(connecting ? "Waiting for your wallet, tap to cancel"
                                                : "Connect a wallet app"))
            // No app claimed `wc:` — the URI, to paste into the wallet
            // directly. The handshake is still listening while this shows.
            if let uri = pairingURI {
                manualPairingCard(uri)
            }
        }
    }

    /// The paste-it-yourself route (2026-07-23). A wallet that registers only a
    /// universal link never claims `wc:`, so `canOpenURL` reads false on a
    /// device that HAS a wallet — this is the way through, not an error, and
    /// the approval it leads to is the same one the direct open would get.
    private func manualPairingCard(_ uri: URL) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Not listed? Copy the link into your wallet's scan screen — it's still waiting.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s2) {
                Text(uri.absoluteString)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                CopyAddressButton(address: uri.absoluteString, style: .inline)
            }
            .padding(DS.Space.s3)
            .dsWell()
        }
        .padding(.top, DS.Space.s1)
    }

    private func cancelConnect() {
        connectGeneration &+= 1   // orphans the in-flight task before it unwinds
        connectTask?.cancel()
        connectTask = nil
        pairingURI = nil
    }

    private func connectWallet() {
        pairingURI = nil
        connectGeneration &+= 1
        let generation = connectGeneration
        connectTask = Task { @MainActor in
            defer { if connectGeneration == generation { connectTask = nil } }

            let outcome: Result<WalletConnectBridge.ConnectOutcome, Error>
            do {
                // WalletConnect's own modal (2026-08-01) — the full wallet
                // directory with real icons and correct deep links.
                //
                // Mac Catalyst can't link the SDK (see the import in
                // `WalletConnectBridge`), so it keeps the open-then-paste
                // route. That is not a lesser fallback there: the directory is
                // 496 PHONE apps opened by deep link, none of which a Mac has,
                // and pasting the URI into a phone's wallet is what a desktop
                // dapp asks for too.
                #if targetEnvironment(macCatalyst)
                outcome = .success(try await WalletConnectBridge.connect(
                    open: openWalletApp,
                    offerManualPairing: { url in
                        // Still the current handshake? A cancelled one must not
                        // paint its URI over a fresh attempt.
                        guard connectGeneration == generation else { return }
                        pairingURI = url
                    }))
                #else
                outcome = .success(try await WalletConnectBridge.connectViaModal())
                #endif
            } catch {
                outcome = .failure(error)
            }

            guard connectGeneration == generation, !Task.isCancelled else { return }

            switch outcome {
            case .success(.connected(let found)):
                pairingURI = nil
                guard !found.isEmpty else {
                    onNote(String(localized: "Your wallet approved but shared no address — paste it instead."), true)
                    return
                }
                onFound(found)
            case .success(.noWalletApp):
                // Only reachable now if no manual-pairing handler ran — the
                // row always passes one, so this is the belt to that braces.
                onNote(String(localized: "No wallet app on \(DS.device) — paste the address instead."), true)
            case .success(.timedOut):
                // Which wait actually expired decides the words: if the URI
                // was on screen, the person was pasting, and telling them
                // "approve it in your wallet" describes a tap they never had.
                onNote(pairingURI == nil
                    ? String(localized: "Nothing came back from your wallet — approve the request there, or paste the address instead.")
                    : String(localized: "The connection link expired — tap Connect for a fresh one."), true)
                pairingURI = nil
            case .failure(WalletConnectBridge.ConnectError.tearDownFailed):
                onNote(String(localized: "Connected, but the session wouldn't close — open your wallet and disconnect Casberi. Nothing was watched."), true)
            case .failure(WalletConnectBridge.ConnectError.keychainUnavailable(let status)):
                onNote(String(localized: "This device's keychain refused the handshake (code \(status)) — paste the address instead."), true)
            case .failure:
                onNote(String(localized: "Couldn't reach your wallet — paste the address instead."), true)
            }
        }
    }

    /// Hand the `wc:` URI to whichever wallet claims the scheme, and report
    /// whether one actually did.
    @MainActor
    private func openWalletApp(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }
}
