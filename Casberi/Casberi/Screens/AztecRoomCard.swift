import SwiftUI

extension AztecSection: DSSectionScope {}

/// The Aztec room's figure — one slot per scope, the testnets' `DSRoomSlot`
/// (Logos' `LogosRoomFigure`).
///
/// - **Home** is the network: the proving lag as a line this phone sampled
///   (`RoomHomeCrown`, the devnets' crown with plain numbers), captioned with
///   the block it is at. With fewer than two samples, the block and the lag
///   in words.
/// - **Holdings** is the PUBLIC Fee Juice of the accounts followed, and a
///   line saying the private half is not readable.
/// - **Node** is the sequencers: a stage word, the stake and the schedule,
///   then each epoch of committee duty as a strip (one sequencer in scope).
struct AztecRoomFigure: View {
    let head: AztecRoom.Head
    let section: AztecSection

    var body: some View {
        DSRoomSlot(headline: nil, reservesHeadline: false) {
            if drawsEmptyState, let words = section.emptyBody {
                DSEmptyState(headline: section.emptyHeadline.map { Text($0) },
                             words: Text(words), scale: .room(section.skeleton))
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s2) { reading }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var drawsEmptyState: Bool {
        switch section {
        case .home:     return false
        case .holdings: return head.accounts.isEmpty
        case .node:     return head.followed == 0
        }
    }

    @ViewBuilder private var reading: some View {
        switch section {
        case .home:     network
        case .holdings: holdings
        case .node:     node
        }
    }

    // MARK: - Home

    private static let plain: (Double) -> String = { AztecWire.grouped(Int($0.rounded())) }

    @ViewBuilder private var network: some View {
        if let net = head.network {
            if head.lagSeries.count > 1 {
                RoomHomeCrown(samples: head.lagSeries,
                              caption: String(localized: "Blocks waiting for a proof · at block \(AztecWire.grouped(net.tips.proposed))"),
                              format: Self.plain, exactFormat: Self.plain, changeFormat: Self.plain,
                              box: DSRoomChassis.figureSlot)
            } else {
                Text(String(localized: "Block \(AztecWire.grouped(net.tips.proposed))"))
                    .dsText(.heading24)
                    .foregroundStyle(DS.textPrimary)
                note(Self.proving(net.tips))
            }
            if let line = Self.traffic(net) { note(line) }
        } else if !head.hasRead {
            title(String(localized: "Reading the testnet…"))
        } else {
            title(String(localized: "Couldn't reach the testnet."))
        }
    }

    /// "Proven 7 blocks behind", or "Proven to the tip". nil proven says
    /// nothing about proving rather than a guess.
    static func proving(_ tips: AztecWire.Tips) -> String {
        guard let lag = tips.provenLag else { return String(localized: "Proving not reported") }
        switch lag {
        case 0:  return String(localized: "Proven to the tip")
        case 1:  return String(localized: "Proven 1 block behind")
        default: return String(localized: "Proven \(AztecWire.grouped(lag)) blocks behind")
        }
    }

    /// Waiting transactions, when any — a quiet testnet's zero says nothing.
    static func traffic(_ net: AztecStore.Network) -> String? {
        guard let pending = net.pending, pending > 0 else { return nil }
        return pending == 1 ? String(localized: "1 transaction waiting")
                            : String(localized: "\(pending) transactions waiting")
    }

    // MARK: - Holdings

    @ViewBuilder private var holdings: some View {
        let known = head.accounts.compactMap(\.feeJuice)
        if known.isEmpty {
            title(head.hasRead ? String(localized: "No public Fee Juice read") : String(localized: "Reading…"))
        } else {
            Text(String(localized: "\(AztecWire.tokens(known.reduce(0, +))) Fee Juice"))
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
            note(head.accounts.count == 1 ? String(localized: "Held publicly · test fees")
                                          : String(localized: "Held publicly by \(head.accounts.count) accounts · test fees"))
        }
        // The one honest limit, stated where the number is (§83).
        note(String(localized: "Private balances stay private to their owner."))
    }

    // MARK: - Node

    @ViewBuilder private var node: some View {
        if head.sequencers.isEmpty {
            title(head.unseen.isEmpty ? String(localized: "Reading your sequencer…")
                                      : String(localized: "Not seen by this node"))
        } else {
            let stopped = head.sequencers.filter(AztecWire.isStopped)
            Text(stopped.isEmpty ? String(localized: "Attesting")
                                 : stopped.count == head.sequencers.count
                                    ? String(localized: "Stopped attesting")
                                    : String(localized: "\(stopped.count) stopped attesting"))
                .dsText(.heading24)
                .foregroundStyle(stopped.isEmpty ? DS.textPrimary : DS.attentionInk)
            if head.sequencers.count == 1, let s = head.sequencers.first {
                note(AztecWire.line(s))
                if let line = Self.stakeLine(head.stakes[s.address], symbol: head.stakeSymbol) { note(line) }
                if let line = Self.dutyLine(head.duties[s.address]) { note(line) }
                if !s.recentEpochs.isEmpty {
                    AztecEpochStrip(missed: s.recentEpochs)
                        .padding(.top, DS.Space.s2)
                }
            } else {
                note(String(localized: "\(head.sequencers.count) sequencers followed"))
                if let line = Self.totalStake(head, symbol: head.stakeSymbol) { note(line) }
            }
            if !head.unseen.isEmpty {
                note(head.unseen.count == 1 ? String(localized: "1 not seen by this node")
                                            : String(localized: "\(head.unseen.count) not seen by this node"))
            }
        }
    }

    /// "Validating · 200,000 STK staked · earned 1,200", from Ethereum.
    static func stakeLine(_ stake: AztecWire.Stake?, symbol: String?) -> String? {
        guard let stake else { return nil }
        let unit = symbol.map { " \($0)" } ?? ""
        var parts = [stake.status.word]
        if stake.staked > 0 { parts.append(String(localized: "\(AztecWire.tokens(stake.staked))\(unit) staked")) }
        if let earned = stake.rewards, earned > 0 { parts.append(String(localized: "earned \(AztecWire.tokens(earned))\(unit)")) }
        return parts.joined(separator: " · ")
    }

    /// "Proposes in 23 min", else whether it sits on this epoch's committee.
    static func dutyLine(_ duty: AztecStore.Duty?, now: Date = .now) -> String? {
        guard let duty else { return nil }
        if let next = duty.nextProposal, next > now {
            let minutes = max(1, Int(next.timeIntervalSince(now) / 60))
            return minutes < 90 ? String(localized: "Proposes in \(minutes) min")
                                : String(localized: "Proposes in \(minutes / 60) h")
        }
        return duty.onCommittee ? String(localized: "On this epoch's committee")
                                : String(localized: "Not on this epoch's committee")
    }

    static func totalStake(_ head: AztecRoom.Head, symbol: String?) -> String? {
        let amounts = head.sequencers.compactMap { head.stakes[$0.address]?.staked }
        guard !amounts.isEmpty else { return nil }
        return String(localized: "\(AztecWire.tokens(amounts.reduce(0, +)))\(symbol.map { " \($0)" } ?? "") staked")
    }

    @ViewBuilder private func title(_ text: String) -> some View {
        Text(text)
            .dsText(.heading24)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.subhead12)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A sequencer's recent committee epochs, oldest first, one cell each: a
/// clean epoch in the primary ink at low weight, an epoch with a miss in the
/// attention ink. No axis and no labels: the caption above says what it is.
struct AztecEpochStrip: View {
    let missed: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: 3) {
                ForEach(Array(missed.enumerated()), id: \.offset) { _, n in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(n > 0 ? DS.attentionInk : DS.textPrimary.opacity(0.35))
                        .frame(maxWidth: 10)
                        .frame(height: 14)
                }
            }
            Text(String(localized: "Last \(missed.count) epochs on the committee · \(missed.filter { $0 > 0 }.count) with a miss"))
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Last \(missed.count) epochs on the committee, \(missed.filter { $0 > 0 }.count) with a miss")))
    }
}
