import Testing
@testable import Casberi

/// **No word alone on a paragraph's last line** (`Design/DSProse.swift`).
/// The binding is invisible when it works and invisible when it silently
/// stops, so the rule is pinned here: which pairs bind, and which are left
/// alone because binding them would do harm.
struct DSProseTests {
    private let nbsp = "\u{00A0}"

    @Test func bindsTheLastTwoWords() {
        #expect(DSProse.unorphaned("Disconnect deletes everything it brought in.")
                == "Disconnect deletes everything it brought\(nbsp)in.")
    }

    @Test func leavesShortLinesAlone() {
        // Three words never wrap into an orphan worth binding.
        #expect(DSProse.unorphaned("Read access enough") == "Read access enough")
        #expect(DSProse.unorphaned("Nothing yet") == "Nothing yet")
        #expect(DSProse.unorphaned("") == "")
    }

    @Test func leavesALongPairAlone() {
        // A pair wider than a line would be forced to break mid-word.
        let s = "Open it at https://dashboard.example.com/settings/keys"
        #expect(DSProse.unorphaned(s) == s)
    }

    @Test func bindsEachParagraph() {
        let s = "One two three four.\n\nFive six seven eight."
        #expect(DSProse.unorphaned(s)
                == "One two three\(nbsp)four.\n\nFive six seven\(nbsp)eight.")
    }

    @Test func leavesTrailingSpaceAlone() {
        #expect(DSProse.unorphaned("One two three four ") == "One two three four ")
    }
}
