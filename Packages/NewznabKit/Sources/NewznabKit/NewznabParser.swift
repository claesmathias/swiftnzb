//
//  NewznabParser.swift
//  NewznabKit
//
//  Parses a Newznab search response: an RSS 2.0 document whose `<item>`s carry extra fields as
//  `<newznab:attr name="…" value="…"/>`, or a bare `<error code="…" description="…"/>`.
//

import Foundation

public enum NewznabParser {
    public static func parseSearch(_ data: Data) throws -> [NewznabItem] {
        let delegate = SearchDelegate()
        let parser = XMLParser(data: data)
        // Keep prefixed names ("newznab:attr") rather than resolving namespaces: some indexers
        // omit the xmlns declaration, which would make a namespace-aware parse fail.
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        let ok = parser.parse()

        if let error = delegate.apiError { throw error }
        guard ok || !delegate.items.isEmpty, delegate.sawRSS else {
            throw NewznabError.unexpectedResponse
        }
        return delegate.items
    }

    /// The `<error>` a Newznab endpoint sends instead of content, if `data` is one.
    public static func apiError(in data: Data) -> NewznabError? {
        let delegate = SearchDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.apiError
    }

    /// RFC 822 dates as used in RSS `<pubDate>`, with and without the weekday.
    static func date(from text: String) -> Date? {
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

private final class SearchDelegate: NSObject, XMLParserDelegate {
    var items: [NewznabItem] = []
    var apiError: NewznabError?
    var sawRSS = false

    private var inItem = false
    private var text = ""
    private var title = ""
    private var guid = ""
    private var link = ""
    private var enclosureURL: String?
    private var enclosureLength: Int?
    private var pubDate = ""
    private var attrs: [(name: String, value: String)] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        text = ""
        switch elementName {
        case "rss", "channel":
            sawRSS = true
        case "error":
            let code = Int(attributes["code"] ?? "") ?? 0
            apiError = .api(code: code, description: attributes["description"] ?? "")
            parser.abortParsing()
        case "item":
            inItem = true
            title = ""; guid = ""; link = ""; pubDate = ""
            enclosureURL = nil; enclosureLength = nil; attrs = []
        case "enclosure" where inItem:
            enclosureURL = attributes["url"]
            enclosureLength = Int(attributes["length"] ?? "")
        case "newznab:attr", "attr" where inItem:
            if let name = attributes["name"], let value = attributes["value"] {
                attrs.append((name.lowercased(), value))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        guard inItem else { return }
        switch elementName {
        case "title": title = value
        case "guid": guid = value
        case "link": link = value
        case "pubDate": pubDate = value
        case "item":
            inItem = false
            finishItem()
        default: break
        }
    }

    private func finishItem() {
        guard let url = URL(string: enclosureURL ?? link) ?? URL(string: link), !title.isEmpty else { return }
        func attr(_ name: String) -> String? { attrs.first { $0.name == name }?.value }
        let categories = attrs.filter { $0.name == "category" }.compactMap { Int($0.value) }
        let published = NewznabParser.date(from: pubDate) ?? attr("usenetdate").flatMap(NewznabParser.date)
        items.append(NewznabItem(
            guid: guid.isEmpty ? url.absoluteString : guid,
            title: title,
            nzbURL: url,
            publishedAt: published,
            sizeBytes: attr("size").flatMap(Int.init) ?? enclosureLength,
            categoryIDs: categories,
            grabs: attr("grabs").flatMap(Int.init)))
    }
}
