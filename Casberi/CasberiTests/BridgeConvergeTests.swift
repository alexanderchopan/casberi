import Foundation
import Testing
@testable import Casberi

/// **A renamed app's records converge to ONE row under its current name**
/// (prd §1147): two "Frames Devnet" records drew as two rows in Settings ›
/// Apps after the seat became Hegotá Frames.
@MainActor
struct BridgeConvergeTests {

    @Test func twinsUnderAnOldNameBecomeOneUnderTheNewName() {
        let store = BridgeStore(bridges: [
            BridgeApp(id: "frames", name: "Frames Devnet", status: .connected, statusLine: "A", can: []),
            BridgeApp(id: "frames", name: "Frames Devnet", status: .connected, statusLine: "B", can: []),
            BridgeApp(id: "github", name: "GitHub", status: .connected, statusLine: "", can: []),
        ])
        store.convergeNames(Corpus.canonicalSource)
        let names = store.bridges.map(\.name)
        #expect(names.filter { $0 == "Hegotá Frames" }.count == 1)
        #expect(!names.contains("Frames Devnet"))
        #expect(names.contains("GitHub"))
        #expect(store.bridges.count == 2)
    }

    @Test func aLiveTwinWinsOverAPausedOne() {
        let store = BridgeStore(bridges: [
            BridgeApp(id: "frames", name: "Hegotá Frames", status: .paused, statusLine: "", can: []),
            BridgeApp(id: "frames", name: "Frames Devnet", status: .connected, statusLine: "", can: []),
        ])
        store.convergeNames(Corpus.canonicalSource)
        #expect(store.bridges.count == 1)
        #expect(store.bridges.first?.status == .connected)
    }

    @Test func nothingToDoLeavesTheStoreAlone() {
        let store = BridgeStore(bridges: [
            BridgeApp(id: "github", name: "GitHub", status: .connected, statusLine: "", can: []),
        ])
        store.convergeNames(Corpus.canonicalSource)
        #expect(store.bridges.map(\.name) == ["GitHub"])
    }
}
