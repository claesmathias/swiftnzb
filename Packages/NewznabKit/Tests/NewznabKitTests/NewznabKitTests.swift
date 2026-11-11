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

@Suite("Custom headers")
struct HeaderTests {
    @Test func validatesNames() {
        #expect(NewznabRequest.isValidHeaderName("User-Agent"))
        #expect(NewznabRequest.isValidHeaderName("X-Api-Token"))
        #expect(!NewznabRequest.isValidHeaderName(""))
        #expect(!NewznabRequest.isValidHeaderName("Bad Name"))
        #expect(!NewznabRequest.isValidHeaderName("Colon:"))
        #expect(!NewznabRequest.isValidHeaderName("Ümlaut"))
    }

    @Test func validatesValues() {
        #expect(NewznabRequest.isValidHeaderValue("Bearer abc.def"))
        #expect(!NewznabRequest.isValidHeaderValue("evil\r\nX-Injected: 1"))
    }

    @Test func parsesPastedHeaderLines() {
        let pasted = """
        CF-Access-Client-Id: example-id.access
        CF-Access-Client-Secret: cfast_abc
        -H "Authorization: Bearer a:b:c"
        not a header
        Bad Name: x
        """
        let parsed = NewznabRequest.parseHeaderLines(pasted)
        #expect(parsed.map(\.name) == ["CF-Access-Client-Id", "CF-Access-Client-Secret", "Authorization"])
        #expect(parsed.map(\.value) == ["example-id.access", "cfast_abc", "Bearer a:b:c"])
    }

    @Test func buildsBasicAuthorization() {
        #expect(NewznabRequest.basicAuthorization(username: "Aladdin", password: "open sesame")
                == "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
    }

    @Test func customHeadersAreSentAndOverrideDefaults() throws {
        let base = try #require(URL(string: "https://example.org"))
        let client = NewznabClient(baseURL: base, apiKey: "k",
                                   headers: ["User-Agent": "Custom/1.0", "X-Token": "secret"])
        let request = client.request(base)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Custom/1.0")
        #expect(request.value(forHTTPHeaderField: "X-Token") == "secret")
    }

    @Test func defaultUserAgentWithoutCustomHeaders() throws {
        let base = try #require(URL(string: "https://example.org"))
        let request = NewznabClient(baseURL: base, apiKey: "k").request(base)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "SwiftNZB")
    }
}

@Suite("Redirects and status codes")
struct StatusTests {
    @Test func sameHostHTTPSRedirectIsFollowed() throws {
        let from = try #require(URL(string: "https://prowlarr.example.com/1/api?t=search"))
        #expect(SameHostRedirects.allows(from: from, to: try #require(URL(string: "https://prowlarr.example.com/1/api/"))))
        #expect(!SameHostRedirects.allows(from: from, to: try #require(URL(string: "http://prowlarr.example.com/login"))))
        #expect(!SameHostRedirects.allows(from: from, to: try #require(URL(string: "https://evil.example.net/"))))
    }

    /// Prowlarr's /{id}/download redirecting to the source indexer (its "Redirect" option).
    @Test func downloadRedirectToIndexerDropsCredentials() throws {
        let from = try #require(URL(string: "https://prowlarr.example.com/3/download?apikey=K&link=abc"))
        let geek = try #require(URL(string: "https://api.nzbgeek.info/api?t=get&id=abc&apikey=GEEK"))
        #expect(SameHostRedirects.decision(from: from, to: geek, followForeignRedirects: true) == .followWithoutCredentials)
        #expect(SameHostRedirects.decision(from: from, to: geek, followForeignRedirects: false) == .refuse)
        let http = try #require(URL(string: "http://api.nzbgeek.info/api?t=get"))
        #expect(SameHostRedirects.decision(from: from, to: http, followForeignRedirects: true) == .refuse)
        let login = try #require(URL(string: "https://team.cloudflareaccess.com/cdn-cgi/access/login/x"))
        #expect(SameHostRedirects.decision(from: from, to: login, followForeignRedirects: true) == .refuse)
    }

    /// What a Cloudflare Access–protected Prowlarr sends without a valid service token.
    @Test func cloudflareAccessLoginRedirect() throws {
        let target = URL(string: "https://example-team.cloudflareaccess.com/cdn-cgi/access/login/prowlarr.example.com?kid=0000")
        #expect(NewznabClient.redirectError(to: target) == .cloudflareAccess)
        #expect(NewznabClient.redirectError(to: URL(string: "https://other.example.org/x")) == .redirected(host: "other.example.org"))
    }

    @Test func statusMapping() throws {
        let url = try #require(URL(string: "https://prowlarr.example.com/1/api"))
        func response(_ status: Int, location: String? = nil) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                         headerFields: location.map { ["Location": $0] }))
        }
        #expect(throws: NewznabError.unauthorized(status: 401)) { try NewznabClient.checkStatus(try response(401), body: Data()) }
        #expect(throws: NewznabError.http(status: 500)) { try NewznabClient.checkStatus(try response(500), body: Data()) }
        #expect(throws: NewznabError.cloudflareAccess) {
            try NewznabClient.checkStatus(try response(302, location: "https://team.cloudflareaccess.com/cdn-cgi/access/login/x"), body: Data())
        }
        try NewznabClient.checkStatus(try response(200), body: Data())
    }
}

