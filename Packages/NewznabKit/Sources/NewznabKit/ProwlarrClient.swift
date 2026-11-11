//
//  ProwlarrClient.swift
//  NewznabKit
//
//  Prowlarr's own API (v1), which searches every indexer configured in Prowlarr in one request.
//  Prowlarr also exposes a Newznab feed per indexer at /{id}/api; this client is the aggregated
//  alternative. Authentication is the Prowlarr API key in the X-Api-Key header.
//

import Foundation

/// One result of `GET /api/v1/search` (Prowlarr's `ReleaseResource`, the fields SwiftNZB uses).
public struct ProwlarrRelease: Decodable, Hashable, Sendable {
    public struct Category: Decodable, Hashable, Sendable {
        public var id: Int
    }

    public var guid: String?
    public var title: String?
    public var size: Int64?
    public var publishDate: Date?
    /// Prowlarr's own proxied download link, e.g. `{base}/{indexerId}/download?apikey=…&link=…`.
    public var downloadUrl: String?
    public var indexerId: Int?
    /// Name of the Prowlarr indexer the release came from.
    public var indexer: String?
    public var categories: [Category]?
    public var grabs: Int?
    /// "usenet", "torrent" or "unknown".
    public var `protocol`: String?

    /// The Newznab category numbers (Prowlarr also lists its own custom ids, 100000 and up).
    public var newznabCategoryIDs: [Int] {
        (categories ?? []).map(\.id).filter { (1000..<10000).contains($0) }
    }

    public var isUsenet: Bool { `protocol`?.lowercased() == "usenet" }
}

/// One entry of `GET /api/v1/indexer` (the fields SwiftNZB uses).
public struct ProwlarrIndexer: Decodable, Hashable, Sendable {
    public var id: Int
    public var name: String?
    public var enable: Bool?
    public var `protocol`: String?
}

public struct ProwlarrClient: Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var headers: [String: String]
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, headers: [String: String] = [:], session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.session = session
    }

    /// Searches every Prowlarr indexer and keeps only Usenet releases with a download link.
    public func search(query: String, categoryID: Int? = nil,
                       limit: Int = NewznabRequest.defaultLimit) async throws -> [ProwlarrRelease] {
        var items = [URLQueryItem(name: "query", value: query),
                     URLQueryItem(name: "type", value: "search"),
                     URLQueryItem(name: "limit", value: String(limit))]
        if let categoryID { items.append(URLQueryItem(name: "categories", value: String(categoryID))) }
        let data = try await get(Self.apiURL(base: baseURL, path: "api/v1/search", queryItems: items),
                                 timeout: 90)
        let releases = try Self.decodeReleases(data)
        return releases.filter { $0.isUsenet && $0.downloadUrl?.isEmpty == false && $0.title?.isEmpty == false }
    }

    /// The configured indexers; a cheap way to check the address, API key and proxy headers.
    public func indexers() async throws -> [ProwlarrIndexer] {
        let data = try await get(Self.apiURL(base: baseURL, path: "api/v1/indexer", queryItems: []), timeout: 30)
        do {
            return try JSONDecoder().decode([ProwlarrIndexer].self, from: data)
        } catch {
            throw NewznabParser.isHTML(data) ? NewznabError.webPage
                : NewznabError.unexpectedResponse(excerpt: NewznabParser.excerpt(of: data))
        }
    }

    /// Fetches the .nzb behind a release's `downloadUrl`, through the same guarded client as the
    /// Newznab path (same-host redirects only, NZB validation), with the key also as a header.
    public func fetchNZB(from url: URL) async throws -> (data: Data, filename: String?) {
        var withKey = headers
        withKey["X-Api-Key"] = apiKey
        return try await NewznabClient(baseURL: baseURL, apiKey: apiKey, headers: withKey, session: session)
            .fetchNZB(from: url)
    }

    // MARK: - Internals

    static func apiURL(base: URL, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard base.scheme?.lowercased() == "https",
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw NewznabError.insecureOrInvalidURL
        }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + "/" + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw NewznabError.insecureOrInvalidURL }
        return url
    }

    static func decodeReleases(_ data: Data) throws -> [ProwlarrRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseISO8601(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unparseable date \(text)"))
            }
            return date
        }
        do {
            return try decoder.decode([ProwlarrRelease].self, from: data)
        } catch {
            throw NewznabParser.isHTML(data) ? NewznabError.webPage
                : NewznabError.unexpectedResponse(excerpt: NewznabParser.excerpt(of: data))
        }
    }

    static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func get(_ url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("SwiftNZB", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await session.data(for: request, delegate: SameHostRedirects())
        if let http = response as? HTTPURLResponse { try NewznabClient.checkStatus(http, body: data) }
        return data
    }
}
