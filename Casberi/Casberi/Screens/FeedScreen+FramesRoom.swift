import SwiftUI
import SwiftData

// The Frames devnet room: sending (prd §553), its scope chrome and account
// slots, and picking an account (prd §948), split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - Sending, from the Frames devnet (prd §553)

    /// **WHO SENDS (prd §728d)** — the passkey account when the room is scoped
    /// to it on the face rail, this phone's key otherwise. The held line says
    /// which, so the sheet never sends as an account it did not name.
    var framesSendsFromPasskey: Bool {
        guard let passkey = FramesPasskey.accountAddress(), let scope = chrome.framesScope else { return false }
        return scope.caseInsensitiveCompare(passkey) == .orderedSame
    }

    private var framesSenderAddress: String? {
        framesSendsFromPasskey ? FramesPasskey.accountAddress() : FramesKey.address()
    }

    /// **YOUR OWN, THEN WHO YOU'VE PAID, THEN WHO YOU WATCH (prd §1089,
    /// narrowing §990).** The picker opened on a search field over nothing:
    /// a phone holding one key and watching nobody had no face to tap, and
    /// the commonest test send — between two of your own accounts — needed a
    /// paste. §990 deleted SUGGESTED strangers; these are not suggestions but
    /// your own record: the accounts this phone holds, and the addresses your
    /// own sends paid, newest first. Never the account sending.
    var framesSendCandidates: [(address: String, name: String?)] {
        let sender = framesSenderAddress
        var seen = Set<String>()
        var out: [(address: String, name: String?)] = []
        func offer(_ address: String, _ name: String?) {
            let key = address.lowercased()
            guard !key.isEmpty, !seen.contains(key),
                  sender.map({ address.caseInsensitiveCompare($0) != .orderedSame }) ?? true
            else { return }
            seen.insert(key)
            out.append((address, FramesWatch.shared.name(for: address) ?? name))
        }
        let passkey = FramesPasskey.accountAddress()
        for address in FramesKey.addresses() { offer(address, String(localized: "Yours")) }
        if let passkey { offer(passkey, String(localized: "Passkey")) }
        // Who your own sends paid: the moves read for an account on this phone
        // whose sender is that account, newest first.
        let paid = FramesLiveState.shared.accounts
            .filter { FramesConnections.onPhone($0.address, passkey: passkey) }
            .flatMap { account in
                account.moves.filter { $0.sender.caseInsensitiveCompare(account.address) == .orderedSame }
            }
            .sorted { $0.blockNumber > $1.blockNumber }
        for move in paid {
            for address in move.recipients { offer(address, nil) }
        }
        for address in FramesWatch.shared.addresses { offer(address, nil) }
        return out
    }

    /// What the sending account holds, off the last sweep — never a live read,
    /// so a keystroke never spends a request. Nil when the sweep could not
    /// reach the chain: a failed read and a real zero must not look alike
    /// (§83), so the line is absent rather than claiming nothing is held.
    var framesHeldLine: String? {
        guard let mine = framesSenderAddress,
              let account = FramesLiveState.shared.accounts.first(where: {
                  $0.address.caseInsensitiveCompare(mine) == .orderedSame
              }), account.reached else { return nil }
        return FramesMoney.balanceLine(weiHex: account.balanceWeiHex)
            .map { framesSendsFromPasskey
                ? String(localized: "\($0) available · passkey account")
                : String(localized: "\($0) available") }
    }

    /// The batch being built, in the shape the ROOM reads a finished one.
    ///
    /// Built through `FramesTransaction.stitched` rather than assembled here,
    /// which is the whole point: the preview is then the real builder's own
    /// answer, so a screen cannot promise a shape the signer does not produce —
    /// including the atomic rule the node corrected, where the LAST payload
    /// frame never carries the flag.
    ///
    /// An unreadable amount contributes a frame with no value rather than
    /// dropping out, so the strip keeps one cell per leg while somebody is
    /// still typing.
    /// The Frames accounts this room is showing, after the face rail's scope.
    ///
    /// **Asked of `FramesRoomSource` rather than filtered here**, so the head,
    /// the figure and the rows cannot disagree about which addresses are on
    /// screen: the rule lives in one place and this is a call to it.
    var framesAccounts: [FramesAccount] {
        FramesRoomSource.accounts(scope: chrome.framesScope)
    }

    /// Every move the Frames room is currently showing, newest first — the
    /// denominator a sponsor's share is taken against.
    var framesShownMoves: [FramesMove] {
        framesAccounts.filter(\.reached).flatMap(\.moves)
            .sorted { $0.blockNumber > $1.blockNumber }
    }

    /// Which shown address a Frames move was read from.
    ///
    /// A move opened from a SPONSOR's sheet has lost its owner on the way —
    /// the payer is by definition not it — so it is looked up rather than
    /// guessed. Empty where the move is no longer in the shown set, which the
    /// sheet draws as an unknown endpoint rather than as somebody.
    func framesOwner(of move: FramesMove) -> String {
        framesAccounts.first {
            $0.moves.contains { $0.hash.lowercased() == move.hash.lowercased() }
        }?.address ?? ""
    }

    /// **ONE LEG, AS THE ENCODER TAKES IT (prd §728b)** — a coin leg or a token
    /// leg, parsed at the asset's own decimals. Used by the send and by the
    /// preview, so the strip and the signature cannot build different legs.
    private func framesLeg(_ leg: DevnetSendLeg) -> FramesTransaction.Leg? {
        guard let target = RLP.data(fromHex: leg.address) else { return nil }
        if leg.asset.isEmpty {
            guard let value = DevnetSendParse.weiData(from: leg.amount) else { return nil }
            return FramesTransaction.Leg(recipient: target, value: value)
        }
        guard let asset = framesSendAssets.first(where: { $0.id == leg.asset }),
              let contract = RLP.data(fromHex: asset.id),
              let units = DevnetSendParse.unitsData(from: leg.amount, decimals: asset.decimals)
        else { return nil }
        return FramesTransaction.tokenLeg(contract: contract, to: target, amount: units)
    }

    /// **WHAT THIS PHONE'S ACCOUNT CAN SEND (prd §728b)** — the coin, then every
    /// token it holds whose decimals read. Empty when it holds no token, which
    /// leaves the sheet's unit a plain label exactly as before.
    var framesSendAssets: [DevnetSendAsset] {
        guard let mine = framesSenderAddress,
              let account = FramesLiveState.shared.accounts.first(where: {
                  $0.address.caseInsensitiveCompare(mine) == .orderedSame
              }), account.reached else { return [] }
        let tokens = account.tokens.compactMap { holding -> DevnetSendAsset? in
            guard let decimals = holding.decimals, let amount = holding.amount else { return nil }
            return DevnetSendAsset(id: holding.contract,
                                   unit: holding.symbol ?? WalletStore.shortAddress(holding.contract),
                                   heldLine: String(localized: "\(DevnetTokens.quantity(amount)) available"),
                                   decimals: decimals)
        }
        guard !tokens.isEmpty else { return [] }
        return [DevnetSendAsset(id: "", unit: String(localized: "test ETH"),
                                heldLine: framesHeldLine, decimals: 18)] + tokens
    }

    func framesPreviewRun(_ legs: [DevnetSendLeg]) -> [FramesFrameRow] {
        let built = legs.map {
            framesLeg($0) ?? FramesTransaction.Leg(recipient: RLP.data(fromHex: $0.address) ?? Data(),
                                                   value: Data())
        }
        // **BUILT JOINED, AND THE TOGGLE DIALS THE TIE** (2026-09-01).
        //
        // The `atomic` argument used to be threaded here, which drew both
        // states correctly and animated NEITHER: flipping the toggle changed
        // `flags` on the frames, and a run whose joins vanish in the same
        // instant as the strip's `joinProgress` gives the tie nothing to
        // travel over. So the toggle's own picture snapped, in the one place
        // the control is visible as a picture at all.
        //
        // Asking `stitched` for the JOINED shape and scaling the ties by the
        // toggle is exact rather than a stand-in, and the reason is a property
        // of the encoder: **the two stitched outputs differ in `flags` and in
        // nothing else** (see `FramesTransaction.stitched` — same frames, same
        // targets, same values, same gas), and `flags` reaches this drawing
        // through exactly one door, `FramesFrameRow.joinedToNext`, which the
        // strip renders as the tie and nowhere else. So `joinProgress: 0`
        // draws the non-atomic run byte for byte. Both halves of that are
        // pinned by `frames-tx-selftest.sh`, because it is the kind of claim
        // that stays true right up until somebody gives `flags` a second
        // meaning.
        let fields = FramesTransaction.stitched(sender: Data(), legs: built, atomic: true,
                                                nonce: 0, maxPriorityFeePerGas: 0, maxFeePerGas: 0,
                                                deadline: FramesSend.deadline())
        return fields.frames.map { frame in
            FramesFrameRow(
                frame: FramesRead.Frame(mode: frame.mode,
                                        flags: frame.flags,
                                        target: nil,
                                        executionGas: frame.executionGas,
                                        stateGas: frame.stateGas,
                                        value: "0x" + RLP.hex(frame.value),
                                        data: nil),
                // **NO OUTCOME, because nothing has happened.** The strip draws
                // an outcome-less cell as "ran", which is the right reading for
                // a plan: it is what this batch WILL do, and inventing a
                // success or a failure here would be a claim about a
                // transaction that has not been signed.
                outcome: nil)
        }
    }

    /// SEVERAL LEGS, ONE SIGNATURE (prd §548 sixth follow-up).
    ///
    /// Deliberately NOT `sendFrames` in a loop: a loop is several transactions
    /// with several nonces and several signatures, which can be reordered,
    /// partially mined, and separately refused — the opposite of what stitching
    /// is for, and it would make the all-or-nothing control a lie.
    func sendFramesStitched(_ legs: [DevnetSendLeg], atomic: Bool) async -> String? {
        guard !DemoMode.isActive else {
            return String(localized: "Nothing is sent in the demo — this is where your own key would sign it.")
        }
        guard let address = framesSenderAddress else {
            return String(localized: "There's no account on this phone yet.")
        }
        // **EVERY LEG IS PARSED BEFORE ANY IS SENT.** One unreadable amount
        // must refuse the whole transaction rather than quietly send the legs
        // that happened to parse — which is exactly the partial-send failure
        // the atomic control exists to let somebody rule out.
        var built: [FramesTransaction.Leg] = []
        for leg in legs {
            guard let frame = framesLeg(leg) else {
                return String(localized: "Couldn't read one of the frames.")
            }
            built.append(frame)
        }
        do {
            // The nonce is READ, never taken from the snapshot — `sendFrames`'
            // own reasoning, and it holds harder here: building a batch takes
            // long enough that a cached figure is more likely to be stale.
            guard let nonce = await FramesSend.currentNonce(for: address) else {
                return String(localized: "Couldn't reach the chain to read this account's nonce.")
            }
            let deadline = FramesSend.deadline()
            let hash = try await framesSendsFromPasskey
                ? FramesSend.sendFromPasskey(legs: built, atomic: atomic, nonce: nonce, deadline: deadline)
                : FramesSend.sendStitched(legs: built, atomic: atomic, nonce: nonce, deadline: deadline)
            // **SAY IT WENT, BEFORE THE CHAIN CAN.** `sendStitched` returns
            // when the node accepts the bytes, which is before any block
            // carries them — so the sheet dismissed onto a room showing the
            // world as it was, and from outside a send that worked looked
            // exactly like one that vanished.
            FramesLiveState.shared.notePending(hash: hash, legs: built.count,
                                               deadline: FramesSend.date(deadline), sender: address)
            await FramesLiveState.shared.refresh()
            return nil
        } catch let failure as FramesSend.Failure {
            switch failure {
            case .noKey:            return String(localized: "There's no account on this phone yet.")
            case .signingRefused:   return String(localized: "The signature was refused.")
            case .chainUnreachable: return String(localized: "Couldn't reach the chain — nothing was sent.")
            case .prefixTooLarge:   return String(localized: "That's more frames than this chain will verify at once — remove one.")
            case .broadcastRefused(let why): return String(localized: "The network refused it: \(why)")
            case .requestUnreadable, .requestSignatureInvalid, .notTheSponsor:
                return FramesSend.sentence(failure)
            }
        } catch {
            return String(localized: "Couldn't send.")
        }
    }

    /// **WHO CAN BE ASKED TO PAY (prd §728c)** — your other accounts on this
    /// phone first (prd §1089: they pay at once, no link), then the addresses
    /// you watch: a request goes to a person who has to open it and agree, so
    /// only somebody you follow makes sense to ask. Never the passkey account,
    /// which cannot sign a sponsor's half. Empty draws no row.
    var framesPayerCandidates: [(address: String, name: String?)] {
        let me = FramesKey.address()
        var seen = Set<String>()
        var out: [(address: String, name: String?)] = []
        func offer(_ address: String, _ name: String?) {
            guard me.map({ address.caseInsensitiveCompare($0) != .orderedSame }) ?? true,
                  seen.insert(address.lowercased()).inserted else { return }
            out.append((address, FramesWatch.shared.name(for: address) ?? name))
        }
        for address in FramesKey.addresses() { offer(address, String(localized: "Yours")) }
        for address in FramesWatch.shared.addresses { offer(address, nil) }
        return out
    }

    /// **WHICH ACCOUNT SENDS, FROM THE SHEET (prd §1089)** — this phone's keys,
    /// then its passkey account. The pick is the room's own (`framesPickAccount`),
    /// so the sheet and the account menu are one choice.
    var framesSenderChoice: DevnetSenderChoice {
        var candidates: [(address: String, name: String)] = FramesKey.addresses().map {
            ($0, FramesWatch.shared.name(for: $0) ?? WalletStore.shortAddress($0))
        }
        if let passkey = FramesPasskey.accountAddress() {
            candidates.append((passkey, String(localized: "Passkey · Face ID")))
        }
        return DevnetSenderChoice(candidates: candidates,
                                  current: framesSenderAddress,
                                  pick: { framesPickAccount($0) })
    }

    /// Sign the batch as a request for `payer`, and hand back the link.
    /// **A THIRTY-MINUTE DEADLINE**, not a send's five — see
    /// `FramesSponsor.requestWindow`.
    func askFramesSponsor(_ legs: [DevnetSendLeg], atomic: Bool,
                                  payer: String) async -> DevnetAskResult {
        guard !DemoMode.isActive else {
            return DevnetAskResult(failure: String(localized: "Nothing is signed in the demo — this is where your own key would sign the request."))
        }
        guard let address = FramesKey.address() else {
            return DevnetAskResult(failure: String(localized: "There's no account on this phone yet."))
        }
        guard let sponsor = RLP.data(fromHex: payer) else {
            return DevnetAskResult(failure: String(localized: "Couldn't read who pays."))
        }
        var built: [FramesTransaction.Leg] = []
        for leg in legs {
            guard let frame = framesLeg(leg) else {
                return DevnetAskResult(failure: String(localized: "Couldn't read one of the frames."))
            }
            built.append(frame)
        }
        guard let nonce = await FramesSend.currentNonce(for: address) else {
            return DevnetAskResult(failure: String(localized: "Couldn't reach the chain to read this account's nonce."))
        }
        // **YOUR OWN OTHER ACCOUNT PAYS HERE (prd §1089)**: a send's five
        // minutes, since nobody has to be reached.
        let paysHere = FramesKey.holds(payer)
        let deadline = paysHere
            ? FramesSend.deadline()
            : UInt64(Date().timeIntervalSince1970 + FramesSponsor.requestWindow)
        do {
            let request = try await FramesSend.askSponsor(sponsor: sponsor, legs: built, atomic: atomic,
                                                          nonce: nonce, deadline: deadline)
            if paysHere {
                // The sponsor's half signs with the PAYER's key, and `FramesKey`
                // signs with the current account — so the payer is current for
                // exactly that signature and the sender is restored after,
                // whatever happens.
                FramesKey.select(payer)
                defer { FramesKey.select(address) }
                let hash = try await FramesSend.payForSponsor(request)
                FramesLiveState.shared.notePending(hash: hash, legs: built.count,
                                                   deadline: FramesSend.date(deadline), sender: address)
                await FramesLiveState.shared.refresh()
                return DevnetAskResult(sent: true)
            }
            guard let link = FramesSponsor.link(request) else {
                return DevnetAskResult(failure: String(localized: "Couldn't make a link for the request."))
            }
            return DevnetAskResult(link: link, expires: FramesSend.date(deadline))
        } catch let failure as FramesSend.Failure {
            return DevnetAskResult(failure: FramesSend.sentence(failure))
        } catch {
            return DevnetAskResult(failure: String(localized: "Couldn't sign the request."))
        }
    }

    func sendFrames(to: String, amount: String) async -> String? {
        guard !DemoMode.isActive else {
            return String(localized: "Nothing is sent in the demo — this is where your own key would sign it.")
        }
        guard let target = RLP.data(fromHex: to),
              let valueWei = DevnetSendParse.weiData(from: amount),
              let address = framesSenderAddress else {
            return String(localized: "Couldn't send.")
        }
        do {
            // **The nonce is READ, never taken from the snapshot.** A send a
            // moment after another one is exactly when the cached figure is
            // stale, and `nonce too low` is a refusal nobody can act on.
            guard let nonce = await FramesSend.currentNonce(for: address) else {
                return String(localized: "Couldn't reach the chain to read this account's nonce.")
            }
            // **EVERY SEND CARRIES A DEADLINE (prd §728b)**, and the pending row
            // is told it, so the row can say "it can't land now" with certainty.
            let deadline = FramesSend.deadline()
            let hash = try await framesSendsFromPasskey
                ? FramesSend.sendFromPasskey(legs: [FramesTransaction.Leg(recipient: target, value: valueWei)],
                                             atomic: false, nonce: nonce, deadline: deadline)
                : FramesSend.sendValue(to: target, valueWei: valueWei, nonce: nonce, deadline: deadline)
            FramesLiveState.shared.notePending(hash: hash, legs: 1,
                                               deadline: FramesSend.date(deadline), sender: address)
            await FramesLiveState.shared.refresh()
            return nil
        } catch let failure as FramesSend.Failure {
            switch failure {
            case .noKey:            return String(localized: "There's no account on this phone yet.")
            case .signingRefused:   return String(localized: "The signature was refused.")
            case .chainUnreachable: return String(localized: "Couldn't reach the chain — nothing was sent.")
            case .prefixTooLarge:   return String(localized: "The verify step asks for more gas than this chain allows.")
            // The node's OWN words (§530): a refusal with no reason cannot be
            // acted on, and on a send that is the worst place for it.
            case .broadcastRefused(let why): return String(localized: "The network refused it: \(why)")
            case .requestUnreadable, .requestSignatureInvalid, .notTheSponsor:
                return FramesSend.sentence(failure)
            }
        } catch {
            return String(localized: "Couldn't send.")
        }
    }

    /// THE FRAMES ROOM'S CHROME: the box, the tiles, the account menu (prd
    /// §1039) — the Wallet's merge, one chain over.
    ///
    /// **The crown is this room's `.home` figure.** `FramesRoomFigure` already
    /// switches on the scope and draws the crown for `.home` (`sponsorship`),
    /// so the chrome mounts that view pinned to `.home`. Off Home the same
    /// view draws the scope's figure in the same box.
    ///
    /// **Four tiles, and the verbs are rows (prd §1108):** Create is "New
    /// account" at the head of the Accounts menu, on every page; Send and Top
    /// up lead Holdings (`framesMoneyDoorsSection`) where `FramesActs` allows
    /// them (§774). Each tap runs exactly what the tile ran.
    @ViewBuilder
    func framesScopeChromeSection(_ active: FramesSection,
                                          head: FramesRoom.Head) -> some View {
        // Every account, never the scoped list: this is the control that SETS
        // the scope, so feeding it the narrowed set would leave one card on
        // screen and no way back.
        let roster = FramesRoomSource.accounts()
        Section {
            DSRoomScopeChrome(
                source: FramesIdentity.source,
                sections: chrome.framesSections,
                active: active,
                home: .home,
                attention: FramesSection.attention(),
                onPick: { picked in chrome.framesSection = picked },
                accounts: framesAccountSlots(roster) + hostedNetworkSlots,
                scope: chrome.framesScope,
                onPickAccount: { picked in
                    if !pickHostedNetwork(picked) { framesPickAccount(picked) }
                },
                accountAction: .init(title: String(localized: "New account"),
                                     symbol: "plus") {
                    FramesActs.create(store: bridges, chrome: chrome)
                },
                crown: { slot in
                    // The room figure carries its own slot (prd §953); a second
                    // one inset the Home crown 12pt past every other crown.
                    Group {
                        if slot.isShowing(chrome.framesScope) {
                            FramesRoomFigure(head: head,
                                             accounts: framesAccounts,
                                             section: .home,
                                             onOpenAccount: { feedSheet = .framesAccount($0) })
                        }
                    }
                },
                figure: { scope in
                    FramesRoomFigure(head: head,
                                     accounts: framesAccounts,
                                     section: scope,
                                     onOpenAccount: { feedSheet = .framesAccount($0) })
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                      bottom: DSRoomChassis.contentGap, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        // The room's read hangs HERE, on the chrome every scope draws —
        // Privacy's placement. It hung on `FramesRoomList`'s row, which has
        // nothing to draw until a read has landed, so a room with a key and
        // no read yet (a first account, or any room after the demo's Exit)
        // never read at all and sat on "Reading the chain…" (measured).
        .task { await FramesLiveState.shared.refresh() }
    }

    /// **SEND AND TOP UP LEAD HOLDINGS (prd §1108)** — the deleted verb tiles,
    /// drawn as Subscriptions' "Track a subscription" row is (§1105, §1117), over the
    /// list of what there is to send. Only on a page `FramesActs` allows
    /// (§774): All and your own accounts, never a stranger's.
    @ViewBuilder
    func framesMoneyDoorsSection(_ scope: FramesSection) -> some View {
        let account = chrome.framesScope
        if scope == .holdings, FramesActs.movesMoney(on: account) {
            Section {
                VStack(spacing: 0) {
                    DSDoorRow(icon: "arrow.up.right", label: "Send") {
                        FramesActs.send(account: account) { feedSheet = .framesSend }
                    }
                    DSDoorRow(icon: "drop", label: "Top up") {
                        FramesActs.topUp(account: account, chrome: chrome) { feedSheet = .web($0) }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    /// The Frames accounts as deck cards, "All" first.
    ///
    /// The deleted `FramesScopeRail.items` captioned with the BALANCE when an
    /// account had no name, which was a rail's compromise: 66pt fits a number
    /// or a name, not both. A card fits both, so the name leads and the
    /// balance goes to the sub line where it belongs.
    private func framesAccountSlots(_ roster: [FramesAccount]) -> [DSAccountSlot] {
        let all = DSAccountSlot(
            id: "",
            name: String(localized: "All accounts"),
            sub: roster.isEmpty
                ? String(localized: "Nothing watched on this chain yet")
                : ListFormatter.localizedString(
                    byJoining: roster.map { FramesWatch.shared.name(for: $0.address)
                        ?? WalletStore.shortAddress($0.address) }),
            faces: roster.prefix(2).map { .wallet(address: $0.address) })
        let passkey = FramesPasskey.accountAddress()
        return DSAccountSlot.groupedByPhone([all] + roster.map { account in
            DSAccountSlot(
                id: account.address,
                name: FramesWatch.shared.name(for: account.address)
                    ?? WalletStore.shortAddress(account.address),
                sub: FramesMoney.eth(fromWeiHex: account.balanceWeiHex ?? "")
                    .map { String(localized: "\($0) test ETH") },
                faces: [.wallet(address: account.address)])
        }, onPhone: { FramesConnections.onPhone($0, passkey: passkey) })
    }

    // MARK: - Picking a devnet account (prd §948)
    //
    // One function per room, read by BOTH doors to the pick — the account
    // menu under the tiles and the faces in the Accounts crown — so the two
    // can never disagree about what picking an account does.

    /// One of this phone's own faces makes that account the one Send and Top
    /// up act for (prd §774); a stranger's face picks nothing — `select`
    /// answers false and changes nothing.
    func framesPickAccount(_ picked: String?) {
        FramesKey.select(picked)
        withAnimation(DS.Motion.standard) {
            chrome.framesScope = (picked?.isEmpty ?? true) ? nil : picked
        }
    }

    /// What the two DEVNET rooms publish to the shell — the scopes each one has
    /// (PERF 2026-09-01).
    ///
    /// Guarded on `source` FIRST for the reason Wallet's is guarded on
    /// `shape`: these are read by every room as `onChange` keys, and
    /// SwiftUI evaluates a key on every body pass — so the cheap term has to be
    /// the one that decides. Unguarded they would also publish a devnet strip
    /// over whatever room is on screen.
    ///
    /// **These exist because the devnet rooms used to write `chrome.*Sections`
    /// from inside their own body**, and the same pass read the value back a
    /// few lines later (the figure, the rail, the switcher's `present:`).
    /// `ShellChrome` is `@Observable` and its generated setter mutates
    /// unconditionally — an equal-valued write still invalidates every
    /// observer — while `sections()` returns a fresh array per call, so the
    /// body invalidated itself for as long as the room was on screen. Wallet
    /// published the identical kind of value correctly from `onChange` the
    /// whole time; the devnet seats copied each other instead, which is why the
    /// file states the rule against it in `memo`'s own doc and it still
    /// reached them.
    var framesSectionPublication: [FramesSection] {
        guard source == FramesIdentity.source else { return [] }
        return FramesRoomSource.sections()
    }
}
