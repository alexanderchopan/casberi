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
/// nothing here is `@MainActor`, and why `receive` re-arms itself after each
/// message — URLSessionWebSocketTask hands over exactly one.
///
/// EVERY piece of mutable state lives behind one lock (2026-07-17), because the
/// SDK genuinely drives this object from three places at once — read out of
/// reown-swift 2.3.0, not assumed: `AutomaticSocketConnectionHandler` calls
/// `connect()` from its syncQueue (the periodic reconnect timer) AND from the
/// cooperative pool (`handleInternalConnect` calls it directly from async
/// context), `disconnect()` arrives on the MAIN thread (the background-task
/// expiration handler — fired ~30s after a wallet app opens over us, which is
/// why only a real device ever exercises it; the sim harness stubs `open` and
/// never backgrounds), and `refreshTokenIfNeeded` writes `request` from the
/// syncQueue while a connect reads it. Unsynchronized `task`/`session` vars
/// under that traffic are ARC pointer races — the crash wears an unrelated
/// EXC_BAD_ACCESS somewhere in objc_release.
///
/// Callbacks carry a STALENESS guard: a failing receive or a delegate close
/// only reports `onDisconnect` if it belongs to the CURRENT task/session. The
/// old session's death rattle arriving after a reconnect would otherwise tell
/// the SDK "disconnected" mid-connect and burn its immediate-retry budget on a
/// socket that's fine. A deliberate `disconnect()` fires `onDisconnect(nil)`
/// itself — the SDK's own `WebSocketMock` does exactly that, so it's the
/// contract, and the suppressed stale callbacks can't leave the status
/// provider hanging.
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

    private let lock = NSLock()
    private var _request: URLRequest
    private var _isConnected = false
    private var _task: URLSessionWebSocketTask?
    private var _session: URLSession?
    private let delegate = SocketDelegate()

    /// The SDK mutates this (Authorization refresh on reconnect) from its
    /// syncQueue while a connect on another thread reads it — locked like
    /// everything else.
    var request: URLRequest {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }

    var isConnected: Bool {
        lock.withLock { _isConnected }
    }

    init(request: URLRequest) {
        _request = request
        delegate.socket = self
    }

    deinit {
        _session?.invalidateAndCancel()
    }

    func connect() {
        // A session can't be reused after invalidation, so each connect gets a
        // fresh one and each disconnect invalidates it. Build outside the lock,
        // swap inside it, kill the old one after — concurrent connects (the
        // periodic timer racing handleInternalConnect) each settle on exactly
        // one live session, and the loser's callbacks fail the staleness guard.
        let session = URLSession(configuration: .default,
                                 delegate: delegate,
                                 delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        let old: URLSession? = lock.withLock {
            let old = _session
            _session = session
            _task = task
            _isConnected = false
            return old
        }
        old?.invalidateAndCancel()
        receive(on: task)
        task.resume()
    }

    func disconnect() {
        let (task, session): (URLSessionWebSocketTask?, URLSession?) = lock.withLock {
            defer { _task = nil; _session = nil; _isConnected = false }
            return (_task, _session)
        }
        task?.cancel(with: .goingAway, reason: nil)
        // Releases URLSession's strong hold on `delegate`. Without this the
        // session, its delegate queue, and this socket outlive every reconnect.
        session?.invalidateAndCancel()
        // A deliberate close reports itself (the SDK's WebSocketMock does the
        // same) — the receive loop's cancellation error is stale by the time it
        // lands and the guard below drops it.
        if task != nil { onDisconnect?(nil) }
    }

    func write(string: String, completion: (() -> Void)?) {
        let task = lock.withLock { _task }
        task?.send(.string(string)) { _ in completion?() }
    }

    /// One `receive` yields one message, so each success re-arms. A failure is
    /// terminal for THIS task — reported only if the task is still current
    /// (see the staleness note above); the SDK's reconnect logic owns what
    /// happens next.
    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.onText?(text) }
                self.receive(on: task)
            case .failure(let error):
                let isCurrent = self.lock.withLock {
                    guard self._task === task else { return false }
                    self._task = nil
                    self._isConnected = false
                    return true
                }
                if isCurrent { self.onDisconnect?(error) }
            }
        }
    }

    fileprivate func handleOpen(for session: URLSession) {
        let isCurrent = lock.withLock {
            guard _session === session else { return false }
            _isConnected = true
            return true
        }
        if isCurrent { onConnect?() }
    }

    fileprivate func handleClose(for session: URLSession) {
        let isCurrent = lock.withLock {
            guard _session === session else { return false }
            _isConnected = false
            return true
        }
        if isCurrent { onDisconnect?(nil) }
    }
}

/// Weakly held bridge from URLSession's delegate callbacks back to the socket.
/// See `WalletConnectSocket` — this exists only to keep URLSession's strong
/// delegate reference off the socket itself. It forwards the SESSION each
/// callback arrived on, so the socket can tell a current close from a stale
/// one (the delegate is shared across every session this socket ever opens).
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate {
    weak var socket: WalletConnectSocket?

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        socket?.handleOpen(for: session)
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        socket?.handleClose(for: session)
    }
}

struct WalletConnectSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        WalletConnectSocket(request: URLRequest(url: url))
    }
}
