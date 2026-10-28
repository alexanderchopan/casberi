import SwiftUI

/// **THE WALLET'S SECURITY TILE (prd §1107)** — who can act for you, and what
/// is trying to fool you, in one place.
///
/// It took two tiles' work: Permissions' (Safe signatures, delegations,
/// approvals, §947) and the three kinds Risk listed as "Worth a look" — address
/// poisoning, fake tokens, fake transfers (user: "those are three rows"). The
/// loan risk Risk also held went to Holdings, beside the positions it is about.
///
/// **The box is a CHECKUP** (user: "checkup is the best"): six counts, one per
/// kind, in the list's own order, and no statement over them (§1107a). A count
/// with something behind it is a door to its section; a zero is a fact and
/// takes no tap (§83). It replaced the ringed faces over "in reach" (user: "i
/// HATE the image we have there"); what each grant reaches is on its row.
///
/// The cells stand bare on the box's well, as every figure does: no plate
/// under a cell (§758, §782).
struct WalletSecurityCounts: Equatable {
    var signatures = 0
    var delegations = 0
    var approvals = 0
    var unlimited = 0
    var poisoning = 0
    var fakeTokens = 0
    var fakeTransfers = 0
    /// **YOUR ACCOUNT'S THREE (prd §1462, user: "F looks the cleanest").**
    /// Nil with no account on this phone.
    var account: YourAccountFacts? = nil

    var flagged: Int { poisoning + fakeTokens + fakeTransfers }
    var isEmpty: Bool {
        signatures + delegations + approvals + flagged == 0
    }
}

extension FeedScreen {

