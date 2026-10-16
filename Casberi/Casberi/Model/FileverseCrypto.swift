import CryptoKit
import Foundation

/// Fileverse's read-side cryptography (prd §1339, §1346): how a dDoc's lock,
/// title and body open, ported from `scripts/fileverse-probe/probe.mjs` step
/// for step. Foundation and CryptoKit only, so `fileverse-selftest.sh` compiles
/// it whole against vectors Fileverse's own libraries wrote. The one curve
/// operation (the ECDH point) is handed in as a closure, because it needs
/// libsecp256k1 and the harness cannot link it; `FileverseKey` supplies it in
/// the app and `CasberiTests/FileverseKeyTests` holds that half to the same
/// vector.
enum FileverseCrypto {
    /// Fileverse's field separator inside a lock string.
    static let separator = "__n__"

    enum Failure: Error, Equatable {
        case notBase64
        case lockParts(Int)
        case noSharedPoint
        case refused
        case notAKey(Int)
        case noLock
        case notADocument
    }

    /// Standard or URL-safe base64, padded or not.
    static func base64(_ s: String) throws -> Data {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        guard let d = Data(base64Encoded: t) else { throw Failure.notBase64 }
        return d
    }

    static func hkdf(_ ikm: Data, salt: Data, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt,
                               info: Data(info.utf8), outputByteCount: 32)
    }

    /// AES-GCM as `@fileverse/crypto` writes it: nonce (24) ‖ ciphertext ‖ tag.
    static func openNonceFirst(key: Data, _ bytes: Data) throws -> Data {
        guard bytes.count > 24 + 16 else { throw Failure.refused }
        let b = [UInt8](bytes)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: b[0..<24]),
                                            ciphertext: b[24..<(b.count - 16)],
                                            tag: b[(b.count - 16)...])
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw Failure.refused
        }
    }

    /// The content file: ciphertext ‖ tag (16) ‖ iv (12).
    static func openContent(key: Data, _ blob: Data) throws -> Data {
        guard blob.count > 12 + 16 else { throw Failure.refused }
        let b = [UInt8](blob)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: b[(b.count - 12)...]),
                                            ciphertext: b[0..<(b.count - 28)],
                                            tag: b[(b.count - 28)..<(b.count - 12)])
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw Failure.refused
        }
    }

    /// An ECIES lock, "<ephPub>__n__<nonce12>__n__<ciphertext>__n__<mac>":
    /// AES-GCM under HKDF-SHA256(the 33-byte compressed ECDH point, salt
    /// ephPub, "ECIES-AES256-GCM-SHA256"). `sharedPoint` turns the ephemeral
    /// public key into that point with the portal's key.
    static func openLock(_ sealed: String, sharedPoint: (Data) -> Data?) throws -> Data {
        let parts = sealed.components(separatedBy: separator)
        guard parts.count == 4 else { throw Failure.lockParts(parts.count) }
        let eph = try base64(parts[0]), nonce = try base64(parts[1])
        let ct = try base64(parts[2]), mac = try base64(parts[3])
        guard let point = sharedPoint(eph) else { throw Failure.noSharedPoint }
        let key = hkdf(point, salt: eph, info: "ECIES-AES256-GCM-SHA256")
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ct, tag: mac)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw Failure.refused
        }
    }

    /// A document, opened: its title and the Yjs update that is its body.
    struct Opened: Equatable {
        let title: String
        let update: Data
        /// Which lock opened it (`appLock` or `ownerLock`).
        let lock: String
    }

    /// Opens a file from its metadata JSON and its content blob. The file key
    /// is under `appLock` (what the API writes) or `ownerLock` (all the editor
    /// wrote for six months, measured §1339); either opens with the portal key.
    static func open(metadata: Data, content: Data, sharedPoint: (Data) -> Data?) throws -> Opened {
        guard let meta = try JSONSerialization.jsonObject(with: metadata) as? [String: Any] else {
            throw Failure.notADocument
        }
        var fileKey: Data?
        var opened = ""
        for lock in ["appLock", "ownerLock"] {
            guard let sealed = (meta[lock] as? [String: Any])?["lockedFileKey"] as? String,
                  let k = try? openLock(sealed, sharedPoint: sharedPoint) else { continue }
            guard k.count == 32 else { throw Failure.notAKey(k.count) }
            fileKey = k
            opened = lock
            break
        }
        guard let key = fileKey else { throw Failure.noLock }
        var title = ""
        if let sealedTitle = meta["title"] as? String {
            title = (try? openNonceFirst(key: key, try base64(sealedTitle)))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        let plain = try openContent(key: key, content)
        guard let body = try JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let file = body["file"] as? String else { throw Failure.notADocument }
        return Opened(title: title, update: try base64(file), lock: opened)
    }
}
