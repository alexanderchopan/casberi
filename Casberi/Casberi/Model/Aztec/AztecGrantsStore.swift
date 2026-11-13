import Foundation
import SwiftUI

/// The authorizations approved in Casberi's browser, kept on this phone
/// (prd §1762), and the two things done with them: read which still stand,
/// and take one back.
@MainActor
@Observable
final class AztecGrantsStore {
    static let shared = AztecGrantsStore()

    private(set) var grants: [AztecGrantsShape.Grant]
    /// The hash being taken back, while its transaction is sent.
    private(set) var takingBack: String?

    private static let key = "aztec.grants.v1"

    #if DEBUG
    private static var sampled: Bool {
        guard let raw = UserDefaults.standard.string(forKey: "aztecGrantsSample") else { return false }
        return raw == "YES" || raw == "1" || raw == "one"
    }
    #endif

    private init() {
        grants = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([AztecGrantsShape.Grant].self, from: $0) } ?? []
        #if DEBUG
        // `-aztecGrantsSample YES|one`: two authorizations (or the first
        // alone) on a simulator, whose account cannot pay for one (prd §1762).
        if Self.sampled {
            grants = [
                .init(hash: "0x" + String(repeating: "1a", count: 32), host: "app.ravenhouse.xyz",
                      caller: "0x" + String(repeating: "0", count: 60) + "63f2", contract: "0x" + String(repeating: "0", count: 60) + "5e83",
                      method: "set_authorized", args: ["message hash ...6fe1", "authorize yes"], transaction: "0x00", at: .now),
                .init(hash: "0x" + String(repeating: "2b", count: 32), host: "nemi.fi",
                      caller: "0x" + String(repeating: "0", count: 60) + "9c1d", contract: "0x" + String(repeating: "0", count: 60) + "4f38",
                      method: "transfer_public_to_public", args: ["amount 5 USDC"], transaction: "0x00", at: .now),
            ]
            if UserDefaults.standard.string(forKey: "aztecGrantsSample") == "one" { grants = Array(grants.prefix(1)) }
        }
        #endif
    }

    /// The engine's word that an approved authorization was sent.
    func add(_ body: [String: Any]) {
        guard let hash = body["hash"] as? String, let caller = body["caller"] as? String,
              let contract = body["contract"] as? String, let method = body["method"] as? String else { return }
        let host = (body["origin"] as? String).flatMap { URL(string: $0)?.host(percentEncoded: false) } ?? ""
        grants = AztecGrantsShape.added(grants, .init(hash: hash, host: host, caller: caller, contract: contract, method: method,
                                                    args: body["args"] as? [String] ?? [],
                                                    transaction: body["tx"] as? String ?? "", at: .now))
        save()
    }

    /// Which still stand in Aztec's registry: the rest were used or taken
    /// back, and leave the list. A read; never in the demo.
    func refresh() async {
        guard !grants.isEmpty, !DemoMode.isActive, AztecProver.isAvailable else { return }
        #if DEBUG
        if Self.sampled { return }
        #endif
        guard let data = try? JSONEncoder().encode(grants.map(\.hash)),
              let answer = try? await AztecEngine.shared.call("grantsStanding", [String(decoding: data, as: UTF8.self)]) as? [String: Any] else { return }
        let next = AztecGrantsShape.kept(grants, standing: answer["standing"] as? [String] ?? [],
                                         unread: answer["unread"] as? [String] ?? [], now: .now)
        if next != grants { grants = next; save() }
    }

    /// Take one back: Face ID, the co-signer, then the registry write with
    /// "no", the account's own transaction (prd §1762). Throws in words.
    func takeBack(_ grant: AztecGrantsShape.Grant) async throws {
        guard takingBack == nil else { return }
        takingBack = grant.hash
        defer { takingBack = nil }
        try await PrivateRootKey.unlock(reason: String(localized: "Revoke this authorization"))
        try await AztecCoSign.approve(String(localized: "Revoke \(AztecGrantsShape.tail(grant.caller))'s authorization to call \(grant.method)"))
        let out = try await AztecEngine.shared.call("revokeGrant", [grant.hash, AztecGas.unminted]) as? [String: Any]
        AztecGas.spent(by: out)
        grants = AztecGrantsShape.removed(grants, hash: grant.hash)
        save()
    }

    private func save() {
        #if DEBUG
        if Self.sampled { return }
        #endif
        UserDefaults.standard.set(try? JSONEncoder().encode(grants), forKey: Self.key)
    }
}
