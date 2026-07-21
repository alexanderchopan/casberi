import Testing
@testable import Casberi

/// Regression coverage for the gen UI document parser (brief §5) — the app
/// had none (CLAUDE.md: "the GenParser tests from early sessions were never
/// persisted"). `parseIncrementalMatchesFullParse` specifically protects the
/// 2026-07-15 incremental-parsing optimization (GenStream/GenParser): the
/// incremental path must produce byte-identical results to a full reparse at
/// every possible streaming cursor position, or the typewriter would render
/// wrong.
struct GenParserTests {

    // MARK: - parseArgs

    @Test func parseArgsSplitsBareTokens() {
        let args = GenParser.parseArgs("red, 3, quiet")
        #expect(args.map(\.stringValue) == ["red", "3", "quiet"])
    }

    @Test func parseArgsHandlesQuotedStrings() {
        let args = GenParser.parseArgs(#""Hello, world", "second""#)
        #expect(args.count == 2)
        #expect(args[0].stringValue == "Hello, world")
        #expect(args[1].stringValue == "second")
    }

    @Test func parseArgsHandlesPartialTrailingString() {
        // No closing quote — a string still fills as its tokens arrive
        // (the mount law: a partial line still mounts its component).
        let args = GenParser.parseArgs(#""still typin"#)
        #expect(args.count == 1)
        #expect(args[0].stringValue == "still typin")
    }

    @Test func parseArgsHandlesNull() {
        let args = GenParser.parseArgs(#""a", null, "b""#)
        #expect(args.count == 3)
        #expect(args[1] == .null)
    }

    @Test func parseArgsHandlesRefsArray() {
        let args = GenParser.parseArgs(#""Title", [child0, child1, child2]"#)
        #expect(args.count == 2)
        #expect(args[1].refsValue == ["child0", "child1", "child2"])
    }

    @Test func parseArgsCommaInsideBracketsDoesNotSplit() {
        let args = GenParser.parseArgs(#"[a, b, c], "after""#)
        #expect(args.count == 2)
        #expect(args[0].refsValue == ["a", "b", "c"])
        #expect(args[1].stringValue == "after")
    }

    // MARK: - parse (whole-prefix)

    private static let sampleDoc = [
        "root = Stack([hero, map])",
        "hero = Hero(\"Getting started\", \"Your home builds itself\", \"Connect an app\")",
        "map = TagMap(\"What's going on\", null, [Links 3, Notes 2])",
    ]

    @Test func parseCompleteDocumentMountsEveryLine() {
        let doc = Self.sampleDoc.joined(separator: "\n")
        let els = GenParser.parse(prefix: doc[...], isComplete: true)
        #expect(els.count == 3)
        #expect(els["root"]?.comp == "Stack")
        #expect(els["hero"]?.comp == "Hero")
        #expect(els["hero"]?.str(0) == "Getting started")
        #expect(els["map"]?.refs(2) == ["Links 3", "Notes 2"])
    }

    @Test func parsePartialLastLineStillMounts() {
        let doc = Self.sampleDoc.joined(separator: "\n")
        // Cut the doc mid-way through the third line's first argument —
        // "map" should still mount with what's arrived of its args so far.
        let cursor = doc.range(of: "What's go")!.upperBound
        let prefix = doc[doc.startIndex..<cursor]
        let els = GenParser.parse(prefix: prefix, isComplete: false)
        #expect(els["root"] != nil)   // earlier complete lines still present
        #expect(els["hero"] != nil)
        #expect(els["map"]?.comp == "TagMap")
        #expect(els["map"]?.str(0) == "What's go")
    }

    @Test func parseEmptyPrefixMountsNothing() {
        let els = GenParser.parse(prefix: ""[...], isComplete: false)
        #expect(els.isEmpty)
    }

    // MARK: - parseIncremental ≡ parse, at every cursor position

    /// The property the 2026-07-15 optimization depends on: streaming a
    /// document character-by-character through `parseIncremental` (reusing
    /// its cache across calls, exactly as `GenStream` does tick by tick)
    /// must land on the SAME `GenEls` as calling `parse` fresh at every one
    /// of those same prefix lengths.
    @Test func parseIncrementalMatchesFullParse() {
        let doc = Self.sampleDoc.joined(separator: "\n")
        var cache: GenEls = [:]
        var cachedCompleteLines = 0

        for cursor in stride(from: 1, through: doc.count, by: 1) {
            let prefix = doc.prefix(cursor)
            let isComplete = cursor >= doc.count
            let incremental = GenParser.parseIncremental(
                prefix: prefix, isComplete: isComplete,
                cache: &cache, cachedCompleteLines: &cachedCompleteLines)
            let full = GenParser.parse(prefix: prefix, isComplete: isComplete)
            #expect(incremental == full, "mismatch at cursor \(cursor)")
        }
    }

    @Test func parseIncrementalCacheResetsCleanlyAcrossDocuments() {
        // GenStream resets `cache`/`cachedCompleteLines` to `[:]`/`0` on
        // every `stream(_:)`/`paint(_:)` call — simulate a second, unrelated
        // document reusing the same (freshly reset) cache and confirm it
        // isn't polluted by the first document's ids.
        let first = "a = Hero(\"one\")"
        var cache: GenEls = [:]
        var cachedCompleteLines = 0
        _ = GenParser.parseIncremental(prefix: first[...], isComplete: true,
                                       cache: &cache, cachedCompleteLines: &cachedCompleteLines)
        #expect(cache["a"] != nil)

        cache = [:]
        cachedCompleteLines = 0
        let second = "b = Row(\"two\")"
        let els = GenParser.parseIncremental(prefix: second[...], isComplete: true,
                                             cache: &cache, cachedCompleteLines: &cachedCompleteLines)
        #expect(els["a"] == nil)
        #expect(els["b"]?.comp == "Row")
    }
}
