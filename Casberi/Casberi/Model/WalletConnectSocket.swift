import Foundation
import WalletConnectRelay

/// The relay's socket, on URLSession. Reown ships no default `WebSocketFactory`
/// — the SDK takes one and calls it for every relay connection — so this is the
/// smallest conforming socket that satisfies it, rather than pulling Starscream
/// in behind it (the whole point of the Sign-only dependency is that nothing
/// else rides along).
///
/// `WebSocketConnecting` is a callback protocol, not an async one: the SDK sets
/// `onConnect`/`onText`/`onDisconnect` and expects them fired from the socket's
/// own lifetime. Delivery therefore happens off the main actor, which is why
/// nothing here is `@MainActor`, why `isConnected` is lock-guarded (the SDK
/// reads it from its own thread while URLSession writes it from the delegate
/// queue), and why `receive` re-arms itself after each message —
/// URLSessionWebSocketTask hands over exactly one.
///
/// The delegate is a SEPARATE object holding a weak back-reference, which is
/// load-bearing: URLSession retains its delegate until invalidated, so making
/// the socket its own delegate is a retain cycle that no `deinit` can break
/// (the cycle is what stops `deinit` running). With the hop, `deinit` runs and
/// invalidates the session even if the SDK drops the socket without calling
/// `disconnect()`.
final class WalletConnectSocket: WebSocketConnecting {
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private let lock = NSLock()
    private var _isConnected = false
    var isConnected: Bool {
        get { lock.withLock { _isConnected } }
        set { lock.withLock { _isConnected = newValue } }
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let delegate = SocketDelegate()

    init(request: URLRequest) {
        self.request = request
        delegate.socket = self
    }

    deinit {
        session?.invalidateAndCancel()
    }

    func connect() {
        // A session can't be reused after invalidation, so each connect gets a
        // fresh one and each disconnect invalidates it.
        session?.invalidateAndCancel()
        let session = URLSession(configuration: .default,
                                 delegate: delegate,
                                 delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        receive(on: task)
        task.resume()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        // Releases URLSession's strong hold on `delegate`. Without this the
        // session, its delegate queue, and this socket outlive every reconnect.
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    /// One `receive` yields one message, so each success re-arms. A failure is
    /// terminal — the SDK's reconnect logic owns what happens next.
    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.onText?(text) }
                self.receive(on: task)
            case .failure(let error):
                self.isConnected = false
                self.onDisconnect?(error)
            }
        }
    }

    fileprivate func handleOpen() {
        isConnected = true
        onConnect?()
    }

    fileprivate func handleClose() {
        isConnected = false
        onDisconnect?(nil)
    }
}

/// Weakly held bridge from URLSession's delegate callbacks back to the socket.
/// See `WalletConnectSocket` — this exists only to keep URLSession's strong
/// delegate reference off the socket itself.
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate {
    weak var socket: WalletConnectSocket?

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        socket?.handleOpen()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        socket?.handleClose()
    }
}

struct WalletConnectSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        WalletConnectSocket(request: URLRequest(url: url))
    }
}
