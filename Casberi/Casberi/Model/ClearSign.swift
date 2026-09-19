import Foundation

/// ERC-7730 clear signing — what a contract call DOES, in the words its own
/// protocol published for it (prd §834).
///
/// **Where the words come from.** ERC-7730 is the open format a protocol uses
/// to describe its calls to a person, and the registry every wallet in the
/// Ethereum Foundation's clear-signing coalition reads (Ledger, Trezor, …) is
/// `ethereum/clear-signing-erc7730-registry`, CC0. A pinned snapshot of it is
/// BUNDLED (`Resources/ClearSignRegistry.json`, built by
/// `scripts/clearsign-registry.py`, which resolves includes, `$ref`s and
/// constants so this file does not have to). Nothing here touches the network:
/// a lookup at signing time would tell a host which contract this phone is
/// about to sign for.
///
/// **What this adds and what it never replaces.** The sign block's own readers
/// (`SafeCalldata.read`) keep priority — they are the reason a Safe proposal
/// can be signed here at all, and they say exactly what they read. This is
/// asked only where they would have said "Casberi can't read what this does",
/// so a transaction with no descriptor reads exactly as it did before.
///
/// **The bytes are decoded HERE, never taken from a service's `dataDecoded`.**
/// A descriptor supplies the function's types and the words; the arguments
/// come out of the calldata on this device, by the same subtraction-only
/// bounds `SafeCalldata.batchCalls` keeps, because a proposal's calldata is
/// written by anyone who can propose. Anything that does not decode cleanly,
/// or any `mustMatch` rule that fails, returns nil — no reading, never a
/// partial one.
///
/// Foundation-only (plus `Keccak256`/`EIP55`), so `clearsign-selftest.sh`
/// compiles it whole and runs the registry's OWN test vectors through it.
enum ClearSign {

    // MARK: - The reading

    /// One described call. `sentence` is the descriptor's interpolated intent
    /// ("Swap 1000 USDC for at least 0.25 WETH") and is nil whenever any value
    /// in it could not be stated cleanly — an amount of a token whose decimals
    /// are unknown never lands inside a sentence; it stays a labelled line.
    struct Reading: Equatable {
        struct Line: Equatable {
            let label: String
            let value: String
        }
        /// Who wrote the words — the descriptor's `metadata.owner`.
        let owner: String?
        /// The contract, as its descriptor names it.
        let contract: String?
        let intent: String
        let sentence: String?
        let lines: [Line]

        /// The one line a row or a title carries.
        var headline: String { sentence ?? intent }
    }

    /// How values are named and printed. `canonical` is the registry's own
    /// test output (full checksummed addresses, `2026-04-03 07:06:40Z`); the
    /// app passes its own names and shortening.
    struct Style {
        /// An address nothing names.
        var address: (String) -> String
        /// A name for an address from a source the caller trusts, or nil.
        var name: (String) -> String?
        /// Ticker and decimals for a token, or nil (then the amount is stated
        /// in base units and kept out of any sentence).
        var token: (String) -> Token?
        /// An NFT collection's name, or nil.
        var collection: (String) -> String?
        /// What `senderAddress` renders as — the account the call is made from.
        var sender: String
        var date: (Date) -> String
        /// What a value nothing can name falls back to. The registry's own
        /// tests expect the bare form (an amount's integer, embedded calldata
        /// as hex); the app says "base units of …" / "a call to …" and keeps
        /// it out of any sentence, because a bare integer reads as a price.
        var rawFallbacks: Bool
        /// Whether a contract or token the bundled registry itself describes
        /// may be named by it. Off for the registry's own vectors, which
        /// expect a bare address wherever their data provider named nothing.
        var namesFromRegistry: Bool

        static let canonical = Style(
            address: { EIP55.checksum($0) },
            name: { _ in nil }, token: { _ in nil }, collection: { _ in nil },
            sender: "Sender",
            date: { ClearSign.utcStamp($0) },
            rawFallbacks: true,
            namesFromRegistry: false)
    }

    struct Token: Decodable, Equatable {
        let ticker: String
        let decimals: Int
    }

    // MARK: - The registry

    struct Registry: Decodable {
        struct Source: Decodable, Equatable {
            let repo: String
            let commit: String
            let date: String
        }
        struct Descriptor: Decodable {
            let owner: String?
            let name: String?
            let formats: [Format]
        }
        struct Format: Decodable {
            let key: String
            let intent: String?
            let interpolatedIntent: String?
            let fields: [Field]
        }
        struct Field: Decodable {
            let path: String?
            let value: JSON?
            let label: String?
            let format: String?
            let visible: JSON?
            let separator: String?
            let params: [String: JSON]?
            let encrypted: String?
        }
        let source: Source
        /// `"<chainId>:<lowercased address>"` → index into `descriptors`.
        let contracts: [String: Int]
        let tokens: [String: Token]
        let descriptors: [Descriptor]
    }

