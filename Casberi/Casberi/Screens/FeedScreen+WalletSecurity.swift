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
            if walletOnPrivateAccount {
                // The private account's own page (prd §1786): its address
                // in the box above, its two moves here.
                walletDoorsSection { walletPrivateAccountRows() }
            } else {
                // **FOLLOWING, A LINE (prd §1937):** the wallets you follow,
                // or the verb with none yet.
                Section {
                    let followed = walletFollowingSlots
                    AccountLine(label: String(localized: "Following"),
                                value: followed.isEmpty ? String(localized: "Follow an account")
                                    : String(localized: "\(followed.count) accounts"),
                                ink: followed.isEmpty ? DS.pickInk : DS.textPrimary,
                                action: {
                                    if followed.isEmpty { feedSheet = .walletFollow }
                                    else { chrome.walletSection = .following }
                                })
                        .walletListRow()
                }
                // **SECURITY AND MONEY, ON PLATES (prd §1937, user picked H):**
                // `MoveSecurity` draws both; Money's Public takes the Safes
                // you hold a key to, its Private the three private places.
                // Risks is its own page and stands on Home (user: "risks is
                // its own page").
                Section {
                    MoveSecurity(account: account, openGoal: { feedSheet = .savingsGoal },
                                 publicLines: AnyView(WalletUnsignedSection(part: .lines, onOpenSafe: walletOpenSafe,
                                                                            queueKey: Self.safeQueueKey(visible))),
                                 privateLines: walletHasPrivatePlaces ? AnyView(walletPrivatePlaces()) : nil)
                        .walletStackRow()
                        // The nudge's landing (`ShellChrome.openYourAccount`, prd §1480).
                        .task(id: chrome.walletScrollRequest) {
                            guard chrome.walletScrollRequest == SecurityAnchor.account.id else { return }
                            try? await Task.sleep(for: .milliseconds(300))
                            cardScrollTarget = SecurityAnchor.account.id
                            chrome.walletScrollRequest = nil
                        }
                }
                .id(SecurityAnchor.account.id)
                .environment(\.feedSectionPanelFilled, false)
                // ACCOUNT AND SETTINGS ARE ONE PAGE (prd §1807): Casberi's own
                // settings close the page, on the third plate, App (§1937).
                Section {
                    AccountPlate(name: String(localized: "App"), glyph: "gearshape") {
                        // ACTIVITY'S ORDER IS A SETTING (prd §1807).
                        AccountLine(label: String(localized: "Activity"), value: String(localized: "Section order"),
                                    action: { feedSheet = .feedOrder })
                        SettingsRows(style: .lines, openNodes: { feedSheet = .ownNodes })
                    }
                    // The plates' one gap, as Security's from Money's.
                    .padding(.top, DS.Space.s4)
                    .walletStackRow()
                    SettingsRows(style: .colophon)
                        .walletStackRow()
                }
                .id(ShellChrome.settingsAnchor)
                .environment(\.feedSectionPanelFilled, false)
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
        // **A SEEN FINDING LEAVES (prd §1919, user: "seen risks need to leave
        // the page").** A section lists what you have not seen, and a row
        // just put away while it takes its stamp (`walletThreatsLeaving`).
        let leaving = walletThreatsLeaving
        let things = walletLive.flagged.live.filter { thing in
            (kind.securityFlag.map { thing.hasSecurityFlag($0) } ?? false)
                && (!ThreatsSeen.shared.contains(thing.id) || leaving[thing.id] != nil)
        }
        if !things.isEmpty {
            let open = walletSecurityOpen(anchor)
            let shown = open ? things : Array(things.prefix(Self.walletRisksCap))
            walletCard(word, glyph: kind.glyph, anchor: anchor.id) {
                // One list row each, at the Wallet's pitch (prd §1482).
                ForEach(shown.keyed) { row in
                    if let thing = row.live {
                        let words = Self.flaggedRowWords(thing, kind: kind)
                        let stamp = leaving[thing.id]
                        // Every threat's glyph is red (prd §1463), fake transfers
                        // too, until it is seen: then grey under its stamp.
                        needsYouRow(glyph: kind.glyph, critical: stamp == nil,
                                    title: words.title, line: words.line,
                                    leadTint: stamp == nil ? nil : DS.textTertiary) {
                            walletSeeThreat(thing, opens: true)
                        }
                        .overlay(alignment: .trailing) {
                            if let stamp { DSSeenStamp(order: stamp) }
                        }
                        .contextMenu {
                            if stamp == nil {
                                Button { walletSeeThreat(thing, opens: false) } label: {
                                    Label("Mark as seen", systemImage: "eye")
                                }
                            }
                        }
                        .walletListRow()
                    }
                }
                walletSecurityDoor(anchor, total: things.count, cap: Self.walletRisksCap)
            }
        }
    }

    /// **THREE FINDINGS A KIND, THEN ONE DOOR (prd §1919, user: "perhaps they
    /// only show 3 per category"; §1408's five stays on Permissions).**
    static let walletRisksCap = 3
    static let walletSeenThreatsKey = "security.seen"

    /// The three kinds Risks lists, in the page's order.
    static let walletThreatKinds: [(kind: WalletWarning.Kind, anchor: SecurityAnchor)] = [
        (.poisoning, .poisoning), (.spoofedSymbol, .fakeTokens), (.fakeTransfer, .fakeTransfers),
    ]

    static func walletThreatKind(_ thing: Thing) -> WalletWarning.Kind {
        walletThreatKinds.first { pair in
            pair.kind.securityFlag.map { thing.hasSecurityFlag($0) } ?? false
        }?.kind ?? .fakeTransfer
    }

    /// One finding put away: stamped at once, gone when you are back from its
    /// sheet, or a beat after a hold's Mark as seen.
    func walletSeeThreat(_ thing: Thing, opens: Bool) {
        if !ThreatsSeen.shared.contains(thing.id) {
            walletThreatsLeaving[thing.id] = 0
            ThreatsSeen.shared.mark(thing.id)
        }
        if opens {
            feedSheet = .thing(thing, walk: .none)
        } else {
            walletReleaseStampedThreats(after: 0.6)
        }
    }

    /// The stamped rows leave together.
    func walletReleaseStampedThreats(after seconds: Double = 0.45, then: (() -> Void)? = nil) {
        guard !walletThreatsLeaving.isEmpty else { return }
        let ids = Array(walletThreatsLeaving.keys)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(DS.Motion.standard) {
                for id in ids { walletThreatsLeaving[id] = nil }
            }
            then?()
        }
    }

    /// **MARK ALL AS SEEN, FELT (prd §1919).** The rows on screen take their
    /// stamps top to bottom, a tick each; then every finding leaves, the page
    /// says All seen, and the flash carries the one success beat and Undo.
    func walletMarkAllThreatsSeen(_ unseen: [Thing]) {
        let ids = unseen.map(\.id)
        guard !ids.isEmpty else { return }
        var order: [UUID: Int] = [:]
        var drawn = 0
        for pair in Self.walletThreatKinds {
            let rows = unseen.filter { thing in pair.kind.securityFlag.map { thing.hasSecurityFlag($0) } ?? false }
            let shown = walletSecurityOpen(pair.anchor) ? rows : Array(rows.prefix(Self.walletRisksCap))
            for thing in shown where order[thing.id] == nil {
                order[thing.id] = drawn
                drawn += 1
            }
        }
        // The ones behind a door are not drawn; they leave with the rest.
        for id in ids where order[id] == nil { order[id] = drawn }
        walletThreatsLeaving.merge(order) { _, new in new }
        ThreatsSeen.shared.markAll(ids)
        let run = Double(min(drawn, DSSeenStamp.longestRun)) * DSSeenStamp.beat + 0.48
        let chrome = chrome
        // The flash stands over the foot of the page, where All seen lands:
        // the row waits until the flash has gone, then takes its bounce.
        let flashSeconds = 4.0   // as every flash that offers Undo
        walletAllSeenHeld = true
        walletReleaseStampedThreats(after: run) {
            chrome.flash(String(localized: "\(ids.count) marked as seen"), tone: .success,
                         action: .init(label: String(localized: "Undo")) {
                             withAnimation(DS.Motion.standard) { ThreatsSeen.shared.unmark(ids) }
                         },
                         seconds: flashSeconds)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(flashSeconds + 0.3))
                withAnimation(DS.Motion.standard) { walletAllSeenHeld = false }
            }
        }
    }

    /// **WHERE THE SEEN ONES WENT (prd §1919).** One row at the foot of the
    /// findings, "Seen N"; it opens them in place, grey, and each still opens
    /// its sheet.
    @ViewBuilder
    func walletSeenThreatsSection(_ seen: [Thing]) -> some View {
        if !seen.isEmpty {
            let open = walletOpenSections.contains(Self.walletSeenThreatsKey)
            DSMoreRow(title: open ? Text("Hide seen")
                                  : Text(verbatim: String(localized: "Seen \(seen.count)")),
                      opens: !open) {
                withAnimation(DS.Motion.standard) {
                    if open { walletOpenSections.remove(Self.walletSeenThreatsKey) }
                    else { walletOpenSections.insert(Self.walletSeenThreatsKey) }
                }
            }
            .walletListRow()
            if open {
                ForEach(seen.keyed) { row in
                    if let thing = row.live {
                        let kind = Self.walletThreatKind(thing)
                        let words = Self.flaggedRowWords(thing, kind: kind)
                        needsYouRow(glyph: kind.glyph, critical: false,
                                    title: words.title, line: words.line,
                                    leadTint: DS.textTertiary) {
                            feedSheet = .thing(thing, walk: .none)
                        }
                        .walletListRow()
                    }
                }
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
    func walletSecurityDoor(_ anchor: SecurityAnchor, total: Int, cap: Int = FeedScreen.walletHomeCap) -> some View {
        if total > cap {
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
    /// What was taken back, as it read, for the empty page's Revoked list
    /// (prd §1633): the page only empties right after you revoke the last
    /// grant on it, so this phone's memory is enough.
    private static var taken: [Taken] = []
    struct Taken {
        let grant: WalletApprovalExposure.Grant
        /// The account it was granted from, so a page scoped to another
        /// account does not list it.
        let wallet: String
        let at: Date
    }
    static func mark(_ ids: [UUID], grants: [WalletApprovalExposure.Grant] = [], wallet: String = "") {
        for id in ids { at[id] = .now }
        for grant in grants where ids.contains(grant.thingID) {
            taken.removeAll { $0.grant.thingID == grant.thingID }
            taken.insert(Taken(grant: grant, wallet: wallet, at: .now), at: 0)
        }
    }
    static func contains(_ id: UUID) -> Bool {
        at[id].map { Date.now.timeIntervalSince($0) < 120 } ?? false
    }
    /// Today's, newest first, on `scope` (nil: every account).
    static func today(scope: String?) -> [Taken] {
        taken.filter {
            Calendar.current.isDateInToday($0.at)
                && (scope == nil || WalletWatch.sameAddress(scope ?? "", $0.wallet))
        }
    }
}

extension FeedScreen {
    // MARK: - Permissions' rows (prd §1633)

    /// The grants taken back today, once nothing is left (prd §1633): the
    /// empty pack draws its skeleton (§1677), and this says what went.
    var walletRevokedTodaySection: some View {
        walletCard(String(localized: "Revoked"), glyph: "checkmark.shield") {
            ForEach(JustRevoked.today(scope: chrome.walletScope), id: \.grant.thingID) { taken in
                HStack(spacing: DS.Space.s3) {
                    AssetMark(name: taken.grant.spender, size: DS.Face.list)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: taken.grant.spender)
                            .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                        (Text(verbatim: "\(taken.grant.symbol) · ").foregroundStyle(DS.textTertiary)
                            + Text("Revoked").foregroundStyle(DS.confirmInk))
                            .dsText(.subhead12).lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Text(taken.at, style: .time)
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
                .walletRowPitch()
                .accessibilityElement(children: .combine)
                .walletListRow()
            }
        }
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
                        JustRevoked.mark(ids[net.chainId] ?? [], grants: walletLive.exposure.all,
                                         wallet: YourAccountDemo.shownAddress ?? "")
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
        case .cosigning: String(localized: "Waiting for your Signer…")
        case .sending: String(localized: "Sending…")
        case .landing: String(localized: "Waiting…")
        }
    }
}
