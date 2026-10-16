import Foundation

/// A reader for Yjs documents (prd §1346) — enough of Yjs to open a Fileverse
/// dDoc, which is a Yjs update holding the editor's ProseMirror tree in the
/// XmlFragment "default". Read-only: it decodes an update (format v1), replays
/// Yjs's own ordering rule over it, and exports the visible tree. It never
/// encodes, so it cannot write a document back.
///
/// WHY NATIVE. Yjs is a CRDT: the bytes hold every insert with the two
/// neighbours it was typed between (`origin`, `rightOrigin`), and the order on
/// screen exists only after the YATA integration rule runs over them. So a
/// reader is a decoder AND that rule. It is ported from yjs 13.6
/// (`src/structs/Item.js` `integrate`, `src/utils/UpdateDecoder.js`, lib0's
/// `decoding.js`), and `fileverse-selftest.sh` holds it to 160 edit histories
/// the real library wrote (concurrent clients, deletes, formats, emoji), so a
/// divergence fails a check instead of reordering somebody's words.
///
/// ONE UNIT PER CLOCK. Yjs stores a run of characters as one struct and splits
/// it when a later insert lands inside. This reader splits every struct into
/// length-one units up front (a unit's origin is its predecessor, its right
/// origin the run's), which is exactly what Yjs's own split produces, and so
/// never needs the split logic. A 30,000-character document is 30,000 units.
enum Yjs {
    // MARK: - The exported tree

    /// What a document reads as: elements with attributes and children, and
    /// text as runs with their formatting.
    indirect enum Node: Equatable {
        case element(name: String, attrs: [String: Value], children: [Node])
        case text([Run])
    }

    struct Run: Equatable {
        /// The run's text, or nil for an embed.
        var text: String?
        var embed: Value?
        var attributes: [String: Value]
    }

    /// A JSON-shaped value (lib0's `any`).
    indirect enum Value: Equatable {
        case null
        case undefined
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([Value])
        case object([String: Value])
        case bytes(Data)

        var string: String? { if case .string(let s) = self { return s }; return nil }
        var number: Double? { if case .number(let n) = self { return n }; return nil }
        var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    }

    enum Failure: Error, Equatable {
        case truncated
        case badContent(UInt8)
        case badTypeRef(UInt64)
        case badAny(UInt8)
        case badJSON
        case missingDependency
    }

    /// Reads a full-state update and returns the root type's children.
    static func read(update: Data, root: String = "default") throws -> [Node] {
        var doc = Doc()
        try doc.apply(update)
        return doc.export(root: root)
    }

    // MARK: - lib0 decoding

    struct Decoder {
        let bytes: [UInt8]
        var pos = 0
        init(_ data: Data) { bytes = [UInt8](data) }

        mutating func uint8() throws -> UInt8 {
            guard pos < bytes.count else { throw Failure.truncated }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func varUint() throws -> UInt64 {
            var num: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let r = try uint8()
                num |= UInt64(r & 0x7f) << shift
                shift += 7
                if r < 0x80 { return num }
                if shift > 63 { throw Failure.truncated }
            }
        }

        mutating func varInt() throws -> Int64 {
            var r = try uint8()
            var num = Int64(r & 0x3f)
            var shift: Int64 = 6
            let negative = r & 0x40 != 0
            while r & 0x80 != 0 {
                r = try uint8()
                num |= Int64(r & 0x7f) << shift
                shift += 7
                if shift > 63 { throw Failure.truncated }
            }
            return negative ? -num : num
        }

        mutating func raw(_ n: Int) throws -> [UInt8] {
            guard n >= 0, pos + n <= bytes.count else { throw Failure.truncated }
            defer { pos += n }
            return Array(bytes[pos..<(pos + n)])
        }

        mutating func varBytes() throws -> [UInt8] { try raw(Int(try varUint())) }

        mutating func varString() throws -> String {
            String(decoding: try varBytes(), as: UTF8.self)
        }

        mutating func json() throws -> Value {
            let s = try varString()
            if s == "undefined" { return .undefined }
            guard let data = s.data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw Failure.badJSON
            }
            return Value(json: any)
        }

