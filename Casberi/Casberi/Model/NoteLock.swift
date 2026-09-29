import Foundation
import SwiftData
import CryptoKit
import LocalAuthentication
import Security

/// A LOCKED NOTE (prd §982, 2026-09-28) — Apple Notes' lock, for a note you
/// kept here.
///
/// **Sealed, not hidden.** Locking moves the note's words, its picture and its
/// links into one ChaCha20-Poly1305 box and leaves "Locked note" in their
/// place. Nothing downstream is asked to look away: the row, the lede, the
/// widget, Spotlight, the embedding index and the agent all read the record,
/// and the record no longer holds the words. A gate that only hid them in
/// Casberi's own screens would leave them in iCloud, in search and in every
/// answer — §83's fake status in the one place somebody trusted it.
///
/// **The key lives in iCloud Keychain (the user's ruling, 2026-09-28), which
/// is Apple's own design for its locked notes:** a locked note opens on each
/// of your devices, and survives a new phone. This is the ONE Keychain item
/// the app stores synchronizable, a reasoned exception to §277's
/// device-only rule, recorded in `keychain-audit.py`'s `KNOWN_EXEMPT`: §277
/// keeps a bridge's credential from leaving the device, and this key's whole
/// job is to reach your other devices, end-to-end encrypted by iCloud
/// Keychain as Apple Notes' own key is.
///
/// **Opening asks for Face ID, Touch ID or the passcode** (`.deviceOwner
/// Authentication`) every time; the words stay open for as long as the sheet
/// stays open and are never written back. Remove lock restores the record.
///
/// **Keys are never overwritten.** Each device that locks a note before any
/// key has synced to it makes its own, under its own id, and the box names
/// the key that sealed it (the first 16 bytes). Two devices creating a key in
/// the same minute therefore cannot race one key out of iCloud Keychain and
/// leave notes sealed under a key nobody holds.
///
/// **What it cannot do, stated:** a note is sealed from the moment it is
/// locked. What CloudKit or a backup held before that moment is theirs; and a
/// device signed out of iCloud Keychain holds no key and shows the note
/// locked. Only a written note locks — a voice note IS its audio, which the
/// player needs.
enum NoteLock {

    /// The `sourceRef` a locked note carries — the one cheap read that says
    /// "locked" without faulting the sealed bytes (`audio` is external
    /// storage). A kept note has no other `sourceRef`; the old one, if any,
    /// rides inside the box and comes back on Remove lock.
    static let refMark = "notelock:v1"

    static func isLocked(_ thing: Thing) -> Bool { thing.sourceRef == refMark }

    /// Whether this thing can be locked: a written note you kept here, not
    /// already locked.
    static func canLock(_ thing: Thing) -> Bool {
        thing.isLive && NoteSheetSource.isKeptNote(thing) && thing.kind == .note
            && !isLocked(thing)
    }

    /// What the box holds — everything that says what the note is.
    struct Sealed: Codable, Equatable {
        var title: String
        var content: String
        var picture: Data?
        var sourceRef: String?
        var wikilinks: [String]
        /// The pictures after the first (the note-pictures ruling). Optional,
        /// so a box sealed before it opens as it always did.
        var pictures: Data? = nil
    }

    enum Failure: Error { case noKey, auth, corrupt }

    // MARK: - Lock

    /// Seal the note. No authentication — locking gives nothing away, and
    /// Apple Notes asks for nothing to lock either. Returns false (and
    /// changes nothing) when there is no key and none could be made.
    @MainActor
    @discardableResult
    static func lock(_ thing: Thing, context: ModelContext) -> Bool {
        // A note locked on a device that cannot ask for its owner could
        // never be opened there: no passcode, no lock (Apple Notes' rule too).
        guard canLock(thing), canAuthenticate, let key = Keys.current() else { return false }
        let sealed = Sealed(title: thing.title, content: thing.content,
                            picture: thing.previewImageData, sourceRef: thing.sourceRef,
                            wikilinks: thing.wikilinks, pictures: thing.notePictures)
        guard let plain = try? JSONEncoder().encode(sealed),
              let box = try? ChaChaPoly.seal(plain, using: key.key).combined else { return false }
        thing.audio = key.idBytes + box
        thing.title = String(localized: "Locked note")
        thing.content = ""
        thing.previewImageData = nil
        thing.notePictures = nil
        thing.wikilinks = []
        // Everything DERIVED from the words goes with them: a phone number
        // the row could dial, the vector search matches on, the retrieval
        // text. The vector is re-made from "Locked note" by the next sweep.
        thing.enrichedText = nil
        thing.detectedTel = nil
        thing.detectedPlace = nil
        thing.detectedMailto = nil
        thing.embedding = nil
        thing.sourceRef = refMark
        StoredPixels.forget(thing.id)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return true
    }

    // MARK: - Open

