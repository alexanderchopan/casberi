import Foundation

/// **YOUR ACCOUNT, IN CASBERI'S BROWSER (prd §1700e).** An Ethereum provider
/// (EIP-1193, announced by EIP-6963 as "Casberi") added to a page Casberi
/// opened for you — first Human Passport, where your Safe earns the score
/// Shield asks for. It connects only when you say so, signs only messages
/// (personal_sign, typed data) with your account's ERC-1271 signature, each
/// one asked first, and never sends a transaction. Reads go to Ethereum
/// through the Wallet's own node, from a short list.
enum BrowserEthereum {
    /// The provider, added at document start to the page's own world (a
    /// page's wallet library reads `window.ethereum` and EIP-6963 there). It
    /// carries no state but listeners: every answer is the app's.
    static let script = #"""
    (() => {
      if (window.__casberiEthereum) return;
      const port = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.casberiEthereum;
      if (!port) return;
      const listeners = {};
      const emit = (name, value) => (listeners[name] || []).slice().forEach(f => { try { f(value); } catch (_) {} });
      const provider = {
        isCasberi: true,
        async request(args) {
          const method = args && args.method;
          const params = (args && args.params) || [];
          const answer = await port.postMessage({ method, params: JSON.stringify(params) });
          if (answer && answer.error) {
            const e = new Error(answer.error.message);
            e.code = answer.error.code;
            throw e;
          }
          const result = answer ? answer.result : null;
          if (method === 'eth_requestAccounts' && Array.isArray(result) && result.length) emit('accountsChanged', result);
          return result;
        },
        on(name, f) { (listeners[name] = listeners[name] || []).push(f); return provider; },
        removeListener(name, f) { listeners[name] = (listeners[name] || []).filter(x => x !== f); return provider; },
        enable() { return provider.request({ method: 'eth_requestAccounts' }); },
      };
      Object.defineProperty(window, '__casberiEthereum', { value: provider });
      // Also `window.ethereum`: Reown's picker draws a "Browser Wallet" row on
      // every phone whatever is installed (measured on Passport, 2026-11-04),
      // so that row reaches Casberi too instead of failing.
      if (!window.ethereum) Object.defineProperty(window, 'ethereum', { value: provider, configurable: true });
      const info = Object.freeze({
        uuid: crypto.randomUUID(), name: 'Casberi', rdns: 'app.casberi',
        icon: 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyOSIgaGVpZ2h0PSIyOSIgdmlld0JveD0iMCAwIDEwMCAxMDAiPjxyZWN0IHg9IjAiIHk9IjAiIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIiBmaWxsPSIjMDAwIi8+PHBhdGggZD0iTTY5LjM4LDE5LjY2IEw2Ny43MywxOC43NSBMNjUuOCwxNy44IEw2My44MSwxNi45OCBMNjEuNzksMTYuMjggTDU5LjczLDE1LjcgTDU3LjY1LDE1LjI0IEw1NS41NCwxNC45MiBMNTMuNDIsMTQuNzIgTDUxLjMsMTQuNjQgTDQ5LjE5LDE0LjcgTDQ3LjA4LDE0Ljg4IEw0NC45OSwxNS4xOCBMNDIuOTMsMTUuNjEgTDQwLjksMTYuMTYgTDM4LjkyLDE2LjgzIEwzNi45OCwxNy42MiBMMzUuMDksMTguNTIgTDMzLjI3LDE5LjUzIEwzMS41MSwyMC42NSBMMjkuODIsMjEuODYgTDI4LjIyLDIzLjE3IEwyNi43LDI0LjU3IEwyNS4yNywyNi4wNiBMMjMuOTMsMjcuNjMgTDIyLjY5LDI5LjI3IEwyMS41NiwzMC45OCBMMjAuNTMsMzIuNzYgTDE5LjYxLDM0LjU4IEwxOC44MSwzNi40NiBMMTguMTIsMzguMzcgTDE3LjU0LDQwLjMyIEwxNy4wOSw0Mi4zIEwxNi43Niw0NC4yOSBMMTYuNTQsNDYuMyBMMTYuNDUsNDguMzEgTDE2LjQ4LDUwLjMyIEwxNi42Miw1Mi4zMiBMMTYuODksNTQuMzEgTDE3LjI4LDU2LjI3IEwxNy43OCw1OC4yIEwxOC4zOSw2MC4xIEwxOS4xMiw2MS45NCBMMTkuOTUsNjMuNzQgTDIwLjg5LDY1LjQ4IEwyMS45Myw2Ny4xNiBMMjMuMDYsNjguNzggTDI0LjI5LDcwLjMxIEwyNS42LDcxLjc3IEwyNi45OSw3My4xNCBMMjguNDcsNzQuNDMgTDMwLjAxLDc1LjYyIEwzMS42Miw3Ni43MSBMMzMuMjksNzcuNyBMMzUuMDEsNzguNTkgTDM2Ljc3LDc5LjM4IEwzOC41OCw4MC4wNSBMNDAuNDIsODAuNjIgTDQyLjI5LDgxLjA3IEw0NC4xNyw4MS40MSBMNDYuMjUsODEuNjUgTDQ4LjQ1LDgxLjYzIEw1MC41Miw4MS4zOCBMNTIuNDksODAuOTcgTDU0LjQxLDgwLjM5IEw1Ni4yNSw3OS42NyBMNTguMDMsNzguOCBMNTkuNzMsNzcuODEgTDYxLjMzLDc2LjY4IEw2Mi44NSw3NS40MyBMNjQuMjUsNzQuMDYgTDY1LjU0LDcyLjU5IEw2Ni43LDcxLjAyIEw2Ny43Myw2OS4zNSBMNjguNjEsNjcuNiBMNjkuMzMsNjUuNzcgTDY5Ljg5LDYzLjg5IEw3MC4yOCw2MS45NiBMNzAuNDcsNTkuOTkgTDcwLjQ4LDU4LjAxIEw3MC4zLDU2LjIyIEw3MC4xMiw1NS4zMyBMNjkuNzEsNTQuNTEgTDY5LjExLDUzLjgyIEw2OC4zNSw1My4zMSBMNjcuNDksNTMuMDIgTDY2LjU4LDUyLjk2IEw2NS42OCw1My4xNCBMNjQuODYsNTMuNTQgTDY0LjE3LDU0LjE0IEw2My42Nyw1NC45IEw2My4zNyw1NS43NyBMNjMuMzEsNTYuNjggTDYzLjM0LDU4LjExIEw2My4yMyw1OS4zNyBMNjIuOTksNjAuNjEgTDYyLjYzLDYxLjgyIEw2Mi4xNiw2MyBMNjEuNTksNjQuMTQgTDYwLjkyLDY1LjIzIEw2MC4xNSw2Ni4yNSBMNTkuMyw2Ny4yMSBMNTguMzgsNjguMDkgTDU3LjM5LDY4LjkgTDU2LjM0LDY5LjYyIEw1NS4yMyw3MC4yNSBMNTQuMDksNzAuOCBMNTIuOTEsNzEuMjUgTDUxLjcsNzEuNiBMNTAuNDksNzEuODQgTDQ5LjI4LDcxLjk5IEw0OC4xMyw3Mi4wMiBMNDcuMDksNzEuOTQgTDQ1Ljk4LDcxLjY5IEw0NC43LDcxLjM0IEw0My40NSw3MC45MiBMNDIuMjQsNzAuNDIgTDQxLjA2LDY5Ljg2IEwzOS45Miw2OS4yMyBMMzguODIsNjguNTMgTDM3Ljc3LDY3Ljc3IEwzNi43Nyw2Ni45NSBMMzUuODIsNjYuMDggTDM0Ljk0LDY1LjE1IEwzNC4xMSw2NC4xOCBMMzMuMzQsNjMuMTYgTDMyLjY0LDYyLjEgTDMyLDYxIEwzMS40NCw1OS44NyBMMzAuOTQsNTguNzIgTDMwLjUyLDU3LjUzIEwzMC4xNyw1Ni4zMyBMMjkuODksNTUuMTIgTDI5LjY5LDUzLjg5IEwyOS41Niw1Mi42NiBMMjkuNTEsNTEuNDMgTDI5LjUzLDUwLjIgTDI5LjYyLDQ4Ljk4IEwyOS43OSw0Ny43NiBMMzAuMDIsNDYuNTcgTDMwLjMzLDQ1LjQgTDMwLjcxLDQ0LjI1IEwzMS4xNSw0My4xMyBMMzEuNjYsNDIuMDQgTDMyLjIzLDQwLjk4IEwzMi44NiwzOS45NyBMMzMuNTUsMzkgTDM0LjI5LDM4LjA4IEwzNS4wOSwzNy4yIEwzNS45MywzNi4zOCBMMzYuODIsMzUuNjIgTDM3Ljc0LDM0LjkxIEwzOC43MSwzNC4yNSBMMzkuNzEsMzMuNjcgTDQwLjc0LDMzLjE0IEw0MS44LDMyLjY4IEw0Mi44NywzMi4yOCBMNDMuOTcsMzEuOTUgTDQ1LjA4LDMxLjY5IEw0Ni4yLDMxLjQ5IEw0Ny4zMiwzMS4zNyBMNDguNDUsMzEuMzEgTDQ5LjU3LDMxLjMyIEw1MC42OSwzMS4zOSBMNTEuNzksMzEuNTQgTDUyLjg4LDMxLjc1IEw1My45NiwzMi4wMiBMNTUuMDEsMzIuMzUgTDU2LjAzLDMyLjc1IEw1Ny4wMywzMy4yMSBMNTcuOTksMzMuNzIgTDU4LjkyLDM0LjI5IEw2MC4wMywzNS4wNSBMNjIuMTgsMzYgTDY0LjUsMzYuMzUgTDY2Ljg0LDM2LjEgTDY5LjAzLDM1LjI1IEw3MC45MywzMy44NiBMNzIuNCwzMi4wMyBMNzMuMzQsMjkuODggTDczLjcsMjcuNTYgTDczLjQ1LDI1LjIyIEw3Mi42LDIzLjAzIEw3MS4yMSwyMS4xNCBaIiBmaWxsPSIjRkEyRDQ4Ii8+PC9zdmc+Cg==',
      });
      const announce = () => window.dispatchEvent(new CustomEvent('eip6963:announceProvider', { detail: Object.freeze({ info, provider }) }));
      window.addEventListener('eip6963:requestProvider', announce);
      announce();
      setTimeout(() => emit('connect', { chainId: '0x1' }), 0);
    })();
    """#

    /// What a request needs from the person, if anything.
    enum Need: Equatable {
        /// Answered from what the app knows (chain, accounts, a refusal).
        case answer(Reply)
        /// Connect this page to your account.
        case connect
        /// Sign this personal message (its text).
        case signText(String)
        /// Sign this typed data (its JSON, and a line saying what it is).
        case signTyped(json: String, summary: String)
        /// A read on Ethereum, passed through.
        case read(method: String, params: [Any])

        static func == (a: Need, b: Need) -> Bool {
            switch (a, b) {
            case (.answer(let x), .answer(let y)): x == y
            case (.connect, .connect): true
            case (.signText(let x), .signText(let y)): x == y
            case (.signTyped(let x, _), .signTyped(let y, _)): x == y
            case (.read(let x, _), .read(let y, _)): x == y
            default: false
            }
        }
    }

    enum Reply: Equatable {
        case result(String?) // JSON text of the result
        case error(code: Int, message: String)

        /// What goes back to the page: `{result}` or `{error: {code, message}}`.
        var body: [String: Any] {
            switch self {
            case .result(let json):
                let value = json.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
                return ["result": value ?? NSNull()]
            case .error(let code, let message):
                return ["error": ["code": code, "message": message]]
            }
        }

        static let rejected = Reply.error(code: 4001, message: "You declined in Casberi.")
        static let unsupported = Reply.error(code: 4200, message: "Casberi signs messages here; it does not send from this page.")
        static let wrongAccount = Reply.error(code: 4100, message: "That is not the account Casberi connected.")
    }

    /// The reads a page may pass through to Ethereum: answers, never writes.
    static let reads: Set<String> = [
        "eth_blockNumber", "eth_call", "eth_getCode", "eth_getBalance", "eth_getTransactionCount",
        "eth_getTransactionReceipt", "eth_getTransactionByHash", "eth_getBlockByNumber", "eth_gasPrice",
        "eth_maxPriorityFeePerGas", "eth_feeHistory", "eth_estimateGas", "eth_getStorageAt",
    ]

    /// Reads one request: its method and its params (JSON text, as the page sent them).
    static func need(method: String, paramsJSON: String, account: String, connected: Bool) -> Need {
        let params = (try? JSONSerialization.jsonObject(with: Data(paramsJSON.utf8))) as? [Any] ?? []
        let mine = { (x: Any?) in (x as? String)?.lowercased() == account.lowercased() }
        switch method {
        case "eth_chainId": return .answer(.result("\"0x1\""))
        case "net_version": return .answer(.result("\"1\""))
        case "eth_accounts": return .answer(.result(connected ? "[\"\(account)\"]" : "[]"))
        case "eth_requestAccounts":
            return connected ? .answer(.result("[\"\(account)\"]")) : .connect
        case "wallet_switchEthereumChain":
            let chain = ((params.first as? [String: Any])?["chainId"] as? String)?.lowercased()
            return chain == "0x1" ? .answer(.result(nil)) : .answer(.error(code: 4902, message: "Casberi's account here is on Ethereum only."))
        case "wallet_requestPermissions", "wallet_getPermissions":
            return connected ? .answer(.result("[{\"parentCapability\":\"eth_accounts\"}]")) : .connect
        case "personal_sign":
            guard connected else { return .answer(.error(code: 4100, message: "Connect first.")) }
            // [message, address]; some libraries send them the other way round.
            let (message, address) = mine(params.dropFirst().first) ? (params.first, params.dropFirst().first)
                                                                     : (params.dropFirst().first, params.first)
            guard mine(address), let raw = message as? String, let text = text(of: raw) else {
                return .answer(mine(address) ? .unsupported : .wrongAccount)
            }
            return .signText(text)
        case "eth_signTypedData_v4":
            guard connected else { return .answer(.error(code: 4100, message: "Connect first.")) }
            guard mine(params.first), let json = params.dropFirst().first as? String,
                  let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
                return .answer(.wrongAccount)
            }
            let chain = ((o["domain"] as? [String: Any])?["chainId"]).map { "\($0)" }
            guard chain == nil || chain == "1" || chain == "0x1" else {
                return .answer(.error(code: 4901, message: "Casberi's account here is on Ethereum only."))
            }
            let name = (o["domain"] as? [String: Any])?["name"] as? String
            let kind = o["primaryType"] as? String ?? "data"
            return .signTyped(json: json, summary: [name, kind].compactMap { $0 }.joined(separator: " · "))
        default:
            if reads.contains(method) { return .read(method: method, params: params) }
            return .answer(.unsupported)
        }
    }

    /// A personal_sign message as text: hex is decoded when it is UTF-8,
    /// otherwise it is the text itself; bytes that are not text are refused
    /// (a hash dressed as a message signs something no one can read).
    static func text(of raw: String) -> String? {
        let lower = raw.lowercased()
        guard lower.hasPrefix("0x"), lower.count % 2 == 0, lower.dropFirst(2).allSatisfy(\.isHexDigit) else { return raw }
        var bytes: [UInt8] = []
        var i = lower.index(lower.startIndex, offsetBy: 2)
        while i < lower.endIndex {
            let j = lower.index(i, offsetBy: 2)
            bytes.append(UInt8(lower[i..<j], radix: 16)!)
            i = j
        }
        guard let text = String(bytes: bytes, encoding: .utf8),
              !text.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\r" && $0 != "\t" }) else { return nil }
        return text
    }
}