    /// The six counts, from the same reads the sections below draw on, so a
    /// cell and its section can never disagree.
    var walletSecurityCounts: WalletSecurityCounts {
        let holders = WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                      acting: walletLive.acting)
        let warnings = walletLive.warnings
        let grants = walletLive.exposure.all
        return WalletSecurityCounts(
            signatures: walletSignatureWarnings.count,
            delegations: WalletPermissions.actingHolders(holders).count,
            approvals: grants.count,
            unlimited: grants.filter(\.unlimited).count,
            poisoning: warnings.filter { $0.kind == .poisoning }.count,
            fakeTokens: warnings.filter { $0.kind == .spoofedSymbol }.count,
            fakeTransfers: warnings.filter { $0.kind == .fakeTransfer }.count,
            account: YourAccountFacts.current)
    }

    /// Where a cell's door lands: its section's header.
    enum SecurityAnchor: String {
        case account, signatures, delegations, approvals, poisoning, fakeTokens, fakeTransfers
        var id: String { "wallet.security.\(rawValue)" }
    }

    /// **YOUR ACCOUNT'S KEYS LEAD SECURITY (prd §1436, user: "ya this makes a
    /// lot more sense").** This iPhone, the recovery key, the outside key —
    /// `MoveSecurity`'s rows, moved here from Move so Move is the acts alone
    /// and every question of keys has one home. On All, or with your account
    /// picked; a followed wallet's Security is a reading, never a key.
    @ViewBuilder
    var walletAccountSection: some View {
        // The demo's own account in the demo (prd §1475), else this phone's.
        if let account = YourAccountDemo.shownAddress,
           chrome.walletScope == nil || WalletWatch.sameAddress(chrome.walletScope ?? "", account) {
            walletCard(String(localized: "Your account"), glyph: ScopeTileGlyph.move, anchor: SecurityAnchor.account.id) {
                MoveSecurity(account: account)
                    .walletStackRow()
                    // The nudge's landing (`ShellChrome.openYourAccount`, prd §1480).
                    .task(id: chrome.walletScrollRequest) {
                        guard chrome.walletScrollRequest == SecurityAnchor.account.id else { return }
                        try? await Task.sleep(for: .milliseconds(300))
                        cardScrollTarget = SecurityAnchor.account.id
                        chrome.walletScrollRequest = nil
                    }
            }
            // Where each network is read from (prd §1517), under the Keys card.
            // The recovery check's page is Needs you's door (§1515): the Keys
            // card already has a Recovery key row.
            walletDoorsSection {
                walletDoor(.nodes)
            }
        }
    }

    /// One kind of flagged transfer under its own name (it was one "Worth a
    /// look" group, §947). **Each row is ONE transfer and opens its own sheet
    /// (prd §1377)**, which says what it is in its box; the pile it opened
    /// (`.flagged`) repeated the section's name over "Nothing to do".
    ///
    /// **FIVE ROWS, THEN ONE DOOR (prd §1408, user: "my list of 'fake
    /// transfers' shows tons, it should show 5 and then 'see more'").** A
    /// spammed wallet holds hundreds of these; the section shows Home's cap
    /// (`walletHomeCap`) and ends in the one More row (`DSMoreRow`, §1386):
    /// "See all N" opens the rest in place, "Show fewer" folds it back.
    @ViewBuilder
    func walletFlaggedSection(_ kind: WalletWarning.Kind, anchor: SecurityAnchor,
                              word: String) -> some View {
        let things = walletLive.flagged.live.filter { thing in
            kind.securityFlag.map { thing.hasSecurityFlag($0) } ?? false
        }
        if !things.isEmpty {
            let open = walletSecurityOpen(anchor)
            let shown = open ? things : Array(things.prefix(Self.walletHomeCap))
            walletCard(word, glyph: kind.glyph, anchor: anchor.id) {
                // One list row each, at the Wallet's pitch (prd §1482).
                ForEach(shown.keyed) { row in
                    if let thing = row.live {
                        let words = Self.flaggedRowWords(thing, kind: kind)
                        let seen = ThreatsSeen.shared.contains(thing.id)
                        // Every threat's glyph is red (prd §1463), fake transfers
                        // too, until it is seen: then grey, and out of Home's
                        // count (prd §1587).
                        needsYouRow(glyph: kind.glyph, critical: !seen,
                                    title: words.title, line: seen ? [words.line, String(localized: "Seen")].joined(separator: " · ") : words.line) {
                            ThreatsSeen.shared.mark(thing.id)
                            feedSheet = .thing(thing, walk: .none)
                        }
                        .contextMenu {
                            if !seen {
                                Button {
                                    withAnimation(DS.Motion.standard) { ThreatsSeen.shared.mark(thing.id) }
                                    DSHaptic.selection()
                                } label: { Label("Mark as seen", systemImage: "eye") }
                            }
                        }
                        .walletListRow()
                    }
                }
                walletSecurityDoor(anchor, total: things.count)
            }
        }
    }

    /// **EVERY SECURITY SECTION SHOWS FIVE ROWS, THEN ONE DOOR (prd §1408,
    /// user: "approvals signatures and delegations also should be capped").**
    /// The fold is Home's set (`walletOpenSections`), keyed by the section.
    func walletSecurityOpen(_ anchor: SecurityAnchor) -> Bool {
        walletOpenSections.contains("security.\(anchor.rawValue)")
    }

    func walletSecurityToggle(_ anchor: SecurityAnchor) {
        let key = "security.\(anchor.rawValue)"
        withAnimation(DS.Motion.standard) {
            if walletOpenSections.contains(key) { walletOpenSections.remove(key) }
            else { walletOpenSections.insert(key) }
        }
    }

    /// "See all N" under a capped section, "Show fewer" once it is open; no
    /// door when five is everything (`DSMoreRow`, §1386).
    @ViewBuilder
    func walletSecurityDoor(_ anchor: SecurityAnchor, total: Int) -> some View {
        if total > Self.walletHomeCap {
            let open = walletSecurityOpen(anchor)
            DSMoreRow(title: open ? Text("Show fewer")
                                  : Text(verbatim: String(localized: "See all \(total)")),
                      opens: !open) { walletSecurityToggle(anchor) }
            .walletListRow()
        }
    }

    /// A flagged row's words: the verdict, then what it moved and when.
    static func flaggedRowWords(_ thing: Thing, kind: WalletWarning.Kind) -> (title: String, line: String) {
        let day = FeedScreen.dayWord(thing.capturedAt)
        let amount = WalletValue.transferAmount(thing)
        switch kind {
        case .poisoning:
            let copy = thing.counterpartyAddress.map(WalletStore.shortAddress) ?? ""
            return (String(localized: "A copy of \(copy)"),
                    [amount.map { String(localized: "Sent you \($0)") }, day].compactMap { $0 }.joined(separator: " · "))
        case .spoofedSymbol:
            let verdict = WalletSafety.spoofVerdict(for: thing)
            let symbol = verdict?.symbol ?? ""
            let title = verdict?.impersonating.map { String(localized: "\(symbol) isn't \($0)") }
                ?? String(localized: "\(symbol), a look-alike token")
            let moved = SwapStage(thing).map { String(localized: "Got \($0.inAmount)") } ?? amount
            return (title, [moved, day].compactMap { $0 }.joined(separator: " · "))
        default:
            return (amount ?? WalletValue.title(thing),
                    String(localized: "You didn't send this · \(day)"))
        }
    }
}

/// Grants this phone just took back (prd §1442l). A public node a block
/// behind still answers the old allowance, so the re-read after a revoke drew
/// the grant again with a live Revoke (measured on Base, 2026-10-20). Held two
/// minutes, by when every node agrees.
@MainActor
enum JustRevoked {
    private static var at: [UUID: Date] = [:]
    static func mark(_ ids: [UUID]) { for id in ids { at[id] = .now } }
    static func contains(_ id: UUID) -> Bool {
        at[id].map { Date.now.timeIntervalSince($0) < 120 } ?? false
    }
}

