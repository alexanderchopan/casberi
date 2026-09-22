import Foundation
import SwiftData
import Testing
@testable import Casberi

/// **Which rows in an onchain card's room are SPENDS** (prd §868).
///
/// It lives here rather than in `scripts/wallet-rooms-selftest.sh` for the
/// reason CLAUDE.md gives: every `swiftc` harness in `scripts/` compiles
/// Foundation-only files against stubs, and this rule reads a `Thing`. The
/// harness owns `CardSpendRoom`'s arithmetic — the currencies never summed,
/// the comparison refused against an unobserved window — and it can only own
/// it because that file touches no model. This is the other half: WHAT gets
/// handed to that arithmetic, which is the half that went wrong.
///
/// The failure being guarded compiles, renders, and states wrong numbers with
/// total confidence. `EtherFiCash.source` is one seat covering two products
/// ("ether.fi — Your staked ETH, and the card"), so its room also holds
/// `EtherFiUnstake`'s withdrawal-queue rows and this seat's own credit-line
/// risk crossings. Both are `.link` rows with no price. Filtering that room by
/// source alone — which is exactly right for Gnosis Pay and MetaMask Card, and
/// is what a third copy of a sibling source would have said — puts them in
/// `CardSpendRoom.allTime` and in the footnote's count of "spends with no
/// readable amount": a sentence about money, on the screen where money is the
/// subject, describing rows that are not purchases (§83).
struct CardSpendSeatTests {

    private static func row(source: String, ref: String?) -> Thing {
        Thing(kind: .transaction, title: "t", content: "c",
              source: source, capturedAt: .now, sourceRef: ref)
    }

    // MARK: - The shared room

    @Test func etherFiSpendIsASpend() {
        let thing = Self.row(source: EtherFiCash.source,
                             ref: EtherFiCash.spendRefPrefix + "0xabc:3")
        #expect(CardSpendSeat.isSpend(thing, seat: EtherFiCash.source))
    }

    /// The whole reason this type exists.
    @Test func etherFiUnstakeRowIsNotASpend() {
        let thing = Self.row(source: EtherFiCash.source, ref: "etherfi:unstake:0xabc")
        #expect(!CardSpendSeat.isSpend(thing, seat: EtherFiCash.source))
    }

    /// `etherficash:risk:` shares this seat's OWN namespace up to the colon, so
    /// a prefix written one segment short (`"etherficash:"`) would accept it —
    /// and a credit-line warning would be counted as an unpriced purchase.
    @Test func etherFiRiskRowIsNotASpend() {
        let thing = Self.row(source: EtherFiCash.source, ref: "etherficash:risk:0xabc:170")
        #expect(!CardSpendSeat.isSpend(thing, seat: EtherFiCash.source))
    }

    @Test func etherFiRowWithNoRefIsNotASpend() {
        let thing = Self.row(source: EtherFiCash.source, ref: nil)
        #expect(!CardSpendSeat.isSpend(thing, seat: EtherFiCash.source))
    }

    /// The demo pours this room too, and a seeded row that the head declines
    /// would leave the one surface anyone can see without an account showing a
    /// card seat with no card (§368's miss, which had left `demo:etherfi:<n>`
    /// matching neither this prefix nor `PurchaseStage.purchaseRefs`).
    @Test func theDemoSeedsRealSpendRefs() {
        let thing = Self.row(source: EtherFiCash.source, ref: "etherficash:spend:demo0")
        #expect(CardSpendSeat.isSpend(thing, seat: EtherFiCash.source))
    }

    // MARK: - The rooms that hold only the card

    /// Stated rather than assumed: these two seats own their rooms outright,
    /// so every row is a spend whatever its ref looks like.
    @Test func aSeatThatOwnsItsRoomAcceptsEveryRow() {
        for seat in [GnosisPayBridge.sourceName, MetaMaskCardBridge.source] {
            #expect(CardSpendSeat.isSpend(Self.row(source: seat, ref: "anything:1"),
                                          seat: seat))
            #expect(CardSpendSeat.isSpend(Self.row(source: seat, ref: nil), seat: seat))
        }
    }

    // MARK: - No rule reaches across rooms

    /// The source test runs FIRST for every seat. Without it the ether.fi arm
    /// would be skipped for a Gnosis Pay row handed to the ether.fi seat and
    /// the row would be accepted, which is how one card's head starts totalling
    /// another card's money.
    @Test func aRowFromAnotherRoomIsNeverASpend() {
        let gnosis = Self.row(source: GnosisPayBridge.sourceName, ref: "gnosispay:spend:1")
        #expect(!CardSpendSeat.isSpend(gnosis, seat: EtherFiCash.source))
        #expect(!CardSpendSeat.isSpend(gnosis, seat: MetaMaskCardBridge.source))

        let etherfi = Self.row(source: EtherFiCash.source,
                               ref: EtherFiCash.spendRefPrefix + "0xabc:1")
        #expect(!CardSpendSeat.isSpend(etherfi, seat: GnosisPayBridge.sourceName))
    }

    // MARK: - The head reads what the rule accepts

    /// `compose` filters `things.live` FIRST (liveness corollary 4), and
    /// `isLive` is `modelContext != nil && !isDeleted` — so a row that was
    /// never inserted is not live, and a test built on bare `Thing()`s would
    /// hand `compose` an EMPTY array, watch it return nil, and pass while
    /// proving nothing. Everything below is inserted into a real in-memory
    /// store for exactly that reason.
    @MainActor
    private static func inserted(_ rows: [Thing]) throws -> (ModelContainer, [Thing]) {
        let container = try ModelContainer(
            for: Thing.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        for row in rows { container.mainContext.insert(row) }
        return (container, rows)
    }

    /// The rule and its one caller, together: a room of unstake rows composes
    /// NO head, rather than a head claiming spends it cannot price.
    @Test @MainActor func aRoomOfUnstakeRowsComposesNoHead() throws {
        let (container, rows) = try Self.inserted([
            Self.row(source: EtherFiCash.source, ref: "etherfi:unstake:a"),
            Self.row(source: EtherFiCash.source, ref: "etherfi:unstake:b"),
        ])
        // Held so the container outlives the compose — a released container
        // deletes its context and every row with it.
        _ = container
        // Computed OUTSIDE the macro: `allSatisfy(\.isLive)` passes a key path
        // where a `throws` closure is expected, so `#expect`'s expansion wraps
        // a call it must then mark `try` — and the test target stops compiling.
        let allLive = rows.allSatisfy { $0.isLive }
        #expect(allLive)
        #expect(EtherFiCashRoomSource.compose(things: rows) == nil)
    }

    /// And the money that IS a spend reaches the head — the same rows, with one
    /// real purchase added, compose a head whose `allTime` counts ONLY it.
    @Test @MainActor func onlySpendsAreCounted() throws {
        let spend = Self.row(source: EtherFiCash.source,
                             ref: EtherFiCash.spendRefPrefix + "0xabc:1")
        spend.priceValue = 4.20
        spend.priceCurrency = "USD"
        let (container, rows) = try Self.inserted([
            spend,
            Self.row(source: EtherFiCash.source, ref: "etherfi:unstake:a"),
            Self.row(source: EtherFiCash.source, ref: "etherficash:risk:a:1"),
        ])
        _ = container
        let room = try #require(EtherFiCashRoomSource.compose(things: rows))
        #expect(room.allTime == 1)
        // The footnote is the surface that would have lied: two non-purchases
        // counted as "2 spends have no readable amount" under a $4.20 total.
        #expect(room.unpriced == 0)
        #expect(room.lead?.total == 4.20)
    }
}
