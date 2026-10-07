import Foundation
import Testing
@testable import Casberi

/// **A renamed app's records converge to ONE row under its current name**
/// (prd §1147): two "Frames Devnet" records drew as two rows in Settings ›
/// Apps after the seat became Hegotá Frames. Pure: `BridgeStore.converged`,
/// never a store, whose write would replace the simulator's saved records.
struct BridgeConvergeTests {

    private static func app(_ name: String, _ status: BridgeApp.Status = .connected) -> BridgeApp {
        BridgeApp(id: "x", name: name, status: status, statusLine: "", can: [])
    }

    @Test func twinsUnderAnOldNameBecomeOneUnderTheNewName() throws {
        let out = try #require(BridgeStore.converged(
            [Self.app("Frames Devnet"), Self.app("Frames Devnet"), Self.app("GitHub")],
            current: Corpus.canonicalSource))
        #expect(out.map(\.name) == ["Hegotá Frames", "GitHub"])
    }

    @Test func aLiveTwinWinsOverAPausedOne() throws {
        let out = try #require(BridgeStore.converged(
            [Self.app("Hegotá Frames", .paused), Self.app("Frames Devnet")],
            current: Corpus.canonicalSource))
        #expect(out.count == 1)
        #expect(out.first?.status == .connected)
    }

    @Test func nothingToDoIsNil() {
        #expect(BridgeStore.converged([Self.app("GitHub")], current: Corpus.canonicalSource)?.count == nil)
    }
}
