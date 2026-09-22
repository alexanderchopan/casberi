import Foundation
import Testing
@testable import Casberi

/// The four rules §879 changed, pinned where they can go wrong silently.
///
/// Each of these compiles, renders and looks fine when wrong: a picture
/// address left HTML-escaped 404s into a glyph, a share titled with its bare
/// host is never renamed, and a cover gate that reads the wrong window either
/// lies about recency or goes missing on the opens with the most news.
struct FeedFaceTests {

    // MARK: - ProductMeta: the page's picture

    @Test func relativePictureResolvesAgainstThePage() {
        let html = #"<html><head><title>A</title><meta property="og:image" content="/img/cover.jpg"></head></html>"#
        let meta = ProductMeta.parse(html, base: URL(string: "https://example.com/post/1"))
        #expect(meta?.image == "https://example.com/img/cover.jpg")
    }

    @Test func relativePictureWithNoBaseIsDropped() {
        let html = #"<html><head><title>A</title><meta property="og:image" content="/img/cover.jpg"></head></html>"#
        #expect(ProductMeta.parse(html)?.image == nil)
    }

    @Test func escapedAmpersandInPictureIsDecoded() {
        let html = #"<html><head><title>A</title><meta property="og:image" content="https://cdn.example.com/i.jpg?w=1200&amp;h=630"></head></html>"#
        #expect(ProductMeta.parse(html)?.image == "https://cdn.example.com/i.jpg?w=1200&h=630")
    }

    @Test func twitterImageIsTheFallback() {
        let html = #"<html><head><title>A</title><meta name="twitter:image" content="https://cdn.example.com/t.jpg"></head></html>"#
        #expect(ProductMeta.parse(html)?.image == "https://cdn.example.com/t.jpg")
    }

    @Test func ogImageBeatsTwitterImageWhateverTheOrder() {
        let html = #"<html><head><title>A</title><meta name="twitter:image" content="https://cdn.example.com/t.jpg"><meta property="og:image" content="https://cdn.example.com/og.jpg"></head></html>"#
        #expect(ProductMeta.parse(html)?.image == "https://cdn.example.com/og.jpg")
    }

    // MARK: - LinkTitle: what still counts as unnamed

    private static func link(title: String, url: String) -> Thing {
        Thing(kind: .link, title: title, content: url, source: "You")
    }

    @Test func bareHostTitleIsUnnamed() {
        let url = URL(string: "https://www.nytimes.com/2026/09/22/story.html")!
        #expect(LinkTitle.looksUnnamed(Self.link(title: "nytimes.com", url: url.absoluteString), url: url))
    }

    @Test func urlTitleIsUnnamed() {
        let raw = "https://example.com/a"
        #expect(LinkTitle.looksUnnamed(Self.link(title: raw, url: raw), url: URL(string: raw)!))
    }

    @Test func realTitleIsNamed() {
        let url = URL(string: "https://www.nytimes.com/story")!
        #expect(!LinkTitle.looksUnnamed(Self.link(title: "The story", url: url.absoluteString), url: url))
    }

    // MARK: - The All feed's cover

    @Test func coverWithinADayIsFresh() {
        let now = Date.now
        #expect(FeedScreen.isCoverFresh(now.addingTimeInterval(-3600), away: nil, now: now))
    }

    @Test func oldCoverWithNoAwayWindowIsStale() {
        let now = Date.now
        #expect(!FeedScreen.isCoverFresh(now.addingTimeInterval(-30 * 3600), away: nil, now: now))
    }

    @Test func oldCoverThatLandedWhileYouWereAwayIsFresh() {
        let now = Date.now
        let away = now.addingTimeInterval(-72 * 3600)..<now
        #expect(FeedScreen.isCoverFresh(now.addingTimeInterval(-40 * 3600), away: away, now: now))
    }

    @Test func oldCoverFromBeforeYouLeftIsStale() {
        // §389's case: a quiet week, nothing new — the top row is old news.
        let now = Date.now
        let away = now.addingTimeInterval(-30 * 3600)..<now
        #expect(!FeedScreen.isCoverFresh(now.addingTimeInterval(-40 * 3600), away: away, now: now))
    }
}
