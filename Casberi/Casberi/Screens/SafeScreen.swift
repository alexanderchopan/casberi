import SwiftUI
import SwiftData

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
    @Environment(\.openURL) private var openURL
    @State private var syncing = false
    @State private var lastResult: String?
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen` (audit,
    /// 2026-07-31): hardcoding `false` painted "Couldn't reach Safe" in
    /// confirm green with the count-up animation.
    @State private var lastResultIsError = false
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

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }
    private var safeCount: Int { SafeBridge.detectedCount() }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Safe",
                mode: .watchedWallets,
                intro: "No account here — it reads the wallets you already watch, so you're told when a transaction is waiting on your signature. This phone can also be one of the Safe's owners, so your computer can't spend without your phone's yes.",
                connected: safeCount > 0)
            connectSection.listRowSeparator(.hidden)
            signerSection.listRowSeparator(.hidden)
            coSignersSection.listRowSeparator(.hidden)
            if hasWallets {
                ChipLiveNote(name: "Safe", verb: "for your Safe's signature queue.")
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Safe")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Safe")
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest on
            // appear, and refresh the queue if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
            signerAddress = SignerKey.address()
            signerPresence = SignerKey.presence()
            if SignerKey.exists {
                Task { signerStanding = await SafeSigner.standing() }
            }
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
    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if hasWallets {
                    DSSlabDoor(title: String(localized: "Watching \(walletCount) wallet"),
                               detail: String(localized: "Manage")) {
                        route.pushBridge(.wallet)
                    }
                } else {
                    DSSlabDoor(title: "Watch a wallet") {
                        route.pushBridge(.wallet)
                    }
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading your Safe's queue…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                // The bare "Read-only." left this note (duplication audit,
                // 2026-07-31): it was in one branch only, and the footer's
                // lede says the same thing with the part that matters — where
                // signing actually happens — in both states.
                DSSlabNote(text: safeCount > 0
                    ? String(localized: "Watching \(safeCount) Safe — a pending signature lands in your feed the moment it's proposed.")
                    : String(localized: "Watch a Safe, or a wallet that signs for one."))
            }
        }
        .dsSlabSection()
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
    @ViewBuilder private var signerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if signerPresence == .destroyed {
                    // The key is GONE, not locked. Saying so is the whole
                    // point: the previous behaviour was a Sign button that
                    // failed with the same words a cancelled prompt gives.
                    Text("This phone's signing key is gone. Face ID was re-enrolled on this device, which erases it by design — there is no copy. Make a new one, and have another owner swap the old address out of the Safe.")
                        .dsText(.subhead13).foregroundStyle(DS.destructive)
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
                                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                            Text(verbatim: WalletStore.shortAddress(address))
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if needsASafe {
                        DSSlabDoor(title: String(localized: "Set up a Safe"),
                                   systemImage: "arrow.up.right") {
                            if let url = URL(string: "https://app.safe.global/new-safe/create") {
                                openURL(url)
                            }
                        }
                    }
                    standingLines
                    Button { confirmDeleteSigner = true } label: {
                        Text("Delete this phone's key")
                            .dsText(.callout15).fontWeight(.semibold)
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
                    DSSlabNote(text: "The key stays on this phone behind Face ID. There is no recovery phrase, and re-enrolling Face ID erases it — so give the Safe a third owner you keep somewhere else.")
                }
                if let signerError {
                    Text(verbatim: signerError)
                        .dsText(.subhead13).foregroundStyle(DS.destructive)
                        .frame(maxWidth: .infinity)
                        .settleIn()
                }
            }
        }
        .dsSlabSection()
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
                    Image(systemName: "exclamationmark.triangle.fill").dsGlyph(13)
                        .foregroundStyle(DS.destructive)
                    Text(verbatim: String(localized: "\(WalletStore.shortAddress(safe.safeAddress)) needs \(safe.threshold) of its \(safe.ownerCount) owners, so every one of them is load-bearing. If this phone is lost or its Face ID is re-enrolled, that Safe can never be signed for again — and its owners can't be changed either, because that takes a signature too. Add one more owner."))
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if report.needingASpareOwner.isEmpty, !report.safes.isEmpty {
                Text(verbatim: signsForLine(report))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func signsForLine(_ report: SafeSigner.StandingReport) -> String {
        let spare = report.safes.map(\.spareOwners).min() ?? 0
        return String(localized: "Signing for \(report.safes.count) Safe. Losing this phone would still leave enough owners to change that (\(spare) to spare).")
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

    // MARK: - Who you sign with

    /// The people, not the addresses (2026-07-30). A Safe is the one place in
    /// this app where others act on your behalf, and the co-signers are the
    /// part of it worth recognising at a glance — so the screen shows their
    /// faces the same way the wallet manager shows a roster of wallets. Named
    /// from the address book / Farcaster where possible; short hex otherwise,
    /// never a guessed identity. Absent entirely when no Safe is detected, so
    /// nothing claims a roster that isn't there.
    @ViewBuilder private var coSignersSection: some View {
        if !coSigners.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Who you sign with")
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    ForEach(coSigners, id: \.self) { address in
                        HStack(spacing: DS.Space.s2) {
                            WalletFace(address: address, size: DS.Face.row, circular: true)
                            Text(verbatim: WalletIngest.knownLabel(for: address)
                                 ?? WalletStore.shortAddress(address))
                                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .dsSlabSection()
        }
    }

    /// Every OTHER owner across the detected Safes — your own watched wallets
    /// filtered out, since "who you sign with" means the other people.
    private var coSigners: [String] {
        let mine = Set(WalletStore.shared.addresses.map { $0.address.lowercased() })
        return SafeBridge.knownCoSigners().filter { !mine.contains($0.lowercased()) }
    }

    // MARK: - Actions

    /// Refresh the queue for the watched wallets. The catalog seat is kept
    /// honest by `store.reconcileWalletSeats()`, not here.
    private func sync() async {
        guard hasWallets, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await SafeBridge.syncNow(context: modelContext)
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
            lastResultIsError = false
        } else {
            lastResult = String(localized: "Couldn't reach Safe — check your connection.")
            lastResultIsError = true
        }
    }
}
