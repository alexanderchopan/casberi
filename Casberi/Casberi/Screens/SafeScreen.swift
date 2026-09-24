import SwiftUI
import SwiftData
// `RPCID`, for the pasted ask that rides the paired ask's shape (prd §913).
import WalletConnectSign

/// Safe, connected — the pending signature queue for any Safe you watch
/// directly, or any Safe that watches one of your own wallets as a signer
/// (2026-07-30). A Safe multisig has no account of its own to sign into —
/// signing happens in the person's own Safe app — so the seat rides the
/// watched wallets the way Peer/0xBow do, and connecting is one switch.
/// Unlike those two, this seat is gated on an ACTUAL detected Safe
/// (`SafeBridge.detectedCount()`), not on a wallet merely being watched:
/// most wallets are neither a Safe nor a Safe signer, and a seat claiming
/// otherwise would be fake status (the same divergence Gnosis Pay's seat
/// makes for the same reason).
struct SafeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome
    @State private var syncing = false
    @State private var lastResult: BridgeProof?
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen` (audit,
    /// 2026-07-31): hardcoding `false` painted "Couldn't reach Safe" in
    /// confirm green with the count-up animation.
    /// Redrawn on create/delete — `SignerKey.address()` reads UserDefaults,
    /// which SwiftUI does not observe.
    @State private var signerAddress: String? = SignerKey.address()
    @State private var signerError: String?
    @State private var confirmDeleteSigner = false
    /// Whether the KEY is still there, not just whether we remember its
    /// address — see `SignerKey.Presence`. Costs no biometric prompt.
    @State private var signerPresence: SignerKey.Presence = SignerKey.presence()
    /// What this phone signs for, and whether losing it would end any of it.
    /// Nil until the read answers; an unreachable read says so rather than
    /// drawing an all-clear.
    @State private var signerStanding: SafeSigner.StandingReport?
    /// What the pending queue owes each co-signer, and how many transactions
    /// there are to owe anything on.
    ///
    /// **Held in `@State`, refreshed on appear and after a sync, NEVER read
    /// from the body.** Both numbers come off `SafeBridge`'s tracking store,
    /// which is a `UserDefaults` read plus a JSON decode — cheap once and a
    /// per-row cost inside a computed property the body evaluates (prd §626,
    /// and §628's rule that a fetch belongs in `onAppear`/`.task` and never in
    /// something a body reads). The first cut of this feature did exactly that
    /// and decoded the store once per roster row per render.
    @State private var queueReading: (outstanding: [String: Int], pending: Int) = ([:], 0)

    // MARK: §913 — the vault-chip key, the paired apps, the guarded wallets

    /// The Secure Enclave owner (prd §913): whether the key is there, the
    /// proxy address the factory answered with, and whether this chain can
    /// take the route at all. Read on appear, never in the body (§628).
    @State private var enclavePresence: SafeEnclaveKey.Presence = SafeEnclaveKey.presence()
    @State private var enclaveAddress: String? = SafeEnclaveSigner.anyCachedAddress()
    /// nil until the chain answers; false is a chain with no factory.
    @State private var enclaveRoute: Bool?
    @State private var confirmDeleteEnclave = false
    /// The `wc:` link a person pastes to pair a Safe app to this phone.
    @State private var pairingLink = ""
    @State private var confirmDisconnect: SafePeer.PeerSession?
    /// A pasted typed-data request (tier 0), read into the same ask sheet a
    /// paired app's request opens.
    @State private var pastedRequest = ""
    @State private var pastedAsk: SafePeer.PendingAsk?
    /// What this phone guards, read live off each module on appear.
    @State private var guards: [SafeRecoverySigner.GuardStanding] = []
    @State private var confirmForgetGuard: GuardianLedger.Entry?

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }
    private var safeCount: Int { SafeBridge.detectedCount() }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Safe", seatID: "safe", source: SafeBridge.sourceName,
            state: AccountPageState.of(name: "Safe", seatID: "safe",
                                       connected: safeCount > 0, store: store),
            mode: .watchedWallets,
            // WHO YOU SIGN WITH is the roster. Safe earned its own source in
            // §349's amendment (it used to land under "Wallet"), so there is a
            // real room and a real list. READ rows, so no Remove: a co-owner
            // is a fact about the Safe, and a swipe offering to drop one would
            // be a control that cannot do what it says. The "You" pill lands
            // on this phone's own signing address where it is an owner.
            rows: rows,
            // NOTHING TO TEAR DOWN (prd §207): this seat reads whatever
            // wallets are watched and holds no store of its own. The signing
            // key is NOT torn down here — it is deleted by its own dialog,
            // which says why, because that undo is somebody ELSE's on-chain
            // transaction.
            teardown: {},
            sheet: $sheet,
            act: {
                connectBlock
                signerBlock
                enclaveBlock
                pairBlock
                guardsBlock
                requestBlock
                // THE TWO LIMITS THAT MAKE THE SIGNING CLAIM SAFE TO PRINT
                // (prd §641b, caught by `safetx-selftest.sh` after §641).
                // They lived in the offer's `features` list, which the product
                // page drew and which went with it — so the tagline went on
                // claiming "this phone as a signer" with nothing carrying the
                // limit. `NetworkReach` states it, but that is a sheet you
                // tap into, not the screen where you make the key.
                // Unnumbered: facts, not steps (§220).
                BridgeStepLines(steps: [
                    String(localized: "Signs behind Face ID. It can never execute."),
                    String(localized: "This phone holds no funds."),
                ], numbered: false)
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest on
            // appear, and refresh the queue if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
            signerAddress = SignerKey.address()
            signerPresence = SignerKey.presence()
            readQueue()
            if SafeSigner.hasAnyKey {
                Task { signerStanding = await SafeSigner.standing() }
                SafePeer.startIfNeeded { modelContext }
            }
            enclavePresence = SafeEnclaveKey.presence()
            enclaveAddress = SafeEnclaveSigner.anyCachedAddress()
            Task { await readEnclave() }
            Task { await readGuards() }
        }
        .sheet(item: $pastedAsk) { ask in
            SafeAskSheet(ask: ask, paired: false)
                .environment(chrome)
        }
        .confirmationDialog("Delete the vault-chip key?",
                            isPresented: $confirmDeleteEnclave, titleVisibility: .visible) {
            Button("Delete the key", role: .destructive) {
                SafeEnclaveKey.delete()
                enclavePresence = .none
                enclaveAddress = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The key lives only in this phone's Secure Enclave. Have another owner swap its signer address out of the Safe first, or the Safe is one signature short. No undo.")
        }
        .confirmationDialog("Disconnect this app?",
                            isPresented: Binding(get: { confirmDisconnect != nil },
                                                 set: { if !$0 { confirmDisconnect = nil } }),
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                if let session = confirmDisconnect {
                    Task { await SafePeer.disconnect(topic: session.topic) }
                }
                confirmDisconnect = nil
            }
            Button("Cancel", role: .cancel) { confirmDisconnect = nil }
        } message: {
            Text("It can pair again with a new link. Nothing it asked for is affected.")
        }
        .confirmationDialog("Stop guarding this wallet?",
                            isPresented: Binding(get: { confirmForgetGuard != nil },
                                                 set: { if !$0 { confirmForgetGuard = nil } }),
                            titleVisibility: .visible) {
            Button("Forget it here", role: .destructive) {
                if let entry = confirmForgetGuard { GuardianLedger.forget(entry) }
                confirmForgetGuard = nil
                Task { await readGuards() }
            }
            Button("Cancel", role: .cancel) { confirmForgetGuard = nil }
        } message: {
            Text("This forgets the wallet on this phone. The module still lists this phone as a guardian until the wallet's owner revokes it.")
        }
        // The one delete in this app whose undo is somebody ELSE's on-chain
        // transaction, so the confirm says so rather than counting rows.
        .confirmationDialog("Delete this phone's signing key?",
                            isPresented: $confirmDeleteSigner, titleVisibility: .visible) {
            Button("Delete the key", role: .destructive) {
                SignerKey.delete()
                signerAddress = nil
                signerError = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There is no copy and no recovery phrase — this key exists only here. Have another owner swap this address out of the Safe first, or the Safe is one signature short. No undo.")
        }
    }


    // MARK: - Connect (automatic — no switch, prd §207)

    /// No toggle: a Safe has no account to sign into, so watching a wallet —
    /// either the Safe itself, or one of its signers — IS the consent to
    /// read its queue. With wallets watched, the row states the fact and
    /// doors to the wallet manager; with none, it's the invitation to watch
    /// one.
    @ViewBuilder private var connectBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if hasWallets {
                DSSlabDoor(title: String(localized: "Watching \(walletCount) address"),
                           detail: String(localized: "Manage"),
                           systemImage: "eye") {
                    route.pushBridge(.wallet)
                }
            } else {
                DSSlabDoor(title: "Follow address", systemImage: "eye") {
                    route.pushBridge(.wallet)
                }
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading your Safe's queue…"),
                                 proof: lastResult)
            // The bare "Read-only." left this note (duplication audit,
            // 2026-07-31): it was in one branch only, and the footer's
            // lede says the same thing with the part that matters — where
            // signing actually happens — in both states.
            DSSlabNote(text: safeCount > 0
                ? String(localized: "Watching \(safeCount) Safe — a pending signature lands in your feed the moment it's proposed.")
                : String(localized: "Watch a Safe, or a wallet that signs for one."),
                       plain: true)
        }
    }


    // MARK: - This phone as a signer (prd §425)

    /// The whole setup, and it is one tap and an address (§9).
    ///
    /// **No form and no toggle** — §217's tripwire: the moment a connect page
    /// grows a switch it is the connect screen §96 deleted. Making the key is
    /// a verb with a visible outcome; whether this phone is actually an owner
    /// is read from the CHAIN at sign time, never claimed here, because a
    /// green "connected" that the Safe does not agree with is the §83 fake
    /// status in the one place believing it costs money.
    ///
    /// It states the two costs every other wallet app trains people not to
    /// expect: there is no recovery phrase, and re-enrolling Face ID destroys
    /// the key. Both are the security model rather than omissions — a phrase
    /// in a drawer is a second phone, and a key that survives a new face is a
    /// key that stopped meaning "this phone's yes".
    @ViewBuilder private var signerBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if signerPresence == .destroyed {
                // The key is GONE, not locked. Saying so is the whole
                // point: the previous behaviour was a Sign button that
                // failed with the same words a cancelled prompt gives.
                DSProse.text("This phone's signing key is gone — Face ID was re-enrolled, which erases it by design. Have another owner swap the old address out of the Safe.")
                    .dsText(.subhead12).foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                DSSlabDoor(title: String(localized: "Make a new key"),
                           systemImage: "signature") {
                    SignerKey.delete()
                    signerAddress = nil
                    signerPresence = .none
                    makeSigner()
                }
            } else if let address = signerAddress {
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: address, size: DS.Face.row, circular: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This phone")
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Text(verbatim: WalletStore.shortAddress(address))
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                DSSlabDoor(title: String(localized: "Copy address"),
                           systemImage: "doc.on.doc") {
                    DSPasteboard.copy(address)
                    chrome.flash(String(localized: "Address copied"))
                }
                // The NEXT STEP, not fine print — §315's rule is that a
                // gray sentence has to change what somebody would do, and
                // this one is the only thing left to do. It reads as an
                // instruction because it is one.
                //
                // It has TWO versions, because the next step genuinely
                // differs: somebody who already runs a Safe has an owner
                // to add, and somebody who does not has a Safe to make
                // first. The old single sentence assumed the first, which
                // left the second person holding an address with nowhere
                // to put it — the whole feature stalled one step in.
                Text(needsASafe
                     ? "You'll need a Safe to add it to. Make one with your other wallet as the first owner, then add this address as the second."
                     : "Add this address as an owner from your other wallet and set the threshold to 2. Casberi will notice when you have.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if needsASafe {
                    DSSlabDoor(title: String(localized: "Set up a Safe"),
                               systemImage: "arrow.up.right",
                               url: URL(string: "https://app.safe.global/new-safe/create"))
                }
                standingLines
                Button { confirmDeleteSigner = true } label: {
                    Text("Delete this phone's key")
                        .dsText(.body17)
                        .foregroundStyle(DS.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                DSSlabDoor(title: String(localized: "Make this phone a signer"),
                           systemImage: "signature") {
                    makeSigner()
                }
                // The one gray sentence this section gets, and it is spent
                // on the cost rather than the pitch — before the tap is the
                // only moment where "there is no recovery phrase" changes
                // what somebody does (it is the argument for 2-of-3 rather
                // than 2-of-2).
                DSSlabNote(text: "The key stays on this phone behind Face ID. There is no recovery phrase, and re-enrolling Face ID erases it — so give the Safe a third owner you keep somewhere else.", plain: true)
            }
            if let signerError {
                Text(verbatim: signerError)
                    .dsText(.subhead12).foregroundStyle(DS.destructive)
                    .frame(maxWidth: .infinity)
                    .settleIn()
            }
        }
    }

    /// True only when we KNOW there is nowhere to put this address: the
    /// lookup answered, and it found no Safe naming this phone.
    ///
    /// Never true from a read that failed. Offering "set up a Safe" to
    /// somebody who already has three, because the transaction service was
    /// briefly down, is the §83 fake status pointed at the one action that
    /// costs gas — and the honest cost of getting it wrong is that they
    /// deploy a second Safe they did not need.
    private var needsASafe: Bool {
        guard let report = signerStanding else { return false }
        return report.reachable && report.safes.isEmpty
    }

    /// What this phone actually signs for, and the one warning that has to be
    /// louder than everything else on this screen (prd §426 amendment).
    ///
    /// An N-of-N Safe cannot be repaired after an owner is lost — owner
    /// management is itself a threshold-meeting transaction, so there is no
    /// admin path and the funds are finished. The abstract "give it a third
    /// owner" advice sits in the note above; this says it about the Safe the
    /// person actually has, which is the only version anybody acts on.
    ///
    /// It never draws an all-clear from a read that did not answer: silence
    /// and "you are fine" must not look alike here.
    @ViewBuilder private var standingLines: some View {
        if let report = signerStanding, report.reachable {
            ForEach(report.needingASpareOwner, id: \.safeAddress) { safe in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill").dsGlyph(.caption)
                        .foregroundStyle(DS.destructive)
                    DSProse.text("\(WalletStore.shortAddress(safe.safeAddress)) needs all \(safe.ownerCount) of its owners. Lose this phone and it can never be signed for again — or repaired, since that takes a signature too. Add one more owner.")
                        .dsText(.subhead12).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if report.needingASpareOwner.isEmpty, !report.safes.isEmpty {
                Text(verbatim: signsForLine(report))
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func signsForLine(_ report: SafeSigner.StandingReport) -> String {
        let spare = report.safes.map(\.spareOwners).min() ?? 0
        // Two strings so English agrees with its own number (prd §855): the
        // one this replaced had no English localization, so it fell back to
        // the key and read "Signing for 2 Safe."
        let count = report.safes.count
        return count == 1
            ? String(localized: "Signing for one Safe. Losing this phone would still leave enough owners to change that (\(spare) to spare).")
            : String(localized: "Signing for \(count) Safes. Losing this phone would still leave enough owners to change that (\(spare) to spare).")
    }

    private func makeSigner() {
        signerError = nil
        do {
            let address = try SignerKey.create()
            signerAddress = address
            // The book is where every other address in this app is named, and
            // an unnamed hex row appearing in it later would be a mystery the
            // person cannot explain. `.smartAccount` would be a lie and
            // `.contract` doubly so: this is a plain EOA that happens to be
            // ours, which is exactly `.wallet`.
            _ = AddressBook.shared.setName(String(localized: "This phone"), for: address,
                                           provenance: "Casberi · signing key", kind: .wallet)
            signerPresence = .present
            Task { signerStanding = await SafeSigner.standing() }
            chrome.flash(String(localized: "Your signing address is ready"))
        } catch SignerKey.Failure.noBiometry {
            signerError = String(localized: "This device has no Face ID or Touch ID set up. The key is only worth having behind one, so Casberi won't make it.")
        } catch SignerKey.Failure.alreadyExists {
            signerAddress = SignerKey.address()
        } catch {
            signerError = String(localized: "Couldn't make the key on this device.")
        }
    }

    // MARK: - The vault-chip key (prd §913)

    /// The Secure Enclave owner. Its bytes never exist in this process,
    /// which is the one promise the §425 key cannot make; the cost is that
    /// the Safe takes it only through a signer contract the desktop deploys.
    ///
    /// **Offered only where it can be checked**: the door draws when the
    /// chip exists (never on a simulator) and the chain has answered that
    /// Safe's passkey factory is there. A route nothing can verify is not
    /// offered, because the first signature would be the test.
    @ViewBuilder private var enclaveBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if enclavePresence == .destroyed {
                DSProse.text("This phone's vault-chip key is gone — Face ID was re-enrolled, which erases it by design. Have another owner swap its signer address out of the Safe.")
                    .dsText(.subhead12).foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                DSSlabDoor(title: String(localized: "Make a new vault-chip key"), systemImage: "cpu") {
                    SafeEnclaveKey.delete()
                    enclavePresence = .none
                    enclaveAddress = nil
                    makeEnclaveKey()
                }
            } else if enclavePresence == .present {
                HStack(spacing: DS.Space.s3) {
                    if let address = enclaveAddress {
                        WalletFace(address: address, size: DS.Face.row, circular: true)
                    } else {
                        Image(systemName: "cpu").dsGlyph(.body).foregroundStyle(DS.textSecondary)
                            .frame(width: DS.Face.row, height: DS.Face.row)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This phone · vault chip")
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Text(verbatim: enclaveAddress.map(WalletStore.shortAddress)
                             ?? String(localized: "reading its signer address…"))
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                if let address = enclaveAddress {
                    DSSlabDoor(title: String(localized: "Copy signer address"), systemImage: "doc.on.doc") {
                        DSPasteboard.copy(address)
                        chrome.flash(String(localized: "Address copied"))
                    }
                    Text("From your other wallet: run createSigner on Safe's passkey factory for this key, then add this address as an owner — or swap it in for the plain key.")
                        .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { confirmDeleteEnclave = true } label: {
                    Text("Delete the vault-chip key")
                        .dsText(.body17)
                        .foregroundStyle(DS.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if SafeEnclaveKey.enclaveAvailable, enclaveRoute == true {
                DSSlabDoor(title: String(localized: "Make a vault-chip key"), systemImage: "cpu") {
                    makeEnclaveKey()
                }
                Text("A P-256 key born in the Secure Enclave. Its bytes never exist in the app, so there is nothing to export — the Safe takes it through a signer contract your other wallet deploys once.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func makeEnclaveKey() {
        signerError = nil
        do {
            _ = try SafeEnclaveKey.create()
            enclavePresence = .present
            chrome.flash(String(localized: "Vault-chip key made — reading its address"))
            Task { await readEnclave() }
        } catch SafeEnclaveKey.Failure.noBiometry {
            signerError = String(localized: "This device has no Face ID or Touch ID set up. The key is only worth having behind one, so Casberi won't make it.")
        } catch SafeEnclaveKey.Failure.alreadyExists {
            enclavePresence = .present
        } catch {
            signerError = String(localized: "Couldn't make the key in this device's Secure Enclave.")
        }
    }

    /// The factory's answer on mainnet: whether the route exists there, and
    /// the proxy address once a key exists. Every rail chain shares the
    /// address; mainnet is asked because it is the chain the factory reached
    /// first and the one most Safes live on.
    private func readEnclave() async {
        enclaveRoute = await SafeEnclaveSigner.routeAvailable(chainId: 1)
        guard SafeEnclaveKey.exists else { return }
        if let address = await SafeEnclaveSigner.signerAddress(chainId: 1) {
            enclaveAddress = address
            _ = AddressBook.shared.setName(String(localized: "This phone (vault chip)"), for: address,
                                           provenance: "Casberi · signing key", kind: .key)
            if SafeSigner.hasAnyKey { signerStanding = await SafeSigner.standing() }
        }
    }

    // MARK: - Paired apps (prd §913)

    /// The Safe web app, paired to this phone the way it pairs to a hardware
    /// wallet. A pasted `wc:` link in, one method offered out.
    @ViewBuilder private var pairBlock: some View {
        if SafeSigner.hasAnyKey {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(SafePeer.state.sessions) { session in
                    DSPushRow(title: Text(verbatim: session.name),
                              subtitle: Text(verbatim: String(localized: "paired · until \(session.expires.formatted(.relative(presentation: .named)))")),
                              fact: Text("Disconnect"), factTone: DS.destructive, opens: false) {
                        confirmDisconnect = session
                    }
                }
                TextField(String(localized: "Paste a wc: pairing link"), text: $pairingLink, axis: .vertical)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...3)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsWell(cornerRadius: DS.Radius.control, recessed: true)
                DSSlabDoor(title: SafePeer.state.pairing ? String(localized: "Pairing…") : String(localized: "Pair a Safe app"),
                           systemImage: "link") {
                    let link = pairingLink
                    pairingLink = ""
                    Task {
                        switch await SafePeer.pair(uri: link, context: { modelContext }) {
                        case .success:
                            chrome.flash(String(localized: "Paired — the app can ask this phone to sign"), tone: .success)
                        case .failure(let error):
                            chrome.flash(Self.pairSentence(error), tone: .failure)
                        }
                    }
                }
                Text("In the Safe app, connect a wallet by WalletConnect and copy its link here. A paired app can ask this phone to sign a Safe transaction, statement or recovery, and nothing else — every other request is refused and lands in your feed.")
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func pairSentence(_ error: SafePeer.PairError) -> String {
        switch error {
        case .unavailable: return String(localized: "Pairing isn't available in this build.")
        case .noKey: return String(localized: "Make this phone a signer first.")
        case .notAPairingLink: return String(localized: "That isn't a WalletConnect pairing link.")
        case .relayRefused: return String(localized: "The relay didn't take the link — it may have expired.")
        }
    }

    // MARK: - Guarded wallets (prd §913)

    /// The wallets this phone has approved a recovery for, with what the
    /// module says about it now. A lone guardian is said in red: not a Safe
    /// that can lock, a phone that could take.
    @ViewBuilder private var guardsBlock: some View {
        if !guards.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(guards, id: \.wallet) { guardStanding in
                    DSPushRow(title: Text(verbatim: WalletIngest.knownLabel(for: guardStanding.wallet)
                                          ?? WalletStore.shortAddress(guardStanding.wallet)),
                              subtitle: Text(verbatim: guardLine(guardStanding)),
                              fact: Text("Forget"), factTone: DS.textTertiary,
                              subtitleTone: guardStanding.isLoneGuardian ? DS.destructive : DS.textTertiary,
                              opens: false) {
                        confirmForgetGuard = GuardianLedger.Entry(chainId: guardStanding.chainId,
                                                                  module: guardStanding.module,
                                                                  wallet: guardStanding.wallet)
                    }
                }
            }
        }
    }

    private func guardLine(_ g: SafeRecoverySigner.GuardStanding) -> String {
        guard g.isGuardian else { return String(localized: "no longer lists this phone as a guardian") }
        if g.isLoneGuardian {
            return String(localized: "this phone is its only guardian — it could replace the owners alone, so Casberi won't sign")
        }
        return String(localized: "guards it with \(g.count - 1) others · \(g.threshold) needed")
    }

    private func readGuards() async {
        var out: [SafeRecoverySigner.GuardStanding] = []
        for entry in GuardianLedger.all() {
            if let standing = await SafeRecoverySigner.standing(chainId: entry.chainId,
                                                                module: entry.module, wallet: entry.wallet) {
                out.append(standing)
            }
        }
        guards = out
    }

    // MARK: - A pasted request (prd §913, tier 0)

    /// The paste door for what a paired app would send: the typed data of a
    /// Safe transaction, a Safe message or a recovery, read into the same
    /// sheet. The answer goes to the clipboard.
    @ViewBuilder private var requestBlock: some View {
        if SafeSigner.hasAnyKey {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                TextField(String(localized: "Paste a signing request (typed data)"), text: $pastedRequest, axis: .vertical)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsWell(cornerRadius: DS.Radius.control, recessed: true)
                DSSlabDoor(title: String(localized: "Read the request"), systemImage: "text.magnifyingglass") {
                    readPastedRequest()
                }
            }
        }
    }

    private func readPastedRequest() {
        let text = pastedRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let typed = EIP712.parse(text) else {
            chrome.flash(String(localized: "That isn't typed data Casberi can read."), tone: .failure)
            return
        }
        switch SafePeerRequest.ask(from: typed, chainId: nil) {
        case .success(let ask):
            let address = signerAddress ?? enclaveAddress ?? ""
            pastedAsk = SafePeer.PendingAsk(topic: "pasted", requestId: .left(UUID().uuidString),
                                            app: String(localized: "A pasted request"),
                                            address: address, ask: ask)
            pastedRequest = ""
        case .failure(let refusal):
            chrome.flash(SafePeer.sentence(for: refusal, method: "paste"), tone: .failure)
        }
    }

    // MARK: - Who you sign with

    /// WHO YOU SIGN WITH — the page's roster since §639. A Safe is the one
    /// place in this app where others act on your behalf, and the co-signers
    /// are the part of it worth recognising at a glance. Named from the
    /// address book / Farcaster where possible; short hex otherwise, never a
    /// guessed identity. Empty when no Safe is detected, so nothing claims a
    /// roster that isn't there.
    /// Reads the queue once. Called from `onAppear` and after a sync — the two
    /// moments it can have changed — never from a body.
    private func readQueue() {
        queueReading = (SafeBridge.outstandingCounts(), SafeBridge.pendingCountForRoster())
    }

    private var rows: [AccountPageShape.Row] {
        coSigners.map { address in
            AccountPageShape.Row(
                id: address,
                title: WalletIngest.knownLabel(for: address) ?? WalletStore.shortAddress(address),
                subline: sublineFor(address),
                weekCount: 0, hasNew: false,
                isYou: address.caseInsensitiveCompare(signerAddress ?? "") == .orderedSame,
                avatarURL: nil)
        }
    }

    /// What this co-signer is actually doing right now.
    ///
    /// Every row said "signs with you" — true of all of them, and therefore
    /// about none of them. The queue already knows who is holding what up
    /// (`SafeBridge.PendingSnapshot.unsignedOwners`, kept for the room head),
    /// so the roster can say it for free: no request, no new field, no
    /// CloudKit deploy.
    ///
    /// **It never says "signed everything" from an empty read.** An owner
    /// list that did not answer this pass leaves `unsignedOwners` empty, which
    /// is indistinguishable from an owner who owes nothing — so the all-clear
    /// is only drawn when there IS a live queue to have signed, and the
    /// no-queue case falls back to the standing fact.
    private func sublineFor(_ address: String) -> String {
        let waiting = queueReading.outstanding[address.lowercased()] ?? 0
        if waiting == 1 { return String(localized: "1 transaction is waiting on them") }
        if waiting > 1 { return String(localized: "\(waiting) transactions are waiting on them") }
        guard queueReading.pending > 0 else {
            return String(localized: "signs with you")
        }
        return String(localized: "signed everything pending")
    }

    /// Every OTHER owner across the detected Safes — your own watched wallets
    /// filtered out, since "who you sign with" means the other people.
    private var coSigners: [String] {
        let mine = Set(WalletStore.shared.addresses.map { $0.address.lowercased() })
        return SafeBridge.knownCoSigners().filter { !mine.contains($0.lowercased()) }
    }

    // MARK: - Actions

    /// Safe's keyless reads share one monthly pool across every app that uses
    /// them, so the line names Safe's limit, not the person's usage.
    static func throttledLine(until: Date?) -> String {
        guard let until else {
            return String(localized: "Safe paused reads, so the queue wasn't checked.")
        }
        return String(localized: "Safe paused reads, so the queue wasn't checked. It reopens \(until.formatted(.relative(presentation: .named))).")
    }

    /// Refresh the queue for the watched wallets. The catalog seat is kept
    /// honest by `store.reconcileWalletSeats()`, not here.
    private func sync() async {
        guard hasWallets, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let result = await SafeBridge.syncNow(context: modelContext)
        // The sync is the other moment the queue can have changed.
        readQueue()
        switch result {
        case .landed(let added):
            lastResult = .landed(added)
        case .throttled(let until, _):
            // A throttle is its own state and draws as `.says`, never
            // `.failed` (§711b): nothing is wrong with the person's Safe or
            // connection, and a "Try again" would meet the same closed gate.
            // It is never `.landed(0)`, which reads "Up to date" (prd §789).
            lastResult = .says(Self.throttledLine(until: until))
        case .unreachable:
            lastResult = .failed(String(localized: "Couldn't reach Safe — check your connection."))
        }
    }
}
