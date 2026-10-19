import CryptoKit
import Foundation

// A no-funds check of the account's bytes against Base Sepolia, with a
// throwaway software P-256 key: the address, a gas estimate with a balance
// override, the module's SafeOp hash, and the chain's own verdict on the
// signature. The phone app runs the same code with its Secure Enclave key.
@main
struct Check {
    static func main() async {
        let net = Chain.baseSepolia
        let soft = P256.Signing.PrivateKey()
        let xy = [UInt8](soft.publicKey.rawRepresentation)
        let key = SafeAccount.Key(x: Array(xy[0..<32]), y: Array(xy[32..<64])) { digest in
            struct Pre: Digest {
                let d: Data
                static var byteCount: Int { 32 }
                func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try d.withUnsafeBytes(body) }
                func makeIterator() -> Array<UInt8>.Iterator { [UInt8](d).makeIterator() }
                var description: String { "" }
                static func == (a: Pre, b: Pre) -> Bool { a.d == b.d }
                func hash(into h: inout Hasher) { h.combine(d) }
            }
            let raw = [UInt8](try soft.signature(for: Pre(d: Data(digest))).rawRepresentation)
            return (Array(raw[0..<32]), SafeWebAuthn.lowS(Array(raw[32..<64])))
        }
        let next = P256.Signing.PrivateKey()
        let nxy = [UInt8](next.publicKey.rawRepresentation)
        let nextKey = SafeAccount.Key(x: Array(nxy[0..<32]), y: Array(nxy[32..<64])) { _ in throw Chain.RPCError(message: "unused") }
        do {
            for rotate in [false, true] {
                print("— \(rotate ? "send + rotate" : "plain send") —")
                let me = try await SafeAccount.address(net, key)
                let call = SafeAccount.sendCall(to: me, value: 1, rotateTo: rotate ? nextKey : nil)
                let prepared = try await SafeAccount.prepare(net, origin: key, callData: call) { print("  " + $0) }
                _ = try await SafeAccount.sign(net, prepared, with: key) { print("  " + $0) }
            }
        } catch {
            print("✗ \(error)")
            exit(1)
        }
    }
}
