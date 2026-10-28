import Foundation
import TDJSON

/// The one TDLib client (prd §1575): Telegram's own library, signed in as
/// you, on this device. Its JSON interface is three C calls — `td_send`,
/// `td_receive`, `td_execute` — and this type is the Swift side of them: one
/// thread receiving, replies matched to requests by `@extra`, events routed
/// by `@client_id`, and the sign-in state published for the account page.
///
/// **Started only when it is needed** — the sign-in, a read with the switch
/// on, or a sign-out — never at launch: a started client holds a connection
/// to Telegram, and nobody who never signed in should pay for one.
///
/// **The database is encrypted with a key that never leaves this device**
/// (`TokenVault`, device-only), and excluded from backups: a restored copy
/// could not be opened without the key, and a Telegram session belongs to
/// the device that made it. A key is made only when there is no database to
/// open; a database whose key cannot be read is never overwritten, because
/// a Keychain read that failed once is not a key that is gone.
final class TelegramClient: @unchecked Sendable {
    static let shared = TelegramClient()

    /// The app id `scripts/tdlib.sh` writes from the login Keychain into the
    /// framework's header. 0 on a build made without it.
    static var configured: Bool { CASBERI_TELEGRAM_API_ID != 0 }

    enum Step: Equatable {
        case idle
        case starting
        case phone
        case code(sentTo: String?)
        case password(hint: String?)
        /// Telegram asks an existing account for a login email, then its code.
        case email
        case emailCode(sentTo: String?)
        /// A number with no Telegram account: this app never signs anyone up.
        case noAccount
        case ready
        case closed
        /// This launch cannot open the session (its key unreadable, or TDLib
        /// refused its parameters); the words say which.
        case unavailable(String)

        /// A step that waits on the person, so a sign-in is under way and
        /// nobody is signed in.
        var asks: Bool {
            switch self {
            case .phone, .code, .password, .email, .emailCode, .noAccount: true
            default: false
            }
        }
    }

    private let lock = NSLock()
    private var clientID: Int32?
    private var receiving = false
    private var nextExtra = 0
    private var waiting: [Int: CheckedContinuation<[String: Any], Never>] = [:]
    private var stepValue: Step = .idle
    private var stepWaiters: [CheckedContinuation<Void, Never>] = []

    /// Where the sign-in stands. Read on any thread; `onStep` hears changes.
    var step: Step { lock.withLock { stepValue } }
    /// Called on the main actor whenever `step` changes. One listener, the
    /// sign-in sheet, which clears it when it goes.
    @MainActor var onStep: ((Step) -> Void)?