extension WalletLiveState {
    @MainActor
    mutating func dropJustRevoked() {
        activeApprovals.removeAll { JustRevoked.contains($0.id) }
        exposure.priced.removeAll { JustRevoked.contains($0.thingID) }
        exposure.unpriced.removeAll { JustRevoked.contains($0.thingID) }
    }
}

extension FeedScreen {
    // MARK: - Revoke (prd §1437)

    /// The grants your own account can take back here: its own, on a network
    /// it acts on (Base, Ethereum). Every other grant keeps its prepare card.
    var walletRevocable: [UUID: Thing] {
        guard let account = YourAccountDemo.shownAddress else { return [:] }
        var out: [UUID: Thing] = [:]
        for thing in walletLive.activeApprovals where thing.isLive
            && WalletWatch.sameAddress(thing.walletAddress ?? "", account)
            && YourAccountOp.network(appName: Self.approvalNetwork(thing)) != nil {
            out[thing.id] = thing
        }
        return out
    }

    /// "base-mainnet" off `wallet:approval:<network>:<tx>:<log>`.
    static func approvalNetwork(_ thing: Thing) -> String {
        let parts = (thing.sourceRef ?? "").split(separator: ":")
        return parts.count == 5 ? String(parts[2]) : ""
    }

    /// Take the grants back: each re-read live first (one gone already is
    /// skipped), then one operation a network, signed by this iPhone. The
    /// calls are the prepare card's own bytes (`WalletPrepare.Check`).
    func walletRevoke(_ ids: [UUID]) {
        guard walletRevoking == nil else { return }
        let things = ids.compactMap { walletRevocable[$0] }
        guard !things.isEmpty else { return }
        let inFlight = Set(things.map(\.id))
        walletRevoking = (inFlight, String(localized: "Preparing…"))
        Task {
            do {
                var networks: [YourAccountOp.Network] = []
                var revokes: [Int: [(to: String, data: String)]] = [:]
                var names: [Int: [String]] = [:]
                var ids: [Int: [UUID]] = [:]
                for thing in things {
                    guard let check = await WalletPrepare.check(for: thing) else {
                        throw YourAccountChain.Failure(message: String(localized: "That grant could not be read"))
                    }
                    guard check.active, let to = check.revokeTo, let data = check.revokeData,
                          let net = YourAccountOp.network(appName: check.network ?? "") else { continue }
                    if !networks.contains(net) { networks.append(net) }
                    revokes[net.chainId, default: []].append((to, data))
                    ids[net.chainId, default: []].append(thing.id)
                    names[net.chainId, default: []].append(walletLive.exposure.all.first { $0.thingID == thing.id }?.spender ?? thing.title)
                }
                var landed: [String] = []
                for net in networks {
                    let who = names[net.chainId] ?? []
                    let reason = who.count == 1
                        ? String(localized: "Revoke \(who[0])'s access")
                        : String(localized: "Revoke \(who.count) approvals on \(net.name)")
                    let sent = try await YourAccountChain.revoke(revokes[net.chainId] ?? [], on: net, reason: reason) { s in
                        await MainActor.run { walletRevoking = (inFlight, Self.stageWord(s)) }
                    }
                    switch sent.outcome {
                    case .landed:
                        landed.append(net.name)
                        JustRevoked.mark(ids[net.chainId] ?? [])
                    case .pending:
                        chrome.flash(String(localized: "Sent, and not yet seen on \(net.name). Check before sending again"), seconds: 6)
                    case .dryRun: break
                    }
                }
                walletRevoking = nil
                if !landed.isEmpty {
                    chrome.flash(String(localized: "Revoked on \(landed.formatted(.list(type: .and)))"), tone: .success, seconds: 4)
                } else if networks.isEmpty {
                    chrome.flash(String(localized: "That grant is no longer here."))
                }
                // What landed leaves the list now; the live re-read confirms
                // the rest, and cannot draw a revoked grant back (§1442l).
                withAnimation(DS.Motion.standard) { walletLive.dropJustRevoked() }
                loadWalletLive()
                chrome.refreshRooms()
            } catch let failure as YourAccountChain.Failure {
                walletRevoking = nil
                chrome.flash(failure.message, tone: .failure, seconds: 5)
            } catch {
                walletRevoking = nil
                chrome.flash(String(localized: "Not revoked"), tone: .failure)
            }
        }
    }

    static func stageWord(_ stage: YourAccountChain.Stage) -> String {
        switch stage {
        case .preparing: String(localized: "Preparing…")
        case .signing: String(localized: "Confirm with Face ID")
        case .sending: String(localized: "Sending…")
        case .landing: String(localized: "Waiting…")
        }
    }
}
