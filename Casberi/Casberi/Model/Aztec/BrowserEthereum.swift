import Foundation

/// **YOUR ACCOUNT, IN CASBERI'S BROWSER (prd §1700e).** An Ethereum provider
/// (EIP-1193, announced by EIP-6963 as "Casberi") added to a page Casberi
/// opened for you — first Human Passport, where your Safe earns the score
/// Shield asks for. It connects only when you say so, signs messages
/// (personal_sign, typed data) with your account's ERC-1271 signature, each
/// one asked first, and reads go to Ethereum through the Wallet's own node,
/// from a short list. In Apps on Aztec's browser it also SENDS (prd §1700k):
/// one call on Ethereum per `eth_sendTransaction`, said on a sheet in words
/// (`ClearSign`, an approval read here), run against the real state, then
/// Face ID and, when the account needs both keys, the Signer.
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
      // The app icon (prd §1708) as a page draws a wallet: 144px, its
      // corners cut as the home screen cuts them (prd §1700l item 8).
      const info = Object.freeze({
        uuid: crypto.randomUUID(), name: 'Casberi', rdns: 'app.casberi',
        icon: 'data:image/png;base64,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',
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
        /// The page lets go of your account.
        case disconnect
        /// Send one call on Ethereum from your account (prd §1700k): `to`, the
        /// calldata as hex, the value in decimal wei.
        case send(to: String, data: String, value: String)

        static func == (a: Need, b: Need) -> Bool {
            switch (a, b) {
            case (.answer(let x), .answer(let y)): x == y
            case (.connect, .connect): true
            case (.signText(let x), .signText(let y)): x == y
            case (.signTyped(let x, _), .signTyped(let y, _)): x == y
            case (.read(let x, _), .read(let y, _)): x == y
            case (.disconnect, .disconnect): true
            case (.send(let a, let b, let c), .send(let x, let y, let z)): a == x && b == y && c == z
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
        static let unsupported = Reply.error(code: 4200, message: "Casberi does not do this on this page.")
        static let wrongAccount = Reply.error(code: 4100, message: "That is not the account Casberi connected.")
    }

    /// **Connected as your co-signer (prd §1700l).** The page knows the
    /// co-signer's address and its signatures come from the co-signer's own
    /// wallet, for an app that takes only a plain key's signature. Where the
    /// page may send at all, its send goes to the co-signer's wallet too and
    /// pays from the co-signer, never your account (prd §1700l item 9). A page
    /// asking to connect again is asked again.
    static func asCoSigner(method: String, connected: Bool, sends: Bool) -> (connected: Bool, sends: Bool) {
        (connected && !["eth_requestAccounts", "wallet_requestPermissions"].contains(method), sends)
    }

    /// A decimal amount of wei as a hex quantity ("0x0" for zero), as a
    /// wallet's `eth_sendTransaction` takes it; nil for anything not digits.
    static func hexQuantity(decimal raw: String) -> String? {
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var digits = raw.compactMap { $0.wholeNumberValue }
        var hex: [Character] = []
        let alphabet = Array("0123456789abcdef")
        while !(digits.isEmpty || digits.allSatisfy { $0 == 0 }) {
            var next: [Int] = [], rest = 0
            for d in digits {
                let cur = rest * 10 + d
                let q = cur / 16
                rest = cur % 16
                if !next.isEmpty || q != 0 { next.append(q) }
            }
            hex.append(alphabet[rest])
            digits = next
        }
        return "0x" + (hex.isEmpty ? "0" : String(hex.reversed()))
    }

    /// A transaction hash as a wallet answers one.
    static func isTransactionHash(_ s: String) -> Bool {
        s.count == 66 && s.hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// **A sign-in your account gave and the app turned down (prd §1700l).**
    /// No app says so to its wallet; what Casberi sees is the retry: a page
    /// your account signed for asks to connect again within this window.
    /// Then Connect is asked again, leading with your co-signer.
    static let retryWindow: TimeInterval = 300

    static func asksAgainAfterSign(method: String, signedAt: Date?, now: Date, hasCoSigner: Bool) -> Bool {
        guard hasCoSigner, let signedAt, ["eth_requestAccounts", "wallet_requestPermissions"].contains(method) else { return false }
        let since = now.timeIntervalSince(signedAt)
        return since >= 0 && since < retryWindow
    }

    /// The reads a page may pass through to Ethereum: answers, never writes.
    static let reads: Set<String> = [
        "eth_blockNumber", "eth_call", "eth_getCode", "eth_getBalance", "eth_getTransactionCount",
        "eth_getTransactionReceipt", "eth_getTransactionByHash", "eth_getBlockByNumber", "eth_gasPrice",
        "eth_maxPriorityFeePerGas", "eth_feeHistory", "eth_estimateGas", "eth_getStorageAt",
    ]

    /// Reads one request: its method and its params (JSON text, as the page
    /// sent them). `sends` is whether this page may send at all (Apps on
    /// Aztec's browser); elsewhere a send is refused as before.
    static func need(method: String, paramsJSON: String, account: String, connected: Bool, sends: Bool = false) -> Need {
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
        case "wallet_revokePermissions":
            return .disconnect
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
        case "eth_sendTransaction":
            guard sends else { return .answer(.unsupported) }
            guard connected else { return .answer(.error(code: 4100, message: "Connect first.")) }
            guard let tx = params.first as? [String: Any] else { return .answer(.unsupported) }
            return transaction(tx, account: account)
        default:
            if reads.contains(method) { return .read(method: method, params: params) }
            return .answer(.unsupported)
        }
    }

    /// One `eth_sendTransaction` object as a send, or the refusal it earns:
    /// from your account or unnamed, to an address (a contract creation is
    /// refused), on Ethereum, the value a hex quantity, the data hex.
    static func transaction(_ tx: [String: Any], account: String) -> Need {
        if let from = tx["from"] as? String, from.lowercased() != account.lowercased() { return .answer(.wrongAccount) }
        if let chain = tx["chainId"].map({ "\($0)".lowercased() }), chain != "0x1", chain != "1" {
            return .answer(.error(code: 4901, message: "Casberi's account here is on Ethereum only."))
        }
        guard let to = tx["to"] as? String, isAddress(to) else {
            return .answer(.error(code: 4200, message: "Casberi does not make contracts from this page."))
        }
        let data = (tx["data"] as? String) ?? (tx["input"] as? String) ?? "0x"
        guard data.lowercased().hasPrefix("0x"), data.count % 2 == 0, data.dropFirst(2).allSatisfy(\.isHexDigit) else {
            return .answer(.error(code: -32602, message: "That call's data is not hex."))
        }
        let value: String
        if let raw = tx["value"] as? String {
            guard let v = decimal(hexQuantity: raw) else { return .answer(.error(code: -32602, message: "That value is not a quantity.")) }
            value = v
        } else {
            value = "0"
        }
        return .send(to: to, data: data.lowercased(), value: value)
    }

    static func isAddress(_ s: String) -> Bool {
        s.count == 42 && s.lowercased().hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A JSON-RPC quantity ("0x…") as decimal digits; nil when it is not one.
    static func decimal(hexQuantity raw: String) -> String? {
        let lower = raw.lowercased()
        guard lower.hasPrefix("0x"), lower.count > 2, lower.count <= 66, lower.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
        // Long division of the hex digits by ten, so 256-bit values stay exact.
        var digits = lower.dropFirst(2).map { Int(String($0), radix: 16)! }
        var out = ""
        while !(digits.isEmpty || digits.allSatisfy { $0 == 0 }) {
            var rest = 0
            var next: [Int] = []
            for d in digits {
                let n = rest * 16 + d
                let q = n / 10
                rest = n % 10
                if !next.isEmpty || q != 0 { next.append(q) }
            }
            out = String(rest) + out
            digits = next
        }
        return out.isEmpty ? "0" : out
    }

    /// An ERC-20 `approve(address,uint256)`: the spender, the amount in base
    /// units, and whether it is no limit (the top byte set: the max uint256
    /// apps send, or near it). nil for any other call.
    struct Approval: Equatable {
        let spender: String
        let amount: String
        let unlimited: Bool
    }

    static func approval(_ data: String) -> Approval? {
        let hex = data.lowercased()
        guard hex.hasPrefix("0x095ea7b3"), hex.count == 2 + 8 + 128 else { return nil }
        let words = hex.dropFirst(10)
        let spenderWord = words.prefix(64), amountWord = words.suffix(64)
        guard spenderWord.prefix(24).allSatisfy({ $0 == "0" }),
              let amount = decimal(hexQuantity: "0x" + amountWord) else { return nil }
        return Approval(spender: "0x" + spenderWord.suffix(40), amount: amount,
                        unlimited: amountWord.prefix(2) == "ff")
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