@Suite("Prowlarr API")
struct ProwlarrTests {
    static let json = """
    [
      {"guid": "https://api.nzbgeek.info/details/abc", "title": "Sintel.2010.1080p.BluRay.x264",
       "size": 2254857830, "publishDate": "2025-11-04T10:15:00Z", "indexerId": 3, "indexer": "NZBgeek",
       "downloadUrl": "http://prowlarr.example.com/3/download?apikey=KEY&link=abc&file=Sintel",
       "categories": [{"id": 2000, "name": "Movies"}, {"id": 2040, "name": "Movies/HD"}, {"id": 102040, "name": "HD"}],
       "grabs": 388, "protocol": "usenet"},
      {"guid": "magnet:?xt=urn:btih:xyz", "title": "Sintel torrent", "size": 1, "indexerId": 5,
       "indexer": "SomeTracker", "downloadUrl": "https://prowlarr.example.com/5/download?x",
       "publishDate": "2025-11-04T10:15:00.123Z", "protocol": "torrent"}
    ]
    """

    @Test func decodesReleases() throws {
        let releases = try ProwlarrClient.decodeReleases(Data(Self.json.utf8))
        #expect(releases.count == 2)
        let first = releases[0]
        #expect(first.isUsenet)
        #expect(first.indexer == "NZBgeek")
        #expect(first.size == 2_254_857_830)
        #expect(first.grabs == 388)
        #expect(first.newznabCategoryIDs == [2000, 2040])
        #expect(first.publishDate == Date(timeIntervalSince1970: 1_762_251_300))
        #expect(!releases[1].isUsenet)
        #expect(releases[1].publishDate != nil)  // fractional seconds
    }

    @Test func buildsSearchURL() throws {
        let base = try #require(URL(string: "https://prowlarr.example.com/"))
        let url = try ProwlarrClient.apiURL(base: base, path: "api/v1/search",
                                            queryItems: [URLQueryItem(name: "query", value: "a+b")])
        #expect(url.absoluteString == "https://prowlarr.example.com/api/v1/search?query=a%2Bb")
        let sub = try #require(URL(string: "https://example.com/prowlarr"))
        #expect(try ProwlarrClient.apiURL(base: sub, path: "api/v1/indexer", queryItems: []).absoluteString
                == "https://example.com/prowlarr/api/v1/indexer")
    }

    @Test func refusesHTTPBase() throws {
        let http = try #require(URL(string: "http://prowlarr.example.com"))
        #expect(throws: NewznabError.insecureOrInvalidURL) {
            try ProwlarrClient.apiURL(base: http, path: "api/v1/indexer", queryItems: [])
        }
    }

    @Test func htmlInsteadOfJSONIsWebPage() {
        #expect(throws: NewznabError.webPage) {
            try ProwlarrClient.decodeReleases(Data("<!DOCTYPE html><html></html>".utf8))
        }
    }

    /// Prowlarr behind a TLS proxy builds http:// download links on its own host.
    @Test func upgradesSameHostHTTPLinks() throws {
        let base = try #require(URL(string: "https://prowlarr.example.com"))
        let link = try #require(URL(string: "http://prowlarr.example.com/3/download?apikey=K&link=abc"))
        #expect(NewznabClient.secured(link, base: base)?.absoluteString
                == "https://prowlarr.example.com/3/download?apikey=K&link=abc")
        let other = try #require(URL(string: "http://elsewhere.example.net/get"))
        #expect(NewznabClient.secured(other, base: base) == nil)
        let https = try #require(URL(string: "https://cdn.example.net/x.nzb"))
        #expect(NewznabClient.secured(https, base: base) == https)
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

    /// Captured from api.nzbgeek.info with a made-up key (served as HTTP 200).
    @Test func nzbGeekInvalidKey() {
        let xml = #"<error code="101" description="Invalid API Key"/>"#
        #expect(throws: NewznabError.api(code: 101, description: "Invalid API Key")) {
            try NewznabParser.parseSearch(Data(xml.utf8))
        }
        #expect(NewznabError.api(code: 101, description: "Invalid API Key").errorDescription
                == "The indexer said: Invalid API Key")
    }

    /// What https://nzbgeek.info/api (the website, not api.nzbgeek.info) sends: its login page.
    @Test func websiteLoginPageIsWebPage() {
        let html = """


        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
        <html xml:lang="en" lang="en" xmlns="http://www.w3.org/1999/xhtml"><head><title>Geek - Logon</title></head></html>
        """
        #expect(throws: NewznabError.webPage) {
            try NewznabParser.parseSearch(Data(html.utf8))
        }
    }

    /// What a Newznab-type entry gets when pointed at Prowlarr's root: its management API.
    @Test func prowlarrRootIsRecognised() {
        let json = #"{"current":"v1","deprecated":[]}"#
        #expect(throws: NewznabError.prowlarrRoot) { try NewznabParser.parseSearch(Data(json.utf8)) }
    }

    @Test func otherXMLIsUnexpectedWithExcerpt() throws {
        let xml = #"<caps><server title="NZBgeek"/></caps>"#
        do {
            _ = try NewznabParser.parseSearch(Data(xml.utf8))
            Issue.record("expected an error")
        } catch let error as NewznabError {
            #expect(error == .unexpectedResponse(excerpt: xml))
            #expect(error.errorDescription?.contains("It began with: <caps>") == true)
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