        /// lib0 `readAny`: a type byte counted down from 127.
        mutating func any() throws -> Value {
            let t = try uint8()
            switch t {
            case 127: return .undefined
            case 126: return .null
            case 125: return .number(Double(try varInt()))
            case 124:
                let b = try raw(4)
                return .number(Double(Float(bitPattern: UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))))
            case 123:
                let b = try raw(8)
                var bits: UInt64 = 0
                for x in b { bits = bits << 8 | UInt64(x) }
                return .number(Double(bitPattern: bits))
            case 122:
                let b = try raw(8)
                var bits: UInt64 = 0
                for x in b { bits = bits << 8 | UInt64(x) }
                return .number(Double(Int64(bitPattern: bits)))
            case 121: return .bool(false)
            case 120: return .bool(true)
            case 119: return .string(try varString())
            case 118:
                var o: [String: Value] = [:]
                for _ in 0..<(try varUint()) {
                    let k = try varString()
                    o[k] = try any()
                }
                return .object(o)
            case 117:
                var a: [Value] = []
                for _ in 0..<(try varUint()) { a.append(try any()) }
                return .array(a)
            case 116: return .bytes(Data(try varBytes()))
            default: throw Failure.badAny(t)
            }
        }
    }

    // MARK: - Structs

    struct ID: Hashable, Comparable {
        let client: UInt64
        let clock: UInt64
        static func < (a: ID, b: ID) -> Bool { a.client == b.client ? a.clock < b.clock : a.client < b.client }
    }

    enum TypeRef: Equatable {
        case array, map, text, xmlElement(String), xmlFragment, xmlHook(String), xmlText
    }

    /// One unit's content. Strings arrive one UTF-16 code unit per unit.
    enum Content {
        case deleted
        case json(Value)
        case binary
        case char(UInt16)
        case embed(Value)
        case format(key: String, value: Value)
        case type(TypeRef)
        case any(Value)
        case doc

        var countable: Bool {
            switch self {
            case .format: return false
            case .deleted: return false
            default: return true
            }
        }
    }

    enum Parent: Hashable {
        case root(String)
        case item(ID)
    }

    final class Item {
        let id: ID
        let origin: ID?
        let rightOrigin: ID?
        var parent: Parent?
        var parentSub: String?
        let content: Content
        var deleted = false
        var integrated = false
        var gc = false
        weak var left: Item?
        var right: Item?

        init(id: ID, origin: ID?, rightOrigin: ID?, parent: Parent?, parentSub: String?, content: Content) {
            self.id = id
            self.origin = origin
            self.rightOrigin = rightOrigin
            self.parent = parent
            self.parentSub = parentSub
            self.content = content
            if case .deleted = content { deleted = true }
        }
    }

    /// A type's children: the sequence (`start`) and the map entries.
    final class TypeState {
        var start: Item?
        var map: [String: Item] = [:]
    }

    // MARK: - The document

    struct Doc {
        private(set) var items: [ID: Item] = [:]
        /// Clocks a GC or Skip struct covers: present, but never content.
        private var collected: [UInt64: [(UInt64, UInt64)]] = [:]
        private var types: [Parent: TypeState] = [:]
        private var order: [ID] = []

        mutating func apply(_ update: Data) throws {
            var d = Decoder(update)
            try readStructs(&d)
            let deletes = try readDeleteSet(&d)
            try integrateAll()
            for (client, ranges) in deletes {
                for (clock, len) in ranges {
                    for c in clock..<(clock + len) { items[ID(client: client, clock: c)]?.deleted = true }
                }
            }
        }

        private func isCollected(_ id: ID) -> Bool {
            collected[id.client]?.contains { id.clock >= $0.0 && id.clock < $0.0 + $0.1 } ?? false
        }

        private mutating func readStructs(_ d: inout Decoder) throws {
            let clients = try d.varUint()
            for _ in 0..<clients {
                let count = try d.varUint()
                let client = try d.varUint()
                var clock = try d.varUint()
                for _ in 0..<count {
                    let info = try d.uint8()
                    switch info & 0x1f {
                    case 0, 10: // GC, Skip
                        let len = try d.varUint()
                        collected[client, default: []].append((clock, len))
                        clock += len
                    default:
                        let hasOrigin = info & 0x80 != 0
                        let hasRight = info & 0x40 != 0
                        let origin = hasOrigin ? ID(client: try d.varUint(), clock: try d.varUint()) : nil
                        let right = hasRight ? ID(client: try d.varUint(), clock: try d.varUint()) : nil
                        let cantCopyParent = !hasOrigin && !hasRight
                        var parent: Parent?
                        var parentSub: String?
                        if cantCopyParent {
                            if try d.varUint() == 1 {
                                parent = .root(try d.varString())
                            } else {
                                parent = .item(ID(client: try d.varUint(), clock: try d.varUint()))
                            }
                            if info & 0x20 != 0 { parentSub = try d.varString() }
                        }
                        let contents = try readContent(&d, ref: info & 0x1f)
                        for (i, content) in contents.enumerated() {
                            let id = ID(client: client, clock: clock + UInt64(i))
                            // A run split at i: the unit's origin is its
                            // predecessor; the right origin is the run's.
                            let o = i == 0 ? origin : ID(client: client, clock: clock + UInt64(i) - 1)
                            let item = Item(id: id, origin: o, rightOrigin: right, parent: parent,
                                            parentSub: parentSub, content: content)
                            items[id] = item
                            order.append(id)
                        }
                        clock += UInt64(contents.count)
                    }
                }
            }
        }

        private func readContent(_ d: inout Decoder, ref: UInt8) throws -> [Content] {
            switch ref {
            case 1: return Array(repeating: .deleted, count: Int(try d.varUint()))
            case 2:
                let n = try d.varUint()
                var out: [Content] = []
                for _ in 0..<n { out.append(.json(try d.json())) }
                return out
            case 3: _ = try d.varBytes(); return [.binary]
            case 4: return try d.varString().utf16.map { .char($0) }
            case 5: return [.embed(try d.json())]
            case 6:
                let key = try d.varString()
                return [.format(key: key, value: try d.json())]
            case 7:
                let t = try d.varUint()
                switch t {
                case 0: return [.type(.array)]
                case 1: return [.type(.map)]
                case 2: return [.type(.text)]
                case 3: return [.type(.xmlElement(try d.varString()))]
                case 4: return [.type(.xmlFragment)]
                case 5: return [.type(.xmlHook(try d.varString()))]
                case 6: return [.type(.xmlText)]
                default: throw Failure.badTypeRef(t)
                }
            case 8:
                let n = try d.varUint()
                var out: [Content] = []
                for _ in 0..<n { out.append(.any(try d.any())) }
                return out
            case 9:
                _ = try d.varString()
                _ = try d.any()
                return [.doc]
            default: throw Failure.badContent(ref)
            }
        }

        private func readDeleteSet(_ d: inout Decoder) throws -> [UInt64: [(UInt64, UInt64)]] {
            var out: [UInt64: [(UInt64, UInt64)]] = [:]
            guard d.pos < d.bytes.count else { return out }
            for _ in 0..<(try d.varUint()) {
                let client = try d.varUint()
                for _ in 0..<(try d.varUint()) {
                    out[client, default: []].append((try d.varUint(), try d.varUint()))
                }
            }
            return out
        }

        // MARK: Integration (yjs `Item.integrate`)

        private func dependencies(_ item: Item) -> [ID] {
            var deps: [ID] = []
            if item.id.clock > 0 { deps.append(ID(client: item.id.client, clock: item.id.clock - 1)) }
            if let o = item.origin { deps.append(o) }
            if let r = item.rightOrigin { deps.append(r) }
            if case .item(let p) = item.parent { deps.append(p) }
            return deps
        }

        private mutating func integrateAll() throws {
            for id in order.sorted() {
                guard let first = items[id], !first.integrated else { continue }
                var stack = [first]
                var guardCount = 0
                while let top = stack.last {
                    guardCount += 1
                    if guardCount > items.count * 8 + 64 { throw Failure.missingDependency }
                    if top.integrated { stack.removeLast(); continue }
                    let all = items
                    if let missing = dependencies(top).compactMap({ all[$0] }).first(where: { !$0.integrated }) {
                        stack.append(missing)
                        continue
                    }
                    integrate(top)
                    stack.removeLast()
                }
            }
        }

        /// The unit an ID names, or nil when a GC or Skip struct covers it (or
        /// nothing does).
        private func unit(_ id: ID?) -> Item? { id.flatMap { items[$0] } }

        private mutating func state(_ p: Parent) -> TypeState {
            if let s = types[p] { return s }
            let s = TypeState()
            types[p] = s
            return s
        }

        private mutating func integrate(_ item: Item) {
            item.integrated = true
            var left = unit(item.origin)
            let right = unit(item.rightOrigin)
            // A neighbour that was garbage-collected takes the item with it.
            let leftGone = item.origin.map { items[$0] == nil || isCollected($0) || items[$0]!.gc } ?? false
            let rightGone = item.rightOrigin.map { items[$0] == nil || isCollected($0) || items[$0]!.gc } ?? false
            if leftGone || rightGone {
                item.gc = true
                item.parent = nil
                return
            }
            if item.parent == nil {
                if let l = left, l.parent != nil {
                    item.parent = l.parent
                    item.parentSub = l.parentSub
                } else if let r = right, r.parent != nil {
                    item.parent = r.parent
                    item.parentSub = r.parentSub
                }
            } else if case .item(let pid) = item.parent!, items[pid] == nil || items[pid]!.gc {
                item.gc = true
                item.parent = nil
                return
            }
            guard let parent = item.parent else {
                item.gc = true
                return
            }
            let type = state(parent)
            item.left = left
            item.right = right

            if (left == nil && (right == nil || right!.left != nil)) || (left != nil && left!.right !== right) {
                var o: Item?
                if let l = left {
                    o = l.right
                } else if let sub = item.parentSub {
                    o = type.map[sub]
                    while let ol = o?.left { o = ol }
                } else {
                    o = type.start
                }
                var conflicting = Set<ObjectIdentifier>()
                var beforeOrigin = Set<ObjectIdentifier>()
                while let cur = o, cur !== right {
                    beforeOrigin.insert(ObjectIdentifier(cur))
                    conflicting.insert(ObjectIdentifier(cur))
                    if item.origin == cur.origin {
                        if cur.id.client < item.id.client {
                            left = cur
                            conflicting.removeAll()
                        } else if item.rightOrigin == cur.rightOrigin {
                            break
                        }
                    } else if let co = cur.origin, let coItem = items[co], beforeOrigin.contains(ObjectIdentifier(coItem)) {
                        if !conflicting.contains(ObjectIdentifier(coItem)) {
                            left = cur
                            conflicting.removeAll()
                        }
                    } else {
                        break
                    }
                    o = cur.right
                }
                item.left = left
            }

            if let l = item.left {
                item.right = l.right
                l.right = item
            } else {
                var r: Item?
                if let sub = item.parentSub {
                    r = type.map[sub]
                    while let rl = r?.left { r = rl }
                } else {
                    r = type.start
                    type.start = item
                }
                item.right = r
            }
            if let r = item.right {
                r.left = item
            } else if let sub = item.parentSub {
                type.map[sub] = item
                item.left?.deleted = true
            }
        }

        // MARK: Export

        func export(root: String) -> [Node] {
            children(of: .root(root))
        }

        private func children(of p: Parent) -> [Node] {
            guard let type = types[p] else { return [] }
            var out: [Node] = []
            var cur = type.start
            while let item = cur {
                if !item.deleted, !item.gc, case .type(let ref) = item.content {
                    out.append(node(item, ref))
                }
                cur = item.right
            }
            return out
        }

        private func node(_ item: Item, _ ref: TypeRef) -> Node {
            let p = Parent.item(item.id)
            switch ref {
            case .xmlText, .text:
                return .text(runs(of: p))
            case .xmlElement(let name):
                return .element(name: name, attrs: attributes(of: p), children: children(of: p))
            case .xmlHook(let name):
                return .element(name: name, attrs: attributes(of: p), children: [])
            default:
                return .element(name: "\(ref)", attrs: [:], children: children(of: p))
            }
        }

        private func attributes(of p: Parent) -> [String: Value] {
            guard let type = types[p] else { return [:] }
            var out: [String: Value] = [:]
            for (key, item) in type.map where !item.deleted && !item.gc {
                switch item.content {
                case .any(let v), .json(let v): out[key] = v
                case .embed(let v): out[key] = v
                default: break
                }
            }
            return out
        }

        /// Yjs `toDelta`: characters gathered into runs under the formats in
        /// force, an embed as a run of its own.
        private func runs(of p: Parent) -> [Run] {
            guard let type = types[p] else { return [] }
            var out: [Run] = []
            var attrs: [String: Value] = [:]
            var units: [UInt16] = []
            func flush() {
                guard !units.isEmpty else { return }
                out.append(Run(text: String(decoding: units, as: UTF16.self), embed: nil, attributes: attrs))
                units.removeAll()
            }
            var cur = type.start
            while let item = cur {
                if !item.deleted, !item.gc {
                    switch item.content {
                    case .char(let u):
                        units.append(u)
                    case .embed(let v):
                        flush()
                        out.append(Run(text: nil, embed: v, attributes: attrs))
                    case .format(let key, let value):
                        flush()
                        if value == .null { attrs.removeValue(forKey: key) } else { attrs[key] = value }
                    default:
                        break
                    }
                }
                cur = item.right
            }
            flush()
            // Adjacent runs under equal formats are one (a format that was set
            // and unset in place splits nothing in Yjs's delta).
            var merged: [Run] = []
            for r in out {
                if let last = merged.last, last.text != nil, r.text != nil, last.attributes == r.attributes {
                    merged[merged.count - 1].text! += r.text!
                } else {
                    merged.append(r)
                }
            }
            return merged
        }
    }
}

extension Yjs.Value {
    init(json: Any) {
        switch json {
        case is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(Yjs.Value.init(json:)))
        case let o as [String: Any]: self = .object(o.mapValues(Yjs.Value.init(json:)))
        default: self = .undefined
        }
    }
}
