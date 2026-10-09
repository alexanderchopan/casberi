import Foundation
import Testing
@testable import Casberi

/// **A renamed app's records converge to ONE row under its current name**
/// (prd §1147): two "Frames Devnet" records drew as two rows in Settings ›
/// Apps after the seat became Hegotá Frames. That seat is deleted (prd
/// §1206), so the cases ride the live "Tokens" → "Markets" rename. Pure:
/// `BridgeStore.converged`,
/// never a store, whose write would replace the simulator's saved records.
struct BridgeConvergeTests {

    private static func app(_ name: String, _ status: BridgeApp.Status = .connected) -> BridgeApp {
        BridgeApp(id: "x", name: name, status: status, statusLine: "", can: [])
    }

    @Test func twinsUnderAnOldNameBecomeOneUnderTheNewName() throws {
        let out = try #require(BridgeStore.converged(
            [Self.app("Tokens"), Self.app("Tokens"), Self.app("GitHub")],
            current: Corpus.canonicalSource))
        #expect(out.map(\.name) == ["Markets", "GitHub"])
    }

    @Test func aLiveTwinWinsOverAPausedOne() throws {
        let out = try #require(BridgeStore.converged(
            [Self.app("Markets", .paused), Self.app("Tokens")],
            current: Corpus.canonicalSource))
        #expect(out.count == 1)
        #expect(out.first?.status == .connected)
    }

    @Test func nothingToDoIsNil() {
        #expect(BridgeStore.converged([Self.app("GitHub")], current: Corpus.canonicalSource)?.count == nil)
    }
}
