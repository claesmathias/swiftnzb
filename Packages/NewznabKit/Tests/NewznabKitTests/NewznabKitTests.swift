import Testing
import Foundation
@testable import NewznabKit

@Suite("Request building")
struct RequestTests {
    @Test func appendsAPIPath() throws {
        let base = try #require(NewznabRequest.baseURL(from: "https://api.nzbgeek.info"))
        let url = try NewznabRequest.search(base: base, apiKey: "KEY", query: "big buck bunny", categoryID: 2000)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "api.nzbgeek.info")
        #expect(components.path == "/api")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["t"] == "search")
        #expect(query["q"] == "big buck bunny")
        #expect(query["cat"] == "2000")
        #expect(query["apikey"] == "KEY")
    }

    @Test func keepsExistingAPIPathAndSubpath() throws {
        let direct = try #require(NewznabRequest.baseURL(from: "https://example.org/api/"))
        #expect(try NewznabRequest.search(base: direct, apiKey: "k", query: nil).path() == "/api")
        let prowlarr = try #require(NewznabRequest.baseURL(from: "https://prowlarr.example.org/1/"))
        #expect(try NewznabRequest.search(base: prowlarr, apiKey: "k", query: nil).path() == "/1/api")
    }

    @Test func addsHTTPSWhenSchemeMissing() throws {
        let url = try #require(NewznabRequest.baseURL(from: "  api.nzbgeek.info "))
        #expect(url.absoluteString == "https://api.nzbgeek.info")
    }

    @Test func refusesPlainHTTP() throws {
        #expect(NewznabRequest.baseURL(from: "http://api.nzbgeek.info") == nil)
        let http = try #require(URL(string: "http://api.nzbgeek.info"))
        #expect(throws: NewznabError.insecureOrInvalidURL) {
            try NewznabRequest.search(base: http, apiKey: "k", query: "x")
        }
    }

    @Test func encodesPlusInQuery() throws {
        let base = try #require(NewznabRequest.baseURL(from: "https://example.org"))
        let url = try NewznabRequest.search(base: base, apiKey: "k", query: "c++")
        #expect(url.absoluteString.contains("q=c%2B%2B"))
    }

    @Test func emptyQueryOmitsQ() throws {
        let base = try #require(NewznabRequest.baseURL(from: "https://example.org"))
        let url = try NewznabRequest.search(base: base, apiKey: "k", query: "", limit: 1)
        #expect(!url.absoluteString.contains("q="))
        #expect(url.absoluteString.contains("limit=1"))
    }
}

@Suite("Search response parsing")
struct ParserTests {
    static let rss = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:newznab="http://www.newznab.com/DTD/2010/feeds/attributes/">
      <channel>
        <title>example</title>
        <item>
          <title>Big.Buck.Bunny.2008.1080p</title>
          <guid isPermaLink="true">https://example.org/details/abc123</guid>
          <link>https://example.org/api?t=get&amp;id=abc123&amp;apikey=KEY</link>
          <pubDate>Tue, 04 Nov 2025 10:15:00 +0000</pubDate>
          <category>Movies &gt; HD</category>
          <enclosure url="https://example.org/getnzb/abc123.nzb&amp;i=1&amp;r=KEY" length="999" type="application/x-nzb"/>
          <newznab:attr name="category" value="2000"/>
          <newznab:attr name="category" value="2040"/>
          <newznab:attr name="size" value="2254857830"/>
          <newznab:attr name="grabs" value="388"/>
        </item>
        <item>
          <title><![CDATA[ubuntu-24.04.1-desktop-amd64]]></title>
          <guid>def456</guid>
          <link>https://example.org/api?t=get&amp;id=def456&amp;apikey=KEY</link>
          <pubDate>Wed, 05 Nov 2025 08:00:00 +0100</pubDate>
          <newznab:attr name="category" value="4000"/>
        </item>
      </channel>
    </rss>
    """

    @Test func parsesItems() throws {
        let items = try NewznabParser.parseSearch(Data(Self.rss.utf8))
        #expect(items.count == 2)

        let first = items[0]
        #expect(first.title == "Big.Buck.Bunny.2008.1080p")
        #expect(first.guid == "https://example.org/details/abc123")
        #expect(first.nzbURL.absoluteString == "https://example.org/getnzb/abc123.nzb&i=1&r=KEY")
        #expect(first.sizeBytes == 2_254_857_830)
        #expect(first.categoryIDs == [2000, 2040])
        #expect(first.grabs == 388)
        #expect(first.publishedAt == Date(timeIntervalSince1970: 1_762_251_300))

        let second = items[1]
        #expect(second.title == "ubuntu-24.04.1-desktop-amd64")
        // No enclosure: falls back to <link>; no size attr and no enclosure length: unknown.
        #expect(second.nzbURL.absoluteString == "https://example.org/api?t=get&id=def456&apikey=KEY")
        #expect(second.sizeBytes == nil)
        #expect(second.grabs == nil)
        #expect(second.publishedAt == Date(timeIntervalSince1970: 1_762_326_000))
    }

    @Test func emptyChannelIsNoResults() throws {
        let xml = #"<?xml version="1.0"?><rss version="2.0"><channel><title>x</title></channel></rss>"#
        #expect(try NewznabParser.parseSearch(Data(xml.utf8)).isEmpty)
    }

    @Test func apiErrorIsThrown() {
        let xml = #"<?xml version="1.0" encoding="UTF-8"?><error code="100" description="Incorrect user credentials"/>"#
        #expect(throws: NewznabError.api(code: 100, description: "Incorrect user credentials")) {
            try NewznabParser.parseSearch(Data(xml.utf8))
        }
        #expect(NewznabError.api(code: 100, description: "").errorDescription == "The indexer rejected the API key.")
    }

    @Test func htmlIsUnexpected() {
        let html = "<html><body>Login</body></html>"
        #expect(throws: NewznabError.unexpectedResponse) {
            try NewznabParser.parseSearch(Data(html.utf8))
        }
    }
}

@Suite("NZB download validation")
struct ValidationTests {
    @Test func recognisesNZB() {
        let nzb = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE nzb PUBLIC "-//newzBin//DTD NZB 1.1//EN" "http://www.newzbin.com/DTD/nzb/nzb-1.1.dtd">
        <nzb xmlns="http://www.newzbin.com/DTD/2003/nzb"><file subject="x"/></nzb>
        """
        #expect(NZBValidation.looksLikeNZB(Data(nzb.utf8)))
    }

    @Test func rejectsErrorAndHTML() {
        let error = #"<error code="429" description="Request limit reached"/>"#
        #expect(!NZBValidation.looksLikeNZB(Data(error.utf8)))
        #expect(NewznabParser.apiError(in: Data(error.utf8)) == .api(code: 429, description: "Request limit reached"))
        #expect(!NZBValidation.looksLikeNZB(Data("<html>nope</html>".utf8)))
    }

    @Test func readsContentDispositionFilename() {
        #expect(NZBValidation.filename(fromContentDisposition: #"attachment; filename="Sintel.2010.nzb""#) == "Sintel.2010.nzb")
        #expect(NZBValidation.filename(fromContentDisposition: "attachment; filename=plain.nzb") == "plain.nzb")
        #expect(NZBValidation.filename(fromContentDisposition: "inline") == nil)
        #expect(NZBValidation.filename(fromContentDisposition: nil) == nil)
    }
}
