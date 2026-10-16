import Foundation
import Testing
@testable import Casberi

/// **The curve half of a Fileverse read** (prd §1346).
///
/// `FileverseCrypto` takes the ECDH point as a closure so the shell harness can
/// compile it without libsecp256k1; this holds the app's closure,
/// `FileverseKey`, to the same vector (`scripts/fileverse-probe/
/// crypto-vectors.json`). The values are a TEST portal's, derived from the
/// vector Fileverse's own libraries wrote, never anybody's key.
///
/// A wrong point does not crash: every lock simply refuses, and the seat would
/// say a portal holds nothing it can open.
struct FileverseKeyTests {
    private static let scalar = Data(base64Encoded: "4EYRVYXIAl9oXqGf4PTtgTIIUzrJwAkaotKDg96Oi88=")!
    private static let publicKey = Data(base64Encoded: "A6gFV3K1UIaUbA1BG9w9pZek/7CH1KFxnWiS8I20jKQ5")!
    private static let ephemeral = Data(base64Encoded: "A5aEeDNabgRYUZbDuUBjzJFQ/3EjhJy0Uh/C+CvV0yg7")!
    private static let sharedPoint = Data(base64Encoded: "Ax+He3DPoJ+rb/ReTo8KbaLz1LxvOjyaXIrMhsS2kWgP")!

    @Test func theSharedPointIsTheCompressedECDHPoint() {
        let point = FileverseKey.sharedPoint(scalar: Self.scalar)(Self.ephemeral)
        #expect(point == Self.sharedPoint)
        #expect(point?.count == 33)
    }

    @Test func theScalarMatchesItsPublicKey() {
        #expect(FileverseKey.matches(scalar: Self.scalar, publicKey: Self.publicKey))
        var other = Self.scalar
        other[31] ^= 1
        #expect(!FileverseKey.matches(scalar: other, publicKey: Self.publicKey))
    }

    @Test func aKeyThatIsNotAScalarOpensNothing() {
        #expect(FileverseKey.sharedPoint(scalar: Data(repeating: 1, count: 31))(Self.ephemeral) == nil)
        #expect(FileverseKey.sharedPoint(scalar: Self.scalar)(Data(repeating: 9, count: 33)) == nil)
    }
}
