import Foundation
import Testing
@testable import Casberi

/// **Post on X opens X's composer within its limit** (`Model/XPostIntent.swift`,
/// prd §1299): the words and the link travel as X's own intent link, a long
/// title is cut at a word so the composer never opens over 280, and nothing
/// to say is no link at all.
struct XPostIntentTests {
    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func carriesTheWordsAndTheLink() {
        let link = URL(string: "https://example.com/a?b=1")!
        let url = XPostIntent.url(words: "Trip plan: Lisbon", link: link)
        #expect(url?.host == "x.com")
        #expect(url?.path == "/intent/post")
        #expect(query(url)["text"] == "Trip plan: Lisbon")
        #expect(query(url)["url"] == "https://example.com/a?b=1")
    }

    @Test func aLongTitleIsCutAtAWordWithinTheLimit() {
        let words = Array(repeating: "word", count: 80).joined(separator: " ")   // 399 characters
        let link = URL(string: "https://example.com")!
        let text = XPostIntent.text(words, link: link)
        #expect(text.count + XPostIntent.linkWeight + 1 <= XPostIntent.limit)
        #expect(text.hasSuffix("…"))
        #expect(!text.dropLast().hasSuffix(" "))
        #expect(text.dropLast().hasSuffix("word"))
    }

    @Test func withoutALinkTheWordsHaveTheWholeLimit() {
        let words = String(repeating: "a", count: 280)
        #expect(XPostIntent.text(words, link: nil) == words)
    }

    /// The X app's own scheme, which the app claims every time: one field,
    /// the words then the link.
    @Test func theAppLinkCarriesTheWordsThenTheLink() {
        let link = URL(string: "https://example.com/a?b=1&c=2")!
        let url = XPostIntent.appURL(words: "Trip plan: Lisbon", link: link)
        #expect(url?.scheme == "twitter")
        #expect(url?.host == "post")
        #expect(query(url)["message"] == "Trip plan: Lisbon https://example.com/a?b=1&c=2")
        #expect(XPostIntent.appURL(words: " ", link: nil) == nil)
    }

    /// A bare `+` in a query reads as a space, so it travels encoded.
    @Test func aPlusTravelsEncoded() {
        let url = XPostIntent.url(words: "C++ & Swift", link: URL(string: "https://example.com/?q=a+b"))
        #expect(url?.query(percentEncoded: true)?.contains("+") == false)
        #expect(query(url)["text"] == "C++ & Swift")
        #expect(query(url)["url"] == "https://example.com/?q=a+b")
        #expect(XPostIntent.appURL(words: "C++", link: nil)?.query(percentEncoded: true)?.contains("+") == false)
    }

    @Test func nothingToSayIsNoLink() {
        #expect(XPostIntent.url(words: "  ", link: nil) == nil)
        #expect(query(XPostIntent.url(words: "", link: URL(string: "https://example.com"))).keys.sorted() == ["url"])
    }
}