    private static let databaseKeyName = "telegram.databaseKey"
    /// Read by the sweep's gate without starting TDLib.
    static let signedInKey = "telegram.session.signedIn"
    static var signedIn: Bool { UserDefaults.standard.bool(forKey: signedInKey) }

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Telegram", directoryHint: .isDirectory)
    }

    // MARK: Start

    /// Creates the client and its receiving thread, once. Safe to call again.
    func start() {
        let (fresh, firstEver): (Bool, Bool) = lock.withLock {
            guard clientID == nil, Self.configured else { return (false, false) }
            _ = td_execute(#"{"@type":"setLogVerbosityLevel","new_verbosity_level":1}"#)
            clientID = td_create_client_id()
            stepValue = .starting
            defer { receiving = true }
            return (true, !receiving)
        }
        guard fresh else { return }
        // ONE receiving thread for the process: `td_receive` serves every
        // client and must never be called from two threads at once, so a
        // sign-in after a sign-out reuses it.
        if firstEver {
            let thread = Thread { [weak self] in self?.receiveLoop() }
            thread.name = "TDLib receive"
            thread.qualityOfService = .utility
            thread.start()
        }
        // TDLib speaks first only once something is sent to it.
        sendOnly(["@type": "getOption", "name": "version"])
    }

    private func receiveLoop() {
        while true {
            guard let raw = td_receive(10.0) else { continue }
            guard let data = String(cString: raw).data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            if let extra = (event["@extra"] as? NSNumber)?.intValue {
                let waiter = lock.withLock { waiting.removeValue(forKey: extra) }
                waiter?.resume(returning: event)
                continue
            }
            // A client that was signed out may still be closing; what it says
            // about itself is not the current client's state.
            let from = (event["@client_id"] as? NSNumber)?.int32Value
            guard from != nil, from == lock.withLock({ clientID }) else { continue }
            if event["@type"] as? String == "updateAuthorizationState",
               let state = event["authorization_state"] as? [String: Any] {
                handle(state)
            }
        }
    }

    // MARK: Requests

    /// One request and its answer — the object, or an `error`. A request that
    /// gets no answer in `timeout` seconds answers an `error` too.
    func send(_ request: [String: Any], timeout: TimeInterval = 30) async -> [String: Any] {
        guard let id = lock.withLock({ clientID }) else {
            return ["@type": "error", "message": "TDLib not started"]
        }
        return await send(request, to: id, timeout: timeout)
    }

    private func send(_ request: [String: Any], to id: Int32, timeout: TimeInterval) async -> [String: Any] {
        let extra = lock.withLock { nextExtra += 1; return nextExtra }
        var body = request
        body["@extra"] = extra
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else {
            return ["@type": "error", "message": "unencodable request"]
        }
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            let waiter = self?.lock.withLock { self?.waiting.removeValue(forKey: extra) }
            waiter?.resume(returning: ["@type": "error", "message": "timeout"])
        }
        return await withCheckedContinuation { continuation in
            lock.withLock { waiting[extra] = continuation }
            td_send(id, json)
        }
    }

    private func sendOnly(_ request: [String: Any]) {
        guard let id = lock.withLock({ clientID }),
              let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8) else { return }
        td_send(id, json)
    }

    static func failed(_ answer: [String: Any]) -> String? {
        answer["@type"] as? String == "error" ? (answer["message"] as? String ?? "error") : nil
    }

    // MARK: Sign-in

    private func handle(_ state: [String: Any]) {
        switch state["@type"] as? String {
        case "authorizationStateWaitTdlibParameters":
            Task { await self.sendParameters() }
        case "authorizationStateWaitPhoneNumber":
            publish(.phone)
        case "authorizationStateWaitCode":
            let info = state["code_info"] as? [String: Any]
            let type = info?["type"] as? [String: Any]
            // Where the code went: the Telegram app, or a text to the number.
            let sentTo: String? = switch type?["@type"] as? String {
            case "authenticationCodeTypeTelegramMessage": String(localized: "your Telegram app")
            case "authenticationCodeTypeSms": info?["phone_number"] as? String
            default: nil
            }
            publish(.code(sentTo: sentTo))
        case "authorizationStateWaitPassword":
            let hint = (state["password_hint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            publish(.password(hint: hint))
        case "authorizationStateWaitEmailAddress":
            publish(.email)
        case "authorizationStateWaitEmailCode":
            let info = state["code_info"] as? [String: Any]
            publish(.emailCode(sentTo: (info?["email_address_pattern"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }))
        case "authorizationStateWaitRegistration":
            publish(.noAccount)
        case "authorizationStateReady":
            publish(.ready)
        case "authorizationStateClosed":
            // Signed out here, or the session ended from another device;
            // `publish` lets the client go.
            publish(.closed)
        default:
            break
        }
    }

    private func publish(_ step: Step) {
        let waiters = lock.withLock {
            stepValue = step
            if step == .closed { clientID = nil }
            defer { stepWaiters = [] }
            return stepWaiters
        }
        waiters.forEach { $0.resume() }
        Task { @MainActor in
            // Signed in is TDLib's word, never a memory of it: a restored
            // phone, or a session ended elsewhere, asks for the number again.
            if step == .ready {
                UserDefaults.standard.set(true, forKey: Self.signedInKey)
            } else if step == .closed || step.asks {
                UserDefaults.standard.set(false, forKey: Self.signedInKey)
            }
            self.onStep?(step)
        }
    }

    /// Waits until the sign-in settles on a step a person or a read can act
    /// on, at most `timeout` seconds. Starts the client.
    func settled(timeout: TimeInterval = 20) async -> Step {
        start()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let now = step
            if now != .starting && now != .idle { return now }
            await withCheckedContinuation { continuation in
                lock.withLock { stepWaiters.append(continuation) }
                Task.detached {
                    try? await Task.sleep(for: .seconds(1))
                    let waiters = self.lock.withLock {
                        defer { self.stepWaiters = [] }
                        return self.stepWaiters
                    }
                    waiters.forEach { $0.resume() }
                }
            }
        }
        return step
    }

    private func sendParameters() async {
        guard let key = Self.databaseKey() else {
            publish(.unavailable(String(localized: "Couldn't read this device's Telegram key. Try again later.")))
            return
        }
        let dir = Self.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = dir
        try? excluded.setResourceValues(values)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let answer = await send([
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": dir.appending(path: "db").path(),
            "files_directory": dir.appending(path: "files").path(),
            "database_encryption_key": key,
            // Chats and their history are kept, so a read asks Telegram only
            // for what is new; files are never downloaded.
            "use_file_database": false,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": Int(CASBERI_TELEGRAM_API_ID),
            "api_hash": CASBERI_TELEGRAM_API_HASH,
            "system_language_code": Locale.current.language.languageCode?.identifier ?? "en",
            // What Telegram's Devices list shows for this session.
            "device_model": "Casberi",
            "application_version": version ?? "1",
        ])
        if let failure = Self.failed(answer) {
            publish(.unavailable(failure))
        }
    }

    /// 32 random bytes, base64 as TDLib wants them. Made only when there is
    /// no database to open; nil when a database exists and its key cannot be
    /// read, which is never answered with a new key.
    private static func databaseKey() -> String? {
        if let key = TokenVault.get(databaseKeyName) { return key }
        if FileManager.default.fileExists(atPath: directory.appending(path: "db").path()) { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let key = Data(bytes).base64EncodedString()
        TokenVault.set(key, for: databaseKeyName)
        return key
    }

    func submit(phone: String) async -> String? {
        Self.failed(await send(["@type": "setAuthenticationPhoneNumber",
                                "phone_number": phone.filter { $0.isNumber || $0 == "+" }]))
    }

    func submit(code: String) async -> String? {
        Self.failed(await send(["@type": "checkAuthenticationCode",
                                "code": code.filter(\.isNumber)]))
    }

    func submit(password: String) async -> String? {
        Self.failed(await send(["@type": "checkAuthenticationPassword", "password": password]))
    }

    func submit(email: String) async -> String? {
        Self.failed(await send(["@type": "setAuthenticationEmailAddress",
                                "email_address": email.trimmingCharacters(in: .whitespaces)]))
    }

    func submit(emailCode: String) async -> String? {
        Self.failed(await send(["@type": "checkAuthenticationEmailCode",
                                "code": ["@type": "emailAddressAuthenticationCode",
                                         "code": emailCode.trimmingCharacters(in: .whitespaces)]]))
    }

    /// Ends the session at Telegram — starting the client to do it, since a
    /// session lives at Telegram whether or not this launch opened it — then
    /// forgets everything kept here, the read switch included. A sign-in
    /// under way is closed rather than logged out. Files are removed only
    /// once TDLib says the client is closed, so nothing is deleted under it.
    func signOut() async {
        let now = await settled()
        if let id = lock.withLock({ clientID }) {
            _ = await send(["@type": now == .ready ? "logOut" : "close"], to: id, timeout: 15)
            let deadline = Date().addingTimeInterval(15)
            while step != .closed, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        lock.withLock { clientID = nil; stepValue = .idle }
        try? FileManager.default.removeItem(at: Self.directory)
        TokenVault.delete(Self.databaseKeyName)
        DefaultsWrite.remove(TelegramMessagesRead.lastSeenKey)
        await MainActor.run {
            UserDefaults.standard.set(false, forKey: Self.signedInKey)
            UserDefaults.standard.set(false, forKey: LiveMessages.Seat.telegram.defaultsKey)
            onStep?(.idle)
        }
    }
}