    /// The generator writes every scalar as a string (a uint256 threshold
    /// decoded as a Double would lose its low digits), so this needs no number.
    indirect enum JSON: Decodable, Equatable {
        case string(String)
        case bool(Bool)
        case array([JSON])
        case object([String: JSON])
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let b = try? c.decode(Bool.self) { self = .bool(b) }
            else if let s = try? c.decode(String.self) { self = .string(s) }
            else if let a = try? c.decode([JSON].self) { self = .array(a) }
            else if let o = try? c.decode([String: JSON].self) { self = .object(o) }
            else if let d = try? c.decode(Double.self) { self = .string(String(d)) }
            else { self = .null }
        }

        var string: String? {
            if case .string(let s) = self { return s }
            return nil
        }
        var strings: [String] {
            switch self {
            case .string(let s): return [s]
            case .array(let a): return a.compactMap(\.string)
            default: return []
            }
        }
    }

    /// The bundled snapshot, decoded once. nil when the resource is missing,
    /// which reads as "no descriptor" everywhere — never as a failure.
    static let shared: Registry? = {
        guard let url = Bundle.main.url(forResource: "ClearSignRegistry", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Registry.self, from: data)
    }()

    /// Decodes the snapshot OFF the main thread, once. A static's first read
    /// is thread-safe, so this simply makes sure that read is not the main
    /// actor's: the first Safe sweep after launch would otherwise pay the
    /// whole decode inside a frame. Await it before the first `describe`
    /// from a main-actor context.
    static func warm() async {
        await Task.detached(priority: .utility) { _ = ClearSign.shared }.value
    }

    // MARK: - Describe

    /// The most levels of embedded calldata (a `calldata`-format field) this
    /// follows before refusing to describe the inner call.
    static let maxDepth = 3

    /// Describes one call, or nil when the registry has no descriptor for this
    /// contract and selector or the calldata does not decode against it.
    ///
    /// `from` is the account making the call — for a Safe proposal's inner
    /// call that is the Safe itself — and is what `@.from` resolves to.
    static func describe(chainId: Int, to: String, data: [UInt8], value: String = "0",
                         from: String? = nil, style: Style = .canonical,
                         registry: Registry? = ClearSign.shared) -> Reading? {
        guard let registry else { return nil }
        return describe(Context(chainId: chainId, to: to.lowercased(), value: decimalWord(value),
                                from: from?.lowercased(), style: style, registry: registry),
                        data: data, depth: 0)
    }

    /// Every token address the reading would ask `style.token` for — so a
    /// caller can read their decimals BEFORE describing, and describe once.
    static func tokensAsked(chainId: Int, to: String, data: [UInt8], value: String = "0",
                            from: String? = nil, registry: Registry? = ClearSign.shared) -> Set<String> {
        final class Box { var asked = Set<String>() }
        let box = Box()
        var style = Style.canonical
        style.token = { box.asked.insert($0.lowercased()); return nil }
        _ = describe(chainId: chainId, to: to, data: data, value: value, from: from,
                     style: style, registry: registry)
        return box.asked
    }

    private struct Context {
        let chainId: Int
        let to: String
        let value: [UInt8]
        let from: String?
        let style: Style
        let registry: Registry
    }

    private static func describe(_ ctx: Context, data: [UInt8], depth: Int) -> Reading? {
        guard depth <= maxDepth, data.count >= 4,
              let index = ctx.registry.contracts["\(ctx.chainId):\(ctx.to)"],
              ctx.registry.descriptors.indices.contains(index)
        else { return nil }
        let descriptor = ctx.registry.descriptors[index]
        let selector = Array(data.prefix(4))

        // Match on the type-only signature's selector. Two keys sharing one is
        // an invalid descriptor (the spec's rule), so it describes nothing.
        var matched: (format: Registry.Format, fn: Function)?
        for format in descriptor.formats {
            guard let fn = Function(key: format.key), fn.selector == selector else { continue }
            if matched != nil { return nil }
            matched = (format, fn)
        }
        guard let format = matched?.format, let fn = matched?.fn,
              let args = ABI.decode(fn.params, Array(data.dropFirst(4)))
        else { return nil }

        let renderer = Renderer(ctx: ctx, args: args, fields: format.fields, depth: depth)
        var lines: [Reading.Line] = []
        for field in format.fields {
            switch renderer.render(field) {
            case .hidden: continue
            case .refused: return nil
            case .shown(let parts):
                // A field with no label is read in interpolation only. An
                // array field is one line per element, each under the label.
                if let label = field.label, !label.isEmpty {
                    lines += parts.map { .init(label: label, value: $0.text) }
                }
            }
        }
        let intent = format.intent ?? fn.name
        return Reading(owner: descriptor.owner, contract: descriptor.name, intent: intent,
                       sentence: format.interpolatedIntent.flatMap(renderer.interpolate),
                       lines: lines)
    }

    // MARK: - Rendering

    /// A formatted value, and whether it is CLEAN — `false` for an amount
    /// whose token is unknown or a call nothing describes. A degraded value is
    /// still a true line; it just never lands inside a sentence.
    private struct Text {
        let text: String
        let clean: Bool
    }

    private enum Outcome {
        /// One text per element (one for a scalar).
        case shown([Text])
        case hidden
        /// A `mustMatch` rule failed, or a value did not resolve — the whole
        /// reading is withdrawn.
        case refused
    }

    private struct Renderer {
        let ctx: Context
        let args: [(String, Value)]
        let fields: [Registry.Field]
        let depth: Int

        func render(_ field: Registry.Field) -> Outcome {
            if case .string(let v)? = field.visible, v == "never" { return .hidden }
            var values: [Value]
            if let path = field.path {
                // A path that does not resolve withdraws the reading: the
                // descriptor promised this value and we could not find it.
                // `@.from` is the one exception — a caller that does not know
                // the sender simply cannot state it.
                guard let resolved = resolve(path) else {
                    return path == "@.from" ? .hidden : .refused
                }
                if resolved.isEmpty { return .hidden }
                values = resolved
            } else if let constant = field.value?.string {
                values = [.string(constant)]
            } else {
                return .hidden
            }
            if case .object(let rules)? = field.visible {
                if let list = rules["mustMatch"]?.strings {
                    return values.allSatisfy({ matches($0, list) }) ? .hidden : .refused
                }
                if let list = rules["ifNotIn"]?.strings {
                    values = values.filter { !matches($0, list) }
                    if values.isEmpty { return .hidden }
                }
            }
            if let encrypted = field.encrypted {
                return .shown([Text(text: encrypted, clean: false)])
            }
            var parts: [Text] = []
            for (i, v) in values.enumerated() {
                guard let t = format(v, field: field, element: values.count > 1 ? i : nil) else {
                    return .refused
                }
                parts.append(t)
            }
            if let separator = field.separator {
                parts = parts.enumerated().map { i, p in
                    Text(text: separator.replacingOccurrences(of: "{index}", with: String(i)) + p.text,
                         clean: p.clean)
                }
            }
            return .shown(parts)
        }

        /// `interpolatedIntent`, or nil when any placeholder fails to resolve
        /// or is not clean — the spec's fallback is the plain intent.
        func interpolate(_ template: String) -> String? {
            var out = ""
            var i = template.startIndex
            while i < template.endIndex {
                let ch = template[i]
                let next = template.index(after: i)
                if ch == "{" {
                    if next < template.endIndex, template[next] == "{" {
                        out.append("{"); i = template.index(after: next); continue
                    }
                    guard let close = template[next...].firstIndex(of: "}") else { return nil }
                    let path = String(template[next..<close])
                    let key = normalized(path)
                    let field = fields.first { $0.path.map(normalized) == key }
                        ?? Registry.Field(path: path, value: nil, label: nil, format: "raw", visible: nil,
                                          separator: nil, params: nil, encrypted: nil)
                    guard case .shown(let parts) = render(field), !parts.isEmpty,
                          parts.allSatisfy(\.clean) else { return nil }
                    out += ClearSign.list(parts.map(\.text))
                    i = template.index(after: close)
                } else if ch == "}" {
                    if next < template.endIndex, template[next] == "}" {
                        out.append("}"); i = template.index(after: next); continue
                    }
                    return nil
                } else {
                    out.append(ch); i = next
                }
            }
            return out
        }

        private func normalized(_ path: String) -> String {
            path.hasPrefix("#.") ? String(path.dropFirst(2)) : path
        }

        // MARK: paths

        func resolve(_ path: String) -> [Value]? {
            if path.hasPrefix("@.") {
                switch path.dropFirst(2) {
                case "from": return ctx.from.map { [Value.address($0)] }
                case "to": return [.address(ctx.to)]
                case "value": return [.uint(ctx.value)]
                case "chainId": return [.uint(decimalWord(String(ctx.chainId)))]
                default: return nil
                }
            }
            guard let segments = Path.parse(normalized(path)) else { return nil }
            var current: [Value] = [.tuple(args)]
            for segment in segments {
                var next: [Value] = []
                for value in current {
                    guard let stepped = step(value, segment) else { return nil }
                    next += stepped
                }
                current = next
            }
            return current
        }

        private func step(_ value: Value, _ segment: Path.Segment) -> [Value]? {
            switch (segment, value) {
            case (.name(let n), .tuple(let members)):
                return members.first { $0.0 == n }.map { [$0.1] }
            case (.index(let i), .list(let items)):
                let at = i < 0 ? items.count + i : i
                return items.indices.contains(at) ? [items[at]] : nil
            case (.all, .list(let items)):
                return items
            case (.slice(let a, let b), .list(let items)):
                guard let r = Path.range(a, b, count: items.count) else { return nil }
                return [.list(Array(items[r]))]
            case (.slice(let a, let b), _):
                guard let bytes = value.bytes, let r = Path.range(a, b, count: bytes.count) else { return nil }
                return [.bytes(Array(bytes[r]))]
            default:
                return nil
            }
        }

        private func param(_ field: Registry.Field, _ name: String, element: Int?) -> Value? {
            if let path = field.params?[name + "Path"]?.string {
                guard let values = resolve(path), !values.isEmpty else { return nil }
                if let element, values.count > 1 { return values.indices.contains(element) ? values[element] : nil }
                return values[0]
            }
            if let constant = field.params?[name]?.string {
                return .string(constant)
            }
            return nil
        }

        private func matches(_ value: Value, _ list: [String]) -> Bool {
            let mine = value.comparable
            return list.contains { ClearSign.comparable($0) == mine }
        }

        // MARK: formats

        func format(_ value: Value, field: Registry.Field, element: Int?) -> Text? {
            let style = ctx.style
            switch field.format ?? "raw" {
            case "raw":
                return raw(value)

            case "amount":
                guard let word = value.word else { return nil }
                return Text(text: units(word, decimals: 18) + " " + nativeSymbol(ctx.chainId), clean: true)

            case "tokenAmount":
                guard let word = value.word else { return nil }
                let tokenValue = param(field, "token", element: element)
                guard let token = tokenValue?.address else {
                    return Text(text: decimal(word), clean: style.rawFallbacks)
                }
                let natives = (field.params?["nativeCurrencyAddress"]?.strings ?? []).map { $0.lowercased() }
                let known: Token?
                if natives.contains(token) {
                    known = Token(ticker: nativeSymbol(ctx.chainId), decimals: 18)
                } else {
                    known = ctx.registry.tokens["\(ctx.chainId):\(token)"] ?? style.token(token)
                }
                if let threshold = field.params?["threshold"]?.string.flatMap(ClearSign.word),
                   !less(word, threshold) {
                    let message = field.params?["message"]?.string ?? "Unlimited"
                    guard let known else { return Text(text: message + " " + name(token), clean: false) }
                    return Text(text: message + " " + known.ticker, clean: true)
                }
                guard let known else {
                    if style.rawFallbacks { return Text(text: decimal(word), clean: true) }
                    return Text(text: decimal(word) + " base units of " + name(token), clean: false)
                }
                return Text(text: units(word, decimals: known.decimals) + " " + known.ticker, clean: true)

            case "addressName":
                guard let address = value.address else { return raw(value) }
                let senders = (field.params?["senderAddress"]?.strings ?? []).map { $0.lowercased() }
                if senders.contains(address) { return Text(text: style.sender, clean: true) }
                return Text(text: name(address), clean: true)

            case "tokenTicker":
                guard let address = value.address else { return raw(value) }
                if let t = ctx.registry.tokens["\(ctx.chainId):\(address)"] ?? style.token(address) {
                    return Text(text: t.ticker, clean: true)
                }
                return Text(text: name(address), clean: false)

            case "nftName":
                guard let word = value.word else { return nil }
                let id = decimal(word)
                if let collection = param(field, "collection", element: element)?.address,
                   let title = style.collection(collection) {
                    return Text(text: "\(title) #\(id)", clean: true)
                }
                return Text(text: "#\(id)", clean: true)

            case "date":
                guard let word = value.word else { return nil }
                let n = decimal(word)
                if field.params?["encoding"]?.string == "blockheight" {
                    return Text(text: "block \(n)", clean: true)
                }
                guard let seconds = Double(n), seconds < 1e13 else { return Text(text: n, clean: false) }
                return Text(text: style.date(Date(timeIntervalSince1970: seconds)), clean: true)

            case "duration":
                guard let word = value.word, let s = Int(decimal(word)) else { return raw(value) }
                return Text(text: String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60), clean: true)

            case "unit":
                guard let word = value.word else { return nil }
                let decimals = Int(field.params?["decimals"]?.string ?? "0") ?? 0
                let base = field.params?["base"]?.string ?? ""
                if case .bool(true)? = field.params?["prefix"] {
                    return Text(text: siPrefixed(decimal(word), decimals: decimals) + base, clean: true)
                }
                return Text(text: units(word, decimals: decimals) + base, clean: true)

            case "enum":
                guard let word = value.word else { return raw(value) }
                let key = decimal(word)
                // A bool's enum is keyed however its author's tooling wrote
                // `true` — "true", "True" (Python) or "1".
                var keys = [key]
                if case .bool(let b) = value { keys += b ? ["true", "True"] : ["false", "False"] }
                if case .object(let map)? = field.params?["enum"],
                   let label = keys.lazy.compactMap({ map[$0]?.string }).first {
                    return Text(text: label, clean: true)
                }
                return Text(text: key, clean: false)

            case "chainId":
                guard let word = value.word else { return raw(value) }
                let id = decimal(word)
                return Text(text: ClearSign.chainNames[id] ?? id, clean: true)

            case "calldata":
                guard let inner = value.bytes,
                      let callee = param(field, "callee", element: element)?.address
                else { return nil }
                let amount = param(field, "amount", element: element)?.word
                let spender = param(field, "spender", element: element)?.address
                let nested = Context(chainId: ctx.chainId, to: callee, value: amount ?? zeroWord,
                                     from: spender ?? ctx.to, style: style, registry: ctx.registry)
                if let reading = ClearSign.describe(nested, data: inner, depth: depth + 1) {
                    return Text(text: reading.headline, clean: true)
                }
                if style.rawFallbacks { return Text(text: "0x" + Keccak256.hexString(inner), clean: false) }
                return Text(text: "a call to " + name(callee), clean: false)

            default:
                return raw(value)
            }
        }

        private func name(_ address: String) -> String {
            if let n = ctx.style.name(address) { return n }
            if ctx.style.namesFromRegistry {
                if let t = ctx.registry.tokens["\(ctx.chainId):\(address)"] { return t.ticker }
                if let i = ctx.registry.contracts["\(ctx.chainId):\(address)"],
                   ctx.registry.descriptors.indices.contains(i),
                   let n = ctx.registry.descriptors[i].name { return n }
            }
            return ctx.style.address(address)
        }

        private func raw(_ value: Value) -> Text? {
            switch value {
            case .uint(let w): return Text(text: decimal(w), clean: true)
            case .int(let w): return Text(text: signedDecimal(w), clean: true)
            case .address(let a): return Text(text: ctx.style.address(a), clean: true)
            case .bool(let b): return Text(text: b ? "true" : "false", clean: true)
            case .bytes(let b): return Text(text: "0x" + Keccak256.hexString(b), clean: true)
            case .string(let s): return Text(text: s, clean: true)
            case .list(let items):
                let parts = items.compactMap(raw)
                guard parts.count == items.count else { return nil }
                return Text(text: parts.map(\.text).joined(separator: ", "), clean: parts.allSatisfy(\.clean))
            case .tuple: return nil
            }
        }
    }

    // MARK: - Values

    indirect enum Value: Equatable {
        /// 32 big-endian bytes.
        case uint([UInt8])
        case int([UInt8])
        /// Lowercased, `0x`-prefixed.
        case address(String)
        case bool(Bool)
        case bytes([UInt8])
        case string(String)
        case list([Value])
        case tuple([(String, Value)])

        static func == (a: Value, b: Value) -> Bool {
            switch (a, b) {
            case (.uint(let x), .uint(let y)), (.int(let x), .int(let y)), (.bytes(let x), .bytes(let y)):
                return x == y
            case (.address(let x), .address(let y)), (.string(let x), .string(let y)): return x == y
            case (.bool(let x), .bool(let y)): return x == y
            case (.list(let x), .list(let y)): return x == y
            case (.tuple(let x), .tuple(let y)):
                return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default: return false
            }
        }

        /// As a number, when it is one — a uint, an int, a short bytes slice,
        /// or a decimal/hex constant.
        var word: [UInt8]? {
            switch self {
            case .uint(let w), .int(let w): return w
            case .bytes(let b) where b.count <= 32: return Array(repeating: 0, count: 32 - b.count) + b
            case .bool(let b): return decimalWord(b ? "1" : "0")
            case .string(let s): return ClearSign.word(s)
            default: return nil
            }
        }

        /// As an address, when it is one — including a 20-byte slice of a
        /// packed path (Uniswap's `path.[0:20]`) and a constant.
        var address: String? {
            switch self {
            case .address(let a): return a
            case .bytes(let b) where b.count == 20: return "0x" + Keccak256.hexString(b)
            case .string(let s):
                let l = s.lowercased()
                guard l.hasPrefix("0x"), l.count == 42, l.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
                return l
            case .uint(let w) where w.prefix(12).allSatisfy({ $0 == 0 }):
                return "0x" + Keccak256.hexString(Array(w.suffix(20)))
            default: return nil
            }
        }

        var bytes: [UInt8]? {
            switch self {
            case .bytes(let b): return b
            case .uint(let w), .int(let w): return w
            case .string(let s): return Array(s.utf8)
            default: return nil
            }
        }

        /// The form `ifNotIn`/`mustMatch` compare in.
        var comparable: String {
            switch self {
            case .address(let a): return a
            case .uint(let w): return decimal(w)
            case .int(let w): return signedDecimal(w)
            case .bool(let b): return b ? "true" : "false"
            case .bytes(let b): return "0x" + Keccak256.hexString(b)
            case .string(let s): return ClearSign.comparable(s)
            default: return ""
            }
        }
    }

    /// "a", "a and b", "a, b and c" — an array read inside a sentence.
    fileprivate static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    fileprivate static func comparable(_ constant: String) -> String {
        let l = constant.lowercased()
        if l.hasPrefix("0x"), l.count == 42 { return l }
        if let w = word(constant) { return decimal(w) }
        return constant
    }

    // MARK: - Function keys

    /// A `display.formats` key — `name(type name,(type a,type b) p)` —
    /// parsed into its types and names. Spaces after commas are tolerated
    /// (the spec forbids them; the registry has them).
    struct Function {
        let name: String
        let params: [ABI.Param]
        let selector: [UInt8]

        init?(key: String) {
            guard let open = key.firstIndex(of: "("), key.hasSuffix(")") else { return nil }
            name = String(key[..<open]).trimmingCharacters(in: .whitespaces)
            var parser = ABI.Parser(Array(key[key.index(after: open)...]))
            guard let list = parser.paramList(), parser.atEnd else { return nil }
            params = list
            let signature = name + "(" + list.map(\.type.canonical).joined(separator: ",") + ")"
            selector = Array(Keccak256.hash(Array(signature.utf8)).prefix(4))
        }
    }

    enum ABI {
        indirect enum Kind: Equatable {
            case uint(Int), int(Int), address, bool, fixedBytes(Int), bytes, string
            case array(Kind), fixedArray(Kind, Int), tuple([Param])

            var canonical: String {
                switch self {
                case .uint(let n): return "uint\(n)"
                case .int(let n): return "int\(n)"
                case .address: return "address"
                case .bool: return "bool"
                case .fixedBytes(let n): return "bytes\(n)"
                case .bytes: return "bytes"
                case .string: return "string"
                case .array(let k): return k.canonical + "[]"
                case .fixedArray(let k, let n): return k.canonical + "[\(n)]"
                case .tuple(let ps): return "(" + ps.map(\.type.canonical).joined(separator: ",") + ")"
                }
            }

            var isDynamic: Bool {
                switch self {
                case .bytes, .string, .array: return true
                case .fixedArray(let k, _): return k.isDynamic
                case .tuple(let ps): return ps.contains { $0.type.isDynamic }
                default: return false
                }
            }

            /// Bytes this type takes in its parent's head.
            var headSize: Int {
                if isDynamic { return 32 }
                switch self {
                case .fixedArray(let k, let n): return k.headSize * n
                case .tuple(let ps): return ps.reduce(0) { $0 + $1.type.headSize }
                default: return 32
                }
            }
        }

        struct Param: Equatable {
            let name: String
            let type: Kind
        }

        struct Parser {
            let chars: [Character]
            var i = 0
            init(_ chars: [Character]) { self.chars = chars }

            var atEnd: Bool { i == chars.count }

            mutating func skipSpace() { while i < chars.count, chars[i] == " " { i += 1 } }

            /// After the opening `(`: params up to and including `)`.
            mutating func paramList() -> [Param]? {
                var out: [Param] = []
                skipSpace()
                if i < chars.count, chars[i] == ")" { i += 1; return out }
                while true {
                    skipSpace()
                    guard let p = param() else { return nil }
                    out.append(p)
                    skipSpace()
                    guard i < chars.count else { return nil }
                    if chars[i] == "," { i += 1; continue }
                    if chars[i] == ")" { i += 1; return out }
                    return nil
                }
            }

            mutating func param() -> Param? {
                var kind: Kind
                if i < chars.count, chars[i] == "(" {
                    i += 1
                    guard let members = paramList() else { return nil }
                    kind = .tuple(members)
                } else {
                    let start = i
                    while i < chars.count, chars[i].isLetter || chars[i].isNumber { i += 1 }
                    guard let base = Self.elementary(String(chars[start..<i])) else { return nil }
                    kind = base
                }
                while i < chars.count, chars[i] == "[" {
                    i += 1
                    let start = i
                    while i < chars.count, chars[i].isNumber { i += 1 }
                    let digits = String(chars[start..<i])
                    guard i < chars.count, chars[i] == "]" else { return nil }
                    i += 1
                    if digits.isEmpty { kind = .array(kind) }
                    else { guard let n = Int(digits), n > 0, n <= 1024 else { return nil }; kind = .fixedArray(kind, n) }
                }
                skipSpace()
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$" { i += 1 }
                let name = String(chars[start..<i])
                // `calldata`/`memory` data locations are not part of a fragment,
                // but a name must not swallow one silently.
                return Param(name: name, type: kind)
            }

            static func elementary(_ s: String) -> Kind? {
                switch s {
                case "address": return .address
                case "bool": return .bool
                case "bytes": return .bytes
                case "string": return .string
                case "uint": return .uint(256)
                case "int": return .int(256)
                default: break
                }
                if s.hasPrefix("uint"), let n = Int(s.dropFirst(4)), n % 8 == 0, (8...256).contains(n) { return .uint(n) }
                if s.hasPrefix("int"), let n = Int(s.dropFirst(3)), n % 8 == 0, (8...256).contains(n) { return .int(n) }
                if s.hasPrefix("bytes"), let n = Int(s.dropFirst(5)), (1...32).contains(n) { return .fixedBytes(n) }
                return nil
            }
        }

        /// The most elements one array may claim before the decode is refused.
        static let maxElements = 4096

        /// Decodes the arguments, or nil. Every bound is a SUBTRACTION from a
        /// real count — `SafeCalldata.batchCalls`'s rule, because `a + b`
        /// traps on a crafted offset and these bytes are anyone's proposal.
        static func decode(_ params: [Param], _ data: [UInt8]) -> [(String, Value)]? {
            var budget = maxElements * 4
            guard case .tuple(let members)? = decode(.tuple(params), data, at: 0, budget: &budget, depth: 0)
            else { return nil }
            return members
        }

        private static func decode(_ kind: Kind, _ data: [UInt8], at: Int,
                                   budget: inout Int, depth: Int) -> Value? {
            guard depth < 32, at >= 0 else { return nil }
            budget -= 1
            guard budget > 0 else { return nil }
            switch kind {
            case .uint(let n):
                guard let w = word(data, at) else { return nil }
                guard w.prefix(32 - n / 8).allSatisfy({ $0 == 0 }) else { return nil }
                return .uint(w)
            case .int:
                guard let w = word(data, at) else { return nil }
                return .int(w)
            case .address:
                guard let w = word(data, at), w.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
                return .address("0x" + Keccak256.hexString(Array(w.suffix(20))))
            case .bool:
                guard let w = word(data, at), w.prefix(31).allSatisfy({ $0 == 0 }), w[31] <= 1 else { return nil }
                return .bool(w[31] == 1)
            case .fixedBytes(let n):
                guard let w = word(data, at) else { return nil }
                return .bytes(Array(w.prefix(n)))
            case .bytes, .string:
                guard let length = int(data, at), length <= data.count - at - 32 else { return nil }
                let body = Array(data[(at + 32)..<(at + 32 + length)])
                if kind == .string { return .string(String(decoding: body, as: UTF8.self)) }
                return .bytes(body)
            case .array(let element):
                guard let count = int(data, at), count <= maxElements,
                      count <= (data.count - at - 32) / 32 + 1
                else { return nil }
                return list(element, count, data, base: at + 32, budget: &budget, depth: depth)
            case .fixedArray(let element, let count):
                return list(element, count, data, base: at, budget: &budget, depth: depth)
            case .tuple(let params):
                var out: [(String, Value)] = []
                var head = 0
                for p in params {
                    guard head <= data.count - at else { return nil }
                    let position = at + head
                    let value: Value?
                    if p.type.isDynamic {
                        guard let offset = int(data, position), offset <= data.count - at else { return nil }
                        value = decode(p.type, data, at: at + offset, budget: &budget, depth: depth + 1)
                    } else {
                        value = decode(p.type, data, at: position, budget: &budget, depth: depth + 1)
                    }
                    guard let value else { return nil }
                    out.append((p.name, value))
                    head += p.type.headSize
                }
                return .tuple(out)
            }
        }

        private static func list(_ element: Kind, _ count: Int, _ data: [UInt8], base: Int,
                                 budget: inout Int, depth: Int) -> Value? {
            guard base <= data.count else { return count == 0 ? .list([]) : nil }
            let members = (0..<count).map { Param(name: String($0), type: element) }
            guard case .tuple(let decoded)? = decode(.tuple(members), data, at: base,
                                                     budget: &budget, depth: depth + 1)
            else { return nil }
            return .list(decoded.map(\.1))
        }

        private static func word(_ data: [UInt8], _ at: Int) -> [UInt8]? {
            guard at >= 0, at <= data.count - 32 else { return nil }
            return Array(data[at..<(at + 32)])
        }

        /// A length or offset word, refused past 32 bits — no real calldata is
        /// four gigabytes long.
        private static func int(_ data: [UInt8], _ at: Int) -> Int? {
            guard let w = word(data, at), w.prefix(28).allSatisfy({ $0 == 0 }) else { return nil }
            return w.suffix(4).reduce(0) { $0 << 8 | Int($1) }
        }
    }

    // MARK: - Paths

    enum Path {
        enum Segment: Equatable {
            case name(String), index(Int), all, slice(Int?, Int?)
        }

        /// `a.b.[0].c.[-20:]`, and the spec's own shorthand `a[0]`.
        static func parse(_ path: String) -> [Segment]? {
            var out: [Segment] = []
            for raw in path.split(separator: ".", omittingEmptySubsequences: false) {
                var part = Substring(raw)
                if let open = part.firstIndex(of: "["), open != part.startIndex {
                    out.append(.name(String(part[..<open])))
                    part = part[open...]
                }
                if part.hasPrefix("[") {
                    guard part.hasSuffix("]") else { return nil }
                    let inner = part.dropFirst().dropLast()
                    if inner.isEmpty { out.append(.all); continue }
                    if let colon = inner.firstIndex(of: ":") {
                        let a = inner[..<colon], b = inner[inner.index(after: colon)...]
                        guard a.isEmpty || Int(a) != nil, b.isEmpty || Int(b) != nil else { return nil }
                        out.append(.slice(a.isEmpty ? nil : Int(a), b.isEmpty ? nil : Int(b)))
                    } else {
                        guard let n = Int(inner) else { return nil }
                        out.append(.index(n))
                    }
                } else {
                    guard !part.isEmpty else { return nil }
                    out.append(.name(String(part)))
                }
            }
            return out
        }

        static func range(_ a: Int?, _ b: Int?, count: Int) -> Range<Int>? {
            func clamp(_ x: Int) -> Int { x < 0 ? max(0, count + x) : min(x, count) }
            let lo = a.map(clamp) ?? 0, hi = b.map(clamp) ?? count
            return lo <= hi ? lo..<hi : nil
        }
    }

    // MARK: - Numbers

    fileprivate static let zeroWord = [UInt8](repeating: 0, count: 32)

    /// A uint256 as a decimal string. Long division, because no Swift integer
    /// holds one.
    fileprivate static func decimal(_ word: [UInt8]) -> String {
        var digits = word
        var out = ""
        while digits.contains(where: { $0 != 0 }) {
            var remainder = 0
            for i in digits.indices {
                let current = remainder * 256 + Int(digits[i])
                digits[i] = UInt8(current / 10)
                remainder = current % 10
            }
            out = String(remainder) + out
        }
        return out.isEmpty ? "0" : out
    }

    fileprivate static func signedDecimal(_ word: [UInt8]) -> String {
        guard let top = word.first, top & 0x80 != 0 else { return decimal(word) }
        // Two's complement: invert and add one.
        var inverted = word.map { ~$0 }
        for i in inverted.indices.reversed() {
            let (sum, overflow) = inverted[i].addingReportingOverflow(1)
            inverted[i] = sum
            if !overflow { break }
        }
        return "-" + decimal(inverted)
    }

    /// A decimal string as 32 big-endian bytes (zero on anything else).
    fileprivate static func decimalWord(_ s: String) -> [UInt8] {
        word(s) ?? zeroWord
    }

    /// A `0x` hex or decimal constant as 32 bytes, or nil.
    fileprivate static func word(_ s: String) -> [UInt8]? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("0x") {
            var hex = String(t.dropFirst(2))
            guard !hex.isEmpty, hex.count <= 64, hex.allSatisfy(\.isHexDigit) else { return nil }
            if hex.count % 2 == 1 { hex = "0" + hex }
            var bytes: [UInt8] = []
            var i = hex.startIndex
            while i < hex.endIndex {
                let j = hex.index(i, offsetBy: 2)
                bytes.append(UInt8(hex[i..<j], radix: 16) ?? 0)
                i = j
            }
            return Array(repeating: 0, count: 32 - bytes.count) + bytes
        }
        guard !t.isEmpty, t.allSatisfy(\.isNumber) else { return nil }
        var out = zeroWord
        for ch in t {
            guard let d = ch.wholeNumberValue else { return nil }
            var carry = d
            for i in out.indices.reversed() {
                let v = Int(out[i]) * 10 + carry
                out[i] = UInt8(v & 0xff)
                carry = v >> 8
            }
            guard carry == 0 else { return nil }
        }
        return out
    }

    fileprivate static func less(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return x < y }
        return false
    }

    /// `value / 10^decimals`, exactly, trailing zeros trimmed.
    fileprivate static func units(_ word: [UInt8], decimals: Int) -> String {
        shift(decimal(word), decimals: decimals)
    }

    fileprivate static func shift(_ digits: String, decimals: Int) -> String {
        guard decimals > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let cut = padded.index(padded.endIndex, offsetBy: -decimals)
        var fraction = String(padded[cut...])
        while fraction.hasSuffix("0") { fraction.removeLast() }
        let whole = String(padded[..<cut])
        return fraction.isEmpty ? whole : whole + "." + fraction
    }

    /// `unit` with `prefix: true` — the value scaled to an SI prefix.
    fileprivate static func siPrefixed(_ digits: String, decimals: Int) -> String {
        let prefixes: [(Int, String)] = [(24, "Y"), (21, "Z"), (18, "E"), (15, "P"), (12, "T"),
                                         (9, "G"), (6, "M"), (3, "k")]
        let magnitude = digits.count - 1 - decimals
        for (exp, symbol) in prefixes where magnitude >= exp {
            return shift(digits, decimals: decimals + exp) + symbol
        }
        return shift(digits, decimals: decimals)
    }

    fileprivate static func nativeSymbol(_ chainId: Int) -> String {
        switch chainId {
        case 100: return "xDAI"
        case 137: return "POL"
        case 56: return "BNB"
        case 43114: return "AVAX"
        default: return "ETH"
        }
    }

    fileprivate static let chainNames: [String: String] = [
        "1": "Ethereum", "10": "OP Mainnet", "56": "BNB Chain", "100": "Gnosis",
        "137": "Polygon", "8453": "Base", "42161": "Arbitrum One", "43114": "Avalanche",
        "59144": "Linea", "534352": "Scroll", "480": "World Chain",
    ]

    /// `2026-04-03 07:06:40Z` — the registry's own test form.
    static func utcStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date) + "Z"
    }
}