    /// Ask for Face ID / Touch ID / the passcode, then open the box. nil when
    /// the person declined, the key is not on this device, or the box does
    /// not open.
    @MainActor
    static func open(_ thing: Thing) async -> Result<Sealed, Failure> {
        // The bytes are read BEFORE the wait for a face: the row can be
        // deleted (another device, an Undo window) while the prompt is up.
        guard thing.isLive, let bytes = thing.audio else { return .failure(.corrupt) }
        guard await authenticate() else { return .failure(.auth) }
        return unseal(bytes)
    }

    static func unseal(_ bytes: Data) -> Result<Sealed, Failure> {
        guard bytes.count > 16 else { return .failure(.corrupt) }
        let id = UUID(uuid: Array(bytes.prefix(16)).withUnsafeBytes {
            $0.load(as: uuid_t.self)
        })
        guard let key = Keys.key(id: id) else { return .failure(.noKey) }
        guard let box = try? ChaChaPoly.SealedBox(combined: bytes.dropFirst(16)),
              let plain = try? ChaChaPoly.open(box, using: key),
              let sealed = try? JSONDecoder().decode(Sealed.self, from: plain)
        else { return .failure(.corrupt) }
        return .success(sealed)
    }

    /// Remove the lock: the box's contents go back where they came from.
    /// Detection is re-armed (`detectedAt = nil`) so the phone and address
    /// verbs the lock cleared come back on the next sweep.
    @MainActor
    static func unlock(_ thing: Thing, with sealed: Sealed, context: ModelContext) {
        guard thing.isLive, isLocked(thing) else { return }
        thing.title = sealed.title
        thing.content = sealed.content
        thing.previewImageData = sealed.picture
        thing.notePictures = sealed.pictures
        thing.wikilinks = sealed.wikilinks
        thing.sourceRef = sealed.sourceRef
        thing.audio = nil
        thing.embedding = nil
        thing.detectedAt = nil
        StoredPixels.forget(thing.id)
        context.saveHonestly()
        SpotlightIndex.index([thing])
    }

    /// The device owner, by whatever this device has: Face ID, Touch ID or
    /// the passcode. Never biometry-only — a note locked on a phone must
    /// open on a Mac with no Touch ID, and after a failed face.
    static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: String(localized: "Open your locked note"))) ?? false
    }

    /// Whether this device can ask for its owner at all — a passcode is set.
    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// The word for the unlock control: what this device will ask for.
    static var unlockWord: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return String(localized: "Open with Face ID")
        case .touchID: return String(localized: "Open with Touch ID")
        case .opticID: return String(localized: "Open with Optic ID")
        default:       return String(localized: "Open with your passcode")
        }
    }

    // MARK: - Keys (iCloud Keychain)

    /// The lock's keys. Synchronizable, `AfterFirstUnlock` — a synchronizable
    /// item cannot carry an access control or a `ThisDeviceOnly` class, which
    /// is why opening is gated by `authenticate()` rather than by the item.
    enum Keys {
        static let service = "com.casberi.notelock"

        struct Current {
            let id: UUID
            let key: SymmetricKey
            var idBytes: Data { withUnsafeBytes(of: id.uuid) { Data($0) } }
        }

        /// A key to seal with: the oldest one this device holds (synced from
        /// another device or made here), or a new one.
        static func current() -> Current? {
            if let existing = all().min(by: { $0.id.uuidString < $1.id.uuidString }) {
                return existing
            }
            let made = Current(id: UUID(), key: SymmetricKey(size: .bits256))
            let raw = made.key.withUnsafeBytes { Data($0) }
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: made.id.uuidString,
                kSecValueData as String: raw,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: true,
            ]
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? made : nil
        }

        static func key(id: UUID) -> SymmetricKey? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id.uuidString,
                kSecAttrSynchronizable as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var out: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data, data.count == 32 else { return nil }
            return SymmetricKey(data: data)
        }

        static func all() -> [Current] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: true,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var out: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
                  let rows = out as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                guard let account = row[kSecAttrAccount as String] as? String,
                      let id = UUID(uuidString: account),
                      let data = row[kSecValueData as String] as? Data, data.count == 32
                else { return nil }
                return Current(id: id, key: SymmetricKey(data: data))
            }
        }
    }
}

extension ShellChrome {
    /// Lock a note and say so (prd §982) — the row's menu and the sheet's row,
    /// one wording. A lock that could not be made (no key could be stored)
    /// says that, rather than leaving the words readable under a verb that
    /// looked like it worked.
    @MainActor
    func lockNote(_ thing: Thing, context: ModelContext) {
        if !NoteLock.canAuthenticate {
            flash(String(localized: "Set a passcode to lock notes"), tone: .failure)
        } else if NoteLock.lock(thing, context: context) {
            DSHaptic.success()
            flash(String(localized: "Locked"))
        } else {
            flash(String(localized: "Couldn't lock this note"), tone: .failure)
        }
    }
}
